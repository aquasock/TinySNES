// The pad map: twelve 4-bit selectors applied to the 12-bit SNES pad word.
//
// Written as its own module rather than inline in the top level so the link
// bench can instantiate the same logic the board runs.  A remap tested by
// re-deriving the rule in the testbench proves nothing about the hardware; this
// way the bench checks the module, and the top level instantiates that module.
//
// `map` holds selector i in bits 4*i+3 downto 4*i, in the order the pad word
// carries the buttons: bit 11 R, 10 L, 9 X, 8 A, 7 RT, 6 LT, 5 DN, 4 UP,
// 3 START, 2 SELECT, 1 Y, 0 B.  Selector i names the SOURCE button that drives
// output button i, so the identity map is 0,1,2,...,11 and reproduces the
// wiring exactly.  A selector of 12 to 15 means that button is not produced,
// which is how a player removes a binding rather than moving it.
//
// SPDX-License-Identifier: MIT

module pad_remap (
    input  [47:0] map,
    input  [11:0] src,
    output [11:0] out
);

genvar i;
generate
    for (i = 0; i < 12; i = i + 1) begin : button
        wire [3:0] sel = map[4*i +: 4];
        // A variable bit select is a plain mux in fabric; the comparison keeps
        // 12..15 out of the select rather than wrapping them onto a real bit.
        assign out[i] = (sel < 4'd12) ? src[sel] : 1'b0;
    end
endgenerate

endmodule
