`timescale 1ns/1ps

// Reconstruct a real framebuffer from the SNES core in simulation.
//
// Why this exists.  The board shows a static grid and simulation shows a healthy
// raster, and every attempt to bridge that gap by probing hardware signals has
// produced unreliable numbers.  So this bench does the thing the project has
// never done: it renders a frame.  It samples the core's own pixel stream --
// RGB_OUT, X_OUT, Y_OUT, DOTCLK and the display-enable pair -- applies exactly
// the write condition snes2hdmi applies to its line buffer, and writes the
// resulting 256x224 image to a PPM file.
//
// The image is the reference.  Whatever the Tang draws can then be compared
// against it, and a difference of "one column versus a whole picture" stops
// being an inference from a pixel diff and becomes a fact about two files.
//
// It also answers the question the last hardware cycle opened: the counter build
// wrote only into the leftmost six capture pixels, which is what a stuck OUT_X
// produces.  If this bench shows the full 256-pixel width, OUT_X is fine in the
// RTL and the fault is elsewhere; if it shows one column, the fault is here and
// it is now debuggable with every internal signal visible.
//
//   tools/tests/run_video_tb.sh [--rom FILE] [--cycles N] [--out FILE.ppm]

module video_tb;

  reg clk = 0;
  reg rst_n = 0;
  reg enable = 0;
  always #5 clk = ~clk;                    // 100 MHz master clock

  reg [1023:0] hex_path;
  localparam CYCLES = 36000000;

  // ------------------------------------------------------------- cartridge
  reg [7:0] rom [0:1048575];

  // ------------------------------------------------------------- SNES buses
  wire [23:0] CA;
  wire        CPURD_N, CPUWR_N, CPURD_CYC_N, DOT_CLK_CE;
  wire [7:0]  PA, DO;
  wire        PARD_N, PAWR_N, RAMSEL_N, ROMSEL_N;
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
  wire        HIGH_RES, FIELD_OUT, INTERLACE, V224_MODE;
  wire        DOTCLK, HDE, VDE, HSYNC, VSYNC;
  wire [14:0] RGB_OUT;
  wire [8:0]  X_OUT, Y_OUT;
  wire        JOY_STRB, JOY1_CLK, JOY2_CLK, AUDIO_READY;
  wire [15:0] AUDIO_L, AUDIO_R;
  wire [7:0]  DBG_DAT_OUT;
  wire        DBG_BREAK;

  integer i;

  // LoROM mapping, exactly as SNES.v sees it.
  wire [23:0] loff = ({8'd0, (CA[23:16] & 8'h7F), 1'b0} << 15)
                   | {8'd0, (CA[15:0] & 16'h7FFF)};
  wire [7:0]  cart_q = rom[loff[19:0]];
  wire [7:0]  DI = (ROMSEL_N === 1'b0) ? cart_q : 8'hFF;

  reg [7:0] wram [0:131071];
  always @(posedge clk) begin
    if (!WRAM_CE_N && !WRAM_WE_N) wram[WRAM_ADDR] <= WRAM_D;
    WRAM_Q <= wram[WRAM_ADDR];
  end

  reg [7:0] vram [0:65535];
  always @(posedge clk) begin
    if (!VRAM_WRA_N) vram[VRAM_ADDRA] <= VRAM_DAO;
    if (!VRAM_WRB_N) vram[VRAM_ADDRB] <= VRAM_DBO;
    VRAM_DAI <= vram[VRAM_ADDRA];
    VRAM_DBI <= vram[VRAM_ADDRB];
  end

  reg [7:0] aram [0:65535];
  always @(posedge clk) begin
    if (!ARAM_CE_N && !ARAM_WE_N) aram[ARAM_ADDR] <= ARAM_D;
    ARAM_Q <= aram[ARAM_ADDR];
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
    .DBG_SEL(8'h00), .DBG_REG(8'h00), .DBG_REG_WR(1'b0), .DBG_DAT_IN(8'h00),
    .DBG_DAT_OUT(DBG_DAT_OUT), .DBG_BREAK(DBG_BREAK)
  );

  // ---------------------------------------------------------- framebuffer
  // A pixel is taken under exactly the condition snes2hdmi uses to write its
  // line buffer.  x is the SNES pixel column (X_OUT is {x, dotclk}), y the row.
  reg [14:0] fb [0:256*224-1];
  reg        fb_written [0:256*224-1];

  integer wr = 0, seen_x_max = 0, seen_y_max = 0;
  integer n_dot = 0, n_hde = 0, n_vde = 0, n_both = 0, n_ys = 0;
  integer distinct_x = 0, distinct_y = 0;
  reg [255:0] x_seen = 256'b0;
  reg  [255:0] y_seen = 256'b0;
  reg dot_r = 0;
  integer cyc = 0;

  integer k;
  initial for (k = 0; k < 256*224; k = k + 1) begin
    fb[k] = 15'h0000;
    fb_written[k] = 1'b0;
  end

  always @(posedge clk) begin
    cyc <= cyc + 1;
    dot_r <= DOTCLK;
    if (enable) begin
      if (DOTCLK && ~dot_r) n_dot = n_dot + 1;
      if (HDE === 1'b1) n_hde = n_hde + 1;
      if (VDE === 1'b1) n_vde = n_vde + 1;
      if (HDE === 1'b1 && VDE === 1'b1) n_both = n_both + 1;
      if (Y_OUT[7:0] < 8'd224) n_ys = n_ys + 1;
    end
    // X_OUT[8:1] is eight bits, so it is always a valid column.  An earlier
    // version compared it against 8'd256, which truncates to zero and made the
    // whole condition false -- the bench reported zero pixels while every
    // individual term was healthy, which is what that diagnostic was added to
    // catch.
    if (enable && DOTCLK && ~dot_r && HDE && VDE && Y_OUT[7:0] < 8'd224) begin
      fb[Y_OUT[7:0]*256 + X_OUT[8:1]] = RGB_OUT;
      fb_written[Y_OUT[7:0]*256 + X_OUT[8:1]] = 1'b1;
      wr = wr + 1;
      x_seen[X_OUT[8:1]] = 1'b1;
      y_seen[Y_OUT[7:0]] = 1'b1;
    end
  end

  // ---------------------------------------------------------------- output
  integer fd, x, y, n;
  reg [7:0] r8, g8, b8;

  task dump_frame;
    begin
      fd = $fopen("frame_0.ppm", "w");
      $fwrite(fd, "P6\n256 224\n255\n");
      for (y = 0; y < 224; y = y + 1)
        for (x = 0; x < 256; x = x + 1) begin
          n = y*256 + x;
          // BGR555 to RGB888, the same expansion snes2hdmi uses.
          r8 = {fb[n][4:0], 3'b000};
          g8 = {fb[n][9:5], 3'b000};
          b8 = {fb[n][14:10], 3'b000};
          $fwrite(fd, "%c%c%c", r8, g8, b8);
        end
      $fclose(fd);
    end
  endtask

  integer distinct_colours;
  integer ok_pixels;

  always @(posedge clk) begin
    if (cyc == CYCLES) begin
      distinct_x = 0;
      distinct_y = 0;
      for (k = 0; k < 256; k = k + 1) begin
        if (x_seen[k]) distinct_x = distinct_x + 1;
        if (y_seen[k]) distinct_y = distinct_y + 1;
      end
      ok_pixels = 0;
      for (k = 0; k < 256*224; k = k + 1) if (fb_written[k]) ok_pixels = ok_pixels + 1;

      $display("");
      $display("video bench");
      $display("  pixels written under the snes2hdmi write condition: %0d", wr);
      $display("  distinct framebuffer positions covered:            %0d", ok_pixels);
      $display("  distinct x columns: %0d   distinct y rows: %0d", distinct_x, distinct_y);
      $display("  dotclk edges %0d  HDE high %0d  VDE high %0d  both %0d  ys<224 %0d",
               n_dot, n_hde, n_vde, n_both, n_ys);
      $display("  final: DOTCLK=%b HDE=%b VDE=%b X_OUT=%03d Y_OUT=%03d RGB=%04X",
               DOTCLK, HDE, VDE, X_OUT, Y_OUT, RGB_OUT);
      dump_frame;
      $display("  wrote frame_0.ppm");
      if (distinct_x < 2)
        $display("FAIL  the write address never advances horizontally: OUT_X is stuck.");
      else if (ok_pixels < 256*224)
        $display("FAIL  only %0d of %0d positions were written.", ok_pixels, 256*224);
      else
        $display("PASS  a full 256x224 frame was rendered from the core's pixel stream.");
      $finish;
    end
  end

  initial begin
    if (!$value$plusargs("hex=%s", hex_path)) hex_path = "rom.hex";
    for (i = 0; i < 1048576; i = i + 1) rom[i] = 8'hFF;
    $display("loading cartridge from %0s", hex_path);
    $readmemh(hex_path, rom);
    $display("reset vector = %02X%02X", rom[16'h7FFD], rom[23'h7FFC]);
    for (i = 0; i < 131072; i = i + 1) wram[i] = 8'h00;
    for (i = 0; i < 65536;  i = i + 1) begin vram[i] = 8'h00; aram[i] = 8'h00; end
    repeat (20) @(posedge clk);
    rst_n <= 1'b1;
    repeat (20) @(posedge clk);
    enable <= 1'b1;
    $display("enable raised at cycle %0d, running to %0d", cyc, CYCLES);
  end

endmodule
