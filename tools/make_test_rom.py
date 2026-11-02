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


def bgdraw_program() -> bytes:
    """Draw a solid background field, without ever waiting on an interrupt.

    Why this exists.  With the region bit driven, the blink cartridge reaches the
    screen -- magenta in all 686,880 pixels of the active area -- while
    tinysnes_selftest, F-Zero and ActRaiser all leave the active area black with
    the pillarbox bars intact.  Both readings are consistent with two very
    different faults, and the screen cannot tell them apart:

      * the game never clears force blank, because its init loop waits for an
        NMI or IRQ that never arrives, so the PPU faithfully draws nothing; or
      * the game does clear it, and drawing into VRAM and CGRAM does not come
        back out.

    This cartridge separates them by drawing with no interrupt at all: no NMI
    enable, no vector, no wait.  It fills one 2bpp tile with colour 3, points
    every entry of a 32x32 tilemap at it, sets BG mode 0, enables BG1 on the
    main screen and turns the display on.  The active area should become solid
    blue, `$7C00` in BGR555.

      solid blue   drawing works end to end, so a black retail screen means the
                   machine is stuck before it clears force blank -- an interrupt
                   or handshake, not the raster.
      still black  the PPU is being programmed and the result is not reaching the
                   screen, so the fault is in VRAM, CGRAM or how the PPU reads
                   them, and no amount of CPU-side work would have shown it.

    A marker byte is left in WRAM at $10 so a bus probe can tell "ran to the
    end" from "drew a colour that happens to be blue".
    """
    code = bytearray()
    marks: dict[str, int] = {}
    abs16: list[tuple[int, str]] = []          # (operand offset, label)
    rel8: list[tuple[int, int, str]] = []      # (operand offset, opcode offset, label)

    def emit(*bs: int) -> None:
        code.extend(bs)

    def label(name: str) -> None:
        marks[name] = len(code)

    def lda(value: int) -> None:
        emit(0xA9, value & 0xFF)               # LDA #byte

    def sta(addr: int) -> None:
        emit(0x8D, addr & 0xFF, addr >> 8)     # STA abs, DBR = $00

    def branch(opcode: int, name: str) -> None:
        op_at = len(code)
        emit(opcode, 0x00)
        rel8.append((len(code) - 1, op_at, name))

    emit(0x78, 0x18, 0xFB)          # SEI; CLC; XCE        native mode
    emit(0xC2, 0x10)                # REP #$10             16-bit X and Y

    lda(0x8F)
    sta(0x2100)                     # force blank while the memories are set up

    lda(0x00)
    sta(0x2121)                     # CGRAM word address 0; writes auto-increment
    for colour in (0x0000, 0x001F, 0x03E0, 0x7C00):
        lda(colour & 0xFF)
        sta(0x2122)
        lda(colour >> 8)
        sta(0x2122)                 # 0 black, 1 red, 2 green, 3 blue

    lda(0x00)
    sta(0x2116)                     # VMADD = $0000, tile data at word 0
    lda(0x00)
    sta(0x2117)
    emit(0xA2, 0x08, 0x00)          # LDX #$0008            8 words = one 2bpp tile
    label("tile")
    lda(0xFF)
    sta(0x2118)
    sta(0x2119)                     # every pixel of tile 0 is colour 3
    emit(0xCA)                      # DEX
    branch(0xD0, "tile")            # BNE tile

    lda(0x00)
    sta(0x2116)                     # VMADD = $0400, tilemap words
    lda(0x04)
    sta(0x2117)
    emit(0xA2, 0x00, 0x04)          # LDX #$0400            1024 entries: 32x32
    label("map")
    lda(0x00)
    sta(0x2118)
    sta(0x2119)                     # entry $0000: tile 0, palette 0, no flip
    emit(0xCA)                      # DEX
    branch(0xD0, "map")             # BNE map

    lda(0x00)
    sta(0x2105)                     # BG mode 0
    lda(0x04)
    sta(0x2107)                     # BG1SC: base word address $0400, 32x32
    lda(0x00)
    sta(0x210B)                     # BG12NBA: BG1 tile data at word 0
    lda(0x01)
    sta(0x212C)                     # main screen: BG1 only

    lda(0xB6)
    sta(0x0010)                     # WRAM marker: the program reached the end
    lda(0x0F)
    sta(0x2100)                     # display on, brightness 15

    label("spin")
    emit(0x4C)                      # JMP spin
    abs16.append((len(code), "spin"))
    emit(0x00, 0x00)

    for off, name in abs16:
        target = ENTRY + marks[name]
        code[off] = target & 0xFF
        code[off + 1] = target >> 8
    for off, op_at, name in rel8:
        code[off] = (marks[name] - (op_at + 2)) & 0xFF

    return bytes(code)


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


