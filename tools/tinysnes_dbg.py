#!/usr/bin/env python3
"""Read and drive TinySNES's debug register bank (fpga/snes/src/tinysnes_dbg.v).

The core answers frame type 0x10 on its BL616 UART: TinyTang's `fpgar <addr>`
reads one register from the console, and this tool does everything else through
`fpgapipe`, the same way tools/load_snes_rom.py loads a ROM.  The board must be
in two-wire mode with the console at the shell prompt.

    tools/tinysnes_dbg.py status [--watch SECONDS]
    tools/tinysnes_dbg.py rd ADDR [COUNT]
    tools/tinysnes_dbg.py wr ADDR VALUE
    tools/tinysnes_dbg.py knob [N]               GSU minimum ROM_CYCLES before ROM ready, 1..13; 0 = built-in 1
    tools/tinysnes_dbg.py peek bsram|wram ADDR [LEN]   (reads 0: peek ports not built)
    tools/tinysnes_dbg.py trace arm [--only rl,op,mm] [--no-reads] [--linear] [--go N]
    tools/tinysnes_dbg.py trace stop
    tools/tinysnes_dbg.py trace dump BASE        writes BASE_{rl,op,mm}.hex + BASE_meta.txt
    tools/tinysnes_dbg.py analyze --dump BASE --rom GAME.sfc

`analyze` needs no board: it reads a dump written by `trace dump` or by
board_tb's +tracedump (tools/sim/run_board_sim.sh writes build/<out>/trace_*),
so the bench and the board are checked by the same code.  In the bench every GSU
ROM latch should equal the cartridge byte at its address; on a board that shows
a blank screen, the first latch that does not is where the GSU went wrong.
"""

from __future__ import annotations

import argparse
import os
import re
import sys
import time

PROBE = b"\x1b[?77n"
REPLY = re.compile(rb"\x1b\[\?77;(\d+)n")
AT_PROMPT = 1

EXT_TYPE = 0x10
EXT_VERSION = 1
OP_CAPS, OP_READ, OP_WRITE = 0, 1, 2
STATUS_NAMES = {0: "ok", 1: "bad version", 2: "bad opcode", 3: "bad CRC"}

MAGIC = 0x54534431
TRACE_BASE = 0x10000
TRACE_STRIDE = 0x4000
BUFS = ("rl", "op", "mm")

REG = dict(magic=0x000, layout=0x004, frames=0x008, uptime=0x00C, board=0x010,
           go_sfr=0x020, pc=0x024, flags=0x028, stops=0x02C, bsram_wrs=0x030,
           rom_reqs=0x034, rom_defers=0x038, rom_timeouts=0x03C, knob=0x040,
           scratch=0x044, go_time=0x048, audio_ovf=0x050, audio_unf=0x054,
           i2s=0x058, i2s_unf=0x05C, ctrl=0x100, tstate=0x104)
MCLK = 21_484_000

GSU_REGS = {0x3030: "SFR", 0x3031: "SFRh", 0x3033: "BRAMR", 0x3034: "PBR",
            0x3036: "ROMBR", 0x3037: "CFGR", 0x3038: "SCBR", 0x3039: "CLSR",
            0x303A: "SCMR", 0x303B: "VCR", 0x303C: "RAMBR", 0x303E: "CBRl",
            0x303F: "CBRh"}


def crc16(data: bytes, crc: int = 0xFFFF) -> int:
    for b in data:
        crc ^= b << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021) if crc & 0x8000 else crc << 1
            crc &= 0xFFFF
    return crc


