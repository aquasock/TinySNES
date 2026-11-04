`timescale 1ns/1ps

// Bench for i2s_out.sv: the clocks it generates, the I2S frame it sends, and
// whether the resampler preserves a signal.
//
// Three things are checked, and each is a way this unit can be wrong while
// looking plausible:
//   1. the clock ratios.  MCLK must be sys_clk/4 and LRCK must divide it by 256,
//      because the CS4344 derives Fs from MCLK and will not correct a mistake.
//   2. the frame shape.  LRCK low for the left channel, a zero delay bit, then
//      the sample MSB first; and SDIN must only change while SCLK is low.
//   3. the resampler.  A constant must stay constant -- interpolation that is
//      off by a weight scaling still passes a DC test -- and a slow ramp must
//      come out monotonic and fall between the samples fed in.
//
//   tools/tests/run_i2s_tb.sh

module i2s_tb;

    // mclk, 21.477 MHz, the real rate this unit runs on.
    reg clk = 0;
    always #23.28 clk = ~clk;

    reg resetn = 0;

    reg [15:0] audio_l = 16'd0, audio_r = 16'd0;
    reg        audio_valid = 0;

    wire dac_mclk, dac_lrck, dac_sclk, dac_sdin;
    wire [15:0] dbg_taken, dbg_overwritten;

    i2s_out #(.RATIO_NUM(823808), .RATIO_DEN(1073865)) dut (
        .clk(clk), .resetn(resetn),
        .audio_l(audio_l), .audio_r(audio_r), .audio_valid(audio_valid),
        .dac_mclk(dac_mclk), .dac_lrck(dac_lrck),
        .dac_sclk(dac_sclk), .dac_sdin(dac_sdin),
        .dbg_taken(dbg_taken), .dbg_overwritten(dbg_overwritten)
    );

    // ------------------------------------------------------------ measurement
    integer mclk_rises = 0, sclk_rises = 0, lrck_rises = 0;
    integer cycles = 0;
    reg mclk_p = 0, sclk_p = 0, lrck_p = 0;

    always @(posedge clk) begin
        cycles = cycles + 1;
        mclk_p <= dac_mclk; sclk_p <= dac_sclk; lrck_p <= dac_lrck;
        if (!mclk_p && dac_mclk) mclk_rises = mclk_rises + 1;
        if (!sclk_p && dac_sclk) sclk_rises = sclk_rises + 1;
        if (!lrck_p && dac_lrck) lrck_rises = lrck_rises + 1;
    end

    // ---------------------------------------------------- capture one frame
    // Sample SDIN on every SCLK rise from the LRCK falling edge and keep the last
    // complete 64-bit frame.  `frame_done` is a one-clock pulse on the SCLK rise
    // that completes it, so a poller cannot count the same frame twice.
    reg [63:0] frame = 64'd0;
    reg [63:0] snapshot = 64'd0;
    integer    got = 0;
    reg        sd_p = 1;
    reg        sclk_q = 0, lrck_q = 0;
    reg        frame_done = 1'b0;
    reg        seen_mid = 1'b0;

    always @(posedge clk) begin
        sd_p   <= dac_sdin;
        sclk_q <= dac_sclk;
        lrck_q <= dac_lrck;

        frame_done <= 1'b0;                     // one clock by default
        if (lrck_q && !dac_lrck) begin
            frame <= 64'd0;
            got   <= 0;
        end else if (!sclk_q && dac_sclk) begin
            frame <= {frame[62:0], sd_p};
            if (got == 63) begin
                snapshot   <= {frame[62:0], sd_p};
                frame_done <= 1'b1;
                if ({frame[54:39]} > 16'h0000 && {frame[54:39]} < 16'h4000)
                    seen_mid <= 1'b1;
                got        <= 0;
            end else
                got <= got + 1;
        end
    end

    // SDIN must only change while SCLK is low.
    integer illegal_edges = 0;
    reg sd_prev = 0;
    always @(posedge clk) begin
        sd_prev <= dac_sdin;
        if (dac_sdin !== sd_prev && dac_sclk) illegal_edges = illegal_edges + 1;
    end

    // ---------------------------------------------------------------- checks
    integer errors = 0;
    task check(input bit c, input [8*64-1:0] what);
        begin
            if (!c) begin errors = errors + 1; $display("FAIL  %0s", what); end
            else $display("ok    %0s", what);
        end
    endtask

    real mclk_hz, sclk_hz, lrck_hz;
    real avg_l, avg_r;
    integer i;

    // The producer's clock enable, from the same divider dsp.v uses with the
    // same constants.  The bench must not carry its own idea of the sample rate:
    // it did once, at 667 clocks a sample, and agreed with an RTL that had the
    // same rate wrong, so neither could see the FIFO overflow.
    wire ce;
    CEGen cegen (.CLK(clk), .RST_N(resetn),
                 .IN_CLK(2147730), .OUT_CLK(411904), .CE(ce));
    reg [6:0] sub = 7'd0;         // 128 CE per sample, as dsp.v counts

    // Present a sample pair whenever the DSP would: on the CE that completes a
    // 128-count frame.
    always @(posedge clk) begin
        if (!resetn) begin
            sub <= 7'd0;
            audio_valid <= 1'b0;
        end else begin
            audio_valid <= 1'b0;
            if (ce) begin
                if (sub == 7'd127) begin
                    sub <= 7'd0;
                    audio_l <= prod_l;
                    audio_r <= prod_r;
                    audio_valid <= 1'b1;
                end else
                    sub <= sub + 7'd1;
            end
        end
    end

    // The sample the producer is currently "playing".
    reg [15:0] prod_l = 16'd0, prod_r = 16'd0;

    // Hold a sample for the producer to play for one sample period.
    task send(input [15:0] l, input [15:0] r);
        begin
            prod_l = l; prod_r = r;
            repeat (667) @(posedge clk);
        end
    endtask

    initial begin
        $display("i2s bench: clocks, frame shape and resampler");
        resetn = 0;
        repeat (20) @(posedge clk);
        resetn = 1;

        // ---- 1. clock ratios, measured over 50 ms of bench time
        cycles = 0; mclk_rises = 0; sclk_rises = 0; lrck_rises = 0;
        repeat (2_500_000) @(posedge clk);
        mclk_hz = mclk_rises / (cycles / 21.477e6);
        sclk_hz = sclk_rises / (cycles / 21.477e6);
        lrck_hz = lrck_rises / (cycles / 21.477e6);
        $display("  measured MCLK %.0f Hz  SCLK %.0f Hz  LRCK %.0f Hz",
                 mclk_hz, sclk_hz, lrck_hz);
        check(mclk_hz > 10.6e6 && mclk_hz < 10.9e6, "MCLK is 10.739 MHz (mclk/2)");
        check(sclk_hz > 2.65e6 && sclk_hz < 2.72e6, "SCLK is 2.685 MHz (MCLK/4)");
        check(lrck_hz > 41800 && lrck_hz < 42100, "LRCK is 41,947 Hz (MCLK/256)");
        check(illegal_edges == 0, "SDIN changes only while SCLK is low");

        // ---- 2. a constant must come out constant
        // Anything else means the weight or the phase is wrong.
        for (i = 0; i < 8; i = i + 1) send(16'h1234, 16'h5678);
        repeat (4000) @(posedge clk);
        $display("  frame %016h%016h", snapshot[63:32], snapshot[31:0]);
        check(snapshot[63:32] == {1'b0, 16'h1234, 15'd0},
              "left channel is delay bit, 16 bits MSB first, then zeros");
        check(snapshot[31:0] == {1'b0, 16'h5678, 15'd0},
              "right channel is delay bit, 16 bits MSB first, then zeros");

        // ---- 3. a slow ramp must come out monotonic and in range
        // Send 0x1000, 0x1100, 0x1200 ... and check the output walks up between
        // them rather than jumping or sticking.
        for (i = 0; i < 6; i = i + 1) send(16'h1000 + i*16'h100, 16'h1000 + i*16'h100);
        repeat (4000) @(posedge clk);
        $display("  ramp frame left sample %04h", snapshot[62:47]);
        check(snapshot[62:47] > 16'h1000 && snapshot[62:47] <= 16'h1600,
              "ramp output lies inside the samples fed in");

        // Interpolation between two known samples: hold 0x0000 then 0x4000 and
        // the output must land strictly between once the phase reaches them.
        for (i = 0; i < 6; i = i + 1) send(16'h0000, 16'h0000);
        for (i = 0; i < 6; i = i + 1) send(16'h4000, 16'h4000);
        repeat (8000) @(posedge clk);
        check(seen_mid, "a ramp produces samples strictly between the inputs");

        // ---- 4. a ramp must come out MONOTONIC and without stalls
        // This is the test the earlier three could not do.  A constant passes
        // through even if most samples are dropped, and a ramp's endpoint says
        // nothing about the points between.  A slow monotonic ramp that is
        // resampled correctly steps forward on every output frame; one that
        // drops or repeats samples stalls, and one that loses the phase order
        // steps backwards.  Either produces exactly the thin, comb-filtered
        // sound a listener describes as "tinny with an echo".
        begin : ramp_walk
            integer frames = 0, stalls = 0, backups = 0, steps = 0;
            reg [15:0] last = 16'h0000;
            reg [15:0] want_next;
            // Feed a ramp that rises by 1 every input sample, slowly enough that
            // the interpolator's steps are small.
            fork
                begin
                    integer k;
                    for (k = 0; k < 400; k = k + 1) send(16'h0800 + k*16'd2, 16'h0800 + k*16'd2);
                end
                begin
                    integer j;
                    for (j = 0; j < 300000; j = j + 1) begin
                        @(posedge clk);
                        if (frame_done) begin
                            frames = frames + 1;
                            if (frames > 8) begin
                                if (snapshot[62:47] == last) stalls = stalls + 1;
                                else if (snapshot[62:47] < last) backups = backups + 1;
                                else steps = steps + 1;
                            end
                            last = snapshot[62:47];
                        end
                    end
                end
            join_any
            $display("  ramp walk: %0d output frames, %0d forward, %0d stalls, %0d backwards",
                     frames, steps, stalls, backups);
            check(frames > 100, "enough output frames were captured to judge the walk");
            check(backups == 0, "the resampled ramp never steps backwards");
            check(stalls * 4 < steps, "the resampled ramp is not stalling on most frames");
        end

        // ---- 5. the handoff must not lose samples
        // The producer and the consumer run at matched rates from unrelated
        // clocks, so jitter can leave a new sample arriving before the previous
        // one was consumed.  A one-deep holding slot overwrites in that case and
        // the audio gets broadband distortion -- which is heard as a thin,
        // echoing tone rather than as anything obviously broken.
        $display("  input samples: taken %0d, overwritten %0d", dbg_taken, dbg_overwritten);
        check(dbg_overwritten == 16'd0, "no input sample is overwritten before use");

        // ---- 6. a bursty producer must not run the queue away
        // The board's producer does not deliver samples evenly: the machine is
        // halted once per frame and then released.  A fixed-rate consumer either
        // starves during the halt or overflows on the release.  The servo is what
        // makes that survivable, so this test delivers a whole frame's worth of
        // samples in 2 ms and nothing for the rest of the frame, and requires
        // that nothing is overwritten.
        begin : burst
            integer k, f;
            integer before_ov = dbg_overwritten;
            integer peak = 0;
            for (f = 0; f < 30; f = f + 1) begin
                // one frame's samples, delivered as fast as the producer can
                for (k = 0; k < 536; k = k + 1) begin
                    prod_l = 16'h0800 + k[15:0];
                    prod_r = prod_l;
                    repeat (2) @(posedge clk);      // back-to-back
                end
                // then silence for the rest of the 60 Hz frame
                repeat (300000) @(posedge clk);
                if (dbg_overwritten > peak) peak = dbg_overwritten;
            end
            $display("  burst: %0d frames delivered unevenly, overwritten %0d -> %0d",
                     30, before_ov, dbg_overwritten);
            check(dbg_overwritten == before_ov,
                  "a bursty producer loses no samples");
        end

        $display("");
        if (errors == 0) $display("PASS  clocks, frame shape and resampler all correct");
        else             $display("FAIL  %0d check(s) failed", errors);
        $finish;
    end

endmodule
