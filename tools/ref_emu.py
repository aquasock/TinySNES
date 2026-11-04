#!/usr/bin/env python3
"""Headless reference run of a cartridge through a libretro core (snes9x).

Plays a ROM for a fixed number of frames with no window, and writes the frames
and audio a board capture can be compared against:

    tools/ref_emu.py GAME.sfc --out DIR --frames 1800 [--every 120]
                     [--at 300,421] [--press start@1500:10,a@1700]

  --every N      save every Nth frame (frame 0 is the first after power-on)
  --at LIST      also save these frame numbers
  --press LIST   hold BUTTON from frame F for D frames (default 6)
  --core PATH    libretro core (default: Debian/Ubuntu libretro-snes9x)
  --opt K=V      core option, repeatable (snes9x_overclock_superfx=100% is set)
  --dump         with every saved frame also write DIR/rNNNNN.bin (cartridge
                 RAM; the GSU's work RAM on SuperFX titles) and DIR/wNNNNN.bin
                 (128 KByte WRAM), the regions tools/sim/gsu_tb.sv +dump writes

Frames are written as DIR/fNNNNN.png (RGB, the core's native size) and the
audio as DIR/audio.wav (stereo s16, the core's sample rate, 32040 Hz for
snes9x).  NTSC runs at 60.0988 frames per second, so second S is frame
round(S * 60.0988).
"""
import argparse
import ctypes as C
import os
import struct
import sys
import wave

from PIL import Image

DEFAULT_CORE = "/usr/lib/x86_64-linux-gnu/libretro/snes9x_libretro.so"
NTSC_FPS = 60.0988

ENV_GET_CAN_DUPE = 3
ENV_GET_SYSTEM_DIRECTORY = 9
ENV_SET_PIXEL_FORMAT = 10
ENV_GET_VARIABLE = 15
ENV_GET_VARIABLE_UPDATE = 17
ENV_GET_SAVE_DIRECTORY = 31

PIXFMT_0RGB1555, PIXFMT_XRGB8888, PIXFMT_RGB565 = 0, 1, 2

BUTTONS = {"b": 0, "y": 1, "select": 2, "start": 3, "up": 4, "down": 5,
           "left": 6, "right": 7, "a": 8, "x": 9, "l": 10, "r": 11}


DEFAULT_OPTS = {"snes9x_overclock_superfx": "100%"}


class RetroVariable(C.Structure):
    _fields_ = [("key", C.c_char_p), ("value", C.c_char_p)]


class GameInfo(C.Structure):
    _fields_ = [("path", C.c_char_p), ("data", C.c_void_p),
                ("size", C.c_size_t), ("meta", C.c_char_p)]


ENV_CB = C.CFUNCTYPE(C.c_bool, C.c_uint, C.c_void_p)
VIDEO_CB = C.CFUNCTYPE(None, C.c_void_p, C.c_uint, C.c_uint, C.c_size_t)
AUDIO_CB = C.CFUNCTYPE(None, C.c_int16, C.c_int16)
AUDIO_BATCH_CB = C.CFUNCTYPE(C.c_size_t, C.POINTER(C.c_int16), C.c_size_t)
POLL_CB = C.CFUNCTYPE(None)
INPUT_CB = C.CFUNCTYPE(C.c_int16, C.c_uint, C.c_uint, C.c_uint, C.c_uint)


