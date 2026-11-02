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
  // Two 32 KiB planes, not one 64 KiB array.  SNES VRAM is two 8-bit memories:
  // port A holds the low byte of every word and port B the high byte, and both
  // are addressed with the same 15-bit word address.  Modelling it as one array
  // makes the two ports overwrite each other, so a word written as $11 then $22
  // reads back as $22 in both halves -- which is not what the hardware does and
  // hid the difference between a correct upload and a scattered one.
  reg [7:0]  vram_lo [0:15'h7FFF];
  reg [7:0]  vram_hi [0:15'h7FFF];
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

  // Driven by the wait-state model below, which is this bench's stand-in for the
  // SDRAM controller's "no data yet" level.
  wire mem_wait;

  SNES dut (
    .MCLK(clk), .RST_N(rst_n), .ENABLE(enable), .MEM_WAIT(mem_wait),
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
  //
  // With +wlat=N a WRAM read is answered N clocks late, the same way +lat delays
  // the cartridge.  Without this the bench cannot express the thing that matters
  // most about this board: WRAM and the cartridge both live in SDRAM behind one
  // controller, so a DMA whose source is WRAM reads from a memory that answers
  // late while the DMA's write window closes on a fixed schedule.  A bench that
  // answers WRAM instantly cannot fail that way, which is why this bug showed up
  // on hardware and nowhere else.
  //
  // The wait is a registered flag that always expires, and deliberately not a
  // function of the bus strobes.  Testing "is this a read" with WRAM_OE_N or
  // WRAM_WE_N looks natural and deadlocks: those strobes are gated by P65_EN,
  // which is gated by MEM_WAIT, so once the wait is raised the access stops
  // looking like a read and never releases.  That was measured -- the flag version
  // and the strobe version disagree, and only the flag one lets the machine run.
  // Ageing from the address change instead means the wait is cleared by time, so
  // a wrong guess about the direction costs a delayed access rather than a hung
  // machine.
  integer wlat = 0;
  wire dma_active_now = dut.CPU.DMA_RUN | dut.CPU.HDMA_RUN;
  wire wram_access_is_write = dma_active_now ? dut.CPU.DMA_A_WR
                                             : ~dut.CPU.P65_R_WN;
  reg [7:0] wram_pipe [0:8];
  integer wi;
  reg [23:0] wram_addr_q = 24'hFFFFFF;
  integer    wram_age    = 0;
  reg        wram_pending = 1'b0;
  reg [7:0]  wram_q_next;

  always @(posedge clk) begin
    wram_q_next <= wram[WRAM_ADDR];
    wram_pipe[0] <= wram[WRAM_ADDR];
    for (wi = 8; wi > 0; wi = wi - 1)
      wram_pipe[wi] <= wram_pipe[wi-1];

    if (RAMSEL_N !== 1'b0) begin
      wram_addr_q  <= CA;
      wram_age     <= 0;
      wram_pending <= 1'b0;
    end else if (CA !== wram_addr_q) begin
      // A new access has been issued, and only reads are held.
      //
      // The direction has to come from a signal the wait does not itself gate.
      // CPUWR_N will not do: it is driven from P65_EN, which is driven from
      // MEM_WAIT, so holding a write makes the write look like a read and the
      // byte is never stored -- measured, not supposed.  The 65816's own R/W line
      // and the DMA channel's direction are both valid with the address, so the
      // wait depends on them and not on the strobe being modelled.
      wram_addr_q  <= CA;
      wram_age     <= 0;
      wram_pending <= ~wram_access_is_write;
    end else if (wram_pending) begin
      if (wram_age >= wlat) begin
        wram_pending <= 1'b0;
        wram_age     <= 0;
      end else begin
        wram_age <= wram_age + 1;
      end
    end
  end

  always @(posedge clk) begin
    if (!WRAM_CE_N && !WRAM_WE_N) begin
      wram[WRAM_ADDR] <= WRAM_D;
      if (bl != 0) $fdisplay(bl, "%0d WRAM[%05X] <= %02X", cyc, WRAM_ADDR, WRAM_D);
    end
    WRAM_Q <= (wlat == 0) ? wram_q_next : wram_pipe[wlat];
  end

  // ------------------------------------------------------------ VRAM model
  // Dual port byte-addressable; the PPU drives both ports.
  //
  // Writes are counted and optionally logged, because "the picture is wrong" and
  // "nothing ever wrote VRAM" are different faults and only the bus can tell them
  // apart.  A DMA upload and a CPU-poked upload look identical from outside the
  // core; here they leave the same trace or none.
  // What the CPU reads back from VRAM, and what VRAM holds, so "the DMA did not
  // write" and "it wrote and readback is broken" are different lines.
  // The PPU's own output, not the CPU wrapper's MDR: MDR is only reloaded on a
  // particular clock enable and lags the value the CPU actually latches, so
  // logging it reports the previous instruction's byte.
  always @(posedge clk)
    if (bl != 0 && (PA == 8'h39 || PA == 8'h3A) && dut.PPU.PAWR_N && dut.PPU.PARD_N === 1'b0)
      $fdisplay(bl, "%0d rdvram pa=%02X ppu_do=%02X prefetch=%04X vmadd=%04X",
                cyc, PA, dut.PPU.D_OUT, dut.PPU.VRAMDATA_Prefetch, dut.PPU.VMADD);
  always @(posedge clk) begin
    if (bl != 0 && !VRAM_WRA_N)
      $fdisplay(bl, "%0d vramLO[%04X] <= %02X", cyc, VRAM_ADDRA, VRAM_DAO);
    if (bl != 0 && !VRAM_WRB_N)
      $fdisplay(bl, "%0d vramHI[%04X] <= %02X", cyc, VRAM_ADDRB, VRAM_DBO);
  end

  integer vram_wr = 0;
  integer vlog;
  initial vlog = 0;
  always @(posedge clk) begin
    if (!VRAM_WRA_N) begin
      vram_lo[VRAM_ADDRA[14:0]] <= VRAM_DAO;
      vram_wr <= vram_wr + 1;
      if (vlog != 0) $fdisplay(vlog, "%0d vram %04X <- %02X", cyc, VRAM_ADDRA, VRAM_DAO);
    end
    if (!VRAM_WRB_N) vram_hi[VRAM_ADDRB[14:0]] <= VRAM_DBO;
    VRAM_DAI <= vram_lo[VRAM_ADDRA[14:0]];
    VRAM_DBI <= vram_hi[VRAM_ADDRB[14:0]];
  end

  // ------------------------------------------------------------ ARAM model
  always @(posedge clk) begin
    if (!ARAM_CE_N && !ARAM_WE_N)
      aram[ARAM_ADDR] <= ARAM_D;
    ARAM_Q <= aram[ARAM_ADDR];
  end

  // -------------------------------------------------------- wait-state model
  // The board's wait input is a level from the SDRAM controller that says the
  // word the CPU asked for has not arrived yet.  Here the same fact is the
  // pipeline above: rom_pipe is a shift register of exactly rom_lat stages off
  // the clock edge that samples the current address, so an access is stale for
  // rom_lat clocks from the moment the address it asks about appeared.  Ageing
  // the access from that moment makes +lat mean the same thing to the CPU as it
  // means to the memory, instead of leaving the core to guess a phase.
  //
  // `<=` and not `<`: the level stays up through the clock at which the word
  // arrives, so the CPU is released on the edge after the data is stable rather
  // than on the same edge.  That one clock is the whole difference between
  // absorbing a latency and not: with the release on the arrival itself a
  // latency of four still desynchronised the machine, because the CPU was let
  // go on exactly the edge its stale sample would have been taken, while five
  // and six were absorbed.  With the margin, four, five, six and eight are.
  reg [23:0] cart_addr_q = 24'hFFFFFF;
  integer    cart_age    = 0;
  always @(posedge clk) begin
    if (ROMSEL_N !== 1'b0 || CA !== cart_addr_q) begin
      cart_addr_q <= CA;
      cart_age    <= 0;
    end else if (cart_age < 32) begin
      cart_age <= cart_age + 1;
    end
  end

  assign mem_wait = ((ROMSEL_N === 1'b0) && (cart_age <= rom_lat))
                 || ((RAMSEL_N === 1'b0) && wram_pending);

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
  // The APU link, both directions, at the two points where each side acts:
  // the 65816 writing CPUI at $2140-$2143, and the SPC700 touching $00F4-$00F7.
  // These are the two halves entries 8 to 12 could only ever see one of, and the
  // deadlock is whichever of them stops matching.
  wire cpu_wr_apu = dut.CPU.P65C816.EN & ~dut.CPU.P65C816.WE_N
                    & (dut.CPU.P65C816.A_OUT[23:22] == 2'b00)
                    & (dut.CPU.P65C816.A_OUT[15:8] == 8'h21);
  wire spc_ap = dut.smp.SPC700_CE
                & (dut.smp.SPC700_A[15:8] == 8'h00)
                & (dut.smp.SPC700_A[7:0] >= 8'hF4) & (dut.smp.SPC700_A[7:0] <= 8'hF7);
  // Every CPU write, by bank:offset, so the question "does the game touch the
  // PPU" is answered by the bus rather than by a filter that could be wrong --
  // and the first version of the PPU filter was wrong twice.
  // Video evidence from inside the machine: whether the PPU is producing
  // visible pixels and how many colour changes reach the output.  This is the one
  // reading that says a boot reached the picture rather than merely running code,
  // and it needs no capture card.
  // One frame of the picture the PPU produces, written as a PPM so it can be
  // looked at.  Reading a colour-change count says "something moved"; it does not
  // say whether a game drew its title screen or the machine emitted noise, and
  // the difference between those two decides where the next fault is.
  integer fp;
  initial fp = 0;
  reg [14:0] frame_buf [0:255*224];
  integer fx, fy;
  reg frame_done_d = 1'b0;
  always @(posedge clk) begin
    if (fp != 0) begin
      if (HDE) begin
        if (dut.PPU.Y_OUT < 9'd224 && dut.PPU.X_OUT < 9'd256)
          frame_buf[dut.PPU.Y_OUT*256 + dut.PPU.X_OUT] <= RGB_OUT;
      end
    end
  end

  integer vf;
  initial vf = 0;
  integer hde_count = 0;
  integer rgb_changes = 0;
  reg [14:0] rgb_p = 15'h7FFF;
  always @(posedge clk) begin
    if (vf != 0) begin
      if (HDE) hde_count <= hde_count + 1;
      if (HDE && RGB_OUT !== rgb_p) begin
        rgb_p <= RGB_OUT;
        rgb_changes <= rgb_changes + 1;
      end
    end
  end

  // B-bus writes, whoever made them.  The CPU-only filter above cannot see a DMA
  // transfer, because during one the CPU is held off the bus entirely -- which is
  // exactly the case these cartridges exist to test.  This logs the actual write
  // strobe and address instead, so "the DMA wrote nothing" and "the DMA wrote
  // somewhere else" are different lines in a file rather than an argument.
  integer bl;
  initial bl = 0;
  reg pa_wr_p = 1'b1;
  always @(posedge clk) begin
    pa_wr_p <= PAWR_N;
    if (bl != 0)
      $fdisplay(bl, "%0d bbus_wr=%b pa=%02X mdr=%02X cpu_di=%02X wq=%02X waddr=%03X ca=%06X mw=%b ds=%0d",
                cyc, ~PAWR_N, PA, dut.CPU.DO, dut.CPU.DI, WRAM_Q, WRAM_ADDR, CA,
                mem_wait, dut.CPU.DS);
  end

  // Deliberately free of any signal a candidate fix introduces, so the same
  // bench builds against the baseline and against a patched core.  Referencing
  // DMA_SRC_STALL here made the baseline fail to elaborate, which is how a
  // comparison silently becomes one-sided.

  // What the palette actually received.  Reading the bus is not enough: a byte
  // can sit on DI, be written to $2122 and still not become a colour, because
  // CGRAM only latches a word on the second byte.  This logs the latch itself,
  // so "the transfer put the wrong byte on the bus" and "the PPU ignored it" stay
  // apart.
  always @(posedge clk)
    if (bl != 0 && dut.PPU.CGRAM_WE)
      $fdisplay(bl, "%0d CGRAM[%02X] <= %04X", cyc,
                dut.PPU.CGRAM_ADDR, dut.PPU.CGRAM_D);

  // Every CPU write, by bank:offset, so the question "does the game touch the
  // PPU" is answered by the bus rather than by a filter that could be wrong.
  integer wf;
  initial wf = 0;
  wire cpu_wr = dut.CPU.P65C816.EN & ~dut.CPU.P65C816.WE_N;
  reg [23:0] last_wa = 24'hFFFFFF;
  always @(posedge clk)
    if (wf != 0 && cpu_wr && dut.CPU.P65C816.A_OUT !== last_wa) begin
      last_wa <= dut.CPU.P65C816.A_OUT;
      $fdisplay(wf, "%0d wr %06X <- %02X", cyc, dut.CPU.P65C816.A_OUT, dut.CPU.P65C816.D_OUT);
    end

  integer af;
  initial af = 0;
  // Register-change detection rather than bus strobes: a write strobe is a
  // one-mclk pulse inside a condition my sampler can step over, and the first
  // version of this log missed every 65816 write while still showing the port
  // banks change.  Watching the banks themselves cannot miss one.
  reg [15:0] cpui_p = 16'hFFFF, cpuo_p = 16'hFFFF;
  reg [15:0] spc_pc_p = 16'hFFFF;
  always @(posedge clk) begin
    if (af != 0) begin
      if ({dut.smp.CPUI[1], dut.smp.CPUI[0]} !== cpui_p) begin
        cpui_p <= {dut.smp.CPUI[1], dut.smp.CPUI[0]};
        $fdisplay(af, "%0d CPUI %04X -> %04X   [cpuo=%04X spc_pc=%04X cpu_pc=%04X]",
                  cyc, cpui_p, {dut.smp.CPUI[1], dut.smp.CPUI[0]},
                  {dut.smp.CPUO[1], dut.smp.CPUO[0]}, spc_pc, pc);
      end
      if ({dut.smp.CPUO[1], dut.smp.CPUO[0]} !== cpuo_p) begin
        cpuo_p <= {dut.smp.CPUO[1], dut.smp.CPUO[0]};
        $fdisplay(af, "%0d CPUO %04X -> %04X   [cpui=%04X spc_pc=%04X cpu_pc=%04X]",
                  cyc, cpuo_p, {dut.smp.CPUO[1], dut.smp.CPUO[0]},
                  {dut.smp.CPUI[1], dut.smp.CPUI[0]}, spc_pc, pc);
      end
      if (spc_pc !== spc_pc_p) begin
        spc_pc_p <= spc_pc;
        $fdisplay(af, "%0d SPC  pc %04X -> %04X  [cpui=%04X cpuo=%04X cpu_pc=%04X]",
                  cyc, spc_pc_p, spc_pc,
                  {dut.smp.CPUI[1], dut.smp.CPUI[0]}, {dut.smp.CPUO[1], dut.smp.CPUO[0]}, pc);
      end
    end
  end

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
  // A[22]==0 is the test that covers both windows: $00-$3F has [23:22]=00 and
  // $80-$BF has [23:22]=10, so masking two bits to zero excludes the game's own
  // bank.  The first version of this filter did exactly that and reported one
  // PPU write in a whole boot; the second version used [23:22] and repeated it.
  wire ppu_sel = dut.CPU.P65C816.EN & ~dut.CPU.P65C816.WE_N
                 & (dut.CPU.P65C816.A_OUT[22] == 1'b0)
                 & (dut.CPU.P65C816.A_OUT[15:8] == 8'h21)
                 & (dut.CPU.P65C816.A_OUT[7:6] == 2'b00);  // $2100-$213F, the PPU
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
    for (i = 0; i < 32768; i = i + 1) vram_lo[i] = 8'h00;
    for (i = 0; i < 32768; i = i + 1) vram_hi[i] = 8'h00;
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
        reg [1023:0] vf_path;
        if ($value$plusargs("vidlog=%s", vf_path)) vf = 1;
      end
      begin
        reg [1023:0] wf_path;
        if ($value$plusargs("wrlog=%s", wf_path)) begin
          wf = $fopen(wf_path, "w");
          if (wf == 0) $display("warning: could not open %0s; no wrlog", wf_path);
        end
      end
      begin
        reg [1023:0] ap_path;
        if ($value$plusargs("apulog=%s", ap_path)) begin
          af = $fopen(ap_path, "w");
          if (af == 0) $display("warning: could not open %0s; no apulog", ap_path);
        end
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
      begin
        reg [1023:0] fp_path;
        if ($value$plusargs("frame=%s", fp_path)) begin
          fp = 1;
        end
      end
      begin
        reg [1023:0] vl_path;
        if ($value$plusargs("vramlog=%s", vl_path)) begin
          vlog = $fopen(vl_path, "w");
          if (vlog == 0) $display("warning: could not open %0s; no vramlog", vl_path);
        end
      end
      begin
        reg [1023:0] bl_path;
        if ($value$plusargs("buslog=%s", bl_path)) begin
          bl = $fopen(bl_path, "w");
          if (bl == 0) $display("warning: could not open %0s; no buslog", bl_path);
        end
      end
      if ($value$plusargs("wlat=%d", wlat)) ;
    end

    repeat (16) @(posedge clk);
    rst_n = 1'b1;
    repeat (8) @(posedge clk);
    enable = 1'b1;
    $display("enable raised at cycle %0d, running to %0d", cyc, cycles_max);

    wait (stopped === 1'b1);
    $display("stopped at cycle %0d: last pc=%04X pbr=%02X sp=%04X p=%02X ir=%02X",
             cyc, pc, pbr, sp, p, ir);
    $display("video: HDE pixels=%0d, colour changes on HDE=%0d, final RGB=%04X",
             hde_count, rgb_changes, RGB_OUT);
    $display("vram writes=%0d", vram_wr);
    begin
      reg [1023:0] fp_path2;
      if ($value$plusargs("frame=%s", fp_path2)) begin
        integer fd;
        fd = $fopen(fp_path2, "w");
        if (fd != 0) begin
          $fdisplay(fd, "P3 256 224 255");
          for (fy = 0; fy < 224; fy = fy + 1)
            for (fx = 0; fx < 256; fx = fx + 1)
              $fdisplay(fd, "%0d %0d %0d",
                        (frame_buf[fy*256+fx] >> 10) & 31,
                        (frame_buf[fy*256+fx] >> 5) & 31,
                        frame_buf[fy*256+fx] & 31);
          $fclose(fd);
          $display("frame written to %0s", fp_path2);
        end
      end
    end
    if (tf != 0) $fclose(tf);
    $finish;
  end

endmodule
