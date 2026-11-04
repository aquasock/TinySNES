// SPDX-License-Identifier: MIT
//
// Standalone bench for i2s_out: the Pmod resampler fed the way the board feeds
// it, so its output can be checked for clicks without a board or a full core.
//
// Production follows the machine.  dsp.v's CEGen adds ACLK_FREQ 411904 per
// mclk against 2147730 and the DSP emits one sample per 128 CEs, but only
// while ENABLE is high, and CEGen is held in reset while it is low.  ENABLE
// drops once per SNES frame for pause_snes_for_frame_sync: snes2hdmi halts the
// machine after its first line until the next HDMI frame starts.  An SNES frame
// is 1364 x 262 - 2 = 357,366 mclk; an HDMI frame is mclk / 60 = 358,423 mclk
// (mclk = 50 MHz x 40/93, the HDMI raster 74.25 MHz / (1650 x 750)), so each
// frame the DSP stops for about 1,057 mclk.
//
// The input is a 440 Hz sine.  Every resampler output (frame_tick) writes the
// interpolated left sample as a text line to +out=FILE, at mclk / 512 Hz.
// +nopause runs the machine flat out, 0.3 percent above the paused rate.
//
//   tools/sim/run_i2s_out.sh [+secs=N] [+nopause] [+out=FILE]
//
// At the end it prints the input samples, the output frames, the resampler's
// underrun and overflow counts, and the FIFO's range after its first second.

`timescale 1ns/1ps

module i2s_out_tb;
    reg clk = 1'b0;
    always #23.25 clk = ~clk;              // ~21.5 MHz; only the cycle count matters

    reg resetn = 1'b0;
    reg [15:0] audio_l = 16'd0, audio_r = 16'd0;
    reg audio_valid = 1'b0;
    wire mclk_o, lrck, sclk, sdin;

    i2s_out dut (
        .clk(clk), .resetn(resetn),
        .audio_l(audio_l), .audio_r(audio_r), .audio_valid(audio_valid),
        .dac_mclk(mclk_o), .dac_lrck(lrck), .dac_sclk(sclk), .dac_sdin(sdin),
        .dbg_taken(), .dbg_overwritten(), .dbg_underrun()
    );

    localparam longint SNES_FRAME = 1364*262 - 2;
    localparam longint HDMI_NUM   = 64'd2_000_000_000;   // mclk/60 = 2e9/5580
    localparam longint HDMI_STEP  = 64'd5580;

    integer secs = 3;
    integer nopause = 0;
    integer fd;
    string  out = "i2s_out.txt";

    longint cyc = 0, hacc = 0, frame_cnt = 0;
    longint cesum = 0;
    integer ce_cnt = 0;
    reg     paused = 1'b0;
    reg     hdmi_edge;
    real    ph = 0.0;
    longint n_in = 0, n_out = 0;
    integer fmin = 999, fmax = 0;

    initial begin
        void'($value$plusargs("secs=%d", secs));
        if ($test$plusargs("nopause")) nopause = 1;
        void'($value$plusargs("out=%s", out));
        fd = $fopen(out, "w");
    end

    always @(posedge clk) begin
        cyc <= cyc + 1;
        if (cyc == 16) resetn <= 1'b1;

        hacc = hacc + HDMI_STEP;
        hdmi_edge = hacc >= HDMI_NUM;
        if (hdmi_edge) hacc = hacc - HDMI_NUM;

        audio_valid <= 1'b0;
        if (!paused) begin
            cesum = cesum + 411904;
            if (cesum >= 2147730) begin
                cesum = cesum - 2147730;
                ce_cnt = ce_cnt + 1;
                if (ce_cnt == 128) begin
                    ce_cnt = 0;
                    audio_l <= $rtoi(8000.0 * $sin(ph));
                    audio_r <= $rtoi(8000.0 * $sin(ph));
                    ph = ph + 2.0 * 3.14159265358979 * 440.0 / 32040.0;
                    audio_valid <= 1'b1;
                    n_in <= n_in + 1;
                end
            end
            frame_cnt = frame_cnt + 1;
            if (frame_cnt == SNES_FRAME && !nopause) begin
                frame_cnt = 0;
                paused <= 1'b1;
                cesum = 0;
            end else if (frame_cnt == SNES_FRAME)
                frame_cnt = 0;
        end else if (hdmi_edge)
            paused <= 1'b0;

        if (resetn && dut.frame_tick) begin
            $fdisplay(fd, "%0d", $signed(dut.lat_l));
            n_out <= n_out + 1;
            if (cyc > 64'd21505376) begin
                if (dut.fifo_count < fmin) fmin = dut.fifo_count;
                if (dut.fifo_count > fmax) fmax = dut.fifo_count;
            end
        end

        if (cyc == longint'(secs) * 64'd21505376) begin
            $display("i2s_out_tb: %0d s, in %0d, out %0d, underruns %0d, overflows %0d, fifo %0d..%0d",
                     secs, n_in, n_out, dut.dbg_underrun, dut.dbg_overwritten, fmin, fmax);
            $fclose(fd);
            $finish;
        end
    end
endmodule
