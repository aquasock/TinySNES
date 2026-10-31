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
