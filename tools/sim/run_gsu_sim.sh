#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Build and run the coprocessor bench in tools/sim/gsu_tb.sv.
#
# This is run_sim.sh's sibling, not a replacement: run_sim.sh drives snes_tb.sv,
# which instantiates SNES.v and therefore has no cartridge mapper and no GSU.
# This one instantiates main.v -- the real mapper with USE_GSU enabled -- so the
# coprocessor can be observed directly.  The source list is run_sim.sh's plus
# main.v and chip/GSU/.
#
#   tools/sim/run_gsu_sim.sh [rom] [options]
#
#   tools/sim/run_gsu_sim.sh "/tmp/fox/Star Fox (USA) (Rev 2).sfc" --cycles 2000000 --vcd
#
# Options:
#   --cycles N     master clocks to run (default 400000)
#   --vcd          dump waves to <out>/waves.vcd
#   --out DIR      output directory (default build/gsusim)
#   --define X     extra Verilator -D define, repeatable
#   --lat N        cartridge read latency in mclk for every master (default 0)
#   --glat N       latency for GSU-initiated reads only, overriding --lat for those
#   --bwlat N      BSRAM acknowledge latency in clk (default 0 = never busy)
#   --romtype N    mapper chip bits after the header arrives (default 112 = $70,
#                  GSU; use 32 = $20 for a plain LoROM control run)
#
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
src="$root/fpga/snes/src"
rom="${1:?usage: run_gsu_sim.sh <rom.sfc> [--cycles N] [--vcd] [--out DIR]}"
shift || true

cycles=400000
vcd=0
rt=112
lat=0
glat=-1
bwlat=0
out="$root/build/gsusim"
defines=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --cycles) cycles="$2"; shift 2 ;;
        --vcd)    vcd=1; shift ;;
        --out)    out="$2"; shift 2 ;;
        --define) defines+=("-D$2"); shift 2 ;;
    --romtype) rt="$2"; shift 2 ;;
    --lat) lat="$2"; shift 2 ;;
    --glat) glat="$2"; shift 2 ;;
    --bwlat) bwlat="$2"; shift 2 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

[[ -f "$rom" ]] || { echo "no such rom: $rom" >&2; exit 2; }
# Resolve to absolute BEFORE cd'ing into it.  A relative --out put the generated
# hex path and the working directory in conflict, so $readmemh silently found
# nothing, the ROM model returned zeros and the CPU read a reset vector of
# $0000.  The default out was absolute, which is why only runs given --out failed.
out="$(cd -- "$(dirname -- "$out")" 2>/dev/null && pwd)/$(basename -- "$out")"
mkdir -p "$out"

# One byte per line, which is what $readmemh wants for a byte array.
hex="$out/rom-$(basename "$rom" .sfc).hex"
if [[ ! -f "$hex" || "$rom" -nt "$hex" ]]; then
    echo "converting $rom to $hex"
    od -An -v -tx1 "$rom" | tr -s ' ' '\n' | grep -v '^$' > "$hex"
fi

# Packages first: Verilator wants them parsed before the modules that import them.
sources=(
    "$src/65C816/common.sv"
    "$src/spc700/_spc700_package.v"
    "$src/SNES.v"
    "$src/cpu.v"
    "$src/ppu.v"
    "$src/smp.v"
    "$src/dsp.v"
    "$src/swram.v"
    "$src/ppucgram.v"
    "$src/ppuoam.v"
    "$src/ppuhoam.v"
    "$src/65C816/adder4.v"
    "$src/65C816/bit_adder.v"
    "$src/65C816/ALU.v"
    "$src/65C816/AddSubBCD.v"
    "$src/65C816/AddrGen.v"
    "$src/65C816/BCDAdder.v"
    "$src/65C816/P65C816.v"
    "$src/65C816/mcode.sv"
    "$src/CEGen.v"
    "$src/spc700/alu.v"
    "$src/spc700/addsub.v"
    "$src/spc700/addrgen.v"
    "$src/spc700/bcdadj.v"
    "$src/spc700/muldiv.v"
    "$src/spc700/mcode.v"
    "$src/spc700/spc700.v"
    "$src/chip/DSP/DSP_LHRomMap.v"
    "$src/chip/DSP/DSPn.v"
    "$src/chip/DSP/OBC1.v"
    "$src/chip/DSP/SRTC.v"
    "$src/chip/DSP/dsp_data_ram.v"
    "$src/chip/GSU/GSU_PKG.v"
    "$src/chip/GSU/GSU.v"
    "$src/chip/GSU/GSUMap.v"
    "$src/main.v"
)
for f in "${sources[@]}"; do
    [[ -f "$f" ]] || { echo "missing source: $f" >&2; exit 2; }
done

args=(+hex="$hex" +cycles="$cycles" +trace="$out/gsu.trace" +frame="$out/frame.ppm" +romtype="$rt" +lat="$lat" +glat="$glat" +bwlat="$bwlat")
[[ "$vcd" == 1 ]] && args+=("+vcd=$out/waves.vcd")

cd "$out"
# DSPn.v loads its microcode with $readmemh and a bare filename, so the file has
# to be in the working directory the binary runs from.  On the board the build
# supplies -I; here it is a copy.
cp -f "$src"/chip/DSP/*.hex "$out/" 2>/dev/null || true
verilator --binary -j 0 -Wno-fatal -DVERILATOR "${defines[@]}" \
    -I"$src" -I"$src/65C816" -I"$src/spc700" -I"$src/chip/GSU" -I"$src/chip/DSP" \
    --top-module gsu_tb_top \
    --Mdir obj_dir \
    -o sim \
    "$root/tools/sim/gsu_tb_top.sv" "$root/tools/sim/gsu_tb.sv" "${sources[@]}"
./obj_dir/sim "${args[@]}"
echo "trace: $out/gsu.trace"
