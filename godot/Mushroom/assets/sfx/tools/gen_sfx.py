#!/usr/bin/env python3
"""Procedural sound generator for Mushroom (Godot) -- standard library only.

Writes every synthesized sound to ../synth/<name>.ogg (via ffmpeg if it is on PATH)
or ../synth/<name>.wav otherwise. Run from anywhere:

    python gen_sfx.py            # all sounds
    python gen_sfx.py owl_hoot   # just the named ones

Deterministic: each sound seeds its own RNG from its name, so regenerating gives the same files.
Loops (amb_*, car_engine, hag_breath, flare_loop, police_siren, gurney) are built seamless.
Released as CC0 together with the generated sounds.
"""
import math
import os
import random
import shutil
import struct
import subprocess
import sys
import tempfile
import wave

SR = 22050
OUT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "synth"))
TAU = math.tau
rng = random.Random(0)


# ---------------------------------------------------------------- helpers

def n(sec):
    return int(sec * SR)


def zeros(sec):
    return [0.0] * n(sec)


def noise(count):
    return [rng.uniform(-1.0, 1.0) for _ in range(count)]


def mix(dst, src, at=0, gain=1.0, wrap=False):
    """Adds src into dst starting at sample `at`; wrap=True wraps around (for seamless loops)."""
    ln = len(dst)
    for i, v in enumerate(src):
        j = at + i
        if wrap:
            j %= ln
        elif j >= ln:
            break
        dst[j] += v * gain
    return dst


def scale(buf, g):
    return [v * g for v in buf]


def lowpass(buf, cutoff):
    """One-pole low-pass; cutoff may be a float or a per-sample list."""
    out = []
    y = 0.0
    var = isinstance(cutoff, list)
    a = 1.0 - math.exp(-TAU * (cutoff if not var else 1000.0) / SR)
    for i, x in enumerate(buf):
        if var:
            a = 1.0 - math.exp(-TAU * cutoff[i] / SR)
        y += a * (x - y)
        out.append(y)
    return out


def highpass(buf, cutoff):
    lp = lowpass(buf, cutoff)
    return [x - l for x, l in zip(buf, lp)]


def bandpass(buf, freq, q=4.0):
    """RBJ band-pass (constant peak gain); freq may be a float or a per-sample list."""
    out = []
    x1 = x2 = y1 = y2 = 0.0
    var = isinstance(freq, list)
    coef = None
    for i, x in enumerate(buf):
        if var or coef is None:
            f = min(max(freq[i] if var else freq, 20.0), SR * 0.45)
            w = TAU * f / SR
            alpha = math.sin(w) / (2.0 * q)
            a0 = 1.0 + alpha
            coef = (alpha / a0, -alpha / a0, -2.0 * math.cos(w) / a0, (1.0 - alpha) / a0)
        b0, b2, a1, a2 = coef
        y = b0 * x + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1 = x1, x
        y2, y1 = y1, y
        out.append(y)
    return out


def formants(src, f_list, qs=(6.0, 8.0, 10.0), gains=(1.0, 0.5, 0.25)):
    """Runs src through parallel band-passes. f_list: list of (per-sample list or float) per formant."""
    out = [0.0] * len(src)
    for f, q, g in zip(f_list, qs, gains):
        mix(out, bandpass(src, f, q), gain=g)
    return out


def env_adsr(count, a, d, s, r, sustain_level=0.7):
    out = []
    a_n, d_n, r_n = n(a), n(d), n(r)
    s_n = max(0, count - a_n - d_n - r_n)
    for i in range(count):
        if i < a_n:
            v = i / max(1, a_n)
        elif i < a_n + d_n:
            v = 1.0 - (1.0 - sustain_level) * (i - a_n) / max(1, d_n)
        elif i < a_n + d_n + s_n:
            v = sustain_level
        else:
            v = sustain_level * max(0.0, 1.0 - (i - a_n - d_n - s_n) / max(1, r_n))
        out.append(v)
    return out


def env_exp(count, decay, attack=0.002):
    a_n = max(1, n(attack))
    return [min(1.0, i / a_n) * math.exp(-i / (decay * SR)) for i in range(count)]


def apply(buf, env):
    return [b * e for b, e in zip(buf, env)]


