#!/usr/bin/env bash
# Build and run the button-path bench: tools/tests/padpath_tb.sv.
#
# Covers what wii_pad_tb does not: controller_adapter and the SNES controller
# serial protocol, i.e. whether a pressed button actually reaches the wire in
# the slot the console expects, with the right polarity.
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
src="$root/fpga/snes"
out="${1:-$root/build/padpath_sim}"

mkdir -p "$out"
cd "$out"

echo "=== building button-path bench ==="
verilator --binary --timing -j 0 -Wno-fatal -Wno-lint -Wno-UNUSED -Wno-UNDRIVEN \
    -I"$src" -I"$src/src" \
    --top-module padpath_tb \
    --Mdir obj_dir \
    -o padpath_sim \
    "$src/src/wii_pad.sv" \
    "$src/src/controller_adapter.sv" \
    "$root/tools/tests/padpath_tb.sv"

echo "=== running ==="
./obj_dir/padpath_sim
