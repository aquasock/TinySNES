#!/usr/bin/env python3
"""Decode the TINYSNES_PROBE_BARS display out of capture-card frames.

The five stripes are 16 bars each, red = 0 and green = 1, bit 0 on the left.
The bars replace the picture, so the whole active area is bars and gaps.  The
SNES 256x224 space is scaled into the capture, so geometry is derived from the
capture rather than assumed:

  horizontal: 16 bars in the 256-px SNES width, scaled by (barwidth*16)/256
  vertical:   stripe b occupies SNES rows 32b..32b+23, scaled by the same factor

Each frame is decoded three times at slightly different sample rows; a frame is
accepted only when all three agree, which rejects the tearing frames the card
produces mid-transition.  The surviving frames are then combined by per-bit
majority vote.

    tools/decode_probe_frame.py FRAME...
    tools/decode_probe_frame.py --stripe-names "CPUO,A,PC,P ..." FRAME...
"""
import sys
import numpy as np
from PIL import Image

GREEN = np.array([0x00, 0xC0, 0x00])
RED = np.array([0xC0, 0x00, 0x00])


def classify(px):
    """Return 1 for the green bar, 0 for the red bar, None for anything else."""
    g = np.abs(px.astype(int) - GREEN).sum(axis=-1)
    r = np.abs(px.astype(int) - RED).sum(axis=-1)
    out = np.where(g < r, 1, 0)
    ok = np.minimum(g, r) < 90
    return np.where(ok, out, -1)


def find_geometry(img):
    """Locate the bar area: rows that contain a healthy mix of red and green."""
    cls = classify(img)
    row_counts = (cls >= 0).sum(axis=1)
    xs = (cls >= 0)
    if row_counts.max() < 100:
        return None
    rows = np.where(row_counts > row_counts.max() * 0.5)[0]
    cols = np.where(xs[rows].any(axis=0))[0]
    if len(rows) == 0 or len(cols) == 0:
        return None
    return rows.min(), rows.max(), cols.min(), cols.max()


def sample_stripe(cls, x0, x1, y):
    """Read 16 bits from one row of bars, sampling each bar's middle."""
    width = x1 - x0 + 1
    bits = []
    for i in range(16):
        cx = x0 + int((i + 0.5) * width / 16)
        lo = max(x0, cx - 2)
        hi = min(x1 + 1, cx + 3)
        window = cls[y, lo:hi]
        window = window[window >= 0]
        if len(window) == 0:
            return None
        bits.append(1 if window.mean() > 0.5 else 0)
    return bits


def decode_frame(path):
    img = np.array(Image.open(path).convert("RGB"))
    geo = find_geometry(img)
    if geo is None:
        return None
    _, _, x0, x1 = geo
    cls = classify(img)
    # Stripe b is SNES rows 32b..32b+23.  Derive the row pitch from the capture:
    # the bars span y=0 of the scaled active area, and stripe 1's gap starts at
    # SNES row 24.  Use 12 rows into each stripe, measured in capture pixels by
    # scanning for the bar rows themselves.
    height = img.shape[0]
    # The five stripes plus gaps occupy SNES rows 0..159; find the scale factor
    # by locating the first all-black gap row below the first stripe.
    barrows = np.where((cls >= 0).sum(axis=1) > (x1 - x0) * 0.5)[0]
    if len(barrows) == 0:
        return None
    # 24 bar rows, then 8 gap rows, repeated: pitch = 32 SNES rows.  Measure the
    # pitch from the run structure of bar rows.
    runs = np.split(barrows, np.where(np.diff(barrows) > 1)[0] + 1)
    if len(runs) < 2:
        return None
    pitch = barrows[0] - 0  # placeholder, replaced below
    pitch = int(round((runs[1][0] - runs[0][0])))
    per_row = pitch / 32.0
    decodes = []
    for variant in (0.5, 0.4, 0.6):
        stripes = []
        ok = True
        for b in range(5):
            y = int(round((b * 32 + 24 * variant) * per_row))
            y = min(max(y, 0), height - 1)
            bits = sample_stripe(cls, x0, x1, y)
            if bits is None:
                ok = False
                break
            stripes.append(bits)
        if ok:
            decodes.append(stripes)
    if not decodes:
        return None
    first = decodes[0]
    if any(d != first for d in decodes[1:]):
        return None  # torn frame: the three sample rows disagree
    words = []
    for bits in first:
        words.append(sum(b << i for i, b in enumerate(bits)))
    return words


def main():
    names = None
    args = sys.argv[1:]
    if args and args[0] == "--stripe-names":
        names = [s for s in args[1].split(",")]
        args = args[2:]
    if not args:
        print(__doc__, file=sys.stderr)
        return 2
    votes = np.zeros((5, 16), dtype=int)
    good = 0
    for path in args:
        words = decode_frame(path)
        if words is None:
            continue
        good += 1
        for s, w in enumerate(words):
            for i in range(16):
                votes[s, i] += (w >> i) & 1
    if good == 0:
        print("no decodable frame", file=sys.stderr)
        return 1
    print(f"{good} decodable frames of {len(args)}")
    for s in range(5):
        label = names[s] if names and s < len(names) else f"stripe {s + 1}"
        word = 0
        for i in range(16):
            bit = 1 if votes[s, i] * 2 > good else 0
            word |= bit << i
        agree = max(votes[s].sum(), 16 * good - votes[s].sum())
        print(f"{label:28s} 0x{word:04X} 0b{word:016b}  ({agree}/{16 * good} bit-votes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
