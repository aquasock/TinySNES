/* 
 * Top level for snestang
 * nand2mario, 2023.6
 */

//`define STEP_TRACE

`ifndef CONFIG_V
// TinySNES: the vendor `error directive is not portable to the open front
// end, and config.v is always first in the file list, so the guard is a
// comment here.  Missing config.v still fails loudly, on configPackage.
`endif

import configPackage::*;

module snestang_top (
    input sys_clk,
    input s0,

    // UART
    input UART_RXD,
    output UART_TXD,

    // HDMI TX
    output       tmds_clk_p,
    output       tmds_clk_n,
    output [2:0] tmds_d_p,
    output [2:0] tmds_d_n,

    // LED
    output [7:0] led,

    // MicroSD
    // output sd_clk,
    // inout  sd_cmd,      // MOSI
    // input  sd_dat0,     // MISO
    // output sd_dat1,
    // output sd_dat2,
    // output sd_dat3,

    // SPI flash
    // output flash_spi_cs_n,          // chip select
    // input flash_spi_miso,           // master in slave out
    // output flash_spi_mosi,          // mster out slave in
    // output flash_spi_clk,           // spi clock
    // output flash_spi_wp_n,          // write protect
    // output flash_spi_hold_n,        // hold operations

`ifdef CONTROLLER_SNES
    // snes controllers
    output joy1_strb,
    output joy1_clk,
    input joy1_data,
    output joy2_strb,
    output joy2_clk,
    input joy2_data,
`endif

`ifdef CONTROLLER_DS2
    // dualshock controllers
    output ds_clk,
    input ds_miso,
    output ds_mosi,
    output ds_cs,
    output ds_clk2,
    input ds_miso2,
    output ds_mosi2,
    output ds_cs2,
`endif

    // USB1 and USB2
`ifdef USB1
    inout usb1_dp,
    inout usb1_dn,
`endif
`ifdef USB2
    inout usb2_dp,
    inout usb2_dn,
`endif
    // SDRAM
    output O_sdram_clk,
    output O_sdram_cke,
    output O_sdram_cs_n,            // chip select
    output O_sdram_cas_n,           // columns address select
    output O_sdram_ras_n,           // row address select
    output O_sdram_wen_n,           // write enable
    inout [SDRAM_DATA_WIDTH-1:0] IO_sdram_dq,       // 31 bit bidirectional data bus
    output [SDRAM_ROW_WIDTH-1:0] O_sdram_addr,     // 11 bit multiplexed address bus
    output [SDRAM_DATA_WIDTH/8-1:0] O_sdram_dqm,       // 
    output [1:0] O_sdram_ba         // 4 banks
);

// Clock signals
wire mclk;                      // SNES master clock at 21.5054Mhz (~21.477)
wire fclk;                      // Fast clock for sdram for SDRAM
wire fclk_p;                    // 180-degree shifted fclk
wire clk27;                     // 27Mhz for hdmi clock generation
wire hclk5, hclk;               // 720p pixel clock at 74.25Mhz, and 5x high-speed

reg resetn = 1'b0;              // reset is cleared after 4 cycles
wire pause;

reg [15:0] resetcnt = 16'hffff;
always @(posedge mclk) begin
    resetcnt <= resetcnt == 0 ? 0 : resetcnt - 1;
     if (resetcnt == 0)
//  if (resetcnt == 0 && s0)   // primer25k, nano20k
//     if (resetcnt == 0 && ~s0)   // mega138k
        resetn <= 1'b1;
end

// rPLL for Tang Nano 20K
`ifdef PLL_R

// Clocks for Nano 20K
assign clk27 = sys_clk;
gowin_pll_hdmi pll_hdmi (
    .clkin(sys_clk),            // 27 Mhz input
    .clkout(hclk5)              // 371.25Mhz
);

CLKDIV #(.DIV_MODE(5)) div5 (
    .CLKOUT(hclk),              // 74.25Mhz
    .HCLKIN(hclk5),
    .RESETN(resetn),
    .CALIB(1'b0)
);

gowin_pll_snes pll_snes (
    .clkin(sys_clk),
    .clkout(fclk),              // 86.4
    .clkoutp(fclk_p),           // 225-degrees shifted
    .clkoutd(mclk)              // 21.6
);

`elsif VERILATOR
// Simulated clocks for verilator
reg [2:0] clk_cnt = 3'b0;       // 0 1 2 3 4 5
reg mclk_buf;                   // 0 0 0 1 1 1
assign fclk = clk_cnt[0];       // 0 1 0 1 0 1
assign mclk = mclk_buf;
always @(posedge sys_clk) begin
    clk_cnt <= clk_cnt + 3'b1; 
    if (clk_cnt == 3'd5) begin
        clk_cnt <= 0;
        mclk_buf <= 0;
    end
    if (clk_cnt == 3'd2)
        mclk_buf <= 1;
end

`else
// Mega 138K: mclk=21.5054, fclk=64.5161
// Primer 25K: mclk=21.4844, fclk=85.9375
gowin_pll_snes pll_snes (
    .clkout0(mclk),             // 21.4844
    .clkout1(fclk),
    .clkout2(fclk_p),
    .clkin(sys_clk)             // 50 Mhz input
);

// HDMI clocks
gowin_pll_27 pll_27 (
    .clkin(sys_clk),
    .clkout0(clk27)
);
gowin_pll_hdmi pll_hdmi (
    .clkin(clk27),              // 27 Mhz input
    .clkout(hclk5)              // 371.25Mhz; TinyTang's wrapper has one output
);

// TinySNES: the pixel clock is the 5x clock divided by five here, in the shape
// TinyNES's ae350_soc.sv:545 and TinyTang's desktop core both use on this
// board.  A single-output PLL, one CLKDIV pinned to the right side's HCLK block
// beside the TMDS pins (tinysnes.cst), and no second PLL output to compete with
// it for the fast-clock lanes.
CLKDIV #(.DIV_MODE("5")) div5 (
    .CLKOUT(hclk),              // 74.25Mhz
    .HCLKIN(hclk5),
    .RESETN(resetn),
    .CALIB(1'b0)
);

`endif

wire [23:0] ROM_ADDR;
wire ROM_CE_N, ROM_OE_N, ROM_WE_N, ROM_WORD;
wire [15:0] ROM_D;
wire [15:0] ROM_Q;
assign      ROM_Q = (ROM_WORD || ~ROM_ADDR[0]) ? cpu_port0 : { cpu_port0[7:0], cpu_port0[15:8] };

wire [16:0] WRAM_ADDR;
wire        WRAM_CE_N;
wire        WRAM_OE_N;
wire        WRAM_RD_N;
wire        WRAM_WE_N;
wire  [7:0] WRAM_SD_Q = WRAM_ADDR[0] ? cpu_port1[15:8] : cpu_port1[7:0];
wire  [7:0] WRAM_Q;
wire  [7:0] WRAM_D;
wire        wram_rd = ~WRAM_CE_N & ~WRAM_RD_N;
wire        wram_wr = ~WRAM_CE_N & ~WRAM_WE_N;

wire [19:0] BSRAM_ADDR;
wire        BSRAM_CE_N;
wire        BSRAM_OE_N;
wire        BSRAM_WE_N;
wire        BSRAM_RD_N;
wire  [7:0] BSRAM_Q = bsram_dout;
wire  [7:0] BSRAM_D;

wire [15:0] VRAM1_ADDR;
wire        VRAM1_WE_N;
wire  [7:0] VRAM1_D, VRAM1_Q;
wire [15:0] VRAM2_ADDR;
wire        VRAM2_WE_N;
wire  [7:0] VRAM2_D, VRAM2_Q;
wire        VRAM_OE_N;

wire [15:0] ARAM_ADDR;
wire        ARAM_CE_N;
wire        ARAM_OE_N;
wire        ARAM_WE_N;
wire [15:0] aram_dout;
wire  [7:0] ARAM_Q = ARAM_ADDR[0] ? aram_dout[15:8] : aram_dout[7:0];
wire  [7:0] ARAM_D;
wire        aram_16 = 0;

wire BLEND = 1'b0;
reg        PAL;
wire       dotclk  /*verilator public*/;
wire [14:0] rgb_out  /*verilator public*/;
wire [8:0] x_out /*verilator public*/, y_out /*verilator public*/;
wire       hblankn,vblankn;

wire [15:0] audio_l /*verilator public*/, audio_r /*verilator public*/;
wire audio_ready /*verilator public*/;
wire audio_en /*XXX synthesis syn_keep=1 */;

wire snes_joy_strb;
wire snes_joy1_clk, snes_joy2_clk;
wire [1:0] snes_joy1_di, snes_joy2_di;

// OR together when both SNES and DS2 controllers are connected (right now only nano20k supports both simultaneously)
wire [11:0] joy1_btns_ds2, joy2_btns_ds2;
wire [11:0] joy1_btns_snes, joy2_btns_snes;
wire [11:0] joy1_usb, joy2_usb;
wire [11:0] hid1, hid2;

wire [5:0] ph;
reg snes_start = 1'b0;
wire pause_snes_for_frame_sync;

wire [7:0] loader_do;
wire loader_do_valid, loading, header_finished;

reg [22:0] loader_addr = 0;

reg [7:0] dbg_reg, dbg_sel; 
wire [7:0] dbg_dat_out, dbg_dat_in;
reg dbg_reg_wr = 0;
reg dbg_break = 0;

wire [7:0] rom_type;
wire [3:0] rom_size, ram_size;
wire [23:0] rom_mask, ram_mask;

wire sdram_busy;
wire refresh;
reg enable; // && ~dbg_break && ~pause;
reg loaded;

always @(posedge mclk) begin        // wait until memory initialize to start SNES
`ifdef TINYSNES_ROM_CHECK
    // Diagnostic build: the probe owns the CPU port until it has read the ROM
    // words back, so the machine must not start before then.
    if (~sdram_busy && ~pause_snes_for_frame_sync && loaded && rom_probe_done)
`elsif TINYSNES_READ_STABILITY
    // Diagnostic build: the read-stability test owns the CPU port until it has
    // finished its double-reads, so the machine must not start before then.
    if (~sdram_busy && ~pause_snes_for_frame_sync && loaded && stability_done)
`else
    if (~sdram_busy && ~pause_snes_for_frame_sync && loaded)
`endif
        enable <= 1;
    else 
        enable <= 0;
end

`ifdef TINYSNES_FETCH_PROBE
// Diagnostic build: capture the CPU's first ROM access after enable at three
// points in time plus the mapper's address for that access, so a wrong address
// and a sample taken before the data exists are told apart in one load.
//
// The previous version of this probe latched ROM_Q once, on the first mclk where
// ROMSEL and ROM_OE were both asserted.  Two independent reasons make that
// reading uninformative: ROM_OE_N is derived from the master-cycle clock
// enables and is low for most of an access rather than as a read marker, and
// the SDRAM controller cannot have returned the word that early anyway -- the
// request crosses from mclk into the arbiter's fclk domain and port 0 registers
// dq_in at cycle[5], roughly two to three mclk after the address appears.  A
// zero from that probe could therefore be the instrument, not the machine.
//
// Fields, low to high in fp_bus:
//   [15:0]  ROM_Q on the first assertion of ROMSEL      (the old sample point)
//   [31:16] ROM_Q two mclk later
//   [47:32] ROM_Q four mclk later
//   [63:48] ROM_ADDR[15:0] for that access, expect 0x7FFC
//   [79:64] ROM_ADDR[23:8] for that access, expect 0x007F
// ActRaiser's reset vector at ROM offset 0x7FFC is 0x8000, so a healthy first
// fetch reads as 0x8000 with only bit 15 set on whichever sample point is taken
// after the controller answers.
reg [79:0] fp_bus = 80'd0;
reg  [2:0] fp_cnt = 3'd0;
reg        fetch_seen = 1'b0;
wire       fp_sel = enable && ~ROM_CE_N;

// fp_cnt walks the sample window and parks at 7 when it is over.  If ROMSEL is
// released before the window closes the remaining samples are dropped rather
// than taken from a later access, because an offset measured from the wrong
// access is worse than a missing stripe.
always @(posedge mclk) begin
    if (~fp_sel) begin
        if (fp_cnt != 3'd0 && fp_cnt != 3'd7)
            fp_cnt <= 3'd7;
    end else begin
        case (fp_cnt)
        3'd0: begin
            fp_bus[15:0] <= ROM_Q;
            fetch_seen   <= 1'b1;
            fp_cnt       <= 3'd1;
        end
        3'd1: fp_cnt <= 3'd2;
        3'd2: begin
            fp_bus[31:16] <= ROM_Q;
            fp_cnt        <= 3'd3;
        end
        3'd3: fp_cnt <= 3'd4;
        3'd4: begin
            fp_bus[47:32] <= ROM_Q;
            fp_bus[63:48] <= ROM_ADDR[15:0];
            fp_bus[79:64] <= ROM_ADDR[23:8];
            fp_cnt        <= 3'd7;
        end
        default: fp_cnt <= 3'd7;
        endcase
    end
end
`endif

`ifdef TINYSNES_CPU_PROBE
  `define TINYSNES_CPU_SAMPLER 1
`endif
`ifdef TINYSNES_LIVE_PROBE
  `define TINYSNES_CPU_SAMPLER 1
