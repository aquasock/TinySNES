// SPDX-License-Identifier: GPL-3.0-only
//
// HDMI audio at exactly 48 kHz, resampled from the S-DSP's real output rate.
//
// The SNES pauses each frame to hold 60.000 Hz HDMI, so the S-DSP makes about
// 32,127 samples/s in bursts.  Sending them as they come, under a 32 kHz
// header, is what hdmi_audio_clock.v did; a capture card took it, but a real
// HDMI audio DAC plays at the rate the header and the clock regeneration
// promise and overflowed its buffer about five times a second (core-log
// entry 26).  Here the output rate is fixed and exact: clk_audio is 48 kHz
// counted from the pixel clock (74.25 MHz / 48 kHz = 1546.875 cycles, so any
// 48 periods are exactly 74,250 cycles and the HDMI core's measured CTS is
// constant at 74,250 with N = 6144), and the samples are resampled to it.
//
// Resampling.  A 32-bit phase, in input samples, advances by `step` at each
// output sample; each carry moves the four-sample history x[-1], x0, x1, x2
// along by one and takes the FIFO's head into x2.  The output is the
// Catmull-Rom cubic through the history at t = phase[31:16] between x0 and
// x1, worked out on one shared multiplier in eight cycles.  `step` is the
// nominal ratio 32,127 / 48,000 steered by the FIFO's read-side fill level
// through a PI servo around MID, so input is consumed exactly as fast as it
// is produced and nothing is dropped or repeated; only the interpolation
// changes the samples.
//
// Each output period starts with a tick, at which the phase advances and the
// cubic starts; clk_audio rises half a period later, where the HDMI core
// takes word_l and word_r, long after they have settled.

