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
    hist = (f"vblank={sticky>>0&1} nmien={sticky>>1&1} nmiflag={sticky>>2&1} "
            f"w42xx={sticky>>3&1} w4200={sticky>>4&1}")
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


def summary_where(words, note=""):
    """Describe a TINYSNES_WHERE_PROBE snapshot: where the 65816 is and how it
    got there.

    The interesting field is `left`, the first PC below $8000 seen after the CPU
    had been above it.  Cartridge code in a LoROM is PC >= $8000 in every bank,
    so `left=----` means the CPU never left the image, and any value there is the
    address it departed from -- with `bank` naming the window it left through.
    """
    pc, banksp, psticky, left, rom = words
    pbr = banksp & 0xFF
    sp = (banksp >> 8) & 0xFF
    p = psticky & 0xFF
    st = (psticky >> 8) & 0xFF
    bits = "".join(
        f"{name}={val} " for name, val in
        (("halt", st & 1), ("wai", (st >> 1) & 1), ("armed", (st >> 2) & 1),
         ("left", (st >> 3) & 1), ("bank_nz", (st >> 4) & 1), ("rdy_low", (st >> 5) & 1))
    )
    return (f"PC={pc:04X} PBR={pbr:02X} SP={sp:02X} P={p:02X} "
            f"departure={left:04X} rom={rom:04X} | {bits.strip()}")


def summary_jump(words, note=""):
    """Describe a TINYSNES_JUMP_PROBE snapshot: the fetches before the departure.

    `rom` is the newest ROM address the mapper served before the CPU left, so
    the instruction that jumped ends there: a one-byte instruction such as RTS
    leaves `rom` on its own opcode, while an indirect jump leaves it on its last
    operand byte.  Disassembling backwards from `rom` in the image names the
    instruction; `prev` and `prev2` give the bytes before it for context.  A
    snapshot with every field zero and `departed=0` in the band means the CPU
    never left the cartridge on that boot.
    """
    pc, bankaddr, rom, prev, prev2top = words
    # The fields cross 16-bit word boundaries, so unpack from the whole 80-bit
    # value with the register widths rather than field by field: slicing the
    # words instead reads the high byte of one field as the low byte of the next
    # and produces plausible, wrong addresses.
    v = sum(w << (16 * i) for i, w in enumerate(words))
    d_pc   = v & 0xFFFF
    d_rbnk = (v >> 16) & 0xFF
    d_r0   = (v >> 24) & 0xFFFF
    d_r1   = (v >> 40) & 0xFFFF
    d_r2   = (v >> 56) & 0xFFFF
    d_pbr  = (v >> 72) & 0xFF
    pb = "unstable" if d_pbr == 0xFF else f"{d_pbr:02X}"
    return (f"departure={d_pc:04X} PBR={pb} rom={d_rbnk:02X}:{d_r0:04X} "
            f"prev={d_r1:04X} up2={d_r2:04X}")


def summary_stack(words, note=""):
    """Describe a TINYSNES_STACK_PROBE snapshot: what the RTL returned through.

    `RTL` pops three bytes -- PC low, PC high, then PBR -- starting at the stack
    pointer.  So the three writes shown are, when nothing was pushed after them,
    exactly the address the CPU returned to.  Compare `w0` against `departure`:
    if the popped PC matches the departure address the stack was right and the
    jump target is the fault, and if it does not the stack held something else.
    """
    v = sum(w << (16 * i) for i, w in enumerate(words))
    dpc  = v & 0xFFFF
    sp   = (v >> 16) & 0xFF
    a0   = (v >> 24) & 0xFF
    d0   = (v >> 32) & 0xFF
    a1   = (v >> 40) & 0xFF
    d1   = (v >> 48) & 0xFF
    a2   = (v >> 56) & 0xFF
    d2   = (v >> 64) & 0xFF
    cnt  = (v >> 72) & 0xFF
    return (f"departure={dpc:04X} SP={sp:02X} wrote={cnt:3d} | "
            f"w0={a0:02X}:{d0:02X} w1={a1:02X}:{d1:02X} w2={a2:02X}:{d2:02X}")


