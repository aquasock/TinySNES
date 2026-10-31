#!/usr/bin/env python3
"""Load a SNES ROM into a loaded TinySNES core, over the board's console.

TinyTang's firmware has `nesload` for iNES images only, and it refuses anything
without the NES\\x1a magic.  This tool takes the same path the firmware's own
loader would: it puts the console into `fpgapipe` (raw bytes to and from the
core's UART1) and speaks the TangCore frame protocol that SNESTang's iosys
implements.

    tools/load_snes_rom.py game.sfc
    tools/load_snes_rom.py game.smc --dry-run

The protocol, from fpga/snes/src/iosys/iosys_bl616.v:

    0xAA len[15:0] payload...            len counts the type byte
    0x06 loading_state[7:0]              non-zero holds the core in reset and
                                         opens the ROM window; 0 starts the game
    0x07 <data>                          ROM bytes into the core's loader
    0x08 x[7:0]                          x[0] is the OSD overlay on/off

The core parses its 64-byte SNES header from the *first* bytes of the stream and
writes to SDRAM only after that header is complete (snestang_top.v: loader_addr
resets on the loading edge and counts only while header_finished).  So the
stream is: the 64 header bytes at the image's LoROM/HiROM header offset, then
the image from offset 0.  A 512-byte copier header is stripped first, because it
would otherwise shift the whole image in SDRAM.

The board must be in two-wire mode, a TinySNES core must be loaded, and the
console must be at a shell prompt: the state is probed first, exactly as
TinyTang's own tools do, because bytes sent to a running desktop or command are
typed into it instead of reaching the core.
"""

from __future__ import annotations

import argparse
import re
import sys
import time

try:
    import serial
except ImportError:
    sys.exit("pyserial is required:  pip install pyserial")

PROBE = b"\x1b[?77n"
REPLY = re.compile(rb"\x1b\[\?77;(\d+)n")
AT_PROMPT = 1
CHUNK = 1024                      # len = 1 + 1024 = 1025, below the core's 2048 limit
FRAME_MAGIC = 0xAA


def frame(payload: bytes) -> bytes:
    n = len(payload)
    if n >= 2048:
        raise ValueError(f"frame of {n} bytes exceeds the core's 2047-byte limit")
    return bytes([FRAME_MAGIC, (n >> 8) & 0xFF, n & 0xFF]) + payload


def probe_state(port: serial.Serial, seconds: float = 2.0) -> int | None:
    port.reset_input_buffer()
    port.write(PROBE)
    port.flush()
    deadline = time.time() + seconds
    buf = b""
    while time.time() < deadline:
        chunk = port.read(64)
        if chunk:
            buf += chunk
            m = REPLY.search(buf)
            if m:
                return int(m.group(1))
    return None


def score_header(rom: bytes, base: int) -> int:
    """How much the 64 bytes at `base` look like a SNES header (0 = no)."""
    if base + 0x40 > len(rom):
        return 0
    h = rom[base:base + 0x40]
    score = 0
    checksum = h[0x1E] | (h[0x1F] << 8)
    complement = h[0x1C] | (h[0x1D] << 8)
    if checksum ^ complement == 0xFFFF and checksum != 0:
        score += 3
    if (h[0x15] & 0x0F) in (0, 1, 2, 3, 5):
        score += 2
    if 1 <= (h[0x17] & 0x0F) <= 0x0D:
        score += 1
    if all(0x20 <= c < 0x7F for c in h[0x10:0x15]):
        score += 1
    return score


def find_header(rom: bytes) -> tuple[int, str]:
    lo = score_header(rom, 0x7FC0)
    hi = score_header(rom, 0xFFC0)
    if lo == 0 and hi == 0:
        raise SystemExit("no plausible SNES header at 0x7FC0 or 0xFFC0")
    if hi > lo:
        return 0xFFC0, f"HiROM (score {hi} vs {lo})"
    return 0x7FC0, f"LoROM (score {lo} vs HiROM {hi})"


def strip_copier_header(rom: bytes) -> tuple[bytes, str]:
    if len(rom) % 1024 == 512:
        return rom[512:], "stripped a 512-byte copier header"
    return rom, "no copier header"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("rom")
    ap.add_argument("--port", default="/dev/ttyACM0")
    ap.add_argument("--baud", type=int, default=115200,
                    help="the console's rate; UART1's own rate is set by the firmware")
    ap.add_argument("--dry-run", action="store_true",
                    help="report header detection and the transfer plan, send nothing")
    ap.add_argument("--uart", metavar="DEV",
                    help="write the frames straight to the core's own UART, as the "
                         "BL616 would, instead of going through the console's fpgapipe "
                         "(one-wire mode: /dev/ttyUSB1 at 2000000 baud)")
    args = ap.parse_args()

    raw = open(args.rom, "rb").read()
    image, note = strip_copier_header(raw)
    header_off, which = find_header(image)
    print(f"{args.rom}: {len(raw)} bytes, {note}; {which}, header at 0x{header_off:04X}")
    print(f"plan: 64 header bytes, then {len(image)} image bytes in "
          f"{(len(image) + CHUNK - 1) // CHUNK} frames")
    if args.dry_run:
        return 0

    if args.uart:
        port = serial.Serial(args.uart, 2000000, timeout=0.05)
    else:
        port = serial.Serial(args.port, args.baud, timeout=0.05)
        state = probe_state(port)
        if state != AT_PROMPT:
            names = {2: "running the desktop", 3: "busy running a command", None: "no answer"}
            raise SystemExit(f"console is {names.get(state, state)}; put it at the shell prompt")

        port.reset_input_buffer()
        port.write(b"fpgapipe\r\n")
        port.flush()
        deadline = time.time() + 5
        seen = b""
        while time.time() < deadline and b"fpgapipe: open at" not in seen:
            seen += port.read(256)
        if b"fpgapipe: open at" not in seen:
            raise SystemExit(f"fpgapipe did not open; console said: {seen[-200:]!r}")
        print("fpgapipe open")

    def send(payload: bytes) -> None:
        port.write(frame(payload))
        port.flush()

    try:
        send(b"\x06\x01")                       # hold the core in reset, open the ROM window
        time.sleep(0.05)
        send(b"\x07" + image[header_off:header_off + 0x40])
        sent = 0
        started = time.time()
        for off in range(0, len(image), CHUNK):
            send(b"\x07" + image[off:off + CHUNK])
            sent += min(CHUNK, len(image) - off)
            if sent % (CHUNK * 64) == 0:
                rate = sent / max(time.time() - started, 1e-6)
                print(f"  {sent}/{len(image)} bytes, {rate / 1024:.0f} KB/s", flush=True)
        # Let the loader's tail drain before releasing reset: the last frames are
        # still moving into SDRAM when the host stops writing, and releasing on
        # the same millisecond truncates the image at the end of the stream.
        time.sleep(0.5)
        send(b"\x06\x00")                       # release reset: the game starts here
        time.sleep(0.1)
        send(b"\x08\x00")                       # overlay off, or the game hides behind the OSD
        print(f"sent {sent} image bytes plus the header in {time.time() - started:.1f}s")
    finally:
        time.sleep(0.2)
        port.close()                            # DTR drop ends fpgapipe
    return 0


if __name__ == "__main__":
    sys.exit(main())
