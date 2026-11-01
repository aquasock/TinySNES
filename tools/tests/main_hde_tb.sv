`timescale 1ns/1ps

// Bench for main.v's HBLANKn / VBLANKn outputs.
//
// The question this exists to answer.  hde_tb.sv proves the PPU produces HDE
// correctly inside SNES.v -- 2942 rising edges over four million master clocks.
// A probe inside snes2hdmi then shows HDE never asserts on the board while VDE,
// produced by the same always block from the same counters through the same port
// path, works on both.  Two things can explain that difference and they need
// opposite fixes:
//
//   a) the wire between main.v and the top is broken, or
//   b) HDE depends on something the board's real clocking does that a
//      free-running bench clock does not reproduce.
//
// main.v is the level the top actually instantiates, and it renames the signals
// (`.HDE(HBLANKn)`, `.VDE(VBLANKn)`), so measuring its ports rather than SNES's
// is the difference between testing the PPU and testing the thing the board is
// wired to.  If HBLANKn asserts here, the PPU and main are both fine and the
// break is above them; if it does not, main is where it goes wrong.
//
// The bench also runs ENABLE the way the top does rather than as a constant:
// snestang_top raises it once the loader has finished and can lower it again
// while pause_snes_for_frame_sync is high.  A PPU that stops mid-line and is
// restarted is the one condition a free-running clock never shows, and it is
// candidate (b).
module main_hde_tb;

  reg clk = 0;
  reg rst_n = 0;
  reg enable = 0;

  always #5 clk = ~clk;

  // Test mode: 0 = enable held high after reset, 1 = enable pulsed the way the
  // top pulses it, so the two can be compared in one build.
  integer pulse_enable = 0;

  reg [7:0]  ROM_TYPE  = 8'h20;    // LoROM
  reg [23:0] ROM_MASK  = 24'h0F_FFFF;
  reg [23:0] RAM_MASK  = 24'h00_07FF;
  wire [23:0] ROM_ADDR;
  wire [15:0] ROM_D, ROM_Q;
  wire ROM_CE_N, ROM_OE_N, ROM_WE_N, ROM_WORD;
  wire [19:0] BSRAM_ADDR;
  wire [7:0]  BSRAM_D, BSRAM_Q;
  wire BSRAM_CE_N, BSRAM_OE_N, BSRAM_WE_N, BSRAM_RD_N;
  wire [16:0] WRAM_ADDR;
  wire [7:0]  WRAM_D;
  reg  [7:0]  WRAM_Q;
  wire WRAM_CE_N, WRAM_OE_N, WRAM_WE_N, WRAM_RD_N;
  wire [15:0] VRAM1_ADDR, VRAM2_ADDR;
  reg  [7:0]  VRAM1_DI, VRAM2_DI;
  wire [7:0]  VRAM1_DO, VRAM2_DO;
  wire VRAM1_WE_N, VRAM2_WE_N, VRAM_OE_N;
  wire [15:0] ARAM_ADDR;
  wire [7:0]  ARAM_D;
  reg  [7:0]  ARAM_Q;
  wire ARAM_CE_N, ARAM_OE_N, ARAM_WE_N;
  wire HIGH_RES, FIELD, INTERLACE, DOTCLK;
  wire [14:0] RGB_OUT;
  wire HBLANKn, VBLANKn;
  wire [8:0] X_OUT, Y_OUT;
  wire JOY_STRB, JOY1_CLK, JOY2_CLK, JOY1_P6, JOY2_P6;
  wire DOT_CLK_CE, AUDIO_READY;
  wire [15:0] AUDIO_L, AUDIO_R;
  wire [7:0]  DBG_DAT_OUT;
  wire        DBG_BREAK;
  wire SYSCLKF_CE, SYSCLKR_CE, REFRESH;

  integer i;

  // Cartridge: NOPs with a reset vector of $8000.
  reg [7:0] rom [0:1023];
  initial begin
    for (i = 0; i < 1024; i = i + 1) rom[i] = 8'hEA;
    rom[16'h7FC] = 8'h00;            // LoROM offset of $FFFC within the window
    rom[16'h7FD] = 8'h80;
  end
  wire [23:0] loff = ({8'd0, (ROM_ADDR[23:16] & 8'h7F), 1'b0} << 15)
                   | {8'd0, (ROM_ADDR[15:0] & 16'h7FFF)};
  assign ROM_Q = rom[loff[9:0]];

  reg [7:0] wram [0:131071];
  initial for (i = 0; i < 131072; i = i + 1) wram[i] = 8'h00;
  always @(posedge clk) begin
    if (!WRAM_CE_N && !WRAM_WE_N) wram[WRAM_ADDR] <= WRAM_D;
    WRAM_Q <= wram[WRAM_ADDR];
  end

  reg [7:0] vram [0:65535];
  initial for (i = 0; i < 65536; i = i + 1) vram[i] = 8'h00;
  always @(posedge clk) begin
    if (!VRAM1_WE_N) vram[VRAM1_ADDR] <= VRAM1_DO;
    if (!VRAM2_WE_N) vram[VRAM2_ADDR] <= VRAM2_DO;
    VRAM1_DI <= vram[VRAM1_ADDR];
    VRAM2_DI <= vram[VRAM2_ADDR];
  end

  reg [7:0] aram [0:65535];
  initial for (i = 0; i < 65536; i = i + 1) aram[i] = 8'h00;
  always @(posedge clk) begin
    if (!ARAM_CE_N && !ARAM_WE_N) aram[ARAM_ADDR] <= ARAM_D;
    ARAM_Q <= aram[ARAM_ADDR];
  end

  assign BSRAM_Q = 8'h00;

  main dut (
    .MCLK(clk), .RESET_N(rst_n), .ENABLE(enable), .MEM_WAIT(1'b0),
    .SYSCLKF_CE(SYSCLKF_CE), .SYSCLKR_CE(SYSCLKR_CE), .REFRESH(REFRESH),
    .ROM_TYPE(ROM_TYPE), .ROM_MASK(ROM_MASK), .RAM_MASK(RAM_MASK),
    .ROM_ADDR(ROM_ADDR), .ROM_D(ROM_D), .ROM_Q(ROM_Q),
    .ROM_CE_N(ROM_CE_N), .ROM_OE_N(ROM_OE_N), .ROM_WE_N(ROM_WE_N), .ROM_WORD(ROM_WORD),
    .BSRAM_ADDR(BSRAM_ADDR), .BSRAM_D(BSRAM_D), .BSRAM_Q(BSRAM_Q),
    .BSRAM_CE_N(BSRAM_CE_N), .BSRAM_OE_N(BSRAM_OE_N), .BSRAM_WE_N(BSRAM_WE_N),
    .BSRAM_RD_N(BSRAM_RD_N),
    .WRAM_ADDR(WRAM_ADDR), .WRAM_D(WRAM_D), .WRAM_Q(WRAM_Q),
    .WRAM_CE_N(WRAM_CE_N), .WRAM_OE_N(WRAM_OE_N),
    .WRAM_WE_N(WRAM_WE_N), .WRAM_RD_N(WRAM_RD_N),
    .VRAM1_ADDR(VRAM1_ADDR), .VRAM1_DI(VRAM1_DI), .VRAM1_DO(VRAM1_DO),
    .VRAM1_WE_N(VRAM1_WE_N), .VRAM2_ADDR(VRAM2_ADDR), .VRAM2_DI(VRAM2_DI),
    .VRAM2_DO(VRAM2_DO), .VRAM2_WE_N(VRAM2_WE_N), .VRAM_OE_N(VRAM_OE_N),
    .ARAM_ADDR(ARAM_ADDR), .ARAM_D(ARAM_D), .ARAM_Q(ARAM_Q),
    .ARAM_CE_N(ARAM_CE_N), .ARAM_OE_N(ARAM_OE_N), .ARAM_WE_N(ARAM_WE_N),
    .BLEND(1'b0), .PAL(1'b0), .DIS_SHORTLINE(1'b0),
    .HIGH_RES(HIGH_RES), .FIELD(FIELD), .INTERLACE(INTERLACE), .DOTCLK(DOTCLK),
    .RGB_OUT(RGB_OUT), .HBLANKn(HBLANKn), .VBLANKn(VBLANKn),
    .X_OUT(X_OUT), .Y_OUT(Y_OUT),
    .JOY1_DI(2'b11), .JOY2_DI(2'b11), .JOY_STRB(JOY_STRB),
    .JOY1_CLK(JOY1_CLK), .JOY2_CLK(JOY2_CLK),
    .JOY1_P6(JOY1_P6), .JOY2_P6(JOY2_P6), .JOY2_P6_in(1'b0),
    .DOT_CLK_CE(DOT_CLK_CE), .EXT_RTC(65'b0), .SPC_MODE(1'b0),
    .IO_ADDR(17'b0), .IO_DAT(16'b0), .IO_WR(1'b0),
    .AUDIO_L(AUDIO_L), .AUDIO_R(AUDIO_R), .AUDIO_READY(AUDIO_READY),
    .AUDIO_EN(1'b1),
    .DBG_SEL(8'h00), .DBG_REG(8'h00), .DBG_REG_WR(1'b0), .DBG_DAT_IN(8'h00),
    .DBG_DAT_OUT(DBG_DAT_OUT), .DBG_BREAK(DBG_BREAK)
  );

  // ------------------------------------------------------------- measurement
  integer hb_rise = 0, hb_fall = 0, both_low = 0, samples = 0;
  integer hb_high = 0, vb_high = 0, both_high = 0;
  integer coincide = 0;
  reg dot_r = 0;
  integer first_hb = -1;
  reg hb_r = 1;

  always @(posedge clk) begin
    hb_r <= HBLANKn;
    dot_r <= DOTCLK;
    if (rst_n) begin
      samples <= samples + 1;
      // The exact conjunction snes2hdmi uses to write its line buffer:
      //   dotclk rising && ~hblank && ~vblank && ys < 224
      // Synthesis proves this constant and deletes the memory write port, so the
      // bench measures the conjunction itself rather than its terms.
      if (DOTCLK && ~dot_r && HBLANKn && VBLANKn && Y_OUT[7:0] < 8'd224)
        coincide <= coincide + 1;
      if (HBLANKn === 1'b1 && ~hb_r) begin
        hb_rise <= hb_rise + 1;
        if (first_hb < 0) first_hb <= samples;
      end
      if (HBLANKn === 1'b0 && hb_r) hb_fall <= hb_fall + 1;
      if (HBLANKn === 1'b0 && VBLANKn === 1'b0) both_low <= both_low + 1;
      if (HBLANKn === 1'b1) hb_high <= hb_high + 1;
      if (VBLANKn === 1'b1) vb_high <= vb_high + 1;
      if (HBLANKn === 1'b1 && VBLANKn === 1'b1) both_high <= both_high + 1;
    end
  end

  initial begin
    if ($test$plusargs("pulse")) pulse_enable = 1;
    repeat (20) @(posedge clk);
    rst_n <= 1'b1;
    repeat (20) @(posedge clk);

    if (pulse_enable) begin
      // The way snestang_top drives it: enable high while the machine runs, and
      // low again whenever the frame-sync pause asks for it.  A PPU stopped
      // mid-scanline is the condition a constant enable can never produce.
      fork
        begin : drive
          integer k;
          for (k = 0; k < 400; k = k + 1) begin
            enable <= 1'b1;
            repeat (9000 + (k % 40) * 37) @(posedge clk);
            enable <= 1'b0;
            repeat (300 + (k % 7) * 11) @(posedge clk);
          end
        end
        begin
          repeat (4000000) @(posedge clk);
        end
      join_any
    end else begin
      enable <= 1'b1;
      repeat (4000000) @(posedge clk);
    end

    $display("");
    $display("main.v HBLANKn/VBLANKn bench  (enable %s)",
             pulse_enable ? "pulsed like the top" : "held high");
    $display("  samples                       %0d", samples);
    $display("  HBLANKn rising edges          %0d  first at sample %0d",
             hb_rise, first_hb);
    $display("  HBLANKn falling edges         %0d", hb_fall);
    $display("  HBLANKn (HDE) high            %0d (%.2f%%)",
             hb_high, 100.0 * hb_high / (samples == 0 ? 1 : samples));
    $display("  VBLANKn (VDE) high            %0d (%.2f%%)",
             vb_high, 100.0 * vb_high / (samples == 0 ? 1 : samples));
    $display("  both high (display period)    %0d (%.2f%%)",
             both_high, 100.0 * both_high / (samples == 0 ? 1 : samples));
    $display("  both low                      %0d (%.2f%%)",
             both_low, 100.0 * both_low / (samples == 0 ? 1 : samples));
    $display("  WRITE CONDITION (dotclk rising && HDE && VDE && ys<224): %0d", coincide);

    if (hb_rise == 0) begin
      $display("FAIL  HBLANKn never asserts at the main.v boundary.");
      $display("      The PPU produces HDE inside SNES.v, so the break is here.");
    end else if (coincide == 0) begin
      $display("FAIL  the line-buffer write condition never fires.");
      $display("      Synthesis is right: snes2hdmi can never write its buffer.");
    end else if (both_high == 0) begin
      $display("FAIL  HBLANKn and VBLANKn are never HIGH together: the write");
      $display("      condition snes2hdmi needs can never be met.");
    end else begin
      $display("PASS  HBLANKn asserts and the write condition can be met.");
    end
    $finish;
  end

endmodule