def nmitest_program() -> tuple[bytes, dict[int, int]]:
    """Does the PPU's vertical-blank NMI reach the CPU?

    Why this exists.  `bgdraw` shows that a cartridge can program the PPU and put
    a picture on the screen without any interrupt at all, and every retail
    cartridge tried so far -- F-Zero and ActRaiser -- leaves the active area
    black.  The difference between those two situations is not drawing: it is
    that a game's init waits for an NMI before it clears force blank.  A core
    whose NMI never fires therefore looks exactly like a core whose raster is
    dead, and the screen cannot tell them apart.

    This cartridge asks only that question.  It sets the backdrop to red, enables
    NMI in `$4200`, turns the display on, and then spins.  The handler increments
    a counter in WRAM `$12` and writes it to CGRAM entry 0, so every NMI repaints
    the backdrop with the next value.

      backdrop changing   NMI is delivered, so a black retail screen is a
                          different fault and the raster is not the blocker.
      backdrop stuck red  NMI is not delivered.  That is the whole retail
                          failure for any game that waits on it.

    The native NMI vector at `$7FEA` is pointed at the handler rather than at the
    entry point, which `build()` now allows per mode.
    """
    code = bytearray()
    marks: dict[str, int] = {}
    abs16: list[tuple[int, str]] = []

    def emit(*bs: int) -> None:
        code.extend(bs)

    def label(name: str) -> None:
        marks[name] = len(code)

    def lda(value: int) -> None:
        emit(0xA9, value & 0xFF)

    def sta(addr: int) -> None:
        emit(0x8D, addr & 0xFF, addr >> 8)

    emit(0x78, 0x18, 0xFB)          # SEI; CLC; XCE        native mode
    emit(0xC2, 0x10)                # REP #$10

    lda(0x00)
    sta(0x0012)                     # WRAM counter starts at zero
    lda(0x8F)
    sta(0x2100)                     # force blank while setting up
    lda(0x00)
    sta(0x212C)                     # no layers: the backdrop is the picture
    lda(0x00)
    sta(0x2121)                     # CGRAM entry 0
    lda(0x1F)
    sta(0x2122)                     # red
    lda(0x00)
    sta(0x2122)
    lda(0x80)
    sta(0x4200)                     # NMI on
    lda(0x0F)
    sta(0x2100)                     # display on, brightness 15

    label("spin")
    emit(0x4C)                      # JMP spin
    abs16.append((len(code), "spin"))
    emit(0x00, 0x00)

    label("nmi")
    emit(0x48)                      # PHA
    lda(0x00)
    sta(0x2121)                     # CGRAM entry 0
    emit(0xAD, 0x12, 0x00)          # LDA $0012
    emit(0xEE, 0x12, 0x00)          # INC $0012
    sta(0x2122)                     # low byte = the counter
    lda(0x00)
    sta(0x2122)                     # high byte
    emit(0x68)                      # PLA
    emit(0x40)                      # RTI

    for off, name in abs16:
        target = ENTRY + marks[name]
        code[off] = target & 0xFF
        code[off + 1] = target >> 8

    return bytes(code), {0x7FEA: ENTRY + marks["nmi"]}


DMA_TILE_OFF = 0x1000          # ROM offset of the tile table, reached at $80:9000
DMA_MAP_OFF = 0x1100           # ROM offset of the tilemap, reached at $80:9100


