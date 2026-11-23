#!/usr/bin/env bash
# Bench for iosys_bl616's pad frames: 0x21 out, 0x09 in, and Bluetooth pad 1
# in the HOME gestures (tools/sim/pad_link_tb.sv).  Prints PASS on success.
# Needs iverilog.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
src="$root/fpga/snes/src"
out="$(mkdir -p "$root/build/tmp" && mktemp -d "$root/build/tmp/padlink.XXXXXX")"
trap 'rm -rf "$out"' EXIT
iverilog -g2012 -DSIM -o "$out/tb" -s pad_link_tb \
    "$root/tools/sim/pad_link_tb.sv" \
    "$src/iosys/iosys_bl616.v" "$src/iosys/uart_fixed.v"
vvp -n "$out/tb"
