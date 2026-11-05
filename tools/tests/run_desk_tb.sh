#!/usr/bin/env bash
# Build and run the TinyDesk bench: tools/tests/desk_tb.sv.
#
# snes2hdmi and desk_layer against the HDMI stub's raster; whole frames of the
# desk are compared pixel for pixel with a model of the same cells and font.
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
src="$root/fpga/snes"
out="${1:-$root/build/desk_sim}"

mkdir -p "$out"
cd "$out"

echo "=== building desk bench ==="
verilator --binary --timing -j 0 -Wno-fatal -Wno-lint -Wno-UNUSED -Wno-UNDRIVEN \
    -DTINYSNES_RGB_TAP \
    -DTINYSNES_DESK_FONT="\"$src/src/desk_font.hex\"" \
    -I"$src" -I"$src/src" \
    --top-module desk_tb \
    --Mdir obj_dir \
    -o desk_sim \
    "$root/tools/tests/hdmi_stub.sv" \
    "$src/src/snes2hdmi.v" \
    "$src/src/desk_layer.v" \
    "$root/tools/tests/desk_tb.sv"

echo "=== running ==="
./obj_dir/desk_sim
