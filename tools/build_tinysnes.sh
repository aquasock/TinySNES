#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Build the TinySNES core with the open flow: yosys (read_slang for hdl-util's
# HDMI transmitter, read_verilog for the rest), the nextpnr-himbaechel fork
# against the regenerated GW5AST-138C database, and the apicula fork's
# gowin_pack.  No Gowin EDA is involved.
#
#   tools/build_tinysnes.sh [out-dir]
#
#   TINYSNES_STAGE     synth | pnr | pack | all (default all)
#   TINYSNES_BUILD_DIR output directory (default build/tinysnes)
#   TINYSNES_SEED      placement seed (default 1; not yet proven on hardware)
#   NEXTPNR_HIMBAECHEL, APICULA_FORK, OSS_CAD_SUITE, PYDEPS  see TinyNES
#
# The design is SNESTang's (nand2mario) with TinyTang's board conventions:
# fpga/snes/ holds every source, no upstream checkout or patch is involved.
set -euo pipefail
export LC_ALL=C

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
src="$root/fpga/snes"
out="${TINYSNES_BUILD_DIR:-$root/build/tinysnes}"
stage="${TINYSNES_STAGE:-all}"
case "$stage" in synth|pnr|pack|all) ;; *) echo "TINYSNES_STAGE must be synth, pnr, pack or all" >&2; exit 2 ;; esac

suite="${OSS_CAD_SUITE:-$HOME/oss-cad-suite}"
nextpnr="${NEXTPNR_HIMBAECHEL:-$HOME/tools/nextpnr-mathieufro/nextpnr-himbaechel}"
apycula="${APICULA_FORK:-$(dirname "$root")/apicula-mathieufro}"
pydeps="${PYDEPS:-$HOME/tools/pydeps}"
device=GW5AST-LV138PG484AC1/I0
family=GW5AST-138C
seed="${TINYSNES_SEED:-1}"
# Hold violations do not block a build (user decision, 2026-10-30): the placer
# reports them as fatal errors, so TINYSNES_ALLOW_HOLD=1 passes --timing-allow-fail
# and the Fmax gate below still enforces the clock periods afterwards.
timing_fail=""
[[ "${TINYSNES_ALLOW_HOLD:-0}" == 1 ]] && timing_fail="--timing-allow-fail"
# Extra place-and-route arguments, passed straight to nextpnr.  Used to evaluate
# its --threads and --parallel-refine options, which this script never passed:
# every build so far has run the router single-threaded on one core, which is
# why five parallel builds sit at 25 percent of a 28-core machine rather than
# being able to use the cores inside one build.
pnr_extra="${TINYSNES_PNR_EXTRA:-}"
# Extra preprocessor defines for a diagnostic build, e.g. TINYSNES_DEFINES=-DTINYSNES_TEST_PATTERN
defines="${TINYSNES_DEFINES:-}"
# Which clock net nextpnr's global router takes first.  On this device a clock
# reaches the global network by leaving a spine mux through a bridge pip, and the
# pins nextpnr picks depend on the order it routes the clock nets in -- TinyNES
# core-reference DEV-016: a netlist that did not boot ran unchanged apart from
# its clock routing order.  Setting this makes the choice deterministic instead
# of alphabetical.  The knob matches a net by name, and after flattening Yosys
# names a net after the alphabetically first of its aliases, so the default here
# is the SNES master clock's post-synthesis name: mclk is joined by iosys.clk,
# which sorts first.  Verify with tools/clock_plane_report.py rather than
# assuming; TinyNES's own record notes the knob silently matching nothing when
# that alias changes.
clk_first="${TINYSNES_CLK_FIRST:-iosys.clk}"
# TINYSNES_SYNTH_NO_ABC=1 hand-builds the synthesis script with ABC9 left out.
# synth_gowin has no -noabc flag, so the flow is run in two halves around the
# map_luts stage that contains `abc9 -maxlut 8`:  `begin:map_luts` (everything
# up to and excluding map_luts), then `sort; clean` (the rest of map_luts), then
# `map_cells:` (LUT insertion and checks).  ABC9 proves the line buffer's write
# data don't-care and folds it to a constant x; the user's ruling is that area
# is free on this device and the design may waste it rather than accept that.
no_abc="${TINYSNES_SYNTH_NO_ABC:-0}"
# Refuse a build whose clocks land on spine/bridge pips nobody has measured on
# this board.  TINYSNES_ALLOW_UNMEASURED_CLOCKS=1 downgrades that to a warning.
allow_unmeasured="${TINYSNES_ALLOW_UNMEASURED_CLOCKS:-0}"

