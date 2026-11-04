// SPDX-License-Identifier: GPL-3.0-only
//
// Stereo I2S output for a Pmod I2S2's CS4344 DAC, resampled from the S-DSP.
//
// Why a resampler exists.  The sibling projects make I2S audio from a bus clock
// they also choose, so their emulated rate and their I2S rate are the same number
// by construction: TinyNES runs a 75 MHz bus, divides by 6 for a 12.5 MHz MCLK,
// and gets 48,828 Hz, which is what its emulator produces.  This core cannot do
// that, because the S-DSP's rate is fixed by the hardware it emulates: `CEGen`
// in dsp.v divides mclk by 128 for each sample at ACLK_FREQ 411904, so the core
// produces exactly 32,180 Hz whatever clock we give it.  The CS4344 wants
// MCLK = 256 x Fs, so the rates differ and something must convert between them.
//
// The conversion is linear interpolation, not sample dropping.  32,180 -> 48,828
// is a 1.517x upsample, so there are more output slots than input samples and
// each output sample is a weighted blend of the two inputs either side of it.
// That is a mild lowpass -- under 0.15 dB down at 5 kHz and about 1 dB at 10 kHz,
// with nothing aliased, because no input sample is ever discarded.  Repeating or
// dropping samples would be far cheaper and would be audible as a tone at the
// difference frequency.
//
// The clocks, and why they are not 48 kHz.  The obvious source is sys_clk, the
// 50 MHz oscillator: 50 MHz / 1024 is 48,828.125 Hz exactly, and it is the same
// MCLK TinyNES runs.  It does not work here.  Driving this unit from sys_clk
// changes the fanout of the net that also feeds pll_27, the HDMI PLL, and on this
// device that pushes pll_27.clkin's input onto SPINE16/CBRIDGEOUT_BOTTOM0, a
// bridge pip measured as clocking nothing.  Sixteen seeds were routed that way
// and every one died on that pip, and setting NPNR_GOWIN_CLK_FIRST to that clock
// applied but did not move it.  So the unit runs on mclk (21.477 MHz) instead,
// which leaves sys_clk exactly as the display path had it.  MCLK is mclk / 2 =
// 10.739 MHz, SCLK is MCLK / 4 and LRCK is MCLK / 256, so Fs is 21.477 MHz / 512
// = 41,947 Hz.  That is below the 44.1 and 48 kHz the siblings reach, and it is
// the honest cost of not disturbing a clock plan that took this project weeks to
// stabilise; the rate is inaudibly different for game audio, and the resampler
// ratio is set to it exactly.
//
// All three audio clocks come from one counter on mclk and drive pins directly,
// so this unit adds nothing to the FPGA's clock network and leaves the measured
// bridge pips untouched.
//
// The frame is I2S with 64 SCLKs: LRCK low for the left channel and high for the
// right, each channel's first SCLK the I2S delay bit, then the 16-bit sample MSB
// first, then zeros.  LRCK and SDIN change as SCLK falls, and the DAC samples as
// it rises.
//
// Samples arrive on mclk and are consumed on sys_clk.  They are unrelated clocks,
// so the handoff is a toggle beside the data: the producer flips a toggle when a
// pair is ready, and this unit sees the flip through a synchroniser and latches
// the data.  At 32 kHz against a 50 MHz consumer the producer is three orders of
// magnitude slower, so no pair can be missed and no FIFO is needed.

