#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Lockstep differential bench for the SPC700: this repository's core against
# MiSTer's, on the same random program, compared at every instruction boundary.
# See tools/sim/spc_diff_tb.sv for what is compared and why.
#
#   tools/sim/run_spc_diff.sh                      one run, seed 1
#   tools/sim/run_spc_diff.sh --seed 7 --cycles 400000
#   tools/sim/run_spc_diff.sh --stalls             random RDY wait states
#   tools/sim/run_spc_diff.sh --fill 4c            one opcode, repeated
#   tools/sim/run_spc_diff.sh --sweep 2300         the registration run
#   tools/sim/run_spc_diff.sh --sweep 300 --stalls 300 of them with RDY stalls
#
# The reference (MiSTer's SPC700 at 901a172c, converted by GHDL) is built on the
# first run and cached under build/spc_ref; rebuild it with
# tools/sim/spc_ref/build_ref.sh or force it here with --rebuild.
#
# A sweep runs each seed as an independent program, so it is parallelised:
# --jobs N (default 8) at a time.  Each run is a separate process; the only
# shared state is the compiled bench in a temporary directory.
#
# Needs iverilog and, to build the reference, GHDL from oss-cad-suite.
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
src="$root/fpga/snes/src"
spc="$src/spc700"
ref="$root/build/spc_ref/spc_ref.v"

seed=1
cycles=200000
sweep=0
jobs=8
stalls=0
quiet=0
fill=-1
rebuild=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --seed)    seed="$2"; shift 2 ;;
        --cycles)  cycles="$2"; shift 2 ;;
        --sweep)   sweep="$2"; shift 2 ;;
        --jobs)    jobs="$2"; shift 2 ;;
        --stalls)  stalls=1; shift ;;
        --quiet)   quiet=1; shift ;;
        --fill)    fill="$2"; shift 2 ;;
        --rebuild) rebuild=1; shift ;;
        -h|--help) sed -n '3,22p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) echo "run_spc_diff.sh: unknown option $1" >&2; exit 2 ;;
    esac
done

if [[ $rebuild -eq 1 || ! -f $ref ]]; then
    "$root/tools/sim/spc_ref/build_ref.sh"
fi

out="$(mkdir -p "$root/build/tmp" && mktemp -d "$root/build/tmp/spcdiff.XXXXXX")"
trap 'rm -rf "$out"' EXIT

iverilog -g2012 -I "$spc" -o "$out/tb" -s spc_diff_tb \
    "$root/tools/sim/spc_diff_tb.sv" \
    "$spc/_spc700_package.v" "$spc/addsub.v" "$spc/bcdadj.v" "$spc/muldiv.v" \
    "$spc/alu.v" "$spc/addrgen.v" "$spc/mcode.v" "$spc/spc700.v" \
    "$ref"

# One program.  Prints the bench's own PASS/FAIL/RESULT lines, which the sweep
# counts.  $2 is the RDY-stall flag.
run_one() {
    local s="$1" arg=()
    [[ $2 == "1" ]] && arg=("+stalls=1")
    [[ $fill != "-1" ]] && arg+=("+fill=$fill")
    vvp -n "$out/tb" "+seed=$s" "+cycles=$cycles" "+quiet=$quiet" "${arg[@]}" 2>&1 | \
        grep -E '^(FAIL|PASS|SKIP|DIVERGE|RESULT)'
}

if [[ $sweep -eq 0 ]]; then
    run_one "$seed" "$stalls"
    exit 0
fi

export -f run_one
export out cycles quiet fill

mkdir -p "$out/logs"
for ((s = 1; s <= sweep; s++)); do
    printf '%s\n' "$s"
done | xargs -P "$jobs" -I{} bash -c '
    s={}
    stall=0
    (( s <= '"$stalls"' )) && stall=1
    run_one "$s" "$stall" > "'"$out"'/logs/$s.txt" 2>&1 || true
'

pass=0; fail=0; skip=0; diverge=0; insns=0; cmp_total=0
for ((s = 1; s <= sweep; s++)); do
    f="$out/logs/$s.txt"
    if grep -q '^PASS' "$f" 2>/dev/null; then
        pass=$((pass + 1))
    elif grep -q '^SKIP' "$f" 2>/dev/null; then
        skip=$((skip + 1))
    elif grep -q '^DIVERGE' "$f" 2>/dev/null; then
        diverge=$((diverge + 1))
    else
        fail=$((fail + 1))
        echo "--- seed $s"; grep -E '^(FAIL|RESULT)' "$f" 2>/dev/null | head -3
    fi
    n=$(sed -n 's/^RESULT .*insns=\([0-9]*\).*/\1/p' "$f" 2>/dev/null | head -1)
    c=$(sed -n 's/^RESULT .*cmps=\([0-9]*\).*/\1/p' "$f" 2>/dev/null | head -1)
    insns=$((insns + ${n:-0}))
    cmp_total=$((cmp_total + ${c:-0}))
done

echo "sweep: $pass passed, $fail failed, $skip skipped as too short, $diverge divergent via the known reset defect, $cmp_total instructions compared ($insns retired)"
[[ $fail -eq 0 ]]