# Refuse to build a diagnostic combination that cannot show what the operator is
# being asked to look at.  Two cycles were lost to this: a build carrying a probe
# define draws the probe's own bars because `TINYSNES_PROBE_BARS` overrides the
# production picture, and a build that was reported as "no change" had actually
# never been given a cartridge, so the screen had no colour in it to change.  The
# check is here rather than in the operator's head because it has been got wrong
# twice, and the second time it was reported to the user as a measurement.
probe_bars=""
for d in ${TINYSNES_DEFINES:-}; do
    case "$d" in
        -DTINYSNES_FETCH_PROBE|-DTINYSNES_CPU_PROBE|-DTINYSNES_TRACE_PROBE|-DTINYSNES_LIVE_PROBE|\
        -DTINYSNES_APU_PROBE|-DTINYSNES_IPL_PROBE|-DTINYSNES_LINK_PROBE|-DTINYSNES_WHERE_PROBE|\
        -DTINYSNES_JUMP_PROBE|-DTINYSNES_STACK_PROBE|-DTINYSNES_STACKBYTES_PROBE|\
        -DTINYSNES_INSN_PROBE|-DTINYSNES_IRQ_PROBE|-DTINYSNES_WAIT_PROBE|\
        -DTINYSNES_PIXEL_PROBE|-DTINYSNES_SELFTEST_PROBE|-DTINYSNES_TIMING_PROBE|\
        -DTINYSNES_LINEFILL_PROBE)
            probe_bars="${probe_bars} ${d#-D}" ;;
    esac
done
if [[ -n "$probe_bars" ]]; then
    echo "NOTE: this build replaces the picture with the probe display (${probe_bars# })."
    echo "      The screen will show 16-bar stripes and a status band, NOT the line"
    echo "      buffer.  Do not read 'the same grid' from a build like this."
fi

[[ -f "$suite/environment" ]] || { echo "missing open toolchain: $suite" >&2; exit 2; }
# shellcheck disable=SC1090
source "$suite/environment"
export PYTHONHOME="$suite"
export PYTHONPATH="$apycula:$pydeps:${PYTHONPATH:-}"
mkdir -p "$out"

