# TINYSNES TECHNICAL REFERENCE

> **Project:** TinySNES
> **Purpose:** The authoritative lookup for externally defined facts this project depends on: the board's FPGA and pins, the upstream SNES core this project vendors, the UART contract of the cores TinyTang boots, and the behaviour of the open-flow tools.
> **Authority:** Per `.ai/core.md`, consult this file before looking anything up online, and open the record behind any hardware fact before acting on it. A record is authoritative to the extent of its `status` and cited `sources`. When a better or newer source is found online, add or revise a record and notify the user.

This file records what an outside source (a schematic, a vendor toolchain, an
upstream repository) says, plus observations made in this project's tools that
confirm or refute it. It does not record project history or build results; those
belong in `core-log.md`. It does not record design choices unless an external
fact forces them.

Some records are negative results — facts about what this toolchain *cannot*
express, or ruled-out causes of a fault. They are recorded because each cost a
session to establish: see TCL-002, TCL-004, TCL-005, TCL-009, TCL-011 and BRD-002.

---

## 1. AI operating rules

```yaml
schema_version: 1

record_kinds:
  - DEVICE      # FPGA silicon: part, revision, capacity
  - BOARD       # Tang Console 138K board: pins, clocks, fitted parts
  - PROTOCOL    # the BL616 <-> loaded FPGA core UART contract
  - EXTERNAL    # interface contracts owned by other projects
  - TOOLCHAIN   # yosys/slang, nextpnr-himbaechel, apicula, Gowin cell libraries

statuses:
  VERIFIED:   "Primary source cited AND confirmed in this project's tools or on its hardware."
  SOURCED:    "Primary source cited; not yet confirmed in this project."
  INFERRED:   "Derived from secondary sources, reverse inspection, or consistent observation; no primary source. Flag before relying on it."

rules:
  - "One fact or one tightly coupled fact group per record."
  - "Every record cites at least one source with enough detail to re-check it: repository path plus commit, file, symbol, or tool version."
  - "Separate what the source says (statement) from what it means for this project (consequence)."
  - "Diagnostic or implementation limits chosen by this project are never recorded as standard or device limits."
  - "A record holds what is true now. When a fact changes or proves wrong, edit the record in place: revise statement and consequence, update verified_date and sources, and end verification with 'Revised <date> (core-log entry N): <what changed>'. Git and core-log.md keep the history; this file does not."
  - "Never reuse a record_id. When a record is retired or folded into another, move its id to section 8 with the record that now holds its facts."
  - "An INFERRED record must say how it was inferred, in verification."
  - "A negative result is a fact. Record what the toolchain cannot do with the same rigour as what it can."
  - "When an online lookup was needed because this file had no answer, add the finding here with the existing syntax, then notify the user if the source is newer or more valid than a record already here."
  - "Use technical names (GW5AST-138, GW5AST-138C, BL616, nextpnr-himbaechel, slang). Conversational names are not used in this file."
```

---

## 2. Topic catalog

| Topic | Kind | Range | Covers |
|---|---|---|---|
| DEV | DEVICE | DEV-0xx | part number, revision, capacity, identification |
| BRD | BOARD | BRD-0xx | pins, SDRAM, HDMI, UART, button/LED wiring |
| PRO | PROTOCOL | PRO-0xx | BL616 UART link, core identity, ROM loading |
| EXT | EXTERNAL | EXT-0xx | SNESTang upstream, its clock plan, hdl-util HDMI |
| TCL | TOOLCHAIN | TCL-0xx | yosys/slang, nextpnr-himbaechel, apicula, Gowin cell libraries |

---

## 3. Active routing

| Question | Consult first | Fast records |
|---|---|---|
| Which part does the open flow build for, and which revision? | DEV | DEV-001 |
| How much logic and block RAM does the device have? | DEV | DEV-002 |
| Which pins carry SDRAM, HDMI, UART and the button? | BRD | BRD-001, BRD-002 |
| Why is `O_sdram_cke` not in the constraint file? | BRD | BRD-002 |
| Which core ID does a SNESTang-derived core report, and does TinyTang know it? | PRO | PRO-001 |
| What clocks does SNESTang need, and from what PLL parameters? | EXT | EXT-001 |
| Which upstream files does the `console138k` build require? | EXT | EXT-001 |
| Why can this project not read VHDL? | TCL | TCL-001 |
| Why do cell libraries need both `-v` and `--blackboxed-module`? | TCL | TCL-001 |
| Which SDC commands does nextpnr-himbaechel reject? | TCL | TCL-002 |
| Why does `get_nets {mclk}` match nothing? | TCL | TCL-003 |
| Why did `module ALU` fail to elaborate, and why did `MUX2` fail to place? | TCL | TCL-004 |
| Why do `$fdisplay` and the vendor `` `error `` directive fail synthesis? | TCL | TCL-005 |
| How must the HDMI clocks be generated and placed? | TCL | TCL-006 |
| How does TangCore load a SNES ROM? | EXT | EXT-003 |
| Why does the machine show a static tile grid after a ROM loads? | TCL | TCL-007, TCL-008 |
| Which diagnostic build shows what, and what should it read? | TCL | TCL-008 |
| How do I read a CPU register from the bench without changing upstream? | EXT | EXT-004 |
| The 65816 is stuck in `CMP $2140`: which side of the APU link failed? | EXT | EXT-005 |
| What does the IPL actually do, instruction by instruction? | EXT | EXT-006 |
| Why does the 65816 stop: is it waiting, or lost? | EXT | EXT-007 |
| Which interrupt is missing, and is the PPU generating vblank? | EXT | EXT-008 |
| Why did an ODDR SDRAM clock kill the picture? | TCL | TCL-009 |
| How long does a CPU-port ROM read take, and when does the CPU latch it? | TCL | TCL-010 |
| Why did a probe readout carry a different value in every row? | TCL | TCL-011 |
| Why did a diagnostic build draw nothing at all? | TCL | TCL-012 |
| Which clock-plane pips are safe on this board? | DEV | DEV-004 |
| Why is a clock on general routing instead of the global network? | TCL | TCL-015 |
| A clock reaches no bridge pip at all, and every gate still passed | DEV | DEV-004 |
| Why did a gated flag silently not apply? | TCL | TCL-014 |
| Why does a sticky history bit always read as set? | TCL | TCL-013 |
| How do I load a core in one-wire versus two-wire? | BRD | BRD-003 |
| How does a core image or ROM get onto the card? | BRD | BRD-004 |
| Can a cartridge coprocessor be used for sound, as on the Famicom? | EXT | EXT-013 |

---

## 4. Fast lookup index

DEV-001 part and revision · DEV-002 capacity · DEV-004 clock-plane bridge pips
BRD-001 SDRAM pins · BRD-002 clock enable
PRO-001 core ID 2 versus TinyTang's table
EXT-001 SNESTang console138k file list and clocks · EXT-002 hdl-util HDMI
TCL-001 slang front end and cell-library shim · TCL-002 SDC subset ·
TCL-003 net renaming · TCL-004 cell-name collisions · TCL-005 unsupported constructs ·
TCL-006 HDMI clock shape and placements · TCL-007 SDRAM capture and the fetch path
TCL-008 diagnostic builds · TCL-009 ODDR costs the HDMI route · TCL-010 read latency and the CPU's latch ·
TCL-011 a probe bus must be latched to be photographed · TCL-012 `elsif` with two macros selects nothing ·
TCL-013 a sticky bit must be armed against its reset value · TCL-015 PLL outputs with no clock-plane pip ·
TCL-016 a ROM-address ring names a hot address, not a fetch sequence ·
TCL-017 the WRAM debug channel is selected but never driven ·
TCL-018 the display band says whether a snapshot fired ·
TCL-019 the fastrom access window and the full-core bench ·
BRD-005 placement, not timing, decides whether this netlist boots ·
EXT-012 the APU handshake completes and a boot takes 30M clocks ·
EXT-010 the opcode-commit point for instruction-level probes ·
EXT-011 JSR/JSL/RTS/RTL microcode push and pull widths ·
EXT-013 the cartridge DSP is math-only, so no cart expands audio
EXT-003 TangCore ROM loader · BRD-003 one-wire and two-wire loading · BRD-004 console file transfer
EXT-004 the SCPU debug port as a bench instrument · EXT-005 the APU port banks and IPL boot ·
EXT-006 the IPL block-copy protocol · EXT-007 65816 WAI/STP halts and the status byte · EXT-008 the interrupt chain and IsBRKInterrupt ·
EXT-009 the LoROM cartridge window and the PC >= $8000 test

---

## 5. Records

```yaml
- record_id: DEV-001
  kind: DEVICE
  topic_id: DEV
  title: "The open flow builds for GW5AST-138C; upstream SNESTang's own target says device version B"
  status: SOURCED
  verified_date: 2026-10-30
  statement: "tools/build_tinysnes.sh names the part GW5AST-LV138PG484AC1/I0 with family GW5AST-138C, which is what TinyTang, TinyNES and TinyGBC build for. SNESTang's build.tcl, in its console138k branch, sets the same part string with '-device_version B'. This project's .ai/core.md names the target as GW5AST-LV138PG484AC1/I0, device revision C."
  consequence: "The part string matches upstream, so pin assignments transfer unchanged. The revision field does not: B and C select different chip databases on the apicula side, and nothing in this project has yet demonstrated that a bitstream built for GW5AST-138C loads on this board. Treat the revision as unresolved rather than as C by inheritance."
  sources:
    - "SNESTang commit 5f0ef19, build.tcl, console138k branch: 'set_device GW5AST-LV138PG484AC1/I0 -device_version B'"
    - "TinyTang commit 207f9af, tools/desktop_open/build.sh: DEVICE_PART='GW5AST-LV138PG484AC1/I0', DEVICE_FAMILY='GW5AST-138C'"
    - "TinySNES .ai/core.md, Build Environment: 'Target: GW5AST-LV138PG484AC1/I0 / Device revision C'"
  verification: "Read from all three sources this session. Not confirmed against the board: no bitstream from this project has been loaded, and the JTAG IDCODE has not been read in this project."

- record_id: DEV-002
  kind: DEVICE
  topic_id: DEV
  title: "GW5AST-138C capacity as the apicula database reports it: 138,240 LUT4, 138,240 DFF, 340 BSRAM, 12 PLL"
  status: VERIFIED
  verified_date: 2026-10-30
  statement: "nextpnr-himbaechel's device utilisation report for GW5AST-LV138PG484AC1/I0 lists LUT4 138240, DFF 138240, BSRAM 340, PLL 12, IOB 324, OSER16 156, IDES16 156, CLKDIV2 24."
  consequence: "A SNESTang-class design uses a small fraction of it: the first routed netlist used 21,638 LUT4 (15%), 5,359 DFF, 53 BSRAM and 3 PLL. Capacity is not the constraint on this port; timing and clock distribution are."
  sources:
    - "nextpnr-himbaechel, --device GW5AST-LV138PG484AC1/I0, device utilisation block of the run log (available in build/tinysnes/nextpnr.log on the bench, not committed)"
  verification: "Printed by the tool during this session's place-and-route runs."

- record_id: BRD-001
  kind: BOARD
  topic_id: BRD
  title: "SNESTang's console.cst and TinyNES's ae350_soc.cst agree on the board's SDRAM, HDMI and UART pins"
  status: VERIFIED
  verified_date: 2026-10-30
  statement: "Both constraint files place sys_clk on V22, the HDMI TMDS pair on G15/G16 with data on J14/H14, J15/H15, K17/J17, the BL616 UART on V14 (rx) and U15 (tx), and SDRAM with clk B17, cs_n F21, ras_n F16, cas_n E17, we_n D16, ba F15/C20, a[0..12] D19/E19/C19/C18/E16/D15/D14/A19/A18/C17/D20/D17/B18, dqm F14/F13 and dq[0..15] E14/E13/C15/C14/B13/C13/A14/A13/B21/A21/B20/A20/A15/A16/B15/B16."
  consequence: "fpga/snes/tinysnes.cst is SNESTang's file with only the USB HID, DualShock and SNES-controller pins removed, so every pin this core uses is one of the two upstream projects' pins and no pin was invented. TinyNES's file is the second opinion, and it agreed on every pin compared."
  sources:
    - "SNESTang commit 5f0ef19, src/boards/console.cst (the file its console138k build uses)"
    - "TinyNES, fpga/ae350_soc/ae350_soc.cst, 'Dock connector J9 (SDRAM0), Sipeed SDRAM module (W9825G6KH-6)'"
  verification: "Compared line by line this session while filtering the file; the pin numbers listed above appear in both."

- record_id: BRD-002
  kind: BOARD
  topic_id: BRD
  title: "Neither upstream constraint file assigns a pin to O_sdram_cke"
  status: VERIFIED
  verified_date: 2026-10-30
  statement: "SNESTang's src/boards/console.cst has no IO_LOC for O_sdram_cke, and no SNESTang board file constrains a CKE pin at all. TinyNES's ae350_soc.cst likewise has no CKE entry, and neither design drives one. The signal is asserted by SNESTang's controller and left for the vendor fitter to place."
  consequence: "Gowin EDA placed the pin itself; nextpnr refuses to place an unconstrained top-level port, so this project assigns O_sdram_cke to W19 (PMOD1_IO0), which this core does not otherwise use. That assignment is a guess about a pin nothing on the board is known to read, and it is unverified until the board runs: it is the first thing to check if SDRAM misbehaves."
  sources:
    - "SNESTang commit 5f0ef19, src/boards/console.cst; grep for 'cke' over src/boards/*.cst returns nothing"
    - "TinyNES, fpga/ae350_soc/ae350_soc.cst: SDRAM pin block has no CKE line"
  verification: "Searched both files this session. nextpnr refused to place the port until the constraint was added ('ERROR: Unconstrained IO:O_sdram_cke_OBUF_O')."

