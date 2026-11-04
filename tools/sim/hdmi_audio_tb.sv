// SPDX-License-Identifier: MIT
//
// Standalone bench for the HDMI audio path: dual_clk_fifo plus
// hdmi_audio_clock, fed the way the board feeds them.
//
// Production follows the machine (see i2s_out_tb.sv): CEGen adds 411904 per
// mclk against 2147730, one sample per 128 CEs, and CEGen is held in reset
// while the SNES is paused.  The SNES pauses after each 357,366-mclk frame
// until the next HDMI frame starts; HDMI frames come from the pixel clock
// (1650 x 750 at 74.25 MHz), so +ppm=N offsets the two crystals.
//
// Samples are a counter, so the reader can check that every one arrives
// exactly once: a drop or a repeat is a click.
//
//   tools/sim/run_hdmi_audio.sh [+secs=N] [+ppm=N]
//
// Prints samples in and out, overflows (write while full), underruns (an
// audio clock period with no new sample), drops/repeats, the FIFO level range
// and the audio clock's rate range over 0.1 s windows, both after 1 s.

`timescale 1ps/1ps

module hdmi_audio_tb;
    real ppm = 0.0;
    real pix_half;
    integer secs = 3;

    reg clk = 1'b0;                         // mclk, 21,505,376 Hz
    always #23250 clk = ~clk;
    reg clk_pixel = 1'b0;
    initial begin
        void'($value$plusargs("secs=%d", secs));
        void'($value$plusargs("ppm=%f", ppm));
        pix_half = 1.0e12 / 74.25e6 / 2.0 / (1.0 + ppm * 1.0e-6);
        forever #(pix_half) clk_pixel = ~clk_pixel;
    end

    reg resetn = 1'b0;
    reg [15:0] audio_l = 16'd0, audio_r = 16'd0;
    reg audio_ready = 1'b0;

    wire audio_full, audio_empty;
    wire [31:0] audio_sample;
    wire [4:0] audio_level;
    wire clk_audio, audio_rinc;
    wire [15:0] word_l, word_r;

    dual_clk_fifo #(.DATESIZE(32), .ADDRSIZE(4)) fifo (
        .clk(clk), .wrst_n(1'b1),
        .winc(audio_ready), .wdata({audio_l, audio_r}), .wfull(audio_full),
        .rclk(clk_pixel), .rrst_n(1'b1),
        .rinc(audio_rinc), .rdata(audio_sample), .rempty(audio_empty),
        .almost_full(), .almost_empty(), .rlevel(audio_level)
    );

    hdmi_audio_clock dut (
        .clk(clk_pixel), .resetn(resetn),
        .level(audio_level), .empty(audio_empty), .sample(audio_sample),
        .clk_audio(clk_audio), .rinc(audio_rinc),
        .word_l(word_l), .word_r(word_r)
    );

    // HDMI frame starts, in the pixel domain, handed to mclk as a toggle.
    integer pcnt = 0;
    reg hdmi_tgl = 1'b0;
    always @(posedge clk_pixel) begin
        if (pcnt == 1650*750 - 1) begin
            pcnt <= 0;
            hdmi_tgl <= ~hdmi_tgl;
        end else
            pcnt <= pcnt + 1;
    end

    localparam integer SNES_FRAME = 1364*262 - 2;
    longint cyc = 0;
    integer frame_cnt = 0, cesum = 0, ce_cnt = 0;
    reg paused = 1'b0;
    reg [2:0] hsync = 3'd0;
    longint n_in = 0, overflows = 0;

    always @(posedge clk) begin
        cyc <= cyc + 1;
        if (cyc == 64) resetn <= 1'b1;
        hsync <= {hsync[1:0], hdmi_tgl};

        audio_ready <= 1'b0;
        if (!paused) begin
            cesum = cesum + 411904;
            if (cesum >= 2147730) begin
                cesum = cesum - 2147730;
                ce_cnt = ce_cnt + 1;
                if (ce_cnt == 128) begin
                    ce_cnt = 0;
                    audio_l <= n_in[15:0];
                    audio_r <= ~n_in[15:0];
                    audio_ready <= 1'b1;
                    if (audio_full) overflows <= overflows + 1;
                    n_in <= n_in + 1;
                end
            end
            frame_cnt = frame_cnt + 1;
            if (frame_cnt == SNES_FRAME) begin
                frame_cnt = 0;
                paused <= 1'b1;
                cesum = 0;
            end
        end else if (hsync[2] ^ hsync[1])
            paused <= 1'b0;
    end

    // Reader checks, pixel domain.
    longint n_out = 0, underruns = 0, bad = 0, pcyc = 0, edges = 0, win_edges = 0;
    reg [15:0] last_l = 16'hffff;
    reg got = 1'b0, ca_d = 1'b0, started = 1'b0;
    integer lmin = 99, lmax = -1;
    real rmin = 1.0e9, rmax = 0.0, r;
    localparam longint WIN = 7425000;      // 0.1 s of nominal pixel clock
    localparam longint ONE_S = 74250000;

    always @(posedge clk_pixel) begin
        pcyc <= pcyc + 1;
        ca_d <= clk_audio;
        if (audio_rinc) begin
            got <= 1'b1;
            n_out <= n_out + 1;
        end
        // Sample loaded on the cycle after rinc; check it on the rising edge.
        if (clk_audio && !ca_d) begin
            edges <= edges + 1;
            win_edges <= win_edges + 1;
            if (started && pcyc > ONE_S) begin
                if (!got) underruns <= underruns + 1;
                else if (word_l != last_l + 16'd1 || word_r != ~word_l) bad <= bad + 1;
            end
            if (got) begin
                started <= 1'b1;
                last_l <= word_l;
            end
            got <= 1'b0;
        end
        if (pcyc > ONE_S) begin
            if ($signed({1'b0, audio_level}) < lmin) lmin = audio_level;
            if ($signed({1'b0, audio_level}) > lmax) lmax = audio_level;
        end
        if (pcyc % WIN == 0 && pcyc > 0) begin
            r = win_edges * 10.0;
            if (pcyc > ONE_S) begin
                if (r < rmin) rmin = r;
                if (r > rmax) rmax = r;
            end
            win_edges <= 0;
        end
        if (pcyc == longint'(secs) * ONE_S) begin
            $display("hdmi_audio_tb: %0d s ppm %0.0f: in %0d out %0d, overflows %0d, underruns %0d, drops/repeats %0d, level %0d..%0d, rate %0.0f..%0.0f Hz, integ %0d",
                     secs, ppm, n_in, n_out, overflows, underruns, bad, lmin, lmax, rmin, rmax, dut.integ >>> 4);
            if (overflows != 0 || underruns != 0 || bad != 0) $display("FAIL");
            else $display("PASS");
            $finish;
        end
    end
endmodule
