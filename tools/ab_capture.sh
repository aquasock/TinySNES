#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Record the Pmod and HDMI outputs while booting a cartridge, so every capture
# starts at the same point in the boot.
#
# The problem this solves.  Capturing the two transports by hand meant starting
# arecord and then loading the ROM a second or two later, which recorded whatever
# the machine had been running before -- a different game, mid-level.  Two
# captures taken that way cannot be compared, because they contain different
# music and no amount of analysis fixes that.
#
# So the recording and the boot are a single sequence here: arecord is started
# first because it takes ~100 ms to open the device, then the ROM load begins
# immediately.  The boot is therefore always the same distance from the start of
# the file.
#
#   tools/ab_capture.sh OUTDIR TAG ROM.sfc [SECONDS] [CORE.bin]
#
#   tools/ab_capture.sh build/ab ref /tmp/rom2/zelda.sfc 60 build/aram2/tinysnes.bin
#     -> build/ab/ref_hdmi.wav, build/ab/ref_pmod.wav
#
# With CORE.bin the core is reloaded first, which clears whatever cartridge was
# already running.  Without it the recording opens on the tail of the previous
# game: loading a ROM alone does not silence the old one until the load takes
# hold, which is 5.8 s for a 1 MiB image and lands inside the capture.
#
# Both files are 48 kHz stereo s16.  The HDMI endpoint is the Guermok capture
# card and lags the Pmod by about 0.22 s, which callers must correct for before
# comparing the two; see tools/ab_compare.py.
set -euo pipefail

outdir="${1:?usage: ab_capture.sh OUTDIR TAG ROM.sfc [SECONDS]}"
tag="${2:?}"
rom="${3:?}"
secs="${4:-60}"
core="${5:-}"

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$outdir"
hdmi="$outdir/${tag}_hdmi.wav"
pmod="$outdir/${tag}_pmod.wav"
rm -f "$hdmi" "$pmod"

# A core reload first, when asked for: it clears the running cartridge so the
# capture cannot open on the previous game.
if [[ -n $core ]]; then
    "$root/tools/tang_deploy.py" "$core" /root/cores/console138k/tinysnes-dbg.bin \
        > "$outdir/${tag}_deploy.log" 2>&1
    grep -q 'core loaded' "$outdir/${tag}_deploy.log"
fi

# Start both recorders next: opening an ALSA device takes long enough that
# starting the load first would lose the whole preamble.
arecord -q -D plughw:1,0 -f S16_LE -r 48000 -c 2 -d "$secs" "$hdmi" 2>/dev/null &
hpid=$!
arecord -q -D plughw:0,0 -f S16_LE -r 48000 -c 2 -d "$secs" "$pmod" 2>/dev/null &
ppid=$!

# Wait only until the recorders have opened, then boot.  A fixed short sleep is
# enough for both and keeps the boot at a repeatable offset from the file start.
sleep 0.5

"$root/tools/load_snes_rom.py" "$rom" > "$outdir/${tag}_load.log" 2>&1
tail -1 "$outdir/${tag}_load.log"

wait "$hpid" "$ppid"

python3 - "$hdmi" "$pmod" <<'PY'
import sys, wave
for p in sys.argv[1:]:
    w = wave.open(p)
    print(f"{p}: {w.getnframes()/w.getframerate():.1f}s")
PY
