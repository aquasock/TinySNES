// SDRAM self-test, TinySNES diagnostic build (TINYSNES_SDRAM_TEST).
//
// Runs on fclk against the sdram_snes controller's CPU port.  No ROM is loaded
// in this build, so `loaded` stays low and the SNES machine is never enabled;
// the test owns the port outright and the loader would be ignored if used.
//
// Three sets of addresses, each written in full and then read back:
//
//   set 0  16 addresses 64 KiB apart, data = 1 << i     (walking one)
//   set 1  the same addresses,        data = ~(1 << i)  (walking zero)
//   set 2  4 addresses at 1/2/4 MiB and the last 4 KiB of bank 0,
//          data = 0xA5A5 / 0x5A5A alternating
//
// A walking pattern means a single stuck or swapped DQ bit sets exactly one bit
// of `mask`, rather than hiding behind data that happens to agree.  Walking one
// and walking zero together catch a bit stuck in either direction.
//
//   status 0 running, 1 pass (mask == 0), 2 mismatch, 3 no acknowledge
//
// mask is a MISMATCH mask: bit k set means data bit k disagreed at least once.
// snes2hdmi draws it as 16 bars across the active area, separated by gaps, red
// where the bit is set and green where it is clear, and the status as a band
// across the bottom of the picture.  See
// core-reference.md TCL-008 for what the result means.

module sdram_bist #(
    parameter [7:0] ACK_TIMEOUT = 8'd200,
    parameter [7:0] DATA_WAIT = 8'd12   // fclk from ack to sampling the read data
)(
    input             clk,              // fclk, the controller's clock
    input             resetn,
    input             ready,            // controller has finished its init
    output reg [21:0] addr,             // word address: byte address >> 1
    output reg [15:0] din,
    output reg        we,
    output reg        req,
    input             ack,
    input      [15:0] dout,             // cpu_port0
    output reg [15:0] mask,             // per-bit mismatch, sticky
    output reg  [1:0] status
);

    reg  [1:0] set;                     // 0 walking one, 1 walking zero, 2 high addresses
    reg  [3:0] idx;
    reg        phase;                   // 0 = write pass, 1 = read pass
    reg  [7:0] timer;
    reg  [2:0] st;

    localparam [2:0] S_IDLE  = 3'd0,
                     S_SETUP = 3'd1,
                     S_ACK   = 3'd2,
                     S_DATA  = 3'd3,
                     S_FIN   = 3'd4;

    wire [3:0] last_idx = (set == 2'd2) ? 4'd3 : 4'd15;

    function [23:0] byte_of;
        input [1:0] s;
        input [3:0] i;
        begin
            if (s == 2'd2)
                case (i)
                    4'd0:    byte_of = 24'h100000;
                    4'd1:    byte_of = 24'h200000;
                    4'd2:    byte_of = 24'h400000;
                    default: byte_of = 24'h7FF000;
                endcase
            else
                byte_of = {4'd0, i, 16'h0000};      // i * 64 KiB
        end
    endfunction

    function [15:0] data_of;
        input [1:0] s;
        input [3:0] i;
        begin
            case (s)
                2'd0:    data_of = 16'd1 << i;
                2'd1:    data_of = ~(16'd1 << i);
                default: data_of = i[0] ? 16'h5A5A : 16'hA5A5;
            endcase
        end
    endfunction

    wire [15:0] diff = dout ^ data_of(set, idx);

    always @(posedge clk) begin
        if (~resetn) begin
            st     <= S_IDLE;
            set    <= 2'd0;
            idx    <= 4'd0;
            phase  <= 1'b0;
            timer  <= 8'd0;
            req    <= 1'b0;
            we     <= 1'b1;
            addr   <= 22'd0;
            din    <= 16'd0;
            mask   <= 16'd0;
            status <= 2'd0;
        end else begin
            case (st)
            S_IDLE: begin
                if (ready) begin
                    set   <= 2'd0;
                    idx   <= 4'd0;
                    phase <= 1'b0;
                    st    <= S_SETUP;
                end
            end

            // Address and data are registered one cycle before the request is
            // offered, so the controller latches them and not a half-written value.
            S_SETUP: begin
                addr  <= byte_of(set, idx) >> 1;
                din   <= data_of(set, idx);
                we    <= ~phase;
                req   <= ~req;
                timer <= 8'd0;
                st    <= S_ACK;
            end

            // Pending while req and ack differ; the controller acks the request
            // it accepted by copying the new req value.
            S_ACK: begin
                timer <= timer + 8'd1;
                if (ack == req) begin
                    if (~phase) begin
                        // Write accepted.  After the last one, turn the set around
                        // and read the same addresses back.
                        if (idx == last_idx) begin
                            idx   <= 4'd0;
                            phase <= 1'b1;
                        end else begin
                            idx <= idx + 4'd1;
                        end
                        st <= S_SETUP;
                    end else begin
                        // Read accepted.  Keep idx: the compare needs it, and
                        // advancing it here would test the wrong address.
                        timer <= 8'd0;
                        st    <= S_DATA;
                    end
                end else if (timer == ACK_TIMEOUT) begin
                    status <= 2'd3;                 // never acknowledged
                    st     <= S_FIN;
                end
            end

            // Read data lands in cpu_port0 a few fclk after the ack; wait well
            // past that (DATA_WAIT > the controller's CAS-to-capture distance).
            // Every address in the set is read back: only the last one finishes
            // the set, or the mask would cover a single address per pattern.
            S_DATA: begin
                timer <= timer + 8'd1;
                if (timer == DATA_WAIT) begin
                    mask <= mask | diff;
                    if (idx != last_idx) begin
                        idx <= idx + 4'd1;
                        st  <= S_SETUP;
                    end else if (set == 2'd2) begin
                        status <= ((mask | diff) == 16'd0) ? 2'd1 : 2'd2;
                        st     <= S_FIN;
                    end else begin
                        phase <= 1'b0;
                        set   <= set + 2'd1;
                        idx   <= 4'd0;
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
