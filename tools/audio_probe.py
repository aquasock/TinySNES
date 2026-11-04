#!/usr/bin/env python3
"""Record the Pmod I2S2's line output and measure it, rather than describe it.

The board's own audio can only be judged by ear from the HDMI output, and "it
sounds a bit scratchy" is not something that can be fixed from.  With the Pmod
line-out wired to the PC's line-in, the same signal can be captured and measured,
which separates the possibilities that sound identical:

  * a resampler artefact shows as spurious content that moves with the tone's
    frequency;
  * a clock or FIFO problem shows as broadband noise that does not;
  * clipping shows as a flat-topped waveform and harmonics at odd multiples;
  * a correct output shows one peak at the tone, harmonics far below it, and a
    noise floor set by the 16-bit source rather than by anything else.

    tools/audio_probe.py --seconds 3
    tools/audio_probe.py --seconds 5 --fundamental 440
    tools/audio_probe.py --file /tmp/cap.wav

`--fundamental` names the tone being played, which lets the report separate the
tone's own harmonics from unrelated spurious peaks.  Without it the strongest
peak is taken as the fundamental.
"""
import argparse
import math
import subprocess
import sys
import wave


def record(seconds: float, device: str, rate: int) -> str:
    path = "/tmp/audio_probe.wav"
    cmd = ["arecord", "-D", device, "-f", "S16_LE", "-r", str(rate),
           "-c", "2", "-d", str(int(round(seconds))), path]
    subprocess.run(cmd, check=True, capture_output=True)
    return path


def read_wav(path: str):
    with wave.open(path) as w:
        rate = w.getframerate()
        n = w.getnframes()
        ch = w.getnchannels()
        raw = w.readframes(n)
    import struct
    d = struct.unpack("<%dh" % (n * ch), raw)
    return rate, d[0::ch], d[1::ch]


def rms(xs) -> float:
    return math.sqrt(sum(x * x for x in xs) / len(xs)) if xs else 0.0


def db(value: float, ref: float = 32768.0) -> float:
    return 20 * math.log10(max(abs(value), 1e-12) / ref)


def fft_magnitudes(xs, nfft: int):
    """A plain radix-2 FFT, so this runs with no numpy on the machine."""
    # Hann window: without it the rectangular window's sidelobes are far above
    # the artefacts being looked for.
    n = len(xs)
    win = [0.5 - 0.5 * math.cos(2 * math.pi * i / (n - 1)) for i in range(n)]
    buf = [complex(xs[i] * win[i], 0.0) for i in range(n)]

    j = 0
    for i in range(1, n):
        bit = n >> 1
        while j & bit:
            j ^= bit
            bit >>= 1
        j |= bit
        if i < j:
            buf[i], buf[j] = buf[j], buf[i]

    length = 2
    while length <= n:
        ang = -2 * math.pi / length
        wl = complex(math.cos(ang), math.sin(ang))
        for i in range(0, n, length):
            w = 1 + 0j
            for k in range(i, i + length // 2):
                u = buf[k]
                v = buf[k + length // 2] * w
                buf[k] = u + v
                buf[k + length // 2] = u - v
                w *= wl
        length <<= 1
    return [abs(c) for c in buf[:nfft // 2]]


def analyse(path: str, fundamental: float | None, rate: int):
    rate, L, R = read_wav(path)
    # Use the left channel, and a power-of-two window well inside the capture so
    # the analysis never sees the file's start or end.
    n = 1 << 15
    if len(L) < n + 1024:
        print(f"  capture too short for a {n}-point analysis")
        return 1
    start = (len(L) - n) // 2
    seg = L[start:start + n]

    peak = max(abs(x) for x in seg)
    clipped = sum(1 for x in seg if abs(x) >= 32767)
    print(f"  captured {len(L) / rate:.2f} s at {rate} Hz")
    print(f"  level: peak {db(peak):+.1f} dBFS   rms {db(rms(seg)):+.1f} dBFS"
          f"   clipping {100.0 * clipped / n:.2f}% of samples")
    if clipped > n * 0.001:
        print("  NOTE: the capture is clipping; readings below are of the ADC,")
        print("        not the board.  Lower the capture gain and repeat.")

    mags = fft_magnitudes(seg, n)
    bin_hz = rate / n
    # Take the strongest bin, then refine it against its neighbours.
    best = max(range(2, len(mags)), key=lambda i: mags[i])
    f0 = best * bin_hz
    if fundamental:
        f0 = fundamental
        best = int(round(fundamental / bin_hz))
    peak_mag = mags[best]
    print(f"  fundamental: {f0:.2f} Hz")

    # Harmonic series: each harmonic's level relative to the fundamental.
    print("  harmonics (relative to the fundamental):")
    worst = -999.0
    for h in range(1, 11):
        b = int(round(h * f0 / bin_hz))
        if b + 1 >= len(mags):
            break
        m = max(mags[b - 1:b + 2])
        rel = 20 * math.log10(max(m, 1e-12) / max(peak_mag, 1e-12))
        tag = "  <-- fundamental" if h == 1 else ""
        print(f"    h{h:<2} {h * f0:8.1f} Hz  {rel:7.1f} dBc{tag}")
        if h > 1:
            worst = max(worst, rel)

    # Spurious peaks: anything well clear of the local noise that is neither the
    # fundamental nor one of its first ten harmonics.
    print("  strongest peaks that are not harmonics:")
    harmonics = {int(round(h * f0 / bin_hz)) for h in range(1, 11)}
    masked = set()
    for h in harmonics:
        masked.update(range(max(0, h - 3), h + 4))
    cand = [(i, m) for i, m in enumerate(mags) if i not in masked and i > 2]
    cand.sort(key=lambda t: -t[1])
    shown = 0
    for i, m in cand:
        if shown >= 8:
            break
        rel = 20 * math.log10(max(m, 1e-12) / max(peak_mag, 1e-12))
        if rel < -120:
            break
        print(f"    {i * bin_hz:9.1f} Hz  {rel:7.1f} dBc")
        shown += 1

    # Noise floor: the median bin level, which a tone does not move.
    srt = sorted(mags[3:])
    median = srt[len(srt) // 2]
    print(f"  noise floor: {20 * math.log10(max(median, 1e-12) / max(peak_mag, 1e-12)):7.1f} dBc"
          "  (median bin, relative to the tone)")
    print()
    print("  How to read it: a clean 16-bit output puts the noise floor below")
    print("  about -80 dBc and keeps every harmonic under -70 dBc.  A resampler")
    print("  artefact puts spurious peaks above about -60 dBc whose level moves")
    print("  when the tone's frequency changes; broadband grit raises the floor")
    print("  without adding discrete peaks.")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--seconds", type=float, default=3.0)
    ap.add_argument("--device", default="plughw:0,0")
    ap.add_argument("--rate", type=int, default=48000)
    ap.add_argument("--fundamental", type=float, default=None,
                    help="the tone being played, e.g. 440")
    ap.add_argument("--file", help="analyse an existing wav instead of recording")
    args = ap.parse_args()

    path = args.file or record(args.seconds, args.device, args.rate)
    print(f"audio probe: {path}")
    return analyse(path, args.fundamental, args.rate)


if __name__ == "__main__":
    sys.exit(main())
