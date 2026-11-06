#!/usr/bin/env python3
"""Refuse a netlist in which a register has more than one driver.

Why this exists.  A register written from two `always` blocks is a multiple
driver: yosys keeps one assignment and drops the other without failing the
build, so the netlist is wrong in a way no other gate here can see.  On
2026-11-05 that left `iosys`'s battery-save address frozen -- a 16-byte read
returned the same byte sixteen times, with a correct reply length and a correct
CRC, so the bench, the host test and the protocol check all passed.  The only
evidence was 34 `multiple conflicting drivers` lines in the synthesis log.

Two kinds of name appear in those lines.  Real flops at module scope, such as
`iosys.sav_addr`, are the fault this gate is for.  Function-local temporaries --
`PPU.FlipPlane.bp`, `dsp.CLAMP16.a`, `crc16_byte.value` -- are reported because
yosys turns a function's variables into processes and reuses the name, and they
are harmless: each function has its own copy.  So the benign names are recorded
in a baseline beside this script and only a name that is not in it fails.  A new
name is a decision, not an accident: look at it, and add it to the baseline
deliberately if it is a function local too.

    tools/multi_driver_check.py build/<dir>/lint.log
"""

import re
import sys
from pathlib import Path

BASELINE = Path(__file__).with_name("multi_driver_baseline.txt")

LINE = re.compile(r"multiple conflicting drivers for (\S+?)(?: \[\d+\])?:")


def names_in(log: Path) -> set[str]:
    text = log.read_text(errors="replace")
    found = set()
    for match in LINE.finditer(text):
        # The message names the elaborated path, e.g.
        # snestang_top.\iosys.sav_addr -- keep everything after the backslash.
        name = match.group(1).rsplit("\\", 1)[-1]
        found.add(name)
    return found


def baseline() -> set[str]:
    if not BASELINE.exists():
        return set()
    out = set()
    for line in BASELINE.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            out.add(line)
    return out


def main() -> int:
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    log = Path(sys.argv[1])
    if not log.exists():
        sys.exit(f"multi_driver_check: no such log: {log}")

    found = names_in(log)
    known = baseline()
    new = sorted(found - known)
    gone = sorted(known - found)

    if new:
        print("multiple drivers on signals the baseline does not know:", file=sys.stderr)
        for name in new:
            print(f"  {name}", file=sys.stderr)
        print(
            "A register assigned in two always blocks synthesises to whichever\n"
            "assignment yosys keeps, and the other silently disappears.  If the\n"
            "name is a function-local temporary, add it to\n"
            f"{BASELINE.name}; otherwise fix the RTL.",
            file=sys.stderr,
        )
        return 1

    print(f"    no new multiple drivers ({len(found)} known)")
    if gone:
        print(f"    note: {len(gone)} baseline name(s) no longer conflict: "
              f"{', '.join(gone[:4])}{' ...' if len(gone) > 4 else ''}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
