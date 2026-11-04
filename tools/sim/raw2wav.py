#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Wrap gsu_tb's +wav raw stereo s16le samples in a WAV header.

    tools/sim/raw2wav.py RAW OUT.wav [--rate HZ]

dsp.v's CEGen steps the S-DSP at mclk x ACLK_FREQ / 2147730 and emits one
sample per 128 steps, which at the bench's 21.477272 MHz is 32180 Hz, the
default; pass --rate to override.
"""
import argparse, wave

ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
ap.add_argument("raw")
ap.add_argument("out")
ap.add_argument("--rate", type=int, default=32180)
a = ap.parse_args()
data = open(a.raw, "rb").read()
data = data[: len(data) // 4 * 4]
with wave.open(a.out, "wb") as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(a.rate)
    w.writeframes(data)
print(f"{a.out}: {len(data)//4} samples, {len(data)/4/a.rate:.2f} s at {a.rate} Hz")
