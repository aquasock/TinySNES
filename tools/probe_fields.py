#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""One declarative field list per probe, driving both the RTL and the decoder.

Why this exists.  Four cycles in a row (core-log entries 60, 61, 62 and 63)
shipped a probe whose displayed field order was wrong, and each was caught by
luck rather than by construction:

  * the concatenation width was summed wrongly twice, so the value was
    zero-extended and every field sat above where the comment said it did;
  * the host decoder assumed a different order above the second field, so
    every flag was attributed to its neighbour.

A width check in the RTL fixed the first class.  Nothing fixed the second,
because the order lived in two places: a hand-written concatenation in
Verilog and a throwaway script written fresh each cycle.  This module is the
single source of truth for both.  The RTL concatenation is generated from
`FIELDS` by `emit_sv_concat()`, and the host decoder slices the captured word
using the same list by `decode()`, so the two cannot disagree.

Field order in `FIELDS` is LOW to HIGH, matching the emitted concatenation,
whose rightmost term is the least significant.  `emit_sv_concat()` emits the
terms in reverse so the Verilog reads left-to-right high-to-low and a human
reading the source sees the same order the display does.

Usage:
    from probe_fields import FIELDS, check, emit_sv_concat, decode
    check()                       # raises if the widths do not total 80
    print(emit_sv_concat({...}))  # Verilog concatenation expression
    decode(0x0477)                # dict of field name -> value
