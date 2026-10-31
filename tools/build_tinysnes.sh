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
# Extra preprocessor defines for a diagnostic build, e.g. TINYSNES_DEFINES=-DTINYSNES_TEST_PATTERN
defines="${TINYSNES_DEFINES:-}"

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
    "$src"/src/main.v
    "$src/src/snestang_top.v"
    "$src"/src/snes2hdmi.v
    "$src/src/smc_parser.v"
    "$src/src/sdram_cl2_2ch.v"
    "$src/src/vram.v"
    "$src/src/vram_spb.v"
    "$src/src/SNES.v"
    "$src/src/ppucgram.v"
    "$src/src/ppuhoam.v"
    "$src/src/ppuoam.v"
    "$src/src/dual_clk_fifo.v"
    "$src"/src/gowin_dpb_cgram.v
    "$src"/src/gowin_dpb_hoam.v
    "$src"/src/gowin_dpb_oam.v
    "$src"/src/controller_adapter.sv
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

yosys -Q -T -q -l "$out/synth.log" -p "
    read_verilog -lib $shim/cells_xtra_gw5a.v
    read_slang --std 1800-2017 -U SYNTHESIS -D GW_IDE $defines --allow-use-before-declare --allow-lib-module-redef $bbflags -v $shim/cells_sim_nospecify.v -v $shim/cells_xtra_gw5a.v -I $src/hdmi -I $src/src -I $src/src/65C816 -I $src/src/spc700 ${hdmi_slang[*]} ${sources[*]}
    synth_gowin -family gw5a -top snestang_top
    write_json $out/tinysnes.json
" || { echo "synthesis failed; see $out/synth.log" >&2; exit 1; }
echo "netlist: $out/tinysnes.json ($(du -h "$out/tinysnes.json" | cut -f1))"
else
echo "=== 1. synthesis (cached) ==="
fi

[[ "$stage" == synth ]] && { echo "stopping after synthesis"; exit 0; }

# --------------------------------------------------------------- 2. place and route
echo "=== 2. placement and routing ==="
"$nextpnr" \
    --json "$out/tinysnes.json" \
    --write "$out/tinysnes-routed.json" \
    --device "$device" \
    --freq 65 \
    --vopt cst="$src/tinysnes.cst" \
    --sdc "$src/tinysnes.sdc" \
    --report "$out/timing.json" \
    --seed "$seed" \
    >"$out/nextpnr.log" 2>&1 || {
        tail -60 "$out/nextpnr.log" >&2
        echo "place and route failed; see $out/nextpnr.log" >&2
        exit 1
    }
echo "routed: $out/tinysnes-routed.json"

[[ "$stage" == pnr ]] && { echo "stopping after place and route"; exit 0; }

# --------------------------------------------------------------- 3. timing gate and pack
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
