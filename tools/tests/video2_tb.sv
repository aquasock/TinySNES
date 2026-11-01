`timescale 1ns/1ps

// End-to-end video bench: the real SNES core into the real snes2hdmi line buffer.
//
// video_tb.sv proves the core's pixel stream is correct.  This goes one stage
// further and puts that stream through snes2hdmi itself -- the 32-line BRAM ring,
// port A written on the SNES clock, port B read on the pixel clock, the xy
// derivation from the raster -- and captures the colour the module actually picks
// for each visible pixel.
//
// The HDMI serialiser is replaced by hdmi_stub.sv, which keeps the interface and
// generates the raster.  That is the one part of the video path this project has
// already proven on hardware: a build forcing the active area to a constant drew
// a solid white screen, so the serialiser, the PLL chain and the panel all work.
// Everything between the PPU and the serialiser is the real thing here.
//
// This is the reference the board has been missing.  If this bench renders the
// blink cartridge's magenta, then the RTL and the module are correct end to end
// and the only thing standing between the Tang and a picture is the synthesis
// fold that deletes the write port.
//
//   tools/tests/run_video2_tb.sh [--rom FILE]

module video2_tb;

  reg clk = 0;
  reg clk_pixel = 0;
  reg clk_5x = 0;
  reg rst_n = 0;
  reg enable = 0;

  always #5  clk = ~clk;              // 100 MHz master
  always #2  clk_pixel = ~clk_pixel;  // 250 MHz pixel: fast enough to drain a frame
  always #1  clk_5x = ~clk_5x;

  localparam integer CYCLES = 80000000;

  reg [1023:0] hex_path;

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

  // ------------------------------------------------------------- snes2hdmi
  wire pause_snes;
  wire [7:0] ovl_x, ovl_y;
  wire [2:0] tmds; wire tmds_clk;
  wire tmds_clk_p, tmds_clk_n;
  wire [2:0] tmds_d_p, tmds_d_n;
  wire audio_en;
  wire [23:0] tap_rgb;
  wire        tap_de;
  wire [7:0]  tap_x, tap_y;
  wire        tap_active, tap_we;
  wire [12:0] tap_waddr;
  integer n_active = 0, n_we = 0, n_de = 0, n_xx = 0;

  snes2hdmi s2h (
    .clk(clk), .resetn(rst_n), .snes_refresh(SNES_REFRESH),
    .dotclk(DOTCLK), .hblank(~HDE), .vblank(~VDE), .rgb5(RGB_OUT),
    .xs(X_OUT), .ys(Y_OUT),
    .overlay(1'b0), .overlay_x(ovl_x), .overlay_y(ovl_y), .overlay_color(15'h0000),
    .audio_l(AUDIO_L), .audio_r(AUDIO_R),
    .audio_ready(AUDIO_READY), .audio_en(audio_en),
    .clk_pixel(clk_pixel), .clk_5x_pixel(clk_5x), .locked(1'b1),
    .pause_snes_for_frame_sync(pause_snes),
    .tmds_clk_n(tmds_clk_n), .tmds_clk_p(tmds_clk_p),
    .tmds_d_n(tmds_d_n), .tmds_d_p(tmds_d_p),
    .tap_rgb(tap_rgb), .tap_de(tap_de), .tap_x(tap_x), .tap_y(tap_y),
    .tap_active(tap_active), .tap_we(tap_we), .tap_waddr(tap_waddr)
  );

  // ------------------------------------------------------------ capture
  reg [23:0] fb [0:256*224-1];
  reg        got [0:256*224-1];
  integer k, wr = 0, cols = 0, rows = 0;
  reg [255:0] xs_seen, ys_seen;
  integer cyc = 0;

  initial begin
    for (k = 0; k < 256*224; k = k + 1) begin
      fb[k] = 24'h000000;
      got[k] = 1'b0;
    end
    xs_seen = 256'b0;
    ys_seen = 256'b0;
  end

  always @(posedge clk_pixel) begin
    if (tap_active) n_active = n_active + 1;
    if (tap_we) n_we = n_we + 1;
    if (tap_de) n_de = n_de + 1;
    if (tap_x != 0) n_xx = n_xx + 1;
    if (tap_de) begin
      fb[tap_y*256 + tap_x] = tap_rgb;
      got[tap_y*256 + tap_x] = 1'b1;
      wr = wr + 1;
      xs_seen[tap_x] = 1'b1;
      ys_seen[tap_y] = 1'b1;
    end
  end

  always @(posedge clk) begin
    cyc <= cyc + 1;
    if (cyc == CYCLES) begin
      cols = 0; rows = 0;
      for (k = 0; k < 256; k = k + 1) begin
        if (xs_seen[k]) cols = cols + 1;
        if (ys_seen[k]) rows = rows + 1;
      end
      $display("");
      $display("video2 bench (SNES + real snes2hdmi line buffer)");
      $display("  visible pixels captured: %0d", wr);
      $display("  distinct columns: %0d   distinct rows: %0d", cols, rows);
      $display("  px clocks: active=%0d  A-we=%0d  de=%0d  xx!=0=%0d  last waddr=%04X",
               n_active, n_we, n_de, n_xx, tap_waddr);
      dump;
      if (cols < 2)       $display("FAIL  no horizontal extent: the buffer was never written across a line.");
      else if (rows < 2)  $display("FAIL  no vertical extent.");
      else if (wr < 256*224/2) $display("FAIL  only %0d of %0d pixels captured.", wr, 256*224);
      else                $display("PASS  snes2hdmi rendered the core's picture through its real line buffer.");
      $finish;
    end
  end

  integer fd, x, y, n;
  task dump;
    begin
      fd = $fopen("frame_0.ppm", "w");
      $fwrite(fd, "P6\n256 224\n255\n");
      for (y = 0; y < 224; y = y + 1)
        for (x = 0; x < 256; x = x + 1) begin
          n = y*256 + x;
          $fwrite(fd, "%c%c%c", fb[n][23:16], fb[n][15:8], fb[n][7:0]);
        end
      $fclose(fd);
      $display("  wrote frame_0.ppm");
    end
  endtask

  initial begin
    if (!$value$plusargs("hex=%s", hex_path)) hex_path = "rom.hex";
    for (i = 0; i < 1048576; i = i + 1) rom[i] = 8'hFF;
    $display("loading cartridge from %0s", hex_path);
    $readmemh(hex_path, rom);
    for (i = 0; i < 131072; i = i + 1) wram[i] = 8'h00;
    for (i = 0; i < 65536;  i = i + 1) begin vram[i] = 8'h00; aram[i] = 8'h00; end
    repeat (20) @(posedge clk);
    rst_n <= 1'b1;
    repeat (20) @(posedge clk);
    enable <= 1'b1;
    $display("enable raised, running to %0d master clocks", CYCLES);
  end

endmodule