def summary_stackbytes(words, note=""):
    """Describe a TINYSNES_STACKBYTES_PROBE snapshot: the bytes RTL reads.

    `RTL` pulls PC low, then PC high, then PBR, incrementing S after each read.
    With the measured post-return SP of $01FD the three bytes are $01FA to
    $01FC, so `ret` below is the address those bytes spell.  A `ret` equal to
    the departure means the stack was correct and the jump target is the fault;
    a `ret` that is not means the stacked bytes were wrong.
    """
    dpc, sp_fa, fb_fc, fd_val, pbr_cnt = words
    sp   = sp_fa & 0xFF
    fa   = (sp_fa >> 8) & 0xFF
    fb   = fb_fc & 0xFF
    fc   = (fb_fc >> 8) & 0xFF
    fd   = fd_val & 0xFF
    val  = (fd_val >> 8) & 0xFF
    pbr  = pbr_cnt & 0xFF
    cnt  = (pbr_cnt >> 8) & 0xFF
    ret  = f"{fd:02X}:{fc:02X}{fb:02X}" if (val & 0b0110) == 0b0110 else "??"
    # The band carries the probe's own done bit: grey means {done, loaded,
    # enable} are all set, so a departure was recorded, and cyan means done is
    # clear, so no departure happened on this boot and every field below is the
    # unrefreshed initial value rather than a measurement.  Reporting the zeros
    # as an address was a real misreading and this guard exists to stop it.
    band = ""
    if "band (" in note:
        band = note.split("band (", 1)[1].rstrip(")")
        try:
            r, g, b = (int(x) for x in band.split(","))
        except ValueError:
            r = g = b = 0
        if r < 100 and g > 150 and b > 100:
            return f"NO DEPARTURE (band {band}: done=0, machine never left the image)"
    return (f"departure={dpc:04X} SP={sp:02X} ret={ret} | "
            f"FA={fa:02X} FB={fb:02X} FC={fc:02X} FD={fd:02X} "
            f"valid={val:04b} PBR={pbr:02X} wrote={cnt}")


def summary_insn(words, note=""):
    """Describe a TINYSNES_INSN_PROBE snapshot: did a JSR return through an RTL.

    The flag byte and the balance are cumulative over the boot, so unlike the
    snapshots of cycles 32 to 34 this reading does not depend on catching an
    event and does not need the band to validate it.  `unmatched` set means the
    CPU executed an `RTL` with no outstanding `JSL`, so the bank byte it pulled
    was never pushed by a long call -- the defect three cycles were circling.
    """
    v = sum(w << (16 * i) for i, w in enumerate(words))
    dpc  = v & 0xFFFF
    sp   = (v >> 16) & 0xFF
    fl   = (v >> 24) & 0xFF
    bal  = (v >> 32) & 0xFF
    insn = (v >> 40) & 0xFFFFFF
    rom  = (v >> 64) & 0xFFFF
    seen = "".join(n for n, b in (("JSR", 1), ("JSL", 2), ("RTL", 4), ("RTS", 8))
                   if fl & b) or "none"
    verdict = "UNMATCHED RTL" if fl & 0x10 else "paired"
    # The gate could only have manufactured the flag if a JSL landed in the
    # interrupt window; the ungated counts say whether removing it changed
    # anything at all.
    irq = "".join(n for n, b in (("jsl", 0x20), ("rtl", 0x40)) if fl & b) or "-"
    # The band is the authority on whether the latched snapshot fired (TCL-018).
    # The flags and the count are live so they stand on their own, but the
    # departure fields are latched and read as a full set of zeros when they did
    # not, which is not an address.  Cycle 34 made exactly this mistake once.
    if "band (" in note:
        try:
            r, g, b = (int(x) for x in note.split("band (", 1)[1].rstrip(")").split(","))
        except ValueError:
            r = g = b = 0
        if r < 100 and g > 150 and b > 100:
            return (f"{verdict}: saw {seen}, bal={bal} | "
                    f"ran={insn} instructions | NO DEPARTURE (band {r},{g},{b})")
    return (f"{verdict}: saw {seen}, bal={bal} | "
            f"ran={insn} instructions before leaving | "
            f"departure={dpc:04X} SP={sp:02X} rom={rom:04X} irqwin={irq}")


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
    ap.add_argument("--layout", choices=("link", "trace", "cpu", "irq", "where", "jump", "stack", "stackbytes", "insn"), default="link",
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
        fn = {"trace": summary_trace, "cpu": summary_cpu, "irq": summary_irq,
              "where": summary_where, "jump": summary_jump,
              "stack": summary_stack,
              "stackbytes": summary_stackbytes,
              "insn": summary_insn}.get(args.layout, summary_link)
        desc = fn(words) if fn in (summary_trace, summary_cpu, summary_irq,
                                         summary_link) else fn(words, note)
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
