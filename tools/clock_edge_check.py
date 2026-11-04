#!/usr/bin/env python3
"""Refuse a netlist that clocks one edge of a clock two different ways.

Why this exists.  For GW5A, yosys' synth_gowin keeps only a plain negedge flop
(no enable, no reset) as a true DFFN.  Every other negedge flop is legalised to
a posedge DFFRE whose clock is a LUT1 inverter of the real clock, and that
inverted clock reaches its flops on fabric routing, several ns after the
global clock.  nextpnr treats the inverter output as an unrelated clock and
does not time paths between it and the true negedge flops.

When both kinds sit on the same clock, logic meant to change on one negedge is
split across two edges that are a few ns apart, with no hold check between
them.  That stopped the SuperFX on the board (core-log entry 88): the GSU's EN
was the one true DFFN, its PEND/WAIT handshake flops were on the inverted
clock, they saw EN's new value, and WAIT set without PEND.

    tools/clock_edge_check.py build/x/tinysnes.json

Exit status is 0 when no clock net drives both a true negedge primitive and a
LUT1 clock inverter, 1 when one does, and 2 on a usage or parsing problem.
"""
import json
import re
import sys

CLOCK_PIN = re.compile(r"^CLK[AB]?$")


def is_inverter(cell):
    if cell["type"] != "LUT1":
        return False
    # yosys writes INIT as a binary string, MSB first: F = INIT[I0], so "01".
    return str(cell.get("parameters", {}).get("INIT", "")) in ("01", "1")


def main():
    if len(sys.argv) != 2:
        print(__doc__.strip().splitlines()[0], file=sys.stderr)
        print("usage: clock_edge_check.py <synthesised netlist .json>", file=sys.stderr)
        return 2
    try:
        modules = json.load(open(sys.argv[1]))["modules"]
    except (OSError, ValueError, KeyError) as e:
        print(f"clock_edge_check: cannot read {sys.argv[1]}: {e}", file=sys.stderr)
        return 2

    bad = 0
    for mname, mod in modules.items():
        cells = mod.get("cells", {})
        if not cells:
            continue
        names = {}
        for n, v in mod.get("netnames", {}).items():
            for b in v["bits"]:
                key = (n.startswith("$"), n.count("."), len(n))
                if b not in names or key < names[b][0]:
                    names[b] = (key, n)
        names = {b: n for b, (_, n) in names.items()}

        clock_bits = set()
        negedge = {}
        for cn, c in cells.items():
            for p, bits in c["connections"].items():
                if CLOCK_PIN.match(p) and len(bits) == 1:
                    clock_bits.add(bits[0])
                    if c["type"].startswith("DFFN") and p == "CLK":
                        negedge.setdefault(bits[0], []).append(cn)

        inverted = {}
        for cn, c in cells.items():
            if not is_inverter(c):
                continue
            src = c["connections"].get("I0", [None])[0]
            out = c["connections"].get("F", [None])[0]
            if out in clock_bits:
                inverted.setdefault(src, []).append(cn)

        for b in sorted(set(negedge) & set(inverted), key=str):
            bad += 1
            print(f"clock_edge_check: '{names.get(b, b)}' in {mname} clocks "
                  f"{len(negedge[b])} true negedge flop(s) and also feeds "
                  f"{len(inverted[b])} LUT clock inverter(s)", file=sys.stderr)
            for cn in negedge[b][:8]:
                print(f"    true negedge: {cn}", file=sys.stderr)
            for cn in inverted[b][:8]:
                print(f"    inverter:     {cn} -> '{names.get(cells[cn]['connections']['F'][0])}'",
                      file=sys.stderr)
        for b in sorted(set(inverted) - set(negedge), key=str):
            print(f"    '{names.get(b, b)}': negedge logic on {len(inverted[b])} "
                  f"LUT-inverted clock net(s), no true negedge flops")
        for b in sorted(set(negedge) - set(inverted), key=str):
            print(f"    '{names.get(b, b)}': {len(negedge[b])} true negedge flop(s), "
                  f"no LUT-inverted clock")

    if bad:
        print("clock_edge_check: FAILED -- give the true negedge flop(s) a synchronous "
              "reset or enable so they join the inverted clock (see GSU.v EN)",
              file=sys.stderr)
        return 1
    print("    clock edges: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
