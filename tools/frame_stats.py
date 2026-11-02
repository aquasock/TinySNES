#!/usr/bin/env python3
"""Classify captured frames so "the screen is black" becomes a number.

Every reading of this board's picture in this project has been a single
screenshot interpreted by eye, and that has produced the same argument three
times: a frame with no image is either the machine drawing nothing, the HDMI
transmitter holding sync with a blank picture, or the capture device not having
a signal at all, and one image cannot tell them apart.

`snes2hdmi` draws its pillarbox bars outside the 4:3 picture area at a fixed
place, so the three states are distinguishable without knowing anything about
the SNES:

  no-signal   every pixel black.  The transmitter is not producing a frame, or
              the capture card never locked to it; nothing about the console can
              be concluded from this frame.
  blank       the bars are there and the picture area is one flat colour.  The
              video path works and the PPU is emitting that colour.
  image       the bars are there and the picture area holds more than a couple of
              colours, so something is being drawn.

    tools/frame_stats.py /tmp/cap_*.png
"""
import glob
import sys
from collections import Counter

from PIL import Image

BAR_X = 20            # a column inside the left pillarbox bar
PICTURE = (200, 500, 700, 1000)   # x range well inside the 960-wide picture area
GREY_BAR = (34, 34, 34)


def classify(path: str) -> tuple[str, tuple[int, int, int], int]:
    im = Image.open(path).convert("RGB")
    w, h = im.size
    px = im.load()
    # Sample the picture area rather than counting the whole frame: the bars and
    # their antialiasing otherwise dominate the colour histogram.
    colours = Counter()
    for y in range(0, h, 4):
        for x in range(PICTURE[0], PICTURE[3], 4):
            colours[px[x, y]] += 1
    total = sum(colours.values())
    dominant, count = colours.most_common(1)[0]
    bar = px[BAR_X, h // 2]
    if dominant == (0, 0, 0) and count == total and bar == (0, 0, 0):
        return "no-signal", dominant, 1
    if len(colours) <= 2:
        return "blank", dominant, len(colours)
    return "image", dominant, len(colours)


def main() -> int:
    paths = []
    for arg in sys.argv[1:]:
        paths.extend(sorted(glob.glob(arg)) or [arg])
    if not paths:
        print(__doc__)
        return 2
    tally = Counter()
    first: dict[str, str] = {}
    for p in paths:
        try:
            kind, dominant, n = classify(p)
        except (OSError, IndexError):
            continue
        tally[kind] += 1
        first.setdefault(kind, f"{p.rsplit('/', 1)[-1]} dominant {dominant} ({n} colours)")
    total = sum(tally.values())
    if total == 0:
        print("  frames: 0  (nothing captured -- check that /dev/video0 is free)")
        return 1
    print(f"  frames: {total}")
    for kind in ("image", "blank", "no-signal"):
        if tally[kind]:
            pct = 100.0 * tally[kind] / total
            print(f"  {kind:<10} {tally[kind]:4d}  {pct:5.1f}%   e.g. {first[kind]}")
    print(f"  dropout rate (no-signal): {100.0 * tally['no-signal'] / total:.1f}%")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
