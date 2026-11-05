`timescale 1ns/1ps

// TinyDesk bench: does snes2hdmi draw the desk exactly as TinyTang painted it?
//
// The real snes2hdmi and desk_layer run against hdmi_stub's raster.  Cells are
// written the way iosys_bl616 writes them -- on the machine clock, a toggle with
// the address and data already set -- and every pixel of a whole frame is then
// compared with a model built from the same cells and the same font file.  A
// pipeline that is a pixel early or late, a swapped colour channel, or a glyph
// mirrored left to right fails here at the first pixel, not on the panel.
//
// The sequence checks the switching rule too: the desk turned on in the middle
// of a frame must leave that frame alone and own the whole next one, and turned
// off it must hand the next frame back to what was under it (the boot screen,
// with no cartridge loaded).
//
//   tools/tests/run_desk_tb.sh

module desk_tb;

    localparam integer TOTALW = 1650;
    localparam integer TOTALH = 750;
    localparam integer W = 1280, H = 720;
    localparam integer CELLS = 80 * 45;

    reg clk_pixel = 0;
    reg clk_5x    = 0;
    reg clk       = 0;
    reg resetn    = 0;

    always #3  clk_pixel = ~clk_pixel;
    always #1  clk_5x    = ~clk_5x;
    always #23 clk       = ~clk;          // ~21.7 MHz, unrelated to the pixel clock

    reg desk_on = 0;
    reg desk_wr_tog = 0;
    reg [11:0] desk_wr_addr = 0;
    reg [36:0] desk_wr_data = 0;

    wire pause_snes, audio_en;
    wire [7:0] ovl_x, ovl_y;
    wire tmds_clk_p, tmds_clk_n;
    wire [2:0] tmds_d_p, tmds_d_n;
    wire [23:0] tap_rgb;
    wire tap_de;

    snes2hdmi dut (
        .clk(clk), .resetn(resetn), .snes_refresh(1'b0),
        .rom_loaded(1'b0),
        .dotclk(1'b0), .hblank(1'b1), .vblank(1'b1), .rgb5(15'h0000),
        .xs(9'h000), .ys(9'h000),
        .overlay(1'b0), .overlay_x(ovl_x), .overlay_y(ovl_y),
        .overlay_color(15'h0000),
        .desk_on(desk_on), .desk_wr_tog(desk_wr_tog), .desk_wr_addr(desk_wr_addr),
        .desk_wr_data(desk_wr_data),
        .audio_l(16'h0000), .audio_r(16'h0000),
        .audio_ready(1'b0), .audio_en(audio_en),
        .clk_pixel(clk_pixel), .clk_5x_pixel(clk_5x), .locked(1'b1),
        .pause_snes_for_frame_sync(pause_snes),
        .dbg(3'b000), .bist_mask(16'h0000),
        .tmds_clk_n(tmds_clk_n), .tmds_clk_p(tmds_clk_p),
        .tmds_d_n(tmds_d_n), .tmds_d_p(tmds_d_p),
        .tap_rgb(tap_rgb), .tap_de(tap_de)
    );

    // ------------------------------------------------------------ model
    reg [7:0] font [0:1023];
    reg [36:0] cells [0:CELLS-1];
    initial $readmemh(`TINYSNES_DESK_FONT, font);

    function [23:0] expand(input [14:0] c);
        expand = {c[4:0], c[4:2], c[9:5], c[9:7], c[14:10], c[14:12]};
    endfunction

    function [23:0] model(input integer x, input integer y);
        reg [36:0] cv;
        reg [7:0] g;
        begin
            cv = cells[(y / 16) * 80 + x / 16];
            g = font[{cv[36:30], 3'(y / 2 % 8)}];
            model = expand(g[x / 2 % 8] ? cv[29:15] : cv[14:0]);
        end
    endfunction

    // The boot screen's first bar, which the desk must not be mistaken for.
    localparam [23:0] BAR0 = 24'hC0C0C0;

    // ----------------------------------------------------- raster mirror
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

    // rgb is registered from cx, so it belongs to the position one clock ago.
    reg [10:0] pxc = 0;
    reg [9:0]  pyc = 0;
    always @(posedge clk_pixel) begin
        pxc <= mcx;
        pyc <= mcy;
    end

    // ---------------------------------------------------------- checking
    // mode 0: not counting; 1: every active pixel must be the desk;
    // 2: no active pixel may be the desk (the boot bars must show instead).
    integer mode = 0;
    integer bad = 0, seen = 0;
    always @(negedge clk_pixel) begin
        if (mode != 0 && pxc < W && pyc < H) begin
            seen = seen + 1;
            if (mode == 1 ? tap_rgb !== model(pxc, pyc)
                          : (pxc < 160 && tap_rgb !== BAR0)) begin
                if (bad < 8)
                    $display("  pixel (%0d,%0d) = %06h, expected %06h", pxc, pyc, tap_rgb,
                             mode == 1 ? model(pxc, pyc) : BAR0);
                bad = bad + 1;
            end
        end
    end

    integer errors = 0;
    task check(input bit cond, input [8*72-1:0] what);
        begin
            if (!cond) begin
                errors = errors + 1;
                $display("FAIL  %0s", what);
            end else
                $display("ok    %0s", what);
        end
    endtask

    // Wait for the raster to reach (x, y) as the captured position.  Returns
    // just after a rising edge, so the checker's next falling edge is (x, y)
    // itself and a mode set here applies from that pixel on.
    task at(input integer x, input integer y);
        begin
            @(posedge clk_pixel); #1;
            while (!(pxc == x && pyc == y)) begin
                @(posedge clk_pixel); #1;
            end
        end
    endtask

    task frame(input integer m, input [8*48-1:0] what);
        begin
            at(0, 0);
            bad = 0; seen = 0; mode = m;
            at(0, H);
            mode = 0;
            check(bad == 0 && seen == W * H, what);
            if (bad != 0) $display("  %0d of %0d pixels wrong", bad, seen);
        end
    endtask

    // A cv write the way iosys_bl616 makes it: address and data, then the
    // toggle, all on the machine clock, held for longer than the crossing.
    task write_cell(input integer a, input [36:0] d);
        begin
            @(posedge clk);
            desk_wr_addr <= a;
            desk_wr_data <= d;
            desk_wr_tog <= ~desk_wr_tog;
            repeat (12) @(posedge clk);
            cells[a] = d;
        end
    endtask

    integer i;
    reg [14:0] fg, bg;
    initial begin
        $display("desk bench: snes2hdmi + desk_layer, 80x45 cells at 16x16");
        repeat (16) @(posedge clk_pixel);
        resetn = 1;

        // Every glyph, and colours that differ in every channel so a swap of
        // red and blue or a dropped bit shows.
        for (i = 0; i < CELLS; i = i + 1) begin
            fg = 15'(i * 37 + 5) ^ 15'h7c1f;
            bg = 15'(i * 11);
            write_cell(i, {7'(i * 7 + 3), fg, bg});
        end

        frame(2, "desk off: boot screen untouched");

        // On in the middle of a frame: that frame stays, the next is the desk.
        at(0, 300);
        desk_on = 1;
        at(0, 301);
        bad = 0; seen = 0; mode = 2;
        at(0, H);
        mode = 0;
        check(bad == 0, "desk on mid-frame: rest of that frame untouched");
        frame(1, "desk frame matches the model pixel for pixel");

        // A cv changed while shown appears in the next frame.
        write_cell(45 * 80 - 1, {7'h41, 15'h7fff, 15'h0000});
        write_cell(0, {7'h00, 15'h0000, 15'h001f});
        frame(1, "rewritten cells shown, first and last");

        // Off mid-frame: that frame is still the desk, the next is not.
        at(0, 200);
        desk_on = 0;
        at(0, 201);
        bad = 0; seen = 0; mode = 1;
        at(0, H);
        mode = 0;
        check(bad == 0, "desk off mid-frame: rest of that frame still desk");
        frame(2, "desk off: boot screen back");

        if (errors == 0) $display("PASS: desk bench");
        else $display("FAIL: %0d desk check(s)", errors);
        $finish;
    end

    initial begin
        #400_000_000;
        $display("FAIL: desk bench timed out");
        $finish;
    end
endmodule