def osc(freqs, shape="sine", phase=0.0):
    """Oscillator following a per-sample frequency list."""
    out = []
    ph = phase
    for f in freqs:
        ph = (ph + f / SR) % 1.0
        if shape == "sine":
            out.append(math.sin(TAU * ph))
        elif shape == "saw":
            out.append(2.0 * ph - 1.0)
        elif shape == "square":
            out.append(1.0 if ph < 0.5 else -1.0)
        elif shape == "tri":
            out.append(4.0 * abs(ph - 0.5) - 1.0)
    return out


def glide(count, points):
    """Piecewise-linear curve: points = [(t_sec, value), ...]."""
    out = []
    for i in range(count):
        t = i / SR
        if t <= points[0][0]:
            out.append(points[0][1])
            continue
        for (t0, v0), (t1, v1) in zip(points, points[1:]):
            if t0 <= t <= t1:
                out.append(v0 + (v1 - v0) * (t - t0) / max(1e-9, t1 - t0))
                break
        else:
            out.append(points[-1][1])
    return out


def vibrato(freqs, rate, depth, jitter=0.0):
    out = []
    j = 0.0
    for i, f in enumerate(freqs):
        j += (rng.uniform(-1, 1) - j) * 0.002
        out.append(f * (1.0 + depth * math.sin(TAU * rate * i / SR) + jitter * j))
    return out


def voice(freqs, breath=0.15, rasp=0.0):
    """Glottal-ish source: saw + aspiration noise, optional rasp (noise-modulated amplitude)."""
    s = osc(freqs, "saw")
    out = []
    r = 0.0
    for v in s:
        r += (rng.uniform(-1, 1) - r) * 0.3
        amp = 1.0 + rasp * r * 2.0
        out.append(v * amp + rng.uniform(-1, 1) * breath)
    return out


def drive(buf, amount):
    return [math.tanh(v * amount) for v in buf]


def reverb(buf, wet=0.3, size=1.0, tail=1.0):
    """Small Schroeder reverb; returns buf extended by `tail` seconds."""
    src = buf + [0.0] * n(tail)
    combs = [int(d * size) for d in (1116, 1188, 1277, 1356)]
    fb = 0.78
    wet_sig = [0.0] * len(src)
    for d in combs:
        d = max(1, d * SR // 44100)
        line = [0.0] * d
        idx = 0
        lp = 0.0
        for i, x in enumerate(src):
            y = line[idx]
            lp = y * 0.6 + lp * 0.4
            line[idx] = x + lp * fb
            idx = (idx + 1) % d
            wet_sig[i] += y * 0.25
    for d in (556, 441):
        d = d * SR // 44100
        line = [0.0] * d
        idx = 0
        out = []
        for x in wet_sig:
            b = line[idx]
            y = -x + b
            line[idx] = x + b * 0.5
            idx = (idx + 1) % d
            out.append(y)
        wet_sig = out
    return [s * (1.0 - wet) + w * wet for s, w in zip(src, wet_sig)]


def make_loop(buf, fade_sec):
    """buf has len N+F; crossfade the extra tail into the head so it loops seamlessly at N."""
    f = n(fade_sec)
    total = len(buf) - f
    out = buf[:total]
    for i in range(f):
        k = i / f
        out[i] = buf[i] * math.sin(k * math.pi / 2) + buf[total + i] * math.cos(k * math.pi / 2)
    return out


def fade(buf, fin=0.005, fout=0.02):
    a, b = n(fin), n(fout)
    out = list(buf)
    for i in range(min(a, len(out))):
        out[i] *= i / a
    for i in range(min(b, len(out))):
        out[-1 - i] *= i / b
    return out


def normalize(buf, peak=0.9):
    m = max(1e-9, max(abs(v) for v in buf))
    return [v * peak / m for v in buf]


def write(name, buf, peak=0.9, is_loop=False):
    if not is_loop:
        buf = fade(buf)
    buf = normalize(buf, peak)
    os.makedirs(OUT, exist_ok=True)
    data = b"".join(struct.pack("<h", int(max(-1.0, min(1.0, v)) * 32767)) for v in buf)
    ffmpeg = shutil.which("ffmpeg")
    if ffmpeg:
        tmp = os.path.join(tempfile.gettempdir(), "gen_sfx_" + name + ".wav")
        _write_wav(tmp, data)
        dst = os.path.join(OUT, name + ".ogg")
        subprocess.run([ffmpeg, "-y", "-loglevel", "error", "-i", tmp, "-c:a", "libvorbis", "-q:a", "3", dst],
                       check=True)
        os.remove(tmp)
    else:
        dst = os.path.join(OUT, name + ".wav")
        _write_wav(dst, data)
    print("wrote", dst, "%.2fs" % (len(buf) / SR))


def _write_wav(path, data):
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data)