- record_id: PRO-001
  kind: PROTOCOL
  topic_id: PRO
  title: "SNESTang's BL616 link reports core ID 2; TinyTang's firmware recognises only 0x50 and 0x54 for socket declarations"
  status: VERIFIED
  verified_date: 2026-10-30
  statement: "iosys_bl616 is parameterised by CORE_ID and snestang_top instantiates it with CORE_ID=2. TinyTang's pmod_sockets.cpp matches a socket core by ID against a two-entry table: TANG_INI_CORE_PHOSPHOR and TANG_INI_CORE_DESKTOP (0x54), the latter from desktop ABI 1.0; a bring-up core that also reports 0x50 has no ABI word and is not matched. The table's purpose is to give a loaded core its /tinytang.ini socket word."
  consequence: "A SNESTang-derived core can be loaded, and its own OSD and ROM loader will speak the TangCore command set, but TinyTang's firmware will not treat it as a socket core, so no tang.ini PMOD declaration is applied to it. That is harmless for this core as first configured (no VGA, no OLED, no I2S), and it becomes a real limitation the moment the PMOD sockets are wanted."
  sources:
    - "SNESTang commit 5f0ef19, src/snestang_top.v: 'iosys_bl616 #(.CORE_ID(2), .FREQ(21_484_000)) iosys'"
    - "TinyTang commit 207f9af, ports/bl616/phosphor/pmod_sockets.cpp: s_socket_cores[], TANG_INI_CORE_DESKTOP in ports/bl616/tang_ini.h"
  verification: "Read both sources this session; the firmware table is the only place a core ID is matched."

- record_id: EXT-001
  kind: EXTERNAL
  topic_id: EXT
  title: "SNESTang's console138k build: file list and clock plan"
  status: VERIFIED
  verified_date: 2026-10-30
  statement: "The console138k branch of build.tcl adds src/boards/console138k.v and console.cst, snes2hdmi.v, src/pll/gowin_pll_{27,hdmi,snes}.v, sdram_cl2_2ch.v, vram.v, vram_spb.v, usb_hid_host.v and pll_12.v on top of one device-independent file list, with top module snestang_top. Its clocks come from three PLL wrappers fed by the 50 MHz oscillator: gowin_pll_snes gives clkout0 50*40/93 = 21.505 MHz (mclk), clkout1 50*40/31 = 64.516 MHz (fclk, SDRAM) and clkout2 the same as clkout1 with 225 degrees of phase shift (fclk_p, which drives O_sdram_clk); gowin_pll_27 gives 27 MHz; gowin_pll_hdmi turns that 27 MHz into 27*55/4 = 371.25 MHz (hclk5) and 27*55/20 = 74.25 MHz (hclk, the 720p pixel clock). fclk is three times mclk, not four."
  consequence: "The clock plan is why this project's SDC declares mclk at 46.5 ns rather than the /4 relationship in SNESTang's own snestang.sdc, which was written for the Primer 25K where fclk is 85.9375 MHz. The same file list is what tools/build_tinysnes.sh reproduces, minus USB HID, DualShock, SNES controllers, pll_12, usb_hid_host and the PicoRV32 I/O system."
  sources:
    - "SNESTang commit 5f0ef19, build.tcl (console138k branch and the shared add_file list), src/pll/gowin_pll_*.v defparams"
  verification: "Read from build.tcl and the PLL defparams this session; the clock arithmetic was recomputed from the divider values."

- record_id: EXT-002
  kind: EXTERNAL
  topic_id: EXT
  title: "The HDMI transmitter is hdl-util's, and the copy in this tree is TinyTang's"
  status: VERIFIED
  verified_date: 2026-10-30
  statement: "SNESTang's src/hdmi2/ and snes2hdmi.v use hdl-util/hdmi (Sameer Puri, MIT), with the Gowin OSER10 path selected by `GW_IDE` and the Altera altlvds_tx path by ALTERA_RESERVED_QIS. SNESTang's own copy fails to elaborate in slang with 'non-blocking assignment to variable control_data is not supported after previous blocking assignment' and the matching packet_picker errors; TinyTang's fpga/desktop/hdmi/ copy of the same project elaborates and has run on this board."
  consequence: "fpga/snes/hdmi/ is TinyTang's copy, not SNESTang's, and the build passes -U SYNTHESIS -D GW_IDE so the OSER10 branch is selected. snes2hdmi.v's parameter list matches that copy (AUDIO_RATE, AUDIO_BIT_WIDTH) but not TinyNES's hdmi_silent variant, so the TinyNES copy is not a drop-in here."
  sources:
    - "SNESTang commit 5f0ef19, src/hdmi2/hdmi.sv and src/hdmi2/serializer.sv"
    - "TinyTang commit 207f9af, fpga/desktop/hdmi/*.sv; TinyTang fpga/desktop/README.md records that build as exercising HDMI on hardware"
  verification: "The failure messages are from this session's yosys runs with SNESTang's copy; the swap to TinyTang's copy removed them and synthesis then completed."

- record_id: EXT-005
  kind: EXTERNAL
  topic_id: EXT
  title: "The S-SMP's APU ports are two separate register banks, CPUI and CPUO, and the IPL boot is a four-way handshake over them"
  status: VERIFIED
  verified_date: 2026-10-31
  statement: "smp.v keeps CPUI[0:3] and CPUO[0:3] as distinct arrays: a CPU write to $2140-$2143 lands in CPUI[PA], the SPC700 reads CPUI[$00F4-$00F7], an SPC700 write to $00F4-$00F7 lands in CPUO, and the CPU reads $2140-$2143 from CPUO[PA].  The SMP's own debug registers expose them separately, 0x00-0x03 being CPUI and 0x04-0x07 CPUO, so a probe that reads only 0x00-0x03 measures one direction of the link.  The IPL ROM in the same file is the standard 64-byte dump at $FFC0-$FFFF: it clears ARAM, publishes $AA in port 0 and $BB in port 1, then loops exchanging data and block counters with the 65816, which in turn sits in `CMP $2140 / BNE` at $8891 of the loaded image."
  consequence: "Any statement about the APU link has to name the direction it was measured in.  A 65816 waiting for an echo after writing a byte, with CPUO still holding the initial $AA, means the SPC700 published once and never consumed what came next.  This is also the cheapest place to observe the SPC700 without a logic analyser: DBG_SEL[3] selects it, and A, X, Y, PC, PSW and SP are readable at 0x00-0x06 -- but see the trap below.  Measured on 2026-10-31 (core-log entry 8), the link carries data in both directions and the SPC700 does see the port: CPUO read $10BB with CPUI port 0 at $89 while the 65816 sat in the upload loop at $88EC, so the SPC had published the IPL's $BB at $FFCC and later written $10 to $00F4, and the 65816's own $89 was visible in CPUI.  The SPC700's PC was read as $F4B5-$F4D1 in that frame, which entry 8 took to mean it had taken the `JMP [$0000+X]` at $FFFB into uploaded code -- but core-log entry 10 measured a later boot with a purpose-built exit latch and found the SPC700 never leaving its IPL ROM at all, so that inference does not hold as a general statement and the boot-to-boot variation is the better explanation (see that entry).  The trap: the SPC700's A, X and Y are all $00 both while it waits at $FFCF (A is set to $00 at $FFC3 and Y is never written before the wait) and on a dead debug path, so those registers cannot separate a correct wait from a broken port and must not be used as the instrument for that question."
  sources:
    - "SNESTang commit 5f0ef19, src/smp.v: CPUI/CPUO arrays, the $00F4-$00F7 read and write paths, and the IPLROM array"
    - "SNESTang commit 5f0ef19, src/spc700/spc700.v: the debug case at DBG_REG 0x00-0x08, 0x03/0x04 being PC low and high"
    - "This repository, fpga/snes/src/snestang_top.v: the TINYSNES_APU_PROBE block and its field order"
    - "zelda.smc (1 MiB LoROM, SHA-256 75267ac610cba5ab0b4a4516a669fa43879552c15677dc6c6ca9e9c35b9dd1ac): $8888 the upload routine entry, $8891 the `CMP $2140` handshake, $889A the branch into the loop at $88CC, $88E9 `STA $2140` and $88EC `CMP $2140`"
  verification: "Read from the RTL on 2026-10-31 and then measured on the board (core-log entry 6): the APU probe read CPUI as 0x0080 and CPUO as 0xBBAA in the same frame, which is the observation the fault location rests on.  Revised 2026-10-31 (core-log entry 8): the board then read CPUO as $10BB, CPUI port 0 as $89, and the SPC700's PC at $F4xx while the 65816 was in the upload loop, which shows the port is seen and used in both directions; the A/X/Y trap was established by decoding the IPLROM at $FFC3-$FFCF and is why entry 7's proposed instrument was replaced.  Revised 2026-10-31 (core-log entry 10): a purpose-built exit latch found the SPC700 still inside its IPL ROM on a later boot, at $FFDA-$FFEA in the block-copy loop with CPUI reading $80, $92 and a $082A transfer address, so the two directions of the port are still proven but the ARAM-execution inference of entry 8 is withdrawn."

- record_id: TCL-001
  kind: TOOLCHAIN
  topic_id: TCL
  title: "yosys here reads VHDL nowhere: the flow is read_slang plus read_verilog, and Gowin cells need both a library file and a blackbox flag"
  status: VERIFIED
  verified_date: 2026-10-30
  statement: "The open-flow synthesis is yosys 0.69+260 (git sha1 dcd59343b) with the slang front end (read_slang --std 1800-2017). There is no VHDL front end in the flow and no ghdl plugin in use. Gowin primitives resolve only when the cell libraries are passed twice: as -v library files so a wrapper's PLL/OSER10/DPB instance elaborates, and as --blackboxed-module so the instance is not dropped silently. cells_sim.v needs its specify blocks stripped first."
  consequence: "This is the single largest reason this project ports a Verilog core. SNESTang's machine is Verilog; the MiSTer-derived core is 29,211 lines of VHDL in 56 files and would need a second front end or a vhd2vl pass. Any new source added to fpga/snes/ must be Verilog or SystemVerilog that slang accepts."
  sources:
    - "yosys -V on the bench: 'Yosys 0.69+260 (git sha1 dcd59343b)'"
    - "TinyNES tools/build_ae350_soc.sh and TinyTang tools/desktop_open/synth.ys, whose comments describe the -v plus --blackboxed-module requirement"
  verification: "The build script's shim construction is copied from those two files and reproduced their behaviour this session, including the silent-drop failure mode when only -v is passed."

- record_id: TCL-002
  kind: TOOLCHAIN
  topic_id: TCL
  title: "nextpnr-himbaechel's SDC parser rejects /// comments, -waveform, create_generated_clock and get_clocks"
  status: VERIFIED
  verified_date: 2026-10-30
  statement: "Against the fork used by TinyTang and TinyNES, an SDC file produced these errors in turn: \"Unsupported SDC command '//'\", \"unsupported argument '-waveform' to create_clock\", \"Unsupported SDC command 'create_generated_clock'\", and \"Unsupported SDC command 'get_clocks'\". create_clock with -name, -period and a get_ports/get_nets/get_pins object works. set_multicycle_path is therefore also unavailable, because it cannot name its clocks."
  consequence: "SNESTang's constraints cannot be carried over as written. This project declares fclk, mclk, hclk5, hclk and sys_clk with create_clock and omits the mclk<->fclk multicycle relaxation, which over-constrains those crossings rather than under-constraining them. If the SDRAM paths fail timing, the missing multicycle statement is the first explanation to rule out."
  sources:
    - "nextpnr-himbaechel error output from this session's runs (build/sweep/*/nextpnr.log, not committed)"
  verification: "Each message was reproduced in sequence while editing fpga/snes/tinysnes.sdc this session."

- record_id: TCL-003
  kind: TOOLCHAIN
  topic_id: TCL
  title: "synth_gowin does not preserve the mclk net name, so a clock must be constrained through the PLL cell's pin"
  status: VERIFIED
  verified_date: 2026-10-30
  statement: "In the synthesized netlist there is no net named mclk: the SNES PLL appears as cell pll_snes.PLL_inst and its CLKOUT0 drives an anonymous bit, while the same clock is visible downstream as iosys.clk because that instance port happens to name it. fclk, hclk, hclk5 and sys_clk do keep their names. nextpnr reports 'get_nets argument 'mclk' matched no objects' and times the domain under the name iosys.clk."
  consequence: "fpga/snes/tinysnes.sdc constrains mclk with get_pins {pll_snes.PLL_inst/CLKOUT0} at 46.5 ns. Read the timing report for iosys.clk when looking for the main domain, not for mclk."
  sources:
    - "This session's netlist inspection of build/tinysnes/tinysnes.json: the PLL cells and their CLKOUT0/CLKOUT1 nets, and the absence of a mclk netname"
  verification: "Inspected the JSON netlist directly and confirmed against the nextpnr warning."

- record_id: TCL-004
  kind: TOOLCHAIN
  topic_id: TCL
  title: "The Gowin cell library's names collide with design modules, and its MUX2 cells exhaust the placer"
  status: VERIFIED
  verified_date: 2026-10-30
  statement: "cells_sim.v defines primitives named ALU and MUX2 among others. A design module named ALU fails elaboration with 'duplicate definition of ALU', with the note pointing at cells_sim.v line 837. Separately, a design that instantiates MUX2 cells -- Gowin's IP generator does this when it builds a byte-wide RAM from bit-wide SP blocks -- fails placement with 'no BELs remaining to implement cell type MUX2' on GW5AST-138C."
  consequence: "fpga/snes/src/65C816/ALU.v is renamed P65C816_ALU, and the eight MUX2 instances in vram_spb.v are expressed as a ternary select, which synthesises to LUTs. Any future vendor IP that instantiates MUX2 needs the same treatment."
  sources:
    - "oss-cad-suite share/yosys/gowin/cells_sim.v: module ALU (SUM, COUT, I0, I1, I3, CIN) and module MUX2 (O, I0, I1, S0)"
    - "This session's yosys and nextpnr error messages"
  verification: "Both failures reproduced this session, and both cleared after the described change."

