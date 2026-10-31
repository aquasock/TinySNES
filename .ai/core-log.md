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

## 3 COMMIT Unreleased 2026-10-30T22:38:50-07:00

#### Coming From:

Unreleased 81e91a1

#### Purpose:

Find out why the SNES machine does not execute after a ROM loads, by testing the memory path and then following the data from the loader to the CPU.

#### Outcome:

The machine still does not run, but the fault is now located past memory. The DQ capture in `fpga/snes/src/sdram_cl2_2ch.v` was changed to TinyNES's shape -- `dq_fall` on the falling edge, `dq_rise` on the rising edge, read data used one fclk later, so the port-0 sample moved from `cycle[4]` to `cycle[5]` and the ARAM sample from `cycle[1]` to `cycle[2]` -- because with the 225-degree clock the old sample at 3T sat about 0.4 ns after the SDRAM began driving, while the new capture at 3.5T has roughly 8 ns of setup and 4.4 ns of hold against datasheet worst case. A first attempt that also replaced the SDRAM clock with an ODDR on fclk killed the picture entirely: `fclk` routed into a right-edge IOLOGIC at X181Y23 displaces `hclk5`'s path to `div5` and the three OSER10s, and three earlier images failed the same way. That ODDR was reverted and must not be reintroduced; the source paths for the pixel and SDRAM clocks are now identical to the build the user confirmed synced. With the capture change in place the user saw the letterbox and the static 7x8 grid return, so the capture was not the fault, and `fpga/snes/src/sdram_bist.v` settled the memory question on hardware: walking-one and walking-zero patterns plus four high addresses, 36 write/read pairs, every one of the 16 data bits correct, drawn as 16 gapped bars with a status band and read off the screen as all green with a green band. The loader was then cleared the same way: `TINYSNES_LOAD_COUNT` counted the loader's own SDRAM write issues and the bars lit progressively to all eight thresholds including the top one at 500,000 words, so a full 1 MiB image is issued, and the landing probe in `fpga/snes/src/rom_probe.v` found the image's first word 0xD878 at SDRAM word 0 with no displacement at 16, 32, 64, 128, 256, 512 or 1024 bytes. The machine's gates are all open too: the border reads white for `header_finished`, `loaded` and `enable`, and `ROM_CE_N` toggles, so the CPU is fetching. What it fetches is wrong: `TINYSNES_FETCH_PROBE` latched the CPU's first ROM fetch, which should be ActRaiser's reset vector 0x8000 from offset 0x7FFC, and every bit came back zero. The remaining fault is therefore in the fetch path between the mapper's `ROM_ADDR` and `ROM_Q`, not in memory, not in the loader and not in the machine's start-up gates. Three of this cycle's readings were the instrument's fault, not the machine's, and are recorded so they are not re-derived: a first probe build handed the CPU port to the probe from reset, which disconnected the loader's writes, and the later `-DTINYSNES_EXP` values never reached the module's `EXP` parameters, so every comparison ran against zero and reported red. The user decided on 2026-10-30 that hold violations do not block a build, which is now `TINYSNES_ALLOW_HOLD=1` passing `--timing-allow-fail` to nextpnr with the Fmax gate still enforcing clock periods, though every build used for a measurement took a seed with no hold violations, because a hold violation in the instrument's own logic would corrupt the result it reports; seeds 1 to 4 failed on this netlist and 5 to 8 routed clean. The production configuration was rebuilt from the committed tree at seed 5 with `tinysnes.fs` SHA-256 `01e89c097459aa6b09832779f351e3c91f6e063e50ae1ebe17a3efb769d65b89`, no hold violations, the same four benign `hclk5` dedicated-routing warnings as the known-good build, and fclk 253.8, hclk 119.7 and iosys.clk 27.3 MHz against 64.5, 74.25 and 21.5. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was not changed, checked that entries 1 and 2 were not rewritten, revised TCL-007 in place in `.ai/core-reference.md` and added TCL-008 and TCL-009, and validated this entry's numbering, six sections, one-sentence Purpose, prose, Status values and the three-entry count against the 100-entry limit.

#### Next Steps:

Take the fetch path next, in this order: print or probe the `ROM_ADDR` that `DSP_LHRomMap` produces for a fetch of `$00:FFFC` and confirm it is `0x007FFC` rather than a HiROM or masked form, since the SDRAM holds the right word at that offset and the CPU still reads zero; then check `rom_addr_sd`/`cpu_req` in `snestang_top.v`, which only issues a ROM request when the address changes, against `ROM_CE_N` width and `ROM_WORD`, because a CPU that samples `ROM_Q` before the controller's capture has no request in flight to sample; then rule out the one fclk of read latency this cycle added to the capture, which is harmless if the CPU's access window is the six master cycles a LoROM read allows but is the first thing to test if the address checks out. `TINYSNES_FETCH_PROBE` is the instrument for all three: extend it to latch `ROM_ADDR` alongside `ROM_Q`, and keep the `TINYSNES_SDRAM_TEST`, `TINYSNES_LOAD_COUNT` and `TINYSNES_ROM_CHECK` builds as the regression set, since each one now has a known-good expected readout. Do not reintroduce the SDRAM-clock ODDR. Nothing else in the tree is broken: memory, loader, header parse, start-up gates and video are all confirmed working on hardware, so a working picture is one fetch-path fix away.