# ---------------------------------------------------------------- building blocks

def chirp_bird(dur, f0, f1, wob=0.0):
    c = n(dur)
    fr = glide(c, [(0, f0), (dur, f1)])
    if wob:
        fr = [f * (1 + wob * math.sin(TAU * 35 * i / SR)) for i, f in enumerate(fr)]
    return apply(osc(fr), env_adsr(c, dur * 0.2, dur * 0.3, 0.6, dur * 0.4))


def bird_phrase():
    out = []
    kind = rng.randrange(3)
    base = rng.uniform(2500, 4800)
    for _ in range(rng.randint(2, 6)):
        if kind == 0:
            s = chirp_bird(rng.uniform(0.05, 0.1), base * 1.3, base * 0.8)
        elif kind == 1:
            s = chirp_bird(rng.uniform(0.08, 0.15), base * 0.8, base * 1.2, wob=0.05)
        else:
            s = chirp_bird(0.04, base, base * 1.05)
        out += s + [0.0] * n(rng.uniform(0.03, 0.12))
    return out


def wind(count, base_cut, lfo_cycles, depth=0.6):
    """Low-passed noise with slowly moving cutoff/level; lfo_cycles is an integer for seamless loops."""
    cut = [base_cut * (1.0 + 0.6 * math.sin(TAU * lfo_cycles * i / count)
                       + 0.3 * math.sin(TAU * (lfo_cycles * 3 + 1) * i / count)) for i in range(count)]
    w = lowpass(lowpass(noise(count), cut), [c * 1.5 for c in cut])
    lvl = [1.0 - depth * 0.5 * (1 + math.sin(TAU * lfo_cycles * i / count + 1.3)) for i in range(count)]
    return apply(w, lvl)


def cricket(count, freq, chirp_rate, pulses=3, level=1.0):
    """Cricket: bursts of a few short pulses at `freq`, repeating `chirp_rate` per second (wraps)."""
    out = [0.0] * count
    period = SR / chirp_rate
    pulse = apply(osc([freq] * n(0.012)), env_adsr(n(0.012), 0.002, 0.004, 0.5, 0.004))
    t = rng.uniform(0, period)
    while t < count:
        for p in range(pulses):
            mix(out, pulse, int(t) + p * n(0.02), level, wrap=True)
        t += period * rng.uniform(0.92, 1.08)
    return out


def thump(dur, f0, f1, decay):
    c = n(dur)
    return apply(osc(glide(c, [(0, f0), (dur, f1)])), env_exp(c, decay, 0.003))


def syllables(count, starts, length, attack=0.02):
    env = [0.0] * count
    for s in starts:
        seg = env_adsr(n(length), attack, length * 0.3, 0.6, length * 0.5)
        for i, v in enumerate(seg):
            j = n(s) + i
            if j < count:
                env[j] = max(env[j], v)
    return env


# ---------------------------------------------------------------- sounds

def s_throw():
    c = n(0.4)
    f = glide(c, [(0, 400), (0.15, 2200), (0.4, 500)])
    s = bandpass(noise(c), f, 2.0)
    write("throw", apply(s, env_adsr(c, 0.12, 0.1, 0.5, 0.18)), 0.8)


def s_eat():
    out = zeros(0.9)
    for k in range(4):
        t = 0.05 + k * 0.2 + rng.uniform(-0.02, 0.02)
        c = n(0.09)
        cr = apply(highpass(noise(c), 1500), env_exp(c, 0.025))
        mix(out, cr, n(t))
        mix(out, thump(0.08, 140, 90, 0.03), n(t), 0.6)
    write("eat", out)


