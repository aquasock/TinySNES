// SPDX-License-Identifier: GPL-3.0-only
//
// Bench for iosys_bl616's pad frames other than the 0x03 report itself, which
// dbg_link_tb covers:
//
//   * 0x21 out: the wired Classic's report (wii_pad.sv `report`), type 0x21,
//     length 7, bytes 0 to 3, 6 and 7 in that order; one at every report tick
//     while wii_valid is high and none while it is low; every frame one whole
//     value of wii_report even while it changes; and the 0x03 report still
//     delivered when a button changes while they flow.
//   * 0x09 in: Bluetooth pads 1 and 2 taken whole on the fourth byte, a frame
//     cut short changing nothing, and both let go HID_HOLD_CLOCKS after the
//     last frame but never while frames keep coming.
//   * Bluetooth pad 1's HOME (bit 12) and SELECT acting in the gestures as the
//     wired pad's do: a HOME tap is LB, HOME with SELECT is the exit bit 15,
//     with either half from either pad; and its other buttons stay out of the
//     0x03 word, which is the wired pad's.
//
// The report tick is 2,000 clocks (93 us) rather than 20 ms, long enough that
// a 0x21 frame (50 us on the wire) fits inside one, so the one-per-tick
// cadence is visible.
//
//   tools/sim/run_pad_link_sim.sh

