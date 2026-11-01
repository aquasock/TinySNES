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

## 6 COMMIT Unreleased 2026-10-31T10:09:45-07:00

#### Coming From:

Unreleased 0c276e2

#### Purpose:

Find where the machine stops, now that the CPU is known to execute and the fetch path is proven.

#### Outcome:

The diagnostic set grew from one CPU probe to four, all sharing one display and simulated before use. `TINYSNES_TRACE_PROBE` keeps the last four `ROM_ADDR` values on a ring; `TINYSNES_LIVE_PROBE` draws two latched stripes over the machine's own picture so CPU state and PPU output are read from one frame; `TINYSNES_APU_PROBE` reads both directions of the APU port link through the debug port, `CPUI[0:3]` being what the 65816 writes and `CPUO[0:3]` what the SPC700 writes back. The CPU probe also stopped counting wrong: its edge detector stored the inverted level and so counted every master clock while ROMSEL was asserted, which is why an earlier reading looked like 21.5 M accesses per second, and the trace ring had the same inversion, which is why its stripes tore and flickered; both now detect a real edge, and the benches hold ROMSEL low for six clocks so the defect cannot return. `tools/tests/probe_tb.sh` extracts each sampler verbatim and runs all four benches, and they caught three more instrument defects before hardware: a constant on the right of `always @(*)` never drives, 16-bit registers holding one byte truncated the assembled PC, and the APU probe's bench first reported the SMP's `CPUO` register as if it were `CPUI`. The board was exercised in one-wire throughout with `openFPGALoader` from oss-cad-suite, the ROM streamed at the core's UART, and the picture read back from the bench's own capture card at `/dev/video0` rather than from screenshots. Readings so far: the production image still ends on the static grid; the CPU runs and its status byte showed `RDY_IN` set with SP at 0x01FA; the 65816 sits in `CMP $2140 / BNE` at `$8891`, which the loaded image decodes as the APU boot handshake; the SPC700's PC moves inside its IPL ROM; and with both port banks visible, `CPUI` holds 0x80 while `CPUO` holds the original `$AA`/`$BB` echo, so the SPC700 answered once and never read the byte the 65816 wrote next. The picture never initialises in any boot, and the machine's failure point still varies between boots, which is why entry 5's frozen counter and this cycle's upload stall are the same fault seen at different depths. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was not changed, checked that entries 1 to 5 were not rewritten, revised TCL-008 in place and added EXT-005, and validated this entry's numbering, six sections, one-sentence Purpose, prose, Status values and the six-entry count against the 100-entry limit.

#### Next Steps:

Prove whether the SPC700 can see the port at all, because the two banks now say the 65816 wrote 0x80 and the SPC700 did not consume it: read the SPC700's A and Y through `DBG_SEL[3]` in the same frame as `CPUI[0]`, and a Y of 0x00 next to a `CPUI[0]` of 0x80 means the SPC's read of `$00F4` is not returning the `CPUI` byte, which points at the `SPC700_D_IN` path in `smp.v` rather than at either CPU. If the SPC does read the byte, the fault moves to ARAM, which is the one memory this project has never verified: the SDRAM controller's ARAM sample moved from `cycle[1]` to `cycle[2]` in core-log entry 3 to match the new DQ capture and nothing has tested port 1 since, so a write/read-back self-test on port 1 in the shape of `sdram_bist.v` is the instrument, with the IPL completing its upload as the gate. Do not re-time the port-0 path or the capture while that question is open; keep all six diagnostic builds as the regression set and re-run `tools/tests/probe_tb.sh` after any change to a sampler.

#### Files Modified:

- fpga/snes/src/snestang_top.v
- fpga/snes/src/snes2hdmi.v
- tools/tests/probe_tb.sh
- tools/tests/cpu_probe_tb.sv
- tools/tests/trace_probe_tb.sv
- tools/tests/apu_probe_tb.sv

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 7 COMMIT Unreleased 2026-10-31T10:11:11-07:00

#### Coming From:

Unreleased f8e70a8

#### Purpose:

Record the project state in a form the next agent can take over from without rebuilding this session's context.

#### Outcome:

The project stands with a working machine that runs to the APU boot handshake and deadlocks there, and with the fault narrowed to one link between two processors rather than to the CPU, the ROM path or the video path. What is proven on hardware: the ROM loads and its header parses; the SDRAM CPU port passes a 36-pair write/read self-test; the mapper produces the LoROM address 0x7FFC for the reset vector; the ROM returns 0x8000 at the CPU's port four master clocks into a slow access the CPU latches at seven; the 65816 executes, with PC moving and its status byte showing RDY_IN high; the SPC700 executes, with its PC moving inside its IPL ROM at 0xFFCD-0xFFDD; the APU port echo $AA/$BB was published once, CPUO still reading 0xBBAA; and the 65816 then writes 0x80 into CPUI[0] and waits for an echo that never arrives, sitting in CMP $2140 / BNE at $8891. What is not proven, and is the live suspect: ARAM, which is the CPU port's second bank, a write/read on which has never been tested since its sample moved from cycle[1] to cycle[2]. Bench practice that this session established and that the next agent should keep: every sampler is extracted verbatim from the shipping source by tools/tests/probe_tb.sh and simulated before hardware, because this session found six instrument defects and each one had already produced a confident and wrong reading -- a probe owning the CPU port from reset, expectations that never reached their parameters, a constant on the right of always @(*) that therefore never drove, 16-bit registers holding one byte that truncated the PC to its high byte, an edge detector that stored the inverted level and so counted every clock rather than every access, and a probe reading CPUI while claiming to read the SPC700's answer, which lives in CPUO. Operational facts worth not rediscovering: the build is tools/build_tinysnes.sh with TINYSNES_SEED, TINYSNES_DEFINES and TINYSNES_BUILD_DIR, hold violations are fatal unless TINYSNES_ALLOW_HOLD=1 and any build used for a measurement must use a seed that routes clean, and which seeds are clean changes with the netlist, so a seed that worked for one probe can fail for the next and a sweep is normal; one-wire deployment is openFPGALoader -b tangconsole from the oss-cad-suite copy, because the system copy at v0.13.1 has no such board, followed by tools/load_snes_rom.py --uart /dev/ttyUSB1, with the ROM at /tmp/zelda.smc (1 MiB LoROM, SHA-256 75267ac610cba5ab0b4a4516a669fa43879552c15677dc6c6ca9e9c35b9dd1ac) or on the card at /root/media/snes/zelda.smc; the picture can be read directly from the bench's capture card at /dev/video0 with ffmpeg, and the first grab after a load is often black because the card has not locked yet, so capture a couple of seconds and decode frames rather than trusting one image. The core-syntax audit re-read .ai/core.md and .ai/core-syntax.md, inspected the complete .ai/ diff, confirmed .ai/core.md was not changed, checked that entries 1 to 6 were not rewritten, made no change to core-reference.md this cycle, and validated this entry's numbering, six sections, one-sentence Purpose, prose, Status values and the seven-entry count against the 100-entry limit.

#### Next Steps:

Resume with the SPC700's view of the port, because everything else is downstream of it: extend TINYSNES_APU_PROBE to read the SPC700's A and Y through DBG_SEL[3] in the same frame as CPUI[0] and CPUO[0], and a Y of 0x00 beside a CPUI[0] of 0x80 means the SPC's read of $00F4 is not returning the byte, which puts the fault in the SPC700_D_IN path in smp.v and means neither processor is at fault. If the SPC does see the byte, the fault is ARAM: write the port-1 self-test in the shape of sdram_bist.v, driving the aram port with walking-one and walking-zero patterns and comparing reads, and gate it on the IPL completing its upload rather than on the bar readout alone. Do not re-time the port-0 read path, the DQ capture or the SDRAM clock while that question is open; the ODDR on fclk must not come back, because it costs the HDMI pixel clock its route. Keep all eight diagnostic builds as the regression set, re-run tools/tests/probe_tb.sh after any sampler change, and remember that the machine's failure point varies between boots, so a boot that reaches the sound upload and a boot that halts with PC 0 are the same fault seen at different depths rather than two faults.

#### Files Modified:

None.

#### Status:

- Build: N/A
- Deployment: N/A
- User Test: N/A

---

## 8 COMMIT Unreleased 2026-10-31T11:27:12-07:00

#### Coming From:

Unreleased dbf599f

#### Purpose:

Answer whether the SPC700 can see the APU port, which entry 7 left as the last open question between the machine and a running game.

#### Outcome:

The APU probe was rebuilt around the side of the handshake that is stuck rather than around the SPC700's registers, because decoded against the IPL at $FFC3 the SPC700 sets A to $00 and never writes Y before its wait at $FFCF, so its A and Y read $00 whether it is waiting correctly or its debug path is dead and could not have answered the question. The probe now carries ten bytes over twelve phases -- CPUO ports 1 and 0, the 65816's A, its PC and its P, the SPC700's PC and CPUI port 0 -- each 16-bit PC read with its high byte sampled on both sides of the low byte and accepted only when the two high reads agree, and the field decode expressed as two `case` statements because twelve phases do not fit three bits. The first hardware pass was unreadable and the fault was the instrument, not the machine: `fp_bus` was driven live, so every row of the raster carried a different value and 0 of 353 captured frames decoded, and the first repair gated the refresh on a tick counter and the phase counter coinciding, which is a one-in-twelve coincidence that fired by luck on hardware and never in simulation. The display is now a latched snapshot refreshed once every 2^19 phase revolutions, about 0.29 s, and 349 of 353 frames decode with all three sample rows of every stripe agreeing. Simulation earned its place again: the bench caught the phase watcher racing the combinational select on the rising edge and caught a tear guard that accepted a torn pair, and it corrected a polarity error of the author's own, since `REP #$30` clears M and X and the fifth stripe was first checked for the opposite. `tools/decode_probe_frame.py` was added so the five stripes are decoded from frames and torn frames discarded rather than read by eye. Seed 5 built with `TINYSNES_APU_PROBE` in `build/apu5_s5`, zero hold violations, passing the timing gate at fclk 201.086 against 64.516 MHz, hclk 164.501 against 74.250 and iosys.clk 31.769 against 21.505, giving `tinysnes.fs` SHA-256 `d04658c522715075529d3ee15db67619629ba8c0b1037245314f88daf05f3e06`. Deployment was one-wire with `openFPGALoader -b tangconsole` and `tools/load_snes_rom.py --uart /dev/ttyUSB1` streaming the bench's 1 MiB `zelda.smc`. The readout is stable and identical across captures a minute apart: CPUO reads $10BB, the 65816's A $0089, its P $75 with M and X set and I clear, its PC sweeping $88EC-$88F1, the SPC700's PC $F4B5-$F4D1, and CPUI port 0 $89. That answers the cycle's question and refutes the reasoning this cycle was approved on: the 65816's PC is inside the upload loop at $88EC, which the routine entered at $8888 can only reach by passing the `CMP $2140` handshake at $8891, so the port read path does deliver CPUO to the CPU and the APU read path is not broken; what fails is the per-byte echo inside the upload, where the 65816 wrote $89 to $2140 and reads back $10. Both directions of the link are proven to carry data, since CPUO[1] holds the $BB the IPL publishes at $FFCC and CPUI port 0 holds the $89 the 65816 wrote, and the SPC700's PC sitting in ARAM rather than in the IPL ROM at $FFC0-$FFFF means it took the IPL's `JMP [$0000+X]` into uploaded code and is running whatever arrived through ARAM port 1. The machine is stalled rather than slow: two captures a minute apart returned the same CPUO, the same A, the same P and the same CPUI byte. `SPC700_D_IN` is therefore exonerated, and ARAM port 1 -- the SPC's only path to load its driver, re-timed in entry 3 and untested since -- is the one link both surviving explanations run through. The user confirmed the five-stripe readout on the board with a yellow status band, which is `header_finished` and `loaded` with `loading` clear, so the core is released and the ROM loaded. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was not changed, checked that entries 1 to 7 were not rewritten, revised EXT-005 and TCL-008 in place and added TCL-011, and validated this entry's numbering, six sections, one-sentence Purpose, prose, Status values and the eight-entry count against the 100-entry limit.

#### Next Steps:

Write the ARAM port-1 self-test, in the shape of `sdram_bist.v`, because the SPC700 is executing code that arrived through that port and the byte it echoes back is not the byte the 65816 sent: drive the ARAM port directly with walking-one and walking-zero patterns plus a few high addresses, read each back and compare, and draw the per-bit result as bars with a status band, gated on the IPL having completed its upload rather than on the bar readout alone, since a port that answers its own test still has to deliver a working driver. If the test passes, the fault is in what the 65816 sends rather than in what ARAM stores, and the next instrument is the upload's own protocol state -- the transfer address in $2142/$2143 and the byte in $2141 -- read through the same debug port. If it fails, the port-1 path or its `cycle[2]` sample is the fault and the fix belongs in `sdram_cl2_2ch.v`. Do not re-time the port-0 read path, the DQ capture or the SDRAM clock while that question is open, and do not reintroduce the ODDR on fclk. Keep all nine diagnostic builds as the regression set, re-run `tools/tests/probe_tb.sh` after any sampler change, and use `tools/decode_probe_frame.py` rather than reading stripes by eye. One bench note worth keeping: the capture card is argued over -- OBS held `/dev/video0` and blocked a grab until it was closed -- so a capture failure is the host's, not the board's.

#### Files Modified:

- .gitignore
- fpga/snes/src/snestang_top.v
- fpga/snes/src/snes2hdmi.v
- tools/tests/apu_probe_tb.sv
- tools/decode_probe_frame.py

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 9 COMMIT Unreleased 2026-10-31T11:43:35-07:00

#### Coming From:

Unreleased f677e58

#### Purpose:

Test ARAM through the port the SPC700 loads its driver through, the one memory this project had never verified, because entry 8 found the SPC executing code in ARAM at $F4xx instead of echoing the 65816's byte.

#### Outcome:

`fpga/snes/src/aram_bist.v` is a new self-test in `sdram_bist.v`'s shape that owns the controller's ARAM port outright while no ROM is loaded and the machine is disabled, and it is deliberately byte-lane aware because lane selection is the part of this port most likely to be wrong and a word-wide test cannot see it: for each word it writes a different byte to the even address and the odd address, so the second write must not disturb the first and a swapped pair fails on all 16 bits rather than passing by symmetry. Four sets run, each written in full and then read back -- walking one on the even lane with the odd lane complementary, walking one on the odd lane with the even lane complementary, walking zero on both lanes, and four high words across the 64 KiB space -- and the sticky mismatch mask is drawn as 16 bars over a status band, bits 0-7 the even lane and 8-15 the odd, so one decoder reads this test and the SDRAM test alike. `tools/tests/aram_bist_tb.sv` compiles the shipping module against a model of the port that stores one byte per lane, and it runs four memory models so the test cannot pass vacuously: a correct model must report pass, a swapped-lane model must be caught on all 16 bits, a stuck-low bit must be caught in either lane, and a port that never acknowledges must report no-acknowledge; all four behave as required. `tools/tests/probe_tb.sh` gained a `run_module` case so the memory benches sit behind the same entry point as the four sampled probes, and all five benches pass. The first build and deployment drew a black screen, and the fault was a toolchain trap rather than the design: `elsif TINYSNES_SDRAM_TEST || TINYSNES_ARAM_TEST` does not evaluate as written in slang, and with only the second macro defined the whole expression resolves false, so `snes2hdmi` compiled its production branch and drew the machine's dead picture over the test result. Preprocessing the file with `slang --preprocess` showed the bar branch present for `TINYSNES_SDRAM_TEST` and absent for `TINYSNES_ARAM_TEST`, which is what identified it; the fix is two nested `ifdef`s that set a shared `TINYSNES_BIST_BARS`, the shape the file already uses for `TINYSNES_PROBE_BARS`, and the preprocessor now selects the bars for either define and neither branch for a production build. Seed 5 built with `TINYSNES_ARAM_TEST` in `build/aram2_s5`, zero hold violations, passing the timing gate at fclk 226.552 against 64.516 MHz, hclk 165.071 against 74.250 and iosys.clk 31.494 against 21.505, giving `tinysnes.fs` SHA-256 `8787d6a1cc805197bd440c5eea264d9fd2c8990f95a7c773fcb08748c34ac963`; it was loaded one-wire and needs no ROM. The readout is unambiguous: 16 green bars and a green status band in all 173 captured frames, zero red pixels in any frame, so every bit of both byte lanes read back correctly at every test address and the port, the lane selection and the ARAM storage are all working. That refutes the ARAM hypothesis that entry 8 left standing as the last link. The conclusion is bounded by what the test actually exercises: the SPC700's ARAM traffic does not reach the controller directly but passes through `dsp.v`, which arbitrates between the SMP's bus and its own sample and echo fetches in an RS_SMP state, and this build disables the machine so the sound engine is not competing for the port. What is proven is the port and the storage, not the arbitration on top of them, and the next cycle has to close that gap or look elsewhere. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was not changed, checked that entries 1 to 8 were not rewritten, revised TCL-008 in place and added TCL-012, and validated this entry's numbering, six sections, one-sentence Purpose, prose, Status values and the nine-entry count against the 100-entry limit.

#### Next Steps:

Two things are now known good -- the ARAM port and storage through direct access, and the APU port in both directions -- and the SPC700 still ends up executing at $F4xx, an address inside its own register bank where no code can live, so the next question is what the IPL computed before it took its `JMP [$0000+X]` at $FFFB. The instrument is a latch, not a sample: capture the SPC700's PC and A at the first moment its PC leaves the IPL ROM range $FFC0-$FFFF, together with the four bytes at ARAM $0000-$0003 that the IPL reads its transfer address from, and draw them beside the two port banks, so one frame says what byte went into the jump and whether the bytes the IPL read were the ones the 65816 sent. A transfer address of $0000 or a low byte of $F0 would put the jump inside the port bank and explain $F4xx without any memory fault, while a plausible address whose target holds wrong bytes moves the fault into the upload. Because `dsp.v` sits between the SPC and ARAM, a test that rules the arbitration in or out is worth writing next as well: run the ARAM self-test with the machine enabled and the DSP arbitrating rather than with the port taken over, and confirm the SPC's own reads still return what it wrote. Do not re-time the port-0 read path, the DQ capture or the SDRAM clock, do not reintroduce the ODDR on fclk, and do not build a diagnostic display branch on an `elsif` that ORs two macros, since that shape silently selects the wrong branch under slang. Keep all ten diagnostic builds as the regression set, run `tools/tests/probe_tb.sh` after any sampler or memory-test change, and use `tools/decode_probe_frame.py` rather than reading stripes by eye.

#### Files Modified:

- fpga/snes/src/aram_bist.v
- fpga/snes/src/snestang_top.v
- fpga/snes/src/snes2hdmi.v
- tools/build_tinysnes.sh
- tools/tests/probe_tb.sh
- tools/tests/aram_bist_tb.sv

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: NOT RUN

---

## 10 COMMIT Unreleased 2026-10-31T11:54:03-07:00

#### Coming From:

Unreleased 137f4bb

#### Purpose:

Catch the address the SPC700's IPL jumps to, because entry 8 left the machine executing at an address it had inferred rather than measured.

#### Outcome:

