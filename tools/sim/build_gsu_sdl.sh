#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Build the live-window coprocessor bench (tools/sim/gsu_tb.sv + sim_main.cpp).
#
# run_gsu_sim.sh builds the same design headless and non-interactive; this one
# links SDL so the PPU's output can be watched on a desktop while the GSU state
# is printed beside it.  Keeping the build here rather than in a scratch
# directory matters: the first two copies of this script lived under /tmp, which
# is tmpfs on the development machine, and a reboot deleted both of them.
#
#   tools/sim/build_gsu_sdl.sh            # builds build/gsusdl/obj_dir/Vgsu_tb
#
# Then, from build/gsusdl:
#
#   ./obj_dir/Vgsu_tb +hex=fox.hex +romtype=112 +cycles=60000000
#
# IMPORTANT, learned the hard way: never redirect this program's output
# unfiltered into a file under /tmp.  /tmp is RAM.  A run whose output was
# written there produced about six gigabytes and the machine had to be powered
# off.  Use +cycles to bound the run, and pipe through grep into a file on disk.
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
src="$root/fpga/snes/src"
out="${TINYSNES_SDL_OUT:-$root/build/gsusdl}"
mkdir -p "$out"

cp -f "$src"/chip/DSP/*.hex "$out"/ 2>/dev/null || true

sources=(
  "$src/65C816/common.sv" "$src/spc700/_spc700_package.v"
  "$src/SNES.v" "$src/cpu.v" "$src/ppu.v" "$src/smp.v" "$src/dsp.v" "$src/swram.v"
  "$src/ppucgram.v" "$src/ppuoam.v" "$src/ppuhoam.v"
  "$src/65C816/adder4.v" "$src/65C816/bit_adder.v" "$src/65C816/ALU.v"
  "$src/65C816/AddSubBCD.v" "$src/65C816/AddrGen.v" "$src/65C816/BCDAdder.v"
  "$src/65C816/P65C816.v" "$src/65C816/mcode.sv" "$src/CEGen.v"
  "$src/spc700/alu.v" "$src/spc700/addsub.v" "$src/spc700/addrgen.v"
  "$src/spc700/bcdadj.v" "$src/spc700/muldiv.v" "$src/spc700/mcode.v" "$src/spc700/spc700.v"
  "$src/chip/DSP/DSP_LHRomMap.v" "$src/chip/DSP/DSPn.v" "$src/chip/DSP/OBC1.v"
  "$src/chip/DSP/SRTC.v" "$src/chip/DSP/dsp_data_ram.v"
  "$src/chip/GSU/GSU_PKG.v" "$src/chip/GSU/GSU.v" "$src/chip/GSU/GSUMap.v"
  "$src/main.v"
)

cd "$root"
verilator --cc --exe --build -j 0 -Wno-fatal --no-timing -DVERILATOR \
  -I"$src" -I"$src/65C816" -I"$src/spc700" -I"$src/chip/GSU" -I"$src/chip/DSP" \
  --top-module gsu_tb \
  --Mdir "$out/obj_dir" \
  -CFLAGS "$(pkg-config --cflags sdl2)" \
  -LDFLAGS "$(pkg-config --libs sdl2)" \
  tools/sim/gsu_tb.sv tools/sim/sim_main.cpp "${sources[@]}"

echo "built: $out/obj_dir/Vgsu_tb"