# --------------------------------------------------------------------- link
class Link:
    def __init__(self, args):
        try:
            import serial
        except ImportError:
            sys.exit("pyserial is required:  pip install pyserial")
        self.seq = 0
        self.buf = b""
        if args.uart:
            self.port = serial.Serial(args.uart, 2000000, timeout=0.02)
            return
        self.port = serial.Serial(args.port, args.baud, timeout=0.02)
        state = self._probe()
        if state != AT_PROMPT:
            names = {2: "running the desktop", 3: "busy running a command", None: "no answer"}
            self.port.close()
            raise SystemExit(f"console is {names.get(state, state)}; put it at the shell prompt")
        self.port.reset_input_buffer()
        self.port.write(b"fpgapipe\r\n")
        self.port.flush()
        deadline = time.time() + 5
        seen = b""
        while time.time() < deadline and b"fpgapipe: open at" not in seen:
            seen += self.port.read(256)
        if b"fpgapipe: open at" not in seen:
            self.port.close()
            raise SystemExit(f"fpgapipe did not open; console said: {seen[-200:]!r}")
        # Whatever follows the banner on the same read is core traffic.
        self.buf = seen.split(b"fpgapipe: open at", 1)[1]
        nl = self.buf.find(b"\n")
        self.buf = self.buf[nl + 1:] if nl >= 0 else b""

    def _probe(self, seconds: float = 2.0):
        self.port.reset_input_buffer()
        self.port.write(PROBE)
        self.port.flush()
        deadline = time.time() + seconds
        buf = b""
        while time.time() < deadline:
            buf += self.port.read(64)
            m = REPLY.search(buf)
            if m:
                return int(m.group(1))
        return None

    def close(self):
        time.sleep(0.05)
        self.port.close()                       # DTR drop ends fpgapipe

    def _need(self, n: int, deadline: float) -> bool:
        while len(self.buf) < n:
            if time.time() > deadline:
                return False
            self.buf += self.port.read(max(64, n - len(self.buf)))
        return True

    def _reply(self, timeout: float):
        """Next 0x10 frame; joypad (0x03) and anything else is skipped."""
        deadline = time.time() + timeout
        while True:
            if not self._need(1, deadline):
                return None
            i = self.buf.find(b"\xAA")
            if i < 0:
                self.buf = b""
                continue
            self.buf = self.buf[i:]
            if not self._need(4, deadline):
                return None
            n = (self.buf[1] << 8) | self.buf[2]
            if n == 0 or n > 2047:
                self.buf = self.buf[1:]
                continue
            if not self._need(3 + n, deadline):
                return None
            body, self.buf = self.buf[3:3 + n], self.buf[3 + n:]
            if body[0] == EXT_TYPE and n == 16:
                return body

    def xfer(self, opcode: int, addr: int, value: int = 0, retries: int = 3) -> int:
        for attempt in range(retries):
            self.seq = (self.seq + 1) & 0xFFFF
            body = bytes([EXT_TYPE, EXT_VERSION, opcode, self.seq >> 8, self.seq & 0xFF]) \
                + addr.to_bytes(4, "big") + (value & 0xFFFFFFFF).to_bytes(4, "big")
            c = crc16(body)
            pkt = body + bytes([c >> 8, c & 0xFF])
            self.port.write(bytes([0xAA, 0, len(pkt)]) + pkt)
            self.port.flush()
            while True:
                r = self._reply(0.5)
                if r is None:
                    break
                if crc16(r[:14]) != (r[14] << 8 | r[15]):
                    print(f"  reply CRC error (seq {self.seq})", file=sys.stderr)
                    break
                seq = r[4] << 8 | r[5]
                if seq != self.seq:
                    continue                    # a late reply to an earlier try
                if r[2] != (opcode | 0x80):
                    raise SystemExit(f"reply opcode {r[2]:02x} for {opcode:02x}")
                if r[3] != 0:
                    raise SystemExit(f"core says {STATUS_NAMES.get(r[3], r[3])} "
                                     f"for opcode {opcode} at {addr:#x}")
                return int.from_bytes(r[10:14], "big")
            print(f"  no reply for {addr:#x}, retry {attempt + 1}", file=sys.stderr)
        raise SystemExit(f"no reply from the core for {addr:#x}: is the debug build loaded?")

    def rd(self, addr: int) -> int:
        return self.xfer(OP_READ, addr)

    def wr(self, addr: int, value: int) -> int:
        return self.xfer(OP_WRITE, addr, value)


