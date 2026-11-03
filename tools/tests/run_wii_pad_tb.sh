#!/usr/bin/env bash
# Build and run the Wii Classic Controller bench: tools/tests/wii_pad_tb.sv.
#
# Answers, without the board, whether fpga/snes/src/wii_pad.sv drives an I2C bus
# correctly enough to wake a controller, read its identity and decode every
# button into this core's 12-bit word.
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
src="$root/fpga/snes"
out="${1:-$root/build/wii_pad_sim}"

mkdir -p "$out"
cd "$out"

echo "=== building Wii pad bench ==="
verilator --binary --timing -j 0 -Wno-fatal -Wno-lint -Wno-UNUSED -Wno-UNDRIVEN \
    -I"$src" -I"$src/src" \
    --top-module wii_pad_tb \
    --Mdir obj_dir \
    -o wii_pad_sim \
    "$src/src/wii_pad.sv" \
    "$root/tools/tests/wii_pad_tb.sv"

echo "=== running ==="
./obj_dir/wii_pad_sim
