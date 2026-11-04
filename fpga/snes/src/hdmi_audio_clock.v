// HDMI audio clock, nominally 32 kHz, locked to the S-DSP's real output rate.
//
// The SNES pauses each frame to hold 60.000 Hz HDMI, so the S-DSP makes about
// 32,127 samples/s in bursts, not 32,000. A fixed 32 kHz read dropped about
// 120 samples/s from the 16-entry FIFO, which clicked. Here clk_audio comes
// from a phase accumulator whose step is steered by the FIFO fill level (PI
// servo around MID), so samples are read exactly as fast as they are written
// and go out untouched. The HDMI core measures clk_audio to fill in CTS, so the
// sink follows the real rate.
//
// Each accumulator carry is a falling edge of clk_audio; the next sample is
// loaded then, so it is stable at the rising edge where the HDMI core takes it.

module hdmi_audio_clock #(
    parameter [31:0]  CLK_HZ   = 32'd74250000,
    parameter [31:0]  RATE_HZ  = 32'd32127,     // nominal production rate
    parameter integer KP_SHIFT = 8,         // ~0.014 % rate per sample of error
    parameter integer KI_SHIFT = 4
)(
    input             clk,
    input             resetn,
    input       [4:0] level,                // FIFO fill level, read side, 0..16
    input             empty,
    input      [31:0] sample,               // {left, right} at the FIFO head
    output reg        clk_audio,
    output reg        rinc,
    output reg [15:0] word_l,
    output reg [15:0] word_r
);
    localparam [63:0] RATE64 = {32'd0, RATE_HZ};
    localparam [63:0] CLK64  = {32'd0, CLK_HZ};
    localparam [63:0] STEP64 = (RATE64 << 32) / CLK64;
    localparam signed [31:0] STEP = STEP64[31:0];
    localparam signed [5:0]  MID  = 6'sd8;
    localparam signed [21:0] IMAX = 22'sd1 << 18;   // +/- 0.9 % after >>> KI_SHIFT

    reg [31:0] phase;
    reg signed [21:0] integ;
    // err and step are registered to keep the FIFO pointer math, the PI sum
    // and the phase add in separate cycles. The few cycles of lag are nothing
    // next to the ~2300-cycle sample period.
    reg signed [5:0]  err;
    reg signed [31:0] step;

    wire signed [31:0] err32    = {{26{err[5]}}, err};
    wire signed [31:0] integ32  = {{10{integ[21]}}, integ};
    wire        [32:0] sum      = {1'b0, phase} + {1'b0, step};
    wire signed [21:0] integ_nx = integ + {{16{err[5]}}, err};

    always @(posedge clk) begin
        if (!resetn) begin
            phase     <= 32'd0;
            integ     <= 22'sd0;
            err       <= 6'sd0;
            step      <= STEP;
            clk_audio <= 1'b0;
            rinc      <= 1'b0;
        end else begin
            err       <= $signed({1'b0, level}) - MID;
            step      <= STEP + (err32 <<< KP_SHIFT) + (integ32 >>> KI_SHIFT);
            rinc      <= 1'b0;
            phase     <= sum[31:0];
            clk_audio <= sum[31];
            if (sum[32]) begin
                if (!empty) begin
                    {word_l, word_r} <= sample;
                    rinc <= 1'b1;
                end
                if (integ_nx > IMAX)
                    integ <= IMAX;
                else if (integ_nx < -IMAX)
                    integ <= -IMAX;
                else
                    integ <= integ_nx;
            end
        end
    end
endmodule
