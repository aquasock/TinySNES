#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Add architected-register outputs to GHDL's Verilog for MiSTer's SPC700.

    export_regs.py spc_raw.v spc_ref.v

GHDL's --out=verilog keeps the VHDL entity's ports and nothing else.  MiSTer's
SPC700 exposes no debug port, so a lockstep comparison has no way to read A, X,
Y, SP, PSW or PC out of it.  Those six signals do exist inside the generated
module -- GHDL emits them as module-level wires assigned from nets:

    assign a = n689;   assign x = n690;   ...   assign pc = pcr;

so this script does two mechanical things and nothing else:

  1. renames `module SPC700` to `module SPC700_ref`, so the reference can sit
     beside this repository's SPC700 in one bench;
  2. appends seven output ports to that module and drives them from the wires
     GHDL already produced.

`DBG_LAST` carries MiSTer's `last_cycle`, which is high on the final microcode
step of an instruction.  This repository's SPC700 has the same signal
(`LAST_CYCLE`), so both cores can be compared at instruction boundaries rather
than every clock, which is what lets two different microarchitectures that
agree on behaviour still be compared.

The transformation is asserted, not assumed: every signal the script claims to
export is checked to be declared in the module before the file is written, so a
change in GHDL's output naming fails the build instead of producing a bench that
silently compares zeros.  Nothing in MiSTer's VHDL is edited.
"""

from __future__ import annotations

import re
import sys

EXPORTS = [
    # (port name, source wire, width)
    ("DBG_A", "a", 8),
    ("DBG_X", "x", 8),
    ("DBG_Y", "y", 8),
    ("DBG_SP", "sp", 8),
    ("DBG_PSW", "psw", 8),
    ("DBG_PC", "pc", 16),
    ("DBG_LAST", "last_cycle", 1),
]


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(__doc__.strip().splitlines()[2].strip(), file=sys.stderr)
        return 2
    src, dst = argv[1], argv[2]
    text = open(src).read()

    head = re.search(r"^module SPC700\b", text, re.M)
    if not head:
        print("export_regs.py: no `module SPC700` in GHDL output", file=sys.stderr)
        return 1
    body_start = head.start()
    body_end = text.find("endmodule", body_start)
    if body_end < 0:
        print("export_regs.py: unterminated module SPC700", file=sys.stderr)
        return 1
    body = text[body_start:body_end]

    # Check the wires GHDL is expected to have produced.  A missing one is a
    # hard error: exporting a constant zero would make the bench agree with
    # itself and prove nothing.
    declared = set(re.findall(r"^\s*wire\s+(?:\[[^\]]*\]\s*)?(\w+)\s*;", body, re.M))
    missing = [w for _, w, _ in EXPORTS if w not in declared]
    if missing:
        print(f"export_regs.py: GHDL output lacks {', '.join(missing)}", file=sys.stderr)
        return 1

    # 1. Extra ports, immediately before the port list's closing `);`.
    #    This is the FIRST `);` after the module head: the port list is the only
    #    one at module scope before the body begins.  Using the last one would
    #    place the ports at the end of the module body, where they would not be
    #    ports at all and the bench would bind nothing.
    close = body.find(");")
    if close < 0:
        print("export_regs.py: no closing `);` in module SPC700", file=sys.stderr)
        return 1
    ports = "".join(
        f",\n   output {'[' + str(w - 1) + ':0] ' if w > 1 else ''}{name}"
        for name, _, w in EXPORTS
    )
    body = body[:close] + ports + body[close:]

    # 2. The assignments, after every other statement in the module.
    assigns = "".join(f"\n  assign {name} = {wire};" for name, wire, _ in EXPORTS)
    body = body + assigns + "\n"

    renamed = "module SPC700_ref" + body[len("module SPC700"):]

    # The ports must be inside the header, not merely somewhere in the file.
    header = renamed[: renamed.find(");")]
    if any(name not in header for name, _, _ in EXPORTS):
        print("export_regs.py: debug ports did not land in the port list", file=sys.stderr)
        return 1

    open(dst, "w").write(text[:body_start] + renamed + text[body_end:])
    print(f"export_regs.py: wrote {dst} with {len(EXPORTS)} debug outputs")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
