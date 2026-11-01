#!/usr/bin/env python3
"""Build a minimal SNES test cartridge that blinks the screen.

Why this exists.  Every hardware measurement this project has taken has been of
a commercial game's boot -- 1.4 s of opaque state, thirty million master clocks,
and a fault somewhere inside it.  Forty core-log entries later the board still
draws the same grid, and one question has never been answered: does the 65816
execute a program from the cartridge on this board at all?

This ROM answers only that.  It forces blank, disables every layer, points CGRAM
at colour 0, turns the display on, and then blinks between two colours for ever.
There is no APU handshake, no DMA, no interrupt, no tilemap, no sprite, and no
memory access outside the cartridge and the PPU registers.

  * A screen that blinks means the cartridge read path, instruction fetch, PPU
    register writes, CGRAM and the video output all work, and the fault is in
    something a game does.
  * A screen that stays as it is means the fault is inside that short list, and
    the program is ten instructions that can be reasoned about line by line
    instead of probed.

The blink matters.  A static colour could be a stray CGRAM power-up value; a
screen that changes colour every few seconds can only be a CPU running a loop.

    tools/make_test_rom.py -o build/rom/tinysnes_blink.sfc

LoROM, 64 KiB, header at 0x7FC0 with a correct checksum, reset vector $8000, so
tools/load_snes_rom.py finds the header and the core maps it like any LoROM.
"""
from __future__ import annotations

import argparse
import sys

ROM_SIZE = 0x10000          # 64 KiB: enough for the LoROM header at 0x7FC0
HEADER = 0x7FC0
ENTRY = 0x8000

COLOUR_A = 0x7C1F           # BGR555 magenta: red 31, green 0, blue 31
COLOUR_B = 0x03E0           # BGR555 green:   red 0,  green 31, blue 0

# 16-bit X counting down is 65535 * 5 = 327,675 cycles; a 16-bit Y of $0100 over
# that is 83.9M cycles, which at 21.48 MHz is 3.9 s per colour.
DELAY_OUTER = 0x0100


def program(mode: str = "blink") -> tuple[bytes, dict[str, int]]:
    """The cartridge's code, hand-assembled.

    Native mode with 16-bit index registers and an 8-bit accumulator: A stays
    eight bits so the immediate operands to $2100-$2122 are single bytes, while
    X and Y get wide enough to make a delay that lasts seconds instead of
    milliseconds.  DBR resets to $00 and is never changed, so absolute addresses
    such as $2100 still land in bank $00 where the PPU registers are.
    """
    code = bytearray()
    fixups: list[tuple[int, str]] = []      # (offset of the 16-bit operand, label)
    marks: dict[str, int] = {}

    def emit(*bs: int) -> None:
        code.extend(bs)

    def label(name: str) -> None:
        marks[name] = len(code)

    emit(0x78)                      # SEI
    emit(0x18)                      # CLC
    emit(0xFB)                      # XCE        native mode
    emit(0xC2, 0x10)                # REP #$10   16-bit X and Y, A stays 8-bit

    # Display off, no layers: the backdrop is all that will show.
    emit(0xA9, 0x8F)                # LDA #$8F   force blank, brightness 15
    emit(0x8D, 0x00, 0x21)          # STA $2100
    emit(0xA9, 0x00)                # LDA #$00
    emit(0x8D, 0x2C, 0x21)          # STA $212C  main screen: no layers
    emit(0x8D, 0x2D, 0x21)          # STA $212D  sub screen: no layers

    label("loop")
    if mode == "flash":
        # Force blank on and off.  This asks the smallest question there is --
        # does a PPP write from cartridge code reach the PPU -- and it asks it
        # in a way that cannot be confused with a static power-up value,
        # because the screen has to change.
        emit(0xA9, 0x8F)            # LDA #$8F   force blank
        emit(0x8D, 0x00, 0x21)      # STA $2100
        emit(0x20)                  # JSR delay
        fixups.append((len(code), "delay"))
        emit(0x00, 0x00)
        emit(0xA9, 0x0F)            # LDA #$0F   display on
        emit(0x8D, 0x00, 0x21)      # STA $2100
        emit(0x20)                  # JSR delay
        fixups.append((len(code), "delay"))
        emit(0x00, 0x00)
    else:
        _colour(emit, COLOUR_A)
        emit(0xA9, 0x0F)            # LDA #$0F   display on, brightness 15
        emit(0x8D, 0x00, 0x21)      # STA $2100
        emit(0x20)                  # JSR delay
        fixups.append((len(code), "delay"))
        emit(0x00, 0x00)

        _colour(emit, COLOUR_B)
        emit(0x20)                  # JSR delay
        fixups.append((len(code), "delay"))
        emit(0x00, 0x00)

    emit(0x4C)                      # JMP loop
    fixups.append((len(code), "loop"))
    emit(0x00, 0x00)

    label("delay")
    emit(0xA0, DELAY_OUTER & 0xFF, DELAY_OUTER >> 8)   # LDY #$0100
    label("dout")
    emit(0xA2, 0xFF, 0xFF)          # LDX #$FFFF
    label("din")
    emit(0xCA)                      # DEX
    emit(0xD0, 0xFD)                # BNE din   (-3)
    emit(0x88)                      # DEY
    emit(0xD0, 0xF7)                # BNE dout  (-9)
    emit(0x60)                      # RTS

    for off, name in fixups:
        target = ENTRY + marks[name]
        code[off] = target & 0xFF
        code[off + 1] = target >> 8

    # JSR is three bytes; the placeholder pair follows the opcode, so the fixup
    # offsets above point at the operand.  JMP's operand pair is patched the
    # same way.
    return bytes(code), marks


