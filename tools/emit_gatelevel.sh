#!/usr/bin/env bash
# Emit a gate-level netlist for simulation from the full synthesised design.
#
# The project has been burned repeatedly by instruments that are not the thing on
# the board: staged Yosys runs whose pass boundaries were off by one, isolated
# module synthesis that did not reproduce the whole design's behaviour, and
# captures contaminated by probe displays.  This produces the *shipped* netlist --
# the same synthesis the bitstream comes from -- as Verilog, so a bench can drive
# it and see what the real artifact does.
#
# The three PLLs and the HDMI serialiser are stubbed at simulation time rather
# than synthesised differently, so nothing about the design under test changes.
#
#   tools/emit_gatelevel.sh [-D DEFINES] [-o OUTDIR]
set -uo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
out="$root/build/gatelevel"
defines=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -o) out="$2"; shift 2 ;;
        -D) defines="$2"; shift 2 ;;
        *) echo "usage: $0 [-D DEFINES] [-o OUTDIR]" >&2; exit 2 ;;
    esac
done

suite="${OSS_CAD_SUITE:-$HOME/oss-cad-suite}"
# shellcheck disable=SC1090
source "$suite/environment"
mkdir -p "$out"

echo "=== synthesising the shipped design"
TINYSNES_FORCE_SYNTH=1 TINYSNES_STAGE=synth \
TINYSNES_DEFINES="${defines:+-D$defines}" \
TINYSNES_BUILD_DIR="$out/synth" \
    "$root/tools/build_tinysnes.sh" > "$out/build.log" 2>&1 || {
        echo "synthesis failed; see $out/build.log" >&2; exit 1; }

echo "=== writing Verilog"
# Replay the same read_slang the build used, then stop at the same point, so the
# emitted netlist is the one the bitstream is packed from.
# The build logs its yosys script with four-space indentation and the read_slang
# line wraps across many physical lines, so it is reassembled here rather than
# assumed to be one line.
rs_cmd=$(awk '/read_slang/{f=1} f{printf "%s ", $0} /-v .*gowin_pll_snes\.v/{if(f){f=0; exit}}' \
            "$out/synth/synth.log" | tr -s ' ' | sed 's/^ *//; s/ *$//')
{
    echo "read_verilog -lib $out/synth/shim/cells_sim_nospecify.v"
    echo "read_verilog -lib $out/synth/shim/cells_xtra_gw5a.v"
    echo "${rs_cmd# }"
    echo "synth_gowin -family gw5a -top snestang_top"
    echo "write_verilog -noattr -noexpr -nohex $out/tinysnes_gate.v"
} > "$out/emit.ys"

"$suite/bin/yosys" -q -s "$out/emit.ys" > "$out/emit.log" 2>&1 || {
    echo "emit failed; see $out/emit.log" >&2; exit 1; }

echo "netlist: $out/tinysnes_gate.v ($(wc -l < "$out/tinysnes_gate.v") lines)"

"$suite/py3bin/python3" "$root/tools/report_linebuf_gate.py" "$out/tinysnes_gate.v"