def dmatest_program() -> bytes:
    """Draw the same field as `bgdraw`, but upload it with DMA.

    Why this exists.  `bgdraw` proves a cartridge can program the PPU and put a
    picture on the screen when it writes VRAM through `$2118`/`$2119` one word at
    a time, and `nmitest` proves the vertical-blank NMI is delivered.  Every
    retail cartridge tried -- F-Zero, Mega Man X, ActRaiser, the RetroRegen diag
    -- still leaves the active area black.  What retail does that no test
    cartridge here has done is upload tiles and tilemaps with a DMA channel
    rather than by poking the data port, so a broken DMA engine would leave every
    game black while every hand-written cartridge drew perfectly.

    This cartridge is `bgdraw` with the two upload loops replaced by two channel-0
    transfers, so it differs from a known-good picture in exactly one mechanism.

      solid blue   DMA works, and the retail fault is somewhere else.
      still black  DMA is the fault, and it is the only mechanism in this project
                   that every failing cartridge depends on and no working one
                   has used.

    The tables live in the cartridge, not in WRAM, which also exercises a DMA
    source in a ROM bank other than the code's.
    """
    code = bytearray()
    marks: dict[str, int] = {}
    abs16: list[tuple[int, str]] = []

    def emit(*bs: int) -> None:
        code.extend(bs)

    def label(name: str) -> None:
        marks[name] = len(code)

    def lda(value: int) -> None:
        emit(0xA9, value & 0xFF)

    def sta(addr: int) -> None:
        emit(0x8D, addr & 0xFF, addr >> 8)

    def sta_long(addr: int, bank: int) -> None:
        emit(0x8F, addr & 0xFF, addr >> 8, bank & 0xFF)   # STA long

    def dma_setup(bus: int, src: int, bank: int, nbytes: int) -> None:
        lda(0x01)
        sta(0x4300)                 # A->B, increment A, mode 1: 2 bytes per unit
        lda(bus)
        sta(0x4301)                 # B-bus destination
        lda(src & 0xFF)
        sta(0x4302)
        lda(src >> 8)
        sta(0x4303)                 # A-bus address
        lda(bank)
        sta(0x4304)                 # A-bus bank
        # $4305/$4306 is a byte counter, not a unit counter: in mode 1 the
        # engine moves two bytes per unit and decrements this by two, so the
        # value written here is the transfer's length in bytes.
        lda(nbytes & 0xFF)
        sta(0x4305)
        lda(nbytes >> 8)
        sta(0x4306)                 # transfer size in bytes
        lda(0x01)
        sta(0x420B)                 # start channel 0

    emit(0x78, 0x18, 0xFB)          # SEI; CLC; XCE        native mode
    emit(0xC2, 0x10)                # REP #$10

    lda(0x8F)
    sta(0x2100)                     # force blank while the memories are set up

    lda(0x00)
    sta(0x2121)                     # CGRAM entry 0
    for colour in (0x0000, 0x001F, 0x03E0, 0x7C00):
        lda(colour & 0xFF)
        sta(0x2122)
        lda(colour >> 8)
        sta(0x2122)                 # 0 black, 1 red, 2 green, 3 blue

    lda(0x00)
    sta(0x2116)                     # VMADD = $0000, tile data at word 0
    lda(0x00)
    sta(0x2117)
    dma_setup(0x18, 0x9000, 0x80, 16)         # 8 words = 16 bytes, one 2bpp tile

    lda(0x00)
    sta(0x2116)                     # VMADD = $0400, tilemap words
    lda(0x04)
    sta(0x2117)
    dma_setup(0x18, 0x9100, 0x80, 2048)       # 1024 entries = 2048 bytes

    lda(0x00)
    sta(0x2105)                     # BG mode 0
    lda(0x04)
    sta(0x2107)                     # BG1SC: base word address $0400, 32x32
    lda(0x00)
    sta(0x210B)                     # BG12NBA: BG1 tile data at word 0
    lda(0x01)
    sta(0x212C)                     # main screen: BG1 only

    lda(0xB7)
    sta(0x0010)                     # WRAM marker: reached the end
    lda(0x0F)
    sta(0x2100)                     # display on, brightness 15

    label("spin")
    emit(0x4C)                      # JMP spin
    abs16.append((len(code), "spin"))
    emit(0x00, 0x00)

    for off, name in abs16:
        target = ENTRY + marks[name]
        code[off] = target & 0xFF
        code[off + 1] = target >> 8

    return bytes(code)