def s_vomit():
    dur = 1.6
    c = n(dur)
    pitch = vibrato(glide(c, [(0, 160), (0.3, 120), (1.0, 95), (dur, 80)]), 9, 0.08, 0.5)
    src = voice(pitch, breath=0.5, rasp=0.8)
    f1 = glide(c, [(0, 400), (0.3, 750), (1.2, 650), (dur, 350)])
    f2 = glide(c, [(0, 1800), (0.3, 1150), (dur, 1000)])
    gurgle = [1.0 + 0.6 * math.sin(TAU * 13 * i / SR) for i in range(c)]
    v = apply(formants(src, [f1, f2]), apply(gurgle, env_adsr(c, 0.05, 0.2, 0.8, 0.5)))
    sp = apply(lowpass(noise(n(0.8)), 1200), env_exp(n(0.8), 0.25))
    mix(v, sp, n(0.7), 0.6)
    write("vomit", drive(v, 2.0))


def s_slot_spin():
    out = zeros(1.6)
    t = 0.0
    gap = 0.11
    while t < 1.5:
        c = n(0.02)
        click = apply([0.6 * math.sin(TAU * 1900 * i / SR) + 0.4 * rng.uniform(-1, 1) for i in range(c)],
                      env_exp(c, 0.006))
        mix(out, click, n(t))
        t += gap
        gap = max(0.045, gap * 0.9)
    write("slot_spin", out, 0.7)


def bell(freq, dur, decay):
    c = n(dur)
    s = [math.sin(TAU * freq * i / SR) + 0.4 * math.sin(TAU * freq * 2.76 * i / SR)
         + 0.2 * math.sin(TAU * freq * 5.4 * i / SR) for i in range(c)]
    return apply(s, env_exp(c, decay))


def s_slot_win():
    out = zeros(2.0)
    notes = [523.3, 659.3, 784.0, 1046.5, 784.0, 1046.5, 1318.5]
    for k, f in enumerate(notes):
        c = n(0.14)
        sq = apply(osc([f] * c, "square"), env_adsr(c, 0.005, 0.05, 0.5, 0.06))
        mix(out, lowpass(sq, 4000), n(k * 0.11), 0.35)
    for k in range(10):
        mix(out, bell(rng.choice([2093.0, 2637.0, 3136.0]), 0.4, 0.12), n(0.75 + k * 0.1), 0.3)
    write("slot_win", out, 0.8)


def s_slot_lose():
    out = zeros(2.6)
    for k, (f, d) in enumerate([(392.0, 0.35), (370.0, 0.35), (349.2, 0.35), (329.6, 1.2)]):
        c = n(d)
        fr = [f] * c if k < 3 else vibrato(glide(c, [(0, f), (d, f * 0.94)]), 6, 0.02)
        s = lowpass(osc(fr, "saw"), glide(c, [(0, 600), (0.1, 2200), (d, 900)]))
        mix(out, apply(s, env_adsr(c, 0.03, 0.05, 0.8, 0.12 if k < 3 else 0.5)), n(k * 0.42))
    write("slot_lose", out, 0.75)


def engine_pulse(freq, count, cyl_jitter=0.15):
    """Engine: firing pulses at `freq` Hz. count/freq should give whole pulses for loops."""
    out = [0.0] * count
    period = SR / freq
    k = 0
    while k * period < count:
        c = int(period * 1.6)
        amp = 1.0 + rng.uniform(-cyl_jitter, cyl_jitter)
        p = [amp * (math.sin(TAU * 55 * i / SR) * 0.8 + rng.uniform(-1, 1) * 0.5) * math.exp(-i / (period * 0.35))
             for i in range(c)]
        mix(out, p, int(k * period), wrap=True)
        k += 1
    return lowpass(lowpass(out, 500), 700)


def s_car_engine():
    count = n(1.0)
    e = engine_pulse(30.0, count)
    # run the filter over a doubled copy so the loop boundary is continuous
    e2 = lowpass(e + e, 900)[count:]
    rumble = wind(count, 120, 2, 0.2)
    mix(e2, rumble, 0, 0.15)
    write("car_engine", e2, 0.8, is_loop=True)


