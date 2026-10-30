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
session to establish: see TCL-002, TCL-004, TCL-005 and BRD-002.

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

---

## 4. Fast lookup index

DEV-001 part and revision · DEV-002 capacity
BRD-001 SDRAM pins · BRD-002 clock enable
PRO-001 core ID 2 versus TinyTang's table
EXT-001 SNESTang console138k file list and clocks · EXT-002 hdl-util HDMI
TCL-001 slang front end and cell-library shim · TCL-002 SDC subset ·
TCL-003 net renaming · TCL-004 cell-name collisions · TCL-005 unsupported constructs

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