`endif

`ifdef TINYSNES_CPU_SAMPLER
// Diagnostic build: ask the CPU where it is.  The core already carries a debug
// port that nothing drives: DBG_SEL[0] selects the CPU, DBG_REG picks a
// register and 0x06/0x07 return PC[7:0] and PC[15:8], 0x09/0x0A return SP, and
// DBG_DAT_OUT is combinational from DBG_REG.  Driving it from here needs no
// change to any upstream file, and DBG_REG_WR stays low so nothing is written.
//
// probe_bus fields, low to high:
//   [15:0]  ROM accesses since reset, low half of the count
//   [31:16] the same counter's high half, so the count reads unambiguously
//   [47:32] PC at the most recent sample
//   [63:48] SP, which is 0x01FF out of reset, so a plausible value proves the
//           debug port is answering
//   [79:64] the CPU's status byte from DBG_REG 0x15, eight bits used:
//           7 GotInterrupt, 6 IsResetInterrupt, 5 IsNMIInterrupt,
//           4 IsIRQInterrupt, 3 RDY_IN, 2 EN, 1 WAIExec, 0 STPExec
// A counter that races with a PC that does not move means the CPU is stalled
// rather than looping, and the status byte says which kind: WAIExec or STPExec
// is a CPU that stopped itself and is waiting for an event, while RDY_IN low is
// a CPU held off the bus by something else in the machine.
//
// PC is read as two bytes one mclk apart, so a sample can tear across a byte
// boundary if the CPU crosses one between the two reads.  The status byte and
// SP are single reads and do not tear.
reg  [2:0]  dbg_ph = 3'd0;      // 0 PC low, 1 PC high, 2 SP low, 3 SP high, 4 status
reg  [7:0]  pc_lo_r = 8'd0, pc_hi_r = 8'd0;   // bytes, as DBG_REG returns them
reg [15:0]  sp_r = 16'd0;
reg  [7:0]  flags_r = 8'd0;
reg [15:0]  pc_s0 = 16'd0, pc_s1 = 16'd0;
reg [31:0]  rom_acc = 32'd0;
reg         rom_ce_d = 1'b1;
reg [21:0]  pc_tick = 22'd0;
reg [31:0]  live_bus = 32'd0;             // latched for the split display
reg [79:0]  fp_bus = 80'd0;
wire [15:0] pc_now = {pc_hi_r, pc_lo_r};
wire        pc_changed = (pc_s0 != pc_s1);