- record_id: TCL-005
  kind: TOOLCHAIN
  topic_id: TCL
  title: "slang rejects $fdisplay and the vendor `error directive, which Gowin EDA silently ignored"
  status: VERIFIED
  verified_date: 2026-10-30
  statement: "Sixteen active `$fdisplay(32'h80000002, ...)` debug statements in cpu.v, dsp.v, smp.v, spc700.v, ppuhoam.v and chip/DSP/DSPn.v make elaboration fail with 'unsupported system task $fdisplay'. snestang_top.v's `ifndef CONFIG_V `error \"config.v must be read before snestang_top.v\" guard fails with 'unknown macro or compiler directive `error', even when CONFIG_V is defined."
  consequence: "The debug statements are replaced by null statements in place, and the guard is a comment. Both are recorded as carried changes to upstream sources; they do not alter behaviour. Gowin EDA tolerating them is the reason upstream does not notice."
  sources:
    - "SNESTang commit 5f0ef19, the named files; oss-cad-suite slang error output from this session"
  verification: "Reproduced before the change and cleared after it, with synthesis otherwise unchanged."

- record_id: TCL-006
  kind: TOOLCHAIN
  topic_id: TCL
  title: "HDMI works on this board only with the pixel clock divided from the 5x clock and the PLLs and divider placed"
  status: VERIFIED
  verified_date: 2026-10-30
  statement: "TinyNES's fpga/ae350_soc/ae350_soc.cst pins hdmi_pll27 at PLL_R[1], hdmi_pll at PLL_R[3] and pix_div at RIGHTSIDE[4], and its ae350_soc.sv:545 makes the 74.25 MHz pixel clock with CLKDIV #(.DIV_MODE(\"5\")) from the 371.25 MHz clock; TinyTang's fpga/desktop/desktop.cst pins the same sites and records that without them nextpnr lands the PLL in a row-108 gap. In this project the same arrangement - gowin_pll_hdmi as TinyTang's single-output 371.25 MHz wrapper, a CLKDIV named div5, and those four INS_LOC lines - produced a synced and stable picture, while three earlier images built with the pixel clock on the PLL's second output produced no signal at all. Attempts to divide the clock without the placements failed to route, once with 'Net hclk5 has no route to the FCLK of s2h.hdmi.serializer.gwSer0 (sink wire X181Y102/FCLKA)'."
  consequence: "These five constraints are load-bearing, not tuning: removing the placements makes the design either unroutable or silent. fpga/snes/tinysnes.cst carries them and fpga/snes/pll/gowin_pll_hdmi.v is the single-output wrapper. A change that re-enables the PLL's second output or drops an INS_LOC should be expected to break the picture."
  sources:
    - "TinyNES, fpga/ae350_soc/ae350_soc.cst: INS_LOC hdmi_pll27 PLL_R[1], hdmi_pll PLL_R[3], pix_div RIGHTSIDE[4], with the comment about the row-81 HCLK block and the 9.86 ns general route at PLL_L[3]"
    - "TinyNES, fpga/ae350_soc/ae350_soc.sv:545: CLKDIV #(.DIV_MODE(\"5\")) pix_div"
    - "TinyTang commit 207f9af, fpga/desktop/desktop.cst and fpga/desktop/pll/gowin_pll_hdmi.v"
    - "This project's build/sweep6 routed netlists (bench only, not committed)"
  verification: "Observed on this board on 2026-10-30: three builds with the second PLL output gave 'no signal', and the constrained build gave a stable picture the user confirmed. The failure and success were reproduced across separate loads."

- record_id: EXT-003
  kind: EXTERNAL
  topic_id: EXT
  title: "TangCore's SNES loader: loading state, 64 header bytes, then the file in 1024-byte frames"
  status: VERIFIED
  verified_date: 2026-10-30
  statement: "nand2mario's firmware-bl616 loads a SNES ROM in this order: set_loading_state(1); send the 64 bytes at 0x7FC0 + off, where off is 512 when the file has a copier header; seek to off and send the file in 1024-byte chunks; overlay(0); set_loading_state(0). Frames are 0xAA then the length big-endian then the type byte then the payload, with the length counting the type byte, so a data frame of n bytes carries len = n + 1. loaders must also let the tail settle before releasing the loading state, because the core writes to SDRAM as data arrives."
  consequence: "tools/load_snes_rom.py implements exactly this and the core agrees: with the harness driving the debug border, header_finished and loaded are both set after a load in one-wire and in two-wire, which is the evidence that the protocol and the header parse are correct and that the remaining fault is in the machine's memory path."
  sources:
    - "firmware-bl616 (github.com/nand2mario/firmware-bl616), core/snes.cpp: the load sequence, and utils/utils.cpp: send_fbuf_data() and set_loading_state()"
    - "SNESTang commit 5f0ef19, src/iosys/iosys_bl616.v: the command list and the 0xAA frame format"
  verification: "Read from the upstream firmware and cross-checked against the core's own RTL this session; the header-parse and release half was then confirmed on hardware by the debug border. Revised 2026-10-30 (core-log entry 3): the image half is confirmed too -- the loader's write count reaches 524288 words for a 1 MiB image, and the image's first word is found at SDRAM word 0 with no displacement at 16, 32, 64, 128, 256, 512 or 1024 bytes."

- record_id: EXT-004
  kind: EXTERNAL
  topic_id: EXT
  title: "SNESTang's SCPU carries a debug port that reads CPU registers, and this tree leaves it undriven"
  status: VERIFIED
  verified_date: 2026-10-31
  statement: "SNES.v muxes DBG_DAT_OUT on DBG_SEL: bit 0 selects the SCPU's debug data, bits 1 to 6 select the SMP, WRAM, SPC700, PPU and DSP debug paths, and each chip's write strobe is its DBG_SEL bit ANDed with DBG_REG_WR.  Inside P65C816.v an `always @*` case on DBG_REG publishes A, X, Y, PC, P, SP, D, PBR, DBR and more: 0x06 is PC[7:0], 0x07 is PC[15:8], 0x09 is SP[7:0] and 0x0A is SP[15:8], so the value is combinational in DBG_REG and needs no clock to read.  In this tree main.v exposes DBG_SEL, DBG_REG, DBG_REG_WR, DBG_DAT_IN and DBG_DAT_OUT all the way to snestang_top, where nothing drove them until the CPU probe did."
  consequence: "The CPU can be observed from the top level with no change to any upstream file: hold DBG_REG_WR low, drive DBG_SEL to 8'h01, and DBG_DAT_OUT answers the selected register.  Because DBG_DAT_OUT is combinational, PC is read as two separate bytes and a sample can tear if the CPU crosses a byte boundary between the two reads, so a probe must not treat one sample as an exact instantaneous PC.  Reading through this port has no side effect: every write path through it is gated by DBG_REG_WR."
  sources:
    - "SNESTang commit 5f0ef19, src/SNES.v (DBG_SEL decode, CPU_DBG_WR and the DBG_DAT_OUT mux)"
    - "SNESTang commit 5f0ef19, src/65C816/P65C816.v: the debug case at DBG_REG 0x00-0x15"
    - "This repository, fpga/snes/src/main.v and fpga/snes/src/snestang_top.v: the pass-through ports and the TINYSNES_CPU_PROBE block"
  verification: "Read from the upstream RTL and confirmed on the board on 2026-10-31 (core-log entry 5): SP read 0x0101 on a crashed machine, which is a plausible heavily-pushed stack rather than a dead bus, and PC moved only through the four addresses of a jump-to-self loop."

- record_id: TCL-007
  kind: TOOLCHAIN
  topic_id: TCL
  title: "The SDRAM read path works on this board and the fetch path delivers the right word; the machine fault is past the fetch"
  status: VERIFIED
  verified_date: 2026-10-31
  statement: "SNESTang captured SDRAM_DQ combinationally on posedge fclk while driving O_sdram_clk from the PLL's 225-degree output (fclk_p), which put the sample at 3T, about 0.4 ns after the part could be driving against datasheet worst-case tAC.  Replacing that with TinyNES's shape -- dq_fall on the falling edge, dq_rise on the rising edge, data consumed one fclk later, port-0 sample moved from cycle[4] to cycle[5] and ARAM from cycle[1] to cycle[2] -- gives about 8 ns of setup and 4.4 ns of hold at 3.5T.  A self-test that writes and reads back walking-one and walking-zero patterns plus four high addresses through the controller's CPU port returns all 16 data bits correct across 36 write/read pairs, and a time-resolved probe of the CPU's first ROM access now shows what that port returns: ROM_Q is zero at the first assertion of ROMSEL and two mclk later, and by four mclk it carries the ROM's own reset vector word 0x8000 while ROM_ADDR reads 0x7FFC and 0x007F for the same access."
  consequence: "ROM, WRAM and ARAM reads are not the fault, the capture change stays, and the fetch path is exonerated: the mapper produces the LoROM address the image expects, the SDRAM returns the word the loader wrote, and it is on the CPU's port inside the access window (see TCL-010).  The all-zero fetch reading in core-log entry 3 was the old probe sampling two mclk before the controller could answer, not the machine.  The machine still does not run, so the fault is past the fetch path and the next instruments have to answer whether the CPU executes at all -- its program counter is readable through DBG_SEL[0] -- before the PPU, the SPC700 and the ARAM port are considered."
  sources:
    - "SNESTang commit 5f0ef19, src/sdram_cl2_2ch.v (dq_in, O_sdram_clk = fclk_p)"
    - "TinyNES, fpga/ae350_soc/ahb_sdram.sv: ODDR sdram_clk_oddr, dq_fall on negedge, dq_rise on posedge"
    - "This repository, fpga/snes/src/sdram_bist.v, fpga/snes/src/rom_probe.v and the TINYSNES_FETCH_PROBE sampler in fpga/snes/src/snestang_top.v"
    - "This repository, fpga/snes/src/chip/DSP/DSP_LHRomMap.v: ROM_ADDR = CART_ADDR & ROM_MASK, ROM_WORD = 1'b0"
  verification: "Code comparison read 2026-10-30; the self-test result was then measured on the board that day (core-log entry 3).  Revised 2026-10-30 (core-log entry 3): the record was SOURCED and asserted that the capture was the fault behind the dead machine; the self-test refuted that.  Revised 2026-10-31 (core-log entry 4): the record asserted that the fetch path returned zero and that the fault lay between ROM_ADDR and ROM_Q; the five-stripe probe build read 0x0000, 0x0000, 0x8000, 0x7FFC, 0x007F on the board, which refutes that and moves the fault past the fetch path.  Revised 2026-10-31 (core-log entry 9): the ARAM half of this record's claim is now measured rather than inferred, by the direct port self-test, and is bounded -- see the arbitration caveat in that entry.  Revised 2026-10-31 (core-log entry 20): WRAM's byte lanes were tested through the same controller port and the same lane select the machine uses, and passed at every address including the direct page and stack region, so all three memories -- ROM, ARAM and WRAM -- have now been byte-lane verified on hardware.  Revised 2026-10-31 (core-log entry 17): the read path is now proven STABLE as well as correct -- 65,536 back-to-back double-reads over roughly 3000 refresh periods produced no disagreement -- which refutes core-log entry 5's hypothesis that a refresh steals the CPU port's slot and returns stale data; the reads were taken with the machine disabled, so the WRAM/DMA/PPU contention case is still open."