`timescale 1ns/1ps

module pad_link_tb;

localparam real CLK_NS = 1e9 / 21_484_000.0;
localparam real BIT_NS = 500.0;                 // 2 Mbaud
localparam integer REPORT_CLOCKS = 2000;
localparam integer HID_HOLD_CLOCKS = 12000;     // 6 ticks, 559 us
localparam real TICK_NS = CLK_NS * REPORT_CLOCKS;
localparam real HOLD_NS = CLK_NS * HID_HOLD_CLOCKS;

reg clk = 0;
always #(CLK_NS/2) clk = ~clk;
reg resetn = 0;

reg  uart_rx = 1;
wire uart_tx;
reg  [11:0] joy1 = 0;
reg         home = 0;
reg  [47:0] wii_report = 48'd0;
reg         wii_valid = 1'b0;
wire [15:0] hid1, hid2;

iosys_bl616 #(.CORE_ID(2), .FREQ(21_484_000), .REPORT_CLOCKS(REPORT_CLOCKS),
              .HID_HOLD_CLOCKS(HID_HOLD_CLOCKS)) iosys (
    .clk(clk), .hclk(clk), .resetn(resetn),
    .overlay(), .overlay_x(8'd0), .overlay_y(8'd0), .overlay_color(),
    .joy1(joy1), .joy2(12'd0), .hid1(hid1), .hid2(hid2), .home(home),
    .wii_report(wii_report), .wii_valid(wii_valid),
    .desk_on(), .desk_wr_tog(), .desk_wr_addr(), .desk_wr_data(),
    .uart_tx(uart_tx), .uart_rx(uart_rx),
    .rom_loading(), .rom_do(), .rom_do_valid(),
    .sav_addr(), .sav_wdata(), .sav_we(), .sav_rdata(8'd0),
    .pad_map(), .video_aspect(), .video_overscan(), .audio_gain(),
    .mgmt_address(), .mgmt_read(), .mgmt_readdata(16'd0), .mgmt_write(),
    .mgmt_writedata(), .fdd_request(2'b00), .kbd_data_valid(), .core_config(),
    .debug_address(), .debug_wdata(), .debug_valid(), .debug_write(),
    .debug_rdata(32'd0)
);

// ------------------------------------------------------------ host model
task automatic send_byte(input [7:0] b);
    integer i;
    begin
        uart_rx = 0; #(BIT_NS);
        for (i = 0; i < 8; i = i + 1) begin uart_rx = b[i]; #(BIT_NS); end
        uart_rx = 1; #(BIT_NS);
    end
endtask

// Frame 0x09 with `n` of its four payload bytes (n = 4 is a whole frame).
task automatic pads(input [15:0] p1, input [15:0] p2, input integer n);
    reg [31:0] body;
    integer i;
    begin
        body = {p1, p2};
        send_byte(8'hAA); send_byte(8'h00); send_byte(n + 1); send_byte(8'h09);
        for (i = 0; i < n; i = i + 1) send_byte(body[31 - 8*i -: 8]);
    end
endtask

// Receiver: every byte the FPGA sends goes into rxq.
reg [7:0] rxq [0:65535];
time rxt [0:65535];
integer rx_wr = 0, rx_rd = 0;
initial begin : rx
    integer i;
    reg [7:0] b;
    forever begin
        @(negedge uart_tx);
        #(BIT_NS * 1.5);
        for (i = 0; i < 8; i = i + 1) begin b[i] = uart_tx; #(BIT_NS); end
        rxq[rx_wr % 65536] = b;
        rxt[rx_wr % 65536] = $time;
        rx_wr = rx_wr + 1;
    end
end

integer fails = 0;
task automatic ok(input bit cond, input [8*64-1:0] what);
    if (!cond) begin $display("FAIL: %0s", what); fails = fails + 1; end
    else             $display("ok    %0s", what);
endtask

task automatic get_byte(output [7:0] b, output time t);
    integer guard;
    begin
        guard = 0;
        while (rx_rd == rx_wr) begin
            #(BIT_NS);
            guard = guard + 1;
            if (guard > 4000) begin
                $display("FAIL: timeout waiting for a byte"); $finish;
            end
        end
        b = rxq[rx_rd % 65536];
        t = rxt[rx_rd % 65536];
        rx_rd = rx_rd + 1;
    end
endtask

// The next frame: its type, payload length and up to eight payload bytes,
// and when its first byte finished.
task automatic next_frame(output [7:0] typ, output integer n, output [63:0] body,
                          output time t0);
    reg [7:0] b;
    reg [15:0] len;
    time t;
    integer i;
    begin
        get_byte(b, t0);
        if (b != 8'hAA) begin $display("FAIL: frame start %02x", b); $finish; end
        get_byte(b, t); len[15:8] = b;
        get_byte(b, t); len[7:0] = b;
        get_byte(typ, t);
        n = len - 1;
        body = 64'd0;
        for (i = 0; i < n; i = i + 1) begin
            get_byte(b, t);
            if (i < 8) body[8*i +: 8] = b;
        end
    end
endtask

// Drop everything received so far, once the line has been quiet for 25 bit
// times -- a frame's bytes follow each other with no gap -- so the next byte
// read is the start of a frame, not the middle of one.
task automatic drain;
    integer seen, quiet;
    begin
        seen = rx_wr;
        quiet = 0;
        while (quiet < 25) begin
            #(BIT_NS);
            if (rx_wr != seen) begin seen = rx_wr; quiet = 0; end
            else quiet = quiet + 1;
        end
        rx_rd = rx_wr;
    end
endtask

// Read frames for `span` ns; count each type and keep the 0x03 words seen.
integer n21, n03, bad21, bad_len;
reg [15:0] or03;                    // every 0x03 joy1 word ORed together
reg [15:0] last03;
time t21_first, t21_last;
reg [47:0] last21;
// A 0x21 payload is "whole" when it is one value of the bench's pattern:
// byte i is v + i for some v.
function automatic bit whole21(input [47:0] p);
    integer i;
    begin
        whole21 = 1;
        for (i = 1; i < 6; i = i + 1)
            if (p[8*i +: 8] != p[7:0] + i[7:0]) whole21 = 0;
    end
endfunction
task automatic watch(input real span, input bit check_whole, input [47:0] want);
    reg [7:0] typ;
    integer n;
    reg [63:0] body;
    time t0, stop;
    begin
        n21 = 0; n03 = 0; bad21 = 0; bad_len = 0; or03 = 0; last03 = 0;
        stop = $time + span;
        while ($time < stop) begin
            if (rx_rd == rx_wr)
                #(BIT_NS);
            else begin
                next_frame(typ, n, body, t0);
                if (typ == 8'h21) begin
                    if (n != 6) bad_len = bad_len + 1;
                    if (n21 == 0) t21_first = t0;
                    t21_last = t0;
                    n21 = n21 + 1;
                    last21 = body[47:0];
                    if (check_whole ? !whole21(body[47:0]) : body[47:0] !== want) begin
                        if (bad21 < 3) $display("      0x21 payload %012h", body[47:0]);
                        bad21 = bad21 + 1;
                    end
                end else if (typ == 8'h03) begin
                    if (n != 4) bad_len = bad_len + 1;
                    n03 = n03 + 1;
                    last03 = {body[7:0], body[15:8]};
                    or03 = or03 | last03;
                end else begin
                    $display("FAIL: unexpected frame type %02x", typ); fails = fails + 1;
                end
            end
        end
    end
endtask

// The pattern value v: bytes v, v+1, ... v+5, byte 0 in 7:0.
function automatic [47:0] pat(input [7:0] v);
    pat = {v + 8'd5, v + 8'd4, v + 8'd3, v + 8'd2, v + 8'd1, v};
endfunction

// While the report flows, move wii_report to a new pattern value at a time
// unrelated to the tick, so some frames are taken just as it changes.
reg churn = 1'b0;
initial begin : churner
    reg [7:0] v;
    v = 8'h40;
    forever begin
        #(TICK_NS * 0.37);
        if (churn) begin
            v = v + 8'd7;
            wii_report = pat(v);
        end
    end
end

initial begin : main
    real gap;
    time t;
    $display("pad_link bench: frames 0x21 and 0x09");
    #(CLK_NS * 20);
    resetn = 1;

    // ---- 0x21 out
    watch(TICK_NS * 30, 0, 48'd0);
    ok(n21 == 0, "no 0x21 while there is no report");

    wii_report = 48'h665544332211;          // r7 r6 r3 r2 r1 r0, r0 in 7:0
    wii_valid = 1'b1;
    drain;
    watch(TICK_NS * 40, 0, 48'h665544332211);
    $display("      %0d frames of 0x21 in 40 ticks", n21);
    ok(n21 >= 39 && n21 <= 41, "one 0x21 at every tick");
    ok(bad21 == 0 && bad_len == 0, "0x21 is length 7, bytes 0 to 3, 6, 7 in order");
    gap = (t21_last - t21_first) / (n21 - 1.0);
    ok(gap > TICK_NS * 0.98 && gap < TICK_NS * 1.02, "0x21 a tick apart");

    // The pad still reports while 0x21 flows.
    joy1 = 12'h010;                         // UP
    watch(TICK_NS * 10, 0, 48'h665544332211);
    ok((or03 & 16'h0010) != 0 && n21 >= 9, "0x03 reports a change among the 0x21 frames");
    joy1 = 12'h000;

    // Changing under the sender: every frame one whole value.
    churn = 1'b1;
    watch(TICK_NS * 200, 1, 48'd0);
    churn = 1'b0;
    $display("      %0d frames of 0x21 while it changed, %0d not whole", n21, bad21);
    ok(n21 >= 195 && bad21 == 0, "every 0x21 one whole report");

    wii_valid = 1'b0;
    #(TICK_NS * 2);
    drain;
    watch(TICK_NS * 30, 0, 48'd0);
    ok(n21 == 0, "no 0x21 once the controller is gone");

    // ---- 0x09 in
    pads(16'h1a2b, 16'h3c4d, 4);
    #(BIT_NS * 4);
    ok(hid1 === 16'h1a2b && hid2 === 16'h3c4d, "0x09 sets both pads");
    pads(16'h0000, 16'h0000, 3);            // cut short
    #(BIT_NS * 4);
    ok(hid1 === 16'h1a2b && hid2 === 16'h3c4d, "a short 0x09 changes nothing");

    // Held while renewed: a frame every half hold for three holds.
    repeat (6) begin
        pads(16'h0101, 16'h0202, 4);
        #(HOLD_NS * 0.5 - BIT_NS * 80);
        if (hid1 !== 16'h0101 || hid2 !== 16'h0202) begin
            $display("FAIL: renewed pads let go"); fails = fails + 1;
        end
    end
    ok(hid1 === 16'h0101 && hid2 === 16'h0202, "renewed pads stay held");
    // The last frame ended about a half hold ago: still held at 0.9 of it ...
    #(HOLD_NS * 0.4);
    ok(hid1 === 16'h0101, "held until the hold runs out");
    // ... and let go by 1.1.
    #(HOLD_NS * 0.2);
    ok(hid1 === 16'h0000 && hid2 === 16'h0000, "let go a hold after the last frame");

    // ---- Bluetooth pad 1 in the gestures.  The pads are sent every tick, as
    // TinyTang sends them every 40 ms poll, so they do not lapse meanwhile.
    drain;
    // HOME tap from the Bluetooth pad: LB.
    pads(16'h1000, 0, 4); #(TICK_NS * 3);
    pads(16'h0000, 0, 4);
    watch(TICK_NS * 6, 0, 48'd0);
    ok((or03 & 16'h0400) != 0 && (or03 & 16'h8000) == 0, "Bluetooth HOME tap is LB");
    watch(TICK_NS * 14, 0, 48'd0);
    ok(last03 == 16'h0000, "and the tap ends");

    // HOME with SELECT from the Bluetooth pad: the exit, no LB.
    repeat (4) begin pads(16'h1004, 0, 4); #(TICK_NS); end
    watch(TICK_NS * 3, 0, 48'd0);
    ok(last03 == 16'h8000, "Bluetooth HOME+SELECT is the exit");
    pads(16'h0000, 0, 4);
    watch(TICK_NS * 20, 0, 48'd0);
    ok((or03 & 16'h0400) == 0 && last03 == 16'h0000, "exit released, no LB");

    // Halves from different pads: wired SELECT, Bluetooth HOME.
    joy1 = 12'h004;
    repeat (4) begin pads(16'h1000, 0, 4); #(TICK_NS); end
    watch(TICK_NS * 3, 0, 48'd0);
    ok(last03 == 16'h8000, "wired SELECT + Bluetooth HOME is the exit");
    pads(16'h0000, 0, 4);
    joy1 = 12'h000;
    watch(TICK_NS * 20, 0, 48'd0);
    ok((or03 & 16'h0400) == 0, "and opens no desk");
    // ... and Bluetooth SELECT with the wired HOME.
    home = 1'b1;
    repeat (4) begin pads(16'h0004, 0, 4); #(TICK_NS); end
    watch(TICK_NS * 3, 0, 48'd0);
    ok(last03 == 16'h8000, "Bluetooth SELECT + wired HOME is the exit");
    pads(16'h0000, 0, 4);
    home = 1'b0;
    watch(TICK_NS * 20, 0, 48'd0);
    ok((or03 & 16'h0400) == 0, "and opens no desk");

    // HOME on the Bluetooth pad with B held: a chord, not a tap.
    repeat (4) begin pads(16'h1001, 0, 4); #(TICK_NS); end
    pads(16'h0000, 0, 4);
    watch(TICK_NS * 20, 0, 48'd0);
    ok((or03 & 16'h0400) == 0, "Bluetooth HOME with B is no tap");

    // The Bluetooth pad's buttons are not the 0x03 word's.
    repeat (6) begin pads(16'h0fff, 0, 4); #(TICK_NS); end
    watch(TICK_NS * 3, 0, 48'd0);
    ok(or03 == 16'h0000, "Bluetooth buttons stay out of the 0x03 word");
    pads(16'h0000, 0, 4);

    if (fails == 0) $display("PASS");
    else            $display("FAIL: %0d checks", fails);
    $finish;
end

endmodule
