// SPDX-License-Identifier: MIT
//
// Board-level bench: the real snestang_top, the real SDRAM controller, and a
// behavioural SDRAM part.
//
// Why this bench exists
// ---------------------
// Every simulation this project has run before this one instantiates `main`
// (gsu_tb.sv) or `SNES` (snes_tb.sv) with ideal memory arrays.  Neither contains
// the SDRAM controller, the second clock domain, or the req/ack toggle
// handshakes -- the entire layer where a fault that appears only on the board
// must live.  That is why the coprocessor could be proven correct in simulation
// while the board failed (core-log entry 72), and why six hardware cycles were
// spent inferring controller behaviour from a capture card.
//
// This bench closes that gap by instantiating the board's own top level and
// driving its SDRAM pins with a model of the part the Console carries.  It is
// deliberately NOT a re-implementation of snestang_top's glue in a testbench:
// the glue is the suspect, so copying it would reproduce the bug rather than
// find it.
//
// What is real here: snestang_top, main, the SNES core, the cartridge mappers,
// the GSU, sdram_cl2_2ch (the controller), and the loader protocol.
// What is modelled: the SDRAM part (sim_sdram), the PLLs and primitives
// (gowin_sim.sv), and the HDMI serialiser (hdmi_stub.sv, which is this
// project's existing stub and keeps only the raster).
//
// Clocking
// --------
// sys_clk is the 50 MHz oscillator.  Everything downstream of it -- mclk
// 21.505 MHz, fclk 64.516 MHz, fclk_p at 225 degrees, hclk 74.25 MHz and
// hclk5x 371.25 MHz -- comes from the PLL models driven by those pins, so the
// 3:1 mclk/fclk ratio and the controller's six-mclk slot structure are the
// board's, not a convenience.
//
// Running
// -------
//   tools/sim/run_board_sim.sh <rom.sfc> [--frames N] [--out DIR]
//
// The run prints a line per sample interval with the machine's gates and the
// coprocessor's counters, and at the end a one-line summary of the SDRAM
// traffic and the CPU-port and BSRAM handshake counts, plus `frames` from the
// machine's own debug counters in <out>/trace_meta.txt.  A run whose summary
// shows `loaded=1 enable=1` with `rom_acc` climbing and a nonzero frame count
// has booted the cartridge; a run that never leaves `pc=0000 rom_acc=0` has
// not loaded at all, which is a bench or plusarg problem rather than a machine
// fault and must not be read as one.  There is no picture: the PPM capture was
// removed and this bench reports counts, so judge a run by the counters and by
// `tools/tinysnes_dbg.py analyze` over the trace dump.

