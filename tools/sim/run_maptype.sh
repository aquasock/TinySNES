#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Run the cartridge-layout harness: which mapper does a header select, and what
# cartridge offset does that produce for a given CPU address?
#
#   tools/sim/run_maptype.sh
#
# Why this exists: the answer to "which games does this core not support" was
# first given from reading DSP_LHRomMap.v by eye, and the mechanism stated was
# wrong -- the layout is chosen by MAP_CTRL[1:0], not MAP_CTRL[3].  Reading by
# eye has produced several wrong statements in this project.  This harness asks
# the RTL directly: it feeds smc_parser the 64-byte header for a map byte, takes
# the rom_type it produces, then drives the real DSP_LHRomMap with that rom_type
# and prints the cartridge offset it computes.
#
# The harness resets the parser before each header, mirroring snestang_top's
# resetn & ~(loading & ~loading_r): without that the parser latches
# header_finished after the first pass and every later map byte reads back as
# the first one.
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
src="$root/fpga/snes/src"
out="${TINYSNES_MAPTYPE_OUT:-$root/build/maptype}"
mkdir -p "$out"

cd "$out"
verilator --binary --timing -j 0 -Wno-fatal -Wno-lint -Wno-UNUSED -Wno-UNDRIVEN \
    -I"$src" -I"$src/chip/DSP" \
    --top-module maptype_tb \
    --Mdir obj_dir -o maptype \
    "$root/tools/sim/maptype_tb.sv" \
    "$src/smc_parser.v" "$src/CEGen.v" \
    "$src/chip/DSP/DSP_LHRomMap.v" "$src/chip/DSP/OBC1.v" "$src/chip/DSP/SRTC.v"

./obj_dir/maptype