def open_link(args) -> Link:
    link = Link(args)
    magic = link.rd(REG["magic"])
    if magic != MAGIC:
        link.close()
        raise SystemExit(f"register 0 reads {magic:#010x}, not 'TSD1': not a debug build")
    return link


# ------------------------------------------------------------------ status
def sfr_text(sfr: int) -> str:
    names = ["", "Z", "CY", "S", "OV", "GO", "R", "", "ALT1", "ALT2", "IL", "IH", "B", "", "", "IRQ"]
    return " ".join(n for i, n in enumerate(names) if n and sfr >> i & 1) or "-"


def read_status(link: Link) -> dict:
    return {k: link.rd(a) for k, a in REG.items()}


def show_status(r: dict, prev: dict | None, dt: float) -> None:
    up = r["uptime"] / MCLK
    b = r["board"]
    print(f"uptime {up:9.2f} s   frames {r['frames']}   board "
          f"{'loading ' if b & 1 else ''}{'loaded ' if b & 2 else ''}"
          f"{'enable ' if b & 4 else ''}{'gsu' if b & 8 else 'no-gsu'}")
    go, sfr = r["go_sfr"] >> 16, r["go_sfr"] & 0xFFFF
    pc = r["pc"]
    f = r["flags"]
    print(f"GSU  GO starts {go}   stops {r['stops']}   SFR {sfr:04x} [{sfr_text(sfr)}]   "
          f"PC {pc >> 16:02x}:{pc & 0xFFFF:04x}   GO time {r['go_time'] / MCLK:.2f} s "
          f"({100 * r['go_time'] / max(r['uptime'], 1):.1f}%)")
    print(f"     romst {f >> 5 & 7}  seen {f >> 8 & 0x7F:07b}  states {f >> 16:016b}  "
          f"en {f >> 4 & 1} in_cache {f >> 3 & 1} rom_cache_wait {f >> 2 & 1} "
          f"rom_load_wait {f >> 1 & 1} cache_any {f & 1}")
    knob = r["knob"]
    print(f"cart ROM reads {r['rom_reqs']}   deferred {r['rom_defers']}   "
          f"timeouts {r['rom_timeouts']}   BSRAM writes {r['bsram_wrs']}   "
          f"ROM_CYCLES {knob if knob else 'default (1, then ROM ready)'}")
    # Audio FIFO health.  These should not move with the servos locked; a rising
    # count is a sample the core dropped or a read that found the FIFO empty.
    i2s = r["i2s"]
    print(f"audio   HDMI overflow {r['audio_ovf']}  underrun {r['audio_unf']}   "
          f"Pmod taken {i2s & 0xFFFF}  overflow {i2s >> 16}  underrun {r['i2s_unf']}")
    if prev and dt > 0:
        rate = lambda k: (r[k] - prev[k]) / dt
        print(f"rates/s  frames {rate('frames'):.1f}  GO {((r['go_sfr'] >> 16) - (prev['go_sfr'] >> 16)) % 65536 / dt:.1f}"
              f"  stops {rate('stops'):.1f}  BSRAM wr {rate('bsram_wrs'):.0f}"
              f"  ROM rd {rate('rom_reqs'):.0f}  timeouts {rate('rom_timeouts'):.1f}")
    print(f"trace ctrl {r['ctrl']:#06x}  {'recording' if r['tstate'] & 1 else 'stopped'}"
          f"{' (waiting for GO)' if r['tstate'] & 2 else ''}")


# ------------------------------------------------------------------- trace
def write_dump(base: str, words: list[list[int]], meta: dict) -> None:
    for name, ws in zip(BUFS, words):
        with open(f"{base}_{name}.hex", "w") as fh:
            for w in ws:
                fh.write(f"{w:016x}\n")
    with open(f"{base}_meta.txt", "w") as fh:
        for k, v in meta.items():
            fh.write(f"{k} {' '.join(str(x) for x in v) if isinstance(v, list) else v}\n")