# --------------------------------------------------------------- sources
# SNESTang's console138k file list (build.tcl) minus the parts this board does
# not build: the FPGA-side USB HID host and its 12 MHz PLL, the DualShock and
# SNES-controller adapters (pads arrive over the BL616 link), the Nano-20K and
# 3-channel SDRAM variants, and the PicoRV32 I/O system.
hdmi_slang=()
for f in "$src"/hdmi/*.sv; do hdmi_slang+=("$f"); done

sources=(
    "$src/config.v"
    "$src/src/65C816/adder4.v"
    "$src/src/65C816/bit_adder.v"
    "$src/src/65C816/ALU.v"
    "$src/src/65C816/AddSubBCD.v"
    "$src/src/65C816/AddrGen.v"
    "$src/src/65C816/BCDAdder.v"
    "$src/src/65C816/P65C816.v"
    "$src/src/65C816/common.sv"
    "$src/src/65C816/mcode.sv"
    "$src/src/CEGen.v"
    "$src/src/cpu.v"
    "$src/src/smp.v"
    "$src/src/ppu.v"
    "$src/src/dsp.v"
    "$src/src/swram.v"
    "$src"/src/spc700/alu.v
    "$src"/src/spc700/addsub.v
    "$src"/src/spc700/addrgen.v
    "$src"/src/spc700/bcdadj.v
    "$src"/src/spc700/muldiv.v
    "$src"/src/spc700/mcode.v
    "$src"/src/spc700/_spc700_package.v
    "$src"/src/spc700/spc700.v
    "$src"/src/chip/DSP/DSP_LHRomMap.v
    "$src"/src/chip/DSP/DSPn.v
    "$src"/src/chip/DSP/OBC1.v
    "$src"/src/chip/DSP/SRTC.v
    "$src"/src/chip/DSP/dsp_data_ram.v
    "$src"/src/chip/GSU/GSU_PKG.v
    "$src"/src/chip/GSU/GSU.v
    "$src"/src/chip/GSU/GSUMap.v
    "$src"/src/main.v
    "$src/src/snestang_top.v"
    "$src/src/tinysnes_dbg.v"
    "$src"/src/snes2hdmi.v
    "$src"/src/desk_layer.v
    "$src/src/smc_parser.v"
    "$src/src/sdram_cl2_2ch.v"
    "$src/src/sdram_bist.v"
    "$src/src/aram_bist.v"
    "$src/src/wram_bist.v"
    "$src/src/rom_stability.v"
    "$src/src/rom_probe.v"
    "$src/src/vram.v"
    "$src/src/vram_spb.v"
    "$src/src/SNES.v"
    "$src/src/ppucgram.v"
    "$src/src/ppuhoam.v"
    "$src/src/ppuoam.v"
    "$src/src/dual_clk_fifo.v"
    "$src/src/hdmi_audio_clock.v"
    "$src"/src/gowin_dpb_cgram.v
    "$src"/src/gowin_dpb_hoam.v
    "$src"/src/gowin_dpb_oam.v
    "$src"/src/controller_adapter.sv
    "$src"/src/wii_pad.sv
    "$src"/src/i2s_out.sv
    "$src"/src/iosys/gowin_dpb_menu.v
    "$src/src/iosys/iosys_bl616.v"
    "$src/src/iosys/uart_fractional.v"
    "$src/src/iosys/textdisp.v"
    "$src/src/iosys/uart_fixed.v"
    "$src/src/iosys/crc16.v"
    "$src/pll/gowin_pll_27.v"
    "$src/pll/gowin_pll_hdmi.v"
    "$src/pll/gowin_pll_snes.v"
)

for f in "${sources[@]}" "${hdmi_slang[@]}"; do
    [[ -f "$f" ]] || { echo "missing source: $f" >&2; exit 2; }
done

# --------------------------------------------------------------- 1. synthesis
if [[ ! -f "$out/tinysnes.json" || "${TINYSNES_FORCE_SYNTH:-0}" == 1 ]]; then
echo "=== 1. synthesis ==="
# Primitive visibility: the Gowin cell libraries must be readable (so wrapper
# instances resolve) and every primitive the design instantiates must be
# blackboxed as well, or it is dropped without a word.
shim="$out/shim"
mkdir -p "$shim"
datdir=$(yosys-config --datdir 2>/dev/null || true)
[[ -n "${datdir:-}" && -d "$datdir/gowin" ]] || datdir="$suite/share/yosys"
awk '/^[[:space:]]*specify[[:space:]]*$/ { skip=1 }
     !skip { print }
     /^[[:space:]]*endspecify[[:space:]]*$/ { skip=0 }' \
    "$datdir/gowin/cells_sim.v" > "$shim/cells_sim_nospecify.v"
cp "$datdir/gowin/cells_xtra_gw5a.v" "$shim/cells_xtra_gw5a.v"

libmods=$(grep -hoE '^[[:space:]]*module [A-Za-z_][A-Za-z0-9_]*' "$shim"/cells_*.v |
          awk '{print $2}' | sort -u)
dnames=$(grep -rhoE '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*' "$src" \
              --include=*.v --include=*.sv 2>/dev/null |
         sed 's/^[[:space:]]*//' | sort -u)
bb=$(comm -12 <(echo "$libmods") <(echo "$dnames")) || true
bbflags=$(echo "$bb" | sed 's/^/--blackboxed-module /' | paste -sd' ')

