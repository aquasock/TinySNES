#!/usr/bin/env bash
# Build and run the master-volume bench: tools/tests/audio_volume_tb.sv.
#
# Instantiates fpga/snes/src/audio_volume.v, the module snestang_top puts
# between the S-DSP and both of its consumers.  The bench's strongest check is
# that gain 256 is a bit-exact pass-through over every one of the 65536
# samples, because that is what makes the feature a no-op for a player who
# leaves the slider at 100 percent.
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
src="$root/fpga/snes"
out="${1:-$root/build/volume_sim}"

mkdir -p "$out"
cd "$out"

echo "=== building volume bench ==="
verilator --binary --timing -j 0 -Wno-fatal -Wno-lint -Wno-UNUSED -Wno-UNDRIVEN \
    --top-module audio_volume_tb \
    --Mdir obj_dir \
    -o volume_sim \
    "$src/src/audio_volume.v" \
    "$root/tools/tests/audio_volume_tb.sv"

echo "=== running ==="
./obj_dir/volume_sim
