`timescale 1ns/1ps
// SPDX-License-Identifier: MIT
//
// Full-core bench for TinySNES.
//
// Every instrument this project built before this bench measured the machine
// from outside: a probe latched into a stripe display, read back through a
// capture card, one boot at a time.  That method cannot debug a machine that
// does not boot the same way twice, and thirty-six cycles of it produced
// readings that contradicted each other -- a program counter below the
// cartridge, a long return with no long call behind it, and repeatedly no two
// boots alike.  This bench instantiates the real `SNES.v` with behavioural
// memories so the same machine can be run as many times as needed with every
// internal signal visible and no capture card in the way.
//
// What is real here: `SNES.v` and everything under it -- the 65816, the SPC700,
// the PPU, the DSP, `cpu.v`, the whole CPU bus.  What is modelled: the
// cartridge, WRAM, VRAM, ARAM and battery SRAM, which on the board live in
// SDRAM behind a hand-tuned PHY (`sdram_cl2_2ch.v`).  Modelling them is the
// point, not a shortcut: it removes the SDRAM capture from the experiment, so a
// pass here says the core and its bus are sound and a failure says they are not.
//
// Clocks.  `MCLK` is the 21.477 MHz master clock and everything the core does is
// derived from it by clock enables, so the PLLs and the whole HDMI stack are
// absent and not needed.  `ENABLE` is held low until the cartridge has "loaded",
// then raised, matching the `loaded` gate in `snestang_top.v`.
//
// The cartridge is LoROM, which is what the test image uses: header map byte
// `$7FD5` reads `$30`, and CPU `$8000-$FFFF` in banks `$00-$7D` and `$80-$FF`
// maps to image offset `(bank & $7F) * $8000 + (addr & $7FFF)` (record EXT-009).
// The reset vector at image offset `$7FFC` is `$8000`, so a working core fetches
// its first opcode from `$00:8000`.
//
// Options, all via plusarg so one binary serves every experiment:
//   +rom=path       image to load, default /tmp/zelda.smc
//   +hex=path       pre-converted hex of that image (see run_sim.sh)
//   +cycles=N       master clocks to run, default 400000
//   +lat=N          cartridge read latency in mclk, default 0
//   +trace=path     write a PC trace to this file
//   +vcd=path       dump waves to this file
//   +stoplow=N      stop once the PC is below $8000 for N clocks, default 0 = never
//
module snes_tb;

  // ---------------------------------------------------------------- clocks
  localparam real MCLK_HZ = 21477272.0;
  localparam real MCLK_NS = 1.0e9 / MCLK_HZ;      // 46.56 ns

  reg clk = 1'b0;
  always #(MCLK_NS / 2.0) clk = ~clk;

  reg rst_n  = 1'b0;
  reg enable = 1'b0;

  // ---------------------------------------------------------------- options
  integer cycles_max = 400000;
  integer rom_lat    = 0;
  integer stoplow    = 0;
  reg [1023:0] rom_path, hex_path, trace_path, vcd_path;

  // ---------------------------------------------------------------- memories
  // 128 KiB WRAM, 64 KiB VRAM, 64 KiB ARAM, 32 KiB battery SRAM, 4 MiB ROM.
  reg [7:0]  wram [0:17'h1FFFF];
  reg [7:0]  vram [0:16'hFFFF];
  reg [7:0]  aram [0:16'hFFFF];
  reg [7:0]  bsram[0:16'h7FFF];
  reg [7:0]  rom  [0:21'h3FFFFF];

  // ---------------------------------------------------------------- DUT
  wire [23:0] CA;
  wire        CPURD_N, CPUWR_N, CPURD_CYC_N, DOT_CLK_CE;
  wire [7:0]  PA;
  wire        PARD_N, PAWR_N;
  reg  [7:0]  DI;
  wire [7:0]  DO;
  wire        RAMSEL_N, ROMSEL_N;
  wire        SYSCLKF_CE, SYSCLKR_CE, SNES_REFRESH;

  wire [16:0] WRAM_ADDR;
  wire [7:0]  WRAM_D;
  reg  [7:0]  WRAM_Q;
  wire        WRAM_CE_N, WRAM_OE_N, WRAM_WE_N, WRAM_RD_N;

  wire [15:0] VRAM_ADDRA, VRAM_ADDRB;
  reg  [7:0]  VRAM_DAI, VRAM_DBI;
  wire [7:0]  VRAM_DAO, VRAM_DBO;
  wire        VRAM_WRA_N, VRAM_WRB_N, VRAM_RD_N;

  wire [15:0] ARAM_ADDR;
  wire [7:0]  ARAM_D;
  reg  [7:0]  ARAM_Q;
  wire        ARAM_CE_N, ARAM_OE_N, ARAM_WE_N;

  wire        HIGH_RES, FIELD_OUT, INTERLACE, V224_MODE, DOTCLK;
  wire [14:0] RGB_OUT;
  wire        HDE, VDE, HSYNC, VSYNC;
  wire [8:0]  X_OUT, Y_OUT;

  wire        JOY_STRB, JOY1_CLK, JOY2_CLK;
  wire [15:0] AUDIO_L, AUDIO_R;
  wire        AUDIO_READY;

  reg  [7:0]  DBG_SEL  = 8'h00;
  reg  [7:0]  DBG_REG  = 8'h00;
  reg         DBG_REG_WR = 1'b0;
  reg  [7:0]  DBG_DAT_IN = 8'h00;
  wire [7:0]  DBG_DAT_OUT;
  wire        DBG_BREAK;

  SNES dut (
    .MCLK(clk), .RST_N(rst_n), .ENABLE(enable),
    .PAL(1'b0), .BLEND(1'b0), .DIS_SHORTLINE(1'b0),
    .CA(CA), .CPURD_N(CPURD_N), .CPUWR_N(CPUWR_N),
    .CPURD_CYC_N(CPURD_CYC_N), .DOT_CLK_CE(DOT_CLK_CE),
    .PA(PA), .PARD_N(PARD_N), .PAWR_N(PAWR_N), .DI(DI), .DO(DO),
    .RAMSEL_N(RAMSEL_N), .ROMSEL_N(ROMSEL_N),
    .SYSCLKF_CE(SYSCLKF_CE), .SYSCLKR_CE(SYSCLKR_CE), .SNES_REFRESH(SNES_REFRESH),
    .IRQ_N(1'b1),
    .WRAM_ADDR(WRAM_ADDR), .WRAM_D(WRAM_D), .WRAM_Q(WRAM_Q),
    .WRAM_CE_N(WRAM_CE_N), .WRAM_OE_N(WRAM_OE_N),
    .WRAM_WE_N(WRAM_WE_N), .WRAM_RD_N(WRAM_RD_N),
    .VRAM_ADDRA(VRAM_ADDRA), .VRAM_ADDRB(VRAM_ADDRB),
    .VRAM_DAI(VRAM_DAI), .VRAM_DBI(VRAM_DBI),
    .VRAM_DAO(VRAM_DAO), .VRAM_DBO(VRAM_DBO),
    .VRAM_WRA_N(VRAM_WRA_N), .VRAM_WRB_N(VRAM_WRB_N), .VRAM_RD_N(VRAM_RD_N),
    .ARAM_ADDR(ARAM_ADDR), .ARAM_D(ARAM_D), .ARAM_Q(ARAM_Q),
    .ARAM_CE_N(ARAM_CE_N), .ARAM_OE_N(ARAM_OE_N), .ARAM_WE_N(ARAM_WE_N),
    .HIGH_RES(HIGH_RES), .FIELD_OUT(FIELD_OUT), .INTERLACE(INTERLACE),
    .V224_MODE(V224_MODE), .DOTCLK(DOTCLK), .RGB_OUT(RGB_OUT),
    .HDE(HDE), .VDE(VDE), .HSYNC(HSYNC), .VSYNC(VSYNC),
    .X_OUT(X_OUT), .Y_OUT(Y_OUT),
    .JOY1_DI(2'b11), .JOY2_DI(2'b11),
    .JOY_STRB(JOY_STRB), .JOY1_CLK(JOY1_CLK), .JOY2_CLK(JOY2_CLK),
    .AUDIO_L(AUDIO_L), .AUDIO_R(AUDIO_R),
    .AUDIO_READY(AUDIO_READY), .AUDIO_EN(1'b1),
    .DBG_SEL(DBG_SEL), .DBG_REG(DBG_REG), .DBG_REG_WR(DBG_REG_WR),
    .DBG_DAT_IN(DBG_DAT_IN), .DBG_DAT_OUT(DBG_DAT_OUT), .DBG_BREAK(DBG_BREAK)
  );

  // ------------------------------------------------------------ cart timing
  // A real cartridge answers through SDRAM several master clocks later; +lat
  // models that so the same bench can separate a logic fault from a read that
  // returns too late.  lat=0 is a perfect cartridge.
  integer   i;

  // LoROM: image offset = (bank & $7F) * $8000 + (addr & $7FFF).
  wire [31:0] loff = (({24'd0, CA[23:16]} & 32'h7F) << 15)
                   |  {16'd0, CA[15:0] & 16'h7FFF};
  wire [7:0]  rom_q_next = rom[loff[21:0]];

  // ------------------------------------------------------------ ROM model
  // Read combinationally when ROMSEL is asserted, delayed by rom_lat clocks.
  reg [7:0] rom_pipe [0:8];
  integer k;
  always @(posedge clk) begin
    for (k = 8; k > 0; k = k - 1)
      rom_pipe[k] <= rom_pipe[k-1];
    rom_pipe[0] <= (ROMSEL_N === 1'b0) ? rom_q_next : 8'hFF;
  end

  // ------------------------------------------------------------ WRAM model
  always @(posedge clk) begin
    if (!WRAM_CE_N && !WRAM_WE_N)
      wram[WRAM_ADDR] <= WRAM_D;
    WRAM_Q <= wram[WRAM_ADDR];
  end

  // ------------------------------------------------------------ VRAM model
  // Dual port byte-addressable; the PPU drives both ports.
  always @(posedge clk) begin
    if (!VRAM_WRA_N) vram[VRAM_ADDRA] <= VRAM_DAO;
    if (!VRAM_WRB_N) vram[VRAM_ADDRB] <= VRAM_DBO;
    VRAM_DAI <= vram[VRAM_ADDRA];
    VRAM_DBI <= vram[VRAM_ADDRB];
  end

  // ------------------------------------------------------------ ARAM model
  always @(posedge clk) begin
    if (!ARAM_CE_N && !ARAM_WE_N)
      aram[ARAM_ADDR] <= ARAM_D;
    ARAM_Q <= aram[ARAM_ADDR];
  end

  // ------------------------------------------------------------ cart DI mux
  // The core selects the cartridge only when ROMSEL is low and RAMSEL is high;
  // anywhere else it takes WRAM, the PPU, the APU or open bus.  Driving DI with
  // the cartridge data whenever ROMSEL is low is what the board does.
  always @* begin
    if (ROMSEL_N === 1'b0)
      DI = rom_lat == 0 ? rom_q_next : rom_pipe[rom_lat];
    else
      DI = 8'hFF;
  end

  // ---------------------------------------------------------------- tracing
  integer tf;
  integer cyc = 0;
  integer low_run = 0;
  reg     stopped = 1'b0;

  // The 65816's committed state, reached through the hierarchy rather than
  // through the debug port: the port is one byte wide and muxed, and a trace
  // that has to round-robin registers cannot show an instruction.
  wire [15:0] pc   = dut.CPU.P65C816.PC;
  wire [7:0]  pbr  = dut.CPU.P65C816.PBR;
  wire [15:0] sp   = dut.CPU.P65C816.SP;
  wire [7:0]  p    = dut.CPU.P65C816.P;
  wire [15:0] a    = dut.CPU.P65C816.A;
  wire [15:0] x    = dut.CPU.P65C816.X;
  wire [15:0] y    = dut.CPU.P65C816.Y;
  wire [7:0]  ir   = dut.CPU.P65C816.IR;
  wire [3:0]  state= dut.CPU.P65C816.STATE;

  reg [15:0] last_pc = 16'hFFFF;

  // The SPC700 side of the link.  The 65816's upload waits for the SPC to echo
  // each byte, so when the upload stalls the question is what the SPC is doing
  // and what the two port banks hold -- the same question entries 8 to 12 asked
  // with a probe, here answered from inside the machine.
  wire [15:0] spc_pc  = dut.smp.SPC700.PC;
  wire [15:0] cpui    = {dut.smp.CPUI[1], dut.smp.CPUI[0]};
  wire [15:0] cpuo    = {dut.smp.CPUO[1], dut.smp.CPUO[0]};
  integer sf;
  initial sf = 0;
  reg [15:0] last_spc = 16'hFFFF;
  always @(posedge clk)
    if (sf != 0 && enable && spc_pc !== last_spc) begin
      last_spc <= spc_pc;
      $fdisplay(sf, "%0d spc_pc=%04X cpui=%04X cpuo=%04X pc65816=%04X",
                cyc, spc_pc, cpui, cpuo, pc);
    end

  // Opcode log: every byte the 65816 commits to as an instruction, with the
  // address it came from.  The PC trace shows where the CPU went; this shows
  // what it read to get there, which is what separates a control-flow fault
  // from a fetch that returned the wrong byte.
  integer of;
  wire    insn_now = dut.CPU.P65C816.EN & ~dut.CPU.P65C816.GotInterrupt & (state == 4'd0);

  // PPU programming: does the machine ever get as far as telling the PPU how to
  // draw?  A CPU that boots but never writes $2100 leaves the PPU in its reset
  // state, which is the fixed grid this project has been seeing.
  integer pp;
  reg [7:0] ppu_wr_count = 8'd0;
  // Banks $00-$3F and $80-$BF both reach the PPU registers at $2100-$21FF, and
  // the game runs in bank $80, so masking the top two bits is the test that
  // catches it.  The first version of this filter compared the whole high byte
  // to $00 and silently missed every write the game made.
  wire ppu_sel = dut.CPU.P65C816.EN & ~dut.CPU.P65C816.WE_N
                 & (dut.CPU.P65C816.A_OUT[23:22] == 2'b00)
                 & (dut.CPU.P65C816.A_OUT[15:8] == 8'h21);
  initial pp = 0;
  always @(posedge clk)
    if (pp != 0 && ppu_sel) begin
      if (ppu_wr_count != 8'hFF) ppu_wr_count <= ppu_wr_count + 8'd1;
      $fdisplay(pp, "%0d pc=%04X addr=%02X data=%02X",
                cyc, pc, dut.CPU.P65C816.A_OUT[7:0], dut.CPU.P65C816.D_OUT);
    end
  initial of = 0;
  always @(posedge clk)
    if (of != 0 && insn_now)
      $fdisplay(of, "%0d pbr=%02X pc=%04X din=%02X ca=%06X romsel=%b",
                cyc, pbr, pc, dut.CPU.P65C816.D_IN, CA, ROMSEL_N);

  always @(posedge clk) begin
    cyc <= cyc + 1;
    if (enable && rst_n) begin
      // Log a line whenever the program counter changes, which is once per
      // instruction at this core's rate.
      if (pc !== last_pc) begin
        last_pc <= pc;
        if (tf != 0)
          $fdisplay(tf, "%0d pbr=%02X pc=%04X sp=%04X p=%02X a=%04X x=%04X y=%04X ir=%02X",
                    cyc, pbr, pc, sp, p, a, x, y, ir);
      end
      // A CPU below $8000 is outside the cart in a LoROM (EXT-009).
      if (pc < 16'h8000) begin
        low_run <= low_run + 1;
        if (stoplow != 0 && low_run >= stoplow) stopped <= 1'b1;
      end else
        low_run <= 0;
    end
    if (cyc >= cycles_max) stopped <= 1'b1;
  end

  // ---------------------------------------------------------------- stimulus
  initial begin
    if (!$value$plusargs("rom=%s", rom_path)) rom_path = "/tmp/zelda.smc";
    if (!$value$plusargs("hex=%s", hex_path)) hex_path = "rom.hex";
    if (!$value$plusargs("cycles=%d", cycles_max)) cycles_max = 400000;
    if (!$value$plusargs("lat=%d", rom_lat)) rom_lat = 0;
    if (!$value$plusargs("stoplow=%d", stoplow)) stoplow = 0;
    if (!$value$plusargs("trace=%s", trace_path)) trace_path = "pc.trace";
    if ($value$plusargs("vcd=%s", vcd_path)) begin
      $dumpfile(vcd_path);
      $dumpvars(0, snes_tb);
    end

    for (i = 0; i < 131072; i = i + 1) wram[i]  = 8'h00;
    for (i = 0; i < 65536; i = i + 1) vram[i]  = 8'h00;
    for (i = 0; i < 65536; i = i + 1) aram[i]  = 8'h00;
    for (i = 0; i < 32768; i = i + 1) bsram[i] = 8'h00;
    for (i = 0; i < 1048576; i = i + 1) rom[i]   = 8'hFF;

    $display("loading cartridge from %0s", hex_path);
    $readmemh(hex_path, rom);
    $display("reset vector at $00:FFFC (image $7FFC) = %02X%02X",
             rom[23'h7FFD], rom[23'h7FFC]);

    tf = $fopen(trace_path, "w");
    if (tf == 0) $display("warning: could not open %0s; no trace", trace_path);
    begin
      reg [1023:0] op_path;
      if ($value$plusargs("oplog=%s", op_path)) begin
        of = $fopen(op_path, "w");
        if (of == 0) $display("warning: could not open %0s; no oplog", op_path);
      end
      begin
        reg [1023:0] sp_path;
        if ($value$plusargs("spclog=%s", sp_path)) begin
          sf = $fopen(sp_path, "w");
          if (sf == 0) $display("warning: could not open %0s; no spclog", sp_path);
        end
      end
      begin
        reg [1023:0] pp_path;
        if ($value$plusargs("pplog=%s", pp_path)) begin
          pp = $fopen(pp_path, "w");
          if (pp == 0) $display("warning: could not open %0s; no pplog", pp_path);
        end
      end
    end

    repeat (16) @(posedge clk);
    rst_n = 1'b1;
    repeat (8) @(posedge clk);
    enable = 1'b1;
    $display("enable raised at cycle %0d, running to %0d", cyc, cycles_max);

    wait (stopped === 1'b1);
    $display("stopped at cycle %0d: last pc=%04X pbr=%02X sp=%04X p=%02X ir=%02X",
             cyc, pc, pbr, sp, p, ir);
    if (tf != 0) $fclose(tf);
    $finish;
  end

endmodule
