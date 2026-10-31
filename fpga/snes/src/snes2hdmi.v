// NES video and sound to HDMI converter
// nand2mario, 2022.9

`timescale 1ns / 1ps

// The probe builds share one display: five stripes of 16 bars plus a status
// band.  Which fields the stripes carry belongs to snestang_top, which is where
// the two probes differ, so this file only needs to know that a probe is
// selected.  Defined here rather than with the other diagnostics because the
// port list above depends on it.
`ifdef TINYSNES_FETCH_PROBE
  `define TINYSNES_PROBE_BARS 1
`endif
`ifdef TINYSNES_CPU_PROBE
  `define TINYSNES_PROBE_BARS 1
`endif
`ifdef TINYSNES_TRACE_PROBE
  `define TINYSNES_PROBE_BARS 1
`endif
`ifdef TINYSNES_LIVE_PROBE
  `define TINYSNES_PROBE_BARS 1
  `define TINYSNES_PROBE_SPLIT 1
`endif
`ifdef TINYSNES_APU_PROBE
  `define TINYSNES_PROBE_BARS 1
`endif
`ifdef TINYSNES_IPL_PROBE
  `define TINYSNES_PROBE_BARS 1
`endif
`ifdef TINYSNES_LINK_PROBE
  `define TINYSNES_PROBE_BARS 1
`endif

// The two memory self-tests share one display, so they are folded into a single
// define rather than tested in one `elsif` expression.  `elsif A || B does NOT
// work here: with only B defined, slang resolves the whole expression false, so
// a build defining the second macro alone silently drew the production picture
// instead of the test result.  The nested form above for TINYSNES_PROBE_BARS is
// the shape that does work.
`ifdef TINYSNES_SDRAM_TEST
  `define TINYSNES_BIST_BARS 1
`endif
`ifdef TINYSNES_ARAM_TEST
  `define TINYSNES_BIST_BARS 1
`endif
`ifdef TINYSNES_READ_STABILITY
  `define TINYSNES_BIST_BARS 1
`endif
`ifdef TINYSNES_WRAM_TEST
  `define TINYSNES_BIST_BARS 1
`endif