def trace_dump(link: Link, base: str) -> None:
    ctrl = link.rd(REG["ctrl"])
    if link.rd(REG["tstate"]) & 1:
        link.wr(REG["ctrl"], ctrl & ~1)          # freeze; run=0 keeps the contents
        print("trace stopped for the dump")
    depth = 1 << (link.rd(REG["layout"]) & 0xFFFF)
    meta = {"ctrl": ctrl, "wp": [], "wrapped": [], "full": [], "seen": []}
    words = []
    for b, name in enumerate(BUFS):
        st = link.rd(0x110 + 4 * b)
        wp, wrapped, full = st & 0xFFFF, st >> 31 & 1, st >> 30 & 1
        seen = link.rd(0x120 + 4 * b)
        meta["wp"].append(wp); meta["wrapped"].append(wrapped)
        meta["full"].append(full); meta["seen"].append(seen)
        valid = range(depth) if (wrapped or full) else range(wp)
        ws = [0] * depth
        t0 = time.time()
        for i in valid:
            a = TRACE_BASE + b * TRACE_STRIDE + i * 8
            ws[i] = link.rd(a) << 32 | link.rd(a + 4)
        words.append(ws)
        print(f"  {name}: {len(valid)} entries ({seen} seen) in {time.time() - t0:.1f}s")
    for k in ("uptime", "frames", "stops", "go_time", "bsram_wrs", "rom_reqs",
              "rom_defers", "rom_timeouts"):
        meta[k] = link.rd(REG[k])
    write_dump(base, words, meta)
    print(f"wrote {base}_{{rl,op,mm}}.hex and {base}_meta.txt")


def read_dump(base: str):
    meta = {}
    with open(f"{base}_meta.txt") as fh:
        for line in fh:
            k, *v = line.split()
            meta[k] = [int(x) for x in v] if len(v) > 1 else int(v[0])
    bufs = []
    for b, name in enumerate(BUFS):
        ws = []
        with open(f"{base}_{name}.hex") as fh:
            for line in fh:
                line = line.split("//")[0].strip()
                if not line or line.startswith("@"):
                    continue
                ws.append(int(line.replace("x", "0").replace("X", "0"), 16))
        wp, wrapped, full = meta["wp"][b], meta["wrapped"][b], meta["full"][b]
        if wrapped:
            order = ws[wp:] + ws[:wp]
        elif full:
            order = ws
        else:
            order = ws[:wp]
        bufs.append([(w >> 60, w >> 32 & 0xFFFFFFF, w & 0xFFFFFFFF) for w in order])
    return meta, bufs


# ----------------------------------------------------------------- analyze
def rom_offset(pbr: int, r15: int) -> int | None:
    if pbr < 0x40:
        return (pbr & 0x3F) << 15 | (r15 & 0x7FFF)
    if pbr < 0x60:
        return (pbr & 0x1F) << 16 | r15
    return None


