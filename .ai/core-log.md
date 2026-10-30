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
