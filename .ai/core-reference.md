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
| Why did an ODDR SDRAM clock kill the picture? | TCL | TCL-009 |
| How long does a CPU-port ROM read take, and when does the CPU latch it? | TCL | TCL-010 |
| Why did a probe readout carry a different value in every row? | TCL | TCL-011 |
| Why did a diagnostic build draw nothing at all? | TCL | TCL-012 |
| Why does a sticky history bit always read as set? | TCL | TCL-013 |
| How do I load a core in one-wire versus two-wire? | BRD | BRD-003 |
| How does a core image or ROM get onto the card? | BRD | BRD-004 |

---

## 4. Fast lookup index

DEV-001 part and revision · DEV-002 capacity
BRD-001 SDRAM pins · BRD-002 clock enable
PRO-001 core ID 2 versus TinyTang's table
EXT-001 SNESTang console138k file list and clocks · EXT-002 hdl-util HDMI
TCL-001 slang front end and cell-library shim · TCL-002 SDC subset ·
TCL-003 net renaming · TCL-004 cell-name collisions · TCL-005 unsupported constructs ·
TCL-006 HDMI clock shape and placements · TCL-007 SDRAM capture and the fetch path
TCL-008 diagnostic builds · TCL-009 ODDR costs the HDMI route · TCL-010 read latency and the CPU's latch ·
TCL-011 a probe bus must be latched to be photographed · TCL-012 `elsif` with two macros selects nothing ·
TCL-013 a sticky bit must be armed against its reset value
EXT-003 TangCore ROM loader · BRD-003 one-wire and two-wire loading · BRD-004 console file transfer
EXT-004 the SCPU debug port as a bench instrument · EXT-005 the APU port banks and IPL boot ·
EXT-006 the IPL block-copy protocol

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
  verification: "Code comparison read 2026-10-30; the self-test result was then measured on the board that day (core-log entry 3).  Revised 2026-10-30 (core-log entry 3): the record was SOURCED and asserted that the capture was the fault behind the dead machine; the self-test refuted that.  Revised 2026-10-31 (core-log entry 4): the record asserted that the fetch path returned zero and that the fault lay between ROM_ADDR and ROM_Q; the five-stripe probe build read 0x0000, 0x0000, 0x8000, 0x7FFC, 0x007F on the board, which refutes that and moves the fault past the fetch path.  Revised 2026-10-31 (core-log entry 9): the ARAM half of this record's claim is now measured rather than inferred, by the direct port self-test, and is bounded -- see the arbitration caveat in that entry."