def dmaflag_program(src_bank: int = 0x00, src_addr: int = 0x0100,
                    marker: int = 0xE0, marker_hi: int = 0x03) -> bytes:
    """Does a DMA channel execute at all?  Read the answer off the backdrop.

    `bgdraw` draws a blue field by poking VRAM and `dmatest` draws the same field
    with channel-0 transfers, and only the second is black.  That is consistent
    with a broken DMA engine, with a broken A-bus read from the cartridge, and
    with this project's own bug in the transfer setup, and one screenshot cannot
    tell those apart.

    So this cartridge makes DMA report itself.  It paints the backdrop blue
    through CGRAM with plain CPU writes, turns the display on, and only then
    starts a two-byte DMA of green into CGRAM entry 0.  The source is in WRAM,
    which the CPU has just written and which involves no cartridge read, no ROM
    mapper and no SDRAM -- so the only thing under test is the engine itself.

      backdrop turns green   the engine runs, and `dmatest`'s black screen is
                             the A-bus read from the cartridge instead.
      backdrop stays blue    the engine does not run at all.

    Blue is `$7C00` and green is `$03E0`, so the two outcomes cannot be confused
    with each other or with the blank starting state.
    """
    code = bytearray()
    marks: dict[str, int] = {}
    abs16: list[tuple[int, str]] = []

    def emit(*bs: int) -> None:
        code.extend(bs)

    def label(name: str) -> None:
        marks[name] = len(code)

    def lda(value: int) -> None:
        emit(0xA9, value & 0xFF)

    def sta(addr: int) -> None:
        emit(0x8D, addr & 0xFF, addr >> 8)

    emit(0x78, 0x18, 0xFB)          # SEI; CLC; XCE        native mode
    emit(0xC2, 0x10)                # REP #$10

    lda(0x8F)
    sta(0x2100)                     # force blank
    lda(0x00)
    sta(0x212C)                     # no layers, so the backdrop is the picture
    sta(0x2121)                     # CGRAM entry 0
    sta(0x2122)
    lda(0x7C)
    sta(0x2122)                     # entry 0 = blue ($7C00)

    lda(marker)
    sta(0x0100)                     # WRAM: green $03E0, not the DMA's source here
    lda(marker_hi)
    sta(0x0101)                     # little endian, low byte first

    lda(0x0F)
    sta(0x2100)                     # display on, brightness 15 -> BLUE

    lda(0x00)
    sta(0x2121)                     # point CGRAM back at entry 0
    lda(0x01)
    sta(0x4300)                     # A->B, increment, mode 1: two bytes per unit
    lda(0x22)
    sta(0x4301)                     # B-bus: $2122, CGRAM data
    lda(src_addr & 0xFF)
    sta(0x4302)
    lda(src_addr >> 8)
    sta(0x4303)                     # A-bus address
    lda(src_bank)
    sta(0x4304)                     # A-bus bank
    lda(0x02)
    sta(0x4305)
    lda(0x00)
    sta(0x4306)                     # two bytes
    lda(0x01)
    sta(0x420B)                     # start channel 0 -> GREEN if the engine runs

    label("spin")
    emit(0x4C)
    abs16.append((len(code), "spin"))
    emit(0x00, 0x00)

    for off, name in abs16:
        target = ENTRY + marks[name]
        code[off] = target & 0xFF
        code[off + 1] = target >> 8

    return bytes(code)


HIGHBANK_OFF = 0x8000          # bank $01 address $8000 in a LoROM image


