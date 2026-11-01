#!/usr/bin/env python3
"""Report which spine/bridge pips each clock takes, and refuse unmeasured ones.

Why this exists.  On the GW5AST-138C a clock reaches the global network by
leaving a spine mux through a bridge pip, and not every pip clocks its branches.
TinyNES measured this on this board (core-reference DEV-009, DEV-017):

  * `SPINE17 <= CBRIDGEOUT_BOTTOM0` and `SPINE18 <= CBRIDGEOUT_BOTTOM2` clock
    NONE of the flip-flops on the branches they feed -- they hold power-up 0.
  * `SPINE26 <= CBRIDGEOUT_BOTTOM2` clocks every one.
  * Routing the bus clock into `(54,88) SPINE16` -> `(27,96) SPINE25` left an
    image that loaded with DONE completely silent, while changing only those
    three muxes made it run.
  * Which pins a clock gets depends on the ORDER nextpnr routes clock nets in;
    one failing netlist booted unchanged apart from its clock routing order.

TinyNES and TinyGBC responded with a build gate.  TinySNES had none, so this
design was free to place the SNES master clock across six spines on paths that
have never been measured on this board -- which is a candidate explanation for a
machine whose every self-test passes and which nevertheless fails to run.

    tools/clock_plane_report.py build/x/tinysnes-routed.json
    tools/clock_plane_report.py ... --allow-unmeasured   (warn, do not fail)

Exit status is 0 when every clock is on a measured-good pip set, 1 when one is
not, and 2 on a usage or parsing problem.
"""
import argparse
import json
import re
import sys

# The rule is SOURCE-DEPENDENT, and conflating the two sources is a mistake this
# tool made in its first version.  TinyNES measured both halves separately:
#
# PLL clock source (a PLL output or a clock being routed into a PLL):
#   DEV-009 -- entering at (54,88) SPINE16 and leaving through
#   CBRIDGEOUT_BOTTOM0 into SPINE25 and SPINE1 loaded with DONE and was SILENT;
#   changing only those muxes to (54,93) SPINE10 / CBRIDGEOUT_TOP2 made it RUN,
#   and SPINE8 / CBRIDGEOUT_TOP0 also ran.  So for a PLL source the BOTTOM
#   entries are dead and the TOP entries work.  The apicula fork encodes this by
#   dropping every BOTTOM entry for a `T[LR]PLL\dCLK\d` source.
#
# HCLK CLKDIV source (an HCLK block's escape wires 105..112):
#   DEV-017 -- entering only at (54,88) SPINE18, whose CBRIDGEOUT_BOTTOM2 reaches
#   SPINE26, clocked every flip-flop; entering at (54,88) SPINE16 fed the dead
#   CBRIDGEOUT_BOTTOM0 spines, and entering at (54,93) SPINE9 left the whole
#   clock dead in 8 of 8 seeds.  So for a CLKDIV source TOP is dead and
#   SPINE18 / CBRIDGEOUT_BOTTOM2 is the measured entry.
#
# Anything not listed is unmeasured, which is not the same as broken.
MEASURED = {
    # "pll": True/False verdicts for a PLL-sourced clock
    ("pll", "SPINE8", "CBRIDGEOUT_TOP0"): True,     # DEV-009: ran
    ("pll", "SPINE10", "CBRIDGEOUT_TOP2"): True,    # DEV-009: ran
    ("pll", "SPINE16", "CBRIDGEOUT_BOTTOM0"): False,  # DEV-009: silent
    ("pll", "SPINE25", "CBRIDGEOUT_BOTTOM0"): False,  # DEV-009: silent
    ("pll", "SPINE1", "CBRIDGEOUT_BOTTOM0"): False,   # DEV-009: silent
    # "clkdiv": verdicts for an HCLK CLKDIV-sourced clock
    ("clkdiv", "SPINE18", "CBRIDGEOUT_BOTTOM2"): True,  # DEV-017: clocks every flop
    ("clkdiv", "SPINE26", "CBRIDGEOUT_BOTTOM2"): True,  # DEV-017: clocks every flop
    ("clkdiv", "SPINE16", "CBRIDGEOUT_BOTTOM0"): False,  # DEV-017: clocks nothing
    ("clkdiv", "SPINE17", "CBRIDGEOUT_BOTTOM0"): False,  # DEV-017: clocks nothing
    ("clkdiv", "SPINE18", "CBRIDGEOUT_TOP1"): False,     # DEV-017: dead 8 of 8 seeds
}

# Which source a clock is.  `hclk` in this design is the 74.25 MHz pixel clock
# made by a CLKDIV named div5 from the HDMI PLL's 5x output, so it is a CLKDIV
# source; every other clock here comes straight out of a PLL.  A net this tool
# cannot classify is reported as unclassified rather than guessed at.
CLKDIV_SOURCES = {"hclk"}

