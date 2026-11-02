#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Pick the placement seed whose SNES master clock has the most margin.
#
# Why this exists.  The mclk domain -- the 65816, the PPU and every SDRAM access
# the machine makes -- is the tightest clock in this design: 21.505 MHz required
# against roughly 31 MHz achieved, where fclk has four times its requirement and
# hclk nearly twice.  Every SDRAM access crosses mclk to fclk, and nextpnr gives
# that crossing only a single-cycle assumption because its SDC parser has no
# set_multicycle_path and silently ignores the ones SNESTang relies on.
#
# Placement is seed-sensitive here, and the seeds chosen for tests so far were
# picked for hold cleanliness, not for this margin.
#
#   tools/sweep_mclk.sh <build-dir> [seeds...]
#
# Seeds route in PARALLEL.  Each is an independent place-and-route of the same
# netlist and they share no state, so running them one at a time turned a
# five-minute job into half an hour.  Each seed owns its own directory and log,
# so a failure stays local and the others still report.
set -uo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
src="${1:?usage: sweep_mclk.sh <build-dir> [seeds...]}"
shift
seeds=("$@")
[[ ${#seeds[@]} -gt 0 ]] || seeds=(1 2 3 4 5 6)

[[ -f "$src/tinysnes.json" ]] || { echo "no netlist in $src; synthesis first" >&2; exit 2; }

out_dir="$(cd -- "$(dirname -- "$src")" && pwd)/$(basename "$src")-sweep"
mkdir -p "$out_dir"

echo "=== routing ${#seeds[@]} seeds in parallel: ${seeds[*]} ==="

for s in "${seeds[@]}"; do
    d="$out_dir/s$s"
    rm -rf "$d"; mkdir -p "$d"
    cp "$src/tinysnes.json" "$d/"
    (
        TINYSNES_STAGE=pnr TINYSNES_SEED="$s" TINYSNES_BUILD_DIR="$d" \
        TINYSNES_ALLOW_HOLD=1 TINYSNES_ALLOW_UNMEASURED_CLOCKS=1 \
            "$root/tools/build_tinysnes.sh" >"$d/pnr.log" 2>&1
        echo "$s $?" > "$d/rc"
    ) &
done

wait

echo
printf "%-6s %10s %10s %8s %8s  %s\n" seed mclk fclk hclk holds margin status
best="" best_freq=0
for s in "${seeds[@]}"; do
    d="$out_dir/s$s"
    rc=$(awk '{print $2}' "$d/rc" 2>/dev/null)
    if [[ "$rc" != "0" || ! -f "$d/timing.json" ]]; then
        printf "%-6s %s\n" "$s" "FAILED (rc=${rc:-none})"
        continue
    fi
    read -r mclk fclk hclk < <("$HOME/oss-cad-suite/py3bin/python3" - "$d" <<'PY'
import json, pathlib, sys
t = json.loads((pathlib.Path(sys.argv[1]) / "timing.json").read_text())["fmax"]
def g(*names):
    for n in names:
        if n in t:
            return t[n]["achieved"]
    return 0.0
print(f"{g('iosys.clk','mclk'):.3f} {g('fclk'):.3f} {g('hclk'):.3f}")
PY
)
    holds=$(grep -c "Hold/min time violation for clock" "$d/nextpnr.log" 2>/dev/null)
    holds=${holds:-0}
    margin=$("$HOME/oss-cad-suite/py3bin/python3" -c "print(f'{$mclk/21.505*100-100:+.0f}%')")
    status="ok"
    [[ "$holds" != "0" ]] && status="HOLD VIOLATIONS"
    printf "%-6s %9.3f %10.3f %8.3f %8s  %s  %s\n" "$s" "$mclk" "$fclk" "$hclk" "$holds" "$margin" "$status"
    if [[ "$holds" == "0" ]]; then
        better=$("$HOME/oss-cad-suite/py3bin/python3" -c "print(1 if $mclk > $best_freq else 0)")
        if [[ "$better" == "1" ]]; then best="$s"; best_freq="$mclk"; fi
    fi
done

echo
if [[ -n "$best" ]]; then
    echo "best hold-clean seed: $best  (mclk $best_freq MHz)"
    echo "  bitstream: $out_dir/s$best/tinysnes.fs"
else
    echo "no seed routed hold-clean"
fi