def _colour(emit, colour: int) -> None:
    emit(0xA9, 0x00)                # LDA #$00
    emit(0x8D, 0x21, 0x21)          # STA $2121   CGRAM address 0
    emit(0xA9, colour & 0xFF)       # LDA #low
    emit(0x8D, 0x22, 0x21)          # STA $2122
    emit(0xA9, colour >> 8)         # LDA #high
    emit(0x8D, 0x22, 0x21)          # STA $2122


def build(mode: str = "blink") -> bytes:
    rom = bytearray(ROM_SIZE)
    code, _ = program(mode)
    rom[0:len(code)] = code

    # LoROM, slowrom, ROM only, 64 KiB, 8 KiB WRAM, USA.
    title = b"TINYSNES " + mode.upper().encode() + b" TEST"
    rom[HEADER:HEADER + 21] = title[:21].ljust(21, b" ")
    rom[0x7FD5] = 0x20              # map mode: LoROM, slowrom
    rom[0x7FD6] = 0x00              # ROM only
    rom[0x7FD7] = 0x06              # 64 KiB (log2 64 = 6)
    rom[0x7FD8] = 0x03              # 8 KiB WRAM (log2 8 = 3)
    rom[0x7FD9] = 0x01              # USA
    rom[0x7FDA] = 0x00
    rom[0x7FDB] = 0x00

    # Every vector points at the program, so a stray interrupt lands in the loop
    # instead of at $0000.
    vec = ENTRY.to_bytes(2, "little")
    for off in (0x7FE4, 0x7FE6, 0x7FE8, 0x7FEA, 0x7FEC, 0x7FEE,
                0x7FF4, 0x7FF6, 0x7FFE):
        rom[off:off + 2] = vec
    rom[0x7FFC:0x7FFE] = vec        # RESET

    # Checksum: the two fields must complement to $FFFF and be non-zero, which is
    # what tools/load_snes_rom.py's header scoring tests.  Computed the standard
    # way -- the four checksum bytes read as $FF/$00 during the sum -- so the
    # image is a legal cartridge rather than merely one the loader accepts.
    rom[0x7FDC:0x7FE0] = b"\xFF\xFF\x00\x00"
    checksum = sum(rom) & 0xFFFF
    if checksum == 0:
        checksum = 0x0001
    complement = checksum ^ 0xFFFF
    rom[0x7FDC] = complement & 0xFF
    rom[0x7FDD] = complement >> 8
    rom[0x7FDE] = checksum & 0xFF
    rom[0x7FDF] = checksum >> 8
    return bytes(rom)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("-o", "--out", default="build/rom/tinysnes_blink.sfc")
    ap.add_argument("--mode", default="blink", choices=("blink", "flash"),
                    help="blink: alternate the backdrop colour (tests the whole "
                         "video path).  flash: alternate force-blank (tests only "
                         "whether a PPP write reaches the PPU)")
    ap.add_argument("--disassemble", action="store_true",
                    help="print the program's bytes with their addresses")
    args = ap.parse_args()

    code, marks = program(args.mode)
    if args.disassemble:
        print(f"code: {len(code)} bytes at ${ENTRY:04X}-${ENTRY + len(code) - 1:04X}")
        for i in range(0, len(code), 8):
            row = code[i:i + 8]
            print(f"  ${ENTRY + i:04X}: " + " ".join(f"{b:02X}" for b in row))
        for name, off in marks.items():
            print(f"  {name:6s} -> ${ENTRY + off:04X}")

    rom = build(args.mode)
    with open(args.out, "wb") as f:
        f.write(rom)
    checksum = rom[0x7FDE] | (rom[0x7FDF] << 8)
    complement = rom[0x7FDC] | (rom[0x7FDD] << 8)
    print(f"{args.out}: {len(rom)} bytes, LoROM, header at 0x7FC0")
    print(f"  reset vector ${rom[0x7FFC] | (rom[0x7FFD] << 8):04X}")
    print(f"  checksum ${checksum:04X} ^ complement ${complement:04X} = "
          f"${checksum ^ complement:04X}")
    if args.mode == "flash":
        print("  flash: force-blank on/off, ~3.9 s each")
    else:
        print(f"  blink between ${COLOUR_A:04X} and ${COLOUR_B:04X}, ~3.9 s each")
    return 0


if __name__ == "__main__":
    sys.exit(main())