# Pips this project has measured on its own hardware, which outranks anything
# inherited: the picture on this board syncs and is stable, so whatever the pixel
# clock and the HDMI PLL's input actually route through is known to clock its
# branches.  Recording these stops the gate from refusing a build over a path
# this project has already shown working.  (core-log entry 22, TCL-006.)
OWN_MEASURED = {
    ("clkdiv", "SPINE24", "CBRIDGEOUT_BOTTOM2"): True,   # pixel clock, stable picture
    ("clkdiv", "SPINE25", "CBRIDGEOUT_BOTTOM2"): True,   # pixel clock, stable picture
    ("pll", "SPINE24", "CBRIDGEOUT_BOTTOM0"): True,      # 50 MHz into pll_27; HDMI runs
    ("pll", "SPINE26", "CBRIDGEOUT_TOP0"): True,         # reaches working video logic
    ("pll", "SPINE16", "CBRIDGEOUT_TOP0"): True,         # reaches working video logic
}


def clocks_of(top):
    """Yield (net_name, {(spine, bridge)}) for every clock net in the netlist."""
    netnames = top.get("netnames", {})
    for name, info in netnames.items():
        route = info.get("attributes", {}).get("ROUTING", "")
        if not route or "CBRIDGE" not in route:
            continue
        pips = set()
        # A bridge pip appears as "<x>Y<y>/SPINE<n>/CBRIDGEOUT_<half><k>".
        for m in re.finditer(r"/SPINE(\d+)/(CBRIDGEOUT_(?:TOP|BOTTOM)\d)", route):
            pips.add((f"SPINE{m.group(1)}", m.group(2)))
        if pips:
            yield name, pips


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("routed_json")
    ap.add_argument("--allow-unmeasured", action="store_true",
                    help="report unmeasured pips as warnings instead of failing")
    args = ap.parse_args()

    try:
        with open(args.routed_json) as f:
            design = json.load(f)
    except (OSError, json.JSONDecodeError) as e:
        print(f"cannot read {args.routed_json}: {e}", file=sys.stderr)
        return 2

    modules = design.get("modules", {})
    if not modules:
        print("no modules in the netlist", file=sys.stderr)
        return 2
    # The routed netlist carries one module: the top, flattened.
    top = next(iter(modules.values()))

    dead, unmeasured, good = [], [], []
    found = False
    for name, pips in sorted(clocks_of(top)):
        found = True
        verdicts = []
        src0 = "clkdiv" if name in CLKDIV_SOURCES else "pll"
        for pip in sorted(pips):
            state = OWN_MEASURED.get((src0,) + pip,
                                     MEASURED.get((src0,) + pip, None))
            verdicts.append(f"{pip[0]}/{pip[1]}="
                            f"{'good' if state else 'DEAD' if state is False else 'unmeasured'}")
        src = "clkdiv" if name in CLKDIV_SOURCES else "pll"
        statuses = {OWN_MEASURED.get((src,) + p, MEASURED.get((src,) + p, None))
                    for p in pips}
        line = f"  {name:22s} [{src:6s}] " + ", ".join(verdicts)
        if False in statuses:
            dead.append((name, line))
        elif None in statuses:
            unmeasured.append((name, line))
        else:
            good.append((name, line))
        print(line)

    if not found:
        print("no clock net crosses a bridge pip; nothing to check")
        return 0

    print()
    for name, line in dead:
        print(f"DEAD PIP: {name} crosses a bridge pip measured as clocking nothing",
              file=sys.stderr)
    if dead:
        print("This clock will not reach the flip-flops on those branches; they hold",
              file=sys.stderr)
        print("power-up 0 (TinyNES core-reference DEV-009, DEV-017).", file=sys.stderr)
        return 1

    if unmeasured:
        print(f"{len(unmeasured)} clock(s) on pips never measured on this board.")
        print("A clock on an unmeasured pip may be fine and may be silent; nothing")
        print("has shown it either way.  Measured-good on this board so far:")
        for (src, sp, br) in sorted(OWN_MEASURED):
            print(f"  {src:6s} {sp}/{br}  (this project)")
        for (src, sp, br), ok in sorted(MEASURED.items()):
            if ok:
                print(f"  {src:6s} {sp}/{br}  (TinyNES)")
        if not args.allow_unmeasured:
            print("Refusing the build.  Set TINYSNES_ALLOW_UNMEASURED_CLOCKS=1 to")
            print("proceed anyway, or move the clock onto a measured-good path.",
                  file=sys.stderr)
            return 1
        print("(allowed by --allow-unmeasured)")
        return 0

    print("Every clock is on a measured-good bridge pip.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
