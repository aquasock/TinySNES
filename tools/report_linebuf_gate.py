#!/usr/bin/env python3
"""Report the line buffer's write port in a gate-level netlist.

The question this project has chased for days is narrow enough to answer by
reading one instance out of the shipped netlist: does the line buffer's write
port still have a real enable, a real address and real data, or did synthesis
prove some of it constant and delete it?

These fail in different ways and the difference matters:

  * WREA tied to 0        -- the buffer can never be written at all.
  * DIA or ADA all `x`    -- the buffer is still written, but with nothing, so
                             its contents become undefined rather than retained.

    tools/report_linebuf_gate.py build/gatelevel/tinysnes_gate.v
"""
import re
import sys


def port(body: str, name: str) -> str | None:
    """Extract one .PORT(...) value, tolerating nested brackets."""
    m = re.search(r"\.%s\(((?:[^()]|\([^()]*\))*)\)" % name, body, re.S)
    return m.group(1).strip() if m else None


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    text = open(sys.argv[1]).read()

    # Instance names come from the RTL: the buffer is `mem` inside snes2hdmi, and
    # Yosys names the cells after it.
    blocks = re.findall(r"\)\s*\\?([\w.$]*s2h\.mem[\w.$]*)\s*\((.*?)\);", text, re.S)
    if not blocks:
        print("  no line-buffer instances found in this netlist")
        return 2

    print(f"  line-buffer instances: {len(blocks)}")

    tied_enable = 0
    dead_data = 0
    dead_addr = 0
    for name, body in blocks:
        we = port(body, "WREA") or ""
        di = port(body, "DIA") or ""
        ad = port(body, "ADA") or ""
        if we.replace(" ", "") in ("1'b0", "1'h0", "1'bx"):
            tied_enable += 1
        if di and "x" in di and "\\" not in di:
            dead_data += 1
        if ad and ad.count("x") > 6:
            dead_addr += 1

    n = len(blocks)
    print(f"  WREA tied off:            {tied_enable}/{n}")
    print(f"  write data all-don't-care: {dead_data}/{n}")
    print(f"  write address mostly x:    {dead_addr}/{n}")

    if tied_enable == n:
        print("  VERDICT: the line buffer cannot be written; the write enable is constant.")
        return 1
    if dead_data == n:
        print("  VERDICT: the line buffer is written with undefined data and address.")
        return 1
    print("  VERDICT: the line buffer's write port is intact.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
