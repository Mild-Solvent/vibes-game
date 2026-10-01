"""Summarize Mushroom Foraging session logs (the `logs` folder next to the game's exe).

    python summarize_logs.py <session-....log | folder> [more files...]

For each log: who/what/when, connection quality (ping, bandwidth, FPS), voice health (queue,
skips, clears), lag spikes, deaths and other events, errors, and every F8 recording, with the
ten seconds of log lines before each F8 debug recording started or stopped.
"""
import os
import re
import sys
from collections import Counter

LINE = re.compile(r"^(\d\d:\d\d:\d\d\.\d{3}) (\S+)\s+(.*)$")


def secs(stamp):
    h, m, s = stamp.split(":")
    return int(h) * 3600 + int(m) * 60 + float(s)


def pct(values, p):
    if not values:
        return 0
    values = sorted(values)
    return values[min(len(values) - 1, int(len(values) * p))]


def summarize(path):
    lines = []
    with open(path, encoding="utf-8", errors="replace") as f:
        for raw in f:
            m = LINE.match(raw.rstrip("\n"))
            if m:
                lines.append(m.groups())
    print("=" * 78)
    print(os.path.basename(path))
    if not lines:
        print("  (empty)")
        return
    first, last = secs(lines[0][0]), secs(lines[-1][0])
    print(f"  {lines[0][0]} -> {lines[-1][0]}  ({(last - first) / 60:.1f} min)")
    for _, kind, text in lines:
        if kind == "INFO":
            print("  " + text)
            break

    stats = [dict(kv.split("=", 1) for kv in text.split()) for _, kind, text in lines if kind == "STAT"]
    if stats:
        num = lambda key: [float(s[key]) for s in stats if key in s and float(s[key]) >= 0]
        ping, fps, out, inn, queue = num("ping"), num("fps"), num("out"), num("in"), num("qmax")
        print(f"  role {stats[-1].get('role')}, up to {max(int(s.get('players', 1)) for s in stats)} players")
        if ping:
            print(f"  ping   median {pct(ping, .5):.0f} ms, p95 {pct(ping, .95):.0f}, max {max(ping):.0f}")
        print(f"  fps    median {pct(fps, .5):.0f}, worst {min(fps):.0f}")
        print(f"  net    out avg {sum(out) / len(out):.1f} KB/s (max {max(out):.1f}), "
              f"in avg {sum(inn) / len(inn):.1f} KB/s (max {max(inn):.1f})")
        print(f"  voice  queue median {pct(queue, .5):.0f} ms, max {max(queue):.0f}; "
              f"skips {stats[-1].get('skip')}, clears {stats[-1].get('clear')}, "
              f"frames sent {stats[-1].get('sent')} recv {stats[-1].get('recv')}")

    spikes = [(t, text) for t, kind, text in lines if kind == "LAG"]
    print(f"  lag spikes: {len(spikes)}")
    for t, text in spikes[:15]:
        print(f"    {t} {text}")
    if len(spikes) > 15:
        print(f"    ... {len(spikes) - 15} more")

    print("  events:")
    for t, kind, text in lines:
        if kind in ("NET", "GAME") and not text.startswith(("pickup", "drop", "throw", "toast")):
            print(f"    {t} {kind} {text}")
    small = Counter(text.split(":", 1)[0] for _, kind, text in lines
                    if kind == "GAME" and text.startswith(("pickup", "drop", "throw")))
    if small:
        print("    (also " + ", ".join(f"{n} {k}s" for k, n in small.items()) + ")")

    errors = Counter(text for _, kind, text in lines if kind == "ERR")
    print(f"  errors/warnings: {sum(errors.values())} ({len(errors)} different)")
    for text, n in errors.most_common(12):
        print(f"    {n}x {text[:150]}")

    for i, (t, kind, text) in enumerate(lines):
        if kind != "REC":
            continue
        print(f"  F8 {t}: {text}")
        for t2, k2, x2 in lines[max(0, i - 40):i]:
            if secs(t) - secs(t2) <= 10 and k2 not in ("OUT", "SNAP"):
                print(f"      {t2} {k2} {x2[:140]}")


def main():
    paths = []
    for arg in sys.argv[1:] or ["."]:
        if os.path.isdir(arg):
            paths += sorted(os.path.join(arg, f) for f in os.listdir(arg)
                            if (f.startswith("session-") or f.startswith("debug-")) and f.endswith(".log"))
        else:
            paths.append(arg)
    for p in paths:
        summarize(p)


if __name__ == "__main__":
    main()
