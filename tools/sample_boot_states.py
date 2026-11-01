#!/usr/bin/env python3
"""Sample which failure state a TinySNES diagnostic build lands in, per boot.

Four consecutive loads of the same image produced four different failure shapes
(core-log entries 14, 15, 16).  A distribution over boots separates a marginal
timing path, which drifts, from a deterministic startup race, which always lands
the same way -- and it needs no new RTL, only repeated boots of a build that
already exists.

Each boot is a fresh bitstream load (which reconfigures the FPGA and so is a true
cold start) followed by a ROM stream, a short settle, and a capture.  The frames
are decoded with the same stripe sampler the other tools use.

    tools/sample_boot_states.py --fs build/past_s7/tinysnes.fs --boots 5

Requires openFPGALoader from oss-cad-suite, the capture card free, and the board
in one-wire mode.  Every boot reloads the bitstream, which clears the core's
`loaded` state, so the ROM is streamed again each time -- a diagnostic that sits
in its running state after a reload is waiting for a ROM, not running slowly.
"""
import argparse
import glob
import os
import shutil
import subprocess
import sys
import tempfile
import time

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from decode_probe_frame import classify, sample_stripe  # noqa: E402

GREEN = np.array([0x00, 0xC0, 0x00])
RED = np.array([0xC0, 0x00, 0x00])

# The five stripes of each diagnostic display, low to high.  The sampler only
# needs to know how to describe a decoded snapshot, so a layout is a formatter.
LINK_FIELDS = ["CPUO[1:0]", "CPUI[1:0]", "65816 A", "65816 PC", "hist/Y"]
TRACE_FIELDS = ["newest ROM addr", "previous", "two back", "three back", "ROM_ADDR[23:8]"]


def decode_stripes(path, x0=160, x1=1119, pitch=103.0 / 32.0):
    """Return the five stripe words, or None if the frame is torn."""
    img = np.array(Image.open(path).convert("RGB"))
    cls = classify(img)
    words = []
    for b in range(5):
        vals = set()
        for frac in (0.4, 0.5, 0.6):
            y = int(round((b * 32 + 24 * frac) * pitch))
            bits = sample_stripe(cls, x0, x1, y)
            if bits is None:
                return None
            vals.add(sum(bit << i for i, bit in enumerate(bits)))
        if len(vals) != 1:
            return None      # the sample rows disagree: torn frame
        words.append(vals.pop())
    return words


def band_colour(path):
    img = np.array(Image.open(path).convert("RGB"))
    band = img[620:700, 200:1080]
    cols, cnts = np.unique(band.reshape(-1, 3), axis=0, return_counts=True)
    return tuple(int(v) for v in cols[int(np.argmax(cnts))])


def summary_irq(words):
    """Describe a TINYSNES_IRQ_PROBE snapshot: interrupt history plus the halt.

    The sampler's concat is {48'd0, pc_hi, pc_lo, status, sticky}, so stripe 1
    carries status above sticky, stripe 2 the halt PC, and stripes 3-5 are zero.
    The first version of this formatter assumed the fields were in the order the
    RTL comment listed rather than the order the concat produces, and reported a
    five-digit program counter -- a reading impossible on a 16-bit bus, which is
    what exposed it.
    """
    sticky = words[0] & 0xFF
    status = (words[0] >> 8) & 0xFF
    pc     = words[1]
    hist = (f"vblank={sticky>>0&1} nmien={sticky>>1&1} nmiflag={sticky>>2&1}")
    st = (f"wai={status>>1&1} stp={status&1} en={status>>2&1}")
    return f"PC={pc:04X} status={status:02X} | {st} | {hist}"


def summary_cpu(words):
    """Describe a TINYSNES_CPU_PROBE snapshot: ROM accesses, PC, SP and status."""
    acc_hi, acc_lo, pc, sp, status = words
    acc = (acc_hi << 16) | acc_lo
    flags = (f"int={status>>7&1} rst={status>>6&1} nmi={status>>5&1} irq={status>>4&1} "
             f"rdy={status>>3&1} en={status>>2&1} wai={status>>1&1} stp={status&1}")
    return f"ROMacc={acc:5d} PC={pc:04X} SP={sp:04X} status={status:02X} | {flags}"


def summary_trace(words):
    """Describe a TINYSNES_TRACE_PROBE snapshot: the last four ROM fetches.

    The ring advances only on a ROM access, so on a machine that has left the ROM
    it is frozen on exactly the fetches before the jump, and the newest entry
    names the instruction that diverted it.
    """
    a0, a1, a2, a3, hi = words
    full = (hi << 8) | (a0 >> 8)          # ROM_ADDR[23:8] over ROM_ADDR[15:8]
    return (f"newest={a0:04X} prev={a1:04X} {a2:04X} {a3:04X} "
            f"addr[23:8]={hi:04X} full={full:06X}")


