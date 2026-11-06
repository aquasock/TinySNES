# TinySNES

SNESTang, ported to the Tang Console 138K with the open flow — yosys with the
slang front end, `nextpnr-himbaechel` against the GW5AST-138C database, and the
apicula fork's `gowin_pack`. No Gowin EDA is involved.

**Retail cartridges boot.** Space Invaders, The Legend of Zelda: A Link to the
Past and Super Mario Kart all run with correct video and audio, confirmed on the
board's HDMI output.

The design is nand2mario's SNESTang at `5f0ef19`, with this board's own pinout,
clock plan and HDMI stack. The core is upstream's: `cpu.v`, `SNES.v`, `main.v`,
`ppu.v` and `swram.v` are byte-identical, `smp.v` and `dsp.v` differ only by
removed `$fdisplay`, and `sdram_cl2_2ch.v` by one output port declared and tied
low so the top level needs no edit.

Three changes go beyond that, and each has a measurement behind it:

- **`PAL = 1'b0` in `snestang_top.v`.** Upstream leaves `reg PAL` undriven and
  relies on Gowin tying it low; Yosys makes it constant `x`, which propagates
  into the PPU's HV counters and freezes the raster.
- **`fclk` on the clock spine.** apicula's `_gw5a_pll_clk_wires` gives
  GW5AST-138C three PLL-to-plane wires: CLKOUT0 on each edge and CLKOUT2 on the
  left edge only. CLKOUT1 has none, and upstream puts `fclk` — the SDRAM
  controller's clock — on CLKOUT1, so it was routed point to point across 18,400
  characters with no spine tap, which neither the hold check nor the Fmax gate
  can report. `pll_snes` now sits at `PLL_L[0]`, `fclk` is on CLKOUT2 reaching
  `TLPLL0CLK2`, and the 225-degree shift moved to CLKOUT1, which drives only
  `O_sdram_clk`. Verified by Zelda and Super Mario Kart booting.
- **`read_slang --single-unit`.** Without it each file is its own compilation
  unit, so `config.v`'s `define`s never reached `snestang_top.v` and the
  committed configuration built a core with **no cartridge DSP and no SuperFX**.
  The build now also asserts on the netlist that a configured chip is present.

## Status

- **Machine: working.** Retail boots, video and audio both correct.
- **Boot screen:** with no cartridge loaded the core draws the same eight-bar
  colour pattern as TinyNES and TinyGBC (white, yellow, cyan, green, magenta,
  red, blue, black) across the full raster. Previously it showed an
  uninitialised line-buffer ramp, which read as a fixed tile grid. Gated off in
  every diagnostic build so those still show their own results.
- **Tested cartridges:** Space Invaders (256 KiB, LoROM), Zelda: A Link to the
  Past (1 MiB, LoROM, ROM+RAM+battery), Super Mario Kart (512 KiB, HiROM,
  FastROM, ROM+RAM+battery, DSP-1), Donkey Kong Country (4 MiB, HiROM, FastROM),
  Super Castlevania IV (1 MiB, LoROM) and Chrono Trigger (4 MiB, HiROM, FastROM,
  ROM+RAM+battery). Mario Kart is the first HiROM and the first fastrom
  cartridge confirmed here, and the first working coprocessor. Donkey Kong
  Country is the first 4 MiB image, twice the size of the previous largest, and
  it confirms the whole size range the mapper supports. F-Zero runs with correct
  video and audio, confirmed on the board on 2026-11-05.
- **SuperFX: the GSU runs.** Star Fox, Vortex, Yoshi's Island, Stunt Race FX,
  Dirt Trax FX, Star Fox 2 and Doom all run; Winter Gold is PAL and stops at its
  region check. The blank screen every GSU title used to show was the GSU
  stopping on its first ROM load, caused by the synthesis flow rather than the
  RTL: on GW5A, yosys builds a negedge flop with an enable or reset as a posedge
  flop behind a LUT clock inverter, so the GSU's `EN` (a plain negedge flop) and
  its ROM/RAM handshake flops clocked a few ns apart with no timing check
  between them. `EN` now has a reset so it shares the inverted clock, and
  `tools/clock_edge_check.py` refuses any netlist that splits a clock edge that
  way again. Two picture defects found since were also real rather than
  timing: GSU tile addressing, and `MULT`/`FMULT`/`LMULT` taking `YA` as
  unsigned where it is signed.
- **Audio and video:** correct on every tested cartridge, including the 4 MiB
  title and the DSP-1 title. The S-DSP is complete in this core -- BRR with all
  four filters, Gaussian interpolation, ADSR and the GAIN modes, pitch
  modulation, noise and echo with its FIR filter.
