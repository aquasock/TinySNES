#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
#
# Build and run the HDMI audio resampler bench (tools/sim/hdmi_resample_tb.sv),
# then check its output with tools/sim/hdmi_resample_model.py.
#
#   tools/sim/run_hdmi_resample.sh [+secs=N] [+ppm=N] [+freq=N] [--min-snr DB]
#
# The bench prints overflows, underruns, whole seconds that were not exactly
# 48,000 audio periods and CTS windows that were not exactly 74,250 pixel
# clocks (all must be 0); the model checks every word bit for bit and the
# SNR against the ideal sine.
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
out="${TINYSNES_HDMI_AUDIO:-$root/build/hdmi_resample}"
mkdir -p "$out"
cd "$out"
plus=() model=()
freq=1000
while [[ $# -gt 0 ]]; do
    case "$1" in
        +freq=*) freq="${1#+freq=}"; plus+=("$1") ;;
        +*) plus+=("$1") ;;
        --min-snr) model+=("$1" "$2"); shift ;;
        *) echo "unknown argument $1" >&2; exit 2 ;;
    esac
    shift
done
verilator --binary --timing -j 0 -Wno-fatal -Wno-lint -Wno-UNUSED \
    --top-module hdmi_resample_tb -Mdir obj_dir \
    "$root/fpga/snes/src/dual_clk_fifo.v" "$root/fpga/snes/src/hdmi_audio_resample.v" \
    "$root/tools/sim/hdmi_resample_tb.sv" >build.log 2>&1 \
    || { tail -n 30 build.log; exit 1; }
./obj_dir/Vhdmi_resample_tb "${plus[@]}" +dump="$out/resample.dump" | tee run.log
grep -qx PASS run.log
python3 "$root/tools/sim/hdmi_resample_model.py" "$out/resample.dump" "$freq" 32127 "${model[@]}"
