#!/usr/bin/env python3
"""Classify capture-card frames PREFIX*.png, one letter per frame, in name order.

  N  the card's "No Video" page (black with a white logo in the centre only)
  C  a real picture: mostly level-0 black with bright pixels (Tang console)
  F  flat grey fill (max <= 12): card acquiring, or the first ~2.5 s of a stream
  ?  anything else

    tools/capture/classify_frames.py /tmp/grab/pre_
"""
import sys, glob
from PIL import Image
s = ''
for f in sorted(glob.glob(sys.argv[1] + '*.png')):
    im = Image.open(f).convert('L'); lo, hi = im.getextrema()
    c = im.crop((480, 300, 800, 420)).getextrema()[1]
    e = im.crop((0, 0, 1280, 280)).getextrema()[1]
    h = im.histogram(); black = sum(h[:3]) / sum(h)
    if c > 200 and e < 20: s += 'N'
    elif black > 0.5 and hi > 100: s += 'C'
    elif hi <= 12: s += 'F'
    else: s += '?'
print(s)