`timescale 1ns/1ps

module board_tb;

  // ---------------------------------------------------------------- clocks
  reg sys_clk = 1'b0;
  always #10 sys_clk = ~sys_clk;             // 50 MHz oscillator

  // ------------------------------------------------------------ top level
  wire [15:0] dq;
  wire [12:0] sdram_a;
  wire [1:0]  sdram_dqm;
  wire [1:0]  sdram_ba;
  wire        sdram_cs_n, sdram_we_n, sdram_ras_n, sdram_cas_n;
  wire        sdram_cke, sdram_clk;
  wire        uart_tx;
  wire [7:0]  led;
  wire        tmds_clk_p, tmds_clk_n;
  wire [2:0]  tmds_d_p, tmds_d_n;

  snestang_top dut (
    .sys_clk(sys_clk),
    .s0(1'b0),

    .UART_RXD(1'b1),          // the embedded loader drives the ROM, not the UART
    .UART_TXD(uart_tx),

    .tmds_clk_p(tmds_clk_p), .tmds_clk_n(tmds_clk_n),
    .tmds_d_p(tmds_d_p),     .tmds_d_n(tmds_d_n),

    .led(led),

    .O_sdram_clk(sdram_clk),
    .O_sdram_cke(sdram_cke),
    .O_sdram_cs_n(sdram_cs_n),
    .O_sdram_cas_n(sdram_cas_n),
    .O_sdram_ras_n(sdram_ras_n),
    .O_sdram_wen_n(sdram_we_n),
    .IO_sdram_dq(dq),
    .O_sdram_addr(sdram_a),
    .O_sdram_dqm(sdram_dqm),
    .O_sdram_ba(sdram_ba)
  );

  // ------------------------------------------------------- the SDRAM part
  // Driven by O_sdram_clk, not fclk: that is the edge the real part sees.
  sim_sdram sdram (
    .DQ(dq),
    .A(sdram_a),
    .BA(sdram_ba),
    .DQM(sdram_dqm),
    .nCS(sdram_cs_n),
    .nRAS(sdram_ras_n),
    .nCAS(sdram_cas_n),
    .nWE(sdram_we_n),
    .CKE(sdram_cke),
    .CLK(sdram_clk)
  );

  // ------------------------------------------------------------- run length
  // Counted on sys_clk so the bound does not depend on any modelled PLL: 50 MHz
  // means one second of simulated time is 50 million counts.
  integer max_cycles = 0;
  integer cyc = 0;

  initial begin
    void'($value$plusargs("maxcycles=%d", max_cycles));
    $display("board_tb: snestang_top + real SDRAM controller + modelled part");
    if (max_cycles == 0) max_cycles = 50_000_000;   // 1 s of board time
    $display("board_tb: run bound %0d sys_clk cycles (%0.2f s of board time)",
             max_cycles, max_cycles / 50.0e6);
  end

  always @(posedge sys_clk) begin
    cyc <= cyc + 1;
    if (cyc == max_cycles) begin
      $display("board_tb: reached the run bound at %0d sys_clk cycles", cyc);
      $display("board_tb: handshakes -- CPU req=%0d ack=%0d (lost %0d) | BSRAM (block RAM) writes=%0d | ARAM req=%0d ack=%0d (lost %0d)",
               cpu_req_t, cpu_ack_t, cpu_req_t - cpu_ack_t,
               bs_wr_t,
               ar_req_t,  ar_ack_t,  ar_req_t  - ar_ack_t);
      $display("board_tb: sdram clk edges=%0d cs_low=%0d cke_low=%0d",
               sdram.n_clk, sdram.n_cs_low, sdram.n_cke_low);
      begin : hist_dump
        integer q;
        for (q = 0; q < 16; q = q + 1)
          if (sdram.hist[q] != 0)
            $display("board_tb:   cmd {nCS,nRAS,nCAS,nWE}=%04b seen %0d times", q[3:0], sdram.hist[q]);
      end
      $display("board_tb: sdram commands seen -- activate=%0d read=%0d write=%0d refresh=%0d mrs=%0d",
               sdram.n_act, sdram.n_read, sdram.n_write, sdram.n_ref, sdram.n_mrs);
      $finish;
    end
  end

  // +tracedump=base writes tinysnes_dbg's three trace buffers and its
  // counters in the form tools/tinysnes_dbg.py reads from the board, so
  // `tinysnes_dbg.py analyze --dump base --rom game.sfc` checks the bench
  // and the board with the same code.
  final begin : dbg_dump
    string base;
    integer fd;
    if ($value$plusargs("tracedump=%s", base)) begin
      $writememh({base, "_rl.hex"}, dut.dbg.trace[0].ram.m);
      $writememh({base, "_op.hex"}, dut.dbg.trace[1].ram.m);
      $writememh({base, "_mm.hex"}, dut.dbg.trace[2].ram.m);
      fd = $fopen({base, "_meta.txt"}, "w");
      $fdisplay(fd, "ctrl %0d", dut.dbg.ctrl);
      $fdisplay(fd, "wp %0d %0d %0d", dut.dbg.wp[0], dut.dbg.wp[1], dut.dbg.wp[2]);
      $fdisplay(fd, "wrapped %0d %0d %0d", dut.dbg.wrapped[0], dut.dbg.wrapped[1], dut.dbg.wrapped[2]);
      $fdisplay(fd, "full %0d %0d %0d", dut.dbg.full[0], dut.dbg.full[1], dut.dbg.full[2]);
      $fdisplay(fd, "seen %0d %0d %0d", dut.dbg.seen[0], dut.dbg.seen[1], dut.dbg.seen[2]);
      $fdisplay(fd, "uptime %0d", dut.dbg.uptime);
      $fdisplay(fd, "frames %0d", dut.dbg.frames);
      $fdisplay(fd, "stops %0d", dut.dbg.stops);
      $fdisplay(fd, "go_time %0d", dut.dbg.go_time);
      $fdisplay(fd, "bsram_wrs %0d", dut.dbg.bsram_wrs);
      $fdisplay(fd, "rom_reqs %0d", dut.dbg.rom_reqs);
      $fdisplay(fd, "rom_defers %0d", dut.dbg.rom_defers);
      $fdisplay(fd, "rom_timeouts %0d", dut.dbg.rom_timeouts);
      $fclose(fd);
      $display("board_tb: trace buffers written to %s_{rl,op,mm}.hex, counters to %s_meta.txt", base, base);
    end
  end

  // ------------------------------------------------------- SDRAM telemetry
  // The controller keeps its three ports on separate SDRAM banks (the header of
  // sdram_cl2_2ch.v: bank 0 is ROM/WRAM, bank 1 is BSRAM/RISC-V, bank 2 is
  // ARAM), so counting served commands per bank separates the coprocessor's
  // memory traffic from the 65816's.  That is the measurement that says whether
  // the GSU's work RAM and pixel cache are actually being serviced.
  integer act_b [0:3];
  integer rd_b  [0:3];
  integer wr_b  [0:3];

  integer bi;
  initial begin
    for (bi = 0; bi < 4; bi = bi + 1) begin
      act_b[bi] = 0; rd_b[bi] = 0; wr_b[bi] = 0;
    end
  end

  always @(posedge sdram_clk) begin
    if (~sdram_cs_n) begin
      if (~sdram_ras_n && sdram_cas_n && sdram_we_n)  act_b[sdram_ba] = act_b[sdram_ba] + 1;
      if ( sdram_ras_n && ~sdram_cas_n && ~sdram_we_n) rd_b[sdram_ba]  = rd_b[sdram_ba]  + 1;
      if ( sdram_ras_n && ~sdram_cas_n &&  sdram_we_n) wr_b[sdram_ba]  = wr_b[sdram_ba]  + 1;
    end
  end

  // --------------------------------------------------- image landing check
  // Does the picture the CPU will look at match the cartridge?  The loader
  // writes byte N into SDRAM word N>>1, so file offset $7FFC -- the LoROM
  // location of the reset vector -- lands in word $3FFE.  Comparing the model's
  // array against values read straight out of the .sfc on the host is the one
  // check that cannot be fooled by an instrument in this file: it is a plain
  // memory dump of the thing the CPU reads.
  reg landed_reported = 1'b0;
  always @(posedge sys_clk) begin
    if (dut.loaded && !landed_reported) begin
      landed_reported <= 1'b1;
      $display("board_tb: image landing check, SDRAM words (expect word0=0000 word3=30C2 word3FFE=FF9C for Star Fox)");
      $display("board_tb:   word0=%04X word1=%04X word2=%04X word3=%04X",
               sdram.mem[32'h0], sdram.mem[32'h1], sdram.mem[32'h2], sdram.mem[32'h3]);
      $display("board_tb:   word3FFE=%04X (reset vector, CPU reads $FFFC)  word3FFF=%04X",
               sdram.mem[32'h3FFE], sdram.mem[32'h3FFF]);
      $display("board_tb:   word7FFE=%04X (last word of the 1MiB image)",
               sdram.mem[32'h7FFE]);
    end
  end

  // -------------------------------------------------- handshake accounting
  // The controller services a port when `req ^ ack`, a toggle pair: the host
  // flips req, the controller flips ack back.  If a second request arrives
  // before the first is served, req flips back, `req ^ ack` becomes zero, and
  // BOTH requests are lost with no error anywhere.  Counting each side
  // separately is the only way to see that: a balanced pair means every request
  // was served, and req > ack means requests were silently dropped.
  //
  // This is the discriminator for the "acknowledged but never sampled" class:
  // a counter on the ORIGINATING side of a handshake cannot be fooled by a
  // sampling window on the other side.
  integer cpu_req_t  = 0, cpu_ack_t  = 0;
  integer bs_wr_t    = 0;
  integer ar_req_t   = 0, ar_ack_t   = 0;
  reg     cpu_req_p  = 1'b0, cpu_ack_p = 1'b0;
  reg     bs_wr_p    = 1'b0;
  integer ovr_n      = 0;
  reg     ar_req_p   = 1'b0, ar_ack_p  = 1'b0;

  always @(posedge sdram_clk) begin
    if (dut.cpu_req    !== cpu_req_p) begin
      // A toggle while the controller still owes the previous one cancels both.
      if (cpu_req_p !== dut.sdram.cpu_req_ack && ovr_n < 10) begin
        ovr_n = ovr_n + 1;
        $display("[ovr] %0t cpu_req toggled over an unaccepted request: loading=%b addr=%06X we=%b",
                 $time, dut.loading, dut.cpu_addr, dut.cpu_we);
      end
      cpu_req_t = cpu_req_t + 1; cpu_req_p = dut.cpu_req;
    end
    if (dut.sdram.cpu_req_ack !== cpu_ack_p) begin cpu_ack_t = cpu_ack_t + 1; cpu_ack_p = dut.sdram.cpu_req_ack; end
    // BSRAM is block RAM in snestang_top since core-log entry 88; count write strobes.
    if (dut.bsram_wr && !bs_wr_p) bs_wr_t = bs_wr_t + 1;
    bs_wr_p = dut.bsram_wr;
    if (dut.aram_req   !== ar_req_p)  begin ar_req_t  = ar_req_t + 1;  ar_req_p  = dut.aram_req; end
    if (dut.sdram.aram_req_ack !== ar_ack_p) begin ar_ack_t = ar_ack_t + 1; ar_ack_p = dut.sdram.aram_req_ack; end
  end

  // Report bank traffic once a second of board time, so a long run shows the
  // shape of what the machine is doing rather than only its end state.
  always @(posedge sys_clk) begin
    if (cyc > 0 && cyc % 50_000_000 == 0) begin
      $display("[sdram] bank0(ROM) act=%0d rd=%0d wr=%0d | bank1 act=%0d rd=%0d wr=%0d | bank2(ARAM) act=%0d rd=%0d wr=%0d",
               act_b[0], rd_b[0], wr_b[0], act_b[1], rd_b[1], wr_b[1], act_b[2], rd_b[2], wr_b[2]);
      $fflush();
    end
  end



  // +romwin=T prints the CPU port's request path every mclk for 400 mclk from
  // T ns: the cartridge address and its posted copy, the WRAM strobes, the
  // req/ack toggle pair and the two read registers.  T is in ns because
  // $value$plusargs reads a 32-bit integer.  It found the lost GSU fetch of
  // core-log entry 88.
  integer romwin = 0; integer rw_n = 0;
  initial void'($value$plusargs("romwin=%d", romwin));
  always @(posedge dut.mclk) if (romwin != 0 && $time >= longint'(romwin) * 1000 && rw_n < 400) begin
    rw_n <= rw_n + 1;
    $display("[rw] %0t ROMA=%06X ce%b oe%b sd=%06X | wram rd%b wr%b A=%05X | req%b ack%b port%b caddr=%06X p0=%04X p1=%04X tog%b",
      $time, dut.ROM_ADDR, dut.ROM_CE_N, dut.ROM_OE_N, dut.rom_addr_sd, dut.wram_rd, dut.wram_wr, dut.WRAM_ADDR,
      dut.cpu_req, dut.cpu_ack, dut.cpu_port, dut.cpu_addr, dut.cpu_port0, dut.cpu_port1, dut.cpu_dout_tog);
  end
endmodule

// +gsutrace=N prints the GSU's program counter, opcode and wait flags each time
// R15 changes, for the first N changes after a GO, and once every 100000 clocks
// while it does not change.  Bound into GSU because Verilator does not resolve
// a dotted reference through main's unnamed generate block.
module gsu_probe (
  input        CLK, FLAG_GO,
  input [15:0] PC,
  input [7:0]  PBR, OPCODE, ROM_BUF, RAM_BUF,
  input [3:0]  STATE,
  input [2:0]  ROMST,
  input        RLW, RFW, RCW, MLW, MSW, MPW, MFW, MCW, MUW,
  input [20:0] ROM_A,
  input [16:0] RAM_A,
  input [7:0]  ROM_DI, RAM_DI,
  input        ROM_RD_N, RAM_CE_N, RAM_WE_N
);
  integer n = 0, still = 0, lim = 0;
  reg [15:0] pc_p = 16'hFFFF;
  initial void'($value$plusargs("gsutrace=%d", lim));
  always @(posedge CLK) if (lim != 0 && FLAG_GO) begin
    still <= still + 1;
    if ((PC != pc_p && n < lim) || still == 100000) begin
      pc_p <= PC; n <= n + 1; still <= 0;
      $display("[gsu] %0t pc=%02X:%04X op=%02X st=%0d romst=%0d wait rl%b rf%b rc%b ml%b ms%b mp%b mf%b mc%b mu%b rombuf=%02X rambuf=%02X roma=%06X romdi=%02X rama=%05X ramdi=%02X ce%b we%b",
        $time, PBR, PC, OPCODE, STATE, ROMST, RLW, RFW, RCW, MLW, MSW, MPW, MFW, MCW, MUW,
        ROM_BUF, RAM_BUF, ROM_A, ROM_DI, RAM_A, RAM_DI, RAM_CE_N, RAM_WE_N);
    end
  end
endmodule

// +gsujob=N prints the GSU's ROM-buffer handshake every mclk for the first N
// mclk of the first GO: the R14 latch, LOAD_PEND/WAIT, R14_CHANGE, ROMWAIT and
// the enables that gate them.  Board probes (core-log entry 88) showed the
// first job stuck at 01:b30d with ROM_LOAD_WAIT set and ROMST_LOAD never
// entered; this is the sim side of that comparison.
module gsu_job_probe (
  input        CLK, FLAG_GO, EN, CPU_EN, R14L, LPEND, LWAIT, LSTART, LEND,
  input        R14C, ROMWAIT, LAST, INCPC,
  input [15:0] PC, R14,
  input [7:0]  OPCODE,
  input [3:0]  STATE,
  input [2:0]  ROMST,
  input        RFW, RCW, MLW, MSW, MPW, MFW, MCW, MUW
);
  integer n = 0, lim = 0;
  reg done = 1'b0;
  initial void'($value$plusargs("gsujob=%d", lim));
  always @(posedge CLK) if (lim != 0 && !done) begin
    if (FLAG_GO) begin
      n <= n + 1;
      if (n + 1 >= lim) done <= 1'b1;
      $display("[job] %0d pc=%04X op=%02X st=%0d romst=%0d en%b cpu%b r14c%b romw%b last%b inc%b latch%b pend%b lw%b ls%b le%b | rf%b rc%b ml%b ms%b mp%b mf%b mc%b mu%b r14=%04X",
        n, PC, OPCODE, STATE, ROMST, EN, CPU_EN, R14C, ROMWAIT, LAST, INCPC, R14L, LPEND, LWAIT,
        LSTART, LEND, RFW, RCW, MLW, MSW, MPW, MFW, MCW, MUW, R14);
    end else if (n != 0) done <= 1'b1;
  end
endmodule

bind GSU gsu_job_probe gsu_job_probe_i (
  .CLK(CLK), .FLAG_GO(FLAG_GO), .EN(EN), .CPU_EN(CPU_EN), .R14L(R14_CHANGE_LATCH),
  .LPEND(ROM_LOAD_PEND), .LWAIT(ROM_LOAD_WAIT), .LSTART(ROM_LOAD_START), .LEND(ROM_LOAD_END),
  .R14C(R14_CHANGE), .ROMWAIT(MC.ROMWAIT), .LAST(MC.LAST_CYCLE), .INCPC(MC.INCPC),
  .PC(R[15]), .R14(R[14]), .OPCODE(OPCODE), .STATE(STATE[3:0]), .ROMST(ROMST),
  .RFW(ROM_FETCH_WAIT), .RCW(ROM_CACHE_WAIT),
  .MLW(RAM_LOAD_WAIT), .MSW(RAM_SAVE_WAIT), .MPW(RAM_PCF_WAIT),
  .MFW(RAM_FETCH_WAIT), .MCW(RAM_CACHE_WAIT), .MUW(MULT_WAIT)
);

bind GSU gsu_probe gsu_probe_i (
  .CLK(CLK), .FLAG_GO(FLAG_GO), .PC(R[15]), .PBR(PBR), .OPCODE(OPCODE),
  .ROM_BUF(ROM_BUF), .RAM_BUF(RAM_BUF), .STATE(STATE[3:0]), .ROMST(ROMST),
  .RLW(ROM_LOAD_WAIT), .RFW(ROM_FETCH_WAIT), .RCW(ROM_CACHE_WAIT),
  .MLW(RAM_LOAD_WAIT), .MSW(RAM_SAVE_WAIT), .MPW(RAM_PCF_WAIT),
  .MFW(RAM_FETCH_WAIT), .MCW(RAM_CACHE_WAIT), .MUW(MULT_WAIT),
  .ROM_A(ROM_A), .RAM_A(RAM_A), .ROM_DI(ROM_DI), .RAM_DI(RAM_DI),
  .ROM_RD_N(ROM_RD_N), .RAM_CE_N(RAM_CE_N), .RAM_WE_N(RAM_WE_N)
);
