#!/bin/bash
# One capture-card trial around a two-wire Tang reboot.
#   reboot_trial.sh MODE TAG [PRE_WAIT]
# MODE: none   reboot the Tang only
#       before power-cycle the card, wait PRE_WAIT s (default 8), reboot the Tang
#       after  reboot the Tang, wait 30 s for it to boot, power-cycle the card
#       both   before and after
#       at:REGEX:DELAY  power-cycle the card DELAY s after the reboot script
#              prints a line matching REGEX (e.g. "at:relay 1001:4")
# Then records 25 s at 1 fps into build/capture/TAG_NN.png and prints one letter
# per frame from classify_frames.py.  Needs the sudoers rule for uhubctl and
# the user's unmodified "/home/vash/Desktop/reboot_in 2_wire.py".
#
# Frames go under the repository's build/ directory, not /tmp: /tmp on this
# machine is tmpfs, so capture frames written there are resident RAM, and a
# session of these trials once cost 5 GB of it.  build/ is on the working drive
# and is already gitignored.  Override with TINYSNES_CAPTURE_DIR if needed.
here=$(cd "$(dirname "$0")" && pwd)
cap="${TINYSNES_CAPTURE_DIR:-$here/../../build/capture}"
mkdir -p "$cap"; cd "$cap"; rm -f "$2"_*.png
REBOOT="/home/vash/Desktop/reboot_in 2_wire.py"
cyc(){ sudo -n /usr/sbin/uhubctl -l 1-8.1 -p 2 -a cycle -d 3 >/dev/null; echo "  card cycled $(date +%T) ($1)"; }
case "$1" in
  at:*) IFS=: read -r _ rx dl <<<"$1"
        timeout 120 python3 -u "$REBOOT" 2>&1 | while read -r l; do
          [[ "$l" =~ $rx ]] && { (sleep "$dl"; cyc "$l +${dl}s") & }
        done; wait ;;
  *)    [[ $1 == before || $1 == both ]] && { cyc pre; sleep "${3:-8}"; }
        timeout 120 python3 -u "$REBOOT" >/dev/null 2>&1; echo "  tang reboot done $(date +%T)"
        [[ $1 == after || $1 == both ]] && { sleep 30; cyc post; } ;;
esac
sleep 12
timeout 35 ffmpeg -nostdin -y -loglevel fatal -f v4l2 -input_format mjpeg -video_size 1280x720 \
    -i /dev/video0 -t 25 -vf fps=1 "$2"_%02d.png
echo "$2: $(python3 "$here/classify_frames.py" "$2"_)"
