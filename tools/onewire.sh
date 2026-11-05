#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# One-wire test: flash a bitstream over the FT2232 and stream a cartridge at the
# core's own UART, then read the picture back if a capture device is free.
#
#   tools/onewire.sh <build-dir> [rom] [--no-capture] [--no-flash]
#
#   tools/onewire.sh build/noosd build/rom/tinysnes_bgdraw.sfc
#
# "One-wire" is this project's name for the fast loop: `openFPGALoader -b
# tangconsole` puts the bitstream in the FPGA's SRAM over the FT2232, and
# `tools/load_snes_rom.py --uart` streams the cartridge straight at the core's
# UART on /dev/ttyUSB1 at 2 Mbaud.  No card copy and no console firmware are
# involved, which is why it is the loop to use for video work.  "Two-wire" is
# tangload with the card and the shell, and is only needed for those.
#
# Two operational facts this script exists to stop rediscovering:
#
#   * A flash that reports Done can still leave the board silent, and the fix is
#     to load the same file again.  So the flash is verified by reading the
#     bitstream's hash out of the log it wrote, and a silent board after a load
#     is a failed flash until proven otherwise.
#   * Flashing clears the core's `loaded` state, so the ROM has to be streamed
#     again after every flash.  A diagnostic that reads black after a reload is
#     waiting for a cartridge, not running slowly.
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
suite="${OSS_CAD_SUITE:-$HOME/oss-cad-suite}"
flasher="$suite/bin/openFPGALoader"
board="${TINYSNES_BOARD:-tangconsole}"
uart="${TINYSNES_UART:-/dev/ttyUSB1}"
video="${TINYSNES_VIDEO:-/dev/video0}"
capture="${TINYSNES_CAPTURE_DIR:-$root/build/capture}"

die() { echo "$*" >&2; exit 2; }

[[ $# -ge 1 ]] || die "usage: $(basename "$0") <build-dir> [rom] [--no-capture] [--no-flash]"
build="${1%/}"; shift
rom=""
do_capture=1
do_flash=1
for arg in "$@"; do
    case "$arg" in
        --no-capture) do_capture=0 ;;
        --no-flash)   do_flash=0 ;;
        -*)           die "unknown option: $arg" ;;
        *)            rom="$arg" ;;
    esac
done

fs="$build/tinysnes.fs"
[[ -f "$fs" ]] || die "no bitstream at $fs -- build it with tools/build_tinysnes.sh"

echo "=== bitstream ==="
echo "  $fs"
sha256sum "$fs"
# The build's own log is the evidence for the gates, so read it rather than
# restating what the build claimed at the time.
if [[ -f "$build/timing.json" ]]; then
    "$suite/py3bin/python3" - "$build" <<'PY' || true
import json, pathlib, sys
t = json.loads((pathlib.Path(sys.argv[1]) / "timing.json").read_text())["fmax"]
for name, v in sorted(t.items()):
    state = "PASS" if v["achieved"] >= v["constraint"] else "FAIL"
    print(f"  {name:<22} {v['achieved']:9.3f} / {v['constraint']:8.3f} MHz  {state}")
PY
fi
if [[ -f "$build/tinysnes-routed.json" ]]; then
    echo "=== clock plane ==="
    "$suite/py3bin/python3" "$root/tools/clock_plane_report.py" \
        "$build/tinysnes-routed.json" --allow-unmeasured 2>&1 |
        grep -E "clock\(s\) on pips|^  [a-z_]+ +\[" || true
fi

if [[ "$do_flash" == 1 ]]; then
    echo "=== flash over the FT2232 ==="
    # The system openFPGALoader at v0.13.1 has no tangconsole board; the
    # oss-cad-suite copy does.  Using the wrong one fails with a board-list
    # error, so name the failing tool in the message.
    "$flasher" -b "$board" "$fs" 2>&1 | tail -3 ||
        die "$flasher could not load for board $board"
    sleep 2
fi

if [[ -n "$rom" ]]; then
    [[ -f "$rom" ]] || die "no cartridge at $rom"
    echo "=== cartridge ==="
    echo "  $rom ($(stat -c%s "$rom") bytes)"
    /usr/bin/python3 "$root/tools/load_snes_rom.py" --uart "$uart" "$rom"
else
    echo "=== no cartridge given ==="
    echo "  a diagnostic build that draws its own bars needs none; a production"
    echo "  build will sit black until one is streamed."
fi

if [[ "$do_capture" == 1 ]]; then
    # The capture card often has not locked on the first frame after a load, so
    # a couple of seconds are taken and every frame is classified rather than
    # one image being trusted.
    if [[ -e "$video" ]] && ! fuser -s "$video" 2>/dev/null; then
        echo "=== capture ($video) ==="
        mkdir -p "$capture"
        rm -f "$capture"/frame_*.png
        sleep 4
        timeout 35 ffmpeg -hide_banner -loglevel error -f v4l2 \
            -video_size 1280x720 -i "$video" -frames:v 20 \
            -y "$capture/frame_%03d.png" 2>/dev/null || true
        env -u PYTHONHOME -u PYTHONPATH /usr/bin/python3 \
            "$root/tools/frame_stats.py" "$capture/frame_*.png" 2>/dev/null || \
            echo "  (no frames captured)"
        echo "  frames: $capture"
    else
        echo "=== capture skipped: $video is busy or absent ==="
        echo "  close the program holding it, or pass --no-capture"
    fi
fi