#### Files Modified:

- fpga/snes/src/sdram_cl2_2ch.v
- fpga/snes/src/snestang_top.v
- fpga/snes/src/snes2hdmi.v
- fpga/snes/src/sdram_bist.v
- fpga/snes/src/rom_probe.v
- tools/build_tinysnes.sh
- tools/rom_probe_expect.py

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: FAIL

---

## 4 COMMIT Unreleased 2026-10-31T08:06:17-07:00

#### Coming From:

Unreleased c8f8b31

#### Purpose:

Replace the fetch probe with a time-resolved instrument that separates a wrong address from a sample taken before the data exists, and read it on hardware.

#### Outcome:

The single-shot fetch probe became an instrument that samples the first ROM access three times: `fp_bus` now carries `ROM_Q` at the first assertion of `ROMSEL` and two and four mclk later plus `ROM_ADDR[15:0]` and `ROM_ADDR[23:8]` for that access, drawn by `snes2hdmi` as five 16-bar stripes, and detection no longer depends on `ROM_OE_N`, which derives from the master-cycle enables and is low for most of an access rather than marking a read. The sampler was simulated before it was trusted: `tools/tests/fetch_probe_tb.sh` extracts the block verbatim from `snestang_top.v` and drives a value that changes every master clock, and it reports PASS with the fields landing on offsets 0, 2 and 4, a second access unable to rewrite the window, and an assertion made before `enable` ignored. Seed 5 built with `TINYSNES_FETCH_PROBE` in `build/fetch2`, passed the timing gate at fclk 264.760 against 64.516 MHz, hclk 187.829 against 74.250 and iosys.clk 32.044 against 21.505, and routed with no hold violations, giving `tinysnes.fs` SHA-256 `c6c8b55187c698ae026b69cd8ec2ed03ed24461eb49f7ba464c71a3f0fe135de` and `tinysnes.bin` SHA-256 `0538612fbd1d1be241b8985ed8abff83e9135d712d6cdaac6792ce22a93ec6b3`. The image was staged on the card with `tangput` as `/root/cores/console138k/tinysnes-fetch.bin`, verified against the local file at head, middle and tail after a first upload proved corrupt, loaded with `tangload`, and the core answered as ID 2; the card's `zelda.smc`, 1 MiB and LoROM with no copier header, was pulled to the host with `tangget` and loaded through `tools/load_snes_rom.py`. The user's readout of the five stripes was 0x0000, 0x0000, 0x8000, 0x7FFC and 0x007F with a white status band, which refutes the premise of entry 3: the mapper produces 0x7FFC for the reset vector, the ROM returns 0x8000, and the word reaches the CPU's port four master clocks, about 186 ns, into an access whose slow-memory latch falls at `CPU_LAST_CLOCK` 7 of eight, so the fetch path was never returning zero -- the old probe was sampling two clocks before the controller could answer. The machine still does not run, so the fault is past the fetch path. One tooling defect is recorded because it cost a corrupt upload: `tangput` terminated with CRLF leaves the LF in the console's input queue as the file's first byte and drops the image's last byte while the size still matches, and a bare CR is correct. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was not changed, checked that entries 1 to 3 were not rewritten, revised TCL-007 and TCL-008 in place and added TCL-010 and BRD-004, and validated this entry's numbering, six sections, one-sentence Purpose, prose, Status values and the four-entry count against the 100-entry limit.

#### Next Steps:

Find out whether the CPU executes at all, because the fetch path is now exonerated and the machine's failure has to be past it: add a diagnostic that counts `ROMSEL` bursts since `enable` and snapshots the CPU's own program counter through the core's unused debug port, where `DBG_SEL[0]` selects the CPU and `DBG_REG` 0x06 and 0x07 return `PC[7:0]` and `PC[15:8]`, so no upstream file needs to change; draw the counter and two PC samples as stripes and read whether the counter races, which puts the fault in the PPU, the SPC700 or the ARAM port rather than the CPU, or stands still, which leaves the PC naming the address where execution stopped and the ROM image naming the instruction. Keep `TINYSNES_SDRAM_TEST`, `TINYSNES_LOAD_COUNT`, `TINYSNES_ROM_CHECK` and `TINYSNES_FETCH_PROBE` as the regression set, each with a recorded expected readout, re-run `tools/tests/fetch_probe_tb.sh` after any change to the sampler, and do not reintroduce the SDRAM-clock ODDR. A new finding that moves the fault again is a revised plan for the user, not a continuation of this one.

