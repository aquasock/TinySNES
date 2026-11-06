// TinySNES: the master volume, applied once to the one sample pair both
// outputs play.
//
// This sits between the S-DSP and its two consumers -- snes2hdmi for HDMI and
// i2s_out for the Pmod I2S2 -- because they play the same stream and a volume
// that reached only one of them would be a per-output control, not a master
// one.  It is a separate module rather than an expression in the top level so
// that a testbench instantiates the arithmetic the board runs; a rule restated
// inside a testbench only proves the restatement agrees with itself (core-log
// entry 19).
//
// The gain is 256 at unity, 0 at silence, and comes from the desktop window as
// frame 0x1C.  It arrives as a 9-bit value because 256 needs nine bits, and
// anything above 256 is clamped to unity here: a gain above one is a loudness
// claim this path must not honour, since it would push a full-scale voice into
// hard clipping.
//
// `gain` is computed on the BL616 and not here.  The curve the player feels --
// TinyNES squares the percentage so each 5 percent step is about as large as
// the last, out of TN_VOLUME_UNITY 256 -- is therefore owned in one place, in
// C where it can be tested, instead of duplicated as a lookup table in fabric
// that would silently drift from it.
//
// Arithmetic: the sample is signed 16-bit and the gain is at most 256, so the
// product needs 25 bits and the result of the divide is always back inside 16
// bits -- a full-scale sample scaled by unity is itself.  That means there is
// no saturation case to get wrong.  Rounding adds half an LSB before the shift
// so the error is half an LSB rather than a full one, and at gain 256 the sum
// lands exactly on the original sample, which is what makes "100 percent is
// indistinguishable from no volume control at all" a property of the
// arithmetic rather than a hope.
//
// Latency is one mclk: `out_*` and `out_ready` are registered together, so a
// consumer that takes `out_l` when `out_ready` is high sees a consistent pair
// one clock after the S-DSP produced it.  Both consumers already latch on the
// ready pulse, and one clock at 21.5 MHz is 46 ns.
//
// SPDX-License-Identifier: MIT

module audio_volume (
    input      [15:0] audio_l,
    input      [15:0] audio_r,
    input             audio_ready,   // one-clock pulse beside the pair
    input       [8:0] gain,          // 256 is unity
    output reg [15:0] out_l,
    output reg [15:0] out_r,
    output reg        out_ready,
    input             clk,
    input             resetn
);

// Unity is the maximum the path honours; a host sending more is clamped rather
// than trusted.
wire [8:0] gain_used = (gain > 9'd256) ? 9'd256 : gain;

// Signed 16 x unsigned 9 into 25 bits, then round by adding 128 and shift by 8.
// The shift is arithmetic because the product is signed, which floors rather
// than truncating toward zero; at unity the remainder is exactly 128 so the
// floor lands on the original sample either side of zero.
function [15:0] scale;
    input signed [15:0] sample;
    input        [8:0]  g;
    reg   signed [24:0] product;
    begin
        product = sample * $signed({1'b0, g});
        scale   = $signed(product + 25'sd128) >>> 8;
    end
endfunction

wire [15:0] scaled_l = scale($signed(audio_l), gain_used);
wire [15:0] scaled_r = scale($signed(audio_r), gain_used);

always @(posedge clk) begin
    if (!resetn) begin
        out_l     <= 16'd0;
        out_r     <= 16'd0;
        out_ready <= 1'b0;
    end else begin
        out_ready <= audio_ready;
        if (audio_ready) begin
            out_l <= scaled_l;
            out_r <= scaled_r;
        end
    end
end

endmodule
