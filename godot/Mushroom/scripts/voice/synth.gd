extends RefCounted
## Procedural sounds for Voice: walkie beeps, radio static, ghostly whispers; plus floats -> WAV.

const RATE := 16000


## Mono floats (-1..1) to a 16-bit AudioStreamWAV, optionally looping.
static func wav(samples: PackedFloat32Array, rate := RATE, loop := false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w


## Push-to-talk press: a switch click and a short chirp.
static func beep_down() -> AudioStreamWAV:
	var out := _click(0.012, 0.8)
	out.append_array(_tone(1150.0, 0.06, 0.45))
	return wav(out)


## Push-to-talk release: the two-tone "roger beep" and a squelch tail.
static func beep_up() -> AudioStreamWAV:
	var out := _tone(1400.0, 0.07, 0.4)
	out.append_array(_tone(1000.0, 0.07, 0.4))
	var tail := PackedFloat32Array()
	var n := int(0.18 * RATE)
	tail.resize(n)
	for i in n:
		tail[i] = randf_range(-0.5, 0.5) * pow(1.0 - float(i) / n, 2.0)
	out.append_array(tail)
	out.append_array(_click(0.01, 0.5))
	return wav(out)


## One second of looping static (the Walkie bus band-passes and distorts it into radio hiss).
static func hiss() -> AudioStreamWAV:
	var out := PackedFloat32Array()
	out.resize(RATE)
	var lp := 0.0
	for i in RATE:
		lp += (randf_range(-1.0, 1.0) - lp) * 0.6
		out[i] = lp * 0.5
	return wav(out, RATE, true)


## A breathy, unintelligible whisper: band-passed noise in syllable-like bursts.
static func whisper(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var dur := rng.randf_range(1.0, 2.2)
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var t := rng.randf_range(0.03, 0.12)
	while t < dur - 0.1:
		var length := rng.randf_range(0.07, 0.26)
		var amp := rng.randf_range(0.4, 1.0)
		var bright := rng.randf_range(0.2, 0.75)  # high = hissy "s", low = breathy "h"
		var a := int(t * RATE)
		var b := mini(int((t + length) * RATE), n)
		var fast := 0.0
		var slow := 0.0
		for i in range(a, b):
			fast += (rng.randf_range(-1.0, 1.0) - fast) * bright
			slow += (fast - slow) * 0.08
			var env := sin(PI * (i - a) / float(maxi(b - a, 1)))
			out[i] += (fast - slow) * amp * env * env
		t += length + rng.randf_range(0.02, 0.16)
	return wav(normalized(out, 0.6))


## Scales so the loudest sample is `peak`.
static func normalized(samples: PackedFloat32Array, peak: float) -> PackedFloat32Array:
	var top := 0.0001
	for s in samples:
		top = maxf(top, absf(s))
	var k := peak / top
	for i in samples.size():
		samples[i] *= k
	return samples


## Fades both ends over `fade` samples (no clicks when a clip starts mid-word).
static func faded(samples: PackedFloat32Array, fade := 320) -> PackedFloat32Array:
	var f := mini(fade, samples.size() / 2)
	for i in f:
		var k := float(i) / f
		samples[i] *= k
		samples[samples.size() - 1 - i] *= k
	return samples


static func _tone(freq: float, seconds: float, amp: float) -> PackedFloat32Array:
	var n := int(seconds * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = sin(TAU * freq * i / RATE) * amp
	return faded(out, 48)


static func _click(seconds: float, amp: float) -> PackedFloat32Array:
	var n := int(seconds * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = randf_range(-amp, amp) * (1.0 - float(i) / n)
	return out