module hdmi_audio_resample #(
    parameter [31:0]  CLK_HZ   = 32'd74250000,
    parameter [31:0]  OUT_HZ   = 32'd48000,
    parameter [31:0]  IN_HZ    = 32'd32127,     // nominal production rate
    parameter integer KP_SHIFT = 19,            // ~0.0061 % ratio per entry
    parameter integer KI_SHIFT = 6
)(
    input             clk,
    input             resetn,
    input       [4:0] level,                // FIFO fill level, read side, 0..16
    input             empty,
    input      [31:0] sample,               // {left, right} at the FIFO head
    output reg        clk_audio,
    output reg        rinc,
    output reg        underrun,             // a pop found the FIFO empty
    output reg [15:0] word_l,
    output reg [15:0] word_r
);
    localparam [63:0] STEP64 = ({32'd0, IN_HZ} << 32) / {32'd0, OUT_HZ};
    localparam signed [33:0] STEP = {2'b00, STEP64[31:0]};
    localparam signed [5:0]  MID  = 6'sd8;
    localparam signed [21:0] IMAX = 22'sd1 << 19;   // +/- 1.2 % after <<< KI_SHIFT
    localparam [31:0] HALF = CLK_HZ / OUT_HZ / 2;

    // ---------------------------------------------------------------- the tick
    // Exactly OUT_HZ ticks per CLK_HZ cycles, evenly spread.
    reg [31:0] acc;
    reg [31:0] since;               // cycles since the last tick
    reg        tick;

    always @(posedge clk) begin
        if (!resetn) begin
            acc       <= 32'd0;
            since     <= 32'd0;
            tick      <= 1'b0;
            clk_audio <= 1'b0;
        end else begin
            tick <= 1'b0;
            since <= since + 1'b1;
            if (acc + OUT_HZ >= CLK_HZ) begin
                acc       <= acc + OUT_HZ - CLK_HZ;
                tick      <= 1'b1;
                since     <= 32'd0;
                clk_audio <= 1'b0;
            end else begin
                acc <= acc + OUT_HZ;
                if (since == HALF)
                    clk_audio <= 1'b1;
            end
        end
    end

    // --------------------------------------------------- the phase and history
    reg [31:0] phase;
    reg signed [33:0] step;
    reg signed [21:0] integ;
    reg signed [5:0]  err;
    reg signed [15:0] xl [0:3];     // x[-1], x0, x1, x2
    reg signed [15:0] xr [0:3];

    wire signed [33:0] err34   = {{28{err[5]}}, err};
    wire signed [33:0] integ34 = {{12{integ[21]}}, integ};
    wire        [32:0] sum      = {1'b0, phase} + {1'b0, step[31:0]};
    wire signed [21:0] integ_nx = integ + {{16{err[5]}}, err};

    // ------------------------------------------------------------- the cubic
    // y = x0 + t/2 * (c + t * (b + t * a)), with
    //   a = 3 (x0 - x1) + x2 - x[-1], b = 2 x[-1] - 5 x0 + 4 x1 - x2,
    //   c = x1 - x[-1], and t in [0, 1) as 16 fractional bits.
    // Each product is rounded to nearest; the result saturates to 16 bits.
    // tools/sim/hdmi_resample_model.py is the same arithmetic in Python.
    //
    // One channel at a time, left then right, on one multiplier whose product
    // is registered: seq 1 takes the coefficients, 2 starts a * t, 4 starts
    // (b + a t) * t, 6 starts (c + ...) * t and 8 writes the word, the odd
    // steps letting each product reach prod_r.
    reg  [3:0]  seq;                // 0 idle, 1..8 the steps above
    reg         ch;                 // 0 left, 1 right
    reg  [15:0] t;
    reg  signed [23:0] ca, cb, cc;
    reg  signed [15:0] cx0;
    reg  signed [23:0] mul_x;
    wire signed [40:0] prod = mul_x * $signed({1'b0, t});
    reg  signed [40:0] prod_r;
    wire signed [40:0] rnd16 = (prod_r + 41'sd32768) >>> 16;
    wire signed [40:0] rnd17 = (prod_r + 41'sd65536) >>> 17;
    wire signed [40:0] y41   = {{25{cx0[15]}}, cx0} + rnd17;
    wire signed [15:0] ysat  = y41 > 41'sd32767  ? 16'sh7fff
                             : y41 < -41'sd32768 ? 16'sh8000 : y41[15:0];

    // The history of the channel being worked, sign-extended.
    wire signed [23:0] hm1 = ch ? {{8{xr[0][15]}}, xr[0]} : {{8{xl[0][15]}}, xl[0]};
    wire signed [23:0] h0  = ch ? {{8{xr[1][15]}}, xr[1]} : {{8{xl[1][15]}}, xl[1]};
    wire signed [23:0] h1  = ch ? {{8{xr[2][15]}}, xr[2]} : {{8{xl[2][15]}}, xl[2]};
    wire signed [23:0] h2  = ch ? {{8{xr[3][15]}}, xr[3]} : {{8{xl[3][15]}}, xl[3]};

    integer i;
    always @(posedge clk) begin
        if (!resetn) begin
            phase    <= 32'd0;
            integ    <= 22'sd0;
            err      <= 6'sd0;
            step     <= STEP;
            rinc     <= 1'b0;
            underrun <= 1'b0;
            seq      <= 4'd0;
            ch       <= 1'b0;
            t        <= 16'd0;
            word_l   <= 16'd0;
            word_r   <= 16'd0;
            for (i = 0; i < 4; i = i + 1) begin
                xl[i] <= 16'sd0;
                xr[i] <= 16'sd0;
            end
        end else begin
            rinc     <= 1'b0;
            underrun <= 1'b0;
            err      <= $signed({1'b0, level}) - MID;
            step     <= STEP + (err34 <<< KP_SHIFT) + (integ34 <<< KI_SHIFT);
            prod_r   <= prod;

            if (tick) begin
                phase <= sum[31:0];
                t     <= sum[31:16];
                if (sum[32]) begin
                    for (i = 0; i < 3; i = i + 1) begin
                        xl[i] <= xl[i + 1];
                        xr[i] <= xr[i + 1];
                    end
                    if (!empty) begin
                        xl[3] <= sample[31:16];
                        xr[3] <= sample[15:0];
                        rinc  <= 1'b1;
                    end else
                        underrun <= 1'b1;      // x2 held: a repeat
                end
                if (integ_nx > IMAX)
                    integ <= IMAX;
                else if (integ_nx < -IMAX)
                    integ <= -IMAX;
                else
                    integ <= integ_nx;
                seq <= 4'd1;
                ch  <= 1'b0;
            end else begin
                case (seq)
                    4'd1: begin
                        ca  <= 24'sd3 * (h0 - h1) + h2 - hm1;
                        cb  <= 24'sd2 * hm1 - 24'sd5 * h0 + 24'sd4 * h1 - h2;
                        cc  <= h1 - hm1;
                        cx0 <= h0[15:0];
                        seq <= 4'd2;
                    end
                    4'd2: begin mul_x <= ca;                seq <= 4'd3; end
                    4'd4: begin mul_x <= cb + rnd16[23:0];  seq <= 4'd5; end
                    4'd6: begin mul_x <= cc + rnd16[23:0];  seq <= 4'd7; end
                    4'd8: begin
                        if (ch) word_r <= ysat; else word_l <= ysat;
                        ch  <= 1'b1;
                        seq <= ch ? 4'd0 : 4'd1;
                    end
                    4'd0: ;
                    default: seq <= seq + 1'b1;     // 3, 5, 7: the product settles
                endcase
            end
        end
    end
endmodule