- record_id: TCL-008
  kind: TOOLCHAIN
  topic_id: TCL
  title: "Eleven diagnostic builds behind TINYSNES_* defines, each with a known-good readout"
  status: VERIFIED
  verified_date: 2026-10-31
  statement: "Each diagnostic is selected with TINYSNES_DEFINES and drawn by snes2hdmi, so the result is read off the screen with no logic analyser and no loader changes.  Eleven are defined: TINYSNES_SDRAM_TEST, TINYSNES_LOAD_COUNT, TINYSNES_ROM_CHECK, TINYSNES_FETCH_PROBE, TINYSNES_CPU_PROBE, TINYSNES_TRACE_PROBE, TINYSNES_LIVE_PROBE, TINYSNES_APU_PROBE, TINYSNES_ARAM_TEST, TINYSNES_IPL_PROBE and TINYSNES_LINK_PROBE.  TINYSNES_SDRAM_TEST runs sdram_bist.v before the machine starts: 16 gapped bars, one per DQ bit, red where a bit mismatched, plus a status band (green pass, red mismatch, blue running, yellow no acknowledge).  TINYSNES_LOAD_COUNT shows eight gated thresholds on the count of the loader's own SDRAM write issues, >=1 up to >=500000 words, and all eight green means a full 1 MiB image was issued.  TINYSNES_ROM_CHECK runs rom_probe.v after loaded and searches eight candidate word addresses for a named image word, green where found in either byte order.  TINYSNES_FETCH_PROBE and TINYSNES_CPU_PROBE share one display behind TINYSNES_PROBE_BARS: five stripes of 16 bars, bit 0 on the left and green for 1, 24 rows tall with an 8-row gap, plus a status band in rows 192-223.  The fetch probe's stripes are ROM_Q at the first assertion of ROMSEL and two and four mclk later plus ROM_ADDR[15:0] and ROM_ADDR[23:8] for that access; the CPU probe's are the ROM access counter's two halves, then PC at the most recent sample, SP and the CPU status byte from DBG_REG 0x15; the trace probe's are the last four ROM addresses, newest first, plus ROM_ADDR[23:8] of the newest; the APU probe's are CPUO ports 1 and 0, the 65816's A, the 65816's PC, the SPC700's PC and then the 65816's P above CPUI port 0.  TINYSNES_ARAM_TEST runs aram_bist.v, a byte-lane-aware write and read-back through the controller's ARAM port with no ROM loaded, and draws the same 16 bars and status band as TINYSNES_SDRAM_TEST -- bits 0-7 the even lane, 8-15 the odd -- with green meaning every bit read back correctly.  The two memory tests share the display through a TINYSNES_BIST_BARS define; see TCL-012 for why they cannot share it through one `elsif` expression.  TINYSNES_IPL_PROBE polls the SPC700's program counter and latches the first value below $FFC0 once the IPL range has been seen, which is the target of the IPL's `JMP [$0000+X]`, together with A and X at that moment, the current PC and all four CPUI bytes; its display is the five probe stripes and its band reads R = exit_seen, G = loaded, B = enable.  TINYSNES_LINK_PROBE carries both directions of the APU link and both CPUs in one snapshot -- CPUO ports 1 and 0, CPUI ports 1 and 0, the 65816's A, the 65816's PC and the SPC700's Y -- which is the pairing the deadlock needs, because the APU probe has CPUO and A while the IPL probe has Y and the CPUI banks, and the top stripe carries four sticky history bits saying whether CPUI port 0 has ever held $CC, whether CPUO has changed away from $AA, whether Y has ever been non-zero, and whether the SPC's PC has left the IPL, plus a bit saying the 65816 has been past $8894 and a 3-bit saturating count of visits to $8888; see TCL-013 for why two of those bits have to be armed and why a visit counter must count transitions rather than samples.  The live probe is the exception: it draws only two stripes over the machine's own picture, so one frame shows what the CPU is doing and what the PPU is drawing."
  consequence: "Use these to bisect the machine rather than adding new probes: memory, loader, fetch and CPU state each have an instrument with a recorded expected readout.  The letterbox border doubles as a three-bit state display under TINYSNES_DBG_BORDER, and its bit assignment changes between builds, so always read the comment at the snes2hdmi instantiation before decoding a colour.  A probe's own correctness is not self-evident and has been wrong more often than the machine: simulate the sampler with tools/tests/probe_tb.sh, which extracts the block verbatim from snestang_top.v, before reading anything into a readout."
  sources:
    - "This repository, fpga/snes/src/sdram_bist.v, fpga/snes/src/rom_probe.v, fpga/snes/src/snes2hdmi.v (the ifdef'd rgb branches), fpga/snes/src/snestang_top.v (the ifdef'd CPU-port mux, write counter, fetch sampler and CPU sampler)"
    - "tools/build_tinysnes.sh: TINYSNES_DEFINES, and tools/rom_probe_expect.py for the expectations"
    - "tools/tests/probe_tb.sh, tools/tests/fetch_probe_tb.sv, tools/tests/cpu_probe_tb.sv"
    - "tools/decode_probe_frame.py: decodes the five stripes from captured frames and discards torn ones"
  verification: "Each build was run on the board and its readout recorded in core-log entries 3, 5, 6 and 8.  A counter in each sampler must detect a real edge: storing the inverted level and testing asserted-level AND stored-level counts every master clock a select is held, which read as 21.5 M accesses per second and tore the trace ring, and the benches now hold the select low for six clocks so the defect cannot return.  Two instrument defects were found and fixed during that work and are worth remembering: a probe that owned the CPU port from reset disconnected the loader's writes, and expectations passed as -DTINYSNES_EXP* never reached the module's EXP parameters, so every comparison ran against zero.  Revised 2026-10-31 (core-log entry 4): TINYSNES_FETCH_PROBE now samples the access three times instead of once and also carries the mapper's address, because the single sample at the first ROMSEL assertion could never see data and its all-zero readout was read as a machine fault for a cycle.  Revised 2026-10-31 (core-log entry 5): TINYSNES_CPU_PROBE was added and both probes were put behind one display, and its bench caught two defects of its own before hardware -- a constant on the right of always @(*) never drives, and 16-bit registers holding one byte truncated the assembled PC to its high byte.  Revised 2026-10-31 (core-log entry 8): TINYSNES_APU_PROBE was redesigned from the SPC700's A and Y to the 65816's side of the handshake, because the SPC700's A, X and Y are all $00 both while it waits and on a dead port (see EXT-005) and could not have answered the question that cycle asked; the payload is now CPUO ports 1 and 0, the 65816's A, PC and P, the SPC700's PC and CPUI port 0, each PC's high byte is read on both sides of its low byte and accepted only when the two agree, and the display was made a latched snapshot for the reason in TCL-011.  Revised 2026-10-31 (core-log entry 9): TINYSNES_ARAM_TEST was added as a ninth build, and its first appearance drew nothing because of the `elsif` trap now recorded as TCL-012.  Revised 2026-10-31 (core-log entry 10): TINYSNES_IPL_PROBE was added as a tenth build, and it refuted the ARAM-execution inference that entry 8 had drawn from an APU-probe program-counter reading -- on the later boot the SPC700 never left its IPL ROM at all.  Revised 2026-10-31 (core-log entry 12): TINYSNES_LINK_PROBE was added as an eleventh build to pair both link directions with both CPUs.  Revised 2026-10-31 (core-log entry 13): the link probe's SPC700-PC stripe was replaced by the 65816's PC to date the desync, which answered that question and exposed a second one -- a single snapshot cannot tell a processor that never advanced from one that advanced and restarted, so the next build needs sticky history bits rather than more current-state fields.  Revised 2026-10-31 (core-log entry 14): the sticky bits were added, and the first build of them was wrong -- two were unarmed and self-set at reset, so they reported all three set; armed and rebuilt, all three read clear.  Revised 2026-10-31 (core-log entry 15): a fourth bit was added for CPUI port 0 ever holding $CC, and the next boot set all four and reached a materially deeper state, which withdraws entry 14's reading of all-clear as a general statement about the machine -- it described one boot, and the failure depth varies between boots.  Revised 2026-10-31 (core-log entry 16): a past-the-handshake bit and a routine-entry counter were added; the next boot read four routine entries with the CPU afterwards cycling at $7C7C-$7C7F, below the LoROM window, which is entry 5's jump-to-self signature and means four consecutive loads of the same image have produced four different failure shapes."

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
  consequence: "The SPC700 acknowledges an index by writing its own Y into CPUO port 0 and immediately increments Y, so CPUO port 0 reads one less than the SPC's current Y whenever the loop is waiting.  It only advances when CPUI port 0 equals its Y, which makes the protocol one-way synchronised: a 65816 that falls behind by even one index can never catch up, because the SPC is waiting for a value the 65816 has already passed, and the 65816 is waiting for an echo of the value it holds.  That is the shape of a permanent desync rather than a slow transfer, and it is why a gap between Y and CPUI port 0 is the measurement to take.  The `JMP [$0000+X]` at $FFFB takes its address from ARAM $0000 and $0001, which the same routine has just loaded from CPUI ports 2 and 3, so the jump target is the transfer address the 65816 wrote to $2142 and $2143."
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
  verification: "Both paths exercised repeatedly; the FT2232 enumeration, the openFPGALoader load and the tangload load each reported success, and the console drops were seen three times after tangload and cleared by a power cycle.  Revised 2026-10-31 (core-log entry 5): one-wire was used for a whole cycle for the first time, the oss-cad-suite copy of openFPGALoader was required because the system copy has no tangconsole board, and the ROM was streamed at the core's own UART rather than through the console."

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
