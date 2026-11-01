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
