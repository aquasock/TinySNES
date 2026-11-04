#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Build and run the HDMI audio clock bench (tools/sim/hdmi_audio_tb.sv).
#
#   tools/sim/run_hdmi_audio.sh [+secs=N] [+ppm=N]
#
# Prints overflows, underruns and dropped or repeated samples (all must be 0),
# and the FIFO level and audio clock rate ranges.
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
out="${TINYSNES_HDMI_AUDIO:-$root/build/hdmi_audio}"
mkdir -p "$out"

cd "$out"
verilator --binary --timing -j 0 -Wno-fatal -Wno-lint -Wno-UNUSED \
    --top-module hdmi_audio_tb -Mdir obj_dir \
    "$root/fpga/snes/src/dual_clk_fifo.v" "$root/fpga/snes/src/hdmi_audio_clock.v" \
    "$root/tools/sim/hdmi_audio_tb.sv" >build.log 2>&1 \
    || { tail -n 30 build.log; exit 1; }
./obj_dir/Vhdmi_audio_tb "$@"