always @(*) dbg_reg = (dbg_ph == 3'd0) ? 8'h06 : // PC[7:0]
                      (dbg_ph == 3'd1) ? 8'h07 : // PC[15:8]
                      (dbg_ph == 3'd2) ? 8'h09 : // SP[7:0]
                      (dbg_ph == 3'd3) ? 8'h0A : // SP[15:8]
                                         8'h15;   // status byte

always @(posedge mclk) begin
    // Driven from a clocked block, not from always @(*): a constant on the right
    // of a combinational always has no sensitivity and never drives, so the
    // port would read as undriven in simulation and depend on constant folding
    // in synthesis.
    dbg_sel    <= 8'b0000_0001;
    dbg_reg_wr <= 1'b0;
    dbg_ph     <= (dbg_ph == 3'd4) ? 3'd0 : dbg_ph + 3'd1;
    case (dbg_ph)
    3'd0: pc_lo_r      <= dbg_dat_out;
    3'd1: pc_hi_r      <= dbg_dat_out;
    3'd2: sp_r[7:0]    <= dbg_dat_out;
    3'd3: sp_r[15:8]   <= dbg_dat_out;
    3'd4: flags_r      <= dbg_dat_out;
    endcase

    // One count per ROM access.  rom_ce_d holds ROMSEL as it was on the previous
    // mclk, so the test is a genuine falling edge; storing the inverted level
    // instead counts every cycle ROMSEL is asserted, which reads as one access
    // per master clock on a machine whose bus is busy.
    rom_ce_d <= ROM_CE_N;
    if (~ROM_CE_N && rom_ce_d)
        rom_acc <= rom_acc + 32'd1;

    // Two PC samples 2^22 mclk apart, about 0.2 s at 21.5 MHz.
    pc_tick <= pc_tick + 22'd1;
    if (pc_tick == 22'h3F_FFFF) begin
        pc_s1 <= pc_s0;
        pc_s0 <= pc_now;
        // The split display redraws on top of a live picture, so what it shows
        // has to stand still long enough to be photographed: the counter and
        // the PC are latched here at the same 0.2 s cadence as the samples.
        live_bus <= {pc_now, rom_acc[15:0]};
    end

    fp_bus <= {8'd0, flags_r, sp_r, pc_s0, rom_acc[31:16], rom_acc[15:0]};
end

assign dbg_dat_in = 8'h00;
`endif

`ifdef TINYSNES_APU_PROBE
// Diagnostic build: read the APU handshake from the side that is stuck on it.
//
// The two port banks are separate registers -- CPUI[0:3] is what the 65816
// writes and the SPC700 reads, CPUO[0:3] is what the SPC700 writes and the
// 65816 reads -- and the IPL's stage machine decides what both CPUs are waiting
// for.  Decoded from the IPLROM in smp.v: at $FFC3 the SPC700 sets A to $00 and
// clears ARAM, at $FFC9/$FFCC it publishes $AA to CPUO[0] and $BB to CPUO[1],
// and at $FFCF it sits in `CMP $F4,#$CC / BNE $FFCF` until CPUI[0] holds $CC.
// Its A, X and Y are therefore all $00 for as long as it waits, which is also
// exactly what an undriven debug path would return -- so the SPC700's A and Y
// cannot tell a correct wait from a dead port, and this probe does not read
// them.  The 65816 is the informative side: zelda.smc at $888E does
// `LDA #$BBAA` and at $8891 `CMP $2140 / BNE $8891`, so it compares against a
// value CPUO already holds.  A of $BBAA with M and X clear beside a CPUO of
// $BBAA and a PC still at $8891 proves the port read is broken and not the
// CPU's own operand; any other A moves the fault to the instruction stream.
//
// probe_bus fields, low to high:
//   [15:0]  CPUO ports 1 and 0         (SMP debug 0x05, 0x04)
//   [31:16] 65816 A                    (DBG_SEL[0], 0x01 high and 0x00 low)
//   [47:32] 65816 PC                   (DBG_SEL[0], 0x07 high and 0x06 low)
//   [63:48] SPC700 PC                  (DBG_SEL[3], 0x04 high and 0x03 low)
//   [79:64] 65816 P, then CPUI port 0  (DBG_SEL[0] 0x08, SMP debug 0x00)
// P bit 5 is M and bit 4 is X: the $8889 `REP #$30` clears both, so the top
// byte should read with those two bits clear -- if either is set the CPU is
// comparing 8-bit operands and the $8891 CMP is not the instruction it looks
// like.  A, P and the port banks are single bytes; the two PCs are 16 bits read
// through an 8-bit port one mclk apart and can tear across a byte boundary, so
// each PC's high byte is read twice and the pair is accepted only when the two
// high reads agree.  Both CPUs execute while this reads them, so an unguarded
// PC would be a different instruction's halves almost every time.
//
// The display also has to stand still to be photographed, which cost a hardware
// cycle to learn: a live 80-bit bus changes every mclk and the raster scans a
// frame out over ~14 ms, so one captured frame carried a different value in
// every row and no stripe could be read.  fp_bus is therefore a latched
// snapshot, refreshed once every 2^19 revolutions of the phase counter -- about
// 0.29 s, roughly three refreshes a second -- the same practice the CPU probe
// uses and the same reason.  A readout is one snapshot of a moving machine, not
// an average.
reg [3:0] apu_ph = 4'd0;
reg [7:0] o0 = 8'd0, o1 = 8'd0;                  // CPUO 0 and 1
reg [7:0] a_lo = 8'd0, a_hi = 8'd0;              // 65816 A
reg [7:0] p_r = 8'd0, i0 = 8'd0;                 // 65816 P, CPUI 0
reg [7:0] pch1 = 8'd0, pcl = 8'd0, pch2 = 8'd0;  // 65816 PC, high read twice
reg [7:0] sph1 = 8'd0, spl = 8'd0, sph2 = 8'd0;  // SPC700 PC, high read twice
reg [7:0] pc_hi = 8'd0, pc_lo = 8'd0;            // last accepted 65816 PC
reg [7:0] spc_hi = 8'd0, spc_lo = 8'd0;          // last accepted SPC700 PC
reg [18:0] apu_wrap = 19'd0;                     // counts phase revolutions
reg [79:0] fp_bus = 80'd0;

// A case rather than a chained ternary: twelve phases do not fit three bits, and
// a phase that fell off the end of a shorter select would silently read the
// 65816 for an SMP register number.  apu_ph is on the right-hand side, so this
// always block has sensitivity; a constant on the right of `always @(*)` never
// drives at all, which is a defect this project has already shipped once.
always @(*) begin
    case (apu_ph)
    4'd0, 4'd1, 4'd5:        dbg_sel = 8'h10;     // the SMP wrapper's port banks
    4'd9, 4'd10, 4'd11:      dbg_sel = 8'h08;     // the SPC700 core
    default:                 dbg_sel = 8'h01;     // the 65816
    endcase
end
always @(*) begin
    case (apu_ph)
    4'd0:    dbg_reg = 8'h04;                    // CPUO 0
    4'd1:    dbg_reg = 8'h05;                    // CPUO 1
    4'd2:    dbg_reg = 8'h00;                    // 65816 A low
    4'd3:    dbg_reg = 8'h01;                    // 65816 A high
    4'd4:    dbg_reg = 8'h08;                    // 65816 P
    4'd5:    dbg_reg = 8'h00;                    // CPUI 0
    4'd6:    dbg_reg = 8'h07;                    // 65816 PC high, first read
    4'd7:    dbg_reg = 8'h06;                    // 65816 PC low
    4'd8:    dbg_reg = 8'h07;                    // 65816 PC high, second read
    4'd9:    dbg_reg = 8'h04;                    // SPC700 PC high, first read
    4'd10:   dbg_reg = 8'h03;                    // SPC700 PC low
    default: dbg_reg = 8'h04;                    // SPC700 PC high, second read
    endcase
end

always @(posedge mclk) begin
    dbg_reg_wr <= 1'b0;
    apu_ph     <= (apu_ph == 4'd11) ? 4'd0 : apu_ph + 4'd1;
    case (apu_ph)
    4'd0:  o0    <= dbg_dat_out;
    4'd1:  o1    <= dbg_dat_out;
    4'd2:  a_lo  <= dbg_dat_out;
    4'd3:  a_hi  <= dbg_dat_out;
    4'd4:  p_r   <= dbg_dat_out;
    4'd5:  i0    <= dbg_dat_out;
    4'd6:  pch1  <= dbg_dat_out;
    4'd7:  pcl   <= dbg_dat_out;
    4'd8:  pch2  <= dbg_dat_out;
    4'd9:  sph1  <= dbg_dat_out;
    4'd10: spl   <= dbg_dat_out;
    4'd11: sph2  <= dbg_dat_out;
    endcase

    // Accept a 16-bit PC only when the high byte read on both sides of the low
    // byte agreed; otherwise keep the last accepted value and let the next
    // revolution try again.  dbg_dat_out on this edge is the current phase's
    // register, so the comparison at phase 8 is against the phase-6 high read.
    if (apu_ph == 4'd8 && pch1 == dbg_dat_out) begin
        pc_hi <= pch1;
        pc_lo <= pcl;
    end
    if (apu_ph == 4'd11 && sph1 == dbg_dat_out) begin
        spc_hi <= sph1;
        spc_lo <= spl;
    end

    // Latch the display snapshot once every 2^19 revolutions of the phase
    // counter, which is 6.29M mclk or about 0.29 s -- roughly three refreshes a
    // second, slow enough that a captured frame carries one value in every row.
    // Counting revolutions rather than mclk keeps the refresh independent of the
    // phase count, so it cannot silently drift into never firing: gating on
    // (tick == terminal) AND (phase == last) instead makes the refresh fire only
    // when two independent counters happen to coincide.
    if (apu_ph == 4'd11) begin
        apu_wrap <= apu_wrap + 19'd1;
        if (apu_wrap == 19'd0)
            fp_bus <= {p_r, i0, spc_hi, spc_lo, pc_hi, pc_lo, a_hi, a_lo, o1, o0};
    end
end

assign dbg_dat_in = 8'h00;
`endif

`ifdef TINYSNES_IRQ_PROBE
// Diagnostic build: why the 65816 has halted.  Entry 27 found the CPU stopping
// on WAI after millions of successful ROM fetches, which means it is waiting for
// an interrupt that never arrives, so this build reads the interrupt history
// rather than the current state.
//
// The three bits come from cpu.v's sticky registers, read through debug register
// 0x16 which cpu.v intercepts; the status byte and the program counter come from
// the 65816 core's own registers 0x15 and 0x06/0x07.  Every sticky bit latches
// from reset and is never cleared, for the reason TCL-013 records.
//
// probe_bus fields, low to high:
//   [7:0]   sticky byte: [2] NMI_FLAG ever set, [1] NMI_EN ever set,
//           [0] VBLANK ever high
//   [15:8]  the core's status byte from 0x15, whose bit 1 is WAIExec and bit 0
//           STPExec, so the halt and the history are read in the same frame
//   [31:16] the 65816's program counter where it halted
//   [47:32] the high byte above zero, unused
//   [79:48] zero
reg [2:0] irq_ph = 3'd0;
reg [7:0] sticky_r = 8'd0;
reg [7:0] status_r = 8'd0;
reg [7:0] pc_lo_r = 8'd0, pc_hi_r = 8'd0;
reg [18:0] irq_wrap = 19'd0;
reg [79:0] fp_bus = 80'd0;

// dbg_sel is set in the clocked block below, not here: a constant on the right of
// `always @(*)` has no sensitivity and never drives, which is a defect this
// project has already shipped once (core-reference TCL-008).
always @(*) begin
    case (irq_ph)
    3'd0:    dbg_reg = 8'h16;        // sticky interrupt history
    3'd1:    dbg_reg = 8'h15;        // status byte, WAI/STP
    3'd2:    dbg_reg = 8'h06;        // PC low
    3'd3:    dbg_reg = 8'h07;        // PC high
    3'd4:    dbg_reg = 8'h06;        // PC low again, so a torn pair is visible
    default: dbg_reg = 8'h07;        // PC high again
    endcase
end

always @(posedge mclk) begin
    dbg_sel    <= 8'h01;             // the 65816, for every phase
    dbg_reg_wr <= 1'b0;
    irq_ph     <= (irq_ph == 3'd5) ? 3'd0 : irq_ph + 3'd1;
    case (irq_ph)
    3'd0: sticky_r <= dbg_dat_out;
    3'd1: status_r <= dbg_dat_out;
    3'd2: pc_lo_r  <= dbg_dat_out;
    3'd3: pc_hi_r  <= dbg_dat_out;
    endcase

    if (irq_ph == 3'd5) begin
        irq_wrap <= irq_wrap + 19'd1;
        if (irq_wrap == 19'd0)
            fp_bus <= {48'd0, pc_hi_r, pc_lo_r, status_r, sticky_r};
    end
end

assign dbg_dat_in = 8'h00;
`endif

`ifdef TINYSNES_LINK_PROBE
// Diagnostic build: both directions of the APU link and both CPUs' state in one
// snapshot, because every probe before this one carried only half of it.  The
// APU probe has CPUO and the 65816's A; the IPL probe has the SPC700's Y and the
// CPUI banks; neither can answer whether the echo the SPC published actually
// reached the 65816, which is the one open question left after core-log entry 11
// established that the SPC is behaving correctly and the 65816 is stuck.
//
// The deadlock being measured: the IPL's block-copy loop at $FFDA waits on
// `CMP Y,$F4`, where $F4 read from the SPC side is CPUI port 0, and publishes
// {Y, A} into CPUO at $FFE0.  The 65816's upload loop at $88EC writes a byte to
// $2140 and waits for the same byte to come back.  Entry 11 measured Y one
// ahead of CPUI port 0, which is the loop's normal steady state, so the SPC is
// waiting for an index the 65816 never sends.
//
// probe_bus fields, low to high:
//   [15:0]  CPUO ports 1 and 0         what the 65816 reads at $2141/$2140
//   [31:16] CPUI ports 1 and 0         what the SPC700 reads at $00F5/$00F4
//   [47:32] 65816 A                    its compare operand at $88EC
//   [63:48] 65816 PC                   where the CPU is, which dates the desync
//   [71:64] SPC700 Y                   its index in the block-copy loop
//   [79:77] a saturating count of times the 65816's PC was seen at $8888, the
//            entry to its upload routine; a lower bound, for the reason below
//   [76]    the 65816's PC has been seen past $8894, i.e. the CPU cleared the
//            first handshake at least once on this boot
//   [75:72] four sticky history bits:
//             [75] CPUI port 0 has ever held $CC, the byte the IPL waits for
//             [74] the SPC700's PC has been outside $FFC0-$FFFF since it was
//                  first seen inside it
//             [73] the SPC700's Y has ever been non-zero
//             [72] CPUO port 0 has changed away from $AA since it was first
//                  seen at $AA
//
// st_past and the entry count answer the next one.  Three boots are now on
// record and they differ in exactly one respect that matters: two reached $88EC
// through the first handshake and one never left $8891.  A CPU that has never
// been seen past $8894 with a SPC700 that ran a full copy means something other
// than this call drove the transfer, while a CPU seen past $8894 and back at
// $8888 again means the routine completed and was re-entered -- and a second
// entry waits for a $BBAA that only a restart of the SPC can produce.
//
// The entry count is a lower bound and is documented as one: the probe samples
// the 65816's PC every 11 mclk, one 65816 cycle is about 6 mclk, so a sighting
// that lasts a single cycle can be missed.  st_past is a range check on every
// accepted sample and carries no such caveat.
//
// The $CC bit answers the question this build exists for: the previous build
// established that the SPC700 has never advanced, so either it was shown $CC and
// did not take it, or the 65816 never sent it.  This bit distinguishes those two
// and nothing else.
//
// Each bit is justified against its register's reset value, which is the check
// that caught two broken bits in the previous build.  smp.v clears CPUI to $00
// and this bit tests for $CC, so it cannot self-set at reset and needs no arming;
// it sets only when the byte the IPL waits for actually appears.  Y likewise
// needs none, its reset value $00 being the value that means "never advanced".
// Two of the others do have to be armed before they mean anything, and getting
// that wrong is a trap worth writing down.  CPUO and the SPC's PC do not reset to
// the values the interesting question is phrased around: smp.v clears CPUO to
// $00 and addrgen.v clears PC to $0000, so a bit testing "CPUO != $AA" or
// "PC is not in the IPL" sets the instant reset releases, before the IPL has run
// at all, and reads as a confident yes for ever.  Both are therefore armed on
// first seeing the state they depart from -- CPUO at $AA, or the PC inside the
// IPL -- and only then set.  Y needs no arming because its reset value is $00,
// which is also the value meaning "never advanced", so non-zero is unambiguous.
//
// The sticky bits exist because current state cannot answer the question.  On
// the boot of core-log entry 13, CPUO still held the $AA and $BB the IPL
// publishes at $FFC9 and $FFCC and Y was still $00 -- the values a SPC700 that
// has never executed past its first publish would show -- while the 65816 was
// deep in its upload loop and had clearly advanced past the point where it first
// offers $CC.  Two readings fit: the SPC never consumed the handshake, or it
// consumed it, published its own value, and then restarted at $FFC0 and
// republished $AA and $BB.  A snapshot cannot separate 'never moved' from 'moved
// and came back'.  A bit latched from reset and never cleared can.
//
// Sampling is sound by construction: an eleven-phase revolution samples each
// field every 11 mclk, while one SPC700 cycle is about 21 mclk and the shortest
// instruction is two cycles, so no stored value can appear and vanish between
// two samples of the same field.
//
// The 65816's program counter replaces the SPC700's here because the SPC has
// been read three times and is always inside its IPL, while the gap between Y
// and CPUI port 0 was one index on the boot of core-log entry 11 and ten on the
// boot of entry 12.  A fixed protocol defect would give one number; a gap that
// moves between boots is a race or a restart, and the 65816's PC is what dates
// it.  $88EC is the CPU's echo-wait in its upload loop and $8888 is the entry to
// the routine that starts that upload, so a CPU still at $88EC has never
// restarted while a CPU back at $8888 restarted the transfer.
//
// These are live reads taken one phase apart, not one instant: the 65816's PC is
// read as three bytes because it moves, with its high byte compared on both
// sides of the low byte, while the port banks, the 65816's A and the SPC's Y are
// read once each and are only coherent because this machine is stalled rather
// than running.  A running machine would need a different instrument.
reg [3:0] link_ph = 4'd0;
reg [7:0] o0 = 8'd0, o1 = 8'd0;                  // CPUO 0 and 1
reg [7:0] i0 = 8'd0, i1 = 8'd0;                  // CPUI 0 and 1
reg [7:0] a_lo = 8'd0, a_hi = 8'd0;              // 65816 A
reg [7:0] pch1 = 8'd0, pcl = 8'd0;               // 65816 PC, high read twice
reg [7:0] y_r = 8'd0;                            // SPC700 Y
reg [7:0] sph = 8'd0;                            // SPC700 PC high byte
reg [7:0] cpu_hi = 8'd0, cpu_lo = 8'd0;          // last accepted 65816 PC
reg [18:0] link_wrap = 19'd0;
reg [79:0] fp_bus = 80'd0;
// Sticky history, latched from reset and never cleared.  A $00 in all three is
// the signature of a SPC700 that has never left its first publish.
reg       st_cpuo = 1'b0;    // CPUO port 0 has changed away from $AA
reg       st_y    = 1'b0;    // SPC700 Y has ever been non-zero
reg       st_ipl  = 1'b0;    // SPC700 PC has left the IPL since entering it
reg       st_cc   = 1'b0;    // CPUI port 0 has ever held $CC
reg       st_past = 1'b0;    // the 65816's PC has been past the first handshake
reg [2:0] cpu_ent = 3'd0;    // saturating count of VISITS to $8888 (lower bound)
reg       cpu_at_entry = 1'b0;  // the previous accepted sample was $8888
reg       arm_cpuo = 1'b0;   // CPUO has been seen at $AA
reg       arm_ipl  = 1'b0;   // the SPC's PC has been seen inside the IPL

// Case statements rather than chained ternaries, and ipl_ph -- here link_ph --
// on the right-hand side of both, because a constant on the right of
// `always @(*)` never drives at all and a phase falling off the end of a shorter
// select would silently read the wrong chip's register.
always @(*) begin
    case (link_ph)
    4'd0, 4'd1, 4'd2, 4'd3: dbg_sel = 8'h10;     // the SMP wrapper's port banks
    4'd9, 4'd10:            dbg_sel = 8'h08;     // the SPC700 core
    default:                dbg_sel = 8'h01;     // the 65816
    endcase
end
always @(*) begin
    case (link_ph)
    4'd0:    dbg_reg = 8'h04;                    // CPUO 0
    4'd1:    dbg_reg = 8'h05;                    // CPUO 1
    4'd2:    dbg_reg = 8'h00;                    // CPUI 0
    4'd3:    dbg_reg = 8'h01;                    // CPUI 1
    4'd4:    dbg_reg = 8'h00;                    // 65816 A low
    4'd5:    dbg_reg = 8'h01;                    // 65816 A high
    4'd6:    dbg_reg = 8'h07;                    // 65816 PC high, first read
    4'd7:    dbg_reg = 8'h06;                    // 65816 PC low
    4'd8:    dbg_reg = 8'h07;                    // 65816 PC high, second read
    4'd9:    dbg_reg = 8'h02;                    // SPC700 Y
    default: dbg_reg = 8'h04;                    // SPC700 PC high byte
    endcase
end

always @(posedge mclk) begin
    dbg_reg_wr <= 1'b0;
    link_ph    <= (link_ph == 4'd10) ? 4'd0 : link_ph + 4'd1;
    case (link_ph)
    4'd0: o0   <= dbg_dat_out;
    4'd1: o1   <= dbg_dat_out;
    4'd2: i0   <= dbg_dat_out;
    4'd3: i1   <= dbg_dat_out;
    4'd4: a_lo <= dbg_dat_out;
    4'd5: a_hi <= dbg_dat_out;
    4'd6: pch1 <= dbg_dat_out;
    4'd7: pcl  <= dbg_dat_out;
    4'd9: y_r  <= dbg_dat_out;
    4'd10: sph <= dbg_dat_out;
    endcase

    // Sticky history.  Each bit is tested against the register being read on
    // THIS edge, which is the same value the capture above stores, so the bit and
    // the current-state field never disagree.  Cleared only by reset: a processor
    // that ran and then restarted still sets its bits, which is the whole point.
    if (~resetn) begin
        st_cpuo  <= 1'b0;
        st_y     <= 1'b0;
        st_ipl   <= 1'b0;
        st_cc    <= 1'b0;
        st_past  <= 1'b0;
        cpu_ent  <= 3'd0;
        cpu_at_entry <= 1'b0;
        arm_cpuo <= 1'b0;
        arm_ipl  <= 1'b0;
    end else begin
        // Arm, then observe: see the state the bit departs from once, and only
        // then let a departure set it.  Without the arming both bits would set at
        // reset, since CPUO clears to $00 and the PC to $0000.
        if (link_ph == 4'd0) begin
            if (dbg_dat_out == 8'hAA) arm_cpuo <= 1'b1;
            else if (arm_cpuo)        st_cpuo  <= 1'b1;
        end
        if (link_ph == 4'd9 && dbg_dat_out != 8'h00) st_y <= 1'b1;
        // No arming: CPUI clears to $00 and this tests for $CC, so the bit is
        // clear at reset by construction and sets only on the real event.
        if (link_ph == 4'd2 && dbg_dat_out == 8'hCC) st_cc <= 1'b1;
        // PC < $FFC0 is the same test as "its high byte is not $FF", so one byte
        // is enough and the low byte is not needed for this bit.
        if (link_ph == 4'd10) begin
            if (dbg_dat_out == 8'hFF) arm_ipl <= 1'b1;
            else if (arm_ipl)         st_ipl  <= 1'b1;
        end
    end

    // The 65816's PC is accepted only when its high byte read on both sides of
    // its low byte agreed.  The second high read is compared against
    // dbg_dat_out -- the register being read on THIS edge -- not a stored copy,
    // because at this moment a register assigned from the same edge still holds
    // the previous revolution's byte and the comparison would span revolutions.
    if (link_ph == 4'd8 && pch1 == dbg_dat_out) begin
        cpu_hi <= pch1;
        cpu_lo <= pcl;

        // History on the accepted sample, so it cannot be polluted by a torn
        // pair.  Any address above $8894 means the CPU cleared the first
        // handshake at least once on this boot: $8891 is the compare and $8894
        // the branch back to it, so the first address that proves the handshake
        // was passed is the one after the branch, and the upload loop at $88EC
        // counts because it is reached only from there.  The bound is also
        // offset by the routine's own revisit behaviour -- $8905 holds a JSR
        // back into $8888 -- but any sighting below $88CC still only happens
        // after the handshake.
        if ({pch1, pcl} > 16'h8894 && {pch1, pcl} < 16'h9000)
            st_past <= 1'b1;
        // Count VISITS, not samples.  Holding $8888 for several revolutions
        // would otherwise add one per sample: the first version of this counter
        // read 7 after three visits.  cpu_at_entry remembers the previous
        // accepted sample, so only a transition into $8888 counts.
        cpu_at_entry <= ({pch1, pcl} == 16'h8888);
        if ({pch1, pcl} == 16'h8888 && ~cpu_at_entry && cpu_ent != 3'd7)
            cpu_ent <= cpu_ent + 3'd1;
    end

    // Latched display snapshot, refreshed once every 2^19 phase revolutions for
    // the reason in core-reference TCL-011: a live bus is painted as a different
    // value in every raster row and cannot be photographed.
    if (link_ph == 4'd10) begin
        link_wrap <= link_wrap + 19'd1;
        if (link_wrap == 19'd0)
            fp_bus <= {cpu_ent, st_past, st_cc, st_ipl, st_y, st_cpuo,
                       y_r, cpu_hi, cpu_lo, a_hi, a_lo, i1, i0, o1, o0};
    end
end

assign dbg_dat_in = 8'h00;
`endif

`ifdef TINYSNES_WHERE_PROBE
// Diagnostic build: where the 65816 is, and how it got there, read in one
// coherent snapshot.
//
// Two instruments disagreed and this build settles it.  TINYSNES_LINK_PROBE
// read the PC as $6C6F while TINYSNES_TRACE_PROBE read the ring frozen at
// $88EC-$88EF, the upload routine's echo-wait.  Both cannot be true, and a
// reading cannot be arbitrated from the outside because a six-byte snapshot
// leaves out the one field that says whether an address is cartridge code at
// all: the program bank.  $6C6F with PBR $00 is WRAM and expansion space, while
// $6C6F with PBR $80 would be a LoROM address whose offset is not even code.
//
// So this probe reads PC, PBR, SP and P together, guards every multi-byte read
// against a tear the way the link probe does, and adds the memory that a
// snapshot cannot carry: the first PC below $8000 the CPU was ever seen at
// after it had been above it, which is the moment it left the cartridge, and
// the newest ROM address the mapper served, which dates that moment against the
// instruction stream.
//
// Cartridge code is PC >= $8000 in this and every other LoROM layout: banks
// $00-$7D put the image at $8000-$FFFF and banks $80-$FF do the same, with
// $0000-$7FFF below that window mapped to WRAM, the system area or open bus.  So
// "left the cartridge" is exactly PC[15] == 0, and PBR only says which window it
// departed through.  Arming is required and is not incidental: PC resets to
// $0000, so an unarmed bit testing PC < $8000 would set on the first sample
// after reset and read as a confident yes for ever -- the trap TCL-013 records
// from the sticky interrupt bits.
//
// probe_bus fields, low to high:
//   [15:0]  65816 PC, high byte read on both sides of the low byte
//   [23:16] 65816 PBR, read twice and accepted only when both reads agree
//   [31:24] 65816 SP
//   [39:32] 65816 P
//   [47:40] sticky history, one bit each:
//             [40] STPExec has ever been set, so the CPU has halted
//             [41] WAIExec has ever been set, so the CPU has ever waited
//             [42] armed: an accepted sample has been at PC >= $8000
//             [43] the CPU has left the cartridge: a PC below $8000 seen while
//                  armed.  Clear means it never did, which is a result too
//             [44] PBR has ever been non-zero
//             [45] RDY_IN has ever read low, the CPU being stalled from outside
//             [46], [47] zero
//   [63:48] the first accepted PC below $8000 seen while armed -- where the CPU
//           left the cartridge.  Held, not refreshed, so it survives the CPU
//           wandering further.  Zero when bit [43] is clear
//   [79:64] ROM_ADDR[15:0] of the newest ROM access, which is the fetch the
//           departure was made from when the ring has stopped advancing
//
// P is worth reading for its own sake: bit 5 is M and bit 4 is X, and bit 3
// clear is emulation mode.  A CPU that has left the cartridge in emulation mode
// with X clear is doing something the reset path never asked of it, and a
// departure in the other mode reads differently again.
//
// Sampling.  Ten phases sample PC every 10 mclk, which is one 65816 cycle at
// about 6 mclk, and each byte is read once, so no field can change and change
// back between two samples of it.  The PC and PBR are the only multi-byte fields
// and both are tear-guarded: the PC's high byte is read before and after its low
// byte and the pair is dropped unless the two agree, and the PBR is read twice
// and dropped unless both reads agree.  A dropped PC sample skips the history
// update as well as the capture, so a torn pair can never set a sticky bit.
//
// The display snapshot is latched once every 2^19 phase revolutions for the
// reason TCL-011 records: a live bus is a different value in every raster row
// and cannot be photographed.
reg [3:0] where_ph = 4'd0;
reg [7:0] pch1 = 8'd0, pcl = 8'd0;               // 65816 PC, high read twice
reg [7:0] pbr1 = 8'd0, pbr2 = 8'd0;              // 65816 PBR, read twice
reg [7:0] sp_r = 8'd0, p_r = 8'd0;               // 65816 SP and P
reg [7:0] pc_hi = 8'd0, pc_lo = 8'd0;            // last accepted PC
reg [7:0] bank = 8'd0;                           // last accepted PBR
reg [18:0] where_wrap = 19'd0;
reg [79:0] fp_bus = 80'd0;

// Sticky history, cleared only by reset.
reg       st_halt = 1'b0;    // STPExec has ever been set
reg       st_wai  = 1'b0;    // WAIExec has ever been set
reg       st_arm  = 1'b0;    // a sample has been at PC >= $8000
reg       st_left = 1'b0;    // a PC below $8000 was seen while armed
reg       st_bank = 1'b0;    // PBR has ever been non-zero
reg       st_rdy  = 1'b0;    // RDY_IN has ever read low
reg [15:0] left_pc = 16'd0;  // the first such PC, held

// The newest ROM access, for the same reason the trace probe keeps one: the
// mapper's address is the instruction stream, and when the CPU leaves the ROM
// it stops advancing and dates the departure.
reg [15:0] wr_rom = 16'd0;
reg        wr_ce_d = 1'b1;
wire       wr_sel = enable && ~ROM_CE_N && BSRAM_CE_N;
wire [15:0] pc_now = {pch1, pcl};

// Case statements, not chained ternaries, and where_ph on the right of both, so
// this always block has sensitivity.  A constant on the right of `always @(*)`
// never drives at all, which this project has shipped once already.
always @(*) begin
    case (where_ph)
    4'd1:    dbg_reg = 8'h06;                    // PC low
    4'd2, 4'd6: dbg_reg = 8'h0D;                 // PBR, read twice
    4'd3:    dbg_reg = 8'h09;                    // SP
    4'd4:    dbg_reg = 8'h08;                    // P
    4'd5:    dbg_reg = 8'h15;                    // status byte, WAI/STP
    default: dbg_reg = 8'h07;                    // PC high (phases 0 and 7)
    endcase
end

// dbg_sel is driven from a clocked block for the reason the FIFO probe records:
// a constant on the right of a combinational always has no sensitivity and
// never drives.  Only the 65816 is read here, so it is the same value every
// phase.
always @(posedge mclk) begin
    dbg_sel    <= 8'h01;
    dbg_reg_wr <= 1'b0;
    where_ph   <= (where_ph == 4'd9) ? 4'd0 : where_ph + 4'd1;

    // The PBR is read on phases 2 and 6, with three other registers between
    // them, so a bank change in the middle is caught rather than assumed away.
    if (where_ph == 4'd0) pch1  <= dbg_dat_out;
    if (where_ph == 4'd1) pcl   <= dbg_dat_out;
    if (where_ph == 4'd2) pbr1  <= dbg_dat_out;
    if (where_ph == 4'd3) sp_r  <= dbg_dat_out;
    if (where_ph == 4'd4) p_r   <= dbg_dat_out;
    if (where_ph == 4'd6) pbr2  <= dbg_dat_out;

    if (~resetn) begin
        st_halt <= 1'b0;
        st_wai  <= 1'b0;
        st_arm  <= 1'b0;
        st_left <= 1'b0;
        st_bank <= 1'b0;
        st_rdy  <= 1'b0;
        left_pc <= 16'd0;
    end else begin
        // Halt and wait are single-byte reads of a register that only latches,
        // so no guard is needed; RDY_IN is live and is latched the same way.
        if (where_ph == 4'd5) begin
            if (dbg_dat_out[0]) st_halt <= 1'b1;
            if (dbg_dat_out[1]) st_wai  <= 1'b1;
            if (~dbg_dat_out[3]) st_rdy <= 1'b1;
        end

        // Phase 7 re-reads the PC high byte, so the accept and the history both
        // happen there: pch1 was captured on phase 0 and pcl on phase 1, and
        // the byte arriving on this edge is the third read of the same field.
        if (where_ph == 4'd7 && pch1 == dbg_dat_out) begin
            pc_hi <= pch1;
            pc_lo <= pcl;
            // The PBR accepted with this PC is the one whose two reads agreed,
            // which is what makes the bank and the PC describe one moment.
            if (pbr1 == pbr2) begin
                bank   <= pbr1;
                if (pbr1 != 8'h00) st_bank <= 1'b1;
            end

            if (pc_now >= 16'h8000) begin
                st_arm <= 1'b1;
            end else if (st_arm && ~st_left) begin
                // The first departure only: later samples are further from the
                // cartridge and would overwrite the address that dates it.
                st_left <= 1'b1;
                left_pc <= pc_now;
            end
        end
    end

    wr_ce_d <= wr_sel;    // start-of-access edge, not the held level
    if (wr_sel && ~wr_ce_d)
        wr_rom <= ROM_ADDR[15:0];

    if (where_ph == 4'd9) begin
        where_wrap <= where_wrap + 19'd1;
        if (where_wrap == 19'd0)
            fp_bus <= {wr_rom, left_pc,
                       2'b00, st_rdy, st_bank, st_left, st_arm, st_wai, st_halt,
                       p_r, sp_r, bank, pc_hi, pc_lo};
    end
end

assign dbg_dat_in = 8'h00;
`endif

`ifdef TINYSNES_JUMP_PROBE
// Diagnostic build: catch the fetches that precede the departure.
//
// TINYSNES_WHERE_PROBE established that the 65816 leaves the cartridge on most
// boots, and held the address it departed from -- $1035, $1036, $3D89 and $1101
// over four boots of five (core-log entry 31).  That address is where it
// landed, not what sent it: an indirect jump through a bad pointer, a return
// through a corrupted stack, and a vector fetched from open bus all produce a
// departure and are indistinguishable from the landing address alone.  What
// separates them is the instruction stream immediately before it, because a
// jump fetches its opcode and its operand bytes from ROM while a return fetches
// only the opcode -- the stacked bytes it reads are WRAM reads and never appear
// in this ring.  So the number of consecutive fetches before the departure, and
// the bytes at them, name the instruction.
//
// This probe therefore keeps a three-deep ring of ROM addresses and, at the
// instant the CPU is first seen below $8000 after having been above it, freezes
// the ring into held registers beside the departure PC and the program bank it
// was reading through.  Everything is captured on the single edge that accepts
// the PC, so the ring and the PC describe the same moment rather than two
// samples of a machine that moves between them.
//
// probe_bus fields, low to high:
//   [15:0]  the first PC below $8000 seen after arming -- where it landed
//   [23:16] ROM_ADDR[23:16] of the newest fetch at the departure
//   [39:24] ROM_ADDR[15:0] of the newest fetch at the departure
//   [55:40] ROM_ADDR[15:0] of the fetch before that
//   [71:56] ROM_ADDR[15:0] of the fetch before that one
//   [79:72] the 65816's PBR at the departure, or $FF if its two reads disagreed
//
// The three ROM addresses share one bank byte because consecutive instruction
// bytes cannot cross a bank boundary in a LoROM image except at $FFxx, and a
// departure that did cross one would still be named by the newest address.
//
// The departure is detected exactly as TINYSNES_WHERE_PROBE detects it, and for
// the reason EXT-009 records: cartridge is mapped only at $8000-$FFFF, so a PC
// below $8000 is outside the image in every bank.  The test is armed at a PC of
// $8000 or above before it may fire, because PC resets to $0000 and an unarmed
// bit would fire at reset and read yes for ever (TCL-013).
//
// Sampling: seven phases sample the PC every 7 mclk against one 65816 cycle of
// about 6, and every multi-byte field is tear-guarded.  The PC's high byte is
// read on both sides of its low byte and the pair is dropped unless the two
// reads agree; the PBR is read twice with two other registers between the reads
// and is reported as $FF when they disagree.  A dropped PC pair cannot arm the
// bit, so a torn sample can never fake a departure.
reg [2:0] jp_ph = 3'd0;
reg [7:0] pch1 = 8'd0, pcl = 8'd0;      // PC, high read on both sides of low
reg [7:0] pbr1 = 8'd0, pbr2 = 8'd0;     // PBR, read twice, not adjacently
reg [7:0] sp_r = 8'd0;                  // SP, sampled to keep the phase count up

// The live ring, advanced on the start of every ROM access.  jp_ce_d holds the
// previous level so this is a real start-of-access edge; testing the level
// instead would overwrite the ring every cycle ROMSEL is held and leave three
// copies of one address.
reg [15:0] r0 = 16'd0, r1 = 16'd0, r2 = 16'd0;
reg [7:0]  r_bank = 8'd0;
reg        jp_ce_d = 1'b1;
wire       jp_sel = enable && ~ROM_CE_N && BSRAM_CE_N;

// The frozen copy: written once, on the departure edge, and then left alone, so
// a CPU that wanders back into the cartridge cannot overwrite what took it out.
reg        jp_arm  = 1'b0;   // a sample has been at PC >= $8000
reg        jp_done = 1'b0;   // a departure has been recorded and frozen
reg [15:0] d_pc = 16'd0;
reg [15:0] d_r0 = 16'd0, d_r1 = 16'd0, d_r2 = 16'd0;
reg [7:0]  d_rbank = 8'd0, d_pbr = 8'd0;
reg [18:0] jp_wrap = 19'd0;
reg [79:0] fp_bus = 80'd0;

// Case, not chained ternaries, and jp_ph on the right-hand side, so the block
// has sensitivity: a constant on the right of `always @(*)` never drives.
always @(*) begin
    case (jp_ph)
    3'd0, 3'd5: dbg_reg = 8'h07;        // PC high, first read and second read
    3'd1:       dbg_reg = 8'h06;        // PC low
    3'd2, 3'd4: dbg_reg = 8'h0D;        // PBR, read twice
    3'd3:       dbg_reg = 8'h09;        // SP
    default:    dbg_reg = 8'h07;        // parked on PC high
    endcase
end

always @(posedge mclk) begin
    dbg_sel    <= 8'h01;                // the 65816, every phase
    dbg_reg_wr <= 1'b0;
    jp_ph      <= (jp_ph == 3'd6) ? 3'd0 : jp_ph + 3'd1;

    if (jp_ph == 3'd0) pch1 <= dbg_dat_out;
    if (jp_ph == 3'd1) pcl  <= dbg_dat_out;
    if (jp_ph == 3'd2) pbr1 <= dbg_dat_out;
    if (jp_ph == 3'd3) sp_r <= dbg_dat_out;
    if (jp_ph == 3'd4) pbr2 <= dbg_dat_out;

    jp_ce_d <= jp_sel;                  // start-of-access edge, not the level
    if (jp_sel && ~jp_ce_d) begin
        r2     <= r1;
        r1     <= r0;
        r0     <= ROM_ADDR[15:0];
        r_bank <= ROM_ADDR[23:16];
    end

    if (~resetn) begin
        jp_arm  <= 1'b0;
        jp_done <= 1'b0;
    end else if (jp_ph == 3'd5 && pch1 == dbg_dat_out) begin
        // The accept point: pch1 arrived on phase 0, pcl on phase 1, and the
        // byte arriving on this edge is the second read of PC high.
        if ({pch1, pcl} >= 16'h8000) begin
            jp_arm <= 1'b1;
        end else if (jp_arm && ~jp_done) begin
            jp_done <= 1'b1;
            d_pc    <= {pch1, pcl};
            // Read at this edge, so r0 is the newest fetch committed before the
            // departure and the ring describes the same instant as the PC.
            d_r0    <= r0;
            d_r1    <= r1;
            d_r2    <= r2;
            d_rbank <= r_bank;
            d_pbr   <= (pbr1 == pbr2) ? pbr1 : 8'hFF;
        end
    end

    if (jp_ph == 3'd6) begin
        jp_wrap <= jp_wrap + 19'd1;
        if (jp_wrap == 19'd0)
            fp_bus <= {d_pbr, d_r2, d_r1, d_r0, d_rbank, d_pc};
    end
end

assign dbg_dat_in = 8'h00;
`endif

`ifdef TINYSNES_IPL_PROBE
// Diagnostic build: catch the address the IPL jumps to.  Decoded from the
// IPLROM in smp.v, the path after the $CC handshake is
//
//   $FFEF  MOVW YA,$F6      A = CPUI[2], Y = CPUI[3]
//   $FFF1  MOVW $00,YA      ARAM[$0000] = CPUI[2], ARAM[$0001] = CPUI[3]
//   $FFF3  MOVW YA,$F4      A = CPUI[0], Y = CPUI[1]
//   $FFF5  MOV $F4,A        CPUO[0] = echo of CPUI[0]
//   $FFF8  MOV X,A          X = CPUI[1]
//   $FFFB  JMP [$0000+X]    jump to ARAM[$0000]+X
//
// so the jump target is the transfer address the 65816 wrote to $2142/$2143,
// plus CPUI[1] in X.  The first program counter outside $FFC0-$FFFF *is* that
// target, which means the answer needs no ARAM access at all -- there is no
// debug path to ARAM, and none is required.  Latching that first out-of-range PC
// together with A and X and the three CPUI bytes says in one frame whether the
// SPC jumped where the 65816 told it to.
//
// Sampling rate: one SPC cycle is about 21 mclk (21.505 MHz against 1.024) and
// the shortest instruction is two cycles, so PC cannot change more often than
// every ~42 mclk.  A nine-phase revolution samples PC every 9 mclk, at least
// four times per instruction, so the jump cannot be missed.  A and X are read
// within 2 mclk of the exit, which is inside the same instruction for the same
// reason, so they are the values the jump used.
//
// probe_bus fields, low to high:
//   [15:0]  PC at the first sample outside $FFC0-$FFFF -- the jump target
//   [31:16] the SPC700's live Y above its live A
//   [47:32] the current SPC700 PC, refreshed every latch
//   [63:48] CPUI ports 3 and 2, the transfer address the 65816 sent
//   [79:64] CPUI ports 1 and 0, of which port 1 becomes X above
// A jump target of $0000, or one inside $00F0-$00FF, would land in the port or
// timer bank where no code can run; a target that merely holds the wrong bytes
// moves the fault into the upload itself.
//
// Y is why this probe exists in its present form.  On hardware the exit latch
// never fired -- the SPC700 sat at $FFDA-$FFEA, inside the IPL's own block-copy
// loop -- so the address a jump would have used is not the question yet.  That
// loop is entered at $FFDA and turns entirely on its compare:
//
//   $FFDA  MOV $F4,A        echo A back to the 65816
//   $FFDC  CMP Y,$F4        wait until the CPU has consumed it
//   $FFDE  BNE $FFDC
//   $FFE0  MOV A,$F5        next data byte from CPUI[1]
//   $FFE2  MOV $F4,Y        publish Y as the index
//   $FFE4  MOV $F5,A
//   $FFE5  ADC Y,#$01       advance the index
//   $FFE7  MOV Y,A
//   $FFE8  CMP Y,#$10
//   $FFEA  BNE $FFDA        until 16 bytes have moved
//
// So Y and CPUI port 0 are the two halves of that compare, and their relation
// says which way the upload has failed: Y held at the index CPUI already shows
// puts the fault in the echo path, Y below it means bytes are being dropped as
// they are stored, and Y above it means the SPC has run ahead of the CPU.
reg [3:0] ipl_ph = 4'd0;
reg [7:0] pch1 = 8'd0, pcl = 8'd0;
reg [7:0] a_r = 8'd0, x_r = 8'd0, y_r = 8'd0;
reg [7:0] i0 = 8'd0, i1 = 8'd0, i2 = 8'd0, i3 = 8'd0;
reg [15:0] exit_pc = 16'd0;
reg [15:0] cur_pc = 16'd0;
reg        in_ipl = 1'b0;         // the IPL range has been seen at least once
reg        exit_seen = 1'b0;      // latched once and never rewritten
reg [18:0] ipl_wrap = 19'd0;
reg [79:0] fp_bus = 80'd0;

// Case statements, not chained ternaries: a phase that fell off the end of a
// shorter select would silently read the wrong chip's register, and a constant
// on the right of `always @(*)` never drives at all.  ipl_ph is on the right-hand
// side of both, so both blocks have sensitivity.
always @(*) begin
    case (ipl_ph)
    4'd0, 4'd1, 4'd2, 4'd3, 4'd4: dbg_sel = 8'h08;   // the SPC700 core
    4'd9:                         dbg_sel = 8'h08;   // the SPC700 core, live Y
    default:                      dbg_sel = 8'h10;   // the SMP wrapper's ports
    endcase
end
always @(*) begin
    case (ipl_ph)
    4'd0:    dbg_reg = 8'h04;                    // PC high, first read
    4'd1:    dbg_reg = 8'h03;                    // PC low
    4'd2:    dbg_reg = 8'h04;                    // PC high, second read
    4'd3:    dbg_reg = 8'h00;                    // SPC700 A
    4'd4:    dbg_reg = 8'h01;                    // SPC700 X
    4'd5:    dbg_reg = 8'h00;                    // CPUI 0
    4'd6:    dbg_reg = 8'h01;                    // CPUI 1
    4'd7:    dbg_reg = 8'h02;                    // CPUI 2
    4'd8:    dbg_reg = 8'h03;                    // CPUI 3
    default: dbg_reg = 8'h02;                    // SPC700 Y
    endcase
end

always @(posedge mclk) begin
    dbg_reg_wr <= 1'b0;
    ipl_ph     <= (ipl_ph == 4'd9) ? 4'd0 : ipl_ph + 4'd1;
    case (ipl_ph)
    4'd0: pch1 <= dbg_dat_out;
    4'd1: pcl  <= dbg_dat_out;
    4'd3: a_r  <= dbg_dat_out;
    4'd4: x_r  <= dbg_dat_out;   // captured but not displayed: X is the IPL's
                                 // own scratch, set from CPUI[1] at $FFF8, and
                                 // there is no spare stripe for it this cycle
    4'd5: i0   <= dbg_dat_out;
    4'd6: i1   <= dbg_dat_out;
    4'd7: i2   <= dbg_dat_out;
    4'd8: i3   <= dbg_dat_out;
    4'd9: y_r  <= dbg_dat_out;
    endcase

    // The PC pair is accepted only when the high byte read on both sides of the
    // low byte agreed, so a jump between the two reads is rejected rather than
    // assembled into an address the SPC was never at.  The second high read is
    // compared against dbg_dat_out -- the register being read on THIS edge -- not
    // against a stored copy: at the moment ipl_ph is 2, a register assigned from
    // the same edge still holds the PREVIOUS revolution's byte, so comparing the
    // two registers compares across revolutions and a real tear slips through.
    // The APU probe already carries this fix; it was not carried over here, and
    // the bench below is what caught it.
    if (ipl_ph == 4'd2 && pch1 == dbg_dat_out) begin
        cur_pc <= {pch1, pcl};
        if ({pch1, pcl} >= 16'hFFC0)
            in_ipl <= 1'b1;
        // The first PC below the IPL, once the IPL has been seen, is the address
        // the IPL's JMP arrived at.  Latched once: a machine that later wanders
        // must not overwrite the evidence.
        if (in_ipl && {pch1, pcl} < 16'hFFC0 && ~exit_seen) begin
            exit_pc   <= {pch1, pcl};
            exit_seen <= 1'b1;
        end
    end

    // Latched display snapshot, refreshed once every 2^19 phase revolutions for
    // the reason in core-reference TCL-011: a live bus cannot be photographed.
    if (ipl_ph == 4'd9) begin
        ipl_wrap <= ipl_wrap + 19'd1;
        if (ipl_wrap == 19'd0)
            fp_bus <= {i1, i0, i3, i2, cur_pc, y_r, a_r, exit_pc};
    end
end

assign dbg_dat_in = 8'h00;
`endif

`ifdef TINYSNES_TRACE_PROBE
// Diagnostic build: keep the last four ROM addresses the CPU asked for.  The
// ring only advances on a ROM access, so on a machine that has left the ROM it
// freezes on exactly the fetches before the jump, and the newest address names
// the instruction that did it -- which the loaded image can then be
// disassembled at, because LoROM bank 0 is the image offset directly.
//
// probe_bus fields, low to high:
//   [15:0]  ROM_ADDR[15:0] of the newest access
//   [31:16] the access before it
//   [47:32] the one before that
//   [63:48] the one before that
//   [79:64] ROM_ADDR[23:8] of the newest, so the whole image offset is visible
//           across stripes 1 and 5 for a ROM up to 1 MiB
// Assertions of ROMSEL that are really SRAM or OBC1 are excluded, because their
// addresses come from the same mapper but are not code fetches and would read as
// plausible ROM addresses in the trace.
reg [15:0] tr0 = 16'd0, tr1 = 16'd0, tr2 = 16'd0, tr3 = 16'd0;
reg [15:0] tr_hi = 16'd0;
reg        tr_ce_d = 1'b1;
reg        rom_recent = 1'b0;           // a ROM access inside the last window
reg [21:0] tr_tick = 22'd0;
reg [79:0] fp_bus = 80'd0;
wire       tr_sel = enable && ~ROM_CE_N && BSRAM_CE_N;

always @(posedge mclk) begin
    // tr_ce_d holds the previous level, so this is a real start-of-access edge;
    // storing the inverted level would shift the ring every cycle ROMSEL is held.
    tr_ce_d <= tr_sel;
    if (tr_sel && ~tr_ce_d) begin
        tr3   <= tr2;
        tr2   <= tr1;
        tr1   <= tr0;
        tr0   <= ROM_ADDR[15:0];
        tr_hi <= ROM_ADDR[23:8];
        rom_recent <= 1'b1;
    end

    // The band's first bit reports a ROM access inside the last 0.2 s window, so
    // a machine that has stopped fetching shows it dark without spending a
    // stripe on the counter.
    tr_tick <= tr_tick + 22'd1;
    if (tr_tick == 22'h3F_FFFF)
        rom_recent <= 1'b0;

    fp_bus <= {tr_hi, tr3, tr2, tr1, tr0};
end
`endif

wire sysclkf_ce, sysclkr_ce;
wire overlay;

`ifdef CHIP_DSPn
parameter USE_DSPn=1;
`else
parameter USE_DSPn=0;
`endif
`ifdef CHIP_GSU
parameter USE_GSU=1;
`else
parameter USE_GSU=0;
`endif

// `ifdef VERILATOR
// parameter USE_DSPn=1;
// parameter USE_GSU=1;
// `endif

`ifndef DISABLE_SNES
main #(.USE_DSPn(USE_DSPn), .USE_GSU(USE_GSU)) main (
    .MCLK(mclk), .RESET_N(resetn & ~loading), .ENABLE(enable), 
    .SYSCLKF_CE(sysclkf_ce), .SYSCLKR_CE(sysclkr_ce), .REFRESH(refresh),

    .ROM_TYPE(rom_type), .ROM_MASK(rom_mask), .RAM_MASK(ram_mask),

    .ROM_ADDR(ROM_ADDR), .ROM_D(ROM_D), .ROM_Q(ROM_Q),
    .ROM_CE_N(ROM_CE_N), .ROM_OE_N(ROM_OE_N), .ROM_WE_N(ROM_WE_N),
    .ROM_WORD(ROM_WORD),

    .BSRAM_ADDR(BSRAM_ADDR), .BSRAM_D(BSRAM_D),	.BSRAM_Q(BSRAM_Q),
    .BSRAM_CE_N(BSRAM_CE_N), .BSRAM_OE_N(BSRAM_OE_N), .BSRAM_WE_N(BSRAM_WE_N),
    .BSRAM_RD_N(BSRAM_RD_N),

    .WRAM_ADDR(WRAM_ADDR), .WRAM_D(WRAM_D),	.WRAM_Q(WRAM_SD_Q),
    .WRAM_CE_N(WRAM_CE_N), .WRAM_OE_N(WRAM_OE_N), .WRAM_WE_N(WRAM_WE_N),
    .WRAM_RD_N(WRAM_RD_N),

    .VRAM1_ADDR(VRAM1_ADDR), .VRAM1_DI(VRAM1_Q), .VRAM1_DO(VRAM1_D),
    .VRAM1_WE_N(VRAM1_WE_N), .VRAM2_ADDR(VRAM2_ADDR), .VRAM2_DI(VRAM2_Q),
    .VRAM2_DO(VRAM2_D), .VRAM2_WE_N(VRAM2_WE_N), .VRAM_OE_N(VRAM_OE_N),

    .ARAM_ADDR(ARAM_ADDR), .ARAM_Q(ARAM_Q), .ARAM_D(ARAM_D), 
    .ARAM_CE_N(ARAM_CE_N), .ARAM_OE_N(ARAM_OE_N), .ARAM_WE_N(ARAM_WE_N),

    .BLEND(BLEND), .PAL(PAL), .HIGH_RES(), .FIELD(), .INTERLACE(), .DIS_SHORTLINE(),
    .DOTCLK(dotclk), .RGB_OUT(rgb_out), .HBLANKn(hblankn),
    .VBLANKn(vblankn), .X_OUT(x_out), .Y_OUT(y_out),

    .JOY1_DI(overlay?2'b11:snes_joy1_di), .JOY2_DI(overlay?2'b11:snes_joy2_di), .JOY_STRB(snes_joy_strb), 
    .JOY1_CLK(snes_joy1_clk), .JOY2_CLK(snes_joy2_clk), 

    .AUDIO_L(audio_l), .AUDIO_R(audio_r), .AUDIO_READY(audio_ready), .AUDIO_EN(audio_en),

    .JOY1_P6(), .JOY2_P6(), .JOY2_P6_in(), .DOT_CLK_CE(DOT_CLK_CE), .EXT_RTC(),
    .SPC_MODE(), .IO_ADDR(), .IO_DAT(), .IO_WR(), 

    .DBG_SEL(dbg_sel), .DBG_REG(dbg_reg), .DBG_REG_WR(dbg_reg_wr), .DBG_DAT_IN(dbg_dat_in), 
    .DBG_DAT_OUT(dbg_dat_out), .DBG_BREAK(dbg_break)
);
`endif

// SDRAM for SNES ROM, WRAM and ARAM
wire [15:0] cpu_port0;
wire [15:0] cpu_port1;
reg         cpu_port;

reg         cpu_req;
reg  [1:0]  cpu_ds;
reg [15:0]  cpu_din;
reg [22:0]  cpu_addr; 
reg         cpu_we;

wire [22:0] rom_addr = loading ? loader_addr : ROM_ADDR[22:0];
reg [22:0]  rom_addr_sd;

reg [16:0]  wram_addr_sd;
reg         wram_wr_r, wram_rd_r;

reg         bsram_req, bsram_we;
reg [19:0]  bsram_addr;
reg [7:0]   bsram_din;
wire [7:0]  bsram_dout;
wire        bsram_rd = ~BSRAM_CE_N & (~BSRAM_RD_N || rom_type[7:4] == 4'hC);
wire        bsram_wr = ~BSRAM_CE_N & ~BSRAM_WE_N;
reg         bsram_rd_r, bsram_wr_r;

wire        aram_rd = ~ARAM_CE_N & ~ARAM_OE_N;
wire        aram_wr = ~ARAM_CE_N & ~ARAM_WE_N;
reg [15:0]  aram_addr_sd;
reg         aram_rd_r, aram_wr_r;
reg         aram_req;

wire        DOT_CLK_CE;
assign      O_sdram_clk = fclk_p;

// Generate SDRAM signals
always @(posedge mclk) begin
    if (~resetn) begin
    end else begin
        
        // ROM read and load
        if (loading && loader_do_valid && header_finished && loader_addr[0] 
            || ~loading && ~ROM_CE_N && rom_addr_sd != rom_addr) begin
            rom_addr_sd <= rom_addr;
            cpu_addr <= rom_addr;
            cpu_req <= ~cpu_req;
            cpu_we <= loading;
            cpu_din <= {loader_do, loader_do_r};    // write 16 bits on odd addresses
            cpu_ds <= 2'b11;
            cpu_port <= 0;
        end
        
        // WRAM read/write
        wram_rd_r <= wram_rd; wram_wr_r <= wram_wr;
        if ((wram_rd && WRAM_ADDR[16:1] != wram_addr_sd[16:1]) || (wram_rd & ~wram_rd_r) || (wram_wr & ~wram_wr_r)) begin
            wram_addr_sd <= WRAM_ADDR;
            cpu_req <= ~cpu_req;
            cpu_addr <= {6'b111_111, WRAM_ADDR[16:0]};  // 7E,7F:0000-FFFF, total 128KB
            cpu_we <= wram_wr;
            cpu_ds <= {WRAM_ADDR[0], ~WRAM_ADDR[0]};
            cpu_din <= {WRAM_D, WRAM_D};        
            cpu_port <= 1;
        end 

        // BSRAM read/write
        bsram_rd_r <= bsram_rd; bsram_wr_r <= bsram_wr;
        if (bsram_rd && BSRAM_ADDR != bsram_addr || (bsram_wr & ~bsram_wr_r) || (bsram_rd & ~bsram_rd_r)) begin
            bsram_addr <= BSRAM_ADDR;
            bsram_req <= ~bsram_req;
            bsram_din <= BSRAM_D;
        end

        // ARAM read/write
        aram_rd_r <= aram_rd; aram_wr_r <= aram_wr;
        if (aram_rd && aram_addr_sd != ARAM_ADDR || (aram_wr && aram_addr_sd != ARAM_ADDR) || (aram_rd & ~aram_rd_r) || (aram_wr & ~aram_wr_r)) begin
            aram_req <= ~aram_req;
            aram_addr_sd <= ARAM_ADDR;
        end
    end
end

localparam RV_IDLE_REQ0 = 3'd0;
localparam RV_WAIT0_REQ1 = 3'd1;
localparam RV_DATA0 = 3'd2;
localparam RV_WAIT1 = 3'd3;
localparam RV_DATA1 = 3'd4;
reg [2:0]   rvst;

wire        rv_valid;
reg         rv_ready;
wire [22:0] rv_addr;
wire [31:0] rv_wdata;
wire [3:0]  rv_wstrb;
reg  [15:0] rv_dout0;
wire [31:0] rv_rdata = {rv_dout, rv_dout0};
reg         rv_valid_r;
reg         rv_word;           // which word
reg         rv_req;
wire        rv_req_ack;
wire [15:0] rv_dout;
reg [1:0]   rv_ds;
reg         rv_new_req;

reg [14:0] vram1_addr_sd, vram2_addr_sd;
reg vram1_we_n_old, vram2_we_n_old;
reg vram1_req /* synthesis syn_keep=1 */; 
reg vram2_req /* synthesis syn_keep=1 */;
reg [7:0] vram1_din, vram2_din;

always @(posedge mclk) begin
    vram1_we_n_old <= VRAM1_WE_N;
    if ((~VRAM1_WE_N & vram1_we_n_old) || (VRAM1_ADDR[14:0] != vram1_addr_sd && ~VRAM_OE_N)) begin
        vram1_addr_sd <= VRAM1_ADDR[14:0];
        vram1_din <= VRAM1_D;
        vram1_req <= ~vram1_req;
    end

    vram2_we_n_old <= VRAM2_WE_N;
    if ((~VRAM2_WE_N & vram2_we_n_old) || (VRAM2_ADDR[14:0] != vram2_addr_sd && ~VRAM_OE_N)) begin
        vram2_addr_sd <= VRAM2_ADDR[14:0];
        vram2_din <= VRAM2_D;
        vram2_req <= ~vram2_req;
    end
end

`ifdef TINYSNES_WRAM_TEST
// Diagnostic build: WRAM self-test.  Declared before the controller instance so
// the widths are stated rather than inferred from the port.
wire [16:0] wram_bist_addr;
wire  [7:0] wram_bist_din;
wire [23:0] wram_bist_cpu_addr;
wire  [1:0] wram_bist_ds;
wire        wram_bist_we, wram_bist_req, wram_bist_ack;
wire [15:0] wram_bist_mask;
wire  [1:0] wram_bist_status;
wire  [2:0] wram_bist_dbg = wram_bist_status == 2'd1 ? 3'b010 :   // done, all bits correct
                            wram_bist_status == 2'd2 ? 3'b100 :   // done, mismatch
                            wram_bist_status == 2'd3 ? 3'b110 :   // no acknowledge
                                                      3'b001;   // running
`endif

`ifdef TINYSNES_READ_STABILITY
// Diagnostic build: ROM read-stability test.  Declared before the controller
// instance that connects them so the widths are stated rather than inferred.
wire [21:0] stability_addr;
wire        stability_req, stability_ack, stability_done;
wire [15:0] stability_mism;
wire  [1:0] stability_status;
wire  [2:0] stability_dbg = stability_status == 2'd1 ? 3'b010 :   // done, no mismatch
                            stability_status == 2'd2 ? 3'b100 :   // done, mismatches
                            stability_status == 2'd3 ? 3'b110 :   // no acknowledge
                                                      3'b001;   // running
`endif

`ifdef TINYSNES_ARAM_TEST
// Diagnostic build: ARAM self-test through the port the SPC700 loads through.
// Same 16-bar display and status band as TINYSNES_SDRAM_TEST, so one decoder
// reads both.  See fpga/snes/src/aram_bist.v.  Bits 0-7 are the even-lane byte
// and bits 8-15 the odd-lane byte, red where that bit mismatched.  Declared
// before the controller instance that connects them: an undeclared identifier
// in a port connection becomes an implicit net whose width is taken from the
// port, which would work by luck for the wide ports and not at all for the
// concatenated data port, so the widths are stated here instead.
wire [15:0] aram_bist_addr;
wire  [7:0] aram_bist_din;
wire        aram_bist_we, aram_bist_req, aram_bist_ack;
wire [15:0] aram_bist_mask;
wire  [1:0] aram_bist_status;
wire  [2:0] aram_bist_dbg = aram_bist_status == 2'd1 ? 3'b010 :   // done, all bits correct
                            aram_bist_status == 2'd2 ? 3'b100 :   // done, mismatch
                            aram_bist_status == 2'd3 ? 3'b110 :   // no acknowledge
                                                      3'b001;   // running
`endif

sdram_snes sdram(
    .clk(fclk), .mclk(mclk), .clkref(DOT_CLK_CE), .resetn(resetn), .busy(sdram_busy),

    // SDRAM pins
    .SDRAM_DQ(IO_sdram_dq), .SDRAM_A(O_sdram_addr), .SDRAM_BA(O_sdram_ba), 
    .SDRAM_nCS(O_sdram_cs_n), .SDRAM_nWE(O_sdram_wen_n), .SDRAM_nRAS(O_sdram_ras_n), 
    .SDRAM_nCAS(O_sdram_cas_n), .SDRAM_CKE(O_sdram_cke), .SDRAM_DQM(O_sdram_dqm), 

    // CPU accesses
`ifdef TINYSNES_ROM_CHECK
    // Diagnostic build: the probe reads the ROM words back before the machine
    // starts; after `rom_probe_done` it stops driving and the machine takes over.
    // The machine owns the port until the loader releases `loaded`, the probe
    // owns it from then until it finishes, then the machine gets it back.  The
    // first version of this mux handed the port to the probe from reset, which
    // disconnected the loader's writes: the probe then read an SDRAM that had
    // never been written and every word mismatched.
    .cpu_addr((loaded && ~rom_probe_done) ? rom_probe_addr : cpu_addr[22:1]),
    .cpu_din ((loaded && ~rom_probe_done) ? 16'd0 : cpu_din),
    .cpu_port((loaded && ~rom_probe_done) ? 1'b0 : cpu_port),
    .cpu_port0(cpu_port0), .cpu_port1(cpu_port1),
    .cpu_req ((loaded && ~rom_probe_done) ? rom_probe_req : cpu_req),
    .cpu_req_ack(rom_probe_ack),
    .cpu_we  ((loaded && ~rom_probe_done) ? 1'b0 : cpu_we),
    .cpu_ds  ((loaded && ~rom_probe_done) ? 2'b11 : cpu_ds),
`elsif TINYSNES_WRAM_TEST
    // Diagnostic build: wram_bist owns the CPU port; the machine's requests are
    // left unconnected because no ROM is loaded and the SNES is never enabled.
    // WRAM is addressed at {6'b111_111, WRAM_ADDR[16:0]} in SDRAM, which is the
    // same mapping snestang_top uses for the machine's own WRAM accesses, so the
    // test exercises the real path rather than a private one.
    .cpu_addr(wram_bist_cpu_addr[22:1]), .cpu_din({wram_bist_din, wram_bist_din}),
    .cpu_port(1'b1),
    .cpu_port0(cpu_port0), .cpu_port1(cpu_port1),
    .cpu_req(wram_bist_req), .cpu_req_ack(wram_bist_ack),
    .cpu_we(wram_bist_we), .cpu_ds(wram_bist_ds),
`elsif TINYSNES_READ_STABILITY
    // Diagnostic build: the stability test owns the CPU port from `loaded` until
    // it is done, then hands it back to the machine.  The mux is on the same
    // `loaded && ~done` shape as the ROM check, because handing the port to a
    // probe from reset disconnects the loader's writes -- a defect this project
    // has already shipped once.
    .cpu_addr((loaded && ~stability_done) ? stability_addr : cpu_addr[22:1]),
    .cpu_din ((loaded && ~stability_done) ? 16'd0 : cpu_din),
    // cpu_port selects which read-data register the controller writes: port 0
    // for the test, the machine's own choice once it has the port back.  Tying
    // it high would send every test read into cpu_port1, which nothing reads.
    .cpu_port((loaded && ~stability_done) ? 1'b0 : cpu_port),
    .cpu_port0(cpu_port0), .cpu_port1(cpu_port1),
    .cpu_req ((loaded && ~stability_done) ? stability_req : cpu_req),
    .cpu_req_ack(stability_ack),
    .cpu_we  ((loaded && ~stability_done) ? 1'b0 : cpu_we),
    .cpu_ds  ((loaded && ~stability_done) ? 2'b11 : cpu_ds),
`elsif TINYSNES_SDRAM_TEST
    // Diagnostic build: sdram_bist owns the CPU port; the machine's requests are
    // left unconnected because no ROM is loaded and the SNES is never enabled.
    .cpu_addr(bist_addr), .cpu_din(bist_din), .cpu_port(1'b0),
    .cpu_port0(cpu_port0), .cpu_port1(cpu_port1), .cpu_req(bist_req), .cpu_req_ack(bist_ack),
    .cpu_we(bist_we), .cpu_ds(2'b11),
`else
    .cpu_addr(cpu_addr[22:1]), .cpu_din(cpu_din), .cpu_port(cpu_port), 
    .cpu_port0(cpu_port0), .cpu_port1(cpu_port1), .cpu_req(cpu_req), .cpu_req_ack(),
    .cpu_we(cpu_we), .cpu_ds(cpu_ds),
`endif

    // BSRAM accesses
    .bsram_addr(bsram_addr), .bsram_dout(bsram_dout), .bsram_din(bsram_din),
    .bsram_req(bsram_req), .bsram_req_ack(), .bsram_we(bsram_wr),

    // ARAM accesses
`ifdef TINYSNES_ARAM_TEST
    // Diagnostic build: aram_bist owns the ARAM port; the machine's ARAM
    // requests are left unconnected because no ROM is loaded and the SNES is
    // never enabled.
    .aram_16(1'b0), .aram_addr(aram_bist_addr), .aram_din({aram_bist_din, aram_bist_din}),
    .aram_dout(aram_dout), .aram_req(aram_bist_req), .aram_req_ack(aram_bist_ack),
    .aram_we(aram_bist_we),
`else
    .aram_16(aram_16), .aram_addr(ARAM_ADDR), .aram_din({ARAM_D, ARAM_D}), 
    .aram_dout(aram_dout), .aram_req(aram_req), .aram_req_ack(), .aram_we(aram_wr),
`endif

`ifdef SDRAM_3CH
    // VRAM accesses
    .vram1_addr(vram1_addr_sd), .vram1_req(vram1_req), .vram1_ack(), 
    .vram1_we(~vram1_we_n_old), .vram1_din(vram1_din), .vram1_dout(VRAM1_Q), 
    .vram2_addr(vram2_addr_sd), .vram2_req(vram2_req), .vram2_ack(),
    .vram2_we(~vram2_we_n_old),  .vram2_din(vram2_din), .vram2_dout(VRAM2_Q),
`endif

`ifdef MCU_BL616
    .rv_addr(), .rv_din(), 
    .rv_ds(), .rv_dout(), .rv_req(), .rv_req_ack(), .rv_we()
`else
    // IOSys risc-v softcore
    .rv_addr({rv_addr[22:2], rv_word}), .rv_din(rv_word ? rv_wdata[31:16] : rv_wdata[15:0]), 
    .rv_ds(rv_ds), .rv_dout(rv_dout), .rv_req(rv_req), .rv_req_ack(rv_req_ack), .rv_we(rv_wstrb != 0)
`endif
);

`ifdef TINYSNES_SDRAM_TEST
// Diagnostic build: memory self-test, result drawn by snes2hdmi (green/red bars
// per DQ bit, letterbox = status).  Runs once after the controller's init and
// holds its result.  See fpga/snes/src/sdram_bist.v.
wire [21:0] bist_addr;
wire [15:0] bist_din;
wire        bist_we, bist_req, bist_ack;
wire [15:0] bist_mask;
wire  [1:0] bist_status;
wire  [2:0] bist_dbg = bist_status == 2'd1 ? 3'b010 :   // done, all bits correct
                       bist_status == 2'd2 ? 3'b100 :   // done, mismatch
                       bist_status == 2'd3 ? 3'b110 :   // no acknowledge
                                             3'b001;   // running
sdram_bist bist (
    .clk(fclk), .resetn(resetn), .ready(~sdram_busy),
    .addr(bist_addr), .din(bist_din), .we(bist_we), .req(bist_req), .ack(bist_ack),
    .dout(cpu_port0), .mask(bist_mask), .status(bist_status)
);
`endif

`ifdef TINYSNES_WRAM_TEST
// Diagnostic build: WRAM self-test through the controller's CPU port.
// See fpga/snes/src/wram_bist.v.  The address and data wires are declared above
// the controller instance, with the rest of this build's nets.
wram_bist wram_bist (
    .clk(mclk), .resetn(resetn), .ready(~sdram_busy),
    .addr(wram_bist_addr), .din(wram_bist_din), .we(wram_bist_we),
    .req(wram_bist_req), .ack(wram_bist_ack),
    .dout(cpu_port1), .mask(wram_bist_mask), .status(wram_bist_status)
);
// The controller takes a 23-bit byte address; WRAM sits at {6'b111_111, addr}
// in SDRAM and the lane select is {addr[0], ~addr[0]}, exactly as the machine's
// own WRAM path does it.
assign wram_bist_cpu_addr = {6'b111_111, wram_bist_addr};
assign wram_bist_ds       = {wram_bist_addr[0], ~wram_bist_addr[0]};
`endif

`ifdef TINYSNES_READ_STABILITY
// Diagnostic build: read the same address twice over thousands of refresh
// periods and count disagreements.  See fpga/snes/src/rom_stability.v.
rom_stability rom_stability (
    .clk(mclk), .resetn(resetn), .loaded(loaded),
    .dout(cpu_port0), .addr(stability_addr), .req(stability_req), .ack(stability_ack),
    .mism(stability_mism), .status(stability_status), .done(stability_done)
);
`endif

`ifdef TINYSNES_ARAM_TEST
aram_bist aram_bist (
    .clk(fclk), .resetn(resetn), .ready(~sdram_busy),
    .addr(aram_bist_addr), .din(aram_bist_din), .we(aram_bist_we),
    .req(aram_bist_req), .ack(aram_bist_ack),
    .dout(aram_dout), .mask(aram_bist_mask), .status(aram_bist_status)
);
`endif

`ifdef TINYSNES_ROM_CHECK
// Diagnostic build: read the loaded ROM back out of SDRAM through the CPU's own
// port and compare it with the image, before the machine is allowed to start.
wire [21:0] rom_probe_addr;
wire        rom_probe_req, rom_probe_ack, rom_probe_done, rom_probe_timeout;
wire  [7:0] rom_probe_fail;
rom_probe rom_probe (
    .clk(mclk), .resetn(resetn), .loaded(loaded),
    .dout(cpu_port0), .addr(rom_probe_addr), .req(rom_probe_req),
    .ack(rom_probe_ack), .fail(rom_probe_fail), .done(rom_probe_done),
    .timed_out(rom_probe_timeout)
);
`endif

`ifndef SDRAM_3CH
// FPGA block RAM for SNES VRAM 
vram vram(
    .clk(mclk), 
    .vram1_addr(vram1_addr_sd), .vram1_req(vram1_req), .vram1_ack(), 
    .vram1_we(~vram1_we_n_old), .vram1_din(vram1_din), .vram1_dout(VRAM1_Q), 
    .vram2_addr(vram2_addr_sd), .vram2_req(vram2_req), .vram2_ack(),
    .vram2_we(~vram2_we_n_old),  .vram2_din(vram2_din), .vram2_dout(VRAM2_Q)
);
`endif

`ifdef TINYSNES_LOAD_COUNT
// Diagnostic build: count the loader's own SDRAM write issues, using the exact
// condition that issues them, and show the count as gated thresholds.  Nothing
// touches the CPU port or the data path, so the loader runs unmodified and the
// count is of real writes rather than of a simulation of them.
reg [19:0] wr_count = 20'd0;
always @(posedge mclk)
    if (loading && loader_do_valid && header_finished && loader_addr[0])
        wr_count <= wr_count + 20'd1;
// A 1 MiB image is 524288 words, so the top threshold is just below that.
wire [7:0] load_flags = { wr_count >= 20'd500000,
                          wr_count >= 20'd262144,
                          wr_count >= 20'd131072,
                          wr_count >= 20'd32768,
                          wr_count >= 20'd4096,
                          wr_count >= 20'd256,
                          wr_count >= 20'd16,
                          wr_count >= 20'd1 };
`endif

// Parse 64-byte rom header into rom_type and etc
smc_parser smc (
    .clk(mclk), .resetn(resetn & ~(loading & ~loading_r)),
    .rom_d(loader_do), .rom_strb(loader_do_valid), 
    .rom_type(rom_type), .rom_mask(rom_mask), .ram_mask(ram_mask),
    .rom_size(rom_size), .ram_size(ram_size),
    .header_finished(header_finished)
);

reg [7:0] loader_do_r;
reg loading_r;
always @(posedge mclk) begin
    if (~resetn) begin
        loading_r <= 0;
        loaded <= 0;
    end else begin
        loading_r <= loading;
        if (loader_do_valid && header_finished) begin
            loader_addr <= loader_addr + 23'd1; 
            loader_do_r <= loader_do;
        end
        if (loading & ~loading_r) begin
            loader_addr <= 0;
            loaded <= 0;
        end
        if (~loading & loading_r)
            loaded <= 1;
    end
end

`ifndef VERILATOR

// Controller input
`ifdef CONTROLLER_SNES
controller_snes joy1_snes (
    .clk(mclk), .resetn(resetn), .buttons(joy1_btns_snes),
    .joy_strb(joy1_strb), .joy_clk(joy1_clk), .joy_data(joy1_data)
);
controller_snes joy2_snes (
    .clk(mclk), .resetn(resetn), .buttons(joy2_btns_snes),
    .joy_strb(joy2_strb), .joy_clk(joy2_clk), .joy_data(joy2_data)
);
`else
assign joy1_btns_snes = 12'h0;
assign joy2_btns_snes = 12'h0;
`endif

`ifdef CONTROLLER_DS2
controller_ds2 joy1_ds2 (
    .clk(mclk), .snes_buttons(joy1_btns_ds2),
    .ds_clk(ds_clk), .ds_miso(ds_miso), .ds_mosi(ds_mosi), .ds_cs(ds_cs) 
);
controller_ds2 joy2_ds2 (
   .clk(mclk), .snes_buttons(joy2_btns_ds2),
   .ds_clk(ds_clk2), .ds_miso(ds_miso2), .ds_mosi(ds_mosi2), .ds_cs(ds_cs2) 
);
`else
assign joy1_btns_ds2 = 12'h0;
assign joy2_btns_ds2 = 12'h0;
`endif

`ifdef USB1
wire clk12;
wire pll_lock_12;
wire usb_conerr;
wire [1:0] usb_type;
pll_12 pll12(.clkin(sys_clk), .clkout0(clk12), .lock(pll_lock_12));
usb_hid_host usb_hid_host (
    .usbclk(clk12), .usbrst_n(pll_lock_12),
    .usb_dm(usb1_dn), .usb_dp(usb1_dp),
    .typ(usb_type), .conerr(usb_conerr),
    .game_snes(joy1_usb)
);
`else
assign joy1_usb = 12'h0;
`endif

`ifdef USB2
wire usb_conerr2;
wire [1:0] usb_type2;   
usb_hid_host usb_hid_host2 (
    .usbclk(clk12), .usbrst_n(pll_lock_12),
    .usb_dm(usb2_dn), .usb_dp(usb2_dp),
    .game_snes(joy2_usb), .typ(usb_type2), .conerr(usb_conerr2)
);
assign led = ~{joy2_usb[1:0], usb_type2, usb_conerr2, usb_type, usb_conerr};
`else
assign joy2_usb = 12'h0;
// TinySNES has no FPGA-side USB HID host, so nothing to report on the LEDs.
assign led = 8'hff;
`endif

// output button presses to SNES
controller_adapter joy1_adapter (
    .clk(mclk), .snes_joy_strb(snes_joy_strb), 
    .snes_buttons(joy1_btns_ds2 | joy1_btns_snes | hid1 | joy1_usb), .snes_joy_clk(snes_joy1_clk), .snes_joy_di(snes_joy1_di[0])
);
controller_adapter joy2_adapter (
    .clk(mclk), .snes_joy_strb(snes_joy_strb), 
    .snes_buttons(joy2_btns_ds2 | joy2_btns_snes | hid2 | joy2_usb), .snes_joy_clk(snes_joy2_clk), .snes_joy_di(snes_joy2_di[0])
);
assign snes_joy1_di[1] = 0;  // P3
assign snes_joy2_di[1] = 0;  // P4

wire [14:0] overlay_color;
wire [7:0] overlay_x;
wire [7:0] overlay_y;

wire [7:0] dbg_dat_out_loader;

snes2hdmi s2h(
    .clk(mclk), .resetn(resetn), .snes_refresh(refresh),
`ifdef TINYSNES_IRQ_PROBE
    // Diagnostic build: R = a ROM access in the last sample window, G = loaded,
    // B = enable; probe_bus carries the sticky interrupt bits, the status byte
    // and the halt PC per the field order in the TINYSNES_IRQ_PROBE block.
    .dbg({header_finished, loaded, enable}),
    .bist_mask(fp_bus[15:0]),
    .probe_bus(fp_bus),
`elsif TINYSNES_LINK_PROBE
    // Diagnostic build: R = header_finished, G = loaded, B = enable -- the three
    // machine gates, which are declared unconditionally, so this probe does not
    // drag in the trace probe's own signals.  Yellow means the header parsed and
    // the core is enabled, which is the state a link measurement is taken in.
    // probe_bus carries both directions of the APU link and both CPUs' state per
    // the field order in the TINYSNES_LINK_PROBE block.
    .dbg({header_finished, loaded, enable}),
    .bist_mask(fp_bus[15:0]),
    .probe_bus(fp_bus),
`elsif TINYSNES_JUMP_PROBE
    // Diagnostic build: R = a departure from the cartridge has been recorded,
    // G = loaded, B = enable.  The band reads the same event the stripes
    // describe, so "no stripe data" and "no departure" are told apart before
    // anything is decoded.  probe_bus carries the departure PC, the ROM bank and
    // newest fetch before it, the two fetches before that, and the PBR, per the
    // field order in the TINYSNES_JUMP_PROBE block.
    .dbg({jp_done, loaded, enable}),
    .bist_mask(fp_bus[15:0]),
    .probe_bus(fp_bus),
`elsif TINYSNES_WHERE_PROBE
    // Diagnostic build: R = the CPU has left the cartridge, G = loaded, B =
    // enable.  The band is a second, stripe-independent reading of the one
    // question this build exists to answer: red means a PC below $8000 was seen
    // after the CPU had been above it, so the departure is visible before any
    // stripe is decoded.  probe_bus carries the PC, PBR, SP, P, the sticky
    // history byte, the departure PC and the newest ROM address, per the field
    // order in the TINYSNES_WHERE_PROBE block.
    .dbg({st_left, loaded, enable}),
    .bist_mask(fp_bus[15:0]),
    .probe_bus(fp_bus),
`elsif TINYSNES_IPL_PROBE
    // Diagnostic build: R = exit_seen, G = loaded, B = enable.  A red band means
    // the SPC700 has been seen leaving its IPL ROM, which is the state this build
    // exists to measure, so the band confirms the instrument fired before the
    // stripes are read.  probe_bus carries the jump target, A and X at that
    // moment, the current PC and the three CPUI bytes, per the field order in the
    // TINYSNES_IPL_PROBE block above.
    .dbg({exit_seen, loaded, enable}),
    .bist_mask(fp_bus[15:0]),
    .probe_bus(fp_bus),
`elsif TINYSNES_APU_PROBE
    // Diagnostic build: R = header_finished, G = loaded, B = loading, so the
    // border says whether the core is released; probe_bus carries CPUO's two
    // ports, the 65816's A, PC and P, the SPC700's PC and CPUI port 0, in the
    // field order set out in the TINYSNES_APU_PROBE block above.
    .dbg({header_finished, loaded, loading}),
    .bist_mask(fp_bus[15:0]),
    .probe_bus(fp_bus),
`elsif TINYSNES_LIVE_PROBE
    // Diagnostic build: the machine's own picture, with two latched stripes laid
    // over its top 64 rows so the CPU's state and what the PPU draws are read
    // from one screenshot.  Stripe 1 is the ROM access count's low half and
    // stripe 2 is the CPU's PC, both latched every 0.2 s.  The port carries the
    // three machine gates rather than the probe's activity, because a build like
    // this is used to ask why the machine is not running: under
    // TINYSNES_DBG_BORDER the border reads R = header_finished, G = loaded,
    // B = loading, and a blue border means the core is still held in reset.
    .dbg({header_finished, loaded, loading}),
    .bist_mask(fp_bus[15:0]),
    .probe_bus({48'd0, live_bus}),
`elsif TINYSNES_TRACE_PROBE
    // Diagnostic build: R = a ROM access in the last sample window, G = loaded,
    // B = enable; probe_bus carries the last four ROM addresses, newest first,
    // and the high half of the newest one.
    .dbg({rom_recent, loaded, enable}),
    .bist_mask(fp_bus[15:0]),
    .probe_bus(fp_bus),
`elsif TINYSNES_CPU_PROBE
    // Diagnostic build: R = pc_changed, G = loaded, B = enable; probe_bus
    // carries the ROM access count, two PC samples and SP.
    .dbg({pc_changed, loaded, enable}),
    .bist_mask(fp_bus[15:0]),
    .probe_bus(fp_bus),
`elsif TINYSNES_FETCH_PROBE
    // Diagnostic build: R = fetch_seen, G = loaded, B = enable; probe_bus
    // carries the five time-ordered fields of the first ROM access.
    .dbg({fetch_seen, loaded, enable}),
    .bist_mask(fp_bus[15:0]),
    .probe_bus(fp_bus),
`elsif TINYSNES_LOAD_COUNT
    // Diagnostic build: R = header_finished, G = loaded, B = enable, and the
    // mask port carries the loader write-count thresholds.
    .dbg({header_finished, loaded, enable}),
    .bist_mask({8'd0, load_flags}),
`elsif TINYSNES_ROM_CHECK
    // Diagnostic build: R = header_finished, G = loaded, B = enable.  Yellow
    // means the 64-byte header parsed, so the write gate opened and any missing
    // image data is downstream of it; cyan means the header never completed and
    // no image byte could ever have been written.
    .dbg({header_finished, loaded, enable}),
    .bist_mask({8'd0, rom_probe_fail}),
`elsif TINYSNES_SDRAM_TEST
    .dbg(bist_dbg),
    .bist_mask(bist_mask),
`elsif TINYSNES_ARAM_TEST
    .dbg(aram_bist_dbg),
    .bist_mask(aram_bist_mask),
`elsif TINYSNES_READ_STABILITY
    .dbg(stability_dbg),
    .bist_mask(stability_mism),
`elsif TINYSNES_WRAM_TEST
    .dbg(wram_bist_dbg),
    .bist_mask(wram_bist_mask),
`else
  `ifdef TINYSNES_DBG_MACHINE
    // Diagnostic build: why the machine is or is not running.  R = enable,
    // G = loaded, B = pause_snes_for_frame_sync.  enable is the gate into main,
    // and it needs ~pause, so green alone means the SNES is held off.
    .dbg({enable, loaded, pause_snes_for_frame_sync}),
  `else
    .dbg({header_finished, loaded, loading}),
  `endif
    .bist_mask(16'hFFFF),
`endif
    .pause_snes_for_frame_sync(pause_snes_for_frame_sync),
    .dotclk(dotclk), .hblank(~hblankn),.vblank(~vblankn),.rgb5(rgb_out),
    .xs(x_out), .ys(y_out), 
    .overlay(overlay), .overlay_x(overlay_x), .overlay_y(overlay_y),
    .overlay_color(overlay_color), 
    .audio_l(audio_l), .audio_r(audio_r), .audio_ready(audio_ready), .audio_en(audio_en),
    .clk_pixel(hclk),.clk_5x_pixel(hclk5),.locked(1'b1),
    .tmds_clk_n(tmds_clk_n), .tmds_clk_p(tmds_clk_p),
    .tmds_d_n(tmds_d_n), .tmds_d_p(tmds_d_p)
);

iosys_bl616 #(.CORE_ID(2), .FREQ(21_484_000)) iosys (
    .clk(mclk), .hclk(hclk), .resetn(resetn),
    .overlay(overlay), .overlay_x(overlay_x), .overlay_y(overlay_y),
    .overlay_color(overlay_color),
    .joy1(joy1_btns_ds2 | joy1_btns_snes | joy1_usb), .joy2(joy2_btns_ds2 | joy2_btns_snes | joy2_usb), .hid1(hid1), .hid2(hid2),
    .uart_tx(UART_TXD), .uart_rx(UART_RXD),
    .rom_loading(loading), .rom_do(loader_do), .rom_do_valid(loader_do_valid)
);

`else       // VERILATOR

// test loader with embedded rom
test_loader test_loader (
    .clk(mclk), .resetn(resetn),
    .dout(loader_do), .dout_valid(loader_do_valid),
    .loading(loading), .fail()
);

// test audio sink: FIFO-like rate limiting to sound sample generation
reg [3:0] sample_counter = 0;
always @(posedge mclk) begin
    if (audio_ready)
        sample_counter <= 0;
    else
        sample_counter <= sample_counter == 15 ? 15 : sample_counter + 1;
end
assign audio_en = sample_counter == 15;


// test video sync by turning on pause_snes_for_frame_sync periodically
reg test_halt_snes, test_sync_done;
reg [3:0] test_halt_cnt = 0;
assign pause_snes_for_frame_sync = test_halt_snes;

always @(posedge mclk) begin    // halt SNES during snes dram refresh on line 2
    if (~resetn) begin
        test_halt_cnt <= 0;
        test_halt_snes <= 0;
        test_sync_done <= 0;
    end else begin
        if (~test_sync_done) begin
            if (~test_halt_snes) begin
                if (y_out[7:0] == 2 && refresh) begin
                    test_halt_snes <= 1;
                    test_halt_cnt <= 4'd12;        // halt snes for 13 cycles
                end
            end else begin
                if (test_halt_cnt != 0) begin
                    test_halt_cnt <= test_halt_cnt - 4'd1;
                end else begin
                    test_halt_snes <= 0;
                    test_sync_done <= 1;
                end                            
            end
        end else if (y_out[7:0] == 8'd200)
            test_sync_done <= 0;
    end
end

`endif

`ifndef VERILATOR

reg [19:0] timer;           // 21 times per second

// status display on LED

reg [9:0] status;
//assign led = s0 == 1'b0 ? ~status[9:5] : ~status[4:0];        // s0==0 when pressed, for mega138k
// assign led = UART_TXD;
//assign led = joy1_btns[1:0];        // Y and B

always @(posedge mclk) begin
    if (loading && ~loading_r)
        status <= 0;
    if (loaded) begin
        case (rom_addr)
        23'h00_000A: status[1] <= 1;
        23'h00_00A1: status[2] <= 1;        // Clear_WRAM
        23'h00_0645: status[3] <= 1;        // Main
        23'h00_0111: status[4] <= 1;        // DMA_Palette
        
        23'h00_06AB: status[5] <= 1;        // Draw_Map
        23'h00_072A: status[6] <= 1;        // Init_Music
        23'h00_075F: status[7] <= 1;        // Infinite_loop
        23'h00_0787: status[8] <= 1;        // left button
        default: ;
        endcase
    end
end

`endif

endmodule