if [[ "$no_abc" == 1 ]]; then
    echo "synthesis: hand-built script, ABC9 omitted"
    synth_cmds="
    synth_gowin -family gw5a -top snestang_top -run begin:map_luts
    sort
    clean
    synth_gowin -family gw5a -top snestang_top -run map_cells:"
else
    synth_cmds="
    synth_gowin -family gw5a -top snestang_top"
fi

yosys -Q -T -q -l "$out/synth.log" -p "
    read_verilog -lib $shim/cells_xtra_gw5a.v
    read_slang --single-unit --std 1800-2017 -U SYNTHESIS -D GW_IDE $defines --allow-use-before-declare --allow-lib-module-redef $bbflags -v $shim/cells_sim_nospecify.v -v $shim/cells_xtra_gw5a.v -I $src/hdmi -I $src/src -I $src/src/65C816 -I $src/src/spc700 -I $src/src/chip/DSP ${hdmi_slang[*]} ${sources[*]}
    $synth_cmds
    write_json $out/tinysnes.json
" || { echo "synthesis failed; see $out/synth.log" >&2; exit 1; }
echo "netlist: $out/tinysnes.json ($(du -h "$out/tinysnes.json" | cut -f1))"

# ------------------------------------------------- netlist instance assertion
#
# A configuration macro that never reaches the RTL is silent: the generate
# block that instantiates a chip elaborates to nothing and the build passes
# every gate with the chip absent.  That is what happened before core-log entry
# 73 -- read_slang compiles each input file as its own compilation unit unless
# --single-unit is given, so the `define`s in fpga/snes/config.v never crossed
# into snestang_top.v, which then read USE_DSPn=0 and USE_GSU=0 from its
# `ifdef CHIP_* defaults.  Every coprocessor build in the log that worked had
# its defines injected on the command line through TINYSNES_DEFINES, so the
# committed tree could not reproduce any of them.  Check the netlist, not the
# command line: a cell name proves the logic survived elaboration and synthesis.
require_cell() {  # require_cell <label> <cell-name-substring> <min-count>
    local label="$1" needle="$2" want="$3" got
    got=$(grep -o "$needle" "$out/tinysnes.json" | wc -l)
    if (( got < want )); then
        echo "netlist assertion FAILED: $label -- expected at least $want occurrence(s)" >&2
        echo "  of '$needle' in $out/tinysnes.json, found $got" >&2
        echo "  the chip is absent from the synthesised netlist; check that its" >&2
        echo "  CHIP_* define actually reaches snestang_top.v" >&2
        return 1
    fi
    echo "    $label present ($got cell-name matches)"
}
assert_ok=1
require_cell "SuperFX (GSU)"  'GSUMap'       1 || assert_ok=0
require_cell "cartridge DSP"   'DSP_LHRomMap' 1 || assert_ok=0
(( assert_ok == 1 )) || {
    echo "netlist assertions failed; refusing to place a netlist that is missing a configured chip" >&2
    exit 1
}
else
echo "=== 1. synthesis (cached) ==="
fi

# A clock must not drive both a true negedge flop and a LUT1 clock inverter:
# the two halves of its negedge logic then clock a few ns apart, untimed.
# This stopped the SuperFX on the board (core-log entry 88).
echo "=== 1b. clock edges ==="
"$suite/py3bin/python3" "$root/tools/clock_edge_check.py" "$out/tinysnes.json" || {
    echo "refusing to place a netlist with split negedge clocking" >&2
    exit 1
}

[[ "$stage" == synth ]] && { echo "stopping after synthesis"; exit 0; }