"""

# (name, width) pairs, LOW bit first.
FIELDS = [
    ("flags", 8),    # {sfr30_read, restart_after, sfr31_while_set, rom_seen,
                     #  cache_fill, stop_seen, flag_irq, flag_go}
    ("cf_addr", 8),     # ROM_A[7:0] at the first cache write
    ("cf_b0", 8),       # first four bytes written into the cache, in order
    ("cf_b1", 8),
    ("cf_b2", 8),
    ("cf_b3", 8),
    ("first_op", 8),    # first opcode decoded while FLAG_GO was set
    ("state_seen", 16),
    ("go_cnt", 8),      # saturating; the question is "one" versus "many"
]

BUS_WIDTH = 80


def check() -> None:
    """Fail loudly if the field list does not fill the bus exactly."""
    total = sum(w for _, w in FIELDS)
    if total != BUS_WIDTH:
        raise SystemExit(
            f"probe field widths total {total}, expected {BUS_WIDTH}; "
            "fix FIELDS rather than the generated code"
        )


def layout() -> list[tuple[str, int, int]]:
    """(name, hi, lo) for every field, lowest first."""
    out, bit = [], 0
    for name, width in FIELDS:
        out.append((name, bit + width - 1, bit))
        bit += width
    return out


def emit_sv_concat(expr: dict[str, str]) -> str:
    """Verilog concatenation, highest field first, from `expr` by field name."""
    check()
    parts = []
    for name, width, _lo in reversed(layout()):
        parts.append(expr[name])
    return "{" + ",\n                       ".join(parts) + "}"


def decode(word: int) -> dict[str, int]:
    """Slice a captured 80-bit word into named fields."""
    check()
    return {name: (word >> lo) & ((1 << (hi - lo + 1)) - 1)
            for name, hi, lo in layout()}


ROMST = ["IDLE", "FETCH", "FETCH_DONE", "CACHE", "CACHE_DONE", "CACHE_END", "LOAD"]


def verify_rtl(path: str, marker: str = "TINYSNES_GSU_PROBE") -> list[str]:
    """Compare the RTL's fp_bus concatenation against FIELDS.

    Returns a list of problems, empty when they agree.  The order check is the
    one that matters: a wrong width fails synthesis (the elaboration guard),
    but a wrong ORDER builds cleanly and decodes as plausible nonsense, which
    is what entries 60 to 63 each did once.
    """
    import re
    src = open(path).read()
    # Anchor on the `ifdef line: the marker name also appears in comments
    # earlier in the file, and matching one of those made this check compare
    # against the wrong probe's concatenation.
    at = src.index("`ifdef " + marker)
    seg = src[at:]
    m = re.search(r"fp_bus <= \{(.*?)\};", seg, re.S)
    if not m:
        return [f"no fp_bus concatenation found after {marker}"]
    # Split on top-level commas only: a field may itself be a concatenation,
    # and splitting blindly on every comma breaks such a field into pieces and
    # reports phantom position mismatches.
    terms, depth, cur = [], 0, ""
    for ch in m.group(1):
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
        if ch == "," and depth == 0:
            terms.append(cur.strip()); cur = ""
        else:
            cur += ch
    if cur.strip():
        terms.append(cur.strip())
    expected = [n for n, _hi, _lo in reversed(layout())]
    problems = []
    if len(terms) != len(expected):
        problems.append(
            f"RTL concat has {len(terms)} terms, FIELDS has {len(expected)} fields")
    for i, (got, want) in enumerate(zip(terms, expected)):
        if want == "pad":
            if not re.match(r"^\d+'b0$", got):
                problems.append(f"expected a constant zero pad, got {got!r}")
            continue
        stem = got.replace("gsu_dbg_", "").replace("gs_", "")
        # A sliced term names the same field, but the slice also states a width.
        # Cutting one field down to fit while another keeps its full width leaves
        # the concatenation the right total width and every field after it in the
        # wrong place, which is the exact corruption this module exists to stop,
        # so the slice width is checked against the declaration rather than
        # stripped and ignored.
        m_slice = re.match(r"^(.*?)\[(\d+):(\d+)\]$", stem)
        if m_slice:
            stem = m_slice.group(1)
            width = int(m_slice.group(2)) - int(m_slice.group(3)) + 1
            want_width = [w for n, w in FIELDS if n == want]
            if want_width and width != want_width[0]:
                problems.append(
                    f"slice width mismatch at {want!r}: RTL term {got!r} is "
                    f"{width} bits, FIELDS declares {want_width[0]}")
        # A field may legitimately be built as a nested concatenation of
        # sub-fields (a packed flag word, a pair of counters).  Accept a brace
        # term at those named positions; the sub-field order inside it is the
        # RTL comment's job and is not checkable from here.
        if got.startswith("{") and want in ("flags", "flags_now", "bsram", "state_pair", "sfr_lo", "go_writes"):
            continue
        if stem != want:
            problems.append(f"position mismatch: RTL {got!r} vs FIELDS {want!r}")
    return problems


def describe(word: int) -> str:
    """Human-readable one-block summary, for reading a capture by hand."""
    f = decode(word)
    seen = [ROMST[i] for i in range(7) if f["romst_seen"] >> i & 1]
    return (
        f"rom_type        0x{f['rom_type']:04X}\n"
        f"go_cnt          {f['go_cnt']}\n"
        f"mmio_cnt        0x{f['mmio_cnt']:04X}\n"
        f"rom_cnt         0x{f['rom_cnt']:04X}\n"
        f"--- state field 0x{(word & 0xFFFF):04X} ---\n"
        f"cache_seen      {f['cache_seen']}\n"
        f"go_seen         {f['go_seen']}\n"
        f"cache_mmio_seen {f['cache_mmio_seen']}\n"
        f"cache_fill_seen {f['cache_fill_seen']}\n"
        f"ROMST_SEEN      {seen}"
    )


if __name__ == "__main__":
    import sys
    check()
    for name, hi, lo in reversed(layout()):
        print(f"  [{hi:2d}:{lo:2d}]  {name}")
    if len(sys.argv) > 1 and sys.argv[1] == "--verify":
        path = sys.argv[2] if len(sys.argv) > 2 else "fpga/snes/src/snestang_top.v"
        problems = verify_rtl(path)
        if problems:
            for p in problems:
                print("MISMATCH:", p)
            raise SystemExit(1)
        print("RTL concatenation matches FIELDS")
    elif len(sys.argv) > 1:
        print()
        print(describe(int(sys.argv[1], 0)))