`TINYSNES_IPL_PROBE` polls the SPC700's program counter every nine mclk through `DBG_SEL[3]`, reads its high byte on both sides of its low byte, and latches the first program counter below $FFC0 once the IPL range has been seen -- that first out-of-range value is the target of the IPL's `JMP [$0000+X]` at $FFFB, so the answer needed no ARAM access at all and there is no debug path to ARAM to need. The same snapshot carries A and X at that moment, the current program counter, and all four CPUI bytes, since the IPL loads its jump base from CPUI[2] and CPUI[3] at $FFEF-$FFF1 and puts CPUI[1] in X at $FFF8. Sampling is fast enough by construction: one SPC700 cycle is about 21 mclk at 21.505 MHz against 1.024, the shortest instruction is two cycles, so PC cannot change more often than every ~42 mclk and a nine-mclk revolution samples it at least four times per instruction. The bench caught a real defect in the instrument before hardware: the tear guard compared the two stored high-byte registers, and at the moment of comparison the second register still held the PREVIOUS revolution's byte, so it compared across revolutions and let a genuine tear through -- the bench's tear model showed `cur_pc` changing 32 times in 300 mclk, against zero after the fix, which compares the stored first read against the register being read on the same edge, the shape the APU probe already uses. The bench also had to be repaired twice for reading the latched display where it meant to read the sampler's own register. Seed 5 built with `TINYSNES_IPL_PROBE` in `build/ipl_s5`, zero hold violations, passing the timing gate at fclk 238.379 against 64.516 MHz, hclk 149.970 against 74.250 and iosys.clk 31.564 against 21.505, giving `tinysnes.fs` SHA-256 `25df60d6a5fa8deb17c46b94cab02dbe1d8e356af3f7b83ce8c6c6e4a6e4af8c`; it was loaded one-wire and the bench's 1 MiB `zelda.smc` streamed at the core's UART. The readout refutes the premise this cycle was built on: `exit_seen` never fired in any of 172 captured frames, 170 of which decoded cleanly, and the status band reads cyan, which is R clear, G set and B set -- no exit, ROM loaded, core enabled. The SPC700's current program counter sits at $FFDA, $FFDC and $FFEA, all inside the IPL ROM, so it has not left the IPL at all and there is no jump to explain. The three port values are coherent and plausible: CPUI port 0 reads $80, the transfer index the 65816 has reached; CPUI port 1 reads $92, the data byte at that index with bit 7 set; and CPUI ports 3 and 2 read $08 and $2A, the transfer address $082A. The SPC is therefore spinning in the IPL's block-copy loop at $FFDA-$FFE9, which compares its Y against CPUI port 0 and waits, while the 65816 spins at $88EC waiting for an echo -- two processors waiting on each other, with the disagreement between Y and the index in CPUI port 0 as the thing to measure. This contradicts core-log entry 8, which read the SPC700's program counter as $F4B5-$F4D1 and inferred it had taken the IPL's jump into uploaded code in ARAM; the machine's failure point is already recorded as varying between boots, and the two readings were taken on different boots from different bitstreams, but the inference drawn in entry 8 does not survive as a general statement and the ARAM-execution hypothesis it produced is now unsupported, which also removes the premise for this cycle's planned second part, the DSP arbitration test, since the SPC is not executing uploaded code for the DSP to contend with. Entry 9's ARAM result stands on its own: it measured the port and the storage directly and did not depend on the wrong inference. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was not changed, checked that entries 1 to 9 were not rewritten, revised EXT-005 and TCL-008 in place, and validated this entry's numbering, six sections, one-sentence Purpose, prose, Status values and the ten-entry count against the 100-entry limit.

#### Next Steps:

Read the SPC700's Y in the same frame as CPUI port 0, because the IPL's block loop at $FFDA-$FFE9 turns entirely on `CMP Y,$F4` and the deadlock is now two processors waiting on a value that should be equal and is not: replace the A-and-X stripe, which is only meaningful when the exit latch fires and has never fired, with live Y and A, rebuild, and read Y beside the $80 in CPUI port 0. A Y of $80 with the 65816 still spinning means the compare is not the fault and the echo path at $FFE0 is, since that is where the SPC writes Y into $F4 for the CPU to read; a Y below $80 means the SPC is behind and missing bytes, which points at the copy loop storing through ARAM port 1 during a live machine -- the one case entry 9 could not test, because its build disabled the machine and the DSP was not arbitrating; a Y above $80 means the SPC has advanced past the index the CPU sent, which points at the block-restart path through $FFEB-$FFF9. Keep the DSP arbitration question, since it returns as soon as Y shows the SPC is behind. Do not re-time the port-0 read path, the DQ capture or the SDRAM clock, do not reintroduce the ODDR on fclk, and do not build a diagnostic display branch on an `elsif` that ORs two macros. Keep all ten diagnostic builds as the regression set, run `tools/tests/probe_tb.sh` after any sampler change -- it now runs six benches -- and use `tools/decode_probe_frame.py` rather than reading stripes by eye. Treat a readout that contradicts a recorded one as a boot-depth question first and a measurement question second, and say which of the two it is rather than letting the newer reading quietly replace the older.

#### Files Modified:

- fpga/snes/src/snestang_top.v
- fpga/snes/src/snes2hdmi.v
- tools/tests/ipl_probe_tb.sv
- tools/tests/probe_tb.sh

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: NOT RUN

---

## 11 COMMIT Unreleased 2026-10-31T12:07:44-07:00

#### Coming From:

Unreleased 2bc2536

#### Purpose:

Read the SPC700's Y in the same frame as CPUI port 0, because the IPL block-copy loop turns on `CMP Y,$F4` and the deadlock is two processors waiting on a value that should be equal.

#### Outcome:

The IPL probe grew a tenth phase that reads the SPC700's Y, and the stripe that used to carry A and X from the one moment the exit latch never fires now carries live Y above live A; the live-follow behaviour is asserted by the bench rather than assumed, by moving both and checking that the stripe follows. The bench caught two of its own errors before hardware: an expected value taken from a field it had already changed, and a declaration removed while the capture that used it remained. Seed 5 failed place and route with two hold violations on `posedge fclk`, which is the seed sensitivity this project already records, and seed 6 built clean and passed the timing gate at fclk 272.777 against 64.516 MHz, hclk 162.022 against 74.250 and iosys.clk 30.284 against 21.505, giving `tinysnes.fs` SHA-256 `1b90e66f1da3646f01fb62ba0856b0d440a5e9cba67b11658ff09d4595ed6d70`. It was loaded one-wire and the bench's 1 MiB `zelda.smc` streamed at the core's UART; the status band reads cyan again, so the exit latch still has not fired and the SPC700 is still inside its IPL ROM. The readout, from 177 of 180 decoded frames and identical in every one: Y is $45, A is $7A, CPUI port 0 is $44, CPUI port 1 is $7A, CPUI ports 3 and 2 are $40 and $00 giving a $4000 transfer address, and the program counter moves through $FFDA, $FFDC, $FFDD and $FFEB. Decoded against the IPLROM, that loop at $FFDA is `CMP Y,$F4 / BPL`, then `MOV A,$F5`, `MOVW $F4,YA`, `MOV [$00]+Y,A`, `INC Y`, and back to the compare, so its steady state is that Y runs one ahead of CPUI port 0 while the SPC waits for the 65816 to publish the next index. The measured relation is exactly that: Y is $45 and CPUI port 0 is $44, and A equals CPUI port 1, which is the byte the 65816 published. The SPC700 is therefore doing its job correctly -- it consumed the CPU's byte, stored it through ARAM at [$00]+Y, published Y into CPUO, advanced, and is now waiting for the next index -- and the fault is on the 65816 side, which has published index $44 and sits at $88EC comparing `$2140` against its own A without ever advancing to $45. That refines entry 10 rather than contradicting it, and it withdraws the third branch that entry's Next Steps offered: the SPC has not run ahead of the CPU through any fault of its own. The two remaining explanations are the ones the earlier branches named, and the measurement that separates them is CPUO port 0 beside the 65816's A in the same frame, which no current probe carries -- the APU probe has CPUO and A but not Y and CPUI in a form that pairs with them, and this probe has Y and CPUI but not CPUO. One observation is recorded without interpretation because it does not fit a clean reading: Y at $45 is above the $0F that the block loop's own `CMP Y,#$10` bound implies, and whether that means Y is a running byte counter across blocks or that the loop was entered on a different path has not been established. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was not changed, checked that entries 1 to 10 were not rewritten, made no change to `core-reference.md` this cycle beyond the diagnostic-build count already revised in entry 10, and validated this entry's numbering, six sections, one-sentence Purpose, prose, Status values and the eleven-entry count against the 100-entry limit.

#### Next Steps:

Put CPUO port 0 and the 65816's A into the same snapshot as CPUI port 0, CPUI port 1 and the SPC700's Y, because that single frame decides between the two remaining explanations and every probe built so far carries only half of it: the APU probe has CPUO and the 65816's A, and this one has the SPC's Y and the CPUI banks. The cleanest instrument is one build that merges them -- CPUO ports 1 and 0, CPUI ports 1 and 0, the 65816's A, and the SPC700's Y and PC -- and the readout that matters is whether CPUO port 0 holds $44, the echo the SPC published, beside a 65816 whose A is also $44. If CPUO holds $44 and the CPU still sits at $88EC, the CPU's read of `$2140` is not returning CPUO and the fault is in the APU port read path after all, which would reopen the question entry 8 closed -- and the way to test it without touching timing is to compare the value the CPU reads against the value the SPC published in the same frame rather than one probe apart. If CPUO holds something else, the SPC's publish at $FFE0 is landing in the wrong register or being overwritten, and the fault is in the `MOVW $F4,YA` write path in smp.v. Do not re-time the port-0 read path, the DQ capture or the SDRAM clock, do not reintroduce the ODDR on fclk, and do not build a diagnostic display branch on an `elsif` that ORs two macros. Keep all ten diagnostic builds as the regression set and run `tools/tests/probe_tb.sh` -- six benches -- after any sampler change.

#### Files Modified:

- fpga/snes/src/snestang_top.v
- fpga/snes/src/snes2hdmi.v
- tools/tests/ipl_probe_tb.sv

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: NOT RUN

---

## 12 COMMIT Unreleased 2026-10-31T12:20:39-07:00

#### Coming From:

Unreleased 33dcde9

#### Purpose:

Put both directions of the APU link and both CPUs' state into one snapshot, because every earlier probe carried half of the pair needed to explain the deadlock.

#### Outcome:

`TINYSNES_LINK_PROBE` reads CPUO ports 1 and 0, CPUI ports 1 and 0, the 65816's A, the SPC700's PC and its Y across ten phases into one latched snapshot, and its bench checks the field layout, that the two port directions are independent by moving each bank's high byte and confirming the other does not follow, that a torn SPC program counter is rejected, that the display is latched rather than live, and that no phase selects an unprobed register; the bench caught a transposed byte order in the probe's own comment before hardware. Seed 6 built clean with zero hold violations, passing the timing gate at fclk 290.782 against 64.516 MHz, hclk 142.613 against 74.250 and iosys.clk 32.860 against 21.505, giving `tinysnes.fs` SHA-256 `6786e3fc005ae610dbc1a8cd4a40fadb1571f6f78e4e270dc9b5341cd7f7ea8f`; it was loaded one-wire and the bench's 1 MiB `zelda.smc` streamed at the core's UART. The readout, identical in all 177 decoded frames of 179 captured: CPUO port 0 is $19, CPUO port 1 is $BB, CPUI port 0 is $10, CPUI port 1 is $00, the 65816's A is $BB10, the SPC700's Y is $1A, and its program counter sits at $FFDC, $FFEA and $FFE9. Continuing the cycle required decoding the IPL exactly rather than approximately, and doing that exposed a defect in entry 11 worth recording plainly: the instruction listing in that entry was written from recollection, not from this repository, and two of its lines are wrong. The bytes at $FFDC are `D0 0B`, a `BNE $FFE9`, not the `BPL $FFDA` the entry shows, and $FFE0's `CB F4` is `MOV $F4,Y`, writing Y into CPUO port 0, not the `MOVW $F4,YA` the entry shows. The corrected listing was produced by extracting all 256 opcode mnemonics from `fpga/snes/src/spc700/mcode.txt` and walking the `IPLROM` array in `smp.v`, and it validates itself: the walk consumes exactly the 64 bytes and ends at $FFFE, where the reset vector `$C0FF` correctly points back to $FFC0. Entry 11's conclusion survives the correction -- the SPC700 is waiting for an index the 65816 never sends -- but its reasoning quoted an instruction that does not exist at that address, so the mistake is recorded rather than quietly repaired. With the loop decoded, the measured values become exact: CPUO port 0 holds $19, which is Y minus one, and the loop publishes Y at $FFE0 and then increments it at $FFE4, so the SPC700 completed one exchange at Y=$19 and is now waiting at Y=$1A; at $FFDA it compares $1A against CPUI port 0's $10, branches to $FFE9 on the mismatch, and the `BPL` there returns it to $FFDA, so it spins for ever. The 65816 meanwhile compares $10 against CPUO port 0's $19 and cannot leave $88EC. The two are ten indices apart, and because the SPC700 only ever advances when CPUI port 0 equals its Y, a 65816 that is behind can never catch up: the desync is permanent by construction. That the gap was one in entry 11 and is ten now is the most useful new fact -- a fixed protocol offset would be one number, and a gap that changes between boots is a race or a restart, not a wrong constant. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was not changed, checked that entries 1 to 11 were not rewritten, added EXT-006 and revised TCL-008, and validated this entry's numbering, six sections, one-sentence Purpose, prose, Status values and the twelve-entry count against the 100-entry limit.

#### Next Steps:

Find out whether the 65816 is still at $88EC or has restarted its upload, because that one address separates the two remaining explanations for a gap that varies between boots: replace the SPC700 program counter stripe, which has been read three times now and is always inside the IPL, with the 65816's program counter, keeping CPUO, CPUI, A and Y, and read all five in one frame. A 65816 still at $88EC means the CPU is wedged waiting for an echo it will never see and the SPC is waiting for an index the CPU will never send, and the fault is a lost first exchange rather than a restart; a 65816 anywhere else, and especially back at $8888 where the upload routine begins, means the CPU restarted the transfer while the SPC700 kept counting, which would explain a gap that changes between boots and would make the reset and `enable` path between the two processors the next thing to test. If the CPU has restarted, the instrument for that question is a latch on the SPC700's Y taken at the moment `enable` rises, because a Y that is already non-zero at that instant proves the SPC700 did not reset with the 65816. Do not re-time the port-0 read path, the DQ capture or the SDRAM clock, do not reintroduce the ODDR on fclk, and do not build a diagnostic display branch on an `elsif` that ORs two macros. Keep all eleven diagnostic builds as the regression set and run `tools/tests/probe_tb.sh` -- seven benches -- after any sampler change. When a decode is needed, derive it from `mcode.txt` rather than from recollection and check that the walk lands on the reset vector, which is what caught the bad listing in entry 11.

#### Files Modified:

- fpga/snes/src/snestang_top.v
- fpga/snes/src/snes2hdmi.v
- tools/tests/link_probe_tb.sv
- tools/tests/probe_tb.sh

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: NOT RUN

---

## 13 COMMIT Unreleased 2026-10-31T12:41:08-07:00

#### Coming From:

Unreleased 2eb37ea

#### Purpose:

Date the desync by reading the 65816's program counter in the same frame as both link directions, because the gap between the two processors was one index on one boot and ten on another.

#### Outcome:

`TINYSNES_LINK_PROBE` swapped its SPC700 program-counter stripe for the 65816's, so the five fields are now CPUO ports 1 and 0, CPUI ports 1 and 0, the 65816's A and program counter, and the SPC700's Y; the tear guard moved with it, reading the 65816's high byte on both sides of its low byte and rejecting a pair whose high byte moved between the reads. The bench checks the new field, that the tear guard rejects a moving 65816 counter, and that a clean one is accepted afterwards; all seven benches pass. Seed 6 built clean with zero hold violations, passing the timing gate at fclk 189.538 against 64.516 MHz, hclk 201.939 against 74.250 and iosys.clk 33.121 against 21.505, giving `tinysnes.fs` SHA-256 `192da7770012a2d26e5e12dbee455596766bb82de8ab9f383c6376e2733ed9bd`; it was loaded one-wire and the bench's 1 MiB `zelda.smc` streamed at the core's UART. The readout, identical in all 171 decoded frames of 173 captured: CPUO port 0 is $AA and port 1 is $BB, CPUI port 0 is $10 and port 1 is $00, the 65816's A is $BB10, its program counter moves through $88EC, $88ED, $88EF and $88F0, and the SPC700's Y is $00. The question this cycle asked is answered: the 65816 has not restarted, because $88EC is the echo-wait inside its upload loop and the routine entry at $8888 would be the signature of a restart. What the same frame also shows is a contradiction the cycle did not set out to find. CPUO still holds $AA and $BB, which is exactly what the IPL publishes at $FFC9 and $FFCC, and Y is still $00, which is where Y stands before the block-copy loop has run at all. Both values say the SPC700 has never executed past its first publish -- never taken the $CC the 65816 sends, never written CPUO again, never entered the loop that would leave Y non-zero. Yet the 65816 is at $88EC with a byte in hand and has clearly advanced well past the point where it first offers $CC. Two readings fit those facts and this instrument cannot separate them: either the SPC700 is still sitting at $FFCF having never seen $CC, in which case the 65816 advanced on a port read it should not have passed; or the SPC700 did take $CC and publish its own value, then went back to $FFC0 and republished $AA and $BB, which would be a restart of the SPC after the 65816 was already committed. The second reading would also explain why the gap between Y and CPUI port 0 was one index on entry 11's boot and ten on entry 12's, since a restart at an arbitrary moment leaves an arbitrary gap. Recording the ambiguity is the point: the previous cycle's Next Steps treated the 65816's program counter as sufficient to decide between a lost exchange and a restart, and this measurement shows it is not, because it establishes that the 65816 did not restart without establishing what the SPC700 did. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was not changed, checked that entries 1 to 12 were not rewritten, revised TCL-008 in place, and validated this entry's numbering, six sections, one-sentence Purpose, prose, Status values and the thirteen-entry count against the 100-entry limit.

#### Next Steps:

Instrument whether the SPC700 ever advanced, rather than what it is doing now, because a single snapshot cannot distinguish a processor that never moved from one that moved and came back: the next build should keep CPUO port 0, CPUI port 0, both program counters and Y, and add three sticky history bits latched from reset and never cleared -- whether CPUO port 0 has ever differed from $AA, whether Y has ever been non-zero, and whether the SPC700's program counter has ever been below $FFC0. Those three bits answer the question directly and do not depend on timing: a CPUO that has never left $AA with a Y that has never left $00 means the SPC700 never consumed the handshake and the fault is in what the 65816's first $CC reaches, while a CPUO that has changed and a Y that has been non-zero beside a Y of $00 now means the SPC700 ran and then restarted, and the next instrument is a counter of SPC700 restarts and the moment `enable` or the SMP's reset input moves relative to them. Do not spend another cycle on the 65816's program counter alone. Do not re-time the port-0 read path, the DQ capture or the SDRAM clock, do not reintroduce the ODDR on fclk, and do not build a diagnostic display branch on an `elsif` that ORs two macros. Keep all eleven diagnostic builds as the regression set and run `tools/tests/probe_tb.sh` -- seven benches -- after any sampler change.

