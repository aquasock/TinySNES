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




def selftest_program() -> bytes:
    """A self-test that computes something the 65C816 is documented to get wrong.

    The instruction is JMP (abs), the indirect jump, in emulation mode.  On the
    6502 -- and on the 65C816 in emulation mode, which reproduces the 6502 --
    the processor fetches the target's low byte from the address given and its
    high byte from the SAME PAGE.  So JMP ($12FF) reads the low byte from $12FF
    and the high byte from $1200, not from $1300.  This is the best documented
    defect in the whole 6502 family: it is in every reference that discusses the
    indirect jump, and the 65C816 was deliberately designed to keep it in
    emulation mode while fixing it in native mode, where the high byte comes from
    the correct address.

    That makes it exactly the test this project needs.  It is not a liveness
    counter that only says "something ticked": the answer distinguishes four
    outcomes, and every one of them is a different fault.

      result $02  the core jumped to $A000, the page-wrapped target.  The CPU is
                  executing and reproduces the documented emulation-mode defect.
      result $01  the core jumped to $9000, the linear target.  The CPU is
                  executing but implements native-mode semantics in emulation
                  mode, which a correct 65C816 does not do.
      no result   the CPU never reached the jump.
      no magic    the CPU never fetched the reset vector.

    The result is written to WRAM $0011 and read off the bus by the hardware
    probe, so nothing here depends on the PPU, the raster, the line buffer or
    the display hardware -- all of which are separately known not to work.

    Layout, all in emulation mode with DBR = $00:

      $8000  SEI / CLD / LDX #$FF / TXS
      $8005  LDA #$A5 / STA $10        magic, written before anything can fail
      $800B  store the pointer:  $12FF = $00, $1300 = $90, $1200 = $A0
      $8018  JMP ($12FF)               the instruction under test
      $9000  LDA #$01 / STA $11 / JMP $8020     reached if the jump was linear
      $A000  LDA #$02 / STA $11 / JMP $8020     reached if it page-wrapped
      $8020  INC $10+2 ... a liveness loop that keeps writing
    """
    rom = bytearray()

    def at(offset: int, *bs: int) -> None:
        """Place bytes at a ROM offset, zero-filling any gap."""
        while len(rom) < offset + len(bs):
            rom.append(0)
        for i, b in enumerate(bs):
            rom[offset + i] = b

    at(0x0000,
       0x78,                    # SEI
       0xD8,                    # CLD
       0xA2, 0xFF,              # LDX #$FF
       0x9A,                    # TXS
       0xA9, 0xA5,              # LDA #$A5
       0x85, 0x10,              # STA $10     magic -> $00:0010 (WRAM)
       0xA9, 0x00,              # LDA #$00
       0x8D, 0xFF, 0x12,        # STA $12FF   pointer low byte
       0xA9, 0x90,              # LDA #$90
       0x8D, 0x00, 0x13,        # STA $1300   high byte, linear target  -> $9000
       0xA9, 0xA0,              # LDA #$A0
       0x8D, 0x00, 0x12,        # STA $1200   high byte, wrapped target -> $A000
       0x6C, 0xFF, 0x12)        # JMP ($12FF) the instruction under test

    # Reached only if the jump took the correct emulation-mode page wrap.
    at(0x2000,
       0xA9, 0x02,              # LDA #$02
       0x85, 0x11,              # STA $11
       0x4C, 0x20, 0x80)        # JMP $8020

    # Reached only if the jump did NOT wrap, i.e. native-mode semantics.
    at(0x1000,
       0xA9, 0x01,              # LDA #$01
       0x85, 0x11,              # STA $11
       0x4C, 0x20, 0x80)        # JMP $8020

    # Liveness loop: $12 counts every pass, $13 every 256th.
    at(0x0020,
       0xE6, 0x12,              # INC $12
       0xD0, 0x03,              # BNE $8027
       0xE6, 0x13,              # INC $13
       0xEA,                    # NOP
       0x4C, 0x20, 0x80)        # JMP $8020

    return bytes(rom)




class Asm:
    """A very small 65C816 assembler: labels, forward references, immediate and
    absolute operands.

    Explicit mnemonics rather than addressing-mode guessing.  `STA $10` is a zero
    page access and `STA $0010` is absolute even though they name the same byte,
    and a tool that picked the mode for you would silently emit a different
    instruction from the one the comment says.  In a test whose entire job is to
    prove a bus works, that is the difference between a measurement and a rumour.
    """

    def __init__(self) -> None:
        self.b = bytearray()
        self.labels: dict[str, int] = {}
        self.fix: list[tuple[int, str, str]] = []

    def label(self, name: str) -> None:
        self.labels[name] = len(self.b)

    def op(self, *bs: int) -> None:
        for x in bs:
            self.b.append(x & 0xFF)

    def abs_op(self, opcode: int, label: str) -> None:
        self.b.append(opcode)
        pos = len(self.b)
        self.b.extend(b"\x00\x00")
        self.fix.append((pos, label, "abs"))

    def rel_op(self, opcode: int, label: str) -> None:
        self.b.append(opcode)
        pos = len(self.b)
        self.b.append(0)
        self.fix.append((pos, label, "rel"))

    def resolve(self, base: int) -> bytes:
        for pos, lab, kind in self.fix:
            if lab not in self.labels:
                raise SystemExit(f"unresolved label: {lab}")
            tgt = base + self.labels[lab]
            if kind == "abs":
                self.b[pos] = tgt & 0xFF
                self.b[pos + 1] = (tgt >> 8) & 0xFF
            else:
                delta = tgt - (base + pos + 1)
                if not -128 <= delta <= 127:
                    raise SystemExit(f"branch to {lab} is out of range: {delta}")
                self.b[pos] = delta & 0xFF
        return bytes(self.b)