def analyze(base: str, rom_path: str, show: int) -> None:
    rom = open(rom_path, "rb").read()
    if len(rom) % 1024 == 512:
        rom = rom[512:]
    size = len(rom)
    mask = size - 1 if size & (size - 1) == 0 else None
    at = lambda a: rom[(a & mask) if mask is not None else a % size]
    meta, (rl, op, mm) = read_dump(base)

    print(f"dump {base}: ctrl {meta['ctrl']:#x}  entries rl {len(rl)} op {len(op)} mm {len(mm)}  "
          f"seen {meta['seen']}")
    for k in ("uptime", "frames", "stops", "go_time", "rom_reqs", "rom_defers", "rom_timeouts",
              "bsram_wrs"):
        if k in meta:
            print(f"  {k} {meta[k]}")

    # ROM latches: the byte the GSU took against the cartridge at ROM_A.
    kinds = {1: "LOAD", 2: "FETCH", 3: "CACHE"}
    print("\nGSU ROM latches (byte latched vs. cartridge at ROM_A):")
    first_bad = None
    for k, kname in kinds.items():
        ev = [(i, ts, p) for i, (tag, ts, p) in enumerate(rl) if tag & 3 == k]
        if not ev:
            continue
        good = sum(1 for _, _, p in ev if p & 0xFF == at(p >> 8 & 0x1FFFFF))
        near = {d: sum(1 for _, _, p in ev if p & 0xFF == at((p >> 8 & 0x1FFFFF) + d))
                for d in (-2, -1, 1, 2)}
        print(f"  {kname:5s} {good}/{len(ev)} match ({100 * good / len(ev):.1f}%)   "
              f"as if A-2..A+2: {near[-2]} {near[-1]} . {near[1]} {near[2]}")
        for i, ts, p in ev:
            if p & 0xFF != at(p >> 8 & 0x1FFFFF) and (first_bad is None or i < first_bad[0]):
                first_bad = (i, ts, p, kname)
    bad = [(i, ts, p) for i, (tag, ts, p) in enumerate(rl)
           if p & 0xFF != at(p >> 8 & 0x1FFFFF)]
    if bad and show:
        print(f"  first {min(show, len(bad))} mismatches (index, mclk, kind, ROM_A, got, want):")
        for i, ts, p in bad[:show]:
            a = p >> 8 & 0x1FFFFF
            print(f"    {i:4d} {ts:9d} {kinds.get(rl[i][0] & 3, '?'):5s} {a:06x} "
                  f"got {p & 0xFF:02x} want {at(a):02x}")

    # Opcodes: the byte decoded against the cartridge at PBR:R15.
    srcs = {1: "cache", 2: "ROM", 3: "RAM"}
    print("\nGSU opcodes (byte decoded vs. cartridge at PBR:R15+d):")
    for s, sname in srcs.items():
        ev = [p for tag, ts, p in op if tag & 3 == s]
        if not ev:
            continue
        if s == 3:
            print(f"  {sname:5s} {len(ev)} (executing from RAM, not checked)")
            continue
        hist = {}
        for d in (-2, -1, 0, 1):
            n = 0
            for p in ev:
                o = rom_offset(p >> 24, p >> 8 & 0xFFFF)
                if o is not None and p & 0xFF == at(o + d):
                    n += 1
            hist[d] = n
        best = max(hist, key=hist.get)
        print(f"  {sname:5s} {len(ev)} opcodes; match at R15-2..R15+1: "
              f"{hist[-2]} {hist[-1]} {hist[0]} {hist[1]}   (best d={best}, "
              f"{100 * hist[best] / len(ev):.1f}%)")
    pcs = {}
    for tag, ts, p in op:
        pcs[p >> 8] = pcs.get(p >> 8, 0) + 1
    if pcs:
        top = sorted(pcs.items(), key=lambda kv: -kv[1])[:8]
        print("  hottest PCs: " + "  ".join(f"{pc >> 16:02x}:{pc & 0xFFFF:04x}x{n}" for pc, n in top))
        last = op[-show:] if show else []
        if last:
            print(f"  last {len(last)} opcodes (mclk, src, PBR:R15, byte):")
            for tag, ts, p in last:
                print(f"    {ts:9d} {srcs.get(tag & 3, '?'):5s} {p >> 24:02x}:{p >> 8 & 0xFFFF:04x} {p & 0xFF:02x}")

    # S-CPU accesses to the GSU's registers, newest last.
    if mm:
        print(f"\nS-CPU <-> GSU register accesses, last {min(len(mm), max(show, 1) * 2)}:")
        for tag, ts, p in mm[-max(show, 1) * 2:]:
            wr = p >> 31 & 1
            a = p >> 8 & 0xFFFF
            name = GSU_REGS.get(a) or (f"R{(a - 0x3000) >> 1}{'h' if a & 1 else 'l'}"
                                       if 0x3000 <= a < 0x3020 else
                                       "cache" if 0x3100 <= a < 0x3300 else f"{a:04x}")
            print(f"    {ts:9d} {'W' if wr else 'R'} {a:04x} {name:6s} {p & 0xFF:02x}")