- **Controller input: working.** A Wii Classic Controller in Adafruit's Wii
  Nunchuck Breakout Adapter on USB-A port 2, read as I2C by fabric on D+ (SDA)
  and D- (SCL), drives the game. It needs two-wire mode: USB-A's VBUS is what
  powers the adapter's pull-ups, so in one-wire mode the pad is electrically
  invisible and reports absent. The BL616 link is not a second route -- `hid1`
  and `hid2` are wired into the top level but TinyTang's firmware never sends the
  `0x09` pad frame, so they stay zero.
- **TinyDesk overlay: working.** `desk_layer.v` draws TinyTang's 80x45 desk over
  the picture and a tap of the Wii Classic Controller's HOME button opens and
  closes it; game input is held idle while it is shown. The rest of the UI -- a
  ROM browser and a core menu -- is not built.
- **Desk video settings: working.** The desk's Video page sets the picture's
  aspect and whether a 239-line game's extra fifteen lines are drawn or
  cropped, sent to the core in frame `0x1B` and stored in `/tinysnes.ini` at the
  card root. Aspect is 4:3 at 960 pixels, 8:7 at 940 and 1:1 at 823, all from a
  256-pixel line scaled to 720 rows. The defaults reproduce the geometry this
  core had before the setting existed, so a build that never receives the frame
  looks unchanged. The extra-lines row has no evidence behind it yet: it only
  takes effect on a cartridge that sets SETINI bit 2, and none tested here is
  known to.
- **Desk audio volume: working.** The desk's Audio page sets one master volume
  and a mute, sent to the core in frame `0x1C` and stored in `/tinysnes.ini`.
  `audio_volume.v` applies the gain once, between the S-DSP and both of its
  consumers, so HDMI and the Pmod I2S2 cannot disagree. The BL616 computes the
  gain, squaring the percentage out of unity 256 the way TinyNES does, and 100
  percent is a bit-exact pass-through, so a build that never receives the frame
  sounds exactly as it did before.
- **Not tested:** the OSD above the desk (`iosys_bl616.v`), which is tied off.
- **Saves: the mechanic works, persistence does not exist.** A game writes its
  save to the cartridge SRAM in SDRAM and reads it back correctly, so saving and
  loading inside a session both work. Nothing in the tree writes that SRAM out to
  the card, so there is no save file, and a power cycle loses it. One measurement
  is worth keeping because it is easy to mistake for persistence: a save survived
  a core reload, for the several seconds `tangload` takes to reprogram the FPGA
  with the SDRAM left unrefreshed, and was gone after a reboot on the same card
  and the same build. Cell retention across an unrefreshed gap is not a save
  path; do not read it as one.

## Build

```
tools/build_tinysnes.sh                                   # build/tinysnes
TINYSNES_SEED=9 tools/build_tinysnes.sh
TINYSNES_BUILD_DIR=build/diag \
  TINYSNES_DEFINES=-DTINYSNES_LINEFILL_PROBE tools/build_tinysnes.sh
```

| variable | meaning |
|---|---|
| `TINYSNES_STAGE` | `synth`, `pnr`, `pack` or `all` |
| `TINYSNES_BUILD_DIR` | output directory |
| `TINYSNES_SEED` | placement seed; the router is seed-sensitive |
| `TINYSNES_DEFINES` | preprocessor defines for a diagnostic build |
| `TINYSNES_ALLOW_HOLD` | `1` lets an unclean placement through; the Fmax gate still runs |
| `TINYSNES_ALLOW_UNMEASURED_CLOCKS` | `1` permits a clock on a pip never measured on this board |
| `TINYSNES_CLK_FIRST` | which clock net the global router takes first |

Synthesis takes about a minute, place and route five to fifteen. A build that
fails place and route with nets unrouted is the known seed sensitivity, not a
broken change — sweep with `tools/sweep_mclk.sh`, which routes several seeds in
parallel and ranks them by SNES-clock margin.

**Seed 9 is the proven placement** (`tinysnes.fs` SHA-256
`e6ebba7ac2aa8af5f0c58be8742b84da7d336e88a88c2b171c4f2691d1a7814d`). It routes
hold-clean with 46% margin on the SNES master clock. Note that nextpnr does not
reproduce a bitstream from an unchanged netlist and seed — only the RTL is
reproducible, not the placement.

## Deploy (one-wire)

One-wire puts the bitstream in the FPGA over the FT2232 and streams the cartridge
straight at the core's UART. Use the oss-cad-suite copy of `openFPGALoader`; the
system copy at v0.13.1 has no `tangconsole` board.

```
tools/onewire.sh build/tinysnes game.sfc        # flash, stream, capture
```

or by hand:

```
~/oss-cad-suite/bin/openFPGALoader -b tangconsole build/tinysnes/tinysnes.fs
tools/load_snes_rom.py --uart /dev/ttyUSB1 game.sfc
```

