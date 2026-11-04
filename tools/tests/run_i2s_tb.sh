#!/usr/bin/env bash
# Build and run the I2S bench: tools/tests/i2s_tb.sv.
#
# Checks the three clocks i2s_out generates, the shape of the I2S frame, and that
# the 32,180 -> 48,828 resampler preserves a constant and interpolates a step.
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
src="$root/fpga/snes"
out="${1:-$root/build/i2s_sim}"

mkdir -p "$out"
cd "$out"

echo "=== building I2S bench ==="
verilator --binary --timing -j 0 -Wno-fatal -Wno-lint -Wno-UNUSED -Wno-UNDRIVEN \
    --top-module i2s_tb \
    --Mdir obj_dir -o i2s_sim \
    "$src/src/i2s_out.sv" \
    "$src/src/CEGen.v" \
    "$root/tools/tests/i2s_tb.sv"

echo "=== running ==="
./obj_dir/i2s_sim