def highbank_program(bank: int = 0x01, marker: tuple[int, int] = (0x00, 0x7C)) -> bytes:
    """Can the CPU read a ROM byte outside its own 32 KiB bank?

    `bgdraw` draws a blue field and `bgdraw` padded to 512 KiB still draws it, so
    cartridge size is not what separates the working test cartridges from the
    retail cartridges that all come up black.  What does separate them is reach:
    every cartridge in this project so far is 64 KiB or less of code and data and
    runs entirely inside bank $00, addresses $8000-$FFFF, which is the first
    32 KiB of the image.  A retail cartridge jumps and reads all over its address
    space, and Speedy Gonzales aside, no retail title here runs from a single
    bank.

    So this cartridge asks for one byte from the next bank and paints it.  The
    code itself still lives at $00:8000, so instruction fetch is unchanged and
    proven; only the data read is new.  The byte pair at bank $01 address $8000 is
    `$00,$7C`, which is blue `$7C00`.

      backdrop blue    the CPU can read past bank $00, and the retail fault is
                       somewhere else again.
      backdrop black   every read outside bank $00 returns zero or garbage, which
                       would make every retail cartridge fail exactly as seen
                       while leaving these test cartridges working.

    The read is a long `LDA $01:8000`, and both bytes are copied through WRAM so
    the two halves of the colour are written to `$2122` explicitly rather than
    relying on what a 16-bit store does to an 8-bit port.
    """
    code = bytearray()
    marks: dict[str, int] = {}
    abs16: list[tuple[int, str]] = []

    def emit(*bs: int) -> None:
        code.extend(bs)

    def label(name: str) -> None:
        marks[name] = len(code)

    def lda(value: int) -> None:
        emit(0xA9, value & 0xFF)

    def sta(addr: int) -> None:
        emit(0x8D, addr & 0xFF, addr >> 8)

    emit(0x78, 0x18, 0xFB)          # SEI; CLC; XCE        native mode
    emit(0xC2, 0x30)                # REP #$30             16-bit A, X and Y

    lda(0x8F)
    sta(0x2100)                     # force blank (16-bit store, low byte used)
    emit(0xE2, 0x20)                # SEP #$20             back to 8-bit A
    lda(0x00)
    sta(0x212C)                     # no layers: the backdrop is the picture
    sta(0x2121)                     # CGRAM entry 0

    emit(0xC2, 0x20)                # REP #$20             16-bit A for the read
    emit(0xAF, 0x00, 0x80, bank)    # LDA long bank:$8000  the read under test
    sta(0x0000)                     # park both halves in WRAM
    emit(0xE2, 0x20)                # SEP #$20

    emit(0xAD, 0x00, 0x00)          # LDA $0000            low byte
    sta(0x2122)
    emit(0xAD, 0x01, 0x00)          # LDA $0001            high byte
    sta(0x2122)                     # -> BLUE if the read worked

    lda(0x0F)
    sta(0x2100)                     # display on, brightness 15

    label("spin")
    emit(0x4C)
    abs16.append((len(code), "spin"))
    emit(0x00, 0x00)

    for off, name in abs16:
        target = ENTRY + marks[name]
        code[off] = target & 0xFF
        code[off + 1] = target >> 8

    return bytes(code)


def aputest_program() -> bytes:
    """Does the APU handshake that every retail cartridge blocks on complete?

    Everything above this test says the picture path works: `bgdraw` draws a blue
    field, a 512 KiB-padded copy of it still draws, and a cartridge that reads a
    byte from the top bank of a 512 KiB image -- `$0F:8000`, the furthest address
    the image can hold -- paints that byte's colour on screen too.  So neither
    ROM size nor ROM reach separates the cartridges that work from the retail ones
    that all come up black.

    What separates them is the first thing retail boot code does and no test
    cartridge here has ever done: talk to the APU.  The standard sequence is

        LDA #$AA        ; ask the sound module whether it is alive
        STA $2140
      wait:
        CMP $2140       ; the IPL ROM echoes $AA back when it is
        BNE wait

    and a machine whose SPC700 never runs -- never leaves its IPL ROM, or has no
    IPL ROM to leave -- hangs in that loop forever with the display still in
    force blank.  That is indistinguishable from a dead raster on screen, and it
    would look exactly like what has been observed: every retail title black,
    every hand-written cartridge fine.

    The answer is painted as a backdrop colour, and the failure state is painted
    before the handshake is attempted, so a timeout cannot be mistaken for a
    machine that never started.

      backdrop red      the handshake timed out.  The CPU reached this code and
                        the picture path works, and the APU never answered.
      backdrop green    the APU answered, and the retail fault is further on.
      black, no bars    the machine never got here at all.

    The wait is bounded by a 16-bit index, about 650,000 iterations, which at
    three master clocks per iteration is around a quarter of a second -- far
    longer than the IPL ROM needs to reach its echo.
    """
    code = bytearray()
    marks: dict[str, int] = {}
    abs16: list[tuple[int, str]] = []
    rel8: list[tuple[int, int, str]] = []

    def emit(*bs: int) -> None:
        code.extend(bs)

    def label(name: str) -> None:
        marks[name] = len(code)

    def lda(value: int) -> None:
        emit(0xA9, value & 0xFF)

    def sta(addr: int) -> None:
        emit(0x8D, addr & 0xFF, addr >> 8)

    def branch(opcode: int, name: str) -> None:
        op_at = len(code)
        emit(opcode, 0x00)
        rel8.append((len(code) - 1, op_at, name))

    emit(0x78, 0x18, 0xFB)          # SEI; CLC; XCE        native mode
    emit(0xC2, 0x10)                # REP #$10             16-bit X and Y

    lda(0x8F)
    sta(0x2100)                     # force blank
    lda(0x00)
    sta(0x212C)                     # no layers: the backdrop is the picture
    sta(0x2121)                     # CGRAM entry 0
    lda(0x1F)
    sta(0x2122)
    lda(0x00)
    sta(0x2122)                     # entry 0 = red $001F -- the failure colour
    lda(0x0F)
    sta(0x2100)                     # display on, so RED means "timed out"

    lda(0xAA)
    sta(0x2140)                     # ask the APU whether it is alive

    emit(0xA2, 0x00, 0x00)          # LDX #$0000
    label("wait")
    emit(0xAD, 0x40, 0x21)          # LDA $2140    the IPL's echo lands here
    emit(0xC9, 0xAA)                # CMP #$AA
    branch(0xF0, "ok")              # BEQ ok
    emit(0xCA)                      # DEX
    branch(0xD0, "wait")            # BNE wait
    label("stuck")
    emit(0x4C)                      # JMP stuck    leave the screen red
    abs16.append((len(code), "stuck"))
    emit(0x00, 0x00)

    label("ok")
    lda(0x00)
    sta(0x2121)                     # CGRAM entry 0
    lda(0xE0)
    sta(0x2122)
    lda(0x03)
    sta(0x2122)                     # green $03E0 -- the APU answered
    label("spin")
    emit(0x4C)
    abs16.append((len(code), "spin"))
    emit(0x00, 0x00)

    for off, name in abs16:
        target = ENTRY + marks[name]
        code[off] = target & 0xFF
        code[off + 1] = target >> 8
    for off, op_at, name in rel8:
        code[off] = (marks[name] - (op_at + 2)) & 0xFF

    return bytes(code)