Two facts that cost time when forgotten. A flash that reports `Done` can still
leave the board silent, and the fix is to load the same file again — **a single
flash is not a test of a bitstream**. And flashing clears the core's `loaded`
state, so a cartridge must be streamed again after every flash.

## Cartridge test images

`tools/make_test_rom.py` builds small LoROM images that each exercise one
mechanism, so a failure names a subsystem. Twenty-six modes, including
`blink`, `bgdraw`, `aputest`, `dmatest`, `vramrb`, `wramexec` and `highbank`.

```
tools/make_test_rom.py --mode bgdraw -o build/rom/bgdraw.sfc
```

## Diagnostics

`tools/frame_stats.py` classifies captured frames as `image`, `blank` or
`no-signal` by looking for the pillarbox bars. Use it rather than a
dominant-colour count: a black picture with bars and a frame with no bars are
both `(0,0,0)` in a histogram and mean completely different things.

`tools/clock_plane_report.py` reports which spine/bridge pip each clock takes.
On this device a clock reaches the global network through a bridge pip and not
every one clocks its branches, so a clock on an unmeasured pip may be silent.

`tools/emit_gatelevel.sh` and `tools/report_linebuf_gate.py` inspect the shipped
netlist rather than a simulation of it.

`tools/clock_edge_check.py` runs as build step `1b` and fails a netlist in which
one clock drives both a true negedge flop and a LUT clock inverter. Those two
halves clock a few ns apart and nextpnr does not time between them; that split
is what stopped the SuperFX.

`tools/tinysnes_dbg.py` talks to the core's debug endpoint over the BL616 link
(two-wire, `/dev/ttyACM0`): `status` reports GSU state and counters, `knob`
overrides the GSU's `ROM_CYCLES`, and `trace` dumps the GSU's ROM-latch and
opcode trace buffers. Its peek commands read zero, because a second read port on
WRAM or BSRAM made yosys duplicate both arrays and exhausted block RAM.

## The bench, and its limits

`tools/sim/run_sim.sh` runs the full core against behavioural memories. It
answers "is the core logic correct?" and it earned its place by finding the
undriven `PAL`.

It **cannot** answer "does this work on the board." It models the cartridge, WRAM,
VRAM and ARAM as plain arrays with no latency, and has no SDRAM controller, no
physical clock domains and no HDMI. Its `mclk` and `fclk` are unrelated ideal
oscillators, so a design whose correctness depends on the phase relationship
between them cannot fail in it. Eight subsystems passing here while the board
showed nothing was not a contradiction to explain away — it was the bench
reporting on a different machine. Reach for hardware once the logic is right.

`+frame=PATH` writes one 256x224 frame as a PPM, which is the only reading that
distinguishes a title screen from noise.

A second, narrower bench covers the SPC700 alone: `tools/sim/run_spc_diff.sh`
runs this core and MiSTer's, converted from VHDL by `tools/sim/spc_ref/`, on the
same random program and compares PC, A, X, Y, SP, PSW and the write count at
every instruction boundary. Differences in instruction *implementation* are
invisible to a bench that agrees with itself, which is how an SPC700 that shifted
the wrong operand survived this long; this one found that class. Two divergences
are expected and are reported rather than counted as failures: `DIV` overflow,
where this core implements the chip's nine-step rotate-and-subtract and MiSTer's
reference saturates, and `STP`, which ends a random program.

## Layout

```
fpga/snes/src/      SNESTang's sources, deviations marked `TinySNES:` in place
fpga/snes/hdmi/     hdl-util's HDMI transmitter, slang-clean
fpga/snes/pll/      hand-written PLL wrappers matching the vendor parameters
fpga/snes/*.cst     pin and clock placement for the Console 138K
tools/              build, deploy, ROM loading, probes, frame analysis
```

## Known gaps

- **SuperFX.** All the GSU titles tested run, but Star Fox's picture has not been
  compared side by side against an emulator, and Yoshi's Island still has minor
  glitches. The GSU's BSRAM port has no acknowledge input on `GSUMap`, which
  remains a candidate if a GSU title misbehaves.
- **The OSD behind TinyDesk is tied off** (`iosys_bl616.v`). `overlay_reg` powers
  up asserted and `snes2hdmi` draws the overlay in preference to the picture
  while it is set; the menu is empty in one-wire mode, so the whole picture area
  is black by construction. The TinyDesk layer above it is what works.
- `TINYSNES_CART_WAIT` in `snestang_top.v` refers to wait-state machinery removed
  when the core was reverted to upstream. It should be removed or re-derived.
- The board occasionally fails to boot a cartridge on the first load; a reflash
  clears it. Cause unknown.