# -------------------------------------------------------------------- main
def num(s: str) -> int:
    return int(s, 0)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--port", default="/dev/ttyACM0")
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--uart", metavar="DEV",
                    help="talk to the core's UART directly at 2 Mbaud (one-wire mode)")
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("status"); p.add_argument("--watch", type=float, default=0)
    p = sub.add_parser("rd"); p.add_argument("addr", type=num); p.add_argument("count", type=num, nargs="?", default=1)
    p = sub.add_parser("wr"); p.add_argument("addr", type=num); p.add_argument("value", type=num)
    p = sub.add_parser("knob"); p.add_argument("n", type=num, nargs="?")
    p = sub.add_parser("peek"); p.add_argument("mem", choices=["bsram", "wram"])
    p.add_argument("addr", type=num); p.add_argument("length", type=num, nargs="?", default=64)
    p = sub.add_parser("trace"); p.add_argument("action", choices=["arm", "stop", "dump"])
    p.add_argument("base", nargs="?")
    p.add_argument("--only", default="rl,op,mm")
    p.add_argument("--no-reads", action="store_true", help="MMIO buffer records S-CPU writes only")
    p.add_argument("--linear", action="store_true", help="stop each buffer when full instead of wrapping")
    p.add_argument("--go", type=num, metavar="N",
                   help="start at a GSU GO rising edge, after skipping N of them")
    p = sub.add_parser("analyze"); p.add_argument("--dump", required=True)
    p.add_argument("--rom", required=True); p.add_argument("--show", type=int, default=16)
    args = ap.parse_args()

    if args.cmd == "analyze":
        analyze(args.dump, args.rom, args.show)
        return 0

    link = open_link(args)
    try:
        if args.cmd == "status":
            prev, t_prev = None, time.time()
            while True:
                r = read_status(link)
                now = time.time()
                show_status(r, prev, now - t_prev)
                if not args.watch:
                    break
                prev, t_prev = r, now
                print()
                time.sleep(args.watch)
        elif args.cmd == "rd":
            for i in range(args.count):
                a = args.addr + 4 * i
                print(f"{a:08x}: {link.rd(a):08x}")
        elif args.cmd == "wr":
            link.wr(args.addr, args.value)
            print(f"{args.addr:08x} <- {args.value:08x}; reads {link.rd(args.addr):08x}")
        elif args.cmd == "knob":
            if args.n is not None:
                if not 0 <= args.n <= 13:
                    raise SystemExit("ROM_CYCLES is 1..13, or 0 for the built-in 1")
                link.wr(REG["knob"], args.n)
            k = link.rd(REG["knob"])
            print(f"GSU ROM_CYCLES {k if k else 'default (1, then ROM ready)'}")
        elif args.cmd == "peek":
            base = 0x01000000 if args.mem == "bsram" else 0x02000000
            a0 = args.addr & ~3
            data = b""
            for a in range(a0, args.addr + args.length, 4):
                data += link.rd(base + (a & 0x1FFFF)).to_bytes(4, "little")
            data = data[args.addr - a0:args.addr - a0 + args.length]
            for i in range(0, len(data), 16):
                row = data[i:i + 16]
                print(f"{args.mem} {args.addr + i:05x}: {row.hex(' ')}")
        elif args.cmd == "trace":
            if args.action == "arm":
                en = {"rl": 1 << 3, "op": 1 << 4, "mm": 1 << 5}
                ctrl = 1 | (0 if args.linear else 2)
                for s in args.only.split(","):
                    ctrl |= en[s.strip()]
                if not args.no_reads:
                    ctrl |= 1 << 6
                if args.go is not None:
                    ctrl |= 4 | (args.go & 0xFFFF) << 16
                link.wr(REG["ctrl"], ctrl)
                print(f"trace armed, ctrl {ctrl:#x}")
            elif args.action == "stop":
                link.wr(REG["ctrl"], link.rd(REG["ctrl"]) & ~1)
                print("trace stopped")
            else:
                if not args.base:
                    raise SystemExit("trace dump needs a BASE path")
                d = os.path.dirname(args.base)
                if d:
                    os.makedirs(d, exist_ok=True)
                trace_dump(link, args.base)
    finally:
        link.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
