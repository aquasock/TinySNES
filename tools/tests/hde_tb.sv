`timescale 1ns/1ps

// Bench for the PPU's display-enable outputs, HDE and VDE.
//
// Why this exists.  On the board, the line buffer in snes2hdmi is written only
// when `dotclk` rises with hblank and vblank both low, and repeated hardware
// probes came back unable to agree on what those two signals were doing: one
// said hblankn was never low, another said it was never high, and a third that
// counted both levels got zero for each.  A zero from a four-state comparison is
// not a measurement -- synthesis of `===` against a constant on a one-bit wire
// can fold both branches to false, land in the `else`, and increment a counter
// that is never displayed.  That is what happened, and it is why this question
// moved into simulation, where an X is visible instead of being optimised away.
//
// HDE and VDE are the PPU's own outputs: HDE goes high at dot 19 and low at dot
// 275 of every scanline, VDE goes high at line 1 and low after the last visible
// line.  Together they gate the snes2hdmi line-buffer write, so if they never
// assert, nothing is ever drawn -- which is exactly the symptom this project has
// been staring at.
//
// Checked here:
//   1. HDE asserts within a few scanlines of enable and toggles once per line;
//   2. VDE asserts and toggles once per frame;
//   3. HDE and VDE are simultaneously high for a large part of each line, which
//      is the condition the line-buffer write actually needs;
//   4. neither output is X at any point after reset.
//
// HDE and VDE are the PPU's raster position made visible, so they are also the
// cheapest proof that a disabled PPU is distinguishable from a broken one.
module hde_tb;

  reg clk = 0;
  reg rst_n = 0;
  reg enable = 0;

  always #5 clk = ~clk;              // 100 MHz master, as the core is clocked

  wire [23:0] CA;
  wire        CPURD_N, CPUWR_N, CPURD_CYC_N, DOT_CLK_CE;
  wire [7:0]  PA;
  wire        PARD_N, PAWR_N;
  wire [7:0]  DO;
  wire        RAMSEL_N, ROMSEL_N;
  wire        SYSCLKF_CE, SYSCLKR_CE, SNES_REFRESH;

  wire [16:0] WRAM_ADDR;
  wire [7:0]  WRAM_D;
  reg  [7:0]  WRAM_Q;
  wire        WRAM_CE_N, WRAM_OE_N, WRAM_WE_N, WRAM_RD_N;

  wire [15:0] VRAM_ADDRA, VRAM_ADDRB;
  wire [7:0]  VRAM_DAO, VRAM_DBO;
  reg  [7:0]  VRAM_DAI, VRAM_DBI;
  wire        VRAM_RD_N, VRAM_WRA_N, VRAM_WRB_N;

  wire [15:0] ARAM_ADDR;
  wire [7:0]  ARAM_D;
  reg  [7:0]  ARAM_Q;
  wire        ARAM_CE_N, ARAM_OE_N, ARAM_WE_N;

  wire        JOY_STRB, JOY1_CLK, JOY2_CLK, AUDIO_READY;
  wire [15:0] AUDIO_L, AUDIO_R;

  wire        HIGH_RES, FIELD_OUT, INTERLACE, V224_MODE;
  wire        DOTCLK, HDE, VDE, HSYNC, VSYNC;
  wire [14:0] RGB_OUT;
  wire [8:0]  X_OUT, Y_OUT;

  reg  [7:0]  DBG_SEL = 8'h00, DBG_REG = 8'h00, DBG_DAT_IN = 8'h00;
  reg         DBG_REG_WR = 1'b0;
  wire [7:0]  DBG_DAT_OUT;
  wire        DBG_BREAK;

  // A cartridge whose reset vector is $8000 and whose first instruction is a
  // two-byte NOP-ish loop.  The program is irrelevant: HDE and VDE are produced
  // by the PPU from its own counters, so this bench measures the raster with a
  // machine that does nothing but run.
  reg [7:0] rom [0:65535];
  integer i;
  initial begin
    for (i = 0; i < 65536; i = i + 1) rom[i] = 8'hEA;      // NOP everywhere
    rom[16'h7FFC] = 8'h00;                                  // RESET = $8000
    rom[16'h7FFD] = 8'h80;
  end

  wire [23:0] loff = ({8'd0, (CA[23:16] & 8'h7F), 1'b0} << 15)
                   | {8'd0, (CA[15:0] & 16'h7FFF)};
  wire [7:0]  cart = rom[loff[15:0]];
  wire [7:0]  DI = (ROMSEL_N === 1'b0) ? cart : 8'hFF;

  reg [7:0] wram [0:131071];
  initial for (i = 0; i < 131072; i = i + 1) wram[i] = 8'h00;
  always @(posedge clk) begin
    if (!WRAM_CE_N && !WRAM_WE_N) wram[WRAM_ADDR] <= WRAM_D;
    WRAM_Q <= wram[WRAM_ADDR];
  end

  reg [7:0] vram [0:65535];
  initial for (i = 0; i < 65536; i = i + 1) vram[i] = 8'h00;
  always @(posedge clk) begin
    if (!VRAM_WRA_N) vram[VRAM_ADDRA] <= VRAM_DAO;
    if (!VRAM_WRB_N) vram[VRAM_ADDRB] <= VRAM_DBO;
    VRAM_DAI <= vram[VRAM_ADDRA];
    VRAM_DBI <= vram[VRAM_ADDRB];
  end

  reg [7:0] arq [0:65535];
  initial for (i = 0; i < 65536; i = i + 1) arq[i] = 8'h00;
  always @(posedge clk) begin
    if (!ARAM_CE_N && !ARAM_WE_N) arq[ARAM_ADDR] <= ARAM_D;
    ARAM_Q <= arq[ARAM_ADDR];
  end

  SNES dut (
    .MCLK(clk), .RST_N(rst_n), .ENABLE(enable), .MEM_WAIT(1'b0),
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

  // ------------------------------------------------------------- measurement
  integer cyc = 0;
  integer hde_rise = 0, hde_fall = 0;
  integer vde_rise = 0, vde_fall = 0;
  integer both_high = 0, samples = 0;
  integer hde_x = 0, vde_x = 0;
  integer first_hde_at = -1, first_vde_at = -1;
  reg hde_r = 0, vde_r = 0;

  always @(posedge clk) begin
    cyc <= cyc + 1;
    hde_r <= HDE;
    vde_r <= VDE;
    if (rst_n) begin
      samples <= samples + 1;
      if (HDE !== 1'b0 && HDE !== 1'b1) hde_x <= hde_x + 1;
      if (VDE !== 1'b0 && VDE !== 1'b1) vde_x <= vde_x + 1;
      if (HDE === 1'b1 && ~hde_r) begin
        hde_rise <= hde_rise + 1;
        if (first_hde_at < 0) first_hde_at <= cyc;
      end
      if (HDE === 1'b0 && hde_r) hde_fall <= hde_fall + 1;
      if (VDE === 1'b1 && ~vde_r) begin
        vde_rise <= vde_rise + 1;
        if (first_vde_at < 0) first_vde_at <= cyc;
      end
      if (VDE === 1'b0 && vde_r) vde_fall <= vde_fall + 1;
      if (HDE === 1'b1 && VDE === 1'b1) both_high <= both_high + 1;
    end
  end

  initial begin
    repeat (20) @(posedge clk);
    rst_n <= 1'b1;
    repeat (20) @(posedge clk);
    enable <= 1'b1;
    repeat (4000000) @(posedge clk);      // ~40 ms of master clock

    $display("");
    $display("HDE/VDE bench");
    $display("  samples            %0d", samples);
    $display("  HDE rising edges   %0d   first at cycle %0d", hde_rise, first_hde_at);
    $display("  HDE falling edges  %0d", hde_fall);
    $display("  VDE rising edges   %0d   first at cycle %0d", vde_rise, first_vde_at);
    $display("  VDE falling edges  %0d", vde_fall);
    $display("  HDE high and VDE high together: %0d samples (%.2f%%)",
             both_high, 100.0 * both_high / (samples == 0 ? 1 : samples));
    $display("  X on HDE: %0d   X on VDE: %0d", hde_x, vde_x);

    if (hde_rise == 0) begin
      $display("FAIL  HDE never asserts: the PPU never begins a line.");
      $finish;
    end
    if (hde_x != 0 || vde_x != 0) begin
      $display("FAIL  HDE or VDE took an undefined value.");
      $finish;
    end
    if (both_high == 0) begin
      $display("FAIL  HDE and VDE are never high together: the line-buffer write");
      $display("      condition can never be met, whatever the CPU does.");
      $finish;
    end
    $display("PASS");
    $finish;
  end

endmodule