def wramexec_program(use_long: bool = False) -> bytes:
    """Can the CPU execute code it has copied into WRAM?

    The list of things this project has now cleared on hardware is getting long:
    a cartridge draws, a 512 KiB image draws, a byte read from bank $01 and from
    the top bank $0F of a 512 KiB image paints correctly, the mirror bank $8F
    reads the same byte, the vertical-blank NMI is delivered every frame, and the
    APU handshake `LDA #$AA / STA $2140 / CMP $2140` completes.  Every retail
    cartridge here is still black.

    What none of those tests has done is what a great many retail boot sequences
    do within their first few hundred instructions: copy a routine into WRAM and
    jump to it, because the routine patches itself or because it has to run with
    RAM timing.  A core that can read and write WRAM but cannot fetch from it
    would boot every hand-written cartridge in this project and no retail one.

    The answer is painted before and after.  The backdrop is set red and the
    display turned on; then sixteen bytes are stored into $7E:0200 one at a time
    and the CPU does a long jump to them.  Those bytes set CGRAM entry 0 to
    green and then spin.

      backdrop green   the CPU executed from WRAM.
      backdrop red     the CPU never executed from WRAM -- the long jump went
                       somewhere else, or the fetch came back wrong.
      black, no bars   the machine never got as far as the red backdrop.

    The routine is unrolled as sixteen `LDA #imm / STA long` pairs rather than
    copied with a loop, so a fault in the copy cannot be mistaken for a fault in
    the jump.
    """
    if use_long:
        # Absolute-long stores, so the hardware registers are named by their
        # full bank and DBR plays no part.
        ROUTINE = bytes([
            0xA9, 0x00, 0x8F, 0x21, 0x21, 0x00,   # LDA #$00 / STA long $00:2121
            0xA9, 0xE0, 0x8F, 0x22, 0x21, 0x00,   # LDA #$E0 / STA long $00:2122
            0xA9, 0x03, 0x8F, 0x22, 0x21, 0x00,   # LDA #$03 / STA long $00:2122
            0x80, 0xFE,                            # BRA -2
        ])
    else:
        ROUTINE = bytes([
            0xA9, 0x00, 0x8D, 0x21, 0x21,      # LDA #$00 / STA $2121   CGRAM entry 0
            0xA9, 0xE0, 0x8D, 0x22, 0x21,      # LDA #$E0 / STA $2122   green low
            0xA9, 0x03, 0x8D, 0x22, 0x21,      # LDA #$03 / STA $2122   green high
            0x80, 0xFE,                        # BRA -2                 spin here
        ])

    code = bytearray()
    marks: dict[str, int] = {}
    abs16: list[tuple[int, str]] = []

    def emit(*bs: int) -> None:
        code.extend(bs)

    def label(name: str) -> None:
        marks[name] = len(code)

    def lda(value: int) -> None:
        emit(0xA9, value & 0xFF)

    def sta(addr: int) -> None:
        emit(0x8D, addr & 0xFF, addr >> 8)

    emit(0x78, 0x18, 0xFB)          # SEI; CLC; XCE        native mode

    lda(0x8F)
    sta(0x2100)                     # force blank
    lda(0x00)
    sta(0x212C)                     # no layers: the backdrop is the picture
    sta(0x2121)                     # CGRAM entry 0
    lda(0x1F)
    sta(0x2122)
    lda(0x00)
    sta(0x2122)                     # entry 0 = red, the failure colour
    lda(0x0F)
    sta(0x2100)                     # display on: RED from here until the jump

    for i, byte in enumerate(ROUTINE):
        lda(byte)
        emit(0x8F, (0x0200 + i) & 0xFF, (0x0200 + i) >> 8, 0x7E)  # STA long $7E:02xx

    emit(0x5C, 0x00, 0x02, 0x7E)    # JML $7E:0200 -- the instruction under test

    label("spin")
    emit(0x4C)
    abs16.append((len(code), "spin"))
    emit(0x00, 0x00)

    for off, name in abs16:
        target = ENTRY + marks[name]
        code[off] = target & 0xFF
        code[off + 1] = target >> 8

    return bytes(code)