def s_car_start():
    out = zeros(2.6)
    for k in range(3):
        c = n(0.22)
        crank = osc([170 + 20 * math.sin(TAU * 9 * i / SR) for i in range(c)], "saw")
        mix(out, apply(lowpass(crank, 1200), env_adsr(c, 0.02, 0.05, 0.8, 0.08)), n(k * 0.25), 0.35)
    c = n(1.8)
    eng = engine_pulse(30.0, c)
    rev = []
    pos = 0.0
    speed = glide(c, [(0, 0.6), (0.3, 1.9), (0.9, 1.2), (1.8, 1.0)])
    for i in range(c):
        pos += speed[i]
        rev.append(eng[int(pos) % c])
    mix(out, apply(rev, env_adsr(c, 0.05, 0.3, 0.9, 0.3)), n(0.75), 1.0)
    write("car_start", out, 0.85)


def s_car_horn():
    c = n(0.7)
    s = [a + b for a, b in zip(osc([415.0] * c, "square"), osc([523.0] * c, "square"))]
    s = lowpass(bandpass(s, 900, 1.2), 2500)
    write("car_horn", apply(drive(s, 3.0), env_adsr(c, 0.01, 0.05, 0.9, 0.05)), 0.8)


def s_car_crash():
    out = zeros(2.0)
    c = n(0.5)
    mix(out, apply(lowpass(noise(c), 3000), env_exp(c, 0.12)))
    mix(out, thump(0.4, 90, 40, 0.12), 0, 1.2)
    for f in (233, 377, 611, 942, 1430):
        cm = n(1.2)
        mix(out, apply(osc([f * rng.uniform(0.97, 1.03)] * cm), env_exp(cm, rng.uniform(0.1, 0.35))), 0, 0.25)
    for _ in range(25):
        cg = n(0.08)
        ping = apply(osc([rng.uniform(3500, 7000)] * cg), env_exp(cg, 0.02))
        mix(out, ping, n(rng.uniform(0.05, 1.2)), rng.uniform(0.1, 0.3))
    write("car_crash", drive(out, 1.5), 0.9)


def s_whistle():
    c = n(0.9)
    fr = [2900 + 260 * math.sin(TAU * 32 * i / SR) for i in range(c)]
    s = [a + 0.25 * b for a, b in zip(osc(fr), bandpass(noise(c), 3000, 3))]
    write("whistle", apply(s, env_adsr(c, 0.02, 0.05, 0.85, 0.08)), 0.7)


def s_flare():
    out = zeros(2.5)
    c = n(0.06)
    mix(out, apply(noise(c), env_exp(c, 0.015)))
    c = n(2.4)
    hiss = highpass(noise(c), 1800)
    crackle = [rng.uniform(-1, 1) if rng.random() < 0.004 else 0.0 for _ in range(c)]
    s = [h * 0.4 + k for h, k in zip(hiss, crackle)]
    mix(out, apply(s, env_adsr(c, 0.15, 0.3, 0.7, 0.8)), n(0.05))
    write("flare", out, 0.7)


def s_flare_loop():
    count = n(3.0)
    f = n(0.3)
    hiss = highpass(noise(count + f), 1800)
    crackle = [rng.uniform(-1, 1) if rng.random() < 0.004 else 0.0 for _ in range(count + f)]
    write("flare_loop", make_loop([h * 0.4 + k for h, k in zip(hiss, crackle)], 0.3), 0.5, is_loop=True)


def s_scream():
    dur = 1.3
    c = n(dur)
    p = vibrato(glide(c, [(0, 500), (0.15, 880), (1.0, 820), (dur, 600)]), 7, 0.03, 1.0)
    src = voice(p, 0.3, 0.3)
    v = formants(src, [glide(c, [(0, 600), (0.2, 950), (dur, 850)]), 1500.0, 2800.0], (5, 7, 9), (1, 0.6, 0.3))
    write("scream", drive(apply(v, env_adsr(c, 0.04, 0.1, 0.9, 0.4)), 2.5), 0.85)


def s_hag_laugh():
    dur = 2.0
    c = n(dur)
    starts = [0.05 + k * 0.2 for k in range(8)]
    p = vibrato(glide(c, [(0, 330), (dur, 210)]), 11, 0.06, 1.5)
    src = voice(p, 0.6, 1.0)
    v = formants(src, [520.0, 1750.0, 2600.0], (5, 6, 8), (1, 0.6, 0.35))
    env = syllables(c, starts, 0.16, 0.01)
    write("hag_laugh", reverb(drive(apply(v, env), 2.0), 0.25, 1.0, 0.6), 0.85)


