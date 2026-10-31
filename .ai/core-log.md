## 1 COMMIT Unreleased 2026-10-30T16:52:35-07:00

#### Coming From:

Unreleased 03722d0

#### Purpose:

Open the project by building nand2mario's SNESTang SNES core for the Tang Console 138K with the open flow instead of Gowin EDA.

#### Outcome:

The repository now carries SNESTang at commit `5f0ef19` in `fpga/snes/`: its `src/` tree unchanged except for twelve files, TinyTang's slang-clean copy of hdl-util's HDMI transmitter in `fpga/snes/hdmi/`, and three hand-written PLL wrappers in `fpga/snes/pll/` whose parameters match the vendor-generated originals and which open no Gowin-generated file. `fpga/snes/config.v` replaces upstream's `src/boards/console138k.v` with `CONFIG_V`, `CHIP_DSPn` and `MCU_BL616` and no USB HID, DualShock or SNES-controller pads, since pads reach the core over the BL616 link; `fpga/snes/tinysnes.cst` is upstream's `console.cst` minus those pins; `fpga/snes/tinysnes.sdc` re-derives the clock plan for this board, where fclk is 50 * 40 / 31 = 64.516 MHz and mclk is one fclk in three, and cannot carry upstream's multicycle relaxation because nextpnr's SDC parser has no `get_clocks`. `tools/build_tinysnes.sh` is the flow: yosys 0.69+260 with `read_slang`, the cell libraries passed both as `-v` and as `--blackboxed-module`, `synth_gowin -family gw5a`, `nextpnr-himbaechel` for `GW5AST-LV138PG484AC1/I0`, a timing gate, then `gowin_pack`. Twelve upstream files carry small documented changes, all marked `TinySNES:` in place: the 65C816 `ALU` module renamed `P65C816_ALU` because the Gowin cell library defines a primitive of that name, sixteen `$fdisplay` debug statements replaced by null statements, the vendor `` `error `` guard made a comment, a duplicate `reg active` removed from `snes2hdmi.v`, `kbd_data` made a local reg in `iosys_bl616.v`, a missing `led` driver added for the no-USB configuration, and the eight `MUX2` instances in `vram_spb.v` expressed as a ternary select because the open placer has no spare MUX2 BELs. Synthesis produces a 29,425-cell netlist using 21,638 LUT4 of 138,240, 5,359 DFF, 53 BSRAM and 3 PLL. Place and route is seed-sensitive on the main clock domain: seed 1 gave 53 hold violations, seeds 2, 3 and 4 gave 11 each without the clock-first knob taking effect, and a wider sweep gave 11, 3, 11, 11, 0 and 11 for seeds 5 to 10, so seed 9 is the first clean placement and is the one packed. Its timing gate passed at fclk 209.64 MHz against 64.516, hclk 112.88 against 74.25 and the main domain 31.61 against 21.505, and produced `tinysnes.fs` with SHA-256 `5db9a4e99b583998271b9030f2c27236829c749b202257a45ad9d24c73180873` and `tinysnes.bin` with SHA-256 `2f3676e53c5f738e31bf8d5a946185c972e751ab7389a4edff2d678a3883361f`. Nothing was deployed: no bitstream has been sent to the board, no ROM has been loaded and the guessed SDRAM clock-enable pin is unverified. `THIRD_PARTY.md` records the vendored GPL-3.0 and MIT sources and notes that this repository's own licence is undecided. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was not changed and that only the empty `core-log.md` and `core-reference.md` were filled, and validated this entry as entry 1 with six canonical sections, a one-sentence Purpose, prose in Outcome and Next Steps, an allowed Status set and a count of one against the 100-entry limit.

#### Next Steps:

Deploy `tinysnes.bin` with `tangload` and check in order the UART link to the BL616, ROM loading from the card, SDRAM behaviour and video, watching first for the guessed `O_sdram_cke` pin on W19, which is the one pin in this design that no upstream source justifies; then decide whether seed 9 is pinned as the published placement or whether the build refuses any placement with hold violations, the way TinyNES and TinyTang refuse unclean seeds; then confirm whether the 1-bit `SP` block RAMs in `vram_spb.v` read back correctly on this chip, which TinyNES's build notes flag as unproven outside 9-bit modes; and then replace the remaining vendor-generated wrappers (`gowin_dpb_*`, `vram_spb`, `iosys/gowin_dpb_menu`) with hand-written equivalents, as the PLLs already are.

#### Files Modified:

- .gitignore
- THIRD_PARTY.md
- fpga/snes/config.v
- fpga/snes/tinysnes.cst
- fpga/snes/tinysnes.sdc
- fpga/snes/pll/gowin_pll_27.v
- fpga/snes/pll/gowin_pll_hdmi.v
- fpga/snes/pll/gowin_pll_snes.v
- fpga/snes/hdmi/
- fpga/snes/src/
- tools/build_tinysnes.sh
- tools/fs_to_bin.py

#### Status:

- Build: PASS
- Deployment: NOT RUN
- User Test: NOT RUN

---

## 2 COMMIT Unreleased 2026-10-30T19:24:10-07:00

#### Coming From:

Unreleased bdfe60b

#### Purpose:

Make TinySNES produce a stable picture on the Tang Console and run a ROM through it.

#### Outcome:

The video path is solved and the machine is not. Three images produced no signal at all: the design took the 74.25 MHz pixel clock from the HDMI PLL's second output, and under nextpnr that output was routed through tile-local CLK1/CLK2 hops while the 371.25 MHz serialiser clock took the FCLKA paths, so the OSER10s had no usable PCLK/FCLK relationship. A first attempt at dividing the 5x clock inside the design failed twice, the second time with `Net hclk5 has no route to the FCLK of s2h.hdmi.serializer.gwSer0 (sink wire X181Y102/FCLKA)`, because the divider and the PLLs were being placed freely; TinyNES's `fpga/ae350_soc/ae350_soc.cst` and TinyTang's `fpga/desktop/desktop.cst` both pin exactly this and say why. Copying their shape fixed it: `gowin_pll_hdmi` rewritten as TinyTang's single-output 371.25 MHz wrapper, a `CLKDIV #(.DIV_MODE("5"))` named `div5` making the pixel clock, and `INS_LOC` placing `pll_snes.PLL_inst` at `PLL_R[0]`, `pll_27.PLL_inst` at `PLL_R[1]`, `pll_hdmi.PLL_inst` at `PLL_R[3]` and `div5` at `RIGHTSIDE[4]`. That configuration routes on seeds 1, 2 and 4 with no hold violations and the user reported a synced, stable picture with the correct letterbox: a black 256x224 active area between grey borders. Three diagnostic builds followed, each behind an `ifdef` in `snes2hdmi.v` and selected with `TINYSNES_DEFINES`: `TINYSNES_TEST_PATTERN` drew fixed colour bars and proved the HDMI chain lockably, `TINYSNES_OVERLAY_ONLY` removed the line-buffer read and produced the overlay page, and `TINYSNES_DBG_BORDER` drove the border colour from three machine-state bits. The new `tools/load_snes_rom.py` streams a ROM over the TangCore frame protocol, either through the console's `fpgapipe` or straight at the core's UART with `--uart`; it was checked against nand2mario's own loader in `firmware-bl616/core/snes.cpp`, whose sequence it matches (loading state 1, the 64 header bytes from `0x7FC0` plus 512 if a copier header is present, the file from `off` in 1024-byte chunks as `0x07` frames with `len+1`, `overlay(0)`, loading state 0). With that loader the debug border reads yellow in both one-wire and two-wire, so `header_finished` and `loaded` are both set and the frame protocol and header parse work; the machine still shows a static 8x7 grid of black tiles with a grey top edge in every case, and a 32 KiB hand-assembled test ROM that only sets CGRAM colour 0 to blue and spins does not run. The remaining fault is the SDRAM PHY: TinyNES's working `fpga/ae350_soc/ahb_sdram.sv` clocks the part from an `ODDR` on `clk` and captures `sdram_dq` on negedge then posedge, while SNESTang's `sdram_cl2_2ch.v` drives `O_sdram_clk` from the PLL's 225-degree output and samples `dq_in` on posedge `fclk`, a hand-tuned arrangement that nextpnr does not reproduce; ROM, WRAM and ARAM all live in that SDRAM, which is why a broken memory path presents as a dead CPU. The core answered as ID 2 over the link throughout, `tangload` and `openFPGALoader -b tangconsole` both load the image, and the two-wire console re-enumerated repeatedly after core loads, matching the power-droop note in TinyNES. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was not changed, checked that entry 1 was not rewritten, and validated this entry's numbering, six sections, one-sentence Purpose, prose, Status values and the two-entry count against the 100-entry limit.

#### Next Steps:

Replace the SDRAM read path in `fpga/snes/src/sdram_cl2_2ch.v` with TinyNES's capture arrangement, either an `ODDR`-driven clock with negedge/posedge input registers or the same capture on the existing 225-degree clock, and move the controller's fixed sampling points to match; the gate is the 32 KiB blue-screen test ROM turning the active area blue, which will also confirm that ROM, WRAM and ARAM are all readable. After that, the OSD text page still draws nothing even with `osd on` and a string sent over a link that demonstrably delivers frames, which is a separate fault in the font or text path, and only then are real carts worth testing.

#### Files Modified:

- fpga/snes/pll/gowin_pll_hdmi.v
- fpga/snes/src/snes2hdmi.v
- fpga/snes/src/snestang_top.v
- fpga/snes/tinysnes.cst
- tools/build_tinysnes.sh
- tools/load_snes_rom.py

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: FAIL

---