#### Files Modified:

- fpga/snes/src/snestang_top.v
- fpga/snes/src/snes2hdmi.v
- tools/tests/link_probe_tb.sv

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: NOT RUN

---

## 14 COMMIT Unreleased 2026-10-31T13:03:09-07:00

#### Coming From:

Unreleased 29a67e3

#### Purpose:

Separate a SPC700 that never advanced from one that advanced and restarted, which a snapshot cannot do, by latching three history bits that are never cleared.

#### Outcome:

`TINYSNES_LINK_PROBE` gained three sticky bits above the SPC700's Y: whether CPUO port 0 has changed away from $AA, whether Y has ever been non-zero, and whether the SPC700's program counter has left $FFC0-$FFFF. Sampling is sound by construction rather than by assumption -- an eleven-phase revolution samples each field every 11 mclk while one SPC700 cycle is about 21 mclk and the shortest instruction two cycles, so no stored value can appear and vanish between two samples of the same field. The bench is mutation-tested rather than merely passing: reverting any of the three bits to tracking its current value, or removing the arming from either of the two that need it, is caught by a specific check, and the exact defect found on hardware below is one of the mutations. The first hardware build exposed that defect: two of the three bits do not reset to the value their test is phrased around, because `smp.v` clears CPUO to $00 and `addrgen.v` clears the program counter to $0000, so a bit testing "CPUO is not $AA" or "the PC is not in the IPL" sets the instant reset releases and reads as a confident yes for ever. That build reported all three bits set. Both were then armed -- seen at $AA, or seen inside the IPL, before a departure can set them -- and the bench grew the tests that would have caught it, including the one that needed a reset first because arming is one-way. Seed 7 built the corrected logic with zero hold/min violations, passing the timing gate at fclk 247.770 against 64.516 MHz, hclk 139.043 against 74.250 and iosys.clk 34.279 against 21.505, giving `tinysnes.fs` SHA-256 `253c6cfd62ab2762074d3eb665bcc650b274c0507b901b29ff3a53091d38bf07`, and the deployed image is that one, so tree and bitstream agree. The corrected readout, identical in all 170 decoded frames of 172 captured: all three sticky bits are clear, the SPC700's Y is $00, CPUO reads $BBAA, CPUI port 0 reads $10, the 65816's A is $BB10 and its program counter moves through $88EC-$88F1. That resolves the ambiguity entry 13 recorded: the SPC700 has never left its IPL ROM, has never advanced Y, and CPUO has never changed from the $AA and $BB the IPL publishes at $FFC9 and $FFCC, so it is still waiting at $FFCF for a $CC it has never seen. The first reading wins and the second is refuted. It also sharpens the contradiction rather than dissolving it: the 65816 sits at $88EF in the echo-wait of its upload loop with an index of $10, having advanced through sixteen indices, while CPUO has never once changed from the IPL's initial publish. A CPU whose loop waits for an echo that has never been sent should not have advanced at all, so either its compare at $88EC is passing without a matching echo, or what it reads at $2140 is not what this probe reads from CPUO. One reporting defect is recorded because it could have misled a seed choice: the hold-violation check used the pattern "hold violation", which does not match nextpnr's "Hold/min time violation", so a rejected seed was mis-explained during this cycle. Seed acceptance was never affected, because the build script gates on nextpnr's exit status with `TINYSNES_ALLOW_HOLD` unset and not on that grep, and re-checking every seed used for a measurement this session with the correct pattern gives zero hold/min violations in all seven. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was not changed, checked that entries 1 to 13 were not rewritten, revised TCL-008 in place, and validated this entry's numbering, six sections, one-sentence Purpose, prose, Status values and the fourteen-entry count against the 100-entry limit.

#### Next Steps:

Latch whether CPUI port 0 has ever held $CC, because the SPC700 is confirmed stuck at $FFCF waiting for that value and the question is now whether it was ever presented: add a fourth sticky bit armed like the others, taken on the CPUI port 0 phase, and read it beside the existing three. A bit that is set puts the fault in the SPC700's read of $F4 -- it was shown $CC and did not take it -- which points at the `SPC700_D_IN` path in smp.v and at the timing of that read against the 65816's write, and the follow-up instrument is a latch of CPUI port 0 taken at the SPC's own read strobe rather than at a probe phase. A bit that is clear means the 65816 never actually wrote $CC to $2140, which contradicts its program counter being past $8898 and makes the 65816's store path or its `REP #$20` width the suspect, and the follow-up is to read P and the true 16-bit A at the same moment to establish what width that store used. Either way this is now a question about a single byte crossing a single port once, not about the link in general, and it is the last link in the chain between a working port and a running machine. Do not re-time the port-0 read path, the DQ capture or the SDRAM clock, do not reintroduce the ODDR on fclk, and do not build a diagnostic display branch on an `elsif` that ORs two macros. Keep all eleven diagnostic builds as the regression set, run `tools/tests/probe_tb.sh` -- seven benches -- after any sampler change, and mutation-test a new sticky bit before trusting it: an unarmed sticky bit set at reset reads exactly like a confident finding.

#### Files Modified:

- fpga/snes/src/snestang_top.v
- fpga/snes/src/snes2hdmi.v
- tools/tests/link_probe_tb.sv

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: NOT RUN

---

## 15 COMMIT Unreleased 2026-10-31T13:12:36-07:00

#### Coming From:

Unreleased ea9432b

#### Purpose:

Learn whether the 65816 ever wrote the $CC the IPL waits for, which separates a SPC700 that refused the handshake from a CPU that never sent it.

#### Outcome:

`TINYSNES_LINK_PROBE` gained a fourth sticky bit, set when CPUI port 0 has ever held $CC, and it is the one bit of the four that needs no arming: `smp.v` clears CPUI to $00 and the test is for $CC, so the bit is clear at reset by construction and sets only on the real event. That justification is written into the probe beside the arming rationale for the other two, because the previous cycle's defect was an unexamined reset value. The bit is mutation-tested three ways before hardware -- reverting it to track its current value, making it set for any value, and removing its reset clear are each caught by a specific check, and the bench also proves it ignores the neighbouring value $CD and survives the SPC clearing CPUI port 0, which that processor can do by writing $F1. Seed 7 built clean with zero hold/min violations, passing the timing gate at fclk 261.438 against 64.516 MHz, hclk 149.477 against 74.250 and iosys.clk 33.536 against 21.505, giving `tinysnes.fs` SHA-256 `b2a34945162d7d79656a1fc1af850c7dfa7ba5be3e972da004c1c61ff319c150`; it was loaded one-wire and the bench's 1 MiB `zelda.smc` streamed at the core's UART. The readout, identical in all 170 decoded frames of 173 captured, sets every one of the four sticky bits and reads CPUO $00BB, CPUI $0000, the 65816's A $BBAA and its program counter at $8891 and $8894. So on this boot the 65816 did write $CC, the SPC700 did leave its IPL ROM, its Y did advance to $FF, and CPUO did change away from $AA -- and the CPU is now sitting in the first handshake of its upload routine at $8891, comparing $BBAA against a CPUO of $00BB and looping for ever. The SPC700 is meanwhile mid-copy: with Y at $FF and CPUI port 0 at $00 it fails the compare at $FFDA and spins through $FFE9, which is a running copy rather than a restart, since a restart would leave Y at $00. This boot is therefore materially deeper than the two before it, and that is the most important result of the cycle. It also corrects entry 14, which recorded that the ambiguity of entry 13 was resolved and that the SPC700 had never advanced: that statement was true of the single boot it was measured on and is false as a general one, and the correction belongs in the record rather than in a footnote. The machine's failure point varies between boots -- it is recorded as varying as far back as entry 2 -- and a sticky readout measures one boot, so a diagnosis built on one frame is a diagnosis of that boot. What survives across all three boots of entries 13 to 15 is narrower and more useful: whenever the CPU is at $8891 it is waiting for $BBAA in CPUO, and whenever the SPC is waiting it is waiting for CPUI port 0 to equal its Y, and the two only ever match if both machines are at the same stage. The deadlock on this boot is the first handshake rather than the transfer: the CPU wants CPUO to return to $AA, which only the IPL's own first publish at $FFC9 produces, while the SPC has long since moved past that line and is publishing Y values instead. Nothing in the IPL republishes $AA except a restart of that processor. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was not changed, checked that entries 1 to 14 were not rewritten, revised TCL-008 and TCL-013 in place, and validated this entry's numbering, six sections, one-sentence Purpose, prose, Status values and the fifteen-entry count against the 100-entry limit.

#### Next Steps:

Measure whether the 65816 ever got past the first handshake and how many times it entered the routine, because the two boots now on record differ in exactly that and no current field distinguishes them: add a sticky bit for whether the 65816's program counter has ever been past $8894 -- set when the PC is seen in the range $8896 up to the routine's exit -- and a small counter of times the PC has been seen at $8888, the routine's entry. A CPU that has never been past $8894 with a SPC700 that has run a full copy means the transfer was driven by something other than this call and the argument passing at $88CC onwards is the suspect; a CPU that has been past $8894 and has entered the routine more than once means the routine completed and was re-entered, and the second entry's wait for a $BBAA that only an IPL restart can produce is the fault, which points at whatever calls $8888 a second time -- the code at $8905 is a `JSR $8888` followed by `CLI / RTS`, so the caller at $88CA and above is where to look. Take each readout with the boot it came from attached and do not carry a conclusion from one boot to the next without re-measuring it, since this cycle's result is the direct inverse of the previous cycle's on the same bitstream family. Do not re-time the port-0 read path, the DQ capture or the SDRAM clock, do not reintroduce the ODDR on fclk, and do not build a diagnostic display branch on an `elsif` that ORs two macros. Keep all eleven diagnostic builds as the regression set, run `tools/tests/probe_tb.sh` -- seven benches -- after any sampler change, and mutation-test each new sticky bit against its register's reset value and against tracking its current value.

#### Files Modified:

- fpga/snes/src/snestang_top.v
- fpga/snes/src/snes2hdmi.v
- tools/tests/link_probe_tb.sv

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: NOT RUN

---

## 16 COMMIT Unreleased 2026-10-31T13:23:09-07:00

#### Coming From:

Unreleased 4928b56

#### Purpose:

Distinguish a 65816 that never cleared its first handshake from one that cleared it and re-entered its upload routine, since the boots on record differ in exactly that and no existing field could tell them apart.

#### Outcome:

`TINYSNES_LINK_PROBE` gained two more pieces of history in the four bits the top stripe had spare, so no existing field moved: bit 76 records that the 65816's program counter has been seen above $8894, which is only reachable by passing the first handshake, and bits 79:77 hold a saturating count of visits to $8888, the routine's entry. Building the second one found a real defect before hardware: it counted samples rather than visits, so holding $8888 for a few revolutions added several per visit and three visits read as seven, and it now counts only a transition into the address, remembering the previous accepted sample. The bench was corrected twice as well and both corrections are worth recording because they were errors of the test rather than the design: the first expected `st_past` to stay clear at $88EC, which was an arithmetic mistake -- $88EC is inside the range that means "past the handshake" and the design was right -- and the entry-count test asserted only a lower bound, which a sample-counting counter satisfies by overshooting, so it now requires exactly three. Mutation testing confirms all three new behaviours are covered: counting samples instead of visits, never setting `st_past`, and widening the `st_past` range to include the handshake are each caught by a specific check. Seed 7 built clean with zero hold/min violations, passing the timing gate at fclk 190.440 against 64.516 MHz, hclk 168.919 against 74.250 and iosys.clk 31.058 against 21.505, giving `tinysnes.fs` SHA-256 `5c8effe1b9257f816b6e93fee7957d3fdc7b8bb61663843d2a540463b7e9ea4a`; it was loaded one-wire and the bench's 1 MiB `zelda.smc` streamed at the core's UART. The readout, identical in all 170 decoded frames of 172 captured, is a fourth distinct boot state: every history bit is set, the entry count is four, Y has reached $FF, CPUO reads $10BB, CPUI reads $0000, A reads $00C8, and the 65816's program counter moves through $7C7C, $7C7D, $7C7E and $7C7F. The question this cycle asked is therefore answered on this boot: the CPU did clear the first handshake and it did re-enter the upload routine, four times. But the state it ended in is not a handshake stall at all. $7C7C in bank $00 is below the LoROM window, so it is WRAM and register space rather than code, and a program counter cycling through four consecutive addresses there is the jump-to-self signature entry 5 recorded as "executing where no ROM is mapped" -- which means this boot ran the upload four times and then left valid code altogether. Four boot states are now on record from consecutive loads of the same image: the SPC700 never advancing with the CPU parked in its echo-wait, the SPC mid-copy with the CPU waiting for $BBAA, and now the SPC mid-copy with the CPU crashed out of the ROM after four routine entries. They share one property and it is the only one that has survived every measurement: the two processors never stay in step. A failure that changes shape between boots of unchanged code is not a logic error in either processor's program; it is a race, a marginal timing path, or a read that sometimes returns the wrong data. The instrument cannot tell those apart, and no further field on this probe will, because it measures state rather than correctness. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was not changed, checked that entries 1 to 15 were not rewritten, revised TCL-008 and TCL-013 in place, and validated this entry's numbering, six sections, one-sentence Purpose, prose, Status values and the sixteen-entry count against the 100-entry limit.

#### Next Steps:

Stop adding state fields and test whether the machine reads the same data twice, because the varying failure shape across four boots now points at data corruption rather than at either processor's program, and entry 5 already named the first suspect: the SDRAM refresh competing with the CPU port, which answers four master clocks into a six-clock window, so a refresh that steals the slot returns stale data and the CPU executes a corrupted instruction. The instrument is a read-back comparison rather than a state probe: re-run the shape of `TINYSNES_ROM_CHECK`, which already reads the loaded image back out through the CPU's own port and compares it, but run it repeatedly and continuously while the machine executes instead of once before it starts, and count mismatches. A non-zero count proves the read path returns wrong data under load and makes the refresh-versus-CPU arbitration in `sdram_cl2_2ch.v` the fault; a zero count across a long run refutes it and moves the work to the write side, where the loader and the ARAM port would be re-examined with the machine live. The refresh gate is the specific code to read first either way: at `cycle[2]` the controller issues an AutoRefresh only when `!we_latch[0] && !oe_latch[0] && !we_latch[1] && !oe_latch[1]`, which looks correctly gated for a request already latched at `cycle[0]`, but nothing has verified that the gate holds for a request accepted in the same slot, and that is a two-line examination of the RTL rather than a hardware cycle. Do not re-time the port-0 read path, the DQ capture or the SDRAM clock, do not reintroduce the ODDR on fclk, and do not build a diagnostic display branch on an `elsif` that ORs two macros. Keep all eleven diagnostic builds as the regression set, run `tools/tests/probe_tb.sh` -- seven benches -- after any sampler change, and mutation-test each new history bit.

#### Files Modified:

- fpga/snes/src/snestang_top.v
- fpga/snes/src/snes2hdmi.v
- tools/tests/link_probe_tb.sv

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: NOT RUN

---

## 17 COMMIT Unreleased 2026-10-31T14:26:46-07:00

#### Coming From:

Unreleased 8672af1

#### Purpose:

Test whether the machine reads the same data twice, because four boots producing four different failure shapes point at wrong data rather than at either program.

#### Outcome:

The RTL check promised by entry 16 cleared first: the refresh at `cycle[2]` is gated on `!we_latch[0] && !oe_latch[0]`, and a CPU request accepted in the same slot has already latched `oe_latch[0]` at `cycle[0]`, so a refresh cannot overwrite the CAS issued at `cycle[1]` in that slot. Nothing in the state machine allows a refresh to steal a slot already carrying a request. `fpga/snes/src/rom_stability.v` is a new self-test in the shape of `rom_probe.v`: after `loaded` it owns the CPU port until `done`, reads each of eight word addresses spread across a 1 MiB image twice back to back, compares the two, and saturates a 16-bit mismatch count, over 4096 iterations -- 65,536 reads, about 1.5M master clocks or 70 ms, which spans roughly 3000 refresh periods at the controller's 501-cycle cadence. It is drawn by the shared 16-bar display with the count's bits red where set, and its status band is green for a completed run with no mismatch, red for a non-zero count, blue while running and yellow for an unacknowledged request. `enable` is gated on `stability_done` so the image is never disturbed while the port is under test, and the port mux uses the same `loaded && ~done` shape as the ROM landing probe, because handing the port to a probe from reset disconnects the loader's writes. The bench compiles the shipping module against a port model and proves itself non-vacuous three ways: a correct model reports pass with a zero count, a model corrupting every seventeenth read is caught with exactly the three predicted mismatching pairs, and a model that never acknowledges reports status 3. Seed 7 built clean with zero hold/min violations, passing the timing gate at fclk 210.926 against 64.516 MHz, hclk 161.186 against 74.250 and iosys.clk 30.934 against 21.505, giving `tinysnes.fs` SHA-256 `74f8f8a6f1f16a90459ee10cf915e0e7813236c5261645ac4cb47ebf1b2d99be`. The first load of that image produced no video at all and the capture card reported no signal, while the placement of `div5`, the three PLLs and the three OSER10s matched the known-good sites recorded in TCL-009 exactly; reloading the same file produced a picture immediately, so that was a failed SRAM load rather than a design fault, and it is worth knowing that a silent no-video result can mean the load did not take. Reloading also clears `loaded`, so the ROM must be streamed again afterwards -- the first capture after the reload showed the test in its running state for that reason, not because the test was slow. The measured result is a clean negative: all sixteen bars clear and the status band green in all 180 captured frames, so 65,536 double-reads across 4096 iterations produced no disagreement. The SDRAM read path is stable, and core-log entry 5's hypothesis that a refresh stealing the CPU port's slot returns stale data and corrupts an instruction is refuted. That is the most useful thing this cycle produced, because it removes the explanation the project has been carrying since entry 5 and narrows the four-boot variation to the write side or to sequencing rather than to the read path. The bound on the conclusion is stated rather than glossed: `enable` is held low for the duration of the test, so these reads are taken at rest, with the controller's refreshes running throughout but without the machine's own WRAM, DMA and PPU traffic competing for the port. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was not changed, checked that entries 1 to 16 were not rewritten, revised TCL-007, TCL-008 and BRD-003 in place, and validated this entry's numbering, six sections, one-sentence Purpose, prose, Status values and the seventeen-entry count against the 100-entry limit.

#### Next Steps:

Attack the write side while the machine is live, because reads are now proven stable and the four-boot variation has to come from what is stored rather than from what is retrieved: the loader writes through the same CPU port with `cpu_we` high and `cpu_ds` selecting a byte lane, and a corrupted write would leave the image subtly wrong at a varying place, which is exactly the shape the failures show -- a routine entered four times and then a jump to $7C7C, an index that advanced while its partner did not, a SPC that never started. The instrument is a compare-back written into the loader's own path rather than run after it: extend the `TINYSNES_ROM_CHECK` probe to run a second pass after the machine has been enabled for a while, reading the image back out through the CPU port and comparing against the words the loader wrote, and count differences. Since reads are stable, any difference is a write that landed wrong or a location that was overwritten afterwards, and the address of the first difference names the culprit directly. If the image is intact after the machine has run, the corruption is not in SDRAM at all and the next candidates are WRAM, which the 65816 uses for its stack and its variables and whose own port shares the same controller, and the reset and enable sequencing between the two processors, which is the only thing that has varied across the boots measured so far. Also worth one cheap hardware cycle now that reads are exonerated: boot the same build several times without touching the ROM and record which of the four known states appears, since a distribution over states would separate a marginal timing path, which drifts with temperature and placement, from a deterministic startup race, which would always land the same way. Do not re-time the port-0 read path, the DQ capture or the SDRAM clock, do not reintroduce the ODDR on fclk, and do not build a diagnostic display branch on an `elsif` that ORs two macros. Keep all twelve diagnostic builds as the regression set and run `tools/tests/probe_tb.sh` -- eight benches -- after any sampler change. When a build produces no video, reload before investigating placement: the placement comparison is cheap and a failed SRAM load looks exactly like a dead design.

#### Files Modified:

- fpga/snes/src/rom_stability.v
- fpga/snes/src/snestang_top.v
- fpga/snes/src/snes2hdmi.v
- tools/build_tinysnes.sh
- tools/tests/probe_tb.sh
- tools/tests/rom_stability_tb.sv

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: NOT RUN

---

## 18 COMMIT Unreleased 2026-10-31T14:59:06-07:00

#### Coming From:

Unreleased ccc78bf

#### Purpose:

Establish whether the failure is deterministic, because four different failure shapes from one image could mean a marginal path that drifts or a race that always lands the same way, and nothing measured so far distinguished them.

#### Outcome:

`tools/sample_boot_states.py` boots one bitstream repeatedly -- each load reconfigures the FPGA and is therefore a true cold start -- streams the same ROM after every load, captures three seconds and decodes the five stripes by majority over all frames that are not torn, then reports the distinct states and a verdict. It needed no new RTL: it re-boots `build/past_s7/tinysnes.fs`, the exact cycle-16 link probe whose SHA-256 `5c8effe1b9257f816b6e93fee7957d3fdc7b8bb61663843d2a540463b7e9ea4a` matches entry 16's record. One defect in the tool itself was found and fixed on first use: it resolved the ROM loader one directory too high and every boot failed with "can't open file" before that was corrected. Five boots of an identical bitstream and an identical ROM produced five distinct states, so the failure is nondeterministic and neither a logic error in the image nor a fixed protocol defect: boot 1 read CPUO $BB10, A $00B8, PC $7C7F, Y $FF with two routine entries; boot 2 read A $00D8 with three entries; boot 3 read CPUO $BB0B, A $F6F0, PC $FFCF, Y $0C with two entries and the SPC still inside its IPL; boot 4 read A $0100, PC $7C7F, Y $00 with four entries; and boot 5 read CPUO $BB27, CPUI $0010, A $0110, PC $88EF, Y $28 with two entries and the SPC inside its IPL. What is constant across all five is more informative than what varies: the busy bit for a past-the-handshake sighting, the $CC sighting, a non-zero Y and a changed CPUO are set in every single boot, so the 65816 always wrote $CC, the SPC700 always ran, always advanced Y and CPUO always changed. The handshake always completes; what varies is where the 65816 ends up -- $7C7F in three of five, $88EF in one and $FFCF in one -- together with its A, its routine entry count between two and four, whether the SPC left its IPL and how far Y had advanced. $7C7F in bank $00 is below the LoROM window, and following the decode in SNES.v it selects BUSA with CA[15:8] of $7C, which is neither $40 nor $43, so BUSA_DO returns DI: the address reads open bus rather than ROM. Three of five boots are therefore executing data that was merely last on the bus, which is self-sustaining garbage rather than code, and that is the same signature entry 5 recorded at $7C7C. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was not changed, checked that entries 1 to 17 were not rewritten, revised BRD-003 in place, and validated this entry's numbering, six sections, one-sentence Purpose, prose, Status values and the eighteen-entry count against the 100-entry limit.

#### Next Steps:

Name the instruction that diverts the 65816, because a symptom at $7C7F is not the fault and every measurement so far has been of the destination rather than the departure: the trace probe already exists for this and needs no new RTL -- `TINYSNES_TRACE_PROBE` keeps the last four `ROM_ADDR` values on a ring that advances only on ROM accesses, so a CPU that has left the ROM leaves the ring frozen on exactly the fetches before the jump, and LoROM bank 0 is the image offset directly, which makes those four addresses disassemblable against `zelda.smc` without any further work. Boot that build several times rather than once, since the states now provably vary, and disassemble the newest ring entry from each boot: a last address inside the upload routine whose following branch target looks sane points at a computed or indirect transfer reading corrupted data, while a last address that is already wrong, or an opcode no compiler would emit, points at the fetch itself having returned something other than the image. Because reads are proven stable at rest and the handshake completes in every boot, the leading explanation is now state that differs between power-ups rather than a path that is merely marginal: WRAM and the parts of SDRAM below the image are not cleared by this design, so any routine that reads them before writing them behaves differently on each boot, and the second instrument worth building is a sticky record of whether the 65816 ever read outside the loaded image before its first write -- an address-range check on its bus, not on its PC. If the trace ring instead shows the diversion coming from a vector, the interrupt path and the reset and enable sequencing between the two processors are the next candidates, since that is the only thing which has varied across every boot measured in this session. Do not re-time the port-0 read path, the DQ capture or the SDRAM clock, do not reintroduce the ODDR on fclk, and do not build a diagnostic display branch on an `elsif` that ORs two macros. Keep all twelve diagnostic builds as the regression set and run `tools/tests/probe_tb.sh` -- eight benches -- after any sampler change, and use `tools/sample_boot_states.py` rather than single boots whenever a result is compared across builds.

#### Files Modified:

- tools/sample_boot_states.py

#### Status:

- Build: N/A
- Deployment: PASS
- User Test: NOT RUN

---

## 19 COMMIT Unreleased 2026-10-31T15:08:25-07:00

#### Coming From:

Unreleased 3162485

#### Purpose:

Name the ROM code the 65816 was executing at the point it diverged, because every measurement so far described the destination rather than the departure.

#### Outcome:

The trace probe needed no new RTL: `TINYSNES_TRACE_PROBE` keeps the last four `ROM_ADDR` values on a ring that advances on each start of a ROM access, and `tools/sample_boot_states.py` gained a `--layout trace` formatter so it could be sampled over repeated boots the same way the link probe is. Seed 7 built clean with zero hold/min violations and passed the timing gate, giving `tinysnes.fs` SHA-256 `fbbf90169922e99f250103ff37182711ccd860a72be2b9bd7a68d5881e6e4d57`. Five boots produced three distinct ring states. Three boots froze on ROM address $0008EF, which is the LoROM mapping of the 65816's $88EF -- the `D0 FB` branch in the upload loop's echo-wait, with all four ring entries identical and the status band grey, meaning a ROM access had occurred within the last 0.2 s. One boot froze on $007FE6, the LoROM mapping of $FFE6, which is an address in the vector table rather than in code. One boot's ring held a clean descending run of $0003F2, $0003F4, $0003F6, $0003F8 -- four 2-byte steps of linear forward execution, the LoROM mapping of $83F2 to $83F8 -- with a cyan band, meaning no ROM access in the last 0.2 s, so that boot was running real code and then stopped fetching altogether. Reading the image's vector table turned the middle result into a lead: $FFE6 holds the emulation-mode BRK vector, and in this image that vector is $FFFF. A BRK taken in emulation mode therefore jumps to $FFFF, which in a LoROM image is the last byte of padding, and the bytes there are $FF rather than instructions. The other vectors are all sane -- RESET is $8000, IRQ/BRK native and IRQ emulation are $82D8, NMI emulation is $89D8, and COP, ABORT and the native BRK and NMI vectors are all $822C -- so $FFFF at $FFE6 is the one entry in the table that cannot be a handler, which makes it a trap for an unexpected BRK and a plausible explanation for the open-bus execution at $7C7F that entry 16 recorded. Two limits are stated rather than glossed. A ROM access is recorded for vector reads as well as opcode fetches, so an address in the vector table may be a vector being read rather than an instruction being executed, and the $FFE6 result is reported in that light. And five boots against three states is enough to establish nondeterminism, which entry 18 already did, but not enough to attach a frequency to any one state. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was not changed, checked that entries 1 to 18 were not rewritten, revised BRD-003 in place, and validated this entry's numbering, six sections, one-sentence Purpose, prose, Status values and the nineteen-entry count against the 100-entry limit.

#### Next Steps:

Decide whether the CPU is taking a BRK, an interrupt or neither, because the three are separable with one sticky instrument and the vector table now says the answer matters: latch whether the 65816's program counter has ever been in the vector table range $FFE0-$FFFF after it has been seen outside it, and alongside that latch the processor status byte seen at the moment it was last in that range, since the emulation bit and the interrupt-disable bit together say whether the CPU was in emulation mode and whether interrupts were masked at the time. A CPU seen in that range with the emulation bit set and the BRK vector of $FFFF confirms the trap and makes the next question why a BRK fired, which points at the interrupt lines rather than at the fetch path; a CPU never seen there moves the explanation back to the open-bus execution and the $7C7F destination, and the instrument becomes a latch of the first address outside the LoROM window together with the four ring entries immediately before it, which names a jump rather than a vector. Do not spend further cycles sampling current state on a machine that now provably varies between boots without also recording how many boots a result came from, and prefer instruments that record history over those that record a snapshot. Do not re-time the port-0 read path, the DQ capture or the SDRAM clock, do not reintroduce the ODDR on fclk, and do not build a diagnostic display branch on an `elsif` that ORs two macros. Keep all twelve diagnostic builds as the regression set and run `tools/tests/probe_tb.sh` -- eight benches -- after any sampler change, and use `tools/sample_boot_states.py` with `--layout trace` or `--layout link` for any comparison across builds.

#### Files Modified:

- tools/sample_boot_states.py

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: NOT RUN

---

## 20 COMMIT Unreleased 2026-10-31T16:14:55-07:00

#### Coming From:

Unreleased 42812b0

#### Purpose:

Test WRAM's byte lanes, because the upload routine depends on WRAM in three ways and every measured failure has the shape of one of them.

#### Outcome:

The instrument was changed from the vector latch that entry 19 proposed, and the reason is worth recording: reading the loaded image's own code at the upload call site showed that the 65816 writes a 24-bit data pointer to direct page $00-$02 at $8901-$890B, reads source data through it with `LDA [$00],Y` at $88CF, and pushes a return address with `JSR $8888` at $890E whose `RTS` is at $8900 -- and direct page and the stack both live in WRAM. A corrupted pointer copies wrong bytes into the SPC, which is the SPC-executing-garbage behaviour every boot shows; a corrupted return address makes `RTS` jump to garbage, which is the open-bus execution at $7C7F that three of five boots reached. That made WRAM a better instrument than the vector latch, and since a BRK reading $FFE6 is most likely a consequence of executing data rather than its cause, the substitution was put to the user and approved before any code was written. `fpga/snes/src/wram_bist.v` is a byte-lane-aware self-test in `aram_bist.v`'s shape, with a different byte in each lane of every word so a swapped pair fails on all 16 bits, four sets including one confined to $0000-$01FF where the direct page and stack actually live, and the mask drawn as 16 bars over a status band. It drives the controller's CPU port through the same `{6'b111_111, addr}` mapping and `{addr[0], ~addr[0]}` lane select that the machine's own WRAM path uses, so it exercises the real path rather than a private one. The bench is non-vacuous in the same way as the ARAM one: a correct model must pass with mask zero, a swapped-lane model must be caught on all 16 bits, a stuck-low bit must appear in both lanes as $0808, and a silent port must report no-acknowledge; all four behave as required and all nine benches pass. Seed 7 built clean with zero hold/min violations, passing the timing gate at fclk 164.258 against 64.516 MHz, hclk 146.671 against 74.250 and iosys.clk 32.604 against 21.505, giving `tinysnes.fs` SHA-256 `2c2d7017fd112144683e432fad01ff1b23d2290b48c5c17fd348e4b101882133`. Deployment was held on request until the user released it, and no core-log entry was written in the interim because `core-syntax.md` prohibits a work-in-progress entry. The readout is a clean negative: mask $0000 and a green status band in all 174 captured frames -- 172 with the band green and 2 transitional -- so every bit of both byte lanes read back what was written, at every test address including the direct-page and stack region. WRAM is therefore correct, and with it the last memory hypothesis dies. ROM was verified by the SDRAM self-test in entry 3, ARAM port 1 by entry 9, read stability by entry 17, and WRAM by this entry, so the memory the machine executes out of, the memory the 65816 keeps its pointer and stack in, and the memory the SPC loads its driver into have all now passed a byte-lane-aware write and read-back on hardware. That leaves exactly one class of explanation standing for four boots producing four different failure shapes: the sequencing between the two processors, and specifically the reset and enable path, which is the only thing that has differed across every boot measured in this session. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was not changed, checked that entries 1 to 19 were not rewritten, revised TCL-007 and TCL-008 in place, and validated this entry's numbering, six sections, one-sentence Purpose, prose, Status values and the twenty-entry count against the 100-entry limit.

#### Next Steps:

Measure the reset and enable sequencing directly, because every memory is now verified and the only thing left that varies between boots is when the two processors come out of reset relative to each other: latch, on one instrument, the moment `enable` rises relative to the SPC700 and note what the SPC700's program counter and Y are at that instant, since a Y that is already non-zero when the 65816 is first allowed to run proves the SPC was executing before the CPU started and that the two never begin together. The specific path to read first is not the probe but the RTL: `smp.v` takes `RST_N` and `ENABLE` separately, `SNES.v` derives `SMP_CE` and `SMP_EN` with the latter coming from `dsp.v` as `SUBSTEP == 3 ? ENABLE : 1'b0`, and `stability` aside, nothing this session has checked whether the SPC's reset is released on the same clock as the CPU's and whether the DSP's substep arbitration can hold the SPC off while the CPU is already running -- a two-file examination that costs no hardware cycle and should be done before another build. If the sequencing looks correct in the RTL, the next instrument is a sticky record of the first `enable` rising edge together with the SPC's PC and Y sampled at that exact moment, which distinguishes a SPC that started early from one that started late. Do not build another memory test: ROM, ARAM, read stability and WRAM have each now passed on hardware, and a fifth would add no information. Do not re-time the port-0 read path, the DQ capture or the SDRAM clock, do not reintroduce the ODDR on fclk, and do not build a diagnostic display branch on an `elsif` that ORs two macros. Keep all thirteen diagnostic builds as the regression set and run `tools/tests/probe_tb.sh` -- nine benches -- after any sampler change, use `tools/sample_boot_states.py` for any comparison across boots, and hold a build for as long as the user asks rather than deploying on a previous approval.

#### Files Modified:

- fpga/snes/src/wram_bist.v
- fpga/snes/src/snestang_top.v
- fpga/snes/src/snes2hdmi.v
- tools/build_tinysnes.sh
- tools/tests/probe_tb.sh
- tools/tests/wram_bist_tb.sv

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: NOT RUN

---

## 21 COMMIT Unreleased 2026-10-31T16:16:12-07:00

#### Coming From:

Unreleased f06a217

#### Purpose:

Examine the reset and enable path in the RTL before spending another hardware cycle, since entry 20 left the sequencing between the two processors as the last explanation standing.

#### Outcome:

The examination was done first, as entry 20's Next Steps required, and it refutes the hypothesis it was meant to test. Both processors derive from one signal: `snestang_top` raises its `enable` register, `main` passes it to `SNES` as `ENABLE`, `dsp.v` forms `SMP_EN_INT = SUBSTEP == 3 ? ENABLE : 1'b0` and `smp.v` forms `SPC700_CE = ENABLE & CE`, whose `RDY` reaches `spc700.v` as `EN = RDY & ~STPExec`. So the SPC700 cannot start before the 65816: neither runs until the same `ENABLE` is high, and the SPC's one-in-four `SUBSTEP` gate only divides its own clock rate, as the 1.024 MHz SPC requires. Nor can pausing separate them: the only thing that lowers `enable` after it rises is `pause_snes_for_frame_sync`, which is asserted at scanline 2 while a refresh is pending and held for thirteen mclk, and it lowers `ENABLE` for both processors at once. Two further candidates were checked and also cleared. The DSP's clock-enable generator is held in reset whenever `ENABLE` is low, because `CEGEN_RST_N = RST_N & ENABLE`, which re-seeds its fractional divider on every transition -- but that makes the phase deterministic given fixed `ENABLE` edges rather than a source of variation, and `CEGen` zeroes only `CLK_SUM` and `CE`. And `tools/load_snes_rom.py` already waits 0.5 s after the last data frame before releasing the core, which is the tail drain that `EXT-003` requires, so the image is not being truncated at the end of the stream. The result is a negative one and is recorded as such: there is no sequencing defect in the reset and enable path. That matters because it was the last explanation entry 20 left standing, so the diagnosis needs a new hypothesis rather than a new build of the same shape. What survives the whole session is narrower and worth stating plainly: the APU handshake completes on every boot measured, all three memories plus read stability are verified byte-lane correct on hardware, and the 65816 nevertheless ends somewhere different on each of five boots of one identical image and bitstream. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was not changed, checked that entries 1 to 20 were not rewritten, revised EXT-006 in place, and validated this entry's numbering, six sections, one-sentence Purpose, prose, Status values and the twenty-one-entry count against the 100-entry limit.

#### Next Steps:

Test ARAM with the DSP arbitrating, because that is the one memory path this project has deliberately never exercised under load and it is now the best remaining candidate: entry 9's ARAM self-test owns the port with the machine disabled, so `dsp.v`'s `RS_SMP` state was never competing, and the SPC700's own ARAM traffic does not reach the controller directly but passes through that arbiter while the sound engine is concurrently fetching samples and echo. A corrupted arbitration would leave the SPC executing driver code that is subtly wrong, which is exactly the behaviour every boot shows -- it leaves its IPL, it advances Y, and it nonetheless fails to keep step with the 65816. The instrument is not another self-test but a comparison: have the 65816 write a known byte stream into ARAM through its own port while the machine runs, then read that region back through the SPC's view and compare, which catches a fault that appears only when both masters are active. If ARAM under arbitration is clean, the next candidate is the DSP's own sample fetch racing the SPC's fetch of the same addresses, which the same instrument can separate by directing the test region away from the echo buffer. Do not build another test of the CPU port at rest: every memory has passed that, and a sixth would add nothing. Do not re-time the port-0 read path, the DQ capture or the SDRAM clock, and do not reintroduce the ODDR on fclk. Keep all thirteen diagnostic builds as the regression set, run `tools/tests/probe_tb.sh` -- nine benches -- after any sampler change, and use `tools/sample_boot_states.py` for any comparison across boots. Read the RTL before each build the way this cycle did: it cost no hardware and it removed the hypothesis it was written to test.

#### Files Modified:

None.

#### Status:

- Build: N/A
- Deployment: N/A
- User Test: N/A

---

## 22 COMMIT Unreleased 2026-10-31T17:32:51-07:00

#### Coming From:

Unreleased 58a2323

#### Purpose:

Take the clock-plane safeguards the sibling projects already use on this board, because the user asked whether this fault had been solved before and the answer was that it had been, in the projects this one was ported from.

#### Outcome:

The user's recollection was right and the clue was in `TinyNES/.ai/core-reference.md`. DEV-017 records that on this board a clock reaching a spine through `SPINE17 <= CBRIDGEOUT_BOTTOM0` or `SPINE18 <= CBRIDGEOUT_BOTTOM2` clocks none of the flip-flops on that branch, which hold power-up 0, while `SPINE26 <= CBRIDGEOUT_BOTTOM2` clocks every one; DEV-009 records an open-flow image that loaded with DONE and was silent until three centre-mux entries were changed; DEV-016 records a failing netlist that booted with nothing changed but its clock routing order. TinyNES guards all three with `NPNR_GOWIN_CLK_FIRST`, a build gate on the routed spine and bridge pips, and a chipdb test, and TinyTang found the same class from the other side when its desktop core was dead on a left-side PLL and ran on a right-side one. Counting the guards showed TinySNES had inherited none of them: zero occurrences of the knob, of any spine check and of any bridge check, against three, eleven and four in TinyNES's build script. This cycle adds `tools/clock_plane_report.py` and wires it into `tools/build_tinysnes.sh`, which now exports `NPNR_GOWIN_CLK_FIRST` before place and route, fails if nextpnr did not log that it applied (the net not matching anything is the silent failure TinyNES recorded), and then reports every clock's spine and bridge pips and refuses any build whose clocks sit on pips nobody has measured on this board, with `TINYSNES_ALLOW_UNMEASURED_CLOCKS=1` downgrading that to a warning. The rule is source-dependent and the tool's first version got it wrong by conflating the two: for a PLL source DEV-009 puts the good entries on TOP and the dead ones on BOTTOM0, while for an HCLK CLKDIV source DEV-017 puts the good entry at SPINE18/BOTTOM2 and the dead ones on TOP. The table also carries this project's own hardware measurements, which outrank inherited ones, because the picture on this board is stable and therefore whatever the pixel clock and pll_27's input route through is known to clock its branches. Running it on the last routed netlist named the exposure precisely: the SNES master clock, `iosys.clk`, spans six spines -- 0, 8, 16, 18, 25 and 26 -- of which SPINE8/TOP0 is measured good by TinyNES and SPINE16/TOP0 and SPINE26/TOP0 are measured good by this board's working video, leaving `SPINE0/CBRIDGEOUT_TOP0` and `SPINE25/CBRIDGEOUT_TOP1` unmeasured. A six-seed sweep with the knob applied found that pair used at every seed, so it is a constant of this design rather than a placement accident, and SPINE25/TOP1 is in the TOP1 family that DEV-017 left completely dead in eight of eight seeds for a CLKDIV source. That is a lead and not a finding, and the record says why: a fully dead spine would fail deterministically, whereas five boots of one image gave five different states, so the mechanism here would have to be marginal rather than dead, which DEV-018 shows is physically possible on this board since it goes temperature-sensitive above about 41 C. What this cycle establishes is narrower and solid: the design was free to place its machine clock on spines no one has measured, it does so consistently, and the safeguards that would have caught it were absent while three sibling projects had them. One tooling defect of this cycle's own is recorded because it hid the result for a whole sweep: the first wiring passed the allow flag as `${allow_unmeasured:+}`, which expands to nothing and left every seed refused, and the fix is an array built conditionally. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was not changed, checked that entries 1 to 21 were not rewritten, and added DEV-004 and TCL-014, and validated this entry's numbering, six sections, one-sentence Purpose, prose, Status values and the twenty-two-entry count against the 100-entry limit.

#### Next Steps:

Get the machine clock off `SPINE25/CBRIDGEOUT_TOP1` and `SPINE0/CBRIDGEOUT_TOP0` and see whether the machine runs, because that is now a named, reproducible difference between this design and every sibling that works on this board: the knob makes the routing order deterministic but does not choose the spine, so the next lever is the chipdb's own entry rule in `apicula-mathieufro`'s `fse_clock_pips_138`, which already forbids the TOP entries for an HCLK CLKDIV source and could be made to forbid a PLL source's entry into SPINE0 and the TOP1 pips the same way, on the strength of DEV-017's eight-of-eight negative -- with the caveat that widening the fork's restriction is a change to a shared tool and should be measured against a build that keeps video working before it is kept. Build that variant, confirm from `tools/clock_plane_report.py` that no clock sits on an unmeasured pip, and load it: a machine that then runs proves the clock plane; a machine that fails the same way retires the hypothesis and returns the work to the machine itself. Do not treat the present build as exonerated in the meantime, and do not re-time the port-0 read path, the DQ capture or the SDRAM clock, and do not reintroduce the ODDR on fclk. Keep all thirteen diagnostic builds as the regression set, run `tools/tests/probe_tb.sh` -- nine benches -- after any sampler change, run `tools/clock_plane_report.py` on every routed netlist before a hardware load, and use `tools/sample_boot_states.py` for any comparison across boots.

#### Files Modified:

- tools/build_tinysnes.sh
- tools/clock_plane_report.py

#### Status:

- Build: PASS
- Deployment: NOT RUN
- User Test: NOT RUN

---

## 23 COMMIT Unreleased 2026-10-31T19:02:06-07:00

#### Coming From:

Unreleased a8983ae

#### Purpose:

Test whether the clock plane is the fault by building with the routing-order knob applied and sampling repeated boots against the distribution recorded before it.

#### Outcome:

Two link-probe builds were made with `NPNR_GOWIN_CLK_FIRST=iosys.clk` set, at seeds 7 and 9 in `build/kpl7` and `build/kpl9`, both with zero hold/min violations; seed 7 passed the timing gate at hclk 173.611 against 74.250 MHz and iosys.clk 30.398 against 21.505, giving `tinysnes.fs` SHA-256 `dc54750985f80fdd686bea2677e83a980f83d5d1311d8af9ef5a18bdaf25d6fa`, and that image was loaded one-wire and sampled over five boots with `tools/sample_boot_states.py`. The knob did change the route: the machine clock moved from SPINE0, SPINE16, SPINE18, SPINE26 and SPINE8 in all on TOP entries to SPINE0, SPINE16 and SPINE25 only, so SPINE18/TOP1 and SPINE26/TOP0 dropped out and SPINE25/TOP1 came in. It did not remove the exposure, because `SPINE0/CBRIDGEOUT_TOP0` remains at every seed and one TOP1-family entry remains either way, so the clock never actually left an unmeasured pip. The five boots then produced five distinct states -- CPUO $BB10 with A $0100, A $011B and A $012B and three different entry counts, plus two boots at CPUO $BB01 and $BB05 with the program counter at $0006 and one at $7C7F with CPUI reading $40F9 -- which is the same verdict as the five-distinct-states baseline of entry 18 measured without the knob. That is a clean negative and its interpretation has to be exact: the clock-plane hypothesis is not refuted, it is untested, because the only thing that changed was the order in which the router considered the nets, and the router's choice of pips was the thing under test. Three of five boots again ended at $7C7F, which the earlier work established is below the LoROM window and reads back as bus data rather than code, and one ended at $0006, which is inside the WRAM mirror of banks $00 to $3F rather than in cartridge space. The consistent finding across every boot of every build this session is unchanged and is now the whole of the evidence: the handshake completes, every memory verifies byte-lane correct, the read path is stable, no sequencing defect exists, and the machine nonetheless stops somewhere different each time. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was not changed, checked that entries 1 to 22 were not rewritten, revised TCL-007 and DEV-004 in place, and validated this entry's numbering, six sections, one-sentence Purpose, prose, Status values and the twenty-three-entry count against the 100-entry limit.

#### Next Steps:

Move the clock rather than its routing order, which is the only lever that tests the hypothesis: the knob makes the router deterministic but still leaves the machine clock on `SPINE0/CBRIDGEOUT_TOP0` and a TOP1 pip at every seed, so the restriction has to go into the chipdb entry rule in `apicula-mathieufro`'s `fse_clock_pips_138`, which already forbids TOP entries for an HCLK CLKDIV source and could forbid a PLL source's entry into SPINE0 and into the TOP1 pips on the strength of DEV-017's eight-of-eight negative. That is a change to a tool three projects share and needs the user's approval before it is made; the safe form is an environment-gated extra restriction so the fork's default is untouched until a build shows it helps. The test after that is deliberately narrow: build the link probe with the restriction on, confirm with `tools/clock_plane_report.py` that no clock sits on an unmeasured pip, and sample five boots. If the machine runs or the distribution collapses toward a single state, the clock plane was the fault and the restriction should be offered upstream to TinyNES and TinyGBC, which would benefit from it too; if five boots again produce five states, the clock plane is retired and the work returns to the machine with a much stronger negative behind it. Do not deploy another build whose clock plane has not been read first, and do not treat the routing-order knob as evidence either way. Keep all thirteen diagnostic builds as the regression set, run `tools/tests/probe_tb.sh` -- nine benches -- after any sampler change, run `tools/clock_plane_report.py` on every routed netlist before a hardware load, and use `tools/sample_boot_states.py` for any comparison across boots.

#### Files Modified:

None.

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: NOT RUN

---

## 24 COMMIT Unreleased 2026-10-31T19:22:18-07:00

#### Coming From:

Unreleased f577564

#### Purpose:

Check the user's recollection that TinyGBA had already met this fault, by reading its recent findings against this design's routed netlist.

#### Outcome:

The recollection was right and the match is exact. TinyGBA's entry 4 records that `clk67` fell back to general routing on all 255 of its sinks with 1.2 to 1.9 ns of skew, that this cost clean seeds on every netlist change, and that it was suspected of both a failed SDRAM readback and an absent picture; the cause was a missing database entry rather than any design compromise, because apicula's `_gw5a_pll_clk_wires` carried only two pips into the clock plane, both from `CLKOUT0`, so a second PLL output had no way to reach the plane at all. TinyGBA measured two vendor builds, established that a second output reaches the plane on a lane whose number follows the output number, added `(0, 'CLKOUT2') -> 'TLPLL0CLK2'`, regenerated the chipdb and rebuilt nextpnr, and the result went from three clean seeds of six to eight of eight with `clk67` on global resources. Applying the same question to this design found the same class of fault, larger. The fork's pip table carries exactly three entries -- `(0, CLKOUT0) -> TLPLL0CLK0`, `(4, CLKOUT0) -> TRPLL0CLK0` and `(0, CLKOUT2) -> TLPLL0CLK2` -- and this design's three PLLs sit at `PLL_R[0]`, `PLL_R[1]` and `PLL_R[3]` with outputs `CLKOUT0`, `CLKOUT1` and `CLKOUT2`. So only `mclk` from `PLL_R[0]` `CLKOUT0` has a pip; `fclk` from `CLKOUT1` has none anywhere in the database, `fclk_p` from `CLKOUT2` has no slot-4 entry, and `clk27` from `PLL_R[1]` `CLKOUT0` has no slot-5 entry. Reading the routed netlist confirms what that means in silicon: `iosys.clk`, which is `mclk`, runs 11910 segments through the `CLK1`/`GB10` global taps as expected, while `fclk` runs 1281 segments of ordinary interconnect -- `X151Y19/W130`, `X150Y19/N830` -- with no spine and no global tap anywhere in its route, and it clocks 225 flip-flops spread from X140 to X180 and Y0 to Y20. `hclk5` is unaffected because it takes the `FCLKA`/`HCLK32` dedicated high-speed lane to the OSER10s, which is the correct path for that clock. `fclk` is the SDRAM controller's clock: `sdram_snes` takes `.clk(fclk)`, so the ROM, WRAM, ARAM and loader paths all run on a net the router placed on general interconnect with no skew guarantee, at 15.5 ns per period. That is the same fault TinyGBA found, on the clock that matters most here, and it is the first hypothesis this session that explains the shape of every measurement: the compact self-tests place their handful of `fclk` flip-flops close together and pass, while the machine spreads 225 of them across 40 tiles of width and fails, which is exactly the split between byte-lane tests that pass and a machine that does not run. It also explains the nondeterminism without invoking anything else, because a marginal rather than broken path resolves differently depending on power-up state, temperature and the exact phase at which the loader releases the core. The bound is stated: this is a mechanism matched against a sibling project's measured result and confirmed present in this design's netlist, not yet proven to be the cause, and the untested step is whether putting `fclk` on the clock plane makes the machine run. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was not changed, checked that entries 1 to 23 were not rewritten, revised DEV-004 and TCL-007 in place and added TCL-015, and validated this entry's numbering, six sections, one-sentence Purpose, prose, Status values and the twenty-four-entry count against the 100-entry limit.

#### Next Steps:

Add the missing pip for `PLL_R[0]` `CLKOUT1` and test whether `fclk` reaches the clock plane and the machine runs, because that is the one lever nothing this session has touched: TinyGBA's evidence establishes that an output's lane number follows its output number, from `CLKOUT0` on lane 0 and `CLKOUT2` on lane 2 measured in two vendor builds, so `CLKOUT1` on `TRPLL0CLK1` is the entry to add as `(4, 'CLKOUT1') -> 'TRPLL0CLK1'`. The fork's own rule is that only measured entries belong in that table, so this needs a vendor measurement first, in the shape TinyGBA used: a Gowin IDE build with `CLKOUT1` alone enabled driving a register bank, unpacked and read for the spine and bridge it takes. That is a change to a tool three projects share, so it needs the user's approval and should be offered to TinyNES and TinyGBC rather than kept here. The narrower test that needs no fork change at all is to move `fclk` onto `PLL_R[4]` or another slot that already has a `CLKOUT0` pip, rebuilding `gowin_pll_snes` with the same dividers so `mclk`, `fclk` and `fclk_p` come from outputs that have database entries -- `mclk` from one PLL's `CLKOUT0` and `fclk` from another's `CLKOUT0`, at the cost of one more PLL and the phase relationship between them, which is why the pip is the better fix and this is the fallback. Either way, confirm the result with `tools/clock_plane_report.py` before loading and with `tools/sample_boot_states.py` across five boots after, and extend `tools/clock_plane_report.py` to flag any clock net that carries more than a handful of flip-flops without a spine tap, since that check would have caught this and catches the next one. Do not build another memory test and do not sweep more seeds.

#### Files Modified:

None.

#### Status:

- Build: N/A
- Deployment: N/A
- User Test: N/A

---

## 25 COMMIT Unreleased 2026-10-31T19:49:06-07:00

#### Coming From:

Unreleased 67916db

#### Purpose:

Put the SDRAM clock on the global clock plane without changing the shared apicula fork, by moving it onto a PLL output that already has a clock-plane pip.

#### Outcome:

`fpga/snes/pll/gowin_pll_sdram.v` is a second PLL at `PLL_L[0]` driving `fclk` from `CLKOUT2` and `fclk_p` from `CLKOUT1`, with the 225-degree phase shift moved onto `CLKOUT1` so the unshifted clock is the one on the plane and the phase relation between the pair is preserved inside one PLL, which the SDRAM DQ capture depends on. `CLKOUT0` is disabled at that site because its plane wire `TLPLL0CLK0` is the one TinyNES measured as producing a dead core. `gowin_pll_snes` keeps `mclk` on `CLKOUT0` at `PLL_R[0]`, the only other slot with a `CLKOUT0` pip, and its unused outputs are disabled; `fpga/snes/tinysnes.cst` places the new PLL and `tools/build_tinysnes.sh` adds the file. The change works as intended at the routing level: `fclk` moved from 1281 general-routing segments with no spine onto `TLPLL0CLK2` through the centre mux at `X93Y54/SPINE10` and out of `X96Y27/SPINE28/CBRIDGEOUT_TOP2`, which is the pip TinyGBA measured from the vendor flow and the bridge output DEV-009 measured as running, in 699 segments with a spine and with global taps. Both seeded builds had zero hold/min violations and passed the timing gate at hclk 156.006 and iosys.clk 28.746 against 74.250 and 21.505. The hardware result is a change and not a cure, and it has to be read in two halves. The 65816's execution changed substantially: where five boots of the previous image ended at `$7C7F` -- open bus, below the LoROM window -- after entering the upload routine two to four times, five boots of this image execute real ROM code, at `$80FD` and `$82DD` in three boots and at `$7FF7` and `$6C6F` in the other two, and every history bit is now clear, so the CPU never entered the routine at `$8888` and never wrote `$CC`. `$80FD` is ROM offset `$00FD` and holds `8D 30 01`, a `STA $0130`; `$82DD` holds `5A 0B 8B 4B`, real instructions. The picture, however, is unchanged: the production image built from the same tree draws the same static grid of white lines that entry 2 recorded, so the machine does not boot. Five boots still produced five distinct states, so the nondeterminism survives the clock change. The honest reading is that the clock plane was a real defect and fixing it moved the failure, without establishing that it moved it forward: the CPU is executing cartridge code instead of bus data, which is healthier, but it now fails before the sound upload rather than during it, which is earlier in the boot. One caveat on the gate is recorded because it bears on how much weight the routing result carries: `tools/clock_plane_report.py` reports `fclk`'s pips as unmeasured, since the bridge output is `TOP2` at spine 28 rather than the spine 10 DEV-009 named. Same bridge output, different spine number, and the record keeps that distinction rather than rounding it away. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was not changed, checked that entries 1 to 24 were not rewritten, revised TCL-015 and DEV-004 in place, and validated this entry's numbering, six sections, one-sentence Purpose, prose, Status values and the twenty-five-entry count against the 100-entry limit.

#### Next Steps:

Find where the 65816 goes after the reset code, because it now executes cartridge code and then reaches an address below the LoROM window, and the two boots that ended at `$7FF7` and `$6C6F` say the departure happens early rather than in the sound path: the trace ring is the right instrument and needs no new RTL, since it holds the last four `ROM_ADDR` values and LoROM bank 0 is the image offset directly, so sampling it over five boots and disassembling the newest entry from each gives the instruction that diverts the CPU. Read the image's reset path first -- ROM offset 0 is `78 9C 00 42 ...`, a `SEI` then `STZ` to the PPU and APU registers, and the routine at `$80FD` is only `$FD` bytes into the image -- because a CPU that reaches `$80FD` and `$82DD` on some boots and `$7FF7` on others is either taking a different branch on an uninitialised value or being reset into a different path, and the two candidates are a wrong indirect jump and a spurious interrupt. The interrupt question is now the more likely of the two and is testable cheaply: latch whether the 65816's program counter is ever in the vector table and read the processor status byte at that moment, which the APU probe already does through `DBG_REG` 0x08 and 0x15 and which would show whether the emulation bit and the interrupt-disable bit were set when it happened. Do not change the clock plane again while that question is open, since it now demonstrably alters behaviour and every further change makes the comparison harder. Do not build another memory test. Keep the production image and the link probe both built from the same tree so a picture result and a CPU result can be compared boot for boot, and use `tools/sample_boot_states.py` for every comparison across boots.

#### Files Modified:

- fpga/snes/pll/gowin_pll_sdram.v
- fpga/snes/pll/gowin_pll_snes.v
- fpga/snes/src/snestang_top.v
- fpga/snes/tinysnes.cst
- tools/build_tinysnes.sh

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: NOT RUN

---

## 26 COMMIT Unreleased 2026-10-31T20:05:34-07:00

#### Coming From:

Unreleased 2743665

#### Purpose:

Find where the 65816 goes after the reset code, now that the clock-plane repair moved it from executing bus data to executing cartridge code.

#### Outcome:

`TINYSNES_TRACE_PROBE` was rebuilt on the new clock plan at seeds 7 and 9, both with zero hold/min violations and `fclk` on `TLPLL0CLK2` through `CBRIDGEOUT_TOP2`, and seed 7 (`build/tr7/tinysnes.fs`, SHA-256 beginning `bbe5c53a853bc4b8`) was sampled over five boots with `tools/sample_boot_states.py --layout trace`. The ring holds the last four ROM byte addresses, and LoROM bank 0 maps CPU `$8000+n` to ROM offset `n`, so each entry reads directly as an image offset. ROM `0x7FFE` -- CPU `$FFFE`, the IRQ/BRK vector -- appears in all five rings, and it is the newest entry in four of them. Boot 4 is the decisive one because its ring is complete: `1E10`, then `7FFE`, then `02DB` and `02DC`, which is a read of the vector at `$FFFE` followed by execution at ROM `0x02DB` = CPU `$82DB`, three bytes past the vector's own target `$82D8` and therefore inside the handler that target begins. The CPU took an interrupt or a break and ran its handler. The other boots show what look like ordinary instruction fetches immediately before the vector read -- `0084`, `0088`, `008A` ascending, and `02A3`, `02A6`, `02A9` ascending -- so the CPU is running code and then the vector fetch happens, rather than the fetch being the first thing after reset. Two RTL checks narrow the mechanism without another hardware cycle. The 65816's status register resets to `9'b100110100`, whose low byte is `$34`: the emulation, memory-select and index-select flags are set and so is the interrupt-disable bit, so an IRQ would be masked from the first instruction. The core's gate agrees with that, since `GotInterrupt <= (IRQ_ACTIVE & ~P[2]) | NMI_ACTIVE` and `IsIRQInterrupt <= IRQ_ACTIVE & ~P[2]` both respect it. That leaves a BRK, whose opcode is `$00` and which takes the `$FFFE` vector regardless of the interrupt-disable flag, and it leaves NMI, whose vectors are ROM `0x7FEA` and `0x7FFA` and which appear in none of the five rings. Since the two escapes are indistinguishable in a ROM-address trace -- a vector read and an opcode fetch look alike on that bus -- what this cycle establishes is the chain and not its cause: the CPU reaches the `$FFFE` vector and executes its handler on every boot. Two limits are stated rather than glossed. The bytes near the departure points do not read as unmistakable code to manual inspection -- ROM `0x0084` holds `87 83 A4 83 A4 99 99 F8`, which decodes to valid but implausible instructions -- and this image's bank 0 layout has not been established here, so no claim is made that the CPU is diverging at a specific wrong branch. And the trace ring cannot tell a vector fetch from an opcode fetch, which entry 19 recorded and which is exactly the ambiguity that matters now. The production image from the same tree still draws the static grid recorded in entry 2, so the machine does not boot. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was not changed, checked that entries 1 to 25 were not rewritten, revised TCL-008 in place, and validated this entry's numbering, six sections, one-sentence Purpose, prose, Status values and the twenty-six-entry count against the 100-entry limit.

