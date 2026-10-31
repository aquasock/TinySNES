// ARAM self-test, TinySNES diagnostic build (TINYSNES_ARAM_TEST).
//
// Runs on fclk against the sdram_snes controller's ARAM port -- the second CPU
// port, the one the SPC700 loads its driver through.  Like the SDRAM test, no
// ROM is loaded in this build, so `loaded` stays low and the SNES machine is
// never enabled; the test owns the ARAM port outright.
//
// Why this port and why now: the APU probe (core-log entry 8) found the 65816
// writing $89 into the APU port while the SPC700 was executing code at $F4xx
// inside ARAM rather than sitting in its IPL ROM.  The SPC only reaches ARAM by
// taking the IPL's JMP into uploaded code, and the driver it uploads arrives
// through this port, whose sample point moved from cycle[1] to cycle[2] in
// core-log entry 3 and which nothing has tested since.  A port that stores the
// wrong byte in either lane would leave the SPC running garbage and never
// echoing the 65816's byte back, which is what the machine does.
//
// The test is deliberately byte-lane aware, because byte-lane selection is the
// part of this port most likely to be wrong and is invisible to a word test:
// for each word it writes a *different* byte to the even address and the odd
// address, then reads the word back and expects both lanes.  A swapped lane
// pair therefore fails on all 16 bits instead of passing by symmetry.  The
// controller writes one lane at a time by masking the other with DQM
// (next_ds[1] = {aram_addr[0], ~aram_addr[0]}), so the second write must not
// disturb the first byte, and the read must return both.
//
//   mask bit k,   k = 0..7  : mismatch on the even-lane byte, data bit k
//   mask bit k+8, k = 0..7  : mismatch on the odd-lane byte,  data bit k
//
// Sets, each written in full and then read back:
//
//   set 0  8 words, walking one on the even lane, odd lane its complement
//   set 1  8 words, walking one on the odd lane,  even lane its complement
//   set 2  8 words, walking zero on both lanes
//   set 3  4 high words across the 64 KiB space, 0xA5/0x5A on the two lanes
//
// Walking one and walking zero together catch a bit stuck in either direction,
// and doing it on each lane separately catches a byte that lands in the wrong
// half of the word.
//
//   status 0 running, 1 pass (mask == 0), 2 mismatch, 3 no acknowledge
//
// snes2hdmi draws the mask as 16 bars, red where the bit is set, over a status
// band, exactly as TINYSNES_SDRAM_TEST does, so one build's readout is decoded
// by the same tool as the other's.  See core-reference.md TCL-008.

