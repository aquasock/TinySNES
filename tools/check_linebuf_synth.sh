#!/usr/bin/env bash
# Does the line buffer's write port survive synthesis?
#
# The one measurement that matters for the video fault.  `synth_gowin` proves
# `mem_portA_we` constant and deletes the memory's write port, so the buffer keeps
# its power-up contents and the picture is a grid.  Simulation shows the same RTL
# asserting that write enable 25,759,024 times (tools/tests/video2_tb.sv), so the
# fold is the tool's error and the design's intent is sound.
#
# This script synthesises one configuration and reports whether the write data
# input came out driven or don't-care.  Anything that folds is rejected; anything
# that survives is a candidate for hardware.
#
#   tools/check_linebuf_synth.sh [-D DEFINE[,DEFINE...]] [-o OUTDIR]
#
# Exit status 0 when the write port survives, 1 when synthesis folded it, 2 on a
# build failure.
set -uo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
defines=""
out="$root/build/linebuf_check"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -D) defines="$2"; shift 2 ;;
        -o) out="$2"; shift 2 ;;
        *) echo "usage: $0 [-D DEFINES] [-o OUTDIR]" >&2; exit 2 ;;
    esac
done

echo "=== synthesising $( [[ -n "$defines" ]] && echo "-D$defines" || echo 'default configuration' )"
TINYSNES_FORCE_SYNTH=1 TINYSNES_STAGE=synth \
TINYSNES_DEFINES="${defines:+-D$defines}" \
TINYSNES_BUILD_DIR="$out" \
    "$root/tools/build_tinysnes.sh" >"$out.log" 2>&1
if [[ $? -ne 0 ]]; then
    echo "synthesis failed; see $out.log" >&2
    exit 2
fi

"${OSS_CAD_SUITE:-$HOME/oss-cad-suite}/py3bin/python3" - "$out" <<'PY'
import json
import pathlib
import sys

out = pathlib.Path(sys.argv[1])
design = json.loads((out / "tinysnes.json").read_text())
top = design["modules"]["snestang_top"]

# A connection entry is a constant when it is a string ("0", "1", "x", "z") and a
# net when it is an integer index.  Getting this backwards is what produced the
# "both constant" mistake recorded in core-log entry 45, so the types are printed
# alongside the verdict rather than assumed.
cells = [c for c in top["cells"] if "s2h.mem" in c and top["cells"][c]["type"].endswith("DPB")]
if not cells:
    print("  no line-buffer cells found in the netlist")
    print("FOLDED")
    sys.exit(1)

driven = 0
dontcare = 0
for cn in cells:
    c = top["cells"][cn]
    dia = c["connections"].get("DIA", [])
    real = sum(1 for b in dia if isinstance(b, int))
    if real:
        driven += 1
    else:
        dontcare += 1

c0 = top["cells"][sorted(cells)[0]]
print(f"  line-buffer cells: {len(cells)}")
print(f"  write data driven: {driven}   write data don't-care: {dontcare}")
for p in ("WREA", "CEA", "ADA", "DIA"):
    v = c0["connections"].get(p)
    kinds = sorted({type(x).__name__ for x in v}) if isinstance(v, list) else [type(v).__name__]
    sample = str(v)[:48]
    print(f"    {p:5s} types={kinds} {sample}")

if driven == len(cells):
    print("WRITE PORT SURVIVES")
    sys.exit(0)
print("FOLDED  (synthesis proved the write enable constant)")
sys.exit(1)
PY
rc=$?
echo
if [[ $rc -eq 0 ]]; then
    echo "RESULT: the line buffer's write port survives synthesis."
else
    echo "RESULT: synthesis folded the write port away."
fi
exit $rc