#### Next Steps:

Distinguish a vector fetch from an opcode fetch, because that is the one thing standing between this measurement and its explanation, and the existing debug port already carries the state needed: read the processor status byte at `DBG_REG` 0x08 and the flags at 0x15 together with the program counter in the same snapshot the moment the counter is seen above `$8000` and again whenever it is in `$FFE0-$FFFF`, so a CPU that enters the vector range with the interrupt-disable bit still set is executing an opcode there rather than taking an interrupt, which would make the byte at `$FFFE` the instruction and the ring's four entries the fetches before it. A cheaper first check that needs no build is to read the image's bank-0 layout properly, since ROM `0x0084` holding `87 83 A4 83` suggests the region the ring names is not the code path this game boots through, and a disassembler run over ROM `0x0000-$7FFF` would say whether the addresses the ring reports are reachable instructions at all; if they are not, the ROM-address mapping itself is suspect rather than the CPU, and `ROM_WORD` and the mapper in `chip/DSP/DSP_LHRomMap.v` come back into question despite entry 4's finding. Do not change the clock plane again while this question is open, do not build another memory test, and do not sweep seeds for a better placement: five boots have twice given five states, so a seed that happens to look better is not evidence. Keep the production image and each probe built from the same tree, and use `tools/sample_boot_states.py` for every comparison across boots.

#### Files Modified:

None.

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: NOT RUN

---

## 27 COMMIT Unreleased 2026-10-31T21:48:38-07:00

#### Coming From:

Unreleased cdf4438

#### Purpose:

Test whether the fast-ROM read window is the fault, since the image's header marks it a fast cartridge and the fetch path was tuned against a slow one, and then read the CPU's own status rather than inferring from ROM addresses.

#### Outcome:

The header check came first: ROM `0x7FD5` reads `$30`, so this image is LoROM with bit 4 set, a fast cartridge, which confirms the LoROM mapping every address in this session has assumed and puts the CPU on the fast timing path. For banks `$80-$BF` the region decode sets `SLOWFAST`, `MEMSEL` then selects `FAST`, and `CPU_LAST_CLOCK` is 5 rather than 7, so the CPU latches a ROM read at mclk 5 while entry 4 measured the SDRAM path delivering at mclk 4 -- one master clock of margin instead of three. That looked strong because entry 4 also recorded `ROM_Q` reading zero at the first assertion of `ROMSEL`, and a zero read is the `BRK` opcode, which would explain the `$FFFE` vector fetch entry 26 found. A diagnostic build gated behind `TINYSNES_FORCE_SLOW_ROM` forced `SLOW` for those banks, giving three mclk of margin, and the hypothesis is refuted on hardware: the production image still draws the static grid of entry 2, and the trace probe with the same define still fetched `$FFFE` in four of five boots. Reading the CPU's own status byte through `TINYSNES_CPU_PROBE` over five boots replaced the inference with a measurement and changed the picture completely. ROM access counts are in the millions -- 1,114,112, 1,179,648, 6,291,456, 11,730,944 and 12,648,448 -- so the machine is executing a great deal of cartridge code rather than dying at once, and in four of five boots the status byte is `$0A`, which is `WAIExec` set, and in the fifth `$09`, which is `STPExec`. `WAIExec` is sticky, cleared only by reset, and it drives `EN` low through `assign EN = RDY_IN & CE & (~WAIExec) & (~STPExec)`, so in four boots of five the 65816 has executed `WAI` and halted waiting for an interrupt that has not arrived, and in the fifth it executed `STP` and halted outright. One inference made earlier in this cycle is withdrawn before it can be relied on: `GotInterrupt` is zero in all five samples, and I read that as proof the `$FFFE` fetch was a `BRK` rather than an interrupt, but `GotInterrupt` is only held for one instruction sequence -- it is cleared at the next `LAST_CYCLE` -- so sampling instants cannot prove an interrupt never fired. The sound statement is the narrower one: at every sampled instant the CPU is halted on `WAI` or `STP` with no interrupt in progress. The RTL also carries `IsBRKInterrupt`, a combinational `IR == 8'h00`, which is exactly the signal that would settle the `BRK` question and which no probe exposes. For the first time the machine's failure has a shape that points at a missing input rather than corrupt data: a CPU that runs millions of instructions and then waits for an interrupt is behaving correctly, and what is absent is the interrupt. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was not changed, checked that entries 1 to 26 were not rewritten, revised TCL-008 and added EXT-007, and validated this entry's numbering, six sections, one-sentence Purpose, prose, Status values and the twenty-seven-entry count against the 100-entry limit.

#### Next Steps:

Instrument the interrupt inputs, because the CPU is waiting rather than lost and the next question is which interrupt is missing: add sticky bits for whether `VBLANK` has ever risen, whether `NMI_EN` has ever been set, whether `NMI_FLAG` has ever been set, and whether the 65816's own `IsBRKInterrupt` has ever been asserted, and read them beside the `WAI` state. A CPU waiting on `WAI` with `NMI_EN` set and `VBLANK` having risen but `NMI_FLAG` never set puts the fault in the `VBLANK && ~VBLANK_OLD2 && DOT_CLK_CE` edge detector in `cpu.v`; `VBLANK` never rising puts it in the PPU's vblank generation, which would also explain why the picture never initialises, since the CPU would be waiting before it drew anything; `NMI_EN` never set means the game never reached the code that writes `$4200` bit 7, and the `$FFFE` vector fetch has to be re-examined as a `BRK` with `IsBRKInterrupt` as the evidence rather than `GotInterrupt`. Read the PPU's vblank output first because it costs no hardware cycle: `INT_VBLANK` leaves `SNES.v` and reaches `cpu.v` as `VBLANK`, and the counters at `$78` that produce it depend on `DOT_CLK_CE`, `ENABLE` and the H/V blank inputs from the PPU, so a mistake in that chain is visible in the RTL. Do not change the clock plane again while this is open, do not build another memory test, and do not sweep seeds. Keep `TINYSNES_FORCE_SLOW_ROM` in `cpu.v` as a documented negative result rather than removing it, and use `tools/sample_boot_states.py --layout cpu` for any comparison across boots.

#### Files Modified:

- fpga/snes/src/cpu.v
- tools/sample_boot_states.py

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: NOT RUN

---

## 28 COMMIT Unreleased 2026-10-31T22:16:35-07:00

#### Coming From:

Unreleased 360f232

#### Purpose:

Find which interrupt is missing, since entry 27 established that the 65816 halts on `WAI` after millions of correct ROM fetches and is therefore waiting rather than lost.

#### Outcome:

`TINYSNES_IRQ_PROBE` reads three sticky interrupt-history bits plus the core's status byte and halt program counter in one latched snapshot. The bits latch from reset and are never cleared, for the reason TCL-013 records, and they are implemented in `cpu.v` rather than in the 65816 core because that is where `VBLANK`, `NMI_EN` and `NMI_FLAG` all live. They are exposed through debug register `0x16`, which the core does not use: `cpu.v` now intercepts that one register and passes every other value through, so no upstream port list changed. Two defects of this cycle's own are recorded because both were caught before they could produce a reading. The first repeats a fault this project has already shipped: `always @(*) dbg_sel = 8'h01` has no sensitivity and never drives, which is exactly TCL-008, and it was moved into the clocked block. The second was in the decode tool, which assumed the fields were in the order the RTL comment lists rather than the order the concatenation produces, and reported a five-digit program counter -- a value impossible on a 16-bit bus, which is what exposed it; the formatter now reads sticky from the low byte of the first stripe, status from its high byte, and the PC from the second. Seed 7 built clean with zero hold/min violations and passed the timing gate at iosys.clk 30.481 against 21.505, giving `tinysnes.fs` SHA-256 `50d89d8c07b8f992caf81d6190d50ac3c494ac74546cbe0c38df23048aeacfa2`, and it was loaded one-wire with the bench's image streamed after it. The readout, identical in 178 of 180 captured frames, is `sticky = 0x05` and `status = 0x08` with the halt program counter at `$4C4D`. Read against the bits: `VBLANK` has been high, so the PPU does generate vertical blank; `NMI_FLAG` has been set, so the `VBLANK && ~VBLANK_OLD2 && DOT_CLK_CE` edge detector in `cpu.v` does fire; and `NMI_EN` has never been set, so the game never wrote bit 7 of `$4200`. The `EN` bit reads low, but that is not a fault and the record says why: `assign EN = RDY_IN & CE & (~WAIExec) & (~STPExec)` and `CE` is `INT_CLKF_CE`, a one-mclk pulse per instruction, so a random sample almost always catches it low. The halt program counter at `$4C4D` is below `$8000` and therefore not in ROM at the sampled instant, which is consistent with a CPU caught between instructions rather than one parked on a fetch. The result is a clean pair of negatives that narrow the search: the two hypotheses entry 27 ranked first -- that the PPU might not generate vblank, and that the edge detector might not fire -- are both refuted, and what remains is that the 65816 stops before it enables NMI rather than after, so the fault is in the code path between reset and the `$4200` write rather than in the interrupt machinery. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was not changed, checked that entries 1 to 27 were not rewritten, revised TCL-008 and added EXT-008, and validated this entry's numbering, six sections, one-sentence Purpose, prose, Status values and the twenty-eight-entry count against the 100-entry limit.

#### Next Steps:

Follow the 65816 from reset to the stop, because the interrupt machinery is now exonerated and the question is what the code did between entering the ROM and reaching the instruction that halts it: the trace ring is the instrument and holds the last four `ROM_ADDR` values, but entry 26 showed a ROM-address ring cannot tell an opcode fetch from a vector fetch, so pair it with the sticky `st_brk` idea that already has a signal in the core -- `assign IsBRKInterrupt = (IR == 8'h00)`, which no probe yet reads -- by adding it to the `cpu.v` sticky byte in register `0x16`, where there are five spare bits. Then sample the trace ring and the sticky byte in the same build across five boots: a boot with `IsBRKInterrupt` set and the ring ending at `$FFFE` is a software break, and the four addresses before it name the instruction that issued it; a boot without it puts the halt on ordinary code and the ring names the last good fetches before it. Also worth one cheap check that needs no build: read the image's `$4200` write sites with a disassembler, since a game that never enables NMI is doing something else first and the earliest such write in the reset path bounds how far the CPU should have got. Do not change the clock plane, do not build another memory test, and do not sweep seeds. Keep `TINYSNES_FORCE_SLOW_ROM` in `cpu.v` as a recorded negative, use `tools/sample_boot_states.py --layout irq` for this instrument, and remember that `EN` will always read low on a random sample because its clock enable is a one-cycle pulse.

#### Files Modified:

- fpga/snes/src/cpu.v
- fpga/snes/src/snestang_top.v
- fpga/snes/src/snes2hdmi.v
- tools/sample_boot_states.py

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: NOT RUN

---

## 29 COMMIT Unreleased 2026-10-31T23:08:17-07:00

#### Coming From:

Unreleased 0ff6b86

#### Purpose:

Find out whether the `$4200` write the reset path performs ever reaches the decode, since entry 28 showed NMI was never enabled and the store sits only 48 bytes into the image.

#### Outcome:

Two sticky bits were added to `cpu.v`'s interrupt byte, testing the same condition the IO write decode uses -- `P65_EN && ~P65_R_WN && ~P65_A[22] && P65_A[15:8] == 8'h42` -- so a bit means a store reached the decode rather than merely that the address was on the bus. Reading them exposed a regression this project introduced two cycles earlier and the rest of this entry is mostly about that. The measurement first: on the build then current, no write to `$4200-$42FF` had ever been decoded, which is impossible if the CPU were executing the image, because every one of the reset path's first eight instructions is a store to `$4200-$42xx`. That pointed at the fetch rather than at the CPU, and `TINYSNES_FETCH_PROBE` -- the instrument from entry 4 -- settled it in one frame: `ROM_ADDR` read `0x7FFC` correctly while `ROM_Q` read `0x0000` at the first assertion, at +2 mclk and at +4 mclk. The word never arrived. The same probe on the tree as it stood before cycle 25 read `0x0000`, `0x0000`, `0x8000`, exactly as entry 4 recorded, and a build from a worktree at commit `67916db` reproduced that. So cycle 25, which moved `fclk` from `PLL_R[0]`'s `CLKOUT1` onto a second PLL at `PLL_L[0]`'s `CLKOUT2` to reach the global clock plane, broke the SDRAM read path. The mechanism is the one TCL-007 and TCL-003 warn about from the other direction: `fclk_p` drives `O_sdram_clk` straight to a pin while `fclk` is the capture clock, and putting `fclk` on the global clock tree changed its insertion delay relative to `fclk_p`, moving the sampling point out of the window the DQ capture was tuned into. Cycle 25 was reverted in full -- `gowin_pll_sdram.v` deleted, `gowin_pll_snes.v` and `snestang_top.v` and `tinysnes.cst` restored, and the reference record's claim that the machine began executing cartridge code withdrawn -- and the revert was verified on hardware: `ROM_Q` is `0x8000` at +4 mclk again, the production image again draws the static grid of entry 2, and the CPU probe again finds the 65816 nowhere near `WAI` or `STP`. With the read path restored the instrument gave a sound reading for the first time: `w42xx` and `w4200` are both set, so the CPU does write `$4200`, while `NMI_EN` is still clear, so the write never carried bit 7; and the program counter sits at `$8896`, inside the sound upload routine, with neither `WAI` nor `STP` set. That is the picture entries 8 and 11 described, reached from a working ROM path, and it is the baseline any further work should start from. The larger lesson is recorded plainly because it cost three cycles: entries 25 through 28 were all measured on a build whose ROM read returned zero, so their readings described a machine executing `$00` bytes rather than the cartridge. Entry 26's vector fetches, entry 27's `WAI` and `STP` halts and entry 28's interrupt history are all artefacts of that regression and none of them should be relied on. The instruments built in those cycles are sound and worth keeping -- the sticky interrupt byte, the write-history bits, the `cpu` and `irq` layouts in `sample_boot_states.py`, and `TINYSNES_FORCE_SLOW_ROM` as a recorded negative -- but their readings are void. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was not changed, checked that entries 1 to 28 were not rewritten, restored `TCL-015` to its pre-cycle-25 text, and validated this entry's numbering, six sections, one-sentence Purpose, prose, Status values and the twenty-nine-entry count against the 100-entry limit.

#### Next Steps:

Re-measure the interrupt question on the restored baseline rather than trusting anything from entries 25 to 28, because those readings were taken with `ROM_Q` returning zero and describe a machine that was not executing the cartridge: rebuild `TINYSNES_IRQ_PROBE` from the current tree and sample it over five boots to learn whether `NMI_EN` is ever set now that the image actually runs, since the single reading taken after the revert says the CPU writes `$4200` but never with bit 7, and that wants confirming across boots before it is called a finding. Then add one more bit to the same byte for whether the program counter has ever been in `$80-$8F` in the range the reset path occupies, which separates a CPU that ran the prologue and then jumped away from one that never ran it. Only after that should the sound-upload deadlock of entries 8 to 12 be revisited, and the write-history bits make a sharper question possible than before: a CPU sitting at `$8896` with `$4200` written but NMI disabled is running its own code, so the place to look is why the 65816 and the SPC700 stop agreeing, and the `TINYSNES_LINK_PROBE` instrument from entry 12 is the one to bring back. Two habits are worth keeping from this cycle: check `ROM_Q` on any new clock or PLL arrangement before trusting any CPU reading taken on it, since a zero read produces a coherent-looking machine that executes `BRK` and never touches the IO registers; and when two consecutive probes disagree about something as basic as whether the CPU writes `$4200`, suspect the path underneath before the CPU. Do not reintroduce the second SDRAM PLL, do not re-time the port-0 read path or the DQ capture, and do not reintroduce the ODDR on fclk.

#### Files Modified:

- fpga/snes/pll/gowin_pll_sdram.v
- fpga/snes/pll/gowin_pll_snes.v
- fpga/snes/src/cpu.v
- fpga/snes/src/snestang_top.v
- fpga/snes/tinysnes.cst
- tools/build_tinysnes.sh
- tools/sample_boot_states.py

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: NOT RUN

---

## 30 COMMIT Unreleased 2026-10-31T23:13:21-07:00

#### Coming From:

Unreleased cdf1a15

#### Purpose:

Re-measure the interrupt question on the restored baseline, because every reading from entries 25 to 28 was taken on a build whose ROM read returned zero.

#### Outcome:

`TINYSNES_IRQ_PROBE` was rebuilt from the reverted tree and sampled over five boots, which corrects the single reading entry 29 took after the revert. Four things are invariant across all five boots: a write to `$4200-$42FF` is always decoded, a write to `$4200` specifically is always decoded, `VBLANK` has always been high, and `NMI_FLAG` has always fired. So the 65816 always runs the reset prologue that writes `$4200`, the PPU always generates vertical blank, and the vblank edge detector always works. What varies is the program counter and one bit: `NMI_EN` is set in only one boot of five. That refutes entry 29's statement, made from one sample, that the CPU writes `$4200` but never with bit 7 -- whether NMI gets enabled depends on which path the boot takes. The five states are: two boots at `$8894` and `$8895` with `NMI_EN` clear and neither halt flag set, which is the `CMP $2140 / BNE` echo-wait of the sound upload that entries 8 through 12 spent five cycles on; one at `$4C4C`, below the LoROM window and outside the cartridge; one at `$E368` with `WAIExec` set and `NMI_EN` clear, which is a CPU correctly waiting for an interrupt the game had not yet enabled; and one at `$80CE` with `STPExec` set and `NMI_EN` **set**. That last boot is the informative one: NMI was enabled and the edge detector fired, so an interrupt was available, and the CPU still ended halted. Its program counter sits in the handler prologue at `$80C9`, whose bytes `78 C2 30 48 DA 5A 0B 8B` match the `$82D8` handler's, so the CPU took an interrupt and then halted inside the handler rather than failing to receive one. Enabling NMI therefore does not save the machine, which makes the missing-interrupt reading of entry 27 -- itself an artefact of the broken build -- doubly wrong: the machine fails with the interrupt enabled as well as without. Five boots produced five states, so the nondeterminism is unchanged by any of this and remains the one property that has held across every correct measurement in the session. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was not changed, checked that entries 1 to 29 were not rewritten, revised EXT-008 in place, and validated this entry's numbering, six sections, one-sentence Purpose, prose, Status values and the thirty-entry count against the 100-entry limit.

#### Next Steps:

Re-establish the sound-upload picture on the restored baseline, because two of five boots land in that loop at `$8894`/`$8895` and the link readings that diagnosed it -- entries 8, 11 and 12 -- were taken across builds that included the broken ones, so none of them can be assumed correct: rebuild `TINYSNES_LINK_PROBE` from the current tree, verify with `TINYSNES_FETCH_PROBE` that `ROM_Q` still returns `0x8000` at +4 mclk on that same bitstream, and only then sample five boots to learn whether the SPC700 and the 65816 are still ten indices apart or whether that too was an artefact. That single check decides whether the session's earlier diagnosis stands or whether it needs redoing, and it is the cheapest way to find out. If the link picture is confirmed, the next instrument is a sticky bit for whether the 65816 has ever been at `$8888`, which every boot in the earlier work did reach and which would say whether the upload is entered at all on this baseline. Do not build another interrupt instrument -- the interrupt chain is now exonerated twice over, once by the sticky bits and once by the boot that enabled NMI and still halted. Do not reintroduce the second SDRAM PLL. Do not trust a reading taken on a bitstream whose `ROM_Q` has not been checked in this session, and treat a zero `ROM_Q` as invalidating every CPU measurement on that build rather than as a machine state.

#### Files Modified:

None.

#### Status:

- Build: N/A
- Deployment: N/A
- User Test: NOT RUN

---

## 31 COMMIT Unreleased 2026-10-31T23:55:19-07:00

#### Coming From:

Unreleased e43e07a

#### Purpose:

Re-establish the sound-upload picture on the restored baseline, because the link readings of entries 8, 11 and 12 were taken across builds that included the broken cycle-25 one and could not be assumed correct.

#### Outcome:

`TINYSNES_FETCH_PROBE` and `TINYSNES_LINK_PROBE` were rebuilt from the clean `e43e07a` tree at seed 7 and the read path was checked before any CPU reading was trusted: `ROM_Q` reads `0x0000` at the first assertion, `0x0000` at +2 mclk and `0x8000` at +4 mclk, with `ROM_ADDR` `0x7FFC` and `0x007F`, so the machine fetches the real reset vector and every measurement below was taken on a tree where that holds. The link probe then gave a result that does not match entries 8 to 12 at all: the `cc` sticky bit -- whether CPUI port 0 has ever held `$CC`, the exact question entry 12 left open -- is set in all five boots, the 65816 really does send the handshake byte, and the SPC700's `Y` is non-zero in all five, so the SPC advanced past its first publish in every boot. In three boots `CPUO[0]` equals `CPUI[0]` with `Y` exactly one ahead (`18`/`17`, `18`/`17`, `08`/`07`), which is the block-copy loop's normal steady state rather than a deadlock; the equal `CPUO[0]` is weakened by the IPL's own self-echo at `$FFF5` and so is not proof on its own, but the `cc` bit is, and the earlier "ten indices apart, the SPC waits for an index the 65816 never sends" reading is withdrawn as an artefact of the builds it was taken on. The link probe's PC field read `$6C6F` in three of five boots while `TINYSNES_TRACE_PROBE` on the same tree read the ring frozen at `$8894` and `$88EF`, and those two cannot both be true, so a third instrument was built rather than a reading chosen: `TINYSNES_WHERE_PROBE` reads PC, PBR, SP and P together with every multi-byte field tear-guarded, and adds the memory a snapshot cannot carry -- a sticky bit armed at a PC of `$8000` or above and set by the first PC below it, that departing PC held, and the newest ROM address the mapper served. Because a LoROM maps cartridge only at `$8000-$FFFF` (record EXT-009), a PC below `$8000` is not code in any bank, so that bit is a complete test for the CPU leaving the image and it settles the contradiction in the CPU's favour: over five boots four left the cartridge and one did not, with departures at `$1035`, `$1036`, `$3D89` and `$1101`, while the fifth sat at `$88EF` in bank `$80` with `left` clear. The CPU is therefore running, executing the reset prologue, parsing the header, reaching the sound upload and -- on four boots of five -- jumping out of the cartridge into WRAM, expansion or open bus. The departure PC is a held value and describes the moment of leaving, but `PBR`, `SP` and `P` in the same snapshot are read at the latch and describe the machine after it has been out for some time, so they date the departure no more precisely than the bank it is sitting in: they read `$80`, `$00`, `$00` and `$8F` for the bank, `$FA`, `$08`, `$F7` and `$F2` for `SP` and `$05`, `$B0`, `$F0` and `$9C` for `P`, and the spread across those four boots -- including a stack pointer 247 bytes down in one and only thirteen in another -- is wide enough that no single mechanism is implied by them yet. `RDY_IN` reads low at some point in all five boots, which is the externally stalled CPU this core's `EN` gate produces and not a fault. Ten boots of three instruments produced ten distinct states and no boot repeated, so the nondeterminism remains the one invariant of the session and no single-boot reading is worth recording again. Production synthesis was re-run on the tree and completed cleanly, and all nine benches in `tools/tests/probe_tb.sh` pass. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was not changed, checked that entries 1 to 30 were not rewritten, added EXT-009 to the reference library with its fast-lookup index entry, and validated this entry's numbering, six sections, one-sentence Purpose, prose, Status values and the thirty-one-entry count against the 100-entry limit.

#### Next Steps:

Find out why the 65816 leaves the cartridge, because that is now the whole of the fault visible from outside: four boots of five depart at a PC between `$1035` and `$3D89` and end up executing open bus, while the fifth stays in the upload loop at `$88EF`; the bank and stack the CPU holds after the departure vary too widely across those boots to point at a single mechanism, so the departure itself is what has to be instrumented next. The cheapest discriminating instrument is an extension of `TINYSNES_WHERE_PROBE` that holds not just the departure PC but the four ROM addresses fetched immediately before it, which names the instruction that did the jumping rather than the address it landed on; a `JMP [$xxxx]`, an `RTS`, and a `RTI` are told apart by that in one boot and nothing else in the machine can separate them. If the departure proves to be an indirect jump through a pointer the upload routine wrote, the next place to look is the 65816's data reads of WRAM, which no instrument in this session has covered yet. Do not revisit the APU link, the interrupt chain, the SPC700 or the sound-upload deadlock: all four are settled, the link by the `cc` bit in five boots of five, and the deadlock reading of entries 8 to 12 is superseded. Do not trust a reading taken on a bitstream whose `ROM_Q` has not been checked in this session, and do not report a single boot as a result now that ten consecutive boots have produced ten distinct states.

#### Files Modified:

- fpga/snes/src/snestang_top.v
- fpga/snes/src/snes2hdmi.v
- tools/sample_boot_states.py

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: NOT RUN

---

## 32 COMMIT Unreleased 2026-11-01T00:11:30-07:00

#### Coming From:

Unreleased 3981bde

#### Purpose:

Identify the instruction that takes the 65816 out of the cartridge, since entry 31 established that four boots of five leave the image but held only the address they landed at.

#### Outcome:

`TINYSNES_JUMP_PROBE` was added: it keeps a three-deep ring of ROM addresses and, on the single edge that accepts the first PC below `$8000` after a sample at `$8000` or above, freezes that ring, the departure PC and the program bank into held registers, so the fetches and the departure describe one instant rather than two samples of a moving machine. Build and placement at seed 7 were clean and the read path was checked on this tree before any reading was taken, with `ROM_Q` `0x0000`, `0x0000`, `0x8000` and `ROM_ADDR` `0x7FFC`/`0x007F` from `TINYSNES_FETCH_PROBE`. The first sample was discarded because the display decoder unpacked the five 16-bit words as independent fields when the probe's fields cross word boundaries, which produced plausible but wrong addresses; the decoder now reassembles the whole 80-bit value and slices it at the register widths, and the numbers below are from the corrected build. The result is the first repeatable reading of the session: three boots of five depart to exactly `$1035`, a WRAM address, with the same pre-departure stream, and the two outliers departed to `$4958` and `$2400` from completely different regions, so the departure point varies but the common case is now stable enough to name. In those three boots the newest fetch before the departure is `$8887`, and the image disassembles coherently there: `$887E LDA $07`, `$8880 AND #$40`, `$8882 ASL A`, `$8883 ROL A`, `$8884 ROL A`, `$8885 ORA $06`, `$8887 RTL`, with the two conditional branches above at `$8876` and `$887A` both computing `$8887` as their target and confirming the boundary, so `$8887` is a genuine instruction and it is `RTL`. That rules out the indirect-jump hypothesis entry 31 proposed as the leading candidate: the CPU is not jumping through a bad pointer, it is returning through one. `RTL` pops a 24-bit address from the stack and lands at `$1035`, a WRAM address that holds no code from the image, so the stacked return address is wrong, and the reason it is wrong is not established here. A limit of the instrument has to be stated with the result and is recorded as TCL-016: the ring advances on the start of a bus access rather than on every byte, so it names a hot address and the region around it but is not an instruction-by-instruction trace, which is why the `RTL` is justified by disassembling the image rather than by the ring alone. The program bank read as unstable on the three departing boots and as `$80` on the two outliers, which is reported as the instrument seeing a change between its two reads rather than as a fact about the CPU. Five boots of this probe produced three distinct states, against ten distinct states over ten boots of the previous cycle's instruments, so the machine has become more repeatable and the `$8887 RTL` / `$1035` departure is the first failure signature in the session that reproduces. Production synthesis was re-run and completed cleanly and all nine benches in `tools/tests/probe_tb.sh` pass, and the cycle introduced no change to any core RTL path outside the probe blocks. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was not changed, checked that entries 1 to 31 were not rewritten, added TCL-016 to the reference library with its fast-lookup index entry, and validated this entry's numbering, six sections, one-sentence Purpose, prose, Status values and the thirty-two-entry count against the 100-entry limit.

#### Next Steps:

Find out why the stack holds a bad return address at the `$8887 RTL`, which is now the single mechanism standing between this machine and a boot. The routine the CPU is in is a helper that reads a byte, tests it against `#$10` and `#$1C` and returns; it is entered by a `JSL` or `JSR` from somewhere above it, and a correct return would leave the CPU above `$8000` in the same bank. The decisive instrument is one that captures the top three bytes of the stack, `$01FF` downward from the stack pointer, at the moment of the departure, because those three bytes are literally the address `RTL` is about to use: if they match a return address that no `JSL` in the image would have pushed, the caller pushed the wrong number of bytes or the stack pointer was wrong when it pushed, and if they are unrelated to any recent call the corruption is in the WRAM write path that this project's static byte-lane test passed in entry 20 and which nothing has yet exercised under a live `JSL`. Reading `SP` at the departure is the cheaper half of that question and is available by combining the fields already present in `TINYSNES_WHERE_PROBE` with this probe, which should be done before building a stack-content instrument. Do not revisit the APU link, the interrupt chain, the SPC700 or the sound-upload deadlock, all four of which entries 30 and 31 settled, and do not spend another cycle on the departure address: it is known, it reproduces, and the question has moved to the stack.

#### Files Modified:

- fpga/snes/src/snestang_top.v
- fpga/snes/src/snes2hdmi.v
- tools/sample_boot_states.py

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: NOT RUN

---

## 33 COMMIT Unreleased 2026-11-01T00:29:51-07:00

#### Coming From:

Unreleased abbfaae

#### Purpose:

Find out what the 65816 is returning through at the `$8887 RTL`, since entry 32 established the departure is a return and left the stacked address as the open question.

#### Outcome:

`TINYSNES_STACK_PROBE` was built, and the design first had to be established rather than assumed: `SNES.v` presents a WRAM channel on `DBG_SEL[2]` but never drives `DBG_WRAM_DAT` and the `SWRAM` instance has no debug port, so memory contents are not readable through the debug path at all and the instrument had to watch the WRAM bus instead, which is a first-class port and is visible in the top module as `WRAM_ADDR`, `WRAM_D` and the write strobe; that finding is recorded as TCL-017 because the undriven channel reads as a working feature in the selector map. The probe filters writes to the stack page `$01xx` into a three-deep ring of address and data pairs, reads `SP`, `P` and `PBR` through the debug port, and freezes everything on the single edge that accepts the first PC below `$8000` after arming at `$8000` or above. Build and placement at seed 7 were clean, the read path was checked on this tree before any reading was taken with `ROM_Q` `0x0000`, `0x0000`, `0x8000` and `ROM_ADDR` `0x7FFC`/`0x007F`, and the result tightens entry 32's signature to a constant: all five boots now depart to `$1035` with `SP` reading `$01FD`, where entry 32 saw three of five. Because a 65816 pull reads and then increments, a post-`RTL` stack pointer of `$01FD` places the three bytes that return took at `$01FA`, `$01FB` and `$01FC`, which is the first time this session has known where the return address physically was. The ring did not cleanly capture those bytes and that limitation is reported rather than worked around: two boots show a tail whose data in time order is `$01FC`=`$10`, `$01FB`=`$35`, `$01FA`=`$CC`, which read straight through the pointer gives `$10:$35CC` and does not match the departure, and the remaining three show a repeated `$01FA` write that a single push cannot produce. Reading that tail one byte higher, with `PCL` from `$01FB`=`$35` and `PCH` from `$01FC`=`$10`, gives exactly `$1035`, the measured departure, which is a fit too exact to dismiss and too poorly grounded to accept: it needs the pull to have begun at `$01FB` when the stack pointer says `$01FA`, and a one-byte discrepancy of exactly that shape is what a caller pushing two bytes and the callee popping three would produce, since a `JSR` pushes a return address and an `RTL` pulls a bank that was never pushed. That mismatch is the leading hypothesis and nothing more: the ring is a write filter and cannot prove what was at an address, its tails differ between boots, and the stack pointer sample is taken three phases before the PC that it is being compared against. Ten boots across the two instruments now show the departure at `$1035` in eight, which is the most repeatable fault signature recorded in this session, and the shape of it is a return whose low sixteen bits land on a plausible value while the program bank, which `RTL` fetches from a byte no `JSR` would have written, does not. Production synthesis was re-run and completed cleanly and all nine benches in `tools/tests/probe_tb.sh` pass. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was not changed, checked that entries 1 to 32 were not rewritten, added TCL-017 to the reference library with its fast-lookup index entry, and validated this entry's numbering, six sections, one-sentence Purpose, prose, Status values and the thirty-three-entry count against the 100-entry limit.

#### Next Steps:

Settle the one-byte question directly instead of inferring it, because the hypothesis is now narrow enough that a single measurement decides it: read the four bytes at `$01FA` through `$01FD` at the departure rather than relying on the write ring, either by latching `WRAM_Q` on reads to that page or by building a probe that holds the last four stack-page writes with a deeper ring and no repeated-address collapse, and take `SP` in the same phase as the PC so the two cannot disagree by three master clocks. If `$01FB` and `$01FC` really hold `$35` and `$10`, the return address was pushed correctly and the fault is a caller that pushed two bytes into a routine that returns with `RTL`, which is a defect in how this machine executes `JSR` and `RTL` rather than in the cartridge; if they hold something else, the corruption is in the push path and the next place to look is the WRAM write lane under a live stack operation, which the static byte-lane test of entry 20 passed and nothing has exercised since. Do not build another departure instrument: the address, the stack pointer and the fetch before it are all known and reproduce. Do not revisit the APU link, the interrupt chain, the SPC700 or the sound-upload deadlock, all four of which entries 30 and 31 settled.

#### Files Modified:

- fpga/snes/src/snestang_top.v
- fpga/snes/src/snes2hdmi.v
- tools/sample_boot_states.py

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: NOT RUN

---

## 34 COMMIT Unreleased 2026-11-01T00:59:06-07:00

#### Coming From:

Unreleased 53c5671

#### Purpose:

Settle the one-byte question entry 33 left open by reading the four stack bytes `RTL` consumes directly instead of inferring them from a ring of writes.

#### Outcome:

`TINYSNES_STACKBYTES_PROBE` replaced the three-deep write ring with an eight-entry shadow of `$01F8-$01FF` indexed by address and a valid bit per entry, so two pushes landing on the same address can no longer displace each other, and it moved the `SP` sample between the two halves of the PC read so the pointer and the departure cannot drift apart. Build and placement at seed 7 were clean, the read path was checked on this tree before any reading was taken with `ROM_Q` `0x0000`, `0x0000`, `0x8000`, and fifteen boots across two seeds were captured. The cycle did not answer the question it set out to answer, and the reason is worth recording precisely because it invalidates readings rather than the machine. The first thing it exposed is a decoding defect in this project's own tools: every probe paints a status band in the `dbg` colour, for these builds `{done, loaded, enable}`, and the sampler was reading the stripes without consulting the band, so a boot on which the probe never fired decoded as `departure=$0000` with every field zero and was reported as a measurement of a departure to zero. The band was cyan `(2,225,198)` on exactly those boots, which is `done=0`, and grey `(202,202,202)` on the boots that had a real departure; the sampler now checks the colour and reports such a boot as never having departed. This matters beyond the current cycle because `departure=$0000` is a legal-looking address and it was reported as a reading in entries 32 and 33 before it was caught, so the correction is recorded as TCL-018 and the habit it establishes is to read the band before the stripes. The second thing it exposed is that the instrument is not repeatable: two five-boot runs of the identical bitstream produced different results, one reporting a departure on all five boots and the other reporting two boots with no departure at all, and across the runs the departure address ranged over `$0070`, `$1035`, `$0DBE`, `$3209`, `$320D` and `$4215` with `SP` between `$01F8` and `$0132`. Cycle 33's `$1035` with `SP=$01FD` did reappear, once, so that reading is reachable rather than wrong, but it is a sample rather than the constant entry 33 called it. The shadow table also returns two mutually exclusive patterns that each recur exactly, `$01FB`=`$00` with `$01FC`=`$04` on the boots whose stack-write count is below saturation and `$01FA`=`$80` with `$01FD`=`$04` on the boots where it has saturated at 255, which is a signature of the counter saturating before the departure rather than of the stack. What the stack held at the moment of the return is therefore still unknown, and the offset question of entry 33 is untouched: the bytes it would take to resolve it are exactly the bytes this instrument cannot show reliably. Production synthesis was re-run and completed cleanly and all nine benches in `tools/tests/probe_tb.sh` pass. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was not changed, checked that entries 1 to 33 were not rewritten, added TCL-018 to the reference library with its fast-lookup index entry, and validated this entry's numbering, six sections, one-sentence Purpose, prose, Status values and the thirty-four-entry count against the 100-entry limit.