def parse_press(spec):
    events = []
    for item in filter(None, (spec or "").split(",")):
        name, _, when = item.partition("@")
        frame, _, dur = when.partition(":")
        if name.lower() not in BUTTONS:
            sys.exit(f"unknown button {name!r}; one of {', '.join(BUTTONS)}")
        events.append((BUTTONS[name.lower()], int(frame), int(dur or 6)))
    return events


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("rom")
    ap.add_argument("--out", required=True)
    ap.add_argument("--frames", type=int, required=True)
    ap.add_argument("--every", type=int, default=0)
    ap.add_argument("--at", default="")
    ap.add_argument("--press", default="")
    ap.add_argument("--core", default=DEFAULT_CORE)
    ap.add_argument("--opt", action="append", default=[], metavar="KEY=VALUE")
    ap.add_argument("--dump", action="store_true")
    args = ap.parse_args()

    os.makedirs(args.out, exist_ok=True)
    want = {int(x) for x in args.at.split(",") if x}
    presses = parse_press(args.press)
    core = C.CDLL(args.core)

    # The core reads its options through GET_VARIABLE and leaves some unset when
    # the frontend has none; with snes9x_overclock_superfx unset the GSU never
    # runs and SuperFX titles stay black and silent.
    opts = dict(DEFAULT_OPTS)
    for kv in args.opt:
        k, _, v = kv.partition("=")
        opts[k] = v
    opts = {k.encode(): v.encode() for k, v in opts.items()}
    sysdir = C.c_char_p(os.path.abspath(args.out).encode())
    state = {"fmt": PIXFMT_0RGB1555, "frame": 0, "img": None}
    audio = bytearray()

    def env(cmd, data):
        if cmd == ENV_SET_PIXEL_FORMAT:
            state["fmt"] = C.cast(data, C.POINTER(C.c_int)).contents.value
            return True
        if cmd in (ENV_GET_SYSTEM_DIRECTORY, ENV_GET_SAVE_DIRECTORY):
            C.cast(data, C.POINTER(C.c_char_p))[0] = sysdir.value
            return True
        if cmd == ENV_GET_CAN_DUPE:
            C.cast(data, C.POINTER(C.c_bool))[0] = True
            return True
        if cmd == ENV_GET_VARIABLE:
            var = C.cast(data, C.POINTER(RetroVariable)).contents
            val = opts.get(var.key)
            if val is None:
                return False
            var.value = val
            return True
        if cmd == ENV_GET_VARIABLE_UPDATE:
            C.cast(data, C.POINTER(C.c_bool))[0] = False
            return True
        return False

    def video(data, w, h, pitch):
        if not data:
            return
        f = state["frame"]
        if not ((args.every and f % args.every == 0) or f in want):
            return
        raw = C.string_at(data, pitch * h)
        if state["fmt"] == PIXFMT_XRGB8888:
            img = Image.frombuffer("RGBX", (w, h), raw, "raw", "BGRX", pitch, 1)
        elif state["fmt"] == PIXFMT_RGB565:
            img = Image.frombuffer("RGB", (w, h), raw, "raw", "BGR;16", pitch, 1)
        else:
            img = Image.frombuffer("RGB", (w, h), raw, "raw", "BGR;15", pitch, 1)
        img.convert("RGB").save(os.path.join(args.out, f"f{f:05d}.png"))

    def audio1(l, r):
        audio.extend(struct.pack("<hh", l, r))

    def audio_batch(buf, frames):
        audio.extend(C.string_at(buf, frames * 4))
        return frames

    def poll():
        pass

    def input_state(port, device, index, ident):
        if port != 0 or device != 1:
            return 0
        f = state["frame"]
        return int(any(b == ident and s <= f < s + d for b, s, d in presses))

    cbs = (ENV_CB(env), VIDEO_CB(video), AUDIO_CB(audio1),
           AUDIO_BATCH_CB(audio_batch), POLL_CB(poll), INPUT_CB(input_state))
    core.retro_set_environment(cbs[0])
    core.retro_init()
    core.retro_set_video_refresh(cbs[1])
    core.retro_set_audio_sample(cbs[2])
    core.retro_set_audio_sample_batch(cbs[3])
    core.retro_set_input_poll(cbs[4])
    core.retro_set_input_state(cbs[5])

    rom = open(args.rom, "rb").read()
    buf = C.create_string_buffer(rom, len(rom))
    info = GameInfo(os.path.abspath(args.rom).encode(), C.cast(buf, C.c_void_p), len(rom), None)
    core.retro_load_game.restype = C.c_bool
    if not core.retro_load_game(C.byref(info)):
        sys.exit("core refused the ROM")

    core.retro_get_memory_data.restype = C.c_void_p
    core.retro_get_memory_size.restype = C.c_size_t

    def dump(f):
        for kind, tag in ((0, "r"), (2, "w")):   # SAVE_RAM, SYSTEM_RAM
            n = core.retro_get_memory_size(kind)
            ptr = core.retro_get_memory_data(kind)
            if n and ptr:
                with open(os.path.join(args.out, f"{tag}{f:05d}.bin"), "wb") as fh:
                    fh.write(C.string_at(ptr, n))

    for f in range(args.frames):
        state["frame"] = f
        core.retro_run()
        if args.dump and ((args.every and f % args.every == 0) or f in want):
            dump(f)

    with wave.open(os.path.join(args.out, "audio.wav"), "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(32040)
        w.writeframes(bytes(audio))
    core.retro_unload_game()
    core.retro_deinit()
    print(f"{args.frames} frames, {len(audio) // 4} audio samples -> {args.out}")


if __name__ == "__main__":
    main()
