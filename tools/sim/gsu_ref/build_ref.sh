#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Build the two sim-only GSU variants that tools/sim/run_gsu_sim.sh --gsu takes,
# so this repo's SuperFX can be diffed against MiSTer's in the same machine.
#
#   tools/sim/gsu_ref/build_ref.sh [outdir]          (default build/gsu_ref)
#
#   <out>/gsu_ref.v   MiSTer SNES GSU at 901a172c (VHDL), converted by GHDL,
#                     module GSU_ref.  Pair with gsu_ref_wrap.v.
#   <out>/gsu_port.v  this repo's fpga/snes/src/chip/GSU/GSU.v, module renamed
#                     GSU_port.  Pair with gsu_port_wrap.v.
#
# Both wrappers present GSU's port list (TinySNES-only DBG_* outputs tied to 0
# in the reference) and add +rtrace=path +rtracejob=N, which logs R0-R15 on
# every change during GSU start N.  The reference wrapper writes the registers
# R15 first; reverse each line before diffing against the port's trace.
#
#   tools/sim/run_gsu_sim.sh rom.sfc --out build/simB \
#       --gsu build/gsu_ref/gsu_ref.v --gsu tools/sim/gsu_ref/gsu_ref_wrap.v ...
#
# GHDL's synthesis rejects a process that uses both rising_edge and
# falling_edge, which GSU.vhd does three times.  split.py splits each into a
# falling and a rising process; no signal is driven on both edges, and the
# variables read across edges become _XS shadow signals.  Its line numbers are
# for 901a172c only.  dpram_difclk.vhd stands in for MiSTer's altsyncram.
# gsudis.py disassembles GSU code: gsudis.py rom.sfc bank start end (hex).
set -euo pipefail
here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd -- "$here/../../.." && pwd)"
out="$(mkdir -p "${1:-$root/build/gsu_ref}" && cd "${1:-$root/build/gsu_ref}" && pwd)"
ghdl="${GHDL:-$HOME/oss-cad-suite/bin/ghdl}"
base=https://raw.githubusercontent.com/MiSTer-devel/SNES_MiSTer/901a172c/rtl/chip/GSU

cd "$out"
for f in GSU.vhd GSU_PKG.vhd; do
    [[ -f $f ]] || curl -fsSL -o "$f" "$base/$f"
done
cp "$here/dpram_difclk.vhd" .
python3 "$here/split.py"
"$ghdl" -a --std=08 -fsynopsys dpram_difclk.vhd GSU_PKG.vhd GSU_split.vhd
"$ghdl" --synth --std=08 -fsynopsys --out=verilog GSU > gsu_ref.v 2> synth.err
sed -i 's/^module GSU$/module GSU_ref/' gsu_ref.v
grep -q '^module GSU_ref' gsu_ref.v || { echo "rename to GSU_ref failed" >&2; exit 1; }
sed 's/^module GSU(/module GSU_port(/' "$root/fpga/snes/src/chip/GSU/GSU.v" > gsu_port.v
echo "built $out/gsu_ref.v and $out/gsu_port.v"
