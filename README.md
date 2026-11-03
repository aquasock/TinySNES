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
  FastROM, ROM+RAM+battery, DSP-1). Mario Kart is the first HiROM and the first
  fastrom cartridge confirmed here, and the first working coprocessor.
- **SuperFX: built, does not yet run.** The coprocessor is in the bitstream and
  the machine boots with it, but its cartridges fail. Star Fox (1 MiB, `$13`),
  Vortex (512 KiB, `$14`) and Yoshi's Island (2 MiB, `$15`) all draw the grey
  pillarbox bars around a blank picture, so the fault is total across ROM sizes
  and GSU generations rather than specific to one title. Two candidates are open,
  both named in `tools/sim/run_board_sim.sh`: the GSU's cache clock is generated
  by a LUT inverter rather than the global network, because `GSU.v` mixes
  `negedge` and `posedge` on one inferred array; and its BSRAM port loses about
  72 percent of requests to the controller's toggle collapse, with no
  acknowledge input on `GSUMap`.
- **Not tested:** controller input and the OSD.
- **No saves persist.** Nothing in the tree writes SRAM back to the card.

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

## Layout

```
fpga/snes/src/      SNESTang's sources, deviations marked `TinySNES:` in place
fpga/snes/hdmi/     hdl-util's HDMI transmitter, slang-clean
fpga/snes/pll/      hand-written PLL wrappers matching the vendor parameters
fpga/snes/*.cst     pin and clock placement for the Console 138K
tools/              build, deploy, ROM loading, probes, frame analysis
```

## Known gaps

- **SuperFX.** Yoshi's Island and Star Fox need the GSU coprocessor. The source
  is present (`fpga/snes/src/chip/GSU/`, ~2,100 lines) and wired into `main.v`
  behind `USE_GSU`, but `config.v` defines only `CHIP_DSPn` and the three GSU
  files are not in the synthesis list in `build_tinysnes.sh`. Enabling it needs
  those two changes plus its own placement seed and margin check.
- **Controller input** arrives over the BL616 link and has not been exercised.
  `config.v` sets no controller pads, so a game waiting at "press start" is
  indistinguishable from a hang until this is tested.
- **The OSD is tied off** (`iosys_bl616.v`). `overlay_reg` powers up asserted and
  `snes2hdmi` draws the overlay in preference to the picture while it is set; the
  menu is empty in one-wire mode, so the whole picture area is black by
  construction. TinyDesk is meant to replace it.
- `TINYSNES_CART_WAIT` in `snestang_top.v` refers to wait-state machinery removed
  when the core was reverted to upstream. It should be removed or re-derived.
- The board occasionally fails to boot a cartridge on the first load; a reflash
  clears it. Cause unknown.