def wramrw_program() -> bytes:
    """Can the CPU write a byte to WRAM and read it back?

    This is the control for `wramexec`, which came back red: the CPU did not
    execute the sixteen bytes it stored at $7E:0200.  Two different faults produce
    that, and they have different consequences:

      the store never landed   WRAM is not writable at that address, so the CPU
                               jumped into stale bytes and the fault is the
                               write.
      the store landed and the read that follows it here works, but the fetch at
                               $7E:0200 does not   the fault is instruction fetch
                               from WRAM specifically, which is a much narrower
                               and much more interesting thing.

    So this cartridge writes `$E0,$03` to `$7E:0200` with `STA long`, reads it
    back with `LDA long`, and paints the result.

      backdrop green   WRAM stores and loads correctly, so `wramexec`'s red is a
                       fetch fault.
      backdrop red     the byte did not survive the round trip, and the write is
                       the fault.
    """
    code = bytearray()
    marks: dict[str, int] = {}
    abs16: list[tuple[int, str]] = []

    def emit(*bs: int) -> None:
        code.extend(bs)

    def label(name: str) -> None:
        marks[name] = len(code)

    def lda(value: int) -> None:
        emit(0xA9, value & 0xFF)

    def sta(addr: int) -> None:
        emit(0x8D, addr & 0xFF, addr >> 8)

    emit(0x78, 0x18, 0xFB)          # SEI; CLC; XCE        native mode
    emit(0xC2, 0x30)                # REP #$30             16-bit A, X and Y

    lda(0x8F)
    sta(0x2100)                     # force blank
    emit(0xE2, 0x20)                # SEP #$20             8-bit A
    lda(0x00)
    sta(0x212C)                     # no layers
    sta(0x2121)                     # CGRAM entry 0
    lda(0x1F)
    sta(0x2122)
    lda(0x00)
    sta(0x2122)                     # entry 0 = red, the failure colour
    lda(0x0F)
    sta(0x2100)                     # display on: RED from here

    lda(0xE0)
    emit(0x8F, 0x00, 0x02, 0x7E)    # STA long $7E:0200   low byte
    lda(0x03)
    emit(0x8F, 0x01, 0x02, 0x7E)    # STA long $7E:0201   high byte

    emit(0xC2, 0x20)                # REP #$20             16-bit A
    emit(0xAF, 0x00, 0x02, 0x7E)    # LDA long $7E:0200   the read under test
    sta(0x0000)                     # both halves into WRAM low page
    emit(0xE2, 0x20)                # SEP #$20

    lda(0x00)
    sta(0x2121)                     # CGRAM entry 0 again
    emit(0xAD, 0x00, 0x00)          # LDA $0000
    sta(0x2122)
    emit(0xAD, 0x01, 0x00)          # LDA $0001
    sta(0x2122)                     # -> GREEN if the round trip worked

    label("spin")
    emit(0x4C)
    abs16.append((len(code), "spin"))
    emit(0x00, 0x00)

    for off, name in abs16:
        target = ENTRY + marks[name]
        code[off] = target & 0xFF
        code[off + 1] = target >> 8

    return bytes(code)