- record_id: TCL-008
  kind: TOOLCHAIN
  topic_id: TCL
  title: "Thirteen diagnostic builds behind TINYSNES_* defines, each with a known-good readout"
  status: VERIFIED
  verified_date: 2026-10-31
  statement: "Each diagnostic is selected with TINYSNES_DEFINES and drawn by snes2hdmi, so the result is read off the screen with no logic analyser and no loader changes.  Thirteen are defined: TINYSNES_SDRAM_TEST, TINYSNES_LOAD_COUNT, TINYSNES_ROM_CHECK, TINYSNES_FETCH_PROBE, TINYSNES_CPU_PROBE, TINYSNES_TRACE_PROBE, TINYSNES_LIVE_PROBE, TINYSNES_APU_PROBE, TINYSNES_ARAM_TEST, TINYSNES_IPL_PROBE, TINYSNES_LINK_PROBE, TINYSNES_READ_STABILITY and TINYSNES_WRAM_TEST.  TINYSNES_SDRAM_TEST runs sdram_bist.v before the machine starts: 16 gapped bars, one per DQ bit, red where a bit mismatched, plus a status band (green pass, red mismatch, blue running, yellow no acknowledge).  TINYSNES_LOAD_COUNT shows eight gated thresholds on the count of the loader's own SDRAM write issues, >=1 up to >=500000 words, and all eight green means a full 1 MiB image was issued.  TINYSNES_ROM_CHECK runs rom_probe.v after loaded and searches eight candidate word addresses for a named image word, green where found in either byte order.  TINYSNES_FETCH_PROBE and TINYSNES_CPU_PROBE share one display behind TINYSNES_PROBE_BARS: five stripes of 16 bars, bit 0 on the left and green for 1, 24 rows tall with an 8-row gap, plus a status band in rows 192-223.  The fetch probe's stripes are ROM_Q at the first assertion of ROMSEL and two and four mclk later plus ROM_ADDR[15:0] and ROM_ADDR[23:8] for that access; the CPU probe's are the ROM access counter's two halves, then PC at the most recent sample, SP and the CPU status byte from DBG_REG 0x15; the trace probe's are the last four ROM addresses, newest first, plus ROM_ADDR[23:8] of the newest; the APU probe's are CPUO ports 1 and 0, the 65816's A, the 65816's PC, the SPC700's PC and then the 65816's P above CPUI port 0.  TINYSNES_ARAM_TEST runs aram_bist.v, a byte-lane-aware write and read-back through the controller's ARAM port with no ROM loaded, and draws the same 16 bars and status band as TINYSNES_SDRAM_TEST -- bits 0-7 the even lane, 8-15 the odd -- with green meaning every bit read back correctly.  The two memory tests share the display through a TINYSNES_BIST_BARS define; see TCL-012 for why they cannot share it through one `elsif` expression.  TINYSNES_IPL_PROBE polls the SPC700's program counter and latches the first value below $FFC0 once the IPL range has been seen, which is the target of the IPL's `JMP [$0000+X]`, together with A and X at that moment, the current PC and all four CPUI bytes; its display is the five probe stripes and its band reads R = exit_seen, G = loaded, B = enable.  TINYSNES_LINK_PROBE carries both directions of the APU link and both CPUs in one snapshot -- CPUO ports 1 and 0, CPUI ports 1 and 0, the 65816's A, the 65816's PC and the SPC700's Y -- which is the pairing the deadlock needs, because the APU probe has CPUO and A while the IPL probe has Y and the CPUI banks, and the top stripe carries four sticky history bits saying whether CPUI port 0 has ever held $CC, whether CPUO has changed away from $AA, whether Y has ever been non-zero, and whether the SPC's PC has left the IPL, plus a bit saying the 65816 has been past $8894 and a 3-bit saturating count of visits to $8888; see TCL-013 for why two of those bits have to be armed and why a visit counter must count transitions rather than samples.  The live probe is the exception: it draws only two stripes over the machine's own picture, so one frame shows what the CPU is doing and what the PPU is drawing."
  consequence: "Use these to bisect the machine rather than adding new probes: memory, loader, fetch and CPU state each have an instrument with a recorded expected readout.  The letterbox border doubles as a three-bit state display under TINYSNES_DBG_BORDER, and its bit assignment changes between builds, so always read the comment at the snes2hdmi instantiation before decoding a colour.  A probe's own correctness is not self-evident and has been wrong more often than the machine: simulate the sampler with tools/tests/probe_tb.sh, which extracts the block verbatim from snestang_top.v, before reading anything into a readout."
  sources:
    - "This repository, fpga/snes/src/sdram_bist.v, fpga/snes/src/rom_probe.v, fpga/snes/src/snes2hdmi.v (the ifdef'd rgb branches), fpga/snes/src/snestang_top.v (the ifdef'd CPU-port mux, write counter, fetch sampler and CPU sampler)"
    - "tools/build_tinysnes.sh: TINYSNES_DEFINES, and tools/rom_probe_expect.py for the expectations"
    - "tools/tests/probe_tb.sh, tools/tests/fetch_probe_tb.sv, tools/tests/cpu_probe_tb.sv"
    - "tools/decode_probe_frame.py: decodes the five stripes from captured frames and discards torn ones"
  verification: "Each build was run on the board and its readout recorded in core-log entries 3, 5, 6 and 8.  A counter in each sampler must detect a real edge: storing the inverted level and testing asserted-level AND stored-level counts every master clock a select is held, which read as 21.5 M accesses per second and tore the trace ring, and the benches now hold the select low for six clocks so the defect cannot return.  Two instrument defects were found and fixed during that work and are worth remembering: a probe that owned the CPU port from reset disconnected the loader's writes, and expectations passed as -DTINYSNES_EXP* never reached the module's EXP parameters, so every comparison ran against zero.  Revised 2026-10-31 (core-log entry 4): TINYSNES_FETCH_PROBE now samples the access three times instead of once and also carries the mapper's address, because the single sample at the first ROMSEL assertion could never see data and its all-zero readout was read as a machine fault for a cycle.  Revised 2026-10-31 (core-log entry 5): TINYSNES_CPU_PROBE was added and both probes were put behind one display, and its bench caught two defects of its own before hardware -- a constant on the right of always @(*) never drives, and 16-bit registers holding one byte truncated the assembled PC to its high byte.  Revised 2026-10-31 (core-log entry 8): TINYSNES_APU_PROBE was redesigned from the SPC700's A and Y to the 65816's side of the handshake, because the SPC700's A, X and Y are all $00 both while it waits and on a dead port (see EXT-005) and could not have answered the question that cycle asked; the payload is now CPUO ports 1 and 0, the 65816's A, PC and P, the SPC700's PC and CPUI port 0, each PC's high byte is read on both sides of its low byte and accepted only when the two agree, and the display was made a latched snapshot for the reason in TCL-011.  Revised 2026-10-31 (core-log entry 9): TINYSNES_ARAM_TEST was added as a ninth build, and its first appearance drew nothing because of the `elsif` trap now recorded as TCL-012.  Revised 2026-10-31 (core-log entry 10): TINYSNES_IPL_PROBE was added as a tenth build, and it refuted the ARAM-execution inference that entry 8 had drawn from an APU-probe program-counter reading -- on the later boot the SPC700 never left its IPL ROM at all.  Revised 2026-10-31 (core-log entry 12): TINYSNES_LINK_PROBE was added as an eleventh build to pair both link directions with both CPUs.  Revised 2026-10-31 (core-log entry 13): the link probe's SPC700-PC stripe was replaced by the 65816's PC to date the desync, which answered that question and exposed a second one -- a single snapshot cannot tell a processor that never advanced from one that advanced and restarted, so the next build needs sticky history bits rather than more current-state fields.  Revised 2026-10-31 (core-log entry 14): the sticky bits were added, and the first build of them was wrong -- two were unarmed and self-set at reset, so they reported all three set; armed and rebuilt, all three read clear.  Revised 2026-10-31 (core-log entry 15): a fourth bit was added for CPUI port 0 ever holding $CC, and the next boot set all four and reached a materially deeper state, which withdraws entry 14's reading of all-clear as a general statement about the machine -- it described one boot, and the failure depth varies between boots.  Revised 2026-10-31 (core-log entry 16): a past-the-handshake bit and a routine-entry counter were added; the next boot read four routine entries with the CPU afterwards cycling at $7C7C-$7C7F, below the LoROM window, which is entry 5's jump-to-self signature and means four consecutive loads of the same image have produced four different failure shapes.  Revised 2026-10-31 (core-log entry 17): TINYSNES_READ_STABILITY was added as a twelfth build -- 4096 iterations of double-reading eight addresses through the CPU port, drawn as a mismatch count on the shared 16-bar display with a green band for a clean run -- and it reported zero mismatches across 65,536 reads.  Revised 2026-10-31 (core-log entry 26): TINYSNES_TRACE_PROBE was used on the repaired clock plan and reported CPU `$FFFE`, the IRQ/BRK vector, fetched in all five boots -- but a ROM-address ring records vector fetches and opcode fetches alike, so it can establish the chain and not its cause; distinguishing them needs the processor status read alongside the program counter.  Revised 2026-10-31 (core-log entry 20): TINYSNES_WRAM_TEST was added as a thirteenth build -- a byte-lane-aware WRAM self-test through the controller's CPU port, with one set confined to $0000-$01FF where the direct page and stack live -- and it reported mask zero at every address."

- record_id: TCL-009
  kind: TOOLCHAIN
  topic_id: TCL
  title: "An ODDR on fclk for the SDRAM clock costs the HDMI pixel clock its route"
  status: VERIFIED
  verified_date: 2026-10-30
  statement: "Replacing O_sdram_clk = fclk_p with an ODDR clocked by fclk, to make the SDRAM clock's relationship to the capture flops deterministic, produced a bitstream with no video at all: the board displayed nothing and never synced.  The ODDR packs into the right-edge IOLOGIC at X181Y23, the same column that carries hclk5 from the HDMI PLL at X177Y81 up to div5 at X181Y81 and the three OSER10s at X181Y57, X181Y100 and X181Y102.  Reverting the ODDR and restoring fclk_p brought the picture back with the same source, the same seed and the same capture change."
  consequence: "The SDRAM clock must stay on the PLL's phase output.  The four 'Failed to route net hclk5 ... using dedicated routing' warnings are not a usable signal on their own -- the build that produced a synced picture has the same four, same sites -- so a change that adds a clock sink on the right edge can break video while the log looks unchanged.  Diagnose it by whether the picture syncs, not by the warning count."
  sources:
    - "This repository, fpga/snes/src/snestang_top.v: the ODDR variant that was reverted, and fpga/snes/pll/gowin_pll_snes.v for the 225-degree output"
    - "nextpnr-himbaechel placement of sdram_clk_oddr at X181Y23/IOLOGICAO in build/tinysnes/nextpnr.log (bench only, not committed)"
  verification: "Observed on the board on 2026-10-30: the ODDR image gave no sync, and the reverted image gave the letterbox and the static grid back (core-log entry 3)."

- record_id: TCL-010
  kind: TOOLCHAIN
  topic_id: TCL
  title: "A CPU-port SDRAM read answers in four master clocks; the CPU latches read data at the end of an eight-master-cycle slow access"
  status: VERIFIED
  verified_date: 2026-10-31
  statement: "With the falling-edge capture of TCL-007, the word a CPU read asks for reaches cpu_port0 four mclk after ROMSEL asserts, about 186 ns later, as measured on the board by the TINYSNES_FETCH_PROBE build: ROM_Q reads 0x0000 both at the assertion and two mclk after it, and holds the image's reset vector 0x8000 by four mclk, with ROM_ADDR reading 0x7FFC for the same access.  On the CPU side the SNES module registers read data into MDR on INT_CLKF_CE, which cpu.v raises when P65_CLK_CNT reaches CPU_LAST_CLOCK, 7 for a slow access, and one SNES master clock is about 46.5 ns."
  consequence: "A slow-memory ROM access leaves the controller about 371 ns and the port answers in about 186 ns, so the fetch path keeps roughly half an access of margin and the capture change cannot have pushed a fetch past the CPU's latch.  This is the arithmetic behind TCL-007 and it is the budget to re-check before adding latency to the ROM path: a change costing four more master clocks would consume the remaining margin."
  sources:
    - "This repository, fpga/snes/src/cpu.v: CPU_LAST_CLOCK, the INT_CLKF_CE/INT_CLKR_CE generation, and MDR <= P65_DI on INT_CLKF_CE"
    - "This repository, fpga/snes/src/sdram_cl2_2ch.v: the port-0 read registration at cycle[5]"
    - "This repository, fpga/snes/src/snestang_top.v: the TINYSNES_FETCH_PROBE sampler and fp_bus field order"
  verification: "Read from the RTL and measured on the board on 2026-10-31 with the five-stripe probe build (core-log entry 4).  The sampler works in mclk, so the four-mclk figure has one mclk of resolution; nothing here resolves it finer than that."

- record_id: TCL-011
  kind: TOOLCHAIN
  topic_id: TCL
  title: "A diagnostic bus must be latched to be photographed; the raster paints a live bus as a different value in every row"
  status: VERIFIED
  verified_date: 2026-10-31
  statement: "The probe display replaces the picture with five stripes of 16 bars, and the HDMI frame is scanned out over about 14 ms, which is some 300,000 mclk at 21.505 MHz.  A probe that drives its display bus combinationally from live registers therefore changes value thousands of times while one frame is being painted, and each row of a stripe carries whatever the machine was doing at that instant.  Measured on this board: with a live 80-bit bus, 0 of 353 captured frames decoded, because no three rows inside a stripe agreed; with the same sampler latched into a snapshot register and refreshed every 2^19 phase revolutions (about 0.29 s), 349 of 353 frames decoded with all three sample rows of every stripe agreeing, and repeated captures a minute apart returned identical values."
  consequence: "Every probe must present a latched snapshot, not a live bus, and the latch must be gated on a counter that is guaranteed to fire.  A first attempt gated the refresh on a tick counter and the phase counter reaching their terminal values together, a one-in-twelve coincidence: it fired by luck on hardware and never in simulation, which is the worst combination because the hardware looked correct.  Counting phase revolutions instead makes the cadence independent of the phase count.  Reading the stripes from captured frames rather than by eye needs a tool that discards torn frames, which `tools/decode_probe_frame.py` does by requiring the sample rows within each stripe to agree; the status band is the independent check, since its meaning is fixed by the RTL and it decoded correctly even on the unreadable build.  A capture also fails for host reasons: OBS holding `/dev/video0` blocks a grab, and that is not a board fault."
  sources:
    - "This repository, fpga/snes/src/snes2hdmi.v: the TINYSNES_PROBE_BARS branch, five 32-row blocks with 24 bar rows and an 8-row gap each, and the status band at yy[7:5]==3'd6"
    - "This repository, fpga/snes/src/snestang_top.v: fp_bus as a latched snapshot refreshed on apu_wrap rollover, and the same practice in the CPU sampler's pc_tick"
    - "This repository, tools/decode_probe_frame.py: majority-of-rows decoding and torn-frame rejection"
  verification: "Measured on the board on 2026-10-31 across two builds of the same probe (core-log entry 8): the live build gave 0 decodable frames of 353 and the latched build 349 of 353, with the latched readout reproducing exactly across captures a minute apart.  The one-in-twelve latch was observed firing on hardware and failing in simulation before it was replaced."

- record_id: TCL-012
  kind: TOOLCHAIN
  topic_id: TCL
  title: "slang resolves `elsif A || B false when only B is defined, silently selecting another branch"
  status: VERIFIED
  verified_date: 2026-10-31
  statement: "A conditional-compilation branch guarded by `elsif TINYSNES_SDRAM_TEST || TINYSNES_ARAM_TEST` is not selected when only TINYSNES_ARAM_TEST is defined: the whole expression resolves false and the following branch compiles instead.  With TINYSNES_SDRAM_TEST defined the same line is selected.  Running `~/oss-cad-suite/bin/slang --preprocess -D<define> <file>` shows the guarded text present for the first macro and absent for the second."
  consequence: "Never put two diagnostic macros in one `elsif` expression.  Two nested `ifdef`s that each set a shared macro, then a single `elsif` on that macro, is the shape that works -- it is what `TINYSNES_PROBE_BARS` already did for the four sampled probes, and `TINYSNES_BIST_BARS` now does for the two memory self-tests.  The failure is silent and dangerous in a specific way: the build succeeds, the bitstream loads, and the display draws a plausible picture from a different branch, so a diagnostic build reports nothing while looking like it ran.  Check a new diagnostic's display branch with `slang --preprocess` before believing a blank or unchanged readout, rather than rebuilding to test the design."
  sources:
    - "slang from oss-cad-suite, `slang --preprocess -DTINYSNES_ARAM_TEST fpga/snes/src/snes2hdmi.v`, compared against `-DTINYSNES_SDRAM_TEST` and against no define"
    - "This repository, fpga/snes/src/snes2hdmi.v: the nested TINYSNES_BIST_BARS defines and the `elsif TINYSNES_BIST_BARS` branch"
  verification: "Measured on 2026-10-31 (core-log entry 9): the ARAM self-test build drew a black screen with 16 bars absent while aram_bist was present in the netlist, and the preprocessor comparison identified the cause; the nested-define form then selected the bars for either macro and neither for a production build."