def stacktest_program() -> bytes:
    """Exercise the subsystem every real program depends on: the WRAM stack.

    Why the stack, and why now.  The CPU is proven to execute from the cartridge:
    the self-test's page-wrap program ran and reported $11 = $01.  What is not
    proven is the subsystem every subroutine call, every interrupt and every
    PHA/PLA depends on.  Only eight kilobytes of WRAM has ever been touched on
    this board -- the $0000-$1FFF mirror -- and only by single-byte accesses that
    happened to work.  The historical symptom set is stack-shaped: the $1035
    departures, the SP = $01FD landings, and the unmatched RTL that three cycles
    chased are all what a corrupted return address looks like.

    So this program proves two things that the reset-vector and jump tests cannot:

      A. push 256 distinct bytes with PHA, pop them with PLA and compare every
         one.  This exercises WRAM writes on the stack page, WRAM reads on the
         stack page, the eight-bit stack pointer's wrap and every one of the 256
         addresses in $0100-$01FF.
      B. call four subroutines nested four deep, each writing a distinct marker,
         then unwind and check both the markers and that SP came back to $FF.
         This is the return-pairing question, asked directly, with no probe.

    Results go to the same four bytes the hardware probe already watches, so this
    ROM needs no new bitstream: $10 = $52 on entry, $11 = 0 pass / 1 test A fail
    / 2 test B fail, $12 = a heartbeat incremented for ever.  A program that hangs
    stops the heartbeat; a program that runs but fails sets a code and keeps
    beating, which separates "wrong answer" from "no answer".
    """
    a = Asm()
    a.op(0x78)                  # SEI
    a.op(0xD8)                  # CLD
    a.op(0xA2, 0xFF)            # LDX #$FF
    a.op(0x9A)                  # TXS
    a.op(0xA9, 0x52)            # LDA #'R'
    a.op(0x85, 0x10)            # STA $10      magic
    a.op(0xA9, 0x00)
    a.op(0x85, 0x11)            # STA $11      result = 0

    # ---- A: 256 pushes, 256 pops, every byte compared.
    a.op(0xA0, 0x00)            # LDY #$00
    a.label("a_push")
    a.op(0x98)                  # TYA
    a.op(0x48)                  # PHA
    a.op(0xC8)                  # INY
    a.op(0xC0, 0x00)            # CPY #$00     set Z when Y wraps
    a.rel_op(0xD0, "a_push")    # BNE a_push

    a.op(0xA0, 0xFF)            # LDY #$FF
    a.label("a_pop")
    a.op(0x68)                  # PLA
    a.op(0x85, 0x14)            # STA $14      temp
    a.op(0x98)                  # TYA
    a.op(0xC5, 0x14)            # CMP $14
    a.rel_op(0xD0, "a_fail")    # BNE a_fail
    a.op(0x88)                  # DEY
    a.op(0xC0, 0xFF)            # CPY #$FF
    a.rel_op(0xD0, "a_pop")     # BNE a_pop

    a.abs_op(0x4C, "b_start")   # JMP b_start
    a.label("a_fail")
    a.op(0xA9, 0x01)
    a.op(0x85, 0x11)            # STA $11      result = 1
    a.abs_op(0x4C, "done")

    # ---- B: four levels of nested JSR, then unwind and check SP.
    a.label("b_start")
    a.abs_op(0x20, "level1")    # JSR level1
    a.op(0xBA)                  # TSX
    a.op(0xE0, 0xFF)            # CPX #$FF     SP back to its start?
    a.rel_op(0xD0, "b_fail")
    for addr, want in ((0x18, 0xA1), (0x19, 0xA2), (0x1A, 0xA3), (0x1B, 0xA4)):
        a.op(0xA5, addr)        # LDA $nn
        a.op(0xC9, want)        # CMP #nn
        a.rel_op(0xD0, "b_fail")
    a.abs_op(0x4C, "done")
    a.label("b_fail")
    a.op(0xA9, 0x02)
    a.op(0x85, 0x11)            # STA $11      result = 2
    a.abs_op(0x4C, "done")

    for lvl, (addr, mark) in enumerate(
            ((0x18, 0xA1), (0x19, 0xA2), (0x1A, 0xA3), (0x1B, 0xA4)), start=1):
        a.label(f"level{lvl}")
        a.op(0xA9, mark)        # LDA #mark
        a.op(0x85, addr)        # STA $nn
        if lvl < 4:
            a.abs_op(0x20, f"level{lvl + 1}")
        a.op(0x60)              # RTS

    a.label("done")
    a.op(0xE6, 0x12)            # INC $12      heartbeat
    a.abs_op(0x4C, "done")

    return a.resolve(ENTRY)




