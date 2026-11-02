#!/usr/bin/env python3
"""Report the line buffer's write port from a Yosys JSON netlist.

Why JSON and not the Verilog dump.  An earlier version of this tool read the
`write_verilog` output and decided a net was "real" if it was a name rather than
`1'bx`.  That was wrong twice over: synthesis keeps the *name* of a net whose
logic it has deleted, so a dangling wire looks exactly like a driven one, and the
Verilog dump was separately found to disagree with the JSON about how many PPU
nets carry drivers -- 0 in the dump against 2255 of 2303 in the JSON.

The JSON says, for every cell, which net every port connects to and in which
direction.  So "is this net driven" is answerable exactly: does any cell list it
on an output port.  That is the check this tool makes.

Why the verdict is per memory, not per block.  `memory_libmap` splits one RTL
memory across several BRAM primitives, and it pads every block's 16-bit data
port whether or not that block uses the extra lanes.  A per-block test therefore
reports a healthy memory as broken: with the PAL region bit driven, the write
data reaches 15 distinct nets spread over 8 blocks and only two of them land on
any single block's DIA port.  The question that matters is about the memory, so
this tool takes the union of the blocks' port bits and asks whether every one of
them is driven, and whether there are as many of them as the RTL memory is wide.
`mem` in snes2hdmi.v is 15 bits; `--width` overrides that when it is not.

  tools/report_linebuf_gate.py build/x/tinysnes.json [--width 15]
"""
import json
import sys

# Memories are identified by their ports, not by their cell type or by a name
# substring: a name match also catches the registers and adders that share the
# memory's prefix (`s2h.mem_portA_wdata_DFFRE_Q_...`), which is how an earlier
# version came to report 242 "line-buffer blocks".
MEMORY_PORTS = ("ADA", "DOA")


def main() -> int:
    args = sys.argv[1:]
    width = 15
    if "--width" in args:
        i = args.index("--width")
        width = int(args[i + 1])
        del args[i:i + 2]
    if not args:
        print(__doc__)
        return 2

    d = json.load(open(args[0]))
    mods = d["modules"]
    top = mods.get("snestang_top") or mods[list(mods)[0]]
    cells = top["cells"]

    driven = set()
    for cell in cells.values():
        for port, direction in cell.get("port_directions", {}).items():
            if direction == "output":
                for b in cell["connections"].get(port, []):
                    if isinstance(b, int):
                        driven.add(b)

    blocks = [c for c, info in cells.items()
              if "s2h.mem" in c
              and all(p in info.get("connections", {}) for p in MEMORY_PORTS)]
    if not blocks:
        print("  no line-buffer memory blocks found")
        return 2
    print(f"  line-buffer memory blocks: {len(blocks)}")

    def union(port):
        bits = set()
        for cn in blocks:
            for b in cells[cn]["connections"].get(port, []):
                if isinstance(b, int):
                    bits.add(b)
        return bits

    report = {}
    for port, need, label in (("WREA", 1, "write enable"),
                              ("DIA", width, "write data"),
                              ("ADA", width - 1, "write address")):
        bits = union(port)
        dead = bits - driven
        report[label] = (bits, dead, need)
        print(f"  {label:<14} {len(bits)} distinct bits reach the memory, "
              f"{len(dead)} undriven, {need} expected")

    bad = [label for label, (bits, dead, need)
           in report.items() if dead or len(bits) < need]
    if bad:
        print(f"  VERDICT: the line buffer cannot be written ({', '.join(bad)}).")
        return 1
    print("  VERDICT: the line buffer's write port is intact.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
