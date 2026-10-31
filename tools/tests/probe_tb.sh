#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Simulate the diagnostic samplers in fpga/snes/src/snestang_top.v.
#
#   tools/tests/probe_tb.sh            # every probe, then the memory benches
#   tools/tests/probe_tb.sh fetch      # TINYSNES_FETCH_PROBE only
#   tools/tests/probe_tb.sh cpu        # TINYSNES_CPU_PROBE only
#   tools/tests/probe_tb.sh trace      # TINYSNES_TRACE_PROBE only
#   tools/tests/probe_tb.sh apu        # TINYSNES_APU_PROBE only
#   tools/tests/probe_tb.sh aram       # the ARAM self-test controller only
#   tools/tests/probe_tb.sh sram       # the SDRAM self-test controller only
#
# The benches need the sampler text itself, so each block is extracted from the
# shipping source into a temporary file rather than retyped: a copy would drift,
# and a probe that measures the wrong instant has already reported a false result
# once.  The stimulus gives every field a value that could not be confused with
# another, so a wrong offset or a wrong register shows up as a mismatch.
#
# Requires iverilog.  Exit status is 0 only when every bench passes.
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
src="$root/fpga/snes/src/snestang_top.v"
which="${1:-all}"

command -v iverilog >/dev/null || { echo "iverilog is required" >&2; exit 2; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# extract <define> <out>: the block belonging to that define, verbatim.  Both
# probe blocks are single-level, so the first matching `endif closes the block.
extract() {
    local define="$1" out="$2"
    awk -v want="\`ifdef $define" '$0==want{f=1} f{print} f&&/^`endif$/{exit}' "$src" > "$out"
    [[ -s "$out" ]] || { echo "no $define block found in $src" >&2; exit 1; }
    grep -q 'fp_bus' "$out" || { echo "$define block is not a probe sampler" >&2; exit 1; }
}

run_one() {
    local define="$1" bench="$2" dest="$3"
    echo "== $define =="
    extract "$define" "$tmp/$dest.v"
    iverilog -g2012 -D"$define" -I "$tmp" -o "$tmp/$dest.vvp" "$root/tools/tests/$bench"
    "$tmp/$dest.vvp"
}

# The memory self-tests are whole modules, not samplers lifted out of the top
# level, so their benches compile the shipping source directly.
run_module() {
    local module="$1" bench="$2" dest="$3"
    echo "== $module =="
    iverilog -g2012 -o "$tmp/$dest.vvp" "$root/tools/tests/$bench" "$root/fpga/snes/src/$module"
    "$tmp/$dest.vvp"
}

case "$which" in
    # TINYSNES_CPU_PROBE and TINYSNES_LIVE_PROBE both select the one CPU
    # sampler, so its block is guarded by TINYSNES_CPU_SAMPLER and that is what
    # the bench compiles and extracts.
    all)   run_one TINYSNES_FETCH_PROBE  fetch_probe_tb.sv fetch_sampler
           run_one TINYSNES_CPU_SAMPLER  cpu_probe_tb.sv   cpu_sampler
           run_one TINYSNES_TRACE_PROBE  trace_probe_tb.sv trace_sampler
           run_one TINYSNES_APU_PROBE    apu_probe_tb.sv   apu_sampler
           run_module aram_bist.v aram_bist_tb.sv aram_tb ;;
    fetch) run_one TINYSNES_FETCH_PROBE  fetch_probe_tb.sv fetch_sampler ;;
    cpu)   run_one TINYSNES_CPU_SAMPLER  cpu_probe_tb.sv   cpu_sampler ;;
    trace) run_one TINYSNES_TRACE_PROBE  trace_probe_tb.sv trace_sampler ;;
    apu)   run_one TINYSNES_APU_PROBE    apu_probe_tb.sv   apu_sampler ;;
    aram)  run_module aram_bist.v aram_bist_tb.sv aram_tb ;;
    *)     echo "usage: $0 [all|fetch|cpu|trace|apu|aram]" >&2; exit 2 ;;
esac
