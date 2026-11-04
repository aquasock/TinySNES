#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Build and run the standalone Pmod resampler bench (tools/sim/i2s_out_tb.sv).
#
#   tools/sim/run_i2s_out.sh [+secs=N] [+nopause] [+out=FILE]
#
# Writes one interpolated left sample per output frame to +out (default
# build/i2s_out/i2s_out.txt) and prints FIFO underruns and overflows.
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
out="${TINYSNES_I2S_OUT:-$root/build/i2s_out}"
mkdir -p "$out"

cd "$out"
verilator --binary --timing -j 0 -Wno-fatal -Wno-lint -Wno-UNUSED \
    --top-module i2s_out_tb -Mdir obj_dir \
    "$root/fpga/snes/src/i2s_out.sv" "$root/tools/sim/i2s_out_tb.sv" >build.log 2>&1 \
    || { tail -n 30 build.log; exit 1; }
args=("$@")
[[ " ${args[*]-} " == *" +out="* ]] || args+=("+out=$out/i2s_out.txt")
./obj_dir/Vi2s_out_tb "${args[@]}"
