#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Build and run the board-level bench: snestang_top + the real SDRAM controller
# + a modelled SDRAM part.
#
#   tools/sim/run_board_sim.sh "<rom.sfc>" [options]
#
# Options:
#   --frames N     stop after N rendered frames and write a PPM (default 60)
#   --maxcyc N     hard bound in sys_clk (50 MHz) cycles (default 100000000 = 2 s)
#   --out DIR      output directory (default build/boardsim)
#   --arg +X       pass a plusarg to the bench, e.g. --arg +byteclk=4 to load
#                  27x faster than the board's ~2 Mbaud (repeatable)
#
# Why this exists: every earlier bench in this project instantiates `main` or
# `SNES` with ideal memory arrays, so the SDRAM controller, the second clock
# domain and the req/ack toggle handshakes -- the layer where a board-only fault
# must live -- were absent from every simulation this project has run (core-log
# entry 72).  This one instantiates the board's own top level.
#
# The configuration defines are passed on the command line deliberately:
# Verilator, like the yosys flow before core-log entry 73, compiles each input
# file as its own unit, so the `define`s in fpga/snes/config.v do NOT reach
# snestang_top.v.  That is the defect entry 73 found and fixed in the
# synthesis flow with --single-unit; Verilator has no equivalent switch, so
# the defines are repeated here.  They are the same three the board build
# resolves from config.v.
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
src="$root/fpga/snes"

rom="${1:?usage: run_board_sim.sh <rom.sfc> [--frames N] [--maxcyc N] [--out DIR] [--arg +X]...}"
shift || true

frames=60
maxcyc=100000000
out="$root/build/boardsim"
extra=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --frames) frames="$2"; shift 2 ;;
        --maxcyc) maxcyc="$2"; shift 2 ;;
        --out)    out="$2"; shift 2 ;;
        --arg)    extra+=("$2"); shift 2 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

[[ -f "$rom" ]] || { echo "no such rom: $rom" >&2; exit 2; }
# Resolve before cd'ing, for the reason run_gsu_sim.sh records: a relative path
# made $readmemh fail silently and the ROM read back as zeros.
out="$(cd -- "$(dirname -- "$out")" 2>/dev/null && pwd)/$(basename -- "$out")"
mkdir -p "$out"

hex="$out/rom.hex"
if [[ ! -f "$hex" || "$rom" -nt "$hex" ]]; then
    echo "converting $rom to $hex"
    od -An -v -tx1 "$rom" | tr -s ' ' '\n' | grep -v '^$' > "$hex"
fi
romlen=$(stat -c %s "$rom")

sources=(
    # Packages first, in dependency order: Verilator parses files in the order
    # given and ALU.v / P65C816.v import P65816 at their first line.
    "$src/config.v"
    "$src/src/65C816/common.sv" "$src/src/spc700/_spc700_package.v"
    "$src/src/65C816/adder4.v" "$src/src/65C816/bit_adder.v" "$src/src/65C816/ALU.v"
    "$src/src/65C816/AddSubBCD.v" "$src/src/65C816/AddrGen.v" "$src/src/65C816/BCDAdder.v"
    "$src/src/65C816/P65C816.v" "$src/src/65C816/mcode.sv"
    "$src/src/CEGen.v" "$src/src/cpu.v" "$src/src/smp.v" "$src/src/ppu.v"
    "$src/src/dsp.v" "$src/src/swram.v"
    "$src/src/spc700/alu.v" "$src/src/spc700/addsub.v" "$src/src/spc700/addrgen.v"
    "$src/src/spc700/bcdadj.v" "$src/src/spc700/muldiv.v" "$src/src/spc700/mcode.v"
    "$src/src/spc700/spc700.v"
    "$src/src/chip/DSP/DSP_LHRomMap.v" "$src/src/chip/DSP/DSPn.v" "$src/src/chip/DSP/OBC1.v"
    "$src/src/chip/DSP/SRTC.v" "$src/src/chip/DSP/dsp_data_ram.v"
    "$src/src/chip/GSU/GSU_PKG.v" "$src/src/chip/GSU/GSU.v" "$src/src/chip/GSU/GSUMap.v"
    "$src/src/main.v"
    "$src/src/SNES.v" "$src/src/ppucgram.v" "$src/src/ppuhoam.v" "$src/src/ppuoam.v"
    "$src/src/dual_clk_fifo.v" "$src/src/vram.v" "$src/src/vram_spb.v"
    "$src/src/gowin_dpb_cgram.v" "$src/src/gowin_dpb_hoam.v" "$src/src/gowin_dpb_oam.v"
    "$src/src/iosys/gowin_dpb_menu.v" "$src/src/iosys/textdisp.v"
    "$src/src/iosys/uart_fractional.v" "$src/src/iosys/uart_fixed.v" "$src/src/iosys/crc16.v"
    "$src/src/controller_adapter.sv"
    "$src/src/smc_parser.v" "$src/src/sdram_cl2_2ch.v"
    "$src/src/sdram_bist.v" "$src/src/aram_bist.v" "$src/src/wram_bist.v"
    "$src/src/rom_stability.v" "$src/src/rom_probe.v"
    "$src/src/snes2hdmi.v" "$src/src/snestang_top.v" "$src/src/tinysnes_dbg.v"
    "$src/pll/gowin_pll_27.v" "$src/pll/gowin_pll_hdmi.v" "$src/pll/gowin_pll_snes.v"
)

# Simulation-only replacements and additions.  hdmi_stub.sv stands in for
# hdmi/*.sv (the OSER10 serialiser cannot run here and is the one part of the
# video path already proven on hardware); gowin_sim.sv models the primitives;
# sim_sdram.sv is the part; test_loader.sv is the embedded-ROM loader that
# snestang_top's `ifdef VERILATOR branch instantiates but that had no
# definition in this tree.
sim=(
    "$root/tools/tests/hdmi_stub.sv"
    "$root/tools/sim/gowin_sim.sv"
    "$root/tools/sim/sim_sdram.sv"
    "$root/tools/sim/test_loader.sv"
    "$root/tools/sim/board_tb.sv"
)

cd "$out"
# DSPn.v uses $readmemh with a bare filename, so the microcode must sit in the
# directory the binary runs from (same note as run_gsu_sim.sh).
cp -f "$src"/src/chip/DSP/*.hex "$out"/ 2>/dev/null || true

echo "=== building board bench ==="
verilator --binary --timing -j 0 -Wno-fatal -Wno-lint -Wno-UNUSED -Wno-UNDRIVEN \
    -DVERILATOR -DCONFIG_V -DCHIP_GSU -DCHIP_DSPn -DMCU_BL616 -DTINYSNES_CPU_PROBE \
    -I"$src" -I"$src/src" -I"$src/src/65C816" -I"$src/src/spc700" \
    -I"$src/src/chip/GSU" -I"$src/src/chip/DSP" -I"$src/src/iosys" \
    --top-module board_tb \
    --Mdir obj_dir \
    -o board_sim \
    "${sim[@]}" "${sources[@]}"

echo "=== running ==="
./obj_dir/board_sim \
    "+hex=$hex" "+romlen=$romlen" \
    "+stopframes=$frames" "+maxcycles=$maxcyc" \
    "+ppm=$out/frames.ppm" "+tracedump=$out/trace" "${extra[@]}" 2>&1 | tee "$out/run.log"

echo
echo "picture: $out/frames.ppm"
