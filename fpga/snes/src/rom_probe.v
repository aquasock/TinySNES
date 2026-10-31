// ROM landing-offset probe, TinySNES diagnostic build (TINYSNES_ROM_CHECK).
//
// The write-count build proved the loader issues every write for a full image,
// the self-test build proved the CPU port reads back what it wrote, and the
// header parses, yet the image is not at byte 0.  So the remaining question is
// not "does it write" but "where did it land".
//
// This reads the image's first 16-bit word (bytes 0 and 1) out of eight
// candidate word addresses and lights a bar for each place it is found.  The
// candidates are the plausible displacements: none, the 64-byte header, a
// 512-byte copier header, and the small power-of-two offsets that a counting
// slip would produce.
//
// A bar is green when that address holds the sought word in either byte order,
// so a byte-swapped write still shows up instead of reading as a total failure.
// All eight red means the data is corrupted rather than merely displaced, or
// that the probe itself is broken, which the previous builds make unlikely.
//
// Runs on mclk and takes the CPU port after `loaded`, handing it back when
// `done` sets; snestang_top gates `enable` on that.

module rom_probe #(
    parameter [15:0] SEARCH = 16'hD878,   // image bytes 0,1: 78 D8
    parameter [7:0]  ACK_TIMEOUT = 8'd200,
    parameter [7:0]  DATA_WAIT   = 8'd16
)(
    input             clk,          // mclk
    input             resetn,
    input             loaded,
    input      [15:0] dout,         // cpu_port0
    output reg [21:0] addr,         // word address
    output reg        req,
    input             ack,
    output reg  [7:0] fail,         // 1 = word not found at that candidate
    output reg        done,
    output reg        timed_out
);

    localparam [3:0] S_IDLE  = 4'd0,
                     S_SETUP = 4'd1,
                     S_ACK   = 4'd2,
                     S_WAIT  = 4'd3,
                     S_FIN   = 4'd4;

    reg [3:0] st;
    reg [2:0] idx;
    reg [7:0] timer;

    // Displacements in 16-bit words: 0, 16 B, 32 B, 64 B (the SNES header),
    // 128 B, 256 B, 512 B (copier header) and 1 KiB (one loader frame).
    function [21:0] addr_of;
        input [2:0] i;
        begin
            case (i)
                3'd0:    addr_of = 22'd0;
                3'd1:    addr_of = 22'd8;
                3'd2:    addr_of = 22'd16;
                3'd3:    addr_of = 22'd32;
                3'd4:    addr_of = 22'd64;
                3'd5:    addr_of = 22'd128;
                3'd6:    addr_of = 22'd256;
                default: addr_of = 22'd512;
            endcase
        end
    endfunction

    wire swapped = {dout[7:0], dout[15:8]};

    always @(posedge clk) begin
        if (~resetn) begin
            st        <= S_IDLE;
            idx       <= 3'd0;
            timer     <= 8'd0;
            req       <= 1'b0;
            addr      <= 22'd0;
            fail      <= 8'd0;
            done      <= 1'b0;
            timed_out <= 1'b0;
        end else begin
            case (st)
            S_IDLE: begin
                if (loaded) begin
                    idx <= 3'd0;
                    st  <= S_SETUP;
                end
            end

            S_SETUP: begin
                addr  <= addr_of(idx);
                req   <= ~req;
                timer <= 8'd0;
                st    <= S_ACK;
            end

            S_ACK: begin
                timer <= timer + 8'd1;
                if (ack == req) begin
                    timer <= 8'd0;
                    st    <= S_WAIT;
                end else if (timer == ACK_TIMEOUT) begin
                    fail      <= 8'hFF;
                    done      <= 1'b1;
                    timed_out <= 1'b1;
                    st        <= S_FIN;
                end
            end

            S_WAIT: begin
                timer <= timer + 8'd1;
                if (timer == DATA_WAIT) begin
                    if (dout != SEARCH && swapped != SEARCH)
                        fail[idx] <= 1'b1;
                    if (idx == 3'd7) begin
                        done <= 1'b1;
                        st   <= S_FIN;
                    end else begin
                        idx <= idx + 3'd1;
                        st  <= S_SETUP;
                    end
                end
            end

            S_FIN: ;
            default: st <= S_IDLE;
            endcase
        end
    end

endmodule