def s_hag_scream():
    dur = 2.0
    c = n(dur)
    p = vibrato(glide(c, [(0, 300), (0.3, 1100), (1.2, 950), (dur, 280)]), 17, 0.07, 3.0)
    src = voice(p, 1.0, 1.5)
    v = formants(src, [glide(c, [(0, 500), (0.3, 1000), (dur, 600)]), glide(c, [(0, 1200), (dur, 1600)]), 3100.0],
                 (3, 4, 5), (1, 0.7, 0.4))
    write("hag_scream", reverb(drive(apply(v, env_adsr(c, 0.05, 0.2, 0.85, 0.7)), 4.0), 0.3, 1.3, 0.8), 0.9)


def s_hag_whisper():
    dur = 2.4
    c = n(dur)
    starts = [0.05, 0.3, 0.5, 0.85, 1.05, 1.5, 1.7, 1.95]
    f1 = [450 + 250 * math.sin(TAU * 2.7 * i / SR) for i in range(c)]
    f2 = [1600 + 700 * math.sin(TAU * 3.9 * i / SR + 1) for i in range(c)]
    v = formants(noise(c), [f1, f2, 3200.0], (6, 7, 6), (0.6, 1.0, 0.6))
    s_hiss = apply(highpass(noise(c), 4500), syllables(c, [s + 0.12 for s in starts[::3]], 0.12))
    out = apply(v, syllables(c, starts, 0.22, 0.04))
    mix(out, s_hiss, 0, 0.3)
    write("hag_whisper", reverb(out, 0.3, 0.8, 0.5), 0.6)


def s_hag_breath():
    count = n(3.2)
    f = n(0.2)
    total = count + f
    env = [max(0.0, math.sin(TAU * 1 * i / count)) ** 2 * 1.0 + max(0.0, -math.sin(TAU * 1 * i / count)) ** 3 * 0.7
           for i in range(total)]
    fr = [700 + 300 * math.sin(TAU * i / count) for i in range(total)]
    b = bandpass(noise(total), fr, 1.5)
    rasp = [1.0 + 0.5 * math.sin(TAU * 38 * i / SR) for i in range(total)]
    write("hag_breath", make_loop(apply(apply(b, env), rasp), 0.2), 0.6, is_loop=True)


def s_wolf_howl():
    dur = 3.6
    c = n(dur)
    p = vibrato(glide(c, [(0, 330), (0.5, 560), (2.2, 600), (3.0, 520), (dur, 380)]), 5, 0.012, 0.4)
    s = [0.0] * c
    for h, g in ((1, 1.0), (2, 0.35), (3, 0.15), (4, 0.06)):
        mix(s, osc([f * h for f in p]), 0, g)
    mix(s, bandpass(noise(c), p, 3), 0, 0.15)
    out = reverb(apply(s, env_adsr(c, 0.35, 0.3, 0.9, 1.0)), 0.35, 1.6, 1.5)
    write("wolf_howl", out, 0.8)


def s_wolf_growl():
    dur = 1.6
    c = n(dur)
    p = vibrato(glide(c, [(0, 75), (0.6, 90), (dur, 70)]), 4, 0.05, 2.0)
    src = voice(p, 0.8, 1.5)
    v = formants(src, [280.0, 700.0, 1700.0], (4, 5, 6), (1, 0.6, 0.2))
    am = [0.7 + 0.3 * math.sin(TAU * 26 * i / SR) for i in range(c)]
    write("wolf_growl", drive(apply(apply(v, am), env_adsr(c, 0.15, 0.2, 0.85, 0.4)), 3.0), 0.85)


def s_police_siren():
    period = 2.0
    count = n(period * 2)
    fr = [700 + 600 * (0.5 - 0.5 * math.cos(TAU * i / n(period))) for i in range(count)]
    s = osc(fr, "saw")
    s = lowpass(bandpass(s + s, 1200, 0.8)[count:], 3000)  # doubled pass = seamless filter state
    write("police_siren", drive(s, 2.0), 0.7, is_loop=True)