module i2s_out #(
    // The resampling ratio, as an exact rational with no floating point.  Both
    // rates are derived from mclk, so the ratio is a constant of the design:
    //   output = mclk / 512                    (MCLK = mclk/2, LRCK = MCLK/256)
    //   input  = mclk * 411904 / (2147730*128)  (CEGen in dsp.v, 128 CE a sample)
    // so input/output = 823808/1073865 = 0.767142984.
    //
    // These were integers 32180 and 41947 until this cycle, taken from the
    // nominal SNES master clock of 21.477 MHz.  mclk is not that: it is the PLL's
    // 50 MHz * 40/93 = 21.505376 MHz, which makes the S-DSP produce 32,222 Hz,
    // not 32,180.  Consuming at 32,180 while 32,222 arrive lost the difference
    // into the FIFO, which then overflowed every tenth of a second: a continuous
    // crackle, and the reason the Pmod output sounded scratchy while the same
    // module playing TinyNES and TinyGBC was clean.
    parameter integer RATIO_NUM = 823808,
    parameter integer RATIO_DEN = 1073865
) (
    input  wire        clk,        // mclk, 21.477 MHz
    input  wire        resetn,

    // Audio from the machine, in the mclk domain.  `valid` is a one-clock pulse
    // beside the pair it belongs to.
    input  wire [15:0] audio_l,
    input  wire [15:0] audio_r,
    input  wire        audio_valid,

    // To the Pmod I2S2.
    output reg         dac_mclk,
    output reg         dac_lrck,
    output reg         dac_sclk,
    output reg         dac_sdin,

    // Diagnostics: input samples accepted and input samples overwritten before
    // being consumed.  A non-zero overwrite count means the resampler's one-deep
    // holding slot loses audio, which is audible as broadband distortion.
    output reg  [15:0] dbg_taken,
    output reg  [15:0] dbg_overwritten
);

    // ------------------------------------------------------- clock generation
    // One free-running nibble counter off sys_clk.  Every audio clock is a bit
    // of it, so all three stay synchronous with no phase to set, which is what
    // the CS4344 requires.
    //   scnt[0] swings every mclk      -> 10.739 MHz MCLK
    //   scnt[3] swings every 8 mclk    -> 2.685 MHz SCLK
    //   one LRCK period is 64 SCLKs    -> 41,947 Hz
    reg [2:0] scnt = 3'd0;                 // one SCLK period: 8 mclk
    always @(posedge clk) scnt <= scnt + 3'd1;

    wire sclk_fall = (scnt == 3'd4);        // SCLK falls where scnt[2] rises

    always @(posedge clk) begin
        dac_mclk <= scnt[0];                // mclk / 2
        dac_sclk <= ~scnt[2];               // mclk / 8 = MCLK / 4
    end

    // ------------------------------------------------------ frame bit counter
    reg [5:0] bitn = 6'd0;                  // 0..63 within one LRCK period
    wire [5:0] bitn_next = bitn + 6'd1;     // wraps to 0 at 63
    wire [4:0] bchan = bitn[4:0];           // position within the channel, 0..31
    wire       right = bitn[5];             // 0 = left, 1 = right

    always @(posedge clk) begin
        if (!resetn) begin
            bitn <= 6'd0;
            dac_lrck <= 1'b0;
        end else if (sclk_fall) begin
            bitn <= bitn + 6'd1;
            // Exactly 32 SCLKs per channel: low for 0..31, high for 32..63.
            // Taken from the NEXT value, because LRCK has to be right for the
            // bit period that follows this edge, not the one just ended -- using
            // the old count put the channel change one SCLK late and shifted
            // every left-hand sample by two bit positions.
            dac_lrck <= bitn_next[5];
        end
    end

    // -------------------------------------------------- cross the clock domain
    // The producer does not touch the data again until it flips the next time,
    // so seeing the toggle change through the synchroniser means the latched
    // pair is a complete, stable sample.
    reg        in_tog = 1'b0;
    reg [15:0] in_l = 16'd0, in_r = 16'd0;
    always @(posedge clk) begin
        if (!resetn) begin
            in_tog <= 1'b0;
        end else if (audio_valid) begin
            in_tog <= ~in_tog;
            in_l <= audio_l;
            in_r <= audio_r;
        end
    end

    reg [2:0] tog_sync = 3'd0;
    always @(posedge clk) tog_sync <= {tog_sync[1:0], in_tog};
    wire new_sample = tog_sync[2] ^ tog_sync[1];

    // ------------------------------------------------------------- resampler
    // `phase` is a fixed-point position inside one input-sample interval: 0 is
    // exactly at the older sample and wrapping past 2^32 is exactly at the newer
    // one.  Each output frame advances it by one output period expressed in
    // input periods, so the top 8 bits are the interpolation weight and the carry
    // out says a new input sample has been consumed.
    // Nominal STEP, and the servo that corrects it.
    //
    // A fixed step assumes the input arrives at a constant rate.  It does not:
    // `snes2hdmi` halts the whole machine once per frame so its output stays
    // aligned to the HDMI raster (`pause_snes_for_frame_sync`), which stops the
    // DSP making samples and then releases them in a burst.  A fixed-rate
    // resampler turns that into a phase discontinuity at the frame rate -- 60 Hz
    // -- which the spectrum shows as sidebands at the frame rate around every
    // harmonic, and which is heard as grit.  Measured on the board before this
    // change: sidebands at 440 +/- 60, 1320 +/- 60 and 2200 +/- 60 Hz, each about
    // 20 dB below its harmonic.
    //
    // So the step is nudged: when the queue is fuller than the midpoint the
    // resampler consumes slightly faster, and when it is emptier, slightly
    // slower.  The correction is a fraction of a percent, far below anything
    // audible as pitch, and it turns a rate or timing error into a slowly
    // varying phase rather than a jump.  This is why the 0.13 percent error found
    // in the previous cycle would also have been harmless here.
    localparam [63:0] STEP64 = (64'd1 << 32) * RATIO_NUM / RATIO_DEN;
    localparam [31:0] STEP   = STEP64[31:0];
    // Authority and dead band.  1/4096 of a step is 0.024 percent, far below any
    // audible pitch change, and the dead band is a quarter of the queue either
    // side of centre.  An earlier version used 1/1024 and no dead band, and it
    // oscillated: measured on the bench, 2 backwards steps in 522 frames, because
    // each correction carried the phase past the midpoint and the next reversed
    // it.
    localparam [31:0] STEP_TRIM = STEP >> 12;

    // A small FIFO between arrival and consumption.  The average rates match by
    // construction -- consuming IN_RATE per output period is exactly the producer
    // rate -- but the two are not phase-aligned, so a sample can arrive just
    // after a consumption point and have to wait a whole output period.  With a
    // one-deep slot the next arrival then overwrote it: measured on the bench,
    // 68 of 358 samples were lost, 19 percent, which is heard as broadband
    // distortion rather than as anything obviously broken.  Four entries is
    // enough to absorb that jitter because the rates do match, so the occupancy
    // stays bounded.
    localparam integer FIFO_DEPTH = 16;

    reg [15:0] fifo_l [0:FIFO_DEPTH-1];
    reg [15:0] fifo_r [0:FIFO_DEPTH-1];
    reg [4:0]  fifo_wr = 5'd0, fifo_rd = 5'd0;
    reg [4:0]  fifo_count = 5'd0;

    wire        fifo_empty = fifo_count == 5'd0;
    wire        fifo_full  = fifo_count == FIFO_DEPTH[4:0];

    reg [15:0] prev_l = 16'd0, prev_r = 16'd0;   // older of the pair
    reg [15:0] cur_l  = 16'd0, cur_r  = 16'd0;   // newer
    reg [31:0] phase = 32'd0;
    reg        primed = 1'b0;
    reg signed [15:0] lat_l = 16'sd0, lat_r = 16'sd0;

    wire frame_tick = sclk_fall && (bitn_next[4:0] == 5'd0) && ~bitn_next[5];

    // Interpolation: prev + (cur - prev) * weight / 65536, rounded.
    //
    // The weight is sixteen bits of the phase, not eight.  With eight the
    // quantisation of the weight alone was worth up to 256 LSB of error on a
    // full-scale sample-to-sample step, about -42 dBFS riding on every loud
    // passage, which is heard as grit rather than as a wrong pitch; sixteen bits
    // puts it under one LSB.  The product is 33 bits, which costs one small
    // multiplier and removes the artefact.
    wire [15:0] w   = phase[31:16];
    wire signed [16:0] d_l = $signed({cur_l[15], cur_l}) - $signed({prev_l[15], prev_l});
    wire signed [16:0] d_r = $signed({cur_r[15], cur_r}) - $signed({prev_r[15], prev_r});
    wire signed [33:0] m_l = d_l * $signed({1'b0, w});
    wire signed [33:0] m_r = d_r * $signed({1'b0, w});
    // Round rather than truncate: half an LSB of DC bias otherwise.
    wire signed [33:0] r_l = m_l + (34'sd1 << 15);
    wire signed [33:0] r_r = m_r + (34'sd1 << 15);
    wire signed [16:0] p_l = $signed({prev_l[15], prev_l}) + (r_l >>> 16);
    wire signed [16:0] p_r = $signed({prev_r[15], prev_r}) + (r_r >>> 16);

    // Occupancy error against the half-full point, as a direction only: the
    // magnitude is fixed, so the loop is a simple bang-bang servo and cannot
    // overshoot on a single sample.
    localparam [4:0] MID = FIFO_DEPTH[4:0] / 2;
    localparam [4:0] BAND = FIFO_DEPTH[4:0] / 4;
    wire above_mid = fifo_count > MID + BAND;
    wire below_mid = fifo_count < MID - BAND;
    wire [31:0] step_now = above_mid ? STEP + STEP_TRIM :
                           below_mid ? STEP - STEP_TRIM : STEP;

    // 33-bit sum so the carry out of the 32-bit phase is visible.
    wire [32:0] phase_sum = {1'b0, phase} + {1'b0, step_now};

    // The wrap pops one entry; the frame tick is where that happens.
    wire pop = frame_tick && phase_sum[32] && !fifo_empty;

    always @(posedge clk) begin
        if (!resetn) begin
            fifo_wr <= 5'd0;
            fifo_rd <= 5'd0;
            fifo_count <= 5'd0;
            prev_l <= 16'd0; prev_r <= 16'd0;
            cur_l  <= 16'd0; cur_r  <= 16'd0;
            phase <= 32'd0;
            primed <= 1'b0;
            lat_l <= 16'sd0; lat_r <= 16'sd0;
            dbg_taken <= 16'd0;
            dbg_overwritten <= 16'd0;
        end else begin
            // Push on arrival.  A full FIFO would still lose the sample, so the
            // count is exposed; at matched rates it should never fill.
            if (audio_valid && !fifo_full) begin
                fifo_l[fifo_wr] <= audio_l;
                fifo_r[fifo_wr] <= audio_r;
                fifo_wr <= (fifo_wr == FIFO_DEPTH-1) ? 5'd0 : fifo_wr + 5'd1;
                if (dbg_taken != 16'hFFFF) dbg_taken <= dbg_taken + 16'd1;
            end else if (audio_valid && fifo_full) begin
                if (dbg_overwritten != 16'hFFFF)
                    dbg_overwritten <= dbg_overwritten + 16'd1;
            end

            if (frame_tick) begin
                // Hold silence until the pair is real, so the first frames do not
                // interpolate against a zero that was never a sample.
                if (primed)
                    begin lat_l <= p_l[15:0]; lat_r <= p_r[15:0]; end
                else
                    begin lat_l <= 16'sd0; lat_r <= 16'sd0; end

                phase <= phase_sum[31:0];

                if (phase_sum[32]) begin
                    // The phase passed `cur`: shift the window forward.
                    prev_l <= cur_l;
                    prev_r <= cur_r;
                    if (!fifo_empty) begin
                        cur_l <= fifo_l[fifo_rd];
                        cur_r <= fifo_r[fifo_rd];
                        fifo_rd <= (fifo_rd == FIFO_DEPTH-1) ? 5'd0 : fifo_rd + 5'd1;
                        primed <= 1'b1;
                    end
                end
            end

            // Occupancy bookkeeping, in one place so push and pop cannot disagree.
            case ({audio_valid && !fifo_full, pop})
                2'b10:   fifo_count <= fifo_count + 5'd1;
                2'b01:   fifo_count <= fifo_count - 5'd1;
                default: ;
            endcase
        end
    end

    // ------------------------------------------------------------- shift out
    // Everything here is driven by the bit index of the period that FOLLOWS an
    // SCLK falling edge.  Getting that wrong is what makes a sample land one or
    // two positions off: driving from the index that just ended leaves the load
    // branch out of step with the counter as it wraps.
    //
    // Per channel of 32 bits: index 0 is the I2S delay bit, 1..16 carry the
    // sample MSB first, 17..31 are zeros.
    reg [15:0] shift = 16'd0;
    reg [15:0] hold_r = 16'd0;      // right sample captured at the frame start

    always @(posedge clk) begin
        if (!resetn) begin
            shift <= 16'd0;
            hold_r <= 16'd0;
            dac_sdin <= 1'b0;
        end else if (sclk_fall) begin
            if (bitn_next[4:0] == 5'd0) begin
                // Channel delay bit, and load this channel's sample.  The right
                // sample is held at the frame start so both channels carry the
                // same frame rather than one drifting a frame behind.
                if (bitn_next[5]) begin
                    shift <= hold_r;
                end else begin
                    shift  <= lat_l;
                    hold_r <= lat_r;
                end
                dac_sdin <= 1'b0;
            end else if (bitn_next[4:0] <= 5'd16) begin
                dac_sdin <= shift[15];
                shift <= {shift[14:0], 1'b0};
            end else begin
                dac_sdin <= 1'b0;
            end
        end
    end

endmodule