- record_id: EXT-006
  kind: EXTERNAL
  topic_id: EXT
  title: "The IPL's block-copy protocol, verified against mcode.txt: the SPC publishes its index to CPUO port 0 and waits for CPUI port 0 to match"
  status: VERIFIED
  verified_date: 2026-10-31
  statement: "Walking the 64-byte IPLROM in smp.v with the opcode mnemonics extracted from fpga/snes/src/spc700/mcode.txt gives, from $FFC0: `MOV X,#$EF`, `MOV SP,X`, `MOV A,#$00`, then the clear loop `MOV (X),A / DEC X / BNE`; `MOV $F4,#$AA` and `MOV $F5,#$BB` publish the handshake bytes; `CMP $F4,#$CC / BNE` waits for $CC; `BRA $FFEF` jumps into the second half.  The block-copy loop is at $FFDA: `7E F4 CMP Y,$F4`, `D0 0B BNE $FFE9`, `E4 F5 MOV A,$F5`, `CB F4 MOV $F4,Y`, `D7 00 MOV [$00]+Y,A`, `FC INC Y`, `D0 F3 BNE $FFDA`, then `AB 01 INC $01` for the next 256-byte page and `10 EF BPL $FFDA` as the wait.  After the handshake the address half runs `BA F6 MOV YA,$F6`, `DA 00 MOV $00,YA`, `BA F4 MOV YA,$F4`, `C4 F4 MOV $F4,A`, `DD MOV A,Y`, `5D MOV X,A`, `D0 DB BNE $FFD6`, and finally `1F 00 00 JMP [$0000+X]` at $FFFB.  The walk consumes exactly 64 bytes and ends at $FFFE, where the reset vector $C0FF points back to $FFC0, which is the check that the operand sizes are right.  Note that $F4 read from the SPC side is CPUI port 0 and $F4 written from the SPC side is CPUO port 0, and that `CB F4` is `MOV d,Y`, a one-byte store of Y, not a word store."
  consequence: "The SPC700 acknowledges an index by writing its own Y into CPUO port 0 and immediately increments Y, so CPUO port 0 reads one less than the SPC's current Y whenever the loop is waiting.  It only advances when CPUI port 0 equals its Y, which makes the protocol one-way synchronised: a 65816 that falls behind by even one index can never catch up, because the SPC is waiting for a value the 65816 has already passed, and the 65816 is waiting for an echo of the value it holds.  That is the shape of a permanent desync rather than a slow transfer, and it is why a gap between Y and CPUI port 0 is the measurement to take.  The `JMP [$0000+X]` at $FFFB takes its address from ARAM $0000 and $0001, which the same routine has just loaded from CPUI ports 2 and 3, so the jump target is the transfer address the 65816 wrote to $2142 and $2143.  Read on 2026-10-31 (core-log entry 21): both processors are gated by one signal, so neither can start or pause independently of the other -- `snestang_top.enable` reaches `main.ENABLE`, `dsp.v` forms `SMP_EN_INT = SUBSTEP == 3 ? ENABLE : 1'b0` purely to divide the SPC's clock rate, and `smp.v` forms `SPC700_CE = ENABLE & CE`, giving `spc700.v` `EN = RDY & ~STPExec`.  The only thing that lowers `enable` after it rises is the HDMI frame-sync pause, which lowers it for both at once."
  sources:
    - "SNESTang commit 5f0ef19, src/smp.v: localparam IPLROM[0:63]"
    - "SNESTang commit 5f0ef19, src/spc700/mcode.txt: the 256 `// <opcode> <mnemonic>` comments, which give both the mnemonic and the operand form"
    - "SNESTang commit 5f0ef19, src/spc700/mcode.v and spc700.v for the decode path"
  verification: "Derived mechanically on 2026-10-31 by parsing mcode.txt and walking the IPLROM array (core-log entry 12), and validated by the walk landing exactly on the reset vector.  The measured CPUO port 0 of $19 beside a Y of $1A on hardware is the CONFIRMATION of the `MOV $F4,Y` semantics: the published value is the pre-increment Y.  Revised 2026-10-31 (core-log entry 12): this record is new because entry 11 had quoted a listing written from recollection, with `BPL` at $FFDC where the bytes are `BNE $FFE9` and `MOVW $F4,YA` at $FFE0 where the instruction is `MOV $F4,Y`."

- record_id: TCL-013
  kind: TOOLCHAIN
  topic_id: TCL
  title: "A sticky history bit must be armed against its own reset value, or it sets immediately and reads as a confident finding"
  status: VERIFIED
  verified_date: 2026-10-31
  statement: "A diagnostic that latches history -- a bit that says 'this has happened at least once' -- must compare against a value the machine actually passes through after the event it is watching for, and must be armed before a departure can set it.  Three such bits were built to distinguish a coprocessor that never advanced from one that advanced and restarted.  Of the three, only the one testing Y != $00 was correct as written, because spc700.v resets Y to $00 and that is also the value meaning 'never advanced'.  The other two were wrong: smp.v clears CPUO to $00 at reset, so a bit testing 'CPUO != $AA' sets the instant reset releases, and addrgen.v clears the SPC's program counter to $0000, so a bit testing 'the PC is not in the IPL' does the same.  Both reported set on hardware.  Arming them -- setting a flag on first sight of $AA, or of a PC inside $FFC0-$FFFF, and only then allowing a departure to set the bit -- made them informative, and the corrected build reported all three clear where the first had reported all three set."
  consequence: "Any sticky bit added to a probe has to be justified against the register's reset value before it is trusted, and armed if its test value is not the reset value.  Arming is one-way and persists until reset, so a bench that tests arming must reset first: a test written after the bit is already armed asserts something the design never promised.  Mutation-test a new sticky bit by reverting it to tracking its current value and by removing its arming; both must fail a specific check.  A counter of events must count TRANSITIONS, not samples: a value held for several probe revolutions adds one per sample, so three visits read as seven, and a test that only checks a lower bound passes the defect by overshooting -- assert the exact count for a stimulus whose dwell exceeds one revolution.  A bit whose test value differs from its register's reset value needs no arming and is the safe case -- CPUI clearing to $00 and a bit testing for $CC is one -- but that has to be established by reading the reset value, not assumed, and the bit still has to be cleared on reset or a reloaded build reports the previous machine's history.  The failure mode is the dangerous kind -- the probe builds, loads, and reports a definite answer that is simply not evidence -- and it was caught here only by reasoning about reset values after an implausibly unanimous readout, not by the bench, which had been written to match the same wrong assumption."
  sources:
    - "SNESTang commit 5f0ef19, src/smp.v: CPUO <= '{4{8'b0}} on RST_N"
    - "SNESTang commit 5f0ef19, src/spc700/spc700.v: Y <= 8'b0 on reset"
    - "SNESTang commit 5f0ef19, src/spc700/addrgen.v: PCr <= 0 on reset"
    - "This repository, fpga/snes/src/snestang_top.v: the TINYSNES_LINK_PROBE sticky bits and their arm flags"
  verification: "Measured on 2026-10-31 (core-log entry 14): the unarmed build read all three bits set on hardware, and the armed build read all three clear on the same machine state apart from the index; the bench then caught both mutations (tracking instead of latching, and unarmed) for all three bits."

- record_id: DEV-004
  kind: DEVICE
  topic_id: DEV
  title: "Clock-plane bridge pips measured on this board by the sibling projects, and the build gate that carries them"
  status: VERIFIED
  verified_date: 2026-10-31
  statement: "On the GW5AST-138C a clock reaches the global network by leaving a spine mux through a bridge pip, and which pip a net gets depends on the order nextpnr routes the clock nets in.  The rule is source-dependent.  For a PLL-sourced clock, TinyNES DEV-009 measured an image entering at (54,88) SPINE16 and leaving through CBRIDGEOUT_BOTTOM0 into SPINE25 and SPINE1 that loaded with DONE and was silent, while the same image with only those muxes changed to (54,93) SPINE10 / CBRIDGEOUT_TOP2 ran, and SPINE8 / CBRIDGEOUT_TOP0 also ran: TOP works and BOTTOM0 is dead.  For an HCLK CLKDIV source, DEV-017 measured that SPINE26 <= CBRIDGEOUT_BOTTOM2 clocks every flip-flop on its branches, that SPINE17 <= CBRIDGEOUT_BOTTOM0 and SPINE18 <= CBRIDGEOUT_BOTTOM2 clock none of them, and that entering at (54,93) SPINE9 / CBRIDGEOUT_TOP1 left the clock dead in 8 of 8 seeds: BOTTOM2 at SPINE18 works and TOP is dead.  DEV-016 records a netlist that did not boot while an otherwise identical one did, differing only in clock routing order.  The aquasock Apicula fork encodes the PLL half by dropping every BOTTOM entry for a `T[LR]PLL<n>CLK<n>` source and the CLKDIV half by letting escape wires 105..112 enter only at (54,88) SPINE18; `NPNR_GOWIN_CLK_FIRST` in the nextpnr fork makes the routing order deterministic rather than alphabetical."
  consequence: "A design on this board has to check, after place and route, which spine and bridge pips each clock actually took, because the router is free to choose paths that no one has measured and a dead choice is silent rather than loud: the image loads with DONE and nothing runs.  `tools/clock_plane_report.py` reads the routed netlist, reports every clock's pips against a table of the measurements above plus this project's own hardware evidence, and `tools/build_tinysnes.sh` refuses a build that lands on an unmeasured pip unless TINYSNES_ALLOW_UNMEASURED_CLOCKS=1.  The knob matches a net by name and after flattening Yosys names a net after the alphabetically first of its aliases, so `mclk` appears as `iosys.clk`; the build fails if nextpnr did not log applying the knob rather than assuming it took.  Unmeasured is not broken: it has simply not been shown either way, and the table is the place to record a new measurement when hardware settles one.  There is a worse state than unmeasured and the gate used to miss it entirely: a clock that crosses no bridge pip reaches the global network not at all, so its skew is interconnect delay rather than a balanced network, and because the hold check and the Fmax gate both evaluate a domain that never entered the network, a point-to-point clock still meets its period on paper.  `fclk`, the SDRAM controller's clock and this design's widest fast domain, ran in that state for the project's whole history on this board.  The report now finds clocks by their flip-flop clock inputs as well as by their routing, and fails on a clock with no plane access."
  sources:
    - "TinyNES .ai/core-reference.md DEV-009, DEV-016, DEV-017 and the build gate in TinyNES tools/build_ae350_soc.sh"
    - "aquasock/apicula epic/gw5ast138c, apycula/chipdb.py _gw5ast138c_dead_bridge_pips and fse_clock_pips_138"
    - "nextpnr-mathieufro himbaechel/uarch/gowin/globals.cc, the NPNR_GOWIN_CLK_FIRST block"
    - "This repository, tools/clock_plane_report.py and tools/build_tinysnes.sh"
  verification: "Inherited measurements were read from TinyNES's records on 2026-10-31 and not re-measured here.  This project's own entries in the table come from the working picture recorded in TCL-006, since a stable synced image proves the pixel clock and pll_27's input reach their branches.  The gate was exercised on this design's routed netlists over six seeds (core-log entry 22), which showed `iosys.clk` consistently on SPINE0/CBRIDGEOUT_TOP0 and SPINE25/CBRIDGEOUT_TOP1, neither of which has been measured.  No clock has yet been seen on a pip recorded as dead, so this record has not yet explained the machine's fault.  Revised 2026-10-31 (core-log entry 23): `NPNR_GOWIN_CLK_FIRST=iosys.clk` was set on two seeds and did change the route -- the machine clock moved off SPINE18/TOP1 and SPINE26/TOP0 onto SPINE25/TOP1 -- but SPINE0/TOP0 remained at every seed so the clock never left an unmeasured pip, and five boots gave five distinct states exactly as they had without the knob.  The knob fixes routing order and not pip choice, so it can neither test nor fix a clock-plane fault; only a chipdb restriction that removes the pip can.  Revised 2026-11-03 (core-log entry 76): five pips are now measured on this board by a retail cartridge booting from `build/spine75` -- `pll` `SPINE18/TOP2` and `SPINE28/TOP2` carrying `fclk` via `TLPLL0CLK2`, `pll` `SPINE0/TOP0`, `SPINE24/TOP0` and `SPINE25/TOP1` carrying `mclk`, `clkdiv` `SPINE19/BOTTOM2` and `SPINE27/BOTTOM2` carrying the pixel clock, and `pll` `SPINE8/BOTTOM0` carrying pll_27's reference.  The second half of this record's own tooling was the reason: a clock with NO bridge pip at all was invisible to the gate, because the report enumerated clocks from their routing.  `fclk` was in exactly that state -- 193 flip-flop clock inputs, no spine tap, 18,400 characters of point-to-point interconnect -- while every gate reported success.  The report now also enumerates nets that drive flip-flop clock inputs and fails on those with no plane access.

- record_id: TCL-014
  kind: TOOLCHAIN
  topic_id: TCL
  title: "`${var:+}` expands to nothing, so a conditional CLI flag wired that way silently passes no flag"
  status: VERIFIED
  verified_date: 2026-10-31
  statement: "In bash, `${allow_unmeasured:+}` substitutes an empty string whether or not the variable is set, because the `:+` form expands to the alternate word after the colon and no word was written.  A build script that gated a tool invocation on `${flag:+}` therefore ran the tool without its `--allow-*` argument at every setting, and a six-seed sweep reported every seed refused for a reason the operator had already asked to override."
  consequence: "Build a conditional argument list as an array -- `args=(); [[ \"$x\" == 1 ]] && args+=(--flag); cmd \"${args[@]}\"` -- rather than relying on a substitution inside a command line.  The failure is invisible in review because the construct looks like a guard, and it cost a whole sweep before the pattern was read carefully; a `bash -n` syntax check does not catch it because the expansion is legal."
  sources:
    - "This repository, tools/build_tinysnes.sh, the clock-plane gate invocation"
    - "bash manual, parameter expansion, `${parameter:+word}`"
  verification: "Observed on 2026-10-31 (core-log entry 22): six seeds were refused although TINYSNES_ALLOW_UNMEASURED_CLOCKS=1 was exported, and the same seeds all built once the flag was assembled as an array."