def s_walkie(on):
    out = zeros(0.4)
    c = n(0.18)
    burst = apply(bandpass(noise(c), 2200, 1.5), env_adsr(c, 0.005, 0.03, 0.7, 0.08))
    beep = apply(osc([1200.0 if on else 900.0] * n(0.07), "square"), env_adsr(n(0.07), 0.003, 0.01, 0.8, 0.01))
    if on:
        mix(out, burst)
        mix(out, lowpass(beep, 3000), n(0.17), 0.4)
    else:
        mix(out, lowpass(beep, 3000), 0, 0.4)
        mix(out, burst, n(0.08))
    write("walkie_on" if on else "walkie_off", out, 0.7)


def s_heartbeat():
    out = zeros(0.9)
    mix(out, thump(0.2, 70, 45, 0.05))
    mix(out, thump(0.2, 62, 40, 0.06), n(0.2), 0.75)
    write("heartbeat", lowpass(out, 300), 0.95)


def s_pa_chime():
    out = zeros(2.6)
    for k, f in enumerate((784.0, 659.3, 523.3)):
        mix(out, bell(f, 1.6, 0.5), n(k * 0.45), 0.5)
    out = bandpass(out, 1300, 0.6)  # tinny loudspeaker
    write("pa_chime", reverb(out, 0.35, 1.4, 1.0), 0.8)


def s_organ():
    dur = 4.0
    c = n(dur)
    out = [0.0] * c
    for f in (73.4, 146.8, 174.6, 220.0, 293.7):  # D minor
        for h, g in ((1, 1.0), (2, 0.5), (3, 0.3), (4, 0.2), (8, 0.08)):
            mix(out, osc([f * h * (1 + rng.uniform(-0.002, 0.002))] * c), 0, g * 0.2)
    trem = [1.0 + 0.08 * math.sin(TAU * 5.5 * i / SR) for i in range(c)]
    out = apply(apply(out, trem), env_adsr(c, 0.25, 0.3, 0.9, 1.0))
    write("organ", reverb(out, 0.4, 1.8, 2.0), 0.8)


def s_cave_in():
    dur = 3.4
    c = n(dur)
    r = lowpass(lowpass(noise(c), 90), 140)
    out = apply(r, env_adsr(c, 0.3, 0.5, 0.8, 1.6))
    out = normalize(out, 1.0)
    for _ in range(30):
        t = rng.uniform(0.1, 2.6)
        cc = n(0.12)
        rock = apply(lowpass(noise(cc), rng.uniform(800, 2500)), env_exp(cc, 0.03))
        mix(out, rock, n(t), rng.uniform(0.2, 0.6))
    mix(out, thump(0.6, 60, 30, 0.2), n(0.1), 1.0)
    write("cave_in", drive(out, 1.5), 0.95)


def s_gurney():
    count = n(1.6)
    out = [0.0] * count
    for k in range(4):
        c = n(0.18)
        fr = glide(c, [(0, 1700), (0.09, 2300), (0.18, 1900)])
        fr = [f * (1 + 0.03 * math.sin(TAU * 45 * i / SR)) for i, f in enumerate(fr)]
        mix(out, apply(osc(fr, "tri"), env_adsr(c, 0.02, 0.05, 0.6, 0.08)), n(k * 0.4), 0.3, wrap=True)
    rattle = [rng.uniform(-1, 1) if rng.random() < 0.02 else 0.0 for _ in range(count)]
    mix(out, bandpass(rattle + rattle, 900, 2)[count:], 0, 1.5)
    write("gurney", out, 0.6, is_loop=True)


def s_mushroom_break():
    out = zeros(0.45)
    c = n(0.04)
    mix(out, apply(highpass(noise(c), 2500), env_exp(c, 0.008)))
    c = n(0.35)
    sq = bandpass(noise(c), glide(c, [(0, 1400), (0.35, 400)]), 3)
    mix(out, apply(sq, env_exp(c, 0.09)), n(0.02), 1.4)
    write("mushroom_break", out, 0.8)


def s_witch_cackle():
    dur = 2.0
    c = n(dur)
    starts = [0.0] + [0.35 + k * 0.13 for k in range(10)]
    p = vibrato(glide(c, [(0, 700), (0.3, 900), (dur, 520)]), 8, 0.04, 1.0)
    src = voice(p, 0.35, 0.6)
    v = formants(src, [900.0, 1500.0, 2900.0], (5, 6, 8), (1, 0.7, 0.3))
    env = syllables(c, starts, 0.11, 0.008)
    env = [e * (1.3 if i < n(0.3) else 1.0) for i, e in enumerate(env)]
    write("witch_cackle", reverb(drive(apply(v, env), 2.0), 0.25, 1.0, 0.5), 0.85)