module snes2hdmi (
	input clk,      // snes clock
	input resetn,

    // snes video and audio signals
    input dotclk,
    input hblank,
    input vblank,
    input [14:0] rgb5,
    input [8:0] xs, // {x,dotclk}
    input [8:0] ys, // {field,y}

    input overlay,
    output [7:0] overlay_x,
    output [7:0] overlay_y,
    input [14:0] overlay_color,

    input [15:0] audio_l,
    input [15:0] audio_r,
    input audio_ready,
    output audio_en,

    // frame-sync pause happens during snes_refresh
    input snes_refresh,

	// video clocks
	input clk_pixel,
	input clk_5x_pixel,
	input locked,

    output reg pause_snes_for_frame_sync,

    // TinySNES diagnostic: three machine-state bits shown as the border colour,
    // because the OSD text page is blank on this core and there is no other way
    // to see inside the machine from the bench.  Bit order: R = header_finished,
    // G = loaded, B = loading.
    input [2:0] dbg,

    // TinySNES diagnostic: per-DQ-bit result of sdram_bist, drawn as 16 bars
    // across the active area in the TINYSNES_SDRAM_TEST build.  Unused (and
    // tied off) in every other build.
    input [15:0] bist_mask,

`ifdef TINYSNES_PROBE_BARS
    // TinySNES diagnostic: five 16-bit fields of machine state, drawn as one
    // stripe each.  Present only under a probe define so the shipped core
    // carries no extra port.  The field order is set by the probe in
    // snestang_top.v and repeated in its comment:
    //   TINYSNES_FETCH_PROBE: ROM_Q at the first ROMSEL assertion, at +2 mclk,
    //     at +4 mclk, then ROM_ADDR[15:0] and ROM_ADDR[23:8] for that access
    //   TINYSNES_CPU_PROBE:   ROM access counter low and high halves, then PC at
    //     the most recent sample, SP, and the CPU's status byte from DBG_REG
    //     0x15 (7 GotInterrupt, 6 IsResetInterrupt, 5 IsNMIInterrupt,
    //     4 IsIRQInterrupt, 3 RDY_IN, 2 EN, 1 WAIExec, 0 STPExec)
    //   TINYSNES_TRACE_PROBE: the last four ROM addresses, newest first, then
    //     ROM_ADDR[23:8] of the newest
    //   TINYSNES_APU_PROBE:   CPUO ports 1 and 0, the 65816's A, the 65816's
    //     PC, the SPC700's PC, then the 65816's P above CPUI port 0
    //   TINYSNES_IPL_PROBE:   the SPC700 PC at the first sample outside the IPL
    //     ROM, then its live Y and A, the current SPC700 PC, CPUI ports 3 and 2,
    //     and CPUI ports 1 and 0
    //   TINYSNES_LINK_PROBE:  both directions of the APU link and both CPUs --
    //     CPUO ports 1 and 0, CPUI ports 1 and 0, the 65816's A and its PC, then
    //     the SPC700's Y, and in the top stripe a 3-bit count of sightings at
    //     $8888 above five bits: [4] the 65816 has been past the first handshake,
    //     [3] CPUI port 0 has ever held $CC, [2] CPUO has ever left $AA,
    //     [1] Y has ever been non-zero, [0] the SPC700's PC has ever been
    //     outside its IPL ROM
    input [79:0] probe_bus,
`endif

    // output [7:0] led,

	// output signals
	output       tmds_clk_n,
	output       tmds_clk_p,
	output [2:0] tmds_d_n,
	output [2:0] tmds_d_p
);

    localparam FRAMEWIDTH = 1280;       // 720P
    localparam FRAMEHEIGHT = 720;
    localparam TOTALWIDTH = 1650;
    localparam TOTALHEIGHT = 750;
    localparam SCALE = 5;
    localparam VIDEOID = 4;
    localparam VIDEO_REFRESH = 60.0;

    localparam IDIV_SEL_X5 = 3;
    localparam FBDIV_SEL_X5 = 54;
    localparam ODIV_SEL_X5 = 2;
    localparam DUTYDA_SEL_X5 = "1000";
    localparam DYN_SDIV_SEL_X5 = 2;
    
    localparam CLKFRQ = 74250;

    localparam AUDIO_BIT_WIDTH = 16;

    // video stuff
    wire [9:0] cy, frameHeight;
    wire [10:0] cx, frameWidth;
    reg active, r_active;
    wire [7:0] x, y;                    // SNES pixel position

    //
    // BRAM line buffer for 16 lines. Each pixel is 5:5:5 RGB
    // Each BRAM block holds 4 lines. So 16 lines needs 4 blocks.
    //
    localparam BUF_WIDTH = 5;        // 2 ^ BUF_WIDTH lines
    localparam BUF_SIZE = 1 << BUF_WIDTH;
    reg [14:0] mem [0:BUF_SIZE*256-1];
    reg [BUF_WIDTH+8-1:0] mem_portA_addr;
    reg [14:0] mem_portA_wdata;
    reg mem_portA_we;
    wire [BUF_WIDTH+8-1:0] mem_portB_addr;
    reg [14:0] mem_portB_rdata;
    reg mem_writeto = 1'b0;     // current line we are writing to. we read from the other line
   
    // We need to do a bit of synchronization as the SNES and HDMI run on separate clocks and they
    // do not align perfectly.
    // - Let SNES execute a bit faster (0.5%) than the HDMI stack. This way we always have enough pixels.
    // - For each frame, we let the SNES run until the first line is rendered, and written to line buffer.
    //   Then we pause the SNES and wait (through pause_snes_for_frame_sync) for HDMI to catch up.
    // - Once HDMI started the frame, start SNES again.
    reg sync_done = 1'b0;
    reg hdmi_first_line;
    reg pause_sync;     // pause for even number of cycles for PPU sdram access to stay in sync
    reg hdmi_first_line_r, hdmi_first_line_rr;
    always @(posedge clk) begin
        hdmi_first_line_r <= hdmi_first_line;
        hdmi_first_line_rr <= hdmi_first_line_r;
        if (pause_snes_for_frame_sync) pause_sync <= ~pause_sync;
        if (~sync_done) begin
            if (~pause_snes_for_frame_sync) begin
                if (ys[7:0] == 8'd1 && snes_refresh) begin      // halt SNES after first line is buffered
                    pause_snes_for_frame_sync <= 1'b1;
                    pause_sync <= 0;
                end
            end else if (hdmi_first_line_rr && pause_sync) begin                 // HDMI frame start, now resume SNES
                pause_snes_for_frame_sync <= 1'b0;
                sync_done <= 1'b1;
            end
        end else
            pause_snes_for_frame_sync <= 1'b0;
        if (ys[7:0] == 8'd200) sync_done <= 1'b0;               // reset sync_done for next frame
    end
    always @(posedge clk_pixel) begin
        if (cy == 0 && cx >= 11'd160)      
            hdmi_first_line <= 1;
        else
            hdmi_first_line <= 0;
    end

    // BRAM port A read/write
	always_ff @(posedge clk) begin
		if (mem_portA_we) begin
			mem[mem_portA_addr] <= mem_portA_wdata;
		end
	end

    // BRAM port B read
    always_ff @(posedge clk_pixel) begin
        mem_portB_rdata <= mem[mem_portB_addr];
    end

    integer j;
    initial begin
        // On power-up, fill line buffer with a gradient
        for (j = 0; j < 512; j=j+1) begin
            mem[j][14:10] = j;
            mem[j][9:5] = j;
            mem[j][4:0] = j;
        end
    end

    // 
    // Data input
    //
    reg r_dotclk, r_vblank, r_hblank;
    always @(posedge clk) begin
        r_dotclk <= dotclk;
        r_vblank <= vblank;
        mem_portA_we <= 1'b0;
        if (dotclk && ~r_dotclk && ~hblank && ~vblank && ys[7:0] < 224) begin       // on posedge of dotclk, read a pixel
            mem_portA_addr <= {ys[BUF_WIDTH-1:0], xs[8:1]};
            mem_portA_wdata <= rgb5;
            mem_portA_we <= 1'b1;
        end
    end

    always @(posedge clk) begin
        r_hblank <= hblank;
        if (hblank & ~r_hblank) begin       // flip active line on hblank
            mem_writeto <= ~mem_writeto;
        end
    end
    

    // HDMI TX audio - send 32K sampling rate audio
    // Hoarse sound issue: https://github.com/nand2mario/snestang/issues/16
    // SNES average framerate is 60.09881. So we need to pause the SNES a bit every frame to ensure 60 fps HDMI. 
    // For sound, that translate to about 8 samples pause time per frame. So we run our DSP a bit faster to 
    // buffer enough samples before the SNES pause.
    localparam AUDIO_OUT_RATE = 32000;
    localparam AUDIO_DELAY = CLKFRQ * 1000 / AUDIO_OUT_RATE / 2;
    reg [15:0] audio_sample_word [1:0];
    reg [$clog2(AUDIO_DELAY)-1:0] audio_divider;
    reg clk_audio;
    reg audio_rinc;
    wire audio_full, audio_empty;
    wire [31:0] audio_sample;

    always @(posedge clk_pixel) begin
        if (resetn) begin
            audio_rinc <= 0;
            if (audio_divider != AUDIO_DELAY - 1) 
                audio_divider <= audio_divider + 1;
            else begin 
                audio_divider <= 0;
                clk_audio = ~clk_audio;     // generate audio clock @ 32Khz
                // output audio sample on posedge clk_audio
                if (!clk_audio && !audio_empty) begin
                    {audio_sample_word[0], audio_sample_word[1]} <= audio_sample;
                    audio_rinc <= 1'b1;                    
                end
            end
        end
    end

    // Audio sample FIFO for 16 samples
    dual_clk_fifo #(.DATESIZE(32), .ADDRSIZE(4)) audio_fifo (
        .clk(clk), .wrst_n(1'b1), 
        .winc(audio_ready), .wdata({audio_l, audio_r}), .wfull(audio_full),
        .rclk(clk_pixel), .rrst_n(1'b1),
        .rinc(audio_rinc), .rdata(audio_sample), .rempty(audio_empty),
        .almost_full(), .almost_empty()
    );

    //
    // Video
    //
    reg [23:0] rgb;             // actual RGB output
    // TinySNES: `active` is declared once, above, at line 68.  Gowin's
    // synthesiser tolerated the second declaration; slang rejects it.
    reg [7:0] xx;               // scaled-down pixel position
    reg [7:0] yy;
    reg [10:0] xcnt;
    reg [10:0] ycnt;            // fractional scaling counters
    reg [9:0] cy_r;
    assign mem_portB_addr = {yy[BUF_WIDTH-1:0], xx};
    assign overlay_x = xx;
    assign overlay_y = yy;
    localparam XSTART = (1280 - 960) / 2;   // 960:720 = 4:3
    localparam XSTOP = (1280 + 960) / 2;

    // address calculation
    // Assume the video occupies fully on the Y direction, we are upscaling the video by `720/height`.
    // xcnt and ycnt are fractional scaling counters.
    always @(posedge clk_pixel) begin
        reg active_t;
        reg [10:0] xcnt_next;
        reg [10:0] ycnt_next;
        xcnt_next = xcnt + 256;
        ycnt_next = ycnt + 224;

        active_t = 0;
        if (cx == XSTART - 1) begin
            active_t = 1;
            active <= 1;
        end else if (cx == XSTOP - 1) begin
            active_t = 0;
            active <= 0;
        end

        if (active_t | active) begin        // increment xx
            xcnt <= xcnt_next;
            if (xcnt_next >= 960) begin
                xcnt <= xcnt_next - 960;
                xx <= xx + 1;
            end
        end

        cy_r <= cy;
        if (cy[0] != cy_r[0]) begin         // increment yy at new lines
            ycnt <= ycnt_next;
            if (ycnt_next >= 720) begin
                ycnt <= ycnt_next - 720;
                yy <= yy + 1;
            end
        end

        if (cx == 0) begin
            xx <= 0;
            xcnt <= 0;
        end
        
        if (cy == 0) begin
            yy <= 0;
            ycnt <= 0;
        end 

    end

`ifdef TINYSNES_PROBE_BARS
    // Pick the stripe this row belongs to.  yy[7:5] selects a 32-row block and
    // the bottom 8 rows of each block are the gap, so every stripe is 24 rows
    // of bars.  Five blocks are used; block 5 is left black and block 6 is the
    // status band.
    reg [15:0] fp_stripe;
    always @(*) begin
        case (yy[7:5])
            3'd0: fp_stripe = probe_bus[15:0];
            3'd1: fp_stripe = probe_bus[31:16];
            3'd2: fp_stripe = probe_bus[47:32];
            3'd3: fp_stripe = probe_bus[63:48];
            3'd4: fp_stripe = probe_bus[79:64];
            default: fp_stripe = 16'd0;
        endcase
    end
`endif

`ifdef TINYSNES_PROBE_SPLIT
    // The split build draws over the machine's own picture instead of replacing
    // it, so the two stripes it shows are selected here: the top 32 rows carry
    // probe_bus[15:0] and the next 32 rows probe_bus[47:32].
    wire [15:0] live_stripe = yy[5] ? probe_bus[47:32] : probe_bus[15:0];
`endif

    // calc rgb value to hdmi
    always @(posedge clk_pixel) begin
        if (active) begin
`ifdef TINYSNES_PROBE_SPLIT
            // Diagnostic build: the machine's picture with the probe laid over
            // its top 64 rows, so one screenshot shows both what the CPU is
            // doing and what the PPU is drawing.  Bars are 16 pixels wide with
            // a 2-pixel gap, green = 1 and red = 0, and both fields are latched
            // every 0.2 s by the sampler so they can be photographed.
            if (yy < 8'd64)
                rgb <= (xx[3:0] > 4'd13) ? 24'h000000
                                         : (live_stripe[xx[7:4]] ? 24'h00C000 : 24'hC00000);
            else if (overlay)
                rgb <= {overlay_color[4:0],3'b0,overlay_color[9:5],3'b0,overlay_color[14:10],3'b0};
            else
                rgb <= {mem_portB_rdata[4:0], 3'b0, mem_portB_rdata[9:5], 3'b0, mem_portB_rdata[14:10], 3'b0};
`elsif TINYSNES_OVERLAY_ONLY
            // Diagnostic build: the overlay path only, no line-buffer BRAM read,
            // so the picture proves the raster and the overlay meter without
            // involving the SNES-side clock domain.
            rgb <= overlay ? {overlay_color[4:0],3'b0,overlay_color[9:5],3'b0,overlay_color[14:10],3'b0}
                           : 24'h101010;
`elsif TINYSNES_TEST_PATTERN
            // Diagnostic build: fixed vertical colour bars every 16 pixels, so a
            // picture proves the HDMI plumbing (PLL, OSER10s, ELVDS, packets)
            // independently of the SNES machine and the overlay.  Never in a
            // core meant to play a game.
            rgb <= {xx[7:5]==3'd0 ? 8'hFF : 8'h00,
                    xx[7:5]==3'd1 ? 8'hFF : (xx[7:5]==3'd3 ? 8'hC0 : 8'h00),
                    xx[7:5]==3'd2 ? 8'hFF : 8'h00};
`elsif TINYSNES_BIST_BARS
            // Diagnostic build: one bar per SDRAM data bit, 16 pixels apart with a
            // 2-pixel black gap between bars so a run of same-coloured bars can
            // never read as one block.  bist_mask is a MISMATCH mask, so a set bit
            // is drawn red (that bit was wrong at least once) and a clear bit
            // green (it read back correctly at every test address).  The bottom
            // 32 rows are a solid status band in the dbg colour.  Under
            // TINYSNES_ARAM_TEST the same 16 bits are the two byte lanes of the
            // ARAM port, bits 0-7 even and 8-15 odd, which is why one display
            // serves both tests.
            if (yy[7:5] == 3'd6)
                rgb <= {dbg[2] ? 8'hC0 : 8'h00, dbg[1] ? 8'hC0 : 8'h00, dbg[0] ? 8'hC0 : 8'h00};
            else if (xx[3:0] > 4'd13)
                rgb <= 24'h000000;
            else
                rgb <= bist_mask[xx[7:4]] ? 24'hC00000 : 24'h00C000;
`elsif TINYSNES_PROBE_BARS
            // Diagnostic build: five stripes of 16 bars, left to right = bit
            // 0..15, green = 1 and red = 0, 16 pixels per bar with a 2-pixel
            // gap.  What each stripe is belongs to the probe build: under
            // TINYSNES_FETCH_PROBE the top three are ROM_Q at the first ROMSEL
            // assertion and two and four mclk later, so three identical red
            // stripes mean the sample is stale at every point while red, red,
            // correct means the data only arrives late; the last two are the
            // mapper's ROM_ADDR halves.  Under TINYSNES_CPU_PROBE they are the
            // ROM access counter and the CPU's program counter, so a counter
            // that stands still and a PC that does not move mean the CPU is not
            // executing.  Under TINYSNES_TRACE_PROBE they are the last four ROM
            // addresses the CPU asked for, newest in the top stripe, and the
            // high half of the newest, so a machine that has left the ROM shows
            // the fetches it made just before that.  The band in rows 192-223 is
            // R = fetch_seen, pc_changed or a recent ROM access depending on the
            // probe, G = loaded, B = enable.
            if (yy[7:5] == 3'd6)                        // status band
                rgb <= {dbg[2] ? 8'hC0 : 8'h00, dbg[1] ? 8'hC0 : 8'h00, dbg[0] ? 8'hC0 : 8'h00};
            else if (yy[7:5] > 3'd4 || yy[4:3] == 2'b11 || xx[3:0] > 4'd13)
                rgb <= 24'h000000;                      // unused rows, stripe gaps, bar gaps
            else
                rgb <= fp_stripe[xx[7:4]] ? 24'h00C000 : 24'hC00000;
`elsif TINYSNES_LOAD_COUNT
            // Diagnostic build: eight thresholds on the loader's SDRAM write
            // count, left to right >=1, >=16, >=256, >=4096, >=32768, >=131072,
            // >=262144, >=500000.  Green = that threshold was reached.
            rgb <= (xx[4:0] > 5'd29) ? 24'h000000
                                     : (bist_mask[xx[7:5]] ? 24'h00C000 : 24'hC00000);
`elsif TINYSNES_ROM_CHECK
            // Diagnostic build: eight fat bars, one per ROM word the probe read
            // back from SDRAM.  Green = that word matched the loaded image,
            // red = it did not.
            rgb <= (xx[4:0] > 5'd29) ? 24'h000000
                                     : (bist_mask[xx[7:5]] ? 24'hC00000 : 24'h00C000);
`else
            if (overlay)
                rgb <= {overlay_color[4:0],3'b0,overlay_color[9:5],3'b0,overlay_color[14:10],3'b0};       // BGR5 to RGB8
            else
                rgb <= {mem_portB_rdata[4:0], 3'b0, mem_portB_rdata[9:5], 3'b0, mem_portB_rdata[14:10], 3'b0};                
`endif
        end else
`ifdef TINYSNES_DBG_BORDER
            rgb <= {dbg[2] ? 8'hFF : 8'h00, dbg[1] ? 8'hFF : 8'h00, dbg[0] ? 8'hFF : 8'h00};
`else
            rgb <= 24'h303030;
`endif
    end

    // HDMI output.
    logic[2:0] tmds;

    hdmi #( .VIDEO_ID_CODE(VIDEOID), 
            .DVI_OUTPUT(0), 
            .VIDEO_REFRESH_RATE(VIDEO_REFRESH),
            .IT_CONTENT(1),
            .AUDIO_RATE(AUDIO_OUT_RATE), 
            .AUDIO_BIT_WIDTH(AUDIO_BIT_WIDTH),
            .START_X(0),
            .START_Y(0) )

    hdmi( .clk_pixel_x5(clk_5x_pixel), 
          .clk_pixel(clk_pixel), 
          .clk_audio(clk_audio),
          .rgb(rgb), 
          .reset( ~resetn ),
          .audio_sample_word(audio_sample_word),
          .tmds(tmds), 
          .tmds_clock(tmdsClk), 
          .cx(cx), 
          .cy(cy),
          .frame_width( frameWidth ),
          .frame_height( frameHeight ) );

    // Gowin LVDS output buffer
    ELVDS_OBUF tmds_bufds [3:0] (
        .I({clk_pixel, tmds}),
        .O({tmds_clk_p, tmds_d_p}),
        .OB({tmds_clk_n, tmds_d_n})
    );

endmodule