- record_id: TCL-015
  kind: TOOLCHAIN
  topic_id: TCL
  title: "apicula's PLL-to-clock-plane table carries only CLKOUT0 at slots 0 and 4 and CLKOUT2 at slot 0, so any other PLL output falls back to general routing"
  status: VERIFIED
  verified_date: 2026-10-31
  statement: "`apycula/chipdb.py`'s `_gw5a_pll_clk_wires['GW5AST-138C']` holds exactly three entries: `(0, 'CLKOUT0') -> 'TLPLL0CLK0'`, `(4, 'CLKOUT0') -> 'TRPLL0CLK0'` and `(0, 'CLKOUT2') -> 'TLPLL0CLK2'`.  A PLL output with no entry here has no pip into the 24-wire clock plane, and nextpnr then routes it on ordinary interconnect: in this design `fclk`, which is `PLL_R[0]`'s `CLKOUT1`, takes 1281 general-routing segments (`X151Y19/W130`, `X150Y19/N830`) with no spine and no global tap, and clocks 225 flip-flops spread from X140 to X180 and Y0 to Y20, while `mclk`, which is the same PLL's `CLKOUT0`, runs 11910 segments through the `CLK1`/`GB10` global taps.  TinyGBA measured the mechanism from the other side on 2026-10-31: `clk67` on general routing had 255 sinks with 1.2 to 1.9 ns of skew and was suspected of a failed SDRAM readback and an absent picture; two vendor builds showed a second output reaches the plane on the lane matching its output number, the `CLKOUT2` entry was added, and eight of eight seeds then routed on global resources."
  consequence: "Placing a PLL at a site whose output has no entry in this table silently costs the clock its global network, and the design fails in ways that look like logic or memory faults: skew across a domain makes paths marginal rather than broken, so compact self-tests that place their flip-flops close together pass while a machine that spreads the same domain over tens of tiles fails, and the failure point moves between boots.  Any clock that carries more than a handful of flip-flops must be checked for a spine tap in the routed netlist before a failure is blamed on logic -- `tools/clock_plane_report.py` now reports this, and the general-routing case is the one to look for.  Adding a pip needs a vendor measurement in the shape TinyGBA used, because the fork's rule is that only measured entries go in the table; the alternative that needs no database change is to re-place the PLL onto a slot that already has a `CLKOUT0` entry, or -- when one PLL must supply two global clocks -- onto the left-edge slot and onto `CLKOUT2`, which is what this design now does."
  sources:
    - "aquasock/apicula epic/gw5ast138c 495661a, apycula/chipdb.py _gw5a_pll_clk_wires"
    - "TinyGBA .ai/core-log.md entry 4 and the two vendor builds it describes"
    - "This repository, build/kpl7/tinysnes-routed.json and fpga/snes/tinysnes.cst"
  verification: "The table contents were read directly from the fork on 2026-10-31 and the consequence measured on this design's routed netlist (core-log entry 24): `fclk` has 1281 general-routing segments, no spine and no global tap, against `mclk`'s global route.  Revised 2026-11-03 (core-log entry 76): putting `fclk` on the plane was then done and tested, and the machine runs -- Zelda and Super Mario Kart both boot from a build whose `fclk` enters through `TLPLL0CLK2` and crosses `SPINE18/TOP2` and `SPINE28/TOP2`.  The repair used here is the second of the two this record offers, with one addition: a design that needs two global clocks out of a single PLL must place that PLL at a site offering two plane wires, which on this device is the left edge only, because the right-edge site carries `CLKOUT0` alone.  So `pll_snes` moved from `PLL_R[0]` to `PLL_L[0]`, `fclk` moved from `CLKOUT1` to `CLKOUT2` to take `TLPLL0CLK2`, and the phase-shifted output moved to `CLKOUT1` because it drives one pin and needs no plane access.  Re-placing onto a slot with a spare `CLKOUT0` is not sufficient on its own when two clocks need the network."

- record_id: EXT-007
  kind: EXTERNAL
  topic_id: EXT
  title: "The 65816's WAI and STP halt the core until reset, and the sample of its status is the only way to tell a waiting CPU from a lost one"
  status: VERIFIED
  verified_date: 2026-10-31
  statement: "In `P65C816.v`, `WAIExec` and `STPExec` are set when `STATE == 0` and the fetched opcode is `$CB` or `$DB` respectively, and are cleared only by reset.  Both drive `assign EN = RDY_IN & CE & (~WAIExec) & (~STPExec)`, so a CPU that executes either stops advancing until it is reset -- `WAI` resumes on an interrupt in hardware terms, but this core has no wake path other than reset for either flag.  `GotInterrupt` is not comparable: it is assigned at `LAST_CYCLE` and cleared at the next one, so it describes a single instruction sequence and a sampled zero proves nothing about whether an interrupt ever arrived.  The module also carries `assign IsBRKInterrupt = (IR == 8'h00)`, a combinational signal that distinguishes a software `BRK` from an interrupt and which no debug register exposes; `DBG_REG` `0x15` packs GotInterrupt, IsResetInterrupt, IsNMIInterrupt, IsIRQInterrupt, RDY_IN, EN, WAIExec and STPExec but not IsBRKInterrupt."
  consequence: "The `DBG_REG` `0x15` status byte, read by `TINYSNES_CPU_PROBE`, is the instrument that separates three states a ROM-address trace cannot: a CPU running, a CPU halted on `WAI` waiting for an interrupt, and a CPU halted on `STP`.  Measured over five boots of the loaded image (core-log entry 27), four read `$0A` (`WAIExec`) and one `$09` (`STPExec`), with ROM access counts in the millions -- so the machine executes a great deal of code and then waits, which points at a missing interrupt rather than corrupt data.  A diagnosis built on `GotInterrupt` being zero is not sound for the reason above; adding `IsBRKInterrupt` to a probe would make the BRK question answerable."
  sources:
    - "SNESTang commit 5f0ef19, src/65C816/P65C816.v: the WAIExec/STPExec set at STATE 0, `assign EN`, the GotInterrupt assignment at LAST_CYCLE, `assign IsBRKInterrupt`, and the DBG_REG 0x15 packing"
    - "This repository, fpga/snes/src/snestang_top.v: the TINYSNES_CPU_PROBE sampler"
  verification: "Read from the RTL and then measured on the board on 2026-10-31 (core-log entry 27): five boots, four on WAI and one on STP, with ROM access counts between 1.1 and 12.6 million.  The sticky nature of WAIExec and STPExec is what makes the reading sound; the transience of GotInterrupt is what makes the earlier BRK inference in the same cycle unsound, and that inference was withdrawn."

- record_id: EXT-008
  kind: EXTERNAL
  topic_id: EXT
  title: "The SNES interrupt chain from the PPU to the 65816, and the one signal that separates a software BRK from a hardware interrupt"
  status: VERIFIED
  verified_date: 2026-10-31
  statement: "The PPU drives `INT_VBLANK` out of `SNES.v` into `cpu.v`'s `VBLANK` input.  In `cpu.v` the NMI flag sets on `if (VBLANK && ~VBLANK_OLD2 && DOT_CLK_CE)` inside a block gated by `ENABLE`, with `VBLANK_OLD2` updated on `DOT_CLK_CE`; `NMI_EN` is loaded from `P65_DO[7]`, the game's write to `$4200`; and `assign P65_NMI_N = ~(NMI_EN & NMI_FLAG)`.  `assign EN = RDY_IN & CE & (~WAIExec) & (~STPExec)` where `CE` is `INT_CLKF_CE`, a one-mclk pulse per instruction, so `EN` reads low on almost any random sample and is not a fault indicator.  Inside `P65C816.v`, `assign IsBRKInterrupt = (IR == 8'h00)` distinguishes a software `BRK` from a hardware interrupt, and no debug register exposes it: `DBG_REG` `0x15` packs GotInterrupt, IsResetInterrupt, IsNMIInterrupt, IsIRQInterrupt, RDY_IN, EN, WAIExec and STPExec but not this."
  consequence: "Three separate faults produce the same symptom -- a CPU that stops with no code running -- and they are separable only by history, not by a snapshot: the PPU may not generate vblank, the edge detector may not fire, or the game may never write `$4200` bit 7.  Sticky bits read through a spare debug register settle that, and this project's `TINYSNES_IRQ_PROBE` reads them from register `0x16`, which `cpu.v` intercepts while passing every other register through untouched, so no upstream port list changes.  Measured on one boot (core-log entry 28): `VBLANK` has been high and `NMI_FLAG` has been set, so both the PPU and the edge detector work, while `NMI_EN` was never set -- the 65816 stops before enabling NMI, not after.  Revised 2026-10-31 (core-log entry 30): entry 28's reading, and the single post-revert sample of entry 29, were both taken on a build whose ROM read returned zero and are void.  Re-measured over five boots on the restored baseline: a write to `$4200` is always decoded, `VBLANK` is always high and `NMI_FLAG` always fires, so the prologue, the PPU and the edge detector all work in every boot; `NMI_EN` is set in one boot of five, refuting the earlier never; and that boot ended halted on `STP` with NMI enabled and its program counter in a handler prologue, so enabling the interrupt does not save the machine."
  sources:
    - "SNESTang commit 5f0ef19, src/cpu.v: the VBLANK/NMI_FLAG block, NMI_EN from P65_DO[7], `assign P65_NMI_N`, `assign EN`, and `INT_CLKF_CE`"
    - "SNESTang commit 5f0ef19, src/65C816/P65C816.v: `assign IsBRKInterrupt`, the DBG_REG 0x15 packing, and the DBG_REG default case"
    - "SNESTang commit 5f0ef19, src/SNES.v: SPPU `.VBLANK(INT_VBLANK)` and the CPU's VBLANK connection"
  verification: "Read from the RTL and measured on the board on 2026-10-31 (core-log entry 28): sticky byte `0x05` and status `0x08` in 178 of 180 frames, so vblank and the NMI edge detector are both confirmed working and NMI was never enabled.  Revised 2026-10-31 (core-log entry 30): this reading was taken on a build whose ROM read returned zero and is void; see the consequence field for the five-boot re-measurement on the restored baseline, which found `NMI_EN` set in one boot of five and that boot halted on `STP` anyway."

- record_id: EXT-009
  kind: EXTERNAL
  topic_id: EXT
  title: "In a LoROM layout the cartridge is mapped only at $8000-$FFFF, so a program counter below $8000 is running outside the image"
  status: VERIFIED
  verified_date: 2026-10-31
  statement: "A LoROM cartridge maps its image into the upper half of every bank: CPU `$8000-$FFFF` in banks `$00-$7D` is ROM, and banks `$80-$FF` repeat the same image through the fastrom window.  The lower half, `$0000-$7FFF`, is never cartridge in any bank: banks `$00-$3F` and `$80-$BF` put the 128 KiB WRAM mirror at `$0000-$1FFF`, the PPU and APU and CPU registers at `$2000-$5FFF` and `$4200-$43FF`, expansion and the SRAM window at `$6000-$7FFF`; the remaining banks have their own special-purpose mappings.  So for a LoROM image the test `PC >= $8000` is exactly the test `\"the CPU is executing cartridge code\"`, and it holds regardless of the program bank -- which is why the bank byte alone cannot answer the question.  This repository's test image is LoROM with the fastrom bit set: header map byte at `$7FD5` reads `$30`, reset vector `$FFFC` is `$8000`, and the reset code at `$8000` matches the file at offset 0 for bank 0."
  consequence: "A program counter below `$8000` is not a code address and a CPU seen there has left the cartridge. That makes a single sticky bit -- armed at a PC of `$8000` or above, set by the first PC below it -- a complete and cheap test for the departure, where a snapshot of PC and PBR together still needs the map to be interpreted. The corresponding trap is that a `PC >= $8000` test must be armed against the reset value, because PC resets to `$0000` and an unarmed bit would set at reset and read yes for ever (TCL-013). The same reasoning does not transfer to a HiROM or ExHiROM image, where the cartridge also occupies the lower half of the upper banks, so a probe built on this test is specific to the loaded image's layout and should say so."
  sources:
    - "SNES LoROM memory map as used by this project's test image; cross-checked against the image itself rather than taken on trust"
    - "This repository, /tmp/zelda.smc: header map byte `$7FD5` = `$30`, reset vector at file offset `$7FFC` = `$8000`, and the reset code at file offset 0 matching CPU `$8000`"
  verification: "The mapping was confirmed against the image: decoding the candidate reset path at file offset `0x0800` as CPU `$8800` produced the sound-upload routine's echo-wait `CMP $2140 / BNE` at exactly the addresses the trace probe had frozen on (`$8894`, `$88EF`), while decoding the same bytes at file offset `0x8800` produced nonsense. That agreement between a static disassembly and a hardware trace is what establishes the offset relation for this image."

- record_id: TCL-016
  kind: TOOLCHAIN
  topic_id: TCL
  title: "A ROM-address ring on the mapper's cycle-assert edge names a hot address, not a complete fetch sequence, so it cannot be read as an instruction-by-instruction trace"
  status: VERIFIED
  verified_date: 2026-11-01
  statement: "`TINYSNES_TRACE_PROBE` and `TINYSNES_JUMP_PROBE` both advance their ring on `ROMSEL && ~ROM_CE_N_d`, a start-of-access edge rather than the held level, which is the correct test for counting accesses but is not the same as counting bytes fetched.  `ROM_CE_N` is not released between every consecutive byte fetch, so a burst of fetches is recorded once, at its first address, and the ring holds burst starts rather than every address the CPU read.  Measured: on a boot frozen in the sound upload's `CMP $2140 / BNE` loop at `$8891` and `$8894`, whose fetches are `$8891` to `$8895` each iteration, the ring read `$8894`, `$8894`, `$8894`, `$8894`.  The 65816's instruction queue makes this worse rather than better, because the fetch stream runs ahead of execution and the ring therefore dates the bus rather than the program counter."
  consequence: "The ring is sound for what it was built for -- naming the region the CPU was fetching from, and showing that fetching has stopped so that a jump can be located -- and it is not sound for reconstructing the exact instruction sequence that preceded an event. When an entry reports a ring value, it must say which of those two readings it is making, and a claim that names a specific instruction has to be justified by disassembling the image at that address and showing the bytes decode coherently from an established instruction boundary, as the `RTL` at `$8887` was. A probe that needs the exact bytes must instead capture the data the mapper returned (`ROM_Q`) alongside the address, or sample `DBG_REG` `0x06` and `0x07` per accepted PC, because the address ring alone cannot distinguish a fetch that was executed from one that was prefetched and discarded."
  sources:
    - "This repository, fpga/snes/src/snestang_top.v: the TINYSNES_TRACE_PROBE and TINYSNES_JUMP_PROBE rings and their `~ROM_CE_N && ROM_CE_N_d` edge test"
    - "This repository, tools/sample_boot_states.py: the trace and jump layouts"
  verification: "Measured on 2026-10-31 and 2026-11-01 (core-log entries 31 and 32): the trace ring read `$8894` four times on a boot whose loop fetches five distinct addresses, which cannot be a complete fetch sequence, while the same instrument in the same session also reported four distinct addresses on a boot that had left the cartridge, so the ring does track real changes and is not stuck."