def build(mode: str = "blink") -> bytes:
    rom = bytearray(ROM_SIZE)
    vectors: dict[int, int] | None = None
    if mode == "selftest":
        body = selftest_program()
    elif mode == "stacktest":
        body = stacktest_program()
    elif mode == "hvtest":
        body = hvtest_program()
    elif mode == "bgdraw":
        body = bgdraw_program()
    elif mode == "nmitest":
        body, vectors = nmitest_program()
    elif mode == "dmatest":
        body = dmatest_program()
    elif mode == "dmaflag":
        body = dmaflag_program()
    elif mode == "highbank":
        body = highbank_program()
    elif mode == "wramrw":
        body = wramrw_program()
    elif mode == "wramexec_long":
        # Same routine and same jump, but the routine names its target bank
        # explicitly.  Green here and red in `wramexec` would mean fetch from WRAM
        # works and absolute addressing used the wrong bank; red in both means the
        # fetch itself is what fails.
        body = wramexec_program(use_long=True)
    elif mode == "wramexec":
        body = wramexec_program()
    elif mode == "aputest":
        body = aputest_program()
    elif mode == "highbank_mirror":
        # Bank $8F is the mirror of bank $0F, and retail code runs from these
        # mirrored banks.  Same offset, same expected byte as highbank512 -- the
        # only difference is the bank number the CPU asks for.
        body = highbank_program(bank=0x8F, marker=(0xE0, 0x03))
    elif mode == "highbank512":
        # Top bank of a 512 KiB image: bank $0F address $8000 is ROM offset
        # $78000, the furthest address from the code that this image can hold.
        body = highbank_program(bank=0x0F, marker=(0xE0, 0x03))
    elif mode == "dmarom":
        body = dmaflag_program(src_bank=0x80, src_addr=0x9000)
    else:
        body, _ = program(mode)
    rom[0:len(body)] = body
    if mode in ("highbank512", "highbank_mirror"):
        # Green $03E0 at the top of a 512 KiB image, reached as $0F:8000.
        rom = bytearray(rom) + bytearray(512 * 1024 - len(rom))
        rom[0x78000:0x78002] = bytes([0xE0, 0x03])
    if mode == "highbank":
        # $00,$7C is blue $7C00.  It lives at bank $01 address $8000, which is
        # ROM offset 0x8000 -- outside the bank the program itself runs in.
        rom[HIGHBANK_OFF:HIGHBANK_OFF + 2] = bytes([0x00, 0x7C])
    if mode == "dmarom":
        # Magenta $7C1F.  Distinct from the green in WRAM, so a correct read of
        # this table and an accidental read of WRAM cannot be confused.
        rom[DMA_TILE_OFF:DMA_TILE_OFF + 2] = bytes([0x1F, 0x7C])
    if mode == "dmatest":
        # The two tables the DMA channels read.  They sit above the code and are
        # reached through bank $80, so the transfer's source bank is not the one
        # the program is executing in.  The tilemap is already all zero -- entry
        # $0000 is tile 0, palette 0, no flip -- so only the tile is written.
        rom[DMA_TILE_OFF:DMA_TILE_OFF + 16] = b"\xFF" * 16

    # LoROM, slowrom, ROM only, 64 KiB, 8 KiB WRAM, USA.
    title = b"TINYSNES " + mode.upper().encode() + b" TEST"
    rom[HEADER:HEADER + 21] = title[:21].ljust(21, b" ")
    rom[0x7FD5] = 0x20              # map mode: LoROM, slowrom
    rom[0x7FD6] = 0x00              # ROM only
    # Derived from the image rather than hard-coded: a padded cartridge has to
    # declare its real size or the mapper's rom_mask clips the upper banks away
    # and the test reads back the wrong bytes.
    rom[0x7FD7] = len(rom).bit_length() - 11     # code size as log2(KiB)
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
    for off, target in (vectors or {}).items():
        rom[off:off + 2] = target.to_bytes(2, "little")

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
    ap.add_argument("--mode", default="blink", choices=("blink", "flash", "selftest", "stacktest", "hvtest", "bgdraw", "nmitest", "dmatest", "dmaflag", "dmarom", "highbank", "highbank512", "highbank_mirror", "aputest", "wramexec", "wramexec_long", "wramrw"),
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
