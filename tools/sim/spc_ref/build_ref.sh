#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Build MiSTer's SPC700 as a Verilog reference for the lockstep bench.
#
#   tools/sim/spc_ref/build_ref.sh [outdir]          (default build/spc_ref)
#
#   <out>/spc_ref.v   MiSTer SNES SPC700 at 901a172c (VHDL), converted by GHDL,
#                     module SPC700_ref, with A/X/Y/SP/PSW/PC/last_cycle
#                     exported as DBG_* outputs.  See export_regs.py.
#
#   tools/sim/run_spc_diff.sh rom-ignored --ref build/spc_ref/spc_ref.v ...
#   (run_spc_diff.sh builds this automatically; this script is for rebuilding
#    the reference by hand or pinning a different one.)
#
# Why this exists.  A differential test against a second implementation is the
# only way this project has found SPC700 defects: entry 6 of the log records
# eight of them, each invisible to a bench that agrees with itself.  That bench
# lived in /tmp and was lost with it, so it is rebuilt here as a committed tool
# with its reference generated from a pinned upstream commit.
#
# GHDL needs --latches: AddrGen.vhd's NewAL/NewAH and ALU.vhd's tIntR are
# inferred latches in the original design, and GHDL refuses them by default.
# No file uses both clock edges, so no split pass is needed, unlike the GSU.
#
# The VHDL is fetched, not vendored: MiSTer SNES is GPL-3.0, this repository is
# GPL-3.0-only, and the generated Verilog is a build product under build/, so
# nothing derived is committed.
set -euo pipefail
here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd -- "$here/../../.." && pwd)"
out="$(mkdir -p "${1:-$root/build/spc_ref}" && cd "${1:-$root/build/spc_ref}" && pwd)"
ghdl="${GHDL:-$HOME/oss-cad-suite/bin/ghdl}"
base=https://raw.githubusercontent.com/MiSTer-devel/SNES_MiSTer/901a172c/rtl/SPC700

if [[ ! -x $ghdl ]]; then
    echo "build_ref.sh: no GHDL at $ghdl (set GHDL=...)" >&2
    exit 1
fi

cd "$out"
# Dependency order matters to GHDL: an entity must be analysed before the unit
# that instantiates it.
files=(SPC700_pkg.vhd AddSub.vhd BCDAdj.vhd MulDiv.vhd ALU.vhd AddrGen.vhd MCode.vhd SPC700.vhd)
for f in "${files[@]}"; do
    [[ -f $f ]] || curl -fsSL -o "$f" "$base/$f"
done

rm -f work-obj08.cf
"$ghdl" -a --std=08 -fsynopsys "${files[@]}"
"$ghdl" --synth --std=08 -fsynopsys --latches --out=verilog SPC700 > spc_raw.v 2> synth.err
[[ -s spc_raw.v ]] || { echo "build_ref.sh: GHDL produced no Verilog" >&2; tail -20 synth.err >&2; exit 1; }

python3 "$here/export_regs.py" spc_raw.v spc_ref.v
grep -q '^module SPC700_ref' spc_ref.v || { echo "build_ref.sh: rename failed" >&2; exit 1; }
echo "built $out/spc_ref.v"