- record_id: TCL-017
  kind: TOOLCHAIN
  topic_id: TCL
  title: "The SNES debug selector offers a WRAM channel whose data wire is never driven, so a WRAM read through DBG_SEL[2] returns an undriven value"
  status: VERIFIED
  verified_date: 2026-11-01
  statement: "`SNES.v` declares `DBG_WRAM_DAT`, assigns `WRAM_DBG_WR = DBG_SEL[2] & DBG_REG_WR`, and selects `DBG_WRAM_DAT` onto `DBG_DAT_OUT` when `DBG_SEL[2]` is set, so the design presents a WRAM debug channel in its selector map.  The wire itself is never assigned anywhere: a search of `fpga/` finds it in the declaration and in the selector mux and nowhere else, and the `SWRAM` instance takes no debug port at all, connecting only its clock, reset, enables, address and data ports.  A read with `DBG_SEL[2]` therefore returns an undriven net rather than memory contents, and synthesis resolves it to a constant.  The other channels in the same selector are real: `DBG_SEL[0]` reaches the 65816, `[3]` the SPC700 core, `[4]` the SMP wrapper's port banks."
  consequence: "Memory contents cannot be inspected through the debug port, so any question about what WRAM holds -- a stacked return address, a corruption in the port-0 upload buffer -- has to be answered by watching the WRAM bus, which is a first-class port of `SNES.v` and visible in `snestang_top.v` as `WRAM_ADDR`, `WRAM_D`, `wram_rd` and `wram_wr`.  Watching the bus gives writes for free and reads only as addresses, so an instrument that needs the value at an address must either capture the write that put it there or latch `WRAM_Q` on the read, which is one SDRAM turnaround behind and needs the same care as the ROM fetch probe.  The stack page is `WRAM_ADDR[16:8] == $01`, which makes a write filter on the stack one comparison wide."
  sources:
    - "SNESTang commit 5f0ef19, src/SNES.v: the DBG_WRAM_DAT declaration, the WRAM_DBG_WR assign, the DBG_DAT_OUT mux, and the SWRAM instantiation port list"
    - "This repository, a search of DBG_WRAM_DAT across fpga/ showing the declaration and the mux with no driver"
  verification: "Confirmed by searching for every occurrence of DBG_WRAM_DAT in the tree on 2026-11-01 (core-log entry 33) before writing the stack instrument, which was then built against the WRAM bus instead of the debug port and worked: it captured stack-page writes and a reproducible stack pointer at the departure."

- record_id: TCL-018
  kind: TOOLCHAIN
  topic_id: TCL
  title: "A probe's display band is the authority on whether its latched snapshot fired, and a snapshot that never refreshed decodes as a full set of zeros rather than as missing data"
  status: VERIFIED
  verified_date: 2026-11-01
  statement: "Every diagnostic build paints a 32-row status band in the `dbg` colour, one bit per channel, so the captured band colour is a second reading of the same bits the stripes carry.  For the probe builds added in core-log entries 32 and 33 the band is `{done, loaded, enable}`, which makes grey `(202,202,202)` a recorded event and cyan `(2,225,198)` the state where the core is loaded and enabled but the event never happened.  The probe latches its stripes only on that event, so when it has not happened the stripe registers still hold their reset values and decode as a complete set of zeros -- `departure=$0000`, every field `$00`, every valid bit clear.  That is a well-formed readout, not an error: nothing in the sixteen-bit decoders can distinguish it from a genuine measurement of a zero."
  consequence: "A zero readout must be cross-checked against the band before it is believed, because `departure=$0000` is a legal-looking address and was in fact reported as a measurement in core-log entries 32 and 33 before this was caught.  The sampler now does that check itself for the stack layout, whose colour mapping is unambiguous, and reports such a boot as never having departed rather than as having departed to zero.  The general rule is that the band carries the one bit that says whether the stripes mean anything, so any bootstrap layout should be read band first and stripes second; a layout whose band does not include a done bit cannot make this distinction and should be given one."
  sources:
    - "This repository, fpga/snes/src/snes2hdmi.v: the dbg band painted as one channel per bit, grey when all three are set and cyan when the first is clear"
    - "This repository, tools/sample_boot_states.py: the band-colour guard in the stack layout"
  verification: "Measured on 2026-11-01 (core-log entry 34): five boots of one bitstream reported departed addresses, and a second five-boot run of the same file reported two boots with a cyan band whose stripes decoded as all zeros.  Decoding that cyan band as `{done=0, loaded=1, enable=1}` is what identified the zeros as an unrefreshed snapshot instead of an address of $0000."

- record_id: EXT-010
  kind: EXTERNAL
  topic_id: EXT
  title: "The 65816 core's opcode-commit point is STATE==0 with EN and no interrupt, which is where an executed instruction can be observed rather than the bus traffic around it"
  status: VERIFIED
  verified_date: 2026-11-01
  statement: "In `P65C816.v` the core latches its next instruction in an `always @(posedge CLK)` block that, when `EN == 1'b1` and `GotInterrupt == 1'b0` and `STATE == 4'b0000`, examines `D_IN` and acts on the opcode.  `EN` is `RDY_IN & CE & (~WAIExec) & (~STPExec)`, so this fires once per instruction actually executed rather than once per bus cycle, and `STATE == 0` marks the first cycle of an instruction so a multi-cycle opcode is seen once.  `WAIExec` and `STPExec` are set at exactly this point from `D_IN == $CB` and `D_IN == $DB`, which is what makes the condition the established detection point for opcodes in this core.  The 65816's opcodes of interest for call/return pairing are `JSR` `$20` and `RTS` `$60` for a 2-byte stack push and pull, and `JSL` `$22` and `RTL` `$6B` for a 3-byte push and pull."
  consequence: "This is where an instruction-level instrument belongs.  Counting executed opcodes here gives cumulative, repeatable state -- a count, a flag, a balance -- which unlike a latched snapshot of a moving value does not depend on catching an instant and therefore cannot fail a repeatability test.  Three cycles of this project (core-log entries 32 to 34) built bus monitors that sampled the program counter and stack and could not be made repeatable; the reading that held was this one.  A balance of `JSL`s not yet returned from by an `RTL` follows directly, and an `RTL` finding the balance at zero is a long return through a stack that no long call built.  The one gap to know about: a `JSL` executed while `GotInterrupt` is set is skipped by the gate, so a legitimate `RTL` after it would be counted as unmatched -- the flag is sound when set on the first `RTL` of a boot but is worth confirming against the `seen_jsl` flag when `JSL`s are in play."
  sources:
    - "SNESTang commit 5f0ef19, src/65C816/P65C816.v: the WAIExec/STPExec set at STATE 0 with EN and ~GotInterrupt, and `assign EN = RDY_IN & CE & (~WAIExec) & (~STPExec)`"
    - "This repository, fpga/snes/src/65C816/P65C816.v: the TinySNES diagnostic counters and DBG_REG 0x17/0x18"
  verification: "Measured on 2026-11-01 (core-log entry 35): five boots of TINYSNES_INSN_PROBE reported the flag byte and balance, and three of the five had an `RTL` with no outstanding `JSL`.  The same five boots reproduced departure $1035 with SP=$01FD, the reading of core-log entry 33, in two of them."

- record_id: EXT-011
  kind: EXTERNAL
  topic_id: EXT
  title: "The 65816 core's JSR, JSL, RTS and RTL microcode push and pull the correct number of stack bytes, so a JSR/RTL mismatch is not a width defect in the microcode"
  status: VERIFIED
  verified_date: 2026-11-01
  statement: "Read from `mcode.txt`, which is the hand-written source of the generated `mcode.sv` table.  `JSR` at `$20` (`M_TAB[256]` to `M_TAB[260]`) fetches the absolute operand into `AA` and then pushes `PCH` and `PCL`, two bytes, before loading `AA` into `PC`.  `JSL` at `$22` (`M_TAB[272]` to `M_TAB[278]`) pushes `PBR`, then `PCH`, then `PCL` -- three bytes -- and then loads the operand byte into `PBR`.  `RTS` at `$60` (`M_TAB[768]` to `M_TAB[772]`) pre-increments `SP`, pulls the two stack bytes into `DR` and `PC`, and then increments `PC` once more.  `RTL` at `$6B` (`M_TAB[856]` to `M_TAB[860]`) pre-increments `SP`, pulls `PCL` and `PCH` into `PC`, then pulls one more byte into `PBR`.  Every one of the four matches the 65816's documented behaviour: short calls and returns move two bytes, long calls and returns move three."
  consequence: "If the machine is observed executing an `RTL` after only a `JSR`, the mismatch is not that this core pushes or pulls the wrong number of bytes -- the microcode is correct and reading it took minutes and no hardware.  The mismatch has to come from what the CPU decided to execute, which points at the instruction stream, the stack pointer, or the flags that select the operand width rather than at the call/return microcode.  This is worth knowing before any more hardware is spent on the return path: the obvious suspect was cleared by inspection."
  sources:
    - "SNESTang commit 5f0ef19, src/65C816/mcode.txt: the 20 JSR, 22 JSR LONG, 60 RTS and 6B RTL sequences"
  verification: "Read directly from mcode.txt on 2026-11-01 (core-log entry 36) after a hardware instrument reported an RTL with no outstanding JSL.  The push and pull counts were traced through the M_TAB entries by their annotation comments rather than inferred."

- record_id: TCL-019
  kind: TOOLCHAIN
  topic_id: TCL
  title: "The 65816 core's fastrom access window is three master clocks, and a cartridge that answers on the fourth desynchronises the instruction stream"
  status: VERIFIED
  verified_date: 2026-11-01
  statement: "In `cpu.v` the `SPEED` output selects the access length from the address: banks `$80-$FF` at `$8000-$FFFF` take `SLOWFAST` once `MEMSEL` (`$420D`) is set and `SLOW` before that, and `SLOW` is roughly two master clocks longer.  Measured in the bench in `tools/sim/snes_tb.sv`, which instantiates the real `SNES.v` against a behavioural cartridge whose answer can be delayed by `+lat` master clocks: with the image's own `STA $420D` left in place the machine runs a million cycles without leaving the cartridge at `+lat=2` and `+lat=3`, and departs within about 1400 cycles at `+lat=4` and `+lat=5`; with that one store redirected to `$4200` so `MEMSEL` is never set, the same bench runs clean at `+lat=4` and `+lat=5` and only departs at `+lat=6`.  The captured read path answers between the second and fourth master clock (`TINYSNES_FETCH_PROBE`: `ROM_Q` zero at assert and at +2, `$8000` at +4), which puts the hardware on the wrong side of the fastrom threshold and inside the slowrom one.  The failure is not a control-flow fault: the per-instruction log of committed opcodes shows the decode desynchronising immediately after the `STA $420D`, with operand bytes being executed as opcodes."
  consequence: "A cartridge path slower than six master clocks cannot be run in fastrom mode, whatever the header says, and the symptom is not a slow machine but a machine that leaves the cartridge after a handful of instructions and executes open bus -- which presents as nondeterminism, a program counter seen in WRAM or expansion space, and ROM access counts in the millions while nothing progresses.  `TINYSNES_FORCE_SLOW_ROM` in `cpu.v` forces `SLOW` for those banks and restores about two master clocks of margin; the bench shows it holding at `+lat=4` and `+lat=5`.  Before this bench existed the same define had been tried and recorded as a negative result, but that attempt was made on a tree whose ROM read returned zero (core-log entries 25 to 28), so the negative was an artefact of a different fault.  Any future bring-up on a new board should measure the cartridge's answer time first and decide the rom-speed mode from it rather than from the header byte."
  sources:
    - "SNESTang commit 5f0ef19, src/cpu.v: the SPEED selection for banks $80-$FF and the TINYSNES_FORCE_SLOW_ROM override"
    - "This repository, tools/sim/snes_tb.sv and tools/sim/run_sim.sh: the full-core bench and its +lat cartridge model"
  verification: "Measured on 2026-11-01 (core-log entry 37) with the full-core bench: a two-by-two matrix over cartridge latency and rom-speed mode separated the fault cleanly, `+lat=3` passing and `+lat=4` failing with MEMSEL set on the same image, and the committed-opcode log located the desynchronisation at the instruction immediately after the MEMSEL store."

- record_id: BRD-005
  kind: BOARD
  topic_id: BRD
  title: "On this board the same netlist can boot or leave the cartridge depending only on which seed placed it, so a placement that routes clean is not the same as a placement that runs"
  status: VERIFIED
  verified_date: 2026-11-01
  statement: "Two builds of the identical source, both with `TINYSNES_FORCE_SLOW_ROM` and both free of hold violations, behave differently on hardware.  The seed 9 build places `hclk` through `SPINE24/CBRIDGEOUT_BOTTOM2` and `iosys.clk` through `SPINE16/CBRIDGEOUT_TOP0` and boots deterministically: ten boots of five, run twice, every one reporting no departure from the cartridge and the same flag byte.  The seed 5 and seed 11 builds route `hclk` through `SPINE27` and `SPINE25` respectively and both leave the cartridge on every boot sampled, at `$1035` or `$1036` with `SP` at `$01FD`.  All three pass the Fmax gate and none reports a hold violation, so the difference is not visible in either timing check."
  consequence: "A hold-clean placement is necessary but not sufficient for this design to run, and the project's rule that a measurement build must route clean is weaker than it looks -- the outcome has to be confirmed by booting, not inferred from the timing report.  The variable that separates the passing build from the failing ones is which spine the master clock takes, which is the same quantity TCL-015 and the clock-plane work of core-log entries 22 to 24 were about, and it now has a binary observable attached to it: whether the machine departs the cartridge.  `tools/clock_plane_report.py` prints the spine assignment for every build, so a candidate placement can be judged before deployment and the seed chosen for the spine it produces rather than for the absence of hold violations."
  sources:
    - "This repository, build/is9.log, build/is5.log and build/is11.log: the clock-plane reports and Fmax for the three builds"
    - "This repository, tools/clock_plane_report.py"
  verification: "Measured on 2026-11-01 (core-log entry 38) over fifteen hardware boots of three hold-clean builds of the same source, with the seed 9 build sampled twice to confirm its result repeats."