module aram_bist #(
    parameter [7:0] ACK_TIMEOUT = 8'd200,
    parameter [7:0] DATA_WAIT   = 8'd12   // fclk from ack to sampling the read data
)(
    input             clk,              // fclk, the controller's clock
    input             resetn,
    input             ready,            // controller has finished its init
    output reg [15:0] addr,             // ARAM byte address
    output reg  [7:0] din,              // one byte; the controller duplicates it
    output reg        we,
    output reg        req,
    input             ack,
    input      [15:0] dout,             // the whole word: {odd lane, even lane}
    output reg [15:0] mask,             // per-bit mismatch, sticky
    output reg  [1:0] status
);

    reg  [1:0] set;                     // 0 even one, 1 odd one, 2 walking zero, 3 high
    reg  [2:0] idx;
    reg  [1:0] phase;                   // 0 write even, 1 write odd, 2 read
    reg  [7:0] timer;
    reg  [2:0] st;

    localparam [2:0] S_IDLE = 3'd0,
                     S_SETUP = 3'd1,
                     S_ACK   = 3'd2,
                     S_DATA  = 3'd3,
                     S_FIN   = 3'd4;

    wire [2:0] last_idx = (set == 2'd3) ? 3'd3 : 3'd7;

    // Word addresses.  Sets 0-2 spread eight words across the 64 KiB space; the
    // high set takes the first, the two middle and the last word of it.
    function [15:0] word_of;
        input [1:0] s;
        input [2:0] i;
        begin
            if (s == 2'd3)
                case (i)
                    3'd0:    word_of = 16'h0000;
                    3'd1:    word_of = 16'h4000;
                    3'd2:    word_of = 16'h8000;
                    default: word_of = 16'hFFFE;
                endcase
            else
                word_of = {5'd0, i, 8'h00};     // i * 0x1000, up to 0x7000
        end
    endfunction

    // The byte written to each lane.  The two lanes always differ, so a lane swap
    // cannot pass.
    function [7:0] even_of;
        input [1:0] s;
        input [2:0] i;
        begin
            case (s)
                2'd0:    even_of = 8'd1 << i;
                2'd1:    even_of = ~(8'd1 << i);
                2'd2:    even_of = ~(8'd1 << i);
                default: even_of = i[0] ? 8'hA5 : 8'h5A;
            endcase
        end
    endfunction

    function [7:0] odd_of;
        input [1:0] s;
        input [2:0] i;
        begin
            case (s)
                2'd0:    odd_of = ~(8'd1 << i);
                2'd1:    odd_of = 8'd1 << i;
                2'd2:    odd_of = ~(8'd1 << i);
                default: odd_of = i[0] ? 8'h5A : 8'hA5;
            endcase
        end
    endfunction

    wire [15:0] want = {odd_of(set, idx), even_of(set, idx)};
    wire [15:0] diff = dout ^ want;

    always @(posedge clk) begin
        if (~resetn) begin
            st     <= S_IDLE;
            set    <= 2'd0;
            idx    <= 3'd0;
            phase  <= 2'd0;
            timer  <= 8'd0;
            req    <= 1'b0;
            we     <= 1'b1;
            addr   <= 16'd0;
            din    <= 8'd0;
            mask   <= 16'd0;
            status <= 2'd0;
        end else begin
            case (st)
            S_IDLE: begin
                if (ready) begin
                    set   <= 2'd0;
                    idx   <= 3'd0;
                    phase <= 2'd0;
                    st    <= S_SETUP;
                end
            end

            // Address and data are registered one cycle before the request is
            // offered, so the controller latches them and not a half-written
            // value.  The even and odd writes address the same word through
            // addr[0], which is what selects the lane.
            S_SETUP: begin
                addr  <= (phase == 2'd1) ? (word_of(set, idx) | 16'h0001)
                                         : word_of(set, idx);
                din   <= (phase == 2'd1) ? odd_of(set, idx) : even_of(set, idx);
                we    <= (phase != 2'd2);
                req   <= ~req;
                timer <= 8'd0;
                st    <= S_ACK;
            end

            // Pending while req and ack differ; the controller acks the request
            // it accepted by copying the new req value.
            S_ACK: begin
                timer <= timer + 8'd1;
                if (ack == req) begin
                    if (phase != 2'd2) begin
                        // A write was accepted.  The next one is the other lane,
                        // or the read that turns the word around.
                        phase <= phase + 2'd1;
                        st    <= S_SETUP;
                    end else begin
                        // Read accepted.  Keep idx and set: the compare needs them.
                        timer <= 8'd0;
                        st    <= S_DATA;
                    end
                end else if (timer == ACK_TIMEOUT) begin
                    status <= 2'd3;                 // never acknowledged
                    st     <= S_FIN;
                end
            end

            // Read data lands in aram_dout a few fclk after the ack.  Wait well
            // past that; DATA_WAIT is comfortably above the controller's
            // CAS-to-capture distance, which is the same for both ports.
            S_DATA: begin
                timer <= timer + 8'd1;
                if (timer == DATA_WAIT) begin
                    mask <= mask | diff;
                    if (idx != last_idx) begin
                        idx   <= idx + 3'd1;
                        phase <= 2'd0;
                        st    <= S_SETUP;
                    end else if (set == 2'd3) begin
                        status <= ((mask | diff) == 16'd0) ? 2'd1 : 2'd2;
                        st     <= S_FIN;
                    end else begin
                        set   <= set + 2'd1;
                        idx   <= 3'd0;
                        phase <= 2'd0;
                        st    <= S_SETUP;
                    end
                end
            end

            S_FIN: ;                    // hold the result until reset
            default: st <= S_IDLE;
            endcase
        end
    end

endmodule
