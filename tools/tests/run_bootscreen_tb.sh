#!/usr/bin/env bash
# Build and run the boot-screen bench: tools/tests/bootscreen_tb.sv.
#
# Answers one question without the board: when no cartridge image has landed,
# does snes2hdmi draw the eight colour bars the sibling cores draw, and does it
# stop drawing them once an image is loaded?
#
# Only snes2hdmi and the HDMI stub are compiled -- the boot screen depends on the
# raster position and on `rom_loaded`, not on the SNES machine -- so the build is
# seconds rather than the minutes a whole-core bench costs.
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
src="$root/fpga/snes"
out="${1:-$root/build/bootscreen_sim}"

mkdir -p "$out"
cd "$out"

echo "=== building boot-screen bench ==="
verilator --binary --timing -j 0 -Wno-fatal -Wno-lint -Wno-UNUSED -Wno-UNDRIVEN \
    -DTINYSNES_RGB_TAP \
    -DTINYSNES_DESK_FONT="\"$src/src/desk_font.hex\"" \
    -I"$src" -I"$src/src" \
    --top-module bootscreen_tb \
    --Mdir obj_dir \
    -o bootscreen_sim \
    "$root/tools/tests/hdmi_stub.sv" \
    "$src/src/snes2hdmi.v" \
    "$src/src/desk_layer.v" \
    "$root/tools/tests/bootscreen_tb.sv"

echo "=== running ==="
./obj_dir/bootscreen_sim