def hvtest_program() -> bytes:
    """Record the largest H and V counter value the PPU will admit to.

    The raw question this answers: is the PPU's raster counter running, and if it
    is, how far does it get?  $2137 (SLHV) latches the PPU's H and V counters and
    $213C/$213D read them back.

    Why maxima and a swept delay.  The first version of this test sampled in a
    fixed-length loop and came back with OPHCT frozen at 2 while OPVCT moved --
    which is impossible in the RTL, because V_CNT only increments on the H_CNT
    rollover.  A fixed sampling period against a fixed raster period is an
    aliasing trap of exactly the kind this project has fallen into before, so this
    version varies its own delay from pass to pass and keeps the largest value
    seen.  A maximum cannot alias downward: if the counter ever reaches 300, some
    pass will observe a large number, whatever the phase.

      $10  $52 once running
      $11  largest OPHCT low byte seen  (0-255; a real line spans ~340 dots)
      $12  largest OPVCT low byte seen
      $13  number of samples taken, wrapping

    A line is about 340 dots and a frame about 262 lines, so a working PPU should
    push $11 well past $80.  A $11 of 2 means the horizontal counter really is
    not advancing, and that no amount of CPU-side work can fix.
    """
    a = Asm()
    a.op(0x78)                  # SEI
    a.op(0xD8)                  # CLD
    a.op(0xA2, 0xFF)            # LDX #$FF
    a.op(0x9A)                  # TXS
    a.op(0xA9, 0x52)
    a.op(0x85, 0x10)            # STA $10        magic
    a.op(0xA9, 0x00)
    a.op(0x85, 0x11)            # STA $11        max H
    a.op(0x85, 0x12)            # STA $12        max V
    a.op(0x85, 0x13)            # STA $13        samples
    a.op(0x85, 0x17)            # STA $17        phase

    a.label("loop")
    a.op(0xE6, 0x17)            # INC $17        phase varies the delay
    a.op(0xA6, 0x17)            # LDX $17
    a.label("dly")
    a.op(0xCA)                  # DEX
    a.rel_op(0xD0, "dly")       # BNE dly

    a.op(0xAD, 0x37, 0x21)      # LDA $2137      latch
    a.op(0xAD, 0x3C, 0x21)      # LDA $213C      OPHCT
    a.op(0xC5, 0x11)            # CMP $11
    a.rel_op(0x90, "noh")       # BCC noh        smaller, keep the max
    a.op(0x85, 0x11)            # STA $11
    a.label("noh")
    a.op(0xAD, 0x37, 0x21)      # latch
    a.op(0xAD, 0x3D, 0x21)      # OPVCT
    a.op(0xC5, 0x12)            # CMP $12
    a.rel_op(0x90, "nov")       # BCC nov
    a.op(0x85, 0x12)            # STA $12
    a.label("nov")
    a.op(0xE6, 0x13)            # INC $13
    a.abs_op(0x4C, "loop")      # JMP loop

    return a.resolve(ENTRY)


def build(mode: str = "blink") -> bytes:
    rom = bytearray(ROM_SIZE)
    if mode == "selftest":
        body = selftest_program()
        rom[0:len(body)] = body
    elif mode == "stacktest":
        body = stacktest_program()
        rom[0:len(body)] = body
    elif mode == "hvtest":
        body = hvtest_program()
        rom[0:len(body)] = body
    else:
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
    ap.add_argument("--mode", default="blink", choices=("blink", "flash", "selftest", "stacktest", "hvtest"),
                    help="blink: alternate the backdrop colour (tests the whole "
                         "video path).  flash: alternate force-blank (tests only "
                         "whether a PPP write reaches the PPU)")
    ap.add_argument("--disassemble", action="store_true",
                    help="print the program's bytes with their addresses")
    args = ap.parse_args()

    code, marks = (program(args.mode) if args.mode in ("blink", "flash")
                   else (b"", {}))
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
    if args.mode == "hvtest":
        print("  hvtest: read OPHCT/OPVCT through $2137 and count changes")
        print("          $11 changes / $12 samples / $13 last V")
    elif args.mode == "stacktest":
        print("  stacktest: 256 PHA/PLA compares + 4-deep nested JSR")
        print("             $10=$52 magic, $11=0 pass/1 A fail/2 B fail, $12 heartbeat")
    elif args.mode == "selftest":
        print("  selftest: JMP ($12FF) emulation-mode page wrap")
        print("            $11 = $02 wrapped (documented) / $01 linear (not)")
        print("            $10 = $A5 magic, $12 liveness counter")
    elif args.mode == "flash":
        print("  flash: force-blank on/off, ~3.9 s each")
    else:
        print(f"  blink between ${COLOUR_A:04X} and ${COLOUR_B:04X}, ~3.9 s each")
    return 0


if __name__ == "__main__":
    sys.exit(main())
