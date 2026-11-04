#!/usr/bin/env bash
# Bench for the debug register endpoint (iosys_bl616 frame 0x10 + tinysnes_dbg).
# Prints PASS on success.  Needs iverilog.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
src="$root/fpga/snes/src"
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT
iverilog -g2012 -DSIM -o "$out/tb" -s dbg_link_tb \
    "$root/tools/sim/dbg_link_tb.sv" \
    "$src/iosys/iosys_bl616.v" "$src/iosys/uart_fixed.v" "$src/tinysnes_dbg.v"
vvp -n "$out/tb"
