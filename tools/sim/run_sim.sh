#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Build and run the full-core bench in tools/sim/snes_tb.sv.
#
#   tools/sim/run_sim.sh [--cycles N] [--lat N] [--vcd] [--stoplow N] [--iverilog]
#
# The bench instantiates the real SNES.v with behavioural memories, so it needs
# only the core's own sources: not the board top, not the PLLs, not the HDMI
# stack, not the SDRAM controller.  The file list below is the core subset of the
# one in tools/build_tinysnes.sh, kept in step with it by hand because the two
# build different things and a shared list would have to carry both sets of
# excludes.
#
# Verilator is the default because a boot is hundreds of thousands of master
# clocks; --iverilog runs the same bench under Icarus, which is slower but
# handles $dumpvars over the whole hierarchy without the public-signal plumbing.
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
src="$root/fpga/snes/src"
out="${SIM_BUILD_DIR:-$root/build/sim}"
suite="${OSS_CAD_SUITE:-$HOME/oss-cad-suite}"
rom="${ROM:-/tmp/zelda.smc}"

cycles=400000
lat=0
wlat=0
nowait=0
stoplow=0
vcd=0
engine=verilator
defines=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --cycles)  cycles="$2"; shift 2 ;;
        --lat)     lat="$2"; shift 2 ;;
        --wlat)    wlat="$2"; shift 2 ;;
        --nowait)  nowait="$2"; shift 2 ;;
        --stoplow) stoplow="$2"; shift 2 ;;
        --vcd)     vcd=1; shift ;;
        --iverilog) engine=iverilog; shift ;;
        --define)  defines+=("-D$2"); shift 2 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

[[ -f "$rom" ]] || { echo "missing image: $rom" >&2; exit 2; }
mkdir -p "$out"

# The cartridge is loaded through $readmemh, which wants one hex byte per line.
# Regenerating it only when the image changes keeps a run cheap.
# Keyed on the image's basename so two images can be compared without one
# silently reusing the other's converted file.
hex="$out/rom-$(basename "$rom" .smc).hex"
if [[ ! -f "$hex" || "$rom" -nt "$hex" ]]; then
    echo "converting $rom to $hex"
    od -An -v -tx1 "$rom" | tr -s ' ' '\n' | grep -v '^$' > "$hex"
fi

# Packages first: Verilator wants them parsed before the modules that import
# them, and `common.sv` holds package P65816 while `_spc700_package.v` holds
# package spc700.
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
)
for f in "${sources[@]}"; do
    [[ -f "$f" ]] || { echo "missing source: $f" >&2; exit 2; }
done

args=(+hex="$hex" +cycles="$cycles" +lat="$lat" +wlat="$wlat" +nowait="$nowait" +stoplow="$stoplow"
      +trace="$out/pc.trace" +oplog="$out/op.log" +pplog="$out/ppu.log" +spclog="$out/spc.log" +apulog="$out/apu.log" +wrlog="$out/wr.log" +vidlog="$out/vid.log" +vramlog="$out/vram.log" +buslog="$out/bus.log" +frame="$out/frame.ppm" +rom="$rom")
[[ "$vcd" == 1 ]] && args+=("+vcd=$out/waves.vcd")

cd "$out"

if [[ "$engine" == iverilog ]]; then
    incs=(-I "$src" -I "$src/65C816" -I "$src/spc700" -I "$src/hdmi")
    iverilog -g2012 -DVERILATOR -DNO_ICE40_DEFAULT_ASSIGNMENTS "${defines[@]}" \
             "${incs[@]}" -o sim.vvp "$root/tools/sim/snes_tb.sv" "${sources[@]}"
    set +e
    vvp sim.vvp "${args[@]}"
    rc=$?
    set -e
else
    # --binary makes the run self-contained: Verilator generates, compiles and
    # executes.  -DVERILATOR selects the behavioural CGRAM/OAM models the
    # sources already carry, which are the ones the upstream author wrote for
    # exactly this.
    verilator --binary -j 0 -Wno-fatal -DVERILATOR "${defines[@]}" \
        -I"$src" -I"$src/65C816" -I"$src/spc700" \
        --top-module snes_tb \
        --Mdir obj_dir \
        -o sim \
        "$root/tools/sim/snes_tb.sv" "${sources[@]}"
    set +e
    ./obj_dir/sim "${args[@]}"
    rc=$?
    set -e
fi

echo "exit=$rc; trace: $out/pc.trace"
exit 0