def summary_link(words):
    """Describe a TINYSNES_LINK_PROBE snapshot in the terms the log uses."""
    cpuo, cpui, a, pc, hist = words
    ent = hist >> 13
    past = (hist >> 12) & 1
    cc = (hist >> 11) & 1
    ipl = (hist >> 10) & 1
    y = (hist >> 9) & 1
    cpuo_seen = (hist >> 8) & 1
    ynow = hist & 0xFF
    bits = "".join(
        f"{name}={val} " for name, val in
        (("entry", ent), ("past", past), ("cc", cc), ("ipl", ipl), ("y", y), ("cpuo", cpuo_seen))
    )
    return (f"CPUO={cpuo:04X} CPUI={cpui:04X} A={a:04X} PC={pc:04X} Y={ynow:02X} | {bits.strip()}")


def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


def one_boot(args, index, workdir):
    capdir = os.path.join(workdir, f"boot{index}")
    os.makedirs(capdir, exist_ok=True)

    r = run([args.loader, "-b", args.board, args.fs])
    if r.returncode != 0 or "Done" not in (r.stdout + r.stderr):
        return None, f"bitstream load failed: {r.stdout[-200:]} {r.stderr[-200:]}"

    r = run([args.python, args.loader_rom, args.rom, "--uart", args.uart])
    if r.returncode != 0:
        return None, f"ROM stream failed: {r.stderr[-200:]}"

    time.sleep(args.settle)
    r = run([
        "ffmpeg", "-hide_banner", "-loglevel", "error", "-f", "v4l2",
        "-i", args.video, "-t", "3", "-vsync", "0", "-pix_fmt", "rgb24",
        os.path.join(capdir, "f%03d.png"),
    ])
    frames = sorted(glob.glob(os.path.join(capdir, "f*.png")))
    if not frames:
        return None, "no frames captured"

    # Majority over every decodable frame; a single frame can be torn.
    counts = {}
    for f in frames:
        w = decode_stripes(f)
        if w is not None:
            counts[tuple(w)] = counts.get(tuple(w), 0) + 1
    if not counts:
        return None, f"{len(frames)} frames captured, none decodable"
    best = max(counts, key=counts.get)
    return best, f"{counts[best]}/{len(frames)} frames agreed, band {band_colour(frames[len(frames)//2])}"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--fs", required=True, help="bitstream to boot each time")
    ap.add_argument("--rom", default="/tmp/zelda.smc")
    ap.add_argument("--uart", default="/dev/ttyUSB1")
    ap.add_argument("--video", default="/dev/video0")
    ap.add_argument("--board", default="tangconsole")
    ap.add_argument("--boots", type=int, default=5)
    ap.add_argument("--layout", choices=("link", "trace", "cpu", "irq"), default="link",
                    help="which diagnostic display the build draws")
    ap.add_argument("--settle", type=float, default=3.0)
    ap.add_argument("--loader", default=os.path.expanduser("~/oss-cad-suite/bin/openFPGALoader"))
    ap.add_argument("--loader-rom", default=os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "load_snes_rom.py"))
    ap.add_argument("--python", default=sys.executable)
    args = ap.parse_args()

    workdir = tempfile.mkdtemp(prefix="bootstates-")
    states = {}
    for i in range(1, args.boots + 1):
        words, note = one_boot(args, i, workdir)
        if words is None:
            print(f"boot {i}: FAILED -- {note}")
            continue
        desc = {"trace": summary_trace, "cpu": summary_cpu,
                "irq": summary_irq}.get(args.layout, summary_link)(words)
        states[desc] = states.get(desc, 0) + 1
        print(f"boot {i}: {desc}")
        print(f"         {note}")

    print()
    if not states:
        print("no boot produced a decodable state")
        return 1
    print(f"{len(states)} distinct state(s) over {sum(states.values())} decodable boots:")
    for desc, n in sorted(states.items(), key=lambda kv: -kv[1]):
        print(f"  {n}x  {desc}")
    print()
    if len(states) == 1 and sum(states.values()) > 1:
        print("VERDICT: every boot landed in the same state -- deterministic.")
    elif len(states) > 1:
        print("VERDICT: boots differ -- the failure is nondeterministic, which points")
        print("         at a marginal timing path or a race rather than a logic error.")
    else:
        print("VERDICT: inconclusive, one boot only.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