def s_splash():
    out = zeros(1.2)
    c = n(0.7)
    mix(out, apply(lowpass(noise(c), glide(c, [(0, 5000), (0.7, 600)])), env_exp(c, 0.18)))
    for _ in range(14):
        cd = n(0.05)
        f0 = rng.uniform(700, 1600)
        drop = apply(osc(glide(cd, [(0, f0), (0.05, f0 * 2.2)])), env_exp(cd, 0.015))
        mix(out, drop, n(rng.uniform(0.15, 1.0)), rng.uniform(0.15, 0.4))
    write("splash", out, 0.8)


def s_owl_hoot():
    out = zeros(2.0)
    for t, d in ((0.0, 0.45), (0.75, 0.22), (1.05, 0.55)):
        c = n(d)
        fr = glide(c, [(0, 360), (d * 0.3, 395), (d, 350)])
        s = [a + 0.08 * b for a, b in zip(osc(fr), lowpass(noise(c), 900))]
        mix(out, apply(s, env_adsr(c, d * 0.35, d * 0.2, 0.8, d * 0.4)), n(t))
    write("owl_hoot", reverb(out, 0.35, 1.5, 1.2), 0.7)


def s_branch_snap():
    out = zeros(0.35)
    for k in range(rng.randint(3, 5)):
        c = n(0.03)
        cr = apply(bandpass(noise(c), rng.uniform(1500, 4000), 2), env_exp(c, 0.006))
        mix(out, cr, n(k * rng.uniform(0.012, 0.03)), rng.uniform(0.5, 1.0))
    c = n(0.2)
    mix(out, apply(bandpass(noise(c), 450, 6), env_exp(c, 0.04)), 0, 1.5)
    write("branch_snap", out, 0.85)


def s_amb_day():
    count = n(20.0)
    f = n(1.0)
    w = wind(count + f, 350, 3, 0.5)
    out = make_loop(w, 1.0)
    out = normalize(out, 0.35)
    for _ in range(14):
        mix(out, bird_phrase(), n(rng.uniform(0, 20)), rng.uniform(0.08, 0.25), wrap=True)
    write("amb_day", out, 0.6, is_loop=True)


def s_amb_dusk():
    count = n(20.0)
    f = n(1.0)
    w = wind(count + f, 260, 2, 0.6)
    out = normalize(make_loop(w, 1.0), 0.4)
    for _ in range(4):
        mix(out, bird_phrase(), n(rng.uniform(0, 20)), rng.uniform(0.04, 0.1), wrap=True)
    mix(out, cricket(count, 4300, 1.7), 0, 0.03)
    mix(out, cricket(count, 4700, 2.3, 4), 0, 0.02)
    write("amb_dusk", out, 0.6, is_loop=True)


def s_amb_night():
    count = n(24.0)
    f = n(1.0)
    w = wind(count + f, 200, 3, 0.7)
    out = normalize(make_loop(w, 1.0), 0.45)
    for fr, rate, p, lvl in ((4300, 2.9, 3, 0.05), (4650, 3.6, 2, 0.04), (3900, 2.1, 4, 0.03),
                             (5100, 4.3, 3, 0.025), (4450, 1.6, 5, 0.03)):
        mix(out, cricket(count, fr, rate, p), 0, lvl)
    # low uneasy drone, whole number of cycles in the loop
    drone = [0.04 * math.sin(TAU * 55 * i / SR) * (0.5 + 0.5 * math.sin(TAU * 2 * i / count)) for i in range(count)]
    mix(out, drone)
    write("amb_night", out, 0.6, is_loop=True)


SOUNDS = {name[2:]: fn for name, fn in globals().items() if name.startswith("s_") and callable(fn)}
SOUNDS.pop("walkie", None)
SOUNDS["walkie_on"] = lambda: s_walkie(True)
SOUNDS["walkie_off"] = lambda: s_walkie(False)


def main():
    names = sys.argv[1:] or sorted(SOUNDS)
    for name in names:
        rng.seed(name)
        SOUNDS[name]()


if __name__ == "__main__":
    main()
