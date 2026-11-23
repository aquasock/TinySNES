#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Check hdmi_audio_resample.v's output against its arithmetic and the signal.

    tools/sim/hdmi_resample_model.py DUMP FREQ_HZ IN_HZ

DUMP is the bench's log, one line per output sample after the first second:
the index of x0 in the input stream, t (16 fractional bits), the four
left and four right history samples and the two words the core produced.
The bench's input is A sin(2 pi FREQ n / IN_HZ) on the left and
B cos(...) on the right (hdmi_resample_tb.sv), so the ideal output at
input position x0 + t / 65536 is known exactly.

It checks, and exits 1 on any failure:
  * every word equals cubic() below, bit for bit: the core's arithmetic;
  * the input position x0 + t / 65536 advances by the resampling ratio,
    32,127 / 48,000 within 2 percent, at every output sample, so each word
    is taken at the right place and not merely computed right for its t;
  * the SNR of the output against the ideal signal, printed per channel;
    it must be at least --min-snr dB.
"""
import argparse
import math
import sys

AMP_L, AMP_R = 20000.0, 12000.0


def rshift_round(v, n):
    """(v + 2^(n-1)) >> n, arithmetic, as the core rounds."""
    return (v + (1 << (n - 1))) >> n


def cubic(m1, p0, p1, p2, t):
    """Catmull-Rom between p0 and p1 at t / 65536, in the core's fixed point."""
    a = 3 * (p0 - p1) + p2 - m1
    b = 2 * m1 - 5 * p0 + 4 * p1 - p2
    c = p1 - m1
    s1 = b + rshift_round(a * t, 16)
    s2 = c + rshift_round(s1 * t, 16)
    y = p0 + rshift_round(s2 * t, 17)
    return max(-32768, min(32767, y))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dump")
    ap.add_argument("freq", type=float)
    ap.add_argument("in_hz", type=float)
    ap.add_argument("--min-snr", type=float, default=60.0)
    a = ap.parse_args()

    n = mism = jumps = 0
    last = None
    ratio = 32127.0 / 48000.0
    err2 = [0.0, 0.0]
    sig2 = [0.0, 0.0]
    with open(a.dump) as f:
        for line in f:
            v = [int(x) for x in line.split()]
            idx, t = v[0], v[1]
            hl, hr, wl, wr = v[2:6], v[6:10], v[10], v[11]
            if cubic(*hl, t) != wl or cubic(*hr, t) != wr:
                if mism < 5:
                    print("mismatch:", line.strip())
                mism += 1
            pos = idx + t / 65536.0
            if last is not None and abs((pos - last) / ratio - 1.0) > 0.02:
                if jumps < 5:
                    print(f"position step {pos - last:.5f} at sample {n}")
                jumps += 1
            last = pos
            w = 2 * math.pi * a.freq * pos / a.in_hz
            for ch, (amp, fn, word) in enumerate(((AMP_L, math.sin, wl),
                                                  (AMP_R, math.cos, wr))):
                ideal = amp * fn(w)
                err2[ch] += (word - ideal) ** 2
                sig2[ch] += ideal ** 2
            n += 1
    if n == 0:
        print("hdmi_resample_model: no samples")
        return 1
    snr = [10 * math.log10(sig2[c] / max(err2[c], 1e-9)) for c in (0, 1)]
    print(f"hdmi_resample_model: {n} samples at {a.freq:.0f} Hz, "
          f"{mism} differ from the model, {jumps} position steps off the ratio, SNR left {snr[0]:.1f} dB right {snr[1]:.1f} dB")
    ok = mism == 0 and jumps == 0 and min(snr) >= a.min_snr
    print("PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