- record_id: EXT-012
  kind: EXTERNAL
  topic_id: EXT
  title: "The APU boot handshake and the sound upload complete correctly on this core, and a whole 65816 boot to a displayed picture takes about 30 million master clocks"
  status: VERIFIED
  verified_date: 2026-11-01
  statement: "Traced from inside the full-core bench.  The 65816 writes `$CC` to CPUI port 0 at `$88EC`; the IPL echoes it into CPUO at `$FFF5`; the 65816 then loads a transfer address into CPUI 2 and 3, and the upload proceeds one byte at a time, each byte acknowledged by CPUO echoing the index in its low byte and the byte in its high byte.  Measured cost is 521 master clocks per byte, constant across the whole transfer, at about 21.5 MHz that is 24 microseconds a byte.  At cycle 28271823 the SPC700 leaves its IPL ROM and begins executing at `$0800` in ARAM, and at cycle 28463228 the 65816 writes `$81` to `$4200`, enabling NMI.  The game's initialisation then runs, reaching `$87C0` and the NMI handler at `$89D8`, and by cycle 30952029 it writes `$0F` to `$2100`, turning the display on.  Over the boot the 65816 writes 34 distinct PPU registers including `$2105` BGMODE, `$2107` to `$210C` the tilemaps, `$2115` to `$2119` VRAM and CGRAM, `$212C` to `$212F` the screen designation and window registers, and `$2130` to `$2133` colour math, and the PPU produces 7135 colour changes across 30117806 visible pixels."
  consequence: "There is no deadlock in the APU link on this core and no defect in the upload: entries 8 to 12 recorded a machine that had stopped partway, and what had actually happened is that the transfer had not finished yet.  The practical consequence is that a boot takes roughly 1.4 seconds of wall clock on hardware at 21.5 MHz, dominated by the sound upload, so a capture taken four seconds after loading should in principle see a booted machine -- which makes the hardware failure of core-log entry 39 a different fault, not a slow one.  The instruments that sampled the 65816 inside its upload loop (entries 8, 11, 12, 31, 33, 35 and 38) were all reading a machine in the middle of a working transfer, which is why each of them found a plausible but partial state."
  sources:
    - "This repository, tools/sim/snes_tb.sv: the APU link, PPU write and video logs"
    - "SNESTang commit 5f0ef19, src/smp.v: the CPUI/CPUO port banks and the IPL echo"
  verification: "Measured on 2026-11-01 (core-log entry 39) in the full-core bench: a 40 million clock run at cartridge latency 4 with slowrom timing reaches the displayed picture, with the SPC exit, the NMI enable and the `$2100` write each timestamped from the trace."

- record_id: EXT-013
  kind: EXTERNAL
  topic_id: EXT
  title: "The cartridge DSP (uPD77C25) is a fixed math coprocessor with no audio path, so no SNES title can use it to expand sound"
  status: VERIFIED
  verified_date: 2026-11-03
  statement: "The SNES has two unrelated chips called DSP. The S-DSP is the audio chip inside the console, implemented here as `fpga/snes/src/dsp.v`; it has eight BRR voices and is present in every machine. The cartridge DSP is a NEC uPD77C25 microcontroller, implemented here as `fpga/snes/src/chip/DSP/DSPn.v`, whose microcode lives in mask ROM burned at manufacture and therefore cannot be reprogrammed by a game.  fullsnes lists its complete DSP-1 command set: 16-bit multiplication, inverse calculation, set attitude A/B/C, projection parameter setting, object-to-global and global-to-object coordinate conversion, trigonometric calculation, 3D angle rotation, vector size calculation and comparison, vector absolute value, raster data calculation, inner product with attitude, 2D and 3D coordinate rotation, screen-point coordinate calculation, and three test commands.  Every command is arithmetic; none addresses audio.  The titles that use it are correspondingly 3D and vector workloads -- Pilotwings, Super Mario Kart, Ballz 3D, Suzuka 8 Hours, the Genki racing games.  Structurally the path does not exist either: `DSPn.v` and `chip/GSU/GSUMap.v` declare no APU, ARAM or SMP port of any kind, and the only route between the 65816 and the sound side is the four-byte handshake at `$2140-$2143` recorded in EXT-005."
  consequence: "So there is no SNES analogue of a Famicom cartridge adding sound channels, and the question 'which cartridge stresses the audio expansion' has no referent: the NES had almost no sound hardware and the cart had to supply it, whereas the SNES put a complete eight-voice sampler in the console and every cartridge gets identical hardware.  What varies between titles is only which S-DSP features a sound driver exercises, so audio coverage is obtained by choosing titles that stress distinct features -- echo with FIR feedback, the noise channel, pitch modulation, dense eight-voice mixing -- and not by hunting for special hardware.  The one genuine cartridge audio coprocessor is the MSU-1, which streams CD-quality audio and bypasses the S-DSP entirely; it is a homemade chip by Near with no retail release and no physical form, living in bsnes and in sd2snes firmware, so supporting it would mean implementing a new coprocessor rather than testing the existing one -- and it bypasses rather than exercises the S-DSP, so it is not an audio test for this core at all.  The cartridge audio input it uses is real and predates it: the one retail product that fed that pin was the Super Game Boy, which mixes a Game Boy's audio into the SNES output, so the slot provably could carry sound and no retail SNES title ever chose to.  A programmable coprocessor could in principle compute samples and hand them to the 65816 to upload, and the SuperFX is a real CPU able to do so, but no title is known to do it and this project has no evidence that one does."
  sources:
    - "fullsnes (nocash), the SNES cart DSP-n/ST010/ST011 section: the uPD77C25 description, the full DSP1 command list and the list of DSP-1 titles"
    - "fullsnes (nocash), the APU memory and I/O map, which lists `2000h-2007h MSU1: Media Streaming Unit (homebrew)`, and the audio mixer diagram note that the cartridge audio input is used only by the SGB and MSU1"
    - "SnesLab wiki, MSU1: `a homemade enhancement chip made by Near/Byuu for the SNES`, emulated by bsnes and supported by sd2snes"
    - "This repository, fpga/snes/src/dsp.v (the S-DSP) and fpga/snes/src/chip/DSP/DSPn.v (the cartridge DSP), and their port lists"
    - "This repository, fpga/snes/src/chip/GSU/GSUMap.v: no APU, ARAM or SMP port"
  verification: "Read from fullsnes and checked against this tree's RTL on 2026-11-03 (core-log entry 82), while answering whether any cartridge could use the coprocessor for sound generation: a port search over DSPn.v and GSUMap.v returns no APU or ARAM connection, so the hardware path is absent independently of the command set.  Revised 2026-11-03 (core-log entry 83): the MSU-1 sentence was sharpened from `homebrew-era hardware with no retail releases` to its actual identity and status, because the earlier wording left it ambiguous whether such silicon had ever shipped.  MSU-1 is `Media Streaming Unit revision 1`, a homemade enhancement chip by Near (byuu), present in no retail cartridge and in no physical form: it exists as emulation in bsnes and as flashcart firmware in sd2snes, registered at `$2000-$2007` and identifying as `S-MSU1`, streaming up to 4 GB and CD-quality stereo from a `.msu` data file beside the ROM.  A related correction is more useful than the chip itself: the SNES cartridge slot does carry a stereo audio input that is mixed into the console's output, so the provision for a cartridge to supply its own sound did exist in hardware.  fullsnes records that path as used only by the SGB and the MSU1, which makes the Super Game Boy the one retail cartridge that used it -- it passes an entire second console's audio through the SNES mixer rather than adding channels, so it is the nearest retail analogue to a Famicom sound-expansion cart without being a SNES sound expander.  Neither the SGB nor the MSU-1 is supported by this core, and `main.v` carries commented-out `MSU_TRACK_*` ports left unconnected from upstream."

- record_id: BRD-003
  kind: BOARD
  topic_id: BRD
  title: "Core bring-up: one-wire loads over the FT2232 with openFPGALoader, two-wire over tangload, and the console may drop after a load"
  status: VERIFIED
  verified_date: 2026-10-30
  statement: "With the board cold-started on the OTG cable alone, the host enumerates the SIPEED FT2232 (0403:6010) with /dev/ttyUSB0 and /dev/ttyUSB1, and openFPGALoader -b tangconsole writes a .fs into SRAM, reporting 'Load SRAM ... Done'.  The bitstream can then be loaded with tools/load_snes_rom.py --uart /dev/ttyUSB1, which talks the frame protocol straight at the core.  With the board on its power input it enumerates the TinyTang CDC (ffff:5454) as /dev/ttyACM0, tangload loads a .bin from the card, and the core answers 'fpga: core N answering on UART1 at 2000000 baud'.  After a tangload the console was seen several times to report readiness but return no data until the port was reopened or the board power-cycled.  The tangconsole board definition exists in openFPGALoader v1.1.1, which is the copy shipped in oss-cad-suite, and not in the version packaged as /usr/bin/openFPGALoader v0.13.1, which answers 'cannot find board tangconsole'."
  consequence: "One-wire is the faster loop for video work (no card copy, no firmware in the way) and it also lets the host drive the core's UART directly at /dev/ttyUSB1, 2000000 baud 8N1, which is how the ROM and OSD frames were sent without the firmware.  Two-wire is needed only for the card and the shell.  Use the oss-cad-suite copy of openFPGALoader for one-wire, and treat a dead console after tangload as expected noise: reopen the port before concluding anything."
  sources:
    - "Observed on this bench on 2026-10-30 and again on 2026-10-31: lsusb, /dev/serial/by-id, openFPGALoader -b tangconsole, tangload output, fpga output"
    - "openFPGALoader --Version and --list-boards for both installed copies"
    - "TinyTang .ai/core-reference.md BRD-006 and USB-009 for the mode selection, and this project's core-log entry 2 for the observed drops"
  verification: "Both paths exercised repeatedly; the FT2232 enumeration, the openFPGALoader load and the tangload load each reported success, and the console drops were seen three times after tangload and cleared by a power cycle.  Revised 2026-10-31 (core-log entry 5): one-wire was used for a whole cycle for the first time, the oss-cad-suite copy of openFPGALoader was required because the system copy has no tangconsole board, and the ROM was streamed at the core's own UART rather than through the console.  Revised 2026-10-31 (core-log entry 18): a repeatable way to compare boots exists -- `tools/sample_boot_states.py` reloads one bitstream, streams the ROM, captures and decodes, and reports the distinct states over N boots, with `--layout` selecting the link or trace display -- and five boots of one identical image and bitstream produced five distinct states, so a result measured on a single boot is a sample and must be reported as one.  Revised 2026-10-31 (core-log entry 17): two operational facts cost time this session.  An openFPGALoader run that reports Done can still leave the board showing no signal at all, while the placement of the HDMI clocks matches a known-good build exactly; reloading the same file fixes it, so a silent no-video result is a failed SRAM load until proven otherwise, and placement should be compared before the design is suspected.  Reloading also clears the core's `loaded` state, so the ROM has to be streamed again after every bitstream load -- a diagnostic that reads blue after a reload is waiting for a ROM, not running slowly."

- record_id: BRD-004
  kind: BOARD
  topic_id: BRD
  title: "The console's tangput and tangget move raw files over USB, and a CRLF-terminated tangput shifts the file by one byte"
  status: VERIFIED
  verified_date: 2026-10-31
  statement: "TinyTang's shell has `tangput <size> <path>` to receive exactly <size> raw bytes from the USB console into a file on the card and `tangget <path> [offset [length]]` to send them back, which is how a core image reaches the card with no card reader.  The shell consumes the CR that ends a command, so a CRLF terminator leaves the LF in the console's input queue: tangput writes it as the file's first byte and drops the image's last byte, and the file's size still matches what was sent.  tangget answers with 'tangget: <n> bytes at <offset> of <total>' before the raw bytes begin."
  consequence: "Terminate tangput's command line with a bare CR, and verify an upload by pulling bytes back with tangget instead of trusting the size, because the corrupt upload in core-log entry 4 matched on size and differed only by that shift.  Transfer is otherwise quick and does not disturb the loaded core: about 1.2 MB/s, so a 4.7 MB core image takes seconds and a 1 MiB ROM about eleven seconds to pull back."
  sources:
    - "TinyTang ports/bl616/tdsh_tang_flash.c: cmd_tangput and cmd_tangget"
    - "Observed on this bench on 2026-10-31 over /dev/ttyACM0 against a TinyTang running in two-wire mode"
  verification: "Used on the board this session: the first upload, terminated with CRLF, came back from tangget shifted by one byte with a leading 0x0A; the second, with a bare CR, matched the local image at head, middle and tail."

```

---

## 6. Record template

```yaml
- record_id: <TOPIC>-<NNN>
  kind: DEVICE | BOARD | PROTOCOL | EXTERNAL | TOOLCHAIN
  topic_id: <TOPIC>
  title: "Short noun phrase"
  status: VERIFIED | SOURCED | INFERRED
  verified_date: YYYY-MM-DD
  statement: "What the source says, with exact values and units"
  consequence: "What it means for this project, or where it is implemented"
  sources:
    - "Document or repository, revision/commit/path/symbol, URL"
  verification: "How and when it was confirmed, or why it is not yet confirmed; then any 'Revised <date> (core-log entry N): ...' notes"
```

---

## 7. Maintenance boundary

This file holds external facts and the observations that confirm them. Build
results, timing numbers from a particular run, and decisions belong in
`core-log.md`; capacities and tool limitations belong here. When a record's
statement changes, revise it in place and note the revision date and the
core-log entry that changed it. When a record is retired, move its id to
section 8 rather than deleting the number.

---

## 8. Retired record ids

None.