# --------------------------------------------------------------- 2. place and route
#
# `pack` means "pack the routed netlist that is already here", not "place and
# route again".  There was no early exit for it, so TINYSNES_STAGE=pack re-ran
# nextpnr and *overwrote* tinysnes-routed.json and timing.json before packing.
# nextpnr does not reproduce a placement from an unchanged netlist and seed, so
# the bitstream that shipped was routinely a different placement from the one
# whose timing, hold and clock-plane gates had just been checked -- and a seed
# that gated clean could fail the re-run.  Both were observed: seed 1 of the
# GSU probe passed place and route and then hit 'Hold/min time violation for
# clock posedge fclk' on the pack stage's redundant run.  Skipping the re-run
# makes the packed bitstream exactly the one that was gated, and drops the stage
# from minutes to seconds.
if [[ "$stage" == pack ]]; then
    [[ -f "$out/tinysnes-routed.json" ]] || {
        echo "no routed netlist in $out; run TINYSNES_STAGE=pnr first" >&2
        exit 2
    }
    echo "=== 2. placement and routing (reused) ==="
    echo "    $out/tinysnes-routed.json"
else
echo "=== 2. placement and routing ==="
export NPNR_GOWIN_CLK_FIRST="$clk_first"
"$nextpnr" \
    --json "$out/tinysnes.json" \
    --write "$out/tinysnes-routed.json" \
    --device "$device" \
    --freq 65 \
    --vopt cst="$src/tinysnes.cst" \
    --sdc "$src/tinysnes.sdc" \
    --report "$out/timing.json" \
    --seed "$seed" \
    ${timing_fail} \
    ${pnr_extra} \
    >"$out/nextpnr.log" 2>&1 || {
        tail -60 "$out/nextpnr.log" >&2
        echo "place and route failed; see $out/nextpnr.log" >&2
        exit 1
    }
echo "routed: $out/tinysnes-routed.json"

# The router logs this when the knob applied.  If the net is named something else
# after synthesis the knob matches nothing and the routing is alphabetical again,
# which is the failure TinyNES recorded; catch it rather than trust it.
if ! grep -q "experiment: routing '$clk_first' first" "$out/nextpnr.log"; then
    echo "NPNR_GOWIN_CLK_FIRST='$clk_first' did not match any clock net;" >&2
    echo "the clock routing order is alphabetical.  Set TINYSNES_CLK_FIRST to one" >&2
    echo "of the net names in $out/tinysnes-routed.json." >&2
    exit 1
fi

echo "=== 2b. clock plane ==="
plane_args=()
[[ "$allow_unmeasured" == 1 ]] && plane_args+=(--allow-unmeasured)
"$suite/py3bin/python3" "$root/tools/clock_plane_report.py" \
    "$out/tinysnes-routed.json" "${plane_args[@]}" || exit 1

[[ "$stage" == pnr ]] && { echo "stopping after place and route"; exit 0; }
fi   # end of the non-pack branch: place and route

# --------------------------------------------------------------- 3. timing gate and pack
# The gate is Fmax only.  Hold violations reported by nextpnr do not block a
# build or a pack: the user accepted them on 2026-10-30 as the placement cost of
# this design on this device, and seed 9 was the one clean placement out of the
# sweep in core-log entry 1.  Do not add a hold gate without asking.
echo "=== 3. timing gate ==="
"$suite/py3bin/python3" - "$out" <<'PY'
import json, pathlib, sys
out = pathlib.Path(sys.argv[1])
t = json.loads((out / "timing.json").read_text())["fmax"]
for name, v in sorted(t.items()):
    print(f"  {name}: constraint {v['constraint']:.3f} MHz, achieved {v['achieved']:.3f} MHz")
bad = [n for n, v in t.items() if v["achieved"] < v["constraint"]]
if bad:
    raise SystemExit(f"timing not met on: {', '.join(bad)}")
PY

echo "=== 4. bitstream ==="
"$suite/py3bin/python3" -m apycula.gowin_pack \
    -d "$family" \
    -o "$out/tinysnes.fs" \
    "$out/tinysnes-routed.json" \
    >"$out/pack.log" 2>&1 || {
        tail -40 "$out/pack.log" >&2
        exit 1
    }
"$suite/py3bin/python3" "$root/tools/fs_to_bin.py" "$out/tinysnes.fs" -o "$out/tinysnes.bin" >/dev/null
sha256sum "$out/tinysnes.fs" "$out/tinysnes.bin"
echo "Ready to tangload (two-wire): $out/tinysnes.bin"
