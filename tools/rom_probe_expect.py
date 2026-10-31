#!/usr/bin/env python3
"""Emit the -D flags that bake a ROM's own words into the rom_probe diagnostic.

    tools/rom_probe_expect.py "build/rom/ActRaiser (USA).sfc"
    -> -DTINYSNES_EXP0=16'hD878 -DTINYSNES_EXP1=16'hFB18 ...

The probe in fpga/snes/src/rom_probe.v reads eight 16-bit words out of SDRAM at
fixed byte offsets after the loader has run, and compares them with these.  The
offsets below are the same set the module's addr_of() uses; they are kept in one
place here so the flag order cannot drift from the probe's index order.

A word is the little-endian pair the loader writes: byte[2k] in the low half,
byte[2k+1] in the high half, matching cpu_din = {loader_do, loader_do_r}.
"""

from __future__ import annotations

import argparse
import sys

# Byte offsets, in rom_probe bar order 1..7.  Bar 0 is the probe's own
# write/read self-test at a scratch address and has no ROM expectation.
OFFSETS = [0x000000, 0x004000, 0x007FFC,
           0x008000, 0x080000, 0x040000, 0x007FFE]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("rom")
    ap.add_argument("--check", action="store_true",
                    help="print the words in a readable table as well")
    args = ap.parse_args()

    rom = open(args.rom, "rb").read()
    flags = []
    for i, off in enumerate(OFFSETS):
        if off + 1 >= len(rom):
            sys.exit(f"{args.rom}: offset 0x{off:06X} is past the end of the image")
        word = rom[off] | (rom[off + 1] << 8)
        flags.append(f"-DTINYSNES_EXP{i + 1}=16'h{word:04X}")
        if args.check:
            print(f"  bar {i + 1}: byte 0x{off:06X}  word 0x{word:04X}  {rom[off:off+2].hex()}",
                  file=sys.stderr)
    print(" ".join(flags))
    return 0


if __name__ == "__main__":
    sys.exit(main())