#### Files Modified:

- fpga/snes/src/snestang_top.v
- fpga/snes/src/snes2hdmi.v
- tools/tests/fetch_probe_tb.sh
- tools/tests/fetch_probe_tb.sv

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 5 COMMIT Unreleased 2026-10-31T08:30:04-07:00

#### Coming From:

Unreleased 359aac1

#### Purpose:

Find out whether the CPU executes at all, since the fetch path was exonerated and the machine still does not run.

#### Outcome:

A second probe, `TINYSNES_CPU_PROBE`, drives the debug port the core already carries but nothing used: `DBG_SEL[0]` selects the CPU, `DBG_REG` 0x06 and 0x07 return `PC[7:0]` and `PC[15:8]` and 0x09 and 0x0A return SP, with `DBG_DAT_OUT` combinational in `DBG_REG` and `DBG_REG_WR` held low so nothing is written; no upstream file changed. It counts assertions of `ROMSEL` and samples PC every 2^22 mclk, and draws the counter's two halves, the last two PC samples and SP as the same five stripes the fetch probe uses, so both probes now share one display behind `TINYSNES_PROBE_BARS` in `snes2hdmi.v`. Simulation came first and earned it: `tools/tests/probe_tb.sh` extracts each sampler verbatim and runs both benches, and it caught two defects that would each have wasted a hardware cycle -- `always @(*)` driving a constant has no sensitivity, so `dbg_sel` and `dbg_reg_wr` never drove, and the PC byte registers were declared 16 bits wide, so `{pc_hi_r, pc_lo_r}` truncated and the PC would have read as its high byte alone. Seed 5 built with `TINYSNES_CPU_PROBE` in `build/cpu`, passing the timing gate at fclk 177.399 against 64.516 MHz, hclk 178.317 against 74.250 and iosys.clk 31.997 against 21.505, with no hold violations, giving `tinysnes.fs` SHA-256 `b4622093be35e46080877944da9e17442c0b79090bd85ac5a27e0cebbbc6c32c` and `tinysnes.bin` SHA-256 `6d5b5979aeb5ac924eae6917c0e9705aac37219214b7989bd900168a60700075`; the other four diagnostic builds were re-elaborated against the restructured display and all still build. Deployment was one-wire this cycle: `openFPGALoader -b tangconsole` from the oss-cad-suite copy, because the system copy at v0.13.1 has no such board, then the card's `zelda.smc` streamed at the core's UART on `/dev/ttyUSB1` by `tools/load_snes_rom.py --uart`. One black screen was investigated and dismissed as the bench's capture card, not the design: the routed netlist places `div5` at X181Y81, the three PLLs at X177Y27, X177Y81, X178Y45 and the three OSER10s at X181Y57, X181Y100 and X181Y102 in both the working build and this one. The user's video readout, decoded from five frames spanning its 12.9 s, is a frozen ROM access count of 42628 on both halves of the counter, a PC moving only through 0x7C7C, 0x7C7D, 0x7C7E and 0x7C7F, SP at 0x0101, and a white status band. The CPU therefore executes -- about 12 ms of ROM fetches -- and then stops touching the ROM entirely while cycling through four consecutive addresses, which is the footprint of a jump to itself executing where no ROM is mapped, `$00:7C7C` being outside the LoROM window; SP 254 bytes below its reset value agrees that the stack ran away before that point. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was not changed, checked that entries 1 to 4 were not rewritten, revised TCL-008 and BRD-003 in place and added EXT-004, and validated this entry's numbering, six sections, one-sentence Purpose, prose, Status values and the five-entry count against the 100-entry limit.

#### Next Steps:

Find the address where execution left the ROM, because the CPU runs and then jumps into unmapped space and the last fetched address names the instruction that did it: shift the last four `ROM_ADDR` values into a ring on each `ROMSEL` assertion and draw them as three 16-bit stripes plus `ROM_ADDR[23:8]` for the newest and the access counter, then disassemble `zelda.smc` at that offset, which is already on the bench at `/tmp/zelda.smc`. A last address inside valid boot code whose following jump target looks sane points at a corrupted read, and the SDRAM refresh racing the CPU port is the first explanation to test, since the port answers four master clocks into a six-clock window and a refresh that steals it would return stale data; a last address that is already wrong, or an opcode that no compiler would emit, points at the fetch path or the mapper instead. Keep all five diagnostic builds as the regression set with their recorded readouts and re-run `tools/tests/probe_tb.sh` after any change to a sampler.

#### Files Modified:

- fpga/snes/src/snestang_top.v
- fpga/snes/src/snes2hdmi.v
- tools/tests/probe_tb.sh
- tools/tests/cpu_probe_tb.sv
- tools/tests/fetch_probe_tb.sv

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---
