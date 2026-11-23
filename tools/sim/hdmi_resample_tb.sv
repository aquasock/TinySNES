// SPDX-License-Identifier: GPL-3.0-only
//
// Standalone bench for the HDMI audio path: dual_clk_fifo plus
// hdmi_audio_resample, fed the way the board feeds them.
//
// Production follows the machine (see i2s_out_tb.sv): CEGen adds 411904 per
// mclk against 2147730, one sample per 128 CEs, and CEGen is held in reset
// while the SNES is paused.  The SNES pauses after each 357,366-mclk frame
// until the next HDMI frame starts; HDMI frames come from the pixel clock
// (1650 x 750 at 74.25 MHz), so +ppm=N offsets the two crystals.
//
// The samples are a sine, A sin(2 pi f n / 32127) left and B cos right, with
// f from +freq=N, so the ideal output is known at every point.  After the
// first second the bench checks, in the pixel domain:
//   * every window of 74,250,000 pixel clocks holds exactly 48,000 audio
//     clock periods, and every 48 periods are exactly 74,250 pixel clocks,
//     which is the CTS the HDMI core measures (N = 6144);
//   * no overflow (a write to a full FIFO) and, from reset, no underrun (a
//     pop of an empty one), so reading waits for the FIFO to fill;
// and writes one line per output sample to +dump=FILE for
// tools/sim/hdmi_resample_model.py, which checks every word against the
// arithmetic and the signal.
//
//   tools/sim/run_hdmi_resample.sh [+secs=N] [+ppm=N] [+freq=N]

`timescale 1ps/1ps

module hdmi_resample_tb;
    real ppm = 0.0;
    real freq = 1000.0;
    real pix_half;
    integer secs = 3;
    string dump_path = "resample.dump";
    integer dump_fd;

    reg clk = 1'b0;                         // mclk, 21,505,376 Hz
    always #23250 clk = ~clk;
    reg clk_pixel = 1'b0;
    initial begin
        void'($value$plusargs("secs=%d", secs));
        void'($value$plusargs("ppm=%f", ppm));
        void'($value$plusargs("freq=%f", freq));
        void'($value$plusargs("dump=%s", dump_path));
        dump_fd = $fopen(dump_path, "w");
        pix_half = 1.0e12 / 74.25e6 / 2.0 / (1.0 + ppm * 1.0e-6);
        forever #(pix_half) clk_pixel = ~clk_pixel;
    end

    reg resetn = 1'b0;
    reg [15:0] audio_l = 16'd0, audio_r = 16'd0;
    reg audio_ready = 1'b0;

    wire audio_full, audio_empty;
    wire [31:0] audio_sample;
    wire [4:0] audio_level;
    wire clk_audio, audio_rinc, audio_unf;
    wire [15:0] word_l, word_r;

    dual_clk_fifo #(.DATESIZE(32), .ADDRSIZE(4)) fifo (
        .clk(clk), .wrst_n(1'b1),
        .winc(audio_ready), .wdata({audio_l, audio_r}), .wfull(audio_full),
        .rclk(clk_pixel), .rrst_n(1'b1),
        .rinc(audio_rinc), .rdata(audio_sample), .rempty(audio_empty),
        .almost_full(), .almost_empty(), .rlevel(audio_level)
    );

    hdmi_audio_resample dut (
        .clk(clk_pixel), .resetn(resetn),
        .level(audio_level), .empty(audio_empty), .sample(audio_sample),
        .clk_audio(clk_audio), .rinc(audio_rinc), .underrun(audio_unf),
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
    localparam real    IN_HZ = 32127.0;
    longint cyc = 0;
    integer frame_cnt = 0, cesum = 0, ce_cnt = 0;
    reg paused = 1'b0;
    reg [2:0] hsync = 3'd0;
    longint n_in = 0, overflows = 0;
    real w;

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
                    w = 2.0 * 3.14159265358979323846 * freq * n_in / IN_HZ;
                    audio_l <= 16'($rtoi($floor(20000.0 * $sin(w) + 0.5)));
                    audio_r <= 16'($rtoi($floor(12000.0 * $cos(w) + 0.5)));
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
    longint pops = 0, underruns = 0, pcyc = 0, edges = 0, rate_bad = 0, cts_bad = 0;
    longint win_edges = 0, last48 = 0, n_dump = 0;
    integer e48 = 0;
    reg ca_d = 1'b0;
    integer lmin = 99, lmax = -1;
    localparam longint ONE_S = 74250000;

    always @(posedge clk_pixel) begin
        pcyc <= pcyc + 1;
        ca_d <= clk_audio;
        if (audio_rinc) pops <= pops + 1;
        if (audio_unf) underruns <= underruns + 1;        // from reset
        if (clk_audio && !ca_d) begin
            edges <= edges + 1;
            win_edges <= win_edges + 1;
            // The HDMI core's CTS: pixel clocks across 48 audio periods.
            if (e48 == 47) begin
                e48 <= 0;
                if (pcyc > ONE_S && last48 != 0 && pcyc - last48 != 74250)
                    cts_bad <= cts_bad + 1;
                last48 <= pcyc;
            end else
                e48 <= e48 + 1;
            if (pcyc > ONE_S) begin
                // x0 is the fourth-newest sample taken, so its index is pops - 3.
                $fwrite(dump_fd, "%0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d\n",
                        pops - 3, dut.t,
                        dut.xl[0], dut.xl[1], dut.xl[2], dut.xl[3],
                        dut.xr[0], dut.xr[1], dut.xr[2], dut.xr[3],
                        $signed(word_l), $signed(word_r));
                n_dump <= n_dump + 1;
            end
        end
        if (pcyc > ONE_S) begin
            if ($signed({1'b0, audio_level}) < lmin) lmin = audio_level;
            if ($signed({1'b0, audio_level}) > lmax) lmax = audio_level;
        end
        // Whole seconds of the pixel clock: exactly 48,000 periods each.
        if (pcyc % ONE_S == 0 && pcyc > 0) begin
            if (pcyc > ONE_S && win_edges != 48000) rate_bad <= rate_bad + 1;
            win_edges <= 0;
        end
        if (pcyc == longint'(secs) * ONE_S) begin
            $fclose(dump_fd);
            $display("hdmi_resample_tb: %0d s ppm %0.0f freq %0.0f: in %0d popped %0d, overflows %0d, underruns %0d, seconds off 48000 %0d, CTS off 74250 %0d, level %0d..%0d, dumped %0d",
                     secs, ppm, freq, n_in, pops, overflows, underruns, rate_bad, cts_bad,
                     lmin, lmax, n_dump);
            if (overflows != 0 || underruns != 0 || rate_bad != 0 || cts_bad != 0 || n_dump == 0)
                $display("FAIL");
            else
                $display("PASS");
            $finish;
        end
    end
endmodule
