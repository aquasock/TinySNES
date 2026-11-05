`timescale 1ns/1ps

// Boot-screen bench: what does snes2hdmi draw when no cartridge is loaded?
//
// Before this bench existed the answer was taken from the panel.  The failure
// that made a bench worth writing is that the old power-up picture was a ramp
// the line buffer's `initial` block installs, so "the screen shows a pattern"
// said nothing about whether the boot screen had drawn or the buffer had simply
// never been written.  Here the module's own pixel output is captured and the
// bar pattern is checked arithmetically.
//
// The HDMI serialiser is replaced by hdmi_stub.sv, whose raster is deterministic
// from reset, so the bench can mirror cx/cy exactly and know which pixel it is
// looking at.  Everything between the boot-screen decision and the serialiser is
// the real code.
//
// Two runs are made, and the second is the one that matters for regressions:
//   rom_loaded = 0  -> eight equal vertical colour bars across the active raster
//   rom_loaded = 1  -> bars gone, the module falls through to its normal path
//
//   tools/tests/run_bootscreen_tb.sh

module bootscreen_tb;

    localparam integer TOTALW = 1650;
    localparam integer TOTALH = 750;
    localparam integer ROW    = 400;      // a row well inside the active area

    // The eight bars, in order, with the siblings' on 0xC0 / off 0x10 levels.
    // Every channel is independently 0xC0 when its bar bit is on and 0x10 when
    // it is off, which is what `r_on ? 192 : 16` produces in TinyNES and TinyGBC
    // -- so an off channel is 0x10, not 0x00, and the bars are not fully
    // saturated primaries.  white, yellow, cyan, green, magenta, red, blue, black
    localparam [23:0] BAR0 = 24'hC0C0C0;
    localparam [23:0] BAR1 = 24'hC0C010;
    localparam [23:0] BAR2 = 24'h10C0C0;
    localparam [23:0] BAR3 = 24'h10C010;
    localparam [23:0] BAR4 = 24'hC010C0;
    localparam [23:0] BAR5 = 24'hC01010;
    localparam [23:0] BAR6 = 24'h1010C0;
    localparam [23:0] BAR7 = 24'h101010;

    reg clk_pixel = 0;
    reg clk_5x    = 0;
    reg clk       = 0;
    reg resetn    = 0;
    reg rom_loaded = 0;

    always #3  clk_pixel = ~clk_pixel;
    always #1  clk_5x    = ~clk_5x;
    always #10 clk       = ~clk;

    // ---------------------------------------------------------------- DUT
    wire pause_snes;
    wire audio_en;
    wire [7:0] ovl_x, ovl_y;
    wire tmds_clk_p, tmds_clk_n;
    wire [2:0] tmds_d_p, tmds_d_n;
    wire [23:0] tap_rgb;
    wire tap_de;

    snes2hdmi dut (
        .clk(clk), .resetn(resetn), .snes_refresh(1'b0),
        .rom_loaded(rom_loaded),
        .dotclk(1'b0), .hblank(1'b1), .vblank(1'b1), .rgb5(15'h0000),
        .xs(9'h000), .ys(9'h000),
        .overlay(1'b0), .overlay_x(ovl_x), .overlay_y(ovl_y),
        .overlay_color(15'h0000),
        .desk_on(1'b0), .desk_wr_tog(1'b0), .desk_wr_addr(12'd0), .desk_wr_data(37'd0),
        .audio_l(16'h0000), .audio_r(16'h0000),
        .audio_ready(1'b0), .audio_en(audio_en),
        .clk_pixel(clk_pixel), .clk_5x_pixel(clk_5x), .locked(1'b1),
        .pause_snes_for_frame_sync(pause_snes),
        .dbg(3'b000), .bist_mask(16'h0000),
        .tmds_clk_n(tmds_clk_n), .tmds_clk_p(tmds_clk_p),
        .tmds_d_n(tmds_d_n), .tmds_d_p(tmds_d_p),
        .tap_rgb(tap_rgb), .tap_de(tap_de)
    );

    // ------------------------------------------------- raster mirror
    // Identical to hdmi_stub's counter, reset by the same signal, so the bench
    // knows which (cx, cy) the colour it captured belongs to.
    reg [10:0] mcx = 0;
    reg [9:0]  mcy = 0;
    always @(posedge clk_pixel) begin
        if (!resetn) begin
            mcx <= 0;
            mcy <= 0;
        end else if (mcx == TOTALW - 1) begin
            mcx <= 0;
            mcy <= (mcy == TOTALH - 1) ? 10'd0 : mcy + 1'b1;
        end else begin
            mcx <= mcx + 1'b1;
        end
    end

    // ------------------------------------------------------------ capture
    reg [23:0] line [0:TOTALW-1];
    // rgb holds the colour computed from the previous raster position, so the
    // position is delayed one clock to match it.  A one-pixel misalignment would
    // not change any verdict here, but the delay keeps the reported boundaries
    // honest.
    reg [10:0] pxc = 0;
    reg [9:0]  pyc = 0;
    reg        line_valid = 0;

    always @(posedge clk_pixel) begin
        pxc <= mcx;
        pyc <= mcy;
        line_valid <= (pyc == ROW);
        if (pxc < TOTALW)
            line[pxc] <= tap_rgb;
    end

    // ------------------------------------------------------------ checking
    integer errors = 0;

    task check(input bit cond, input [8*72-1:0] what);
        begin
            if (!cond) begin
                errors = errors + 1;
                $display("FAIL  %0s", what);
            end else begin
                $display("ok    %0s", what);
            end
        end
    endtask

    // Walk the captured row and report the runs it is made of.  Runs are
    // reported rather than asserted at fixed columns, because the point is the
    // structure -- eight equal bars in a known order -- and that is what the
    // siblings' generators produce too.
    integer x;
    reg [23:0] cur;
    reg [23:0] expect_bar [0:7];
    integer runs;
    integer run_start;
    integer run_len;
    integer i;
    integer px_bad;

    task analyse(input bit expect_bars);
        begin
            expect_bar[0] = BAR0; expect_bar[1] = BAR1;
            expect_bar[2] = BAR2; expect_bar[3] = BAR3;
            expect_bar[4] = BAR4; expect_bar[5] = BAR5;
            expect_bar[6] = BAR6; expect_bar[7] = BAR7;

            runs = 0;
            cur  = line[0];
            run_start = 0;
            for (x = 1; x < 1280; x = x + 1) begin
                if (line[x] !== cur) begin
                    run_len = x - run_start;
                    $display("      bar %0d: x %0d..%0d  width %0d  colour %06h",
                             runs, run_start, x - 1, run_len, cur);
                    if (expect_bars) begin
                        check(runs < 8, "at most eight bars on the row");
                        if (runs < 8) begin
                            check(cur === expect_bar[runs],
                                  "bar colour is the expected one");
                            check(run_len >= 158 && run_len <= 162,
                                  "bar width is one eighth of active");
                        end
                    end
                    runs = runs + 1;
                    cur  = line[x];
                    run_start = x;
                end
            end
            run_len = 1280 - run_start;
            $display("      bar %0d: x %0d..%0d  width %0d  colour %06h",
                     runs, run_start, 1279, run_len, cur);
            if (expect_bars) begin
                check(runs < 8, "at most eight bars on the row");
                if (runs < 8) begin
                    check(cur === expect_bar[runs], "last bar colour is expected");
                    check(run_len >= 158 && run_len <= 162,
                          "last bar width is one eighth of active");
                end
                runs = runs + 1;
                check(runs == 8, "the row is exactly eight bars");
            end
        end
    endtask

    integer k;
    initial begin
        for (k = 0; k < TOTALW; k = k + 1) line[k] = 24'h000000;

        $display("bootscreen bench: pre-cartridge picture and its removal on load");

        // --- run 1: no cartridge -> bars
        resetn = 0; rom_loaded = 0;
        repeat (16) @(posedge clk_pixel);
        resetn = 1;
        // One whole frame, plus slack for the two-flop synchroniser and the
        // line we capture.
        repeat (TOTALW * (TOTALH + 4)) @(posedge clk_pixel);

        $display("  rom_loaded = 0:");
        analyse(1'b1);
        check(line[0]   !== BAR7, "row does not begin with the black bar");
        check(line[1279] === BAR7, "row ends with the black bar");

        // Every colour on the row must be one of the eight, so a partially
        // drawn screen or a leftover line-buffer ramp cannot pass.
        for (x = 0; x < 1280; x = x + 1) begin
            if (line[x] !== BAR0 && line[x] !== BAR1 && line[x] !== BAR2 &&
                line[x] !== BAR3 && line[x] !== BAR4 && line[x] !== BAR5 &&
                line[x] !== BAR6 && line[x] !== BAR7) begin
                errors = errors + 1;
                $display("FAIL  x %0d holds %06h, which is not a bar colour", x, line[x]);
                x = 1280;
            end
        end
        if (errors == 0) $display("ok    every pixel on the row is a bar colour");

        // --- run 2: cartridge loaded -> bars must be gone
        rom_loaded = 1;
        repeat (TOTALW * (TOTALH + 4)) @(posedge clk_pixel);

        $display("  rom_loaded = 1:");
        k = 0;
        for (i = 0; i < 1280; i = i + 1)
            if (line[i] === BAR0 || line[i] === BAR1 || line[i] === BAR2 ||
                line[i] === BAR3 || line[i] === BAR4 || line[i] === BAR5 ||
                line[i] === BAR6) k = k + 1;
        check(k == 0, "no colour bar survives once a cartridge is loaded");

        // --- pillarbox: outside the 4:3 picture the area is black, as the
        // siblings draw it, not the grey this core used to show.  The picture
        // occupies x 160..1119 (XSTART to XSTOP in snes2hdmi), so those two bands
        // are the only places a pillarbox colour can appear.
        px_bad = 0;
        for (i = 0; i < 160; i = i + 1)
            if (line[i] !== 24'h000000) px_bad = px_bad + 1;
        for (i = 1120; i < 1280; i = i + 1)
            if (line[i] !== 24'h000000) px_bad = px_bad + 1;
        if (px_bad == 0)
            $display("ok    pillarbox is black on both sides");
        else begin
            errors = errors + 1;
            $display("FAIL  %0d pillarbox pixels are not black (left %06h, right %06h)",
                     px_bad, line[20], line[1260]);
        end

        $display("");
        if (errors == 0) $display("PASS  boot screen draws eight colour bars with no cartridge, and clears on load");
        else             $display("FAIL  %0d check(s) failed", errors);
        $finish;
    end

endmodule
