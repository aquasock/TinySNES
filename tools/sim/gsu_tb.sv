`timescale 1ns/1ps
// SPDX-License-Identifier: MIT
//
// Full-machine bench for the cartridge coprocessors, starting with the GSU.
//
// Why this exists.  Six hardware cycles (core-log entries 59 to 64) probed the
// SuperFX through a stripe display read off a capture card, one 16-bit word per
// forty-minute round, and produced five decode errors along the way.  The
// conclusion those cycles reached is that Star Fox's coprocessor is started,
// executes STOP almost immediately, and leaves the 65816 polling a halted GSU --
// but that conclusion rests entirely on hardware readings with no simulation to
// compare against, because snes_tb.sv instantiates SNES.v, which has no
// cartridge mapper, while the GSU lives one level up in main.v.  The GSU has
// never been simulated in this project.
//
// This bench instantiates main.v -- the real mapper, the real GSU, the real
// CPU/PPU/APU under it -- with USE_GSU enabled, so every internal signal is
// visible at once instead of one stripe per round.
//
// What is real: main.v and everything under it.  What is modelled: the
// cartridge, WRAM, VRAM, ARAM and battery SRAM, which on the board live in
// SDRAM behind a hand-tuned PHY.  Modelling them is the point: it takes the
// SDRAM capture out of the experiment so a failure here is the core's.
//
// ROM_TYPE is driven directly rather than parsed.  On the board snestang_top's
// smc_parser turns the cartridge header into rom_type; here the bench states it,
// which is what makes one variable at a time possible.  $70 is what smc_parser
// produces for a GSU cartridge (map $20, type $13) -- see smc_parser.v.
//
// Options, all plusargs so one binary serves every experiment:
//   +hex=path      pre-converted one-byte-per-line hex of the cartridge image
//   +cycles=N      master clocks to run, default 400000
//   +trace=path    write a GSU state trace to this file
//   +vcd=path      dump waves to this file
//
// The port list exists only for the C++ harness: a signal reached from C++ has to
// be a top-level output.  Nothing connects to these in a pure-SV run, where they
// are simply left open.
module gsu_tb (
  input  wire        clk,
  output wire        o_dotclk,
  output wire        o_hblankn,
  output wire        o_vblankn,
  output wire [8:0]  o_x,
  output wire [8:0]  o_y,
  output wire [14:0] o_rgb,
  output wire [7:0]  o_pbr,
  output wire [7:0]  o_pc_hi,
  output wire [7:0]  o_pc_lo,
  output wire [15:0] o_go_cnt,
  output wire [15:0] o_sfr,
  output wire [15:0] o_state_seen,
  output wire        o_stop_seen
);

  // ---------------------------------------------------------------- clocks
  localparam real MCLK_HZ = 21477272.0;
  localparam real MCLK_NS = 1.0e9 / MCLK_HZ;

  // clk is a top-level input driven by the C++ harness (tools/sim/sim_main.cpp).
  // A pure-SV run drives it from a testbench wrapper instead; see run_gsu_sim.sh,
  // which wraps this module for the --binary flow.

  reg rst_n  = 1'b0;
  reg enable = 1'b0;

  // ---------------------------------------------------------------- options
  //
  // The default is deliberately long.  This bench is watched as a live window
  // as well as run in batch, and the PPU does not put Star Fox's intro on
  // screen until roughly two hundred million clocks -- the coprocessor's first
  // start is near twenty million and the title sequence follows it.  A short
  // default makes the window a black rectangle that closes: that is exactly
  // what happened when $finish was first made to work here, at 400000.  Batch
  // runs pass +cycles explicitly, so this only governs the interactive case,
  // and one billion clocks is about sixteen minutes of wall time -- longer than
  // anyone watches, and still bounded rather than running forever.
  integer cycles_max = 1000000000;
  reg     reported = 1'b0;
  reg [1023:0] hex_path, trace_path, vcd_path, frame_path;

  // ------------------------------------------------------------- cart header
  // Star Fox (USA) (Rev 2): LoROM, type $13, rom size $0A (1MByte).
  // rom_type $70 = what smc_parser makes of map $20 + type $13, i.e. GSU.
  //
  // It must NOT be $70 from reset.  main.v selects its ROM-port owner with
  // `case (MAP_ACTIVE)`, and MAP_ACTIVE[2] is GSUMap's MAP_SEL, which is
  // rom_type[7:4]==7.  Driving $70 from cycle 0 therefore hands the cartridge
  // port to the GSU before the 65816 has fetched its reset vector.  On the board
  // smc_parser only produces $70 after the 64-byte header has streamed in, so
  // the CPU boots through the plain mapper first.  The bench has to do the same
  // or it tests a machine that never existed: with $70 from reset the CPU never
  // left a two-address loop in 30 million clocks.
  reg [7:0]  ROM_TYPE = 8'h00;
  // The mapper chip bits, set from +romtype once the header "arrives".  $70 is
  // what smc_parser makes of map $20 + type $13 (GSU, Star Fox); $20 is a plain
  // LoROM cartridge with no coprocessor, which is what a control run needs.
  integer    romtype_val = 8'h70;
  reg [23:0] ROM_MASK = 24'h0F_FFFF;   // 1 MByte
  reg [23:0] RAM_MASK = 24'h00_07FF;   // 2 KByte battery SRAM

  // ------------------------------------------------------------- bus wires
  wire [23:0] ROM_ADDR;
  wire [15:0] ROM_D, ROM_Q;
  wire        ROM_CE_N, ROM_OE_N, ROM_WE_N, ROM_WORD;
  wire [19:0] BSRAM_ADDR;
  wire [7:0]  BSRAM_D, BSRAM_Q;
  wire        BSRAM_CE_N, BSRAM_OE_N, BSRAM_WE_N, BSRAM_RD_N;
  wire [16:0] WRAM_ADDR;
  wire [7:0]  WRAM_D;
  reg  [7:0]  WRAM_Q;
  wire        WRAM_CE_N, WRAM_OE_N, WRAM_WE_N, WRAM_RD_N;
  wire [15:0] VRAM1_ADDR, VRAM2_ADDR;
  reg  [7:0]  VRAM1_DI, VRAM2_DI;
  wire [7:0]  VRAM1_DO, VRAM2_DO;
  wire        VRAM1_WE_N, VRAM2_WE_N, VRAM_OE_N;
  wire [15:0] ARAM_ADDR;
  wire [7:0]  ARAM_D;
  reg  [7:0]  ARAM_Q;
  wire        ARAM_CE_N, ARAM_OE_N, ARAM_WE_N;
  wire        HIGH_RES, FIELD, INTERLACE, DOTCLK;
  wire [14:0] RGB_OUT;
  wire        HBLANKn, VBLANKn;
  wire [8:0]  X_OUT, Y_OUT;
  wire        JOY_STRB, JOY1_CLK, JOY2_CLK, JOY1_P6, JOY2_P6;
  wire        DOT_CLK_CE, AUDIO_READY;
  wire [15:0] AUDIO_L, AUDIO_R;
  wire        SYSCLKF_CE, SYSCLKR_CE, REFRESH;
  wire [7:0]  DBG_DAT_OUT;
  wire        DBG_BREAK;

  reg  [7:0]  DBG_SEL = 8'h00, DBG_REG = 8'h00, DBG_DAT_IN = 8'h00;
  reg         DBG_REG_WR = 1'b0;

  // ------------------------------------------------------- GSU debug outputs
  wire [15:0] GSU_GO_CNT, GSU_SFR, GSU_STATE_SEEN;
  wire        GSU_FLAG_GO, GSU_CACHE_ANY, GSU_EN;
  wire [2:0]  GSU_ROMST;
  wire        GSU_IN_CACHE, GSU_ROM_CACHE_WAIT, GSU_ROM_LOAD_WAIT;
  wire        GSU_CACHE_FILL_SEEN, GSU_CACHE_MMIO_SEEN;
  wire [6:0]  GSU_ROMST_SEEN;
  wire        GSU_FLAG_GO_INT, GSU_FLAG_R_INT, GSU_STOP_SEEN;
  wire [7:0]  GSU_CF_ADDR, GSU_CF_B0, GSU_CF_B1, GSU_CF_B2, GSU_CF_B3, GSU_FIRST_OP;
  wire        GSU_CACHE_EN, GSU_FETCH_OP_SEEN;

  // ------------------------------------------------------------ ROM model
  // One byte per line, produced by run_sim.sh from the .sfc.
  reg [7:0] rom [0:1048575];
  integer i;

  initial begin
    hex_path = 0;
    trace_path = 0;
    vcd_path = 0;
    frame_path = 0;
    void'($value$plusargs("hex=%s", hex_path));
    void'($value$plusargs("frame=%s", frame_path));
    void'($value$plusargs("romtype=%d", romtype_val));
    void'($value$plusargs("lat=%d", rom_lat));
    void'($value$plusargs("glat=%d", gsu_lat));
    void'($value$plusargs("bwlat=%d", bwlat));
    void'($value$plusargs("bwreadnow=%d", bwreadnow));
    void'($value$plusargs("bwnodrop=%d", bwnodrop));
    void'($value$plusargs("rtog=%d", rtog));
    if (gsu_lat > 8) gsu_lat = 8;
    if (rom_lat > 8) rom_lat = 8;
    if (rom_lat < 0) rom_lat = 0;
    if (rom_lat != 0) $display("  [bench] cartridge latency %0d mclk", rom_lat);
    void'($value$plusargs("cycles=%d", cycles_max));
    void'($value$plusargs("trace=%s", trace_path));
    void'($value$plusargs("vcd=%s", vcd_path));
    if (hex_path == 0) begin
      $display("gsu_tb: +hex=<path> is required");
      $fatal(1);
    end
    $readmemh(hex_path, rom);
    $display("  [bench] rom[0]=%h rom[7FFC]=%h rom[7FFE]=%h rom[0x8000]=%h",
             rom[0], rom[16'h7FFC], rom[16'h7FFE], rom[16'h8000]);
    if (vcd_path != 0) begin
      $dumpfile(vcd_path);
      $dumpvars(0, gsu_tb);
    end
  end

  // ROM_ADDR from main.v is ALREADY a linear cartridge offset, not a CPU
  // address: both mappers here compute it (DSP_LHRomMap's `CART_ADDR & ROM_MASK`
  // and GSUMap's `{2'b00,ROM_A} & ROM_MASK`).  The first version of this bench
  // re-applied the LoROM bank formula to it and therefore fetched from the wrong
  // half of the image -- $1F:BDB1 became offset $07BDB1 instead of $0FBDB1 -- so
  // the CPU ran garbage, drifted out of the cartridge and never reached the GSU.
  // Indexing directly is the fix; snes_tb.sv remaps because SNES.v hands it CA
  // rather than a linear offset, which is the difference that misled me.
  // The board's cartridge lives in SDRAM behind a controller that answers about
  // four master clocks after the address appears (TCL-019), while this bench
  // would otherwise answer in the same clock.  +lat makes the model match the
  // hardware, and it is the difference most likely to separate "works in
  // simulation" from "works on the Tang": the GSU latches ROM_DI after counting
  // ROM_CYCLES of RON, and if the data is not there yet it latches garbage.
  integer rom_lat = 0;
  reg [7:0] rom_pipe [0:8];
  integer rp;
  initial begin
    for (rp = 0; rp < 9; rp = rp + 1) rom_pipe[rp] = 8'h00;
  end
  always @(posedge clk) begin
    for (rp = 8; rp > 0; rp = rp - 1) rom_pipe[rp] <= rom_pipe[rp-1];
    rom_pipe[0] <= rom[ROM_ADDR[19:0]];
  end
  // A second, independent delay for reads the GSU initiates.  +lat delays every
  // cartridge read, which makes it impossible to test the coprocessor beyond the
  // latency the 65816 itself tolerates: at +lat=6 the CPU freezes at $00:9E4A
  // and the GSU is never started, so the run says nothing about GSU timing.  On
  // the board the CPU clearly works at whatever its real latency is, since Zelda
  // and Super Mario Kart boot, so the GSU needs to be testable on its own.
  //
  // The GSU owns the ROM port whenever rom_type selects it (MAP_ACTIVE[2]), and
  // gsu_active below mirrors that.
  integer gsu_lat = -1;
  // Select on the GSU actually fetching, NOT on rom_type.  Keying on rom_type
  // matched every read while the GSU owned the port mux -- including the
  // 65816's own instruction fetches, which GSUMap passes straight through when
  // the GSU is idle -- so the CPU starved and go_cnt stayed 0 at every setting,
  // which is what gave the mistake away.
  wire gsu_active = (GSU_ROMST != 3'd0);
  wire [7:0] rom_q_slow = rom_pipe[rom_lat];
  wire [7:0] rom_q_gsu  = (gsu_lat >= 0) ? rom_pipe[gsu_lat] : rom_q_slow;
  // +rtog models the toggle-collapse on the ROM port.  snestang_top issues a
  // cartridge request with `cpu_req <= ~cpu_req` and the SDRAM controller
  // services on `cpu_req ^ cpu_ack`, a toggle pair: if a second address arrives
  // before the controller has serviced the first, the difference vanishes and
  // BOTH requests are lost, leaving ROM_Q stale.  Nothing applies back-pressure,
  // because the default build ties `mem_wait = 1'b0`.  A fixed delay (+lat,
  // +glat) cannot express this -- the delay is not the fault, the lost request
  // is -- which is why the bench could report a healthy coprocessor while the
  // board stalled.
  integer rtog = 0;
  integer rtog_busy = 0;
  integer rtog_lost = 0, rtog_seen = 0;
  reg [23:0] rtog_addr_q = 24'hFFFFFF;
  reg [7:0]  rom_q_held = 8'h00;
  always @(posedge clk) begin
    if (rtog_busy > 0) rtog_busy <= rtog_busy - 1;
    if (ROM_ADDR != rtog_addr_q) begin
      rtog_seen <= rtog_seen + 1;
      rtog_addr_q <= ROM_ADDR;
      if (rtog_busy > 0) rtog_lost <= rtog_lost + 1;   // toggle collapsed
      else rtog_busy <= rtog;
    end
    if (rtog == 0) rom_q_held <= rom[ROM_ADDR[19:0]];
    else if (rtog_busy == 0) rom_q_held <= rom[rtog_addr_q[19:0]];
  end
  wire [7:0] rom_q_final = (rtog == 0) ? (gsu_active ? rom_q_gsu : rom_q_slow)
                                       : (gsu_active ? rom_q_held : rom_q_slow);
  assign ROM_Q = {8'h00, rom_q_final};

  // ----------------------------------------------------------- WRAM model
  reg [7:0] wram [0:131071];
  initial for (i = 0; i < 131072; i = i + 1) wram[i] = 8'h00;
  always @(posedge clk) begin
    if (!WRAM_CE_N && !WRAM_WE_N) wram[WRAM_ADDR] <= WRAM_D;
    WRAM_Q <= wram[WRAM_ADDR];
  end

  // ----------------------------------------------------------- VRAM model
  // VRAM is 32K words of 16 bits, reached through two byte-wide ports: port A
  // carries the low byte of a word and port B the high byte.  They must NOT
  // share one array, because both would then write the same index and overwrite
  // each other -- which is what the first version of this bench did, and why its
  // picture was sparse garbage that never changed.  snes_tb models it as two
  // arrays for the same reason.
  reg [7:0] vram_lo [0:15'h7FFF];
  reg [7:0] vram_hi [0:15'h7FFF];
  initial begin
    for (i = 0; i < 32768; i = i + 1) begin
      vram_lo[i] = 8'h00;
      vram_hi[i] = 8'h00;
    end
  end
  always @(posedge clk) begin
    if (!VRAM1_WE_N) vram_lo[VRAM1_ADDR[14:0]] <= VRAM1_DO;
    if (!VRAM2_WE_N) vram_hi[VRAM2_ADDR[14:0]] <= VRAM2_DO;
    VRAM1_DI <= vram_lo[VRAM1_ADDR[14:0]];
    VRAM2_DI <= vram_hi[VRAM2_ADDR[14:0]];
  end

  // ----------------------------------------------------------- ARAM model
  reg [7:0] aram [0:65535];
  initial for (i = 0; i < 65536; i = i + 1) aram[i] = 8'h00;
  always @(posedge clk) begin
    if (!ARAM_CE_N && !ARAM_WE_N) aram[ARAM_ADDR] <= ARAM_D;
    ARAM_Q <= aram[ARAM_ADDR];
  end

  // ---------------------------------------------------------- BSRAM model
  // Star Fox's header declares no battery RAM, but the GSU uses this window as
  // its own work RAM, so the model must store.  It is the GSU's only writable
  // memory, and on the board it lives in the same SDRAM as the cartridge.
  //
  // +bwlat models the board's request/acknowledge handshake.  That handshake is
  // a toggle pair -- the controller services when `req ^ ack`, and both sides
  // flip a bit -- so if a second request arrives before the first is serviced
  // the difference disappears and BOTH are lost.  snestang_top passes
  // `.bsram_req_ack()` unconnected, so the GSU side never knows whether the
  // controller caught up.  With +bwlat=0 (the default) this bench answers
  // instantly and can never show the race, which is why the coprocessor looked
  // healthy in simulation and not on the board.
  integer bwlat = 0;
  integer bwreadnow = 0;
  integer bwnodrop = 0;
  integer bw_busy = 0;
  integer bw_dropped = 0;
  integer bw_writes = 0;
  reg [7:0] bsram [0:131071];
  initial for (i = 0; i < 131072; i = i + 1) bsram[i] = 8'h00;
  reg [7:0] bsram_q_r;
  always @(posedge clk) begin
    if (bw_busy > 0) bw_busy <= bw_busy - 1;
    if (!BSRAM_CE_N && !BSRAM_WE_N) begin
      bw_writes <= bw_writes + 1;
      // +bwnodrop applies the latency but never loses a request, so a run can
      // separate "slow memory" from "the toggle pair swallowed the access".
      // The two are conflated under plain +bwlat and the distinction decides
      // the fix: slow memory is answered by waiting longer, a swallowed
      // request is answered by not issuing it until the previous one is acked.
      if (bw_busy > 0 && !bwnodrop) begin
        bw_dropped <= bw_dropped + 1;      // the toggle pair collapsed
      end else begin
        bw_busy <= bwlat;
        bsram[BSRAM_ADDR] <= BSRAM_D;
      end
    end
    // +bwreadnow removes the write-busy gate on reads, so a read always gets
    // the array's current contents regardless of an outstanding write.  This is
    // a modelling experiment, not a claim about the hardware: it separates "the
    // memory is slow" from "reads starve behind a continuous write stream".
    // Under the gated model bw_busy is re-armed by every write, so with the GSU
    // writing its plot buffer every few cycles bw_busy never reaches zero and
    // no read ever sees fresh data, however long the core waits.
    if (bwlat == 0 || bwreadnow) bsram_q_r <= bsram[BSRAM_ADDR];
    else if (bw_busy == 0) bsram_q_r <= bsram[BSRAM_ADDR];
  end
  assign BSRAM_Q = bsram_q_r;

  // Instrument validation for the cache-fill probe.
  //
  // The probe's own four bytes cannot be checked against themselves: a sampler
  // that reads the wrong edge still produces four plausible bytes.  The GSU
  // exports its fill strobe, so at each one this prints three independent views
  // -- the address the GSU walked to, the byte the model drives onto the bus,
  // and the byte the ROM array holds at that address -- alongside the sampler's
  // own capture.  The ROM array is the ground truth; the other two say where a
  // disagreement comes from when there is one.
  integer cf_dbg_n = 0;
  always @(posedge clk) begin
    if (rst_n && GSU_CACHE_EN && cf_dbg_n < 10) begin
      $display("  [cffill] ROM_ADDR=%h rom[]=%h ROM_Q=%h | sampler addr=%h b=%h %h %h %h",
               ROM_ADDR, rom[ROM_ADDR[19:0]], ROM_Q,
               GSU_CF_ADDR, GSU_CF_B0, GSU_CF_B1, GSU_CF_B2, GSU_CF_B3);
      cf_dbg_n <= cf_dbg_n + 1;
    end
  end

  // ------------------------------------------------------------- the machine
  // Parameter override rather than a CHIP_GSU define: snestang_top is the module
  // that maps the define to this parameter, and this bench instantiates main
  // directly so that the GSU's internals are reachable.
  main #(.USE_DLH(1'b1), .USE_DSPn(1'b1), .USE_GSU(1'b1)) dut (
    .MCLK(clk), .RESET_N(rst_n), .ENABLE(enable),
    .SYSCLKF_CE(SYSCLKF_CE), .SYSCLKR_CE(SYSCLKR_CE), .REFRESH(REFRESH),
    .ROM_TYPE(ROM_TYPE), .ROM_MASK(ROM_MASK), .RAM_MASK(RAM_MASK),
    .ROM_ADDR(ROM_ADDR), .ROM_D(ROM_D), .ROM_Q(ROM_Q),
    .ROM_CE_N(ROM_CE_N), .ROM_OE_N(ROM_OE_N), .ROM_WE_N(ROM_WE_N), .ROM_WORD(ROM_WORD),
    .BSRAM_ADDR(BSRAM_ADDR), .BSRAM_D(BSRAM_D), .BSRAM_Q(BSRAM_Q),
    .BSRAM_CE_N(BSRAM_CE_N), .BSRAM_OE_N(BSRAM_OE_N), .BSRAM_WE_N(BSRAM_WE_N),
    .BSRAM_RD_N(BSRAM_RD_N),
    .WRAM_ADDR(WRAM_ADDR), .WRAM_D(WRAM_D), .WRAM_Q(WRAM_Q),
    .WRAM_CE_N(WRAM_CE_N), .WRAM_OE_N(WRAM_OE_N), .WRAM_WE_N(WRAM_WE_N),
    .WRAM_RD_N(WRAM_RD_N),
    .VRAM1_ADDR(VRAM1_ADDR), .VRAM1_DI(VRAM1_DI), .VRAM1_DO(VRAM1_DO),
    .VRAM1_WE_N(VRAM1_WE_N),
    .VRAM2_ADDR(VRAM2_ADDR), .VRAM2_DI(VRAM2_DI), .VRAM2_DO(VRAM2_DO),
    .VRAM2_WE_N(VRAM2_WE_N), .VRAM_OE_N(VRAM_OE_N),
    .ARAM_ADDR(ARAM_ADDR), .ARAM_D(ARAM_D), .ARAM_Q(ARAM_Q),
    .ARAM_CE_N(ARAM_CE_N), .ARAM_OE_N(ARAM_OE_N), .ARAM_WE_N(ARAM_WE_N),
    .BLEND(1'b0), .PAL(1'b0), .DIS_SHORTLINE(1'b0),
    .HIGH_RES(HIGH_RES), .FIELD(FIELD), .INTERLACE(INTERLACE),
    .DOTCLK(DOTCLK), .RGB_OUT(RGB_OUT),
    .HBLANKn(HBLANKn), .VBLANKn(VBLANKn), .X_OUT(X_OUT), .Y_OUT(Y_OUT),
    .JOY1_DI(2'b11), .JOY2_DI(2'b11), .JOY_STRB(JOY_STRB),
    .JOY1_CLK(JOY1_CLK), .JOY2_CLK(JOY2_CLK),
    .JOY1_P6(), .JOY2_P6(), .JOY2_P6_in(), .DOT_CLK_CE(DOT_CLK_CE), .EXT_RTC(),
    .AUDIO_L(AUDIO_L), .AUDIO_R(AUDIO_R), .AUDIO_READY(AUDIO_READY), .AUDIO_EN(1'b1),
    .SPC_MODE(), .IO_ADDR(), .IO_DAT(), .IO_WR(),
    .DBG_SEL(DBG_SEL), .DBG_REG(DBG_REG), .DBG_REG_WR(DBG_REG_WR),
    .DBG_DAT_IN(DBG_DAT_IN), .DBG_DAT_OUT(DBG_DAT_OUT), .DBG_BREAK(DBG_BREAK),
    .GSU_DBG_GO_CNT(GSU_GO_CNT), .GSU_DBG_FLAG_GO(GSU_FLAG_GO),
    .GSU_DBG_CACHE_ANY(GSU_CACHE_ANY), .GSU_DBG_EN(GSU_EN),
    .GSU_DBG_ROMST(GSU_ROMST), .GSU_DBG_IN_CACHE(GSU_IN_CACHE),
    .GSU_DBG_ROM_CACHE_WAIT(GSU_ROM_CACHE_WAIT),
    .GSU_DBG_ROM_LOAD_WAIT(GSU_ROM_LOAD_WAIT),
    .GSU_DBG_CACHE_FILL_SEEN(GSU_CACHE_FILL_SEEN),
    .GSU_DBG_CACHE_MMIO_SEEN(GSU_CACHE_MMIO_SEEN),
    .GSU_DBG_ROMST_SEEN(GSU_ROMST_SEEN),
    .GSU_DBG_SFR(GSU_SFR), .GSU_DBG_STATE_SEEN(GSU_STATE_SEEN),
    .GSU_DBG_FLAG_GO_INT(GSU_FLAG_GO_INT),
    .GSU_DBG_FLAG_R_INT(GSU_FLAG_R_INT),
    .GSU_DBG_STOP_SEEN(GSU_STOP_SEEN),
    .GSU_DBG_CF_ADDR(GSU_CF_ADDR),
    .GSU_DBG_CF_B0(GSU_CF_B0), .GSU_DBG_CF_B1(GSU_CF_B1),
    .GSU_DBG_CF_B2(GSU_CF_B2), .GSU_DBG_CF_B3(GSU_CF_B3),
    .GSU_DBG_FIRST_OP(GSU_FIRST_OP),
    .GSU_DBG_CACHE_EN(GSU_CACHE_EN),
    .GSU_DBG_FETCH_OP_SEEN(GSU_FETCH_OP_SEEN),
    .GSU_DBG_PC(), .GSU_DBG_RL(), .GSU_DBG_OP(), .GSU_DBG_MM(),
    .GSU_DBG_ROM_CYCLES(4'd0)
  );

  // ------------------------------------------------------------- reporting
  // The CPU is read through the debug port the core already carries (EXT-004):
  // DBG_SEL[0] selects the 65816 and DBG_DAT_OUT is combinational in DBG_REG.
  // The read is sequenced on the clock and latched, because an earlier version
  // of this bench put #1 delays inside an always @(*) and reported a program
  // counter that was pure tearing -- the same class of instrument error that
  // cost the hardware cycles.
  reg [1:0] dsel = 2'd0;
  reg [7:0] pc_lo, pc_hi, pbr_l, p_l, sp_lo;
  reg [7:0] pc_lo_s, pc_hi_s, pbr_s;
  reg       pc_stable = 1'b0;

  always @(*) begin
    DBG_SEL = 8'h01;
    DBG_REG_WR = 1'b0;
    DBG_DAT_IN = 8'h00;
    case (dsel)
      2'd0: DBG_REG = 8'h06;   // PC low
      2'd1: DBG_REG = 8'h07;   // PC high
      2'd2: DBG_REG = 8'h0D;   // PBR
      default: DBG_REG = 8'h08; // P
    endcase
  end

  assign o_dotclk  = DOTCLK;
  assign o_hblankn = HBLANKn;
  assign o_vblankn = VBLANKn;
  assign o_x       = X_OUT;
  assign o_y       = Y_OUT;
  assign o_rgb     = RGB_OUT;
  assign o_pbr        = pbr_s;
  assign o_pc_hi      = pc_hi_s;
  assign o_pc_lo      = pc_lo_s;
  assign o_go_cnt     = GSU_GO_CNT;
  assign o_sfr        = GSU_SFR;
  assign o_state_seen = GSU_STATE_SEEN;
  assign o_stop_seen  = GSU_STOP_SEEN;

  integer fd = 0;
  integer cyc = 0;
  integer next_report = 0;
  integer rom_reads = 0;
  integer vram_writes = 0;
  reg [23:0] last_pc = 24'hFFFFFF;
  reg [15:0] last_state_seen = 16'd0;
  reg [15:0] last_go_cnt = 16'd0;
  // A tiny histogram of distinct (PBR:PC) values, so a loop is visible without
  // a trace file: the first 32 distinct addresses the CPU is seen at.
  reg [23:0] seen_pc [0:31];
  integer    seen_n = 0;
  integer    j;
  reg        is_new;

  initial begin
    for (j = 0; j < 32; j = j + 1) seen_pc[j] = 24'hFFFFFF;
    if (trace_path != 0) fd = $fopen(trace_path, "w");
    if (fd != 0)
      $fdisplay(fd, "# cyc  pbr:pc  go_cnt sfr state_seen romst");
  end

  always @(posedge clk) begin
    cyc <= cyc + 1;
    dsel <= dsel + 2'd1;

    case (dsel)
      2'd0: pc_lo   <= DBG_DAT_OUT;
      2'd1: pc_hi   <= DBG_DAT_OUT;
      2'd2: pbr_l   <= DBG_DAT_OUT;
      default: p_l  <= DBG_DAT_OUT;
    endcase

    // Every fourth clock the pair (pc_hi,pc_lo,pbr) was sampled in the same
    // order, so treat that as one reading.
    if (dsel == 2'd3) begin
      pc_lo_s <= pc_lo; pc_hi_s <= pc_hi; pbr_s <= pbr_l;
    end

    // PPU programming is the proxy for "the game reached display init".  A
    // machine stuck in the sound upload writes no VRAM at all.
    if (!VRAM1_WE_N || !VRAM2_WE_N) vram_writes <= vram_writes + 1;

    if (cyc == 10)  rst_n  <= 1'b1;
    if (cyc == 100) enable <= 1'b1;
    // The header has been parsed by now; this is when rom_type becomes $70 and
    // the GSU takes the cartridge port, as smc_parser does on the board.
    if (cyc == 2000) begin
      $display("  [bench] rom_type -> %h (romtype plusarg %0d)", romtype_val[7:0], romtype_val);
      ROM_TYPE <= romtype_val[7:0];
    end

    // Record the first distinct code addresses, so a stuck loop names itself.
    if (dsel == 2'd0 && seen_n < 32) begin
      is_new = 1'b1;
      for (j = 0; j < 32; j = j + 1)
        if (seen_pc[j] == {pbr_s, pc_hi_s, pc_lo_s}) is_new = 1'b0;
      if (is_new) begin
        seen_pc[seen_n] <= {pbr_s, pc_hi_s, pc_lo_s};
        seen_n <= seen_n + 1;
      end
    end

    // Bring the bus out for the first few reports: a bench that reports a dead
    // CPU needs to say WHICH signal is dead, or the next hour is guesswork.
    if (cyc == 2_000_000 || cyc == 2_000_100 || cyc == 2_000_200) begin
      $display("  [bus] ROMSEL_N=%b RAMSEL_N=%b ROM_CE_N=%b ROM_ADDR=%h ROM_Q=%h DLH_CE=%b MAPACT=%b",
               dut.ROMSEL_N, dut.RAMSEL_N, ROM_CE_N, ROM_ADDR, ROM_Q,
               dut.DLH_ROM_CE_N, dut.MAP_ACTIVE);
      $display("        CA=%h CPURD_N=%b DI=%h DO=%h P=%h",
               dut.CA, dut.CPURD_N, dut.DI, dut.DO, p_l);
    end

    if (cyc >= next_report) begin
      next_report <= cyc + 2000000;
      $display("[%0d] cpu=%h:%h%h p=%h rom=%0d vram_wr=%0d | gsu go=%0d sfr=%h stseen=%h",
               cyc, pbr_s, pc_hi_s, pc_lo_s, p_l, rom_reads, vram_writes,
               GSU_GO_CNT, GSU_SFR, GSU_STATE_SEEN);
    end

    if (fd != 0 && dsel == 2'd0 &&
        (GSU_STATE_SEEN != last_state_seen || GSU_GO_CNT != last_go_cnt)) begin
      $fdisplay(fd, "%0d %h:%h%h %0d %h %h %0d",
                 cyc, pbr_s, pc_hi_s, pc_lo_s, GSU_GO_CNT, GSU_SFR,
                 GSU_STATE_SEEN, GSU_ROMST);
      last_state_seen <= GSU_STATE_SEEN;
      last_go_cnt <= GSU_GO_CNT;
    end

    // One shot.  $finish is a request the harness may ignore, and when this
    // harness ignored it this block reprinted its whole report on every clock:
    // six lines per clock for as long as the process lived.  The report is now
    // latched off after the first print, so a harness that never stops still
    // cannot produce more than one report.
    if (cyc >= cycles_max && !reported) begin
      reported <= 1'b1;
      $display("");
      $display("=== after %0d mclk ===", cyc);
      $display("  cpu  pbr:pc  %h:%h%h   p=%h   cartridge reads %0d   VRAM writes %0d",
               pbr_s, pc_hi_s, pc_lo_s, p_l, rom_reads, vram_writes);
      $display("  first distinct code addresses seen:");
      for (j = 0; j < 32; j = j + 1)
        if (seen_pc[j] != 24'hFFFFFF) $display("    %h:%h", seen_pc[j][23:16], seen_pc[j][15:0]);
      $display("  GSU go_cnt %0d  flag_go %b/%b  flag_r %b  stop_seen %b",
               GSU_GO_CNT, GSU_FLAG_GO, GSU_FLAG_GO_INT, GSU_FLAG_R_INT, GSU_STOP_SEEN);
      $display("  GSU SFR %h  state_seen %b  romst_seen %b",
               GSU_SFR, GSU_STATE_SEEN, GSU_ROMST_SEEN);
      $display("  GSU cache fill_seen %b  mmio_seen %b  in_cache %b",
               GSU_CACHE_FILL_SEEN, GSU_CACHE_MMIO_SEEN, GSU_IN_CACHE);
      $display("  GSU first cache fill at %h: %h %h %h %h   first_op %h (boundary seen %b)",
               GSU_CF_ADDR, GSU_CF_B0, GSU_CF_B1, GSU_CF_B2, GSU_CF_B3,
               GSU_FIRST_OP, GSU_FETCH_OP_SEEN);
      $display("  BSRAM writes %0d, dropped %0d (bwlat=%0d)", bw_writes, bw_dropped, bwlat);
      $display("  ROM requests %0d, lost to toggle collapse %0d (rtog=%0d)", rtog_seen, rtog_lost, rtog);
      $display("  frame: %0d pixels captured (full frame = 57344)", fb_captured);
      if (frame_path != 0) write_ppm(frame_path);
      if (fd != 0) $fclose(fd);
      $finish;
    end
  end


  // ------------------------------------------------------- internal screenshot
  // The pixel the PPU is producing, captured at the point snes2hdmi would write
  // it to its line buffer: a rising DOTCLK with both blanking outputs inactive.
  // Writing it as a PPM is the simulation equivalent of looking at the board's
  // HDMI, except that nothing between here and the file can lie.
  //
  // RGB_OUT is 15-bit BGR555; it is expanded to 8 bits per channel by shifting
  // left three and replicating the top bits, which is what the HDMI path does.
  reg [14:0] fb [0:255*224];
  reg        fb_dotclk_r = 1'b0;
  wire       fb_dot_edge = DOTCLK & ~fb_dotclk_r;
  integer    fb_captured = 0;

  always @(posedge clk) begin
    fb_dotclk_r <= DOTCLK;
    // X_OUT is {OUT_X, DOT_CLK}, so the column is X_OUT[8:1], not X_OUT.
    if (fb_dot_edge && HBLANKn && VBLANKn && X_OUT[8:1] < 8'd255 && Y_OUT < 9'd224) begin
      fb[{Y_OUT[7:0], X_OUT[8:1]}] <= RGB_OUT;
      fb_captured <= fb_captured + 1;
    end
  end

  task write_ppm(input [1023:0] path);
    integer x, y, fd2;
    reg [7:0] r, g, b;
    reg [14:0] px;
    begin
      fd2 = $fopen(path, "wb");
      if (fd2 == 0) begin
        $display("could not open %0s for writing", path);
      end else begin
        $fwrite(fd2, "P6\n256 224\n255\n");
        for (y = 0; y < 224; y = y + 1) begin
          for (x = 0; x < 256; x = x + 1) begin
            px = fb[{y[7:0], x[7:0]}];
            // BGR555: snes2hdmi orders its 24-bit pixel red-low, blue-high.
            r = {px[4:0], px[4:2]};
            g = {px[9:5], px[9:7]};
            b = {px[14:10], px[14:12]};
            $fwrite(fd2, "%c%c%c", r, g, b);
          end
        end
        $fclose(fd2);
        $display("wrote %0s", path);
      end
    end
  endtask

endmodule