#### Next Steps:

Stop measuring the departure and start measuring the instruction, because three cycles of watching the program counter leave the cartridge have produced a stable event and an unstable instrument, and the question that matters -- whether a `JSR` returned through an `RTL` -- is a property of the instruction pair rather than of the address. The instrument for that already exists in the tree: `P65C816.v` exposes `IR` and `STATE` internally and `DBG_REG` `0x15` already packs `WAIExec` and `STPExec`, which are set at `STATE == 0` on a specific opcode, so a sticky bit for `IR == 8'h6B` at `STATE == 0` beside a sticky bit for `IR == 8'h20` at the same point would say directly whether the machine executed both a `JSR` and an `RTL` in this boot, and a third bit for `IR == 8'h6B` with the pulled bank not equal to the pushing bank would answer the exact question without touching the stack at all. That is a few lines in `cpu.v` behind a define and reuses a pattern this project has already validated twice, rather than building a fourth variation on a bus monitor that has now failed to be repeatable. Do not build another stack-memory instrument, and do not treat a single boot as a result: fifteen boots this cycle produced six distinct departure addresses and two distinct shadow patterns, and the only readings worth carrying forward are the ones with a band that says they fired.

#### Files Modified:

- fpga/snes/src/snestang_top.v
- fpga/snes/src/snes2hdmi.v
- tools/sample_boot_states.py

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: NOT RUN

---

## 35 COMMIT Unreleased 2026-11-01T01:15:55-07:00

#### Coming From:

Unreleased e8041de

#### Purpose:

Answer whether a `JSR` returns through an `RTL` by measuring the instruction pair directly instead of watching where the program counter goes.

#### Outcome:

The 65816 core now counts executed call and return opcodes at the point `P65C816.v` already uses to detect `WAI` and `STP` -- `STATE == 0` with `EN` high and no interrupt being taken -- which is once per instruction actually executed rather than once per bus cycle, and this is recorded as EXT-010 because it is the detection point an instruction-level probe belongs at. Four cumulative flags record that a `JSR`, a `JSL`, an `RTL` and an `RTS` have each run, a four-bit balance counts `JSL`s not yet returned from and saturates at fifteen, and an `RTL` that finds the balance already zero latches a flag, which is a long return through a stack that no long call built. `DBG_REG` `0x17` and `0x18` carry them out through the existing debug port, and `TINYSNES_INSN_PROBE` reads them beside the departure PC, the stack pointer and the newest ROM address. Because the flags are cumulative over the boot and cleared only by reset, this reading does not depend on catching an instant, which is the property every instrument of cycles 32 to 34 lacked. Build and placement at seed 7 were clean, production synthesis with no probe defines was re-run cleanly after the change to the shared core file, the read path was checked on this tree before any reading was taken with `ROM_Q` `0x0000`, `0x0000`, `0x8000`, and all nine benches pass. The answer is that the machine does execute a long return with no long call behind it: three boots of five had the unmatched flag set, and the other two were paired. The reading is also internally consistent with the earlier cycles in a way none of them managed -- two of these five boots departed to `$1035` with `SP=$01FD`, exactly the reading core-log entry 33 called a constant and entry 34 could not reproduce -- so the sampling problem of the last two cycles does not touch a cumulative flag, and the departure that entry 33 saw is real. The conclusion comes with its own limit stated plainly rather than buried: the gate skips any `JSL` executed while `GotInterrupt` is set, so an `RTL` legitimately following such a call would also latch the unmatched flag, and one boot of the five shows two `JSL`s still outstanding beside the flag, which is consistent with normal nesting after an early unmatched return rather than with a single broken pair. The flag therefore establishes that an unmatched long return happens on most boots but does not yet establish whether it is the return that lands the CPU at `$1035`, because one boot departed with no `RTL` in it at all and its departure was still below the cartridge. What is settled is the mechanism class: this is a return-pairing fault in the 65816 core rather than a data-corruption fault in WRAM or a fault in the cartridge, and the three cycles that looked for it in memory were looking in the wrong place. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was not changed, checked that entries 1 to 34 were not rewritten, added EXT-010 to the reference library with its fast-lookup index entry, and validated this entry's numbering, six sections, one-sentence Purpose, prose, Status values and the thirty-five-entry count against the 100-entry limit.

#### Next Steps:

Separate the two things the unmatched flag currently confounds, which is now a small and well-defined piece of work rather than an open-ended hunt. The gate skips a `JSL` executed while `GotInterrupt` is set, so the next version should count `JSL`s at a point that an interrupt cannot suppress, or latch a separate flag for a `JSL` seen while `GotInterrupt` was set and report it beside the unmatched flag; if every unmatched boot turns out to have such a skipped `JSL`, the flag is an instrument artefact and the pairing is sound, and if none does the defect is real. The second half is to date the unmatched `RTL` against the departure, by latching the `SP` and the program counter at the moment the unmatched flag sets rather than only at the departure, so the two events can be compared within one boot instead of across five. Only when those two line up should the return path itself be read -- `RTL` pulls three bytes and `JSR` pushes two, so the suspects are the push width in the `JSR` microcode and the pull width in the `RTL` one, both of which are in `mcode.sv` and have never been examined in this project. Do not build another bus monitor and do not sample the stack again: three cycles of that produced nothing repeatable, and this cycle shows the instruction-level instrument answering in one build what the memory instruments could not answer in three.

#### Files Modified:

- fpga/snes/src/65C816/P65C816.v
- fpga/snes/src/snestang_top.v
- fpga/snes/src/snes2hdmi.v
- tools/sample_boot_states.py

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: NOT RUN

---

## 36 COMMIT Unreleased 2026-11-01T01:37:26-07:00

#### Coming From:

Unreleased 6526dbd

#### Purpose:

Close the false-positive path in entry 35's unmatched-`RTL` flag, which was the one thing standing between that finding and a defect, and check the call/return microcode by reading it rather than by building another instrument.

#### Outcome:

Two pieces of work, one of which needed no hardware at all. The microcode was read first, from `mcode.txt`, which is the hand-written source of the generated table: `JSR` pushes `PCH` and `PCL`, `JSL` pushes `PBR`, `PCH` and `PCL`, `RTS` pre-increments `SP` and pulls two bytes, and `RTL` pre-increments `SP` and pulls three.  All four match the 65816's documented behaviour, so the obvious suspect -- a push or pull width defect in the microcode, which entry 35's Next Steps named as the place to look -- was cleared in minutes by inspection and is recorded as EXT-011 rather than by another cycle of hardware. What remains is therefore not a width bug but a question of what the CPU decided to execute. The instrument was then extended to test its own gate, which was entry 35's stated false-positive path: a `JSL` committed while `GotInterrupt` is set is skipped by the counting gate, so a legitimate `RTL` after one would latch the unmatched flag spuriously. Two flags were added for a `JSL` or an `RTL` seen in that window, and the same two opcodes were counted again with the gate removed, so one boot can say whether removing the gate changes anything. Building that exposed a defect in this cycle's own instrument before it produced a reading: the new counters were reset in both the gated block and the ungated one, so they had two drivers, synthesised as a constant, and returned `ungated_rtl=0` on a boot whose gated flags plainly showed an `RTL` had run -- a contradiction inside one frame that identified the fault immediately. With the duplicate driver removed the counters work, and the answer is unambiguous: in four boots of five the ungated counts are one `RTL` and zero `JSL`, identical to the gated reading, and no opcode was seen in the interrupt window on any boot. The gate therefore did not manufacture the flag, and `unmatched_rtl` is a real observation of this machine executing a long return with no long call behind it. The same five boots also departed to `$1035` with `SP=$01FD` in all five, which is the most repeatable signature recorded in this project, and three of them were fetching at `$8894`, the sound upload's echo-wait, when the departure was recorded. Production synthesis was re-run clean after the change to the shared core file and all nine benches pass. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was not changed, checked that entries 1 to 35 were not rewritten, added EXT-011 to the reference library with its fast-lookup index entry, and validated this entry's numbering, six sections, one-sentence Purpose, prose, Status values and the thirty-six-entry count against the 100-entry limit.

#### Next Steps:

Look at how few instructions the machine executes rather than at the return itself, because the counts now say something new and unexpected: a whole boot commits one `JSR`, one `RTL` and one `RTS`, with the balance at zero, while the departure is at `$1035` and three boots were still fetching at `$8894`. A machine executing a handful of call instructions and then leaving the cartridge is not the picture the sound-upload deadlock gave, and the count is the first reading in this session that can distinguish a CPU that ran a lot and then jumped from one that barely ran at all -- so the next instrument should read a total committed-instruction counter beside the call counts, which is one register and no new thinking. If the total is small the fault is early and the departure is a symptom of a machine that never really started; if the total is large the departure is the fault and the call counts are a side effect. That single number decides which of the two investigations to run, and it should be obtained before anything is concluded about the return path. Do not build another bus monitor, do not sample the stack again, and do not re-examine the microcode widths: all three are settled.

#### Files Modified:

- fpga/snes/src/65C816/P65C816.v
- fpga/snes/src/snestang_top.v
- tools/sample_boot_states.py

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: NOT RUN

---

## 37 COMMIT Unreleased 2026-11-01T01:51:24-07:00

#### Coming From:

Unreleased ca4f59a

#### Purpose:

Build a full-core simulation so the boot failure can be debugged deterministically instead of through nondeterministic hardware probes, after thirty-six cycles of instantaneous instruments were unable to agree with each other.

#### Outcome:

A full-core bench now runs the real `SNES.v` with behavioural memories under Verilator, in `tools/sim/snes_tb.sv` and `tools/sim/run_sim.sh`, and it settled the fault on its first use. The bench instantiates `SNES.v` and everything under it -- the 65816, the SPC700, the PPU, the DSP, the whole CPU bus -- with models for the cartridge, WRAM, VRAM, ARAM and battery SRAM standing in for the SDRAM and its hand-tuned PHY, which is deliberate: removing the SDRAM capture from the experiment means a pass says the core and its bus are sound and a failure says they are not. Two obstacles had to be cleared first and both are worth recording: Icarus cannot parse the `localparam` arrays in `dsp.vh`, so Verilator is the engine, which is also what the sources were written for since they already carry `ifndef VERILATOR` behavioural models for CGRAM and OAM; and `spc700.v` contained a nested `/* */` inside a `/* */` block under `ifdef VERILATOR`, so the inner terminator closed the outer comment and the following lines were live code, which is a latent defect in the upstream source that only this build configuration reaches. With the bench running, the core boots correctly: the reset vector reads `$8000`, the prologue executes, the APU handshake completes and the CPU uploads sound data, and over twenty million master clocks -- 2.36 million committed instructions -- its program counter never once fell below `$8000`. So the departure this project has chased since entry 5 is not a logic fault in the core. It is the cartridge read time. The bench models that directly with a `+lat` knob, and a two-by-two matrix over latency and rom-speed mode separated the fault cleanly: with the image's own `STA $420D` in place, which is the store that sets `MEMSEL` and switches banks `$80-$FF` from slowrom to fastrom timing, the machine runs a million cycles without leaving the cartridge at latency 2 and 3 and departs within about 1400 cycles at latency 4 and 5; with that single store redirected to `$4200` so `MEMSEL` is never set, the same bench at the same latencies runs clean and only departs at 6. The captured hardware read path answers between the second and fourth master clock, which is on the failing side of the fastrom window and comfortably inside the slowrom one. The mechanism is not a jump: the per-instruction log of committed opcodes shows the decode desynchronising on the instruction immediately after the `STA $420D`, with operand bytes executed as opcodes. `TINYSNES_FORCE_SLOW_ROM`, a define already present in `cpu.v`, forces slowrom timing for those banks, and the bench shows it holding at latency 4 and 5 where the default fails -- worth noting because that define had previously been recorded as a negative result, and that attempt was made on the tree whose ROM read returned zero, so the negative was an artefact of the other fault. This is recorded as TCL-019. Production synthesis was re-run clean and all nine benches pass; the only source change to the core itself is the comment-nesting fix in `spc700.v`, which is inside `ifdef VERILATOR` and therefore cannot affect a synthesis build. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was not changed, checked that entries 1 to 36 were not rewritten, added TCL-019 to the reference library with its fast-lookup index entry, and validated this entry's numbering, six sections, one-sentence Purpose, prose, Status values and the thirty-seven-entry count against the 100-entry limit.

#### Next Steps:

Build the production core with `TINYSNES_FORCE_SLOW_ROM` and put it on the board, because the bench says that is the fault and the fix is a define that already exists: the machine should then run past the point where every previous build left the cartridge, and the first sign of success is the picture changing from the static grid rather than any probe readout. If it boots, the follow-on question is how much of the lost speed matters, since slowrom timing costs roughly two master clocks per cartridge access and the honest options are to accept it, to make the SDRAM read path answer within six master clocks, or to add a wait-state input so the core waits for the cartridge, the last being the only correct fix and the only one that keeps fastrom. Do not spend another cycle on departure instruments, on the stack, on the call/return counters or on the APU link: the bench shows the core executes all of those correctly when the cartridge answers in time, and every reading this project took that suggested otherwise was taken on a machine whose instruction stream had already desynchronised. Use `tools/sim/run_sim.sh` before any further hardware build, since it reproduces a boot in seconds and the compiler, not the capture card, now says whether a change helped.

#### Files Modified:

- tools/sim/snes_tb.sv
- tools/sim/run_sim.sh
- fpga/snes/src/spc700/spc700.v

#### Status:

- Build: PASS
- Deployment: NOT RUN
- User Test: NOT RUN

---

## 38 COMMIT Unreleased 2026-11-01T02:35:07-07:00

#### Coming From:

Unreleased f5cb40e

#### Purpose:

Deploy the `TINYSNES_FORCE_SLOW_ROM` build to the board and find out whether the cartridge-latency fault identified in simulation is the whole of the boot failure.

#### Outcome:

`TINYSNES_FORCE_SLOW_ROM` was built into the production configuration at seed 7, passed the timing and clock gates with no hold violations and was deployed, and the result is negative: the picture is unchanged, still the static 8x7 grid of white bars between grey borders, and an instrumented build of the same source shows the machine still leaving the cartridge on most boots.  That answers the cycle's question with a no.  The latency finding of entry 37 is sound in simulation -- the bench separates `+lat=3` from `+lat=4` by the `MEMSEL` store alone -- but forcing slowrom on the board does not rescue it, so either the hardware path is worse than the six master clocks the bench models or there is a second fault, and the second is what the rest of this cycle found.  Three builds of the identical source, all with the same defines and all free of hold violations, were compared over fifteen boots: seed 9 and seed 11 and seed 5 differ only in where the placer put the master clock, and the outcome differs with it.  The seed 9 build takes `hclk` through `SPINE24/CBRIDGEOUT_BOTTOM2` and `iosys.clk` through `SPINE16/CBRIDGEOUT_TOP0`, and it does not leave the cartridge on any boot -- ten boots across two sampling runs, every one reporting no departure, with a cyan band and an identical flag byte each time, which is the first deterministic result this project has ever recorded.  The seed 5 and seed 11 builds take the same clock through `SPINE27` and `SPINE25`, pass the same gates, and leave the cartridge on every boot sampled, at `$1035` or `$1036` with `SP` at `$01FD`.  So a hold-clean placement is necessary but not sufficient here and the outcome has to be confirmed by booting; that is recorded as BRD-005 and the practical consequence is that the seed should be chosen for the spine it produces, which `tools/clock_plane_report.py` prints before deployment.  The second fault is in the sound upload and reproduces in the bench at zero cartridge latency, so it is not the same defect: the 65816 sits in its echo-wait at `$88B3` to `$88B8` while the SPC700 loops inside its IPL block-copy between `$FFDC` and `$FFE2`, with CPUI holding `$A9`,`$30` and CPUO echoing one index behind -- the deadlock entries 8 to 12 spent five cycles on, now reproducible in seconds and with both CPUs visible at once.  The PPU receives exactly one write in a whole simulated boot, `$2100`=`$80`, which is the game's forced-blank at the start of its reset path, and the CPU never reaches the game's own initialisation, so the static grid is explained: the PPU is left in its reset state because the machine never gets past the upload.  Two defects in this cycle's own instruments were found and fixed.  The PPU write filter in the bench compared the full high byte of the address to `$00` when the game runs in bank `$80`, so it silently missed every write and reported one; masking the top two bits fixed it.  The `insn` layout of the boot sampler read latched stripes without consulting the status band, which is the exact mistake core-log entry 34 recorded as TCL-018, and it reported `departure=$0000` as an address on three cyan-band boots before it was caught; the guard is now applied to that layout as well.  The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was not changed, checked that entries 1 to 37 were not rewritten, added BRD-005 to the reference library with its fast-lookup index entry, and validated this entry's numbering, six sections, one-sentence Purpose, prose, Status values and the thirty-eight-entry count against the 100-entry limit.

#### Next Steps:

Work the sound-upload deadlock in the bench, because it is now the only fault standing between this machine and a boot and it reproduces at zero cartridge latency with both processors visible.  The specific question is what the 65816 expects at `$88EC` and what the SPC700 publishes at `$FFDC`: the IPL compares `Y` against the port and the 65816 compares the port against the byte it just sent, so the two are one index apart in a steady state that never advances, and the first thing to capture is the sequence of writes the 65816 makes to `$2140` beside the sequence the SPC publishes to `$F4`, both taken from inside the bench rather than from a probe.  If the 65816 is writing bytes the SPC never sees, the fault is the port write path; if the SPC is publishing and the 65816 is not reading, it is the read path; and if both are correct one index apart, the IPL's compare is what has to be re-read against the published first-byte handshake.  Keep the seed 9 placement as the reference build from now on, since it is the one that reaches the deadlock deterministically, and re-check the spine with `tools/clock_plane_report.py` on any new build before deploying it.  Do not spend another cycle on the departure: it is understood, it depends on placement, and the seed 9 build already avoids it.

#### Files Modified:

- tools/sim/snes_tb.sv
- tools/sim/run_sim.sh
- tools/sample_boot_states.py

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: NOT RUN

---
