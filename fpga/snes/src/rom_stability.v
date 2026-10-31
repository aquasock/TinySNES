// Read-stability self-test, TinyNES diagnostic build (TINYSNES_READ_STABILITY).
//
// Why this and not another state probe: four consecutive loads of the same image
// produced four different failure shapes (core-log entries 14, 15, 16) -- a SPC
// that never advanced, a SPC mid-copy, and a 65816 that entered its upload routine
// four times and then executed at $7C7C, which is below the LoROM window where no
// code exists.  A failure that changes shape between boots of unchanged code is
// not a logic error in either program.  The two surviving explanations are that
// the machine reads wrong data, or that it races, and this test answers the first
// one directly instead of inferring it.
//
// The specific hazard it is built for is core-log entry 5's: the SDRAM answers a
// CPU-port read four master clocks into an access the CPU latches at seven, and a
// refresh that takes the slot returns stale data, on which the CPU then executes a
// corrupted instruction.  So the test reads the SAME address twice and compares,
// over enough iterations to span thousands of refresh periods -- the controller
// refreshes every 501 fclk whether or not anything else is happening, so a
// collision needs no traffic from the machine to occur.
//
// It runs after `loaded`, owns the CPU port until `done`, and `enable` is gated on
// `done` exactly as the ROM landing probe's is, so the image is never disturbed
// while the port is under test.
//
// The mismatch count is SATURATING at 0xFFFF and is drawn as 16 bars, red where a
// bit is set, so an all-green picture means every double-read agreed.  The status
// band is green for a completed run with no mismatch, red when the count is
// non-zero, blue while running, and yellow when a request was never acknowledged.

module rom_stability #(
    parameter [7:0]  ACK_TIMEOUT = 8'd200,
    parameter [7:0]  DATA_WAIT   = 8'd16,
    parameter [15:0] ITERATIONS  = 16'd4096
)(
    input             clk,              // mclk
    input             resetn,
    input             loaded,
    input      [15:0] dout,             // cpu_port0
    output reg [21:0] addr,             // word address
    output reg        req,
    input             ack,
    output reg [15:0] mism,             // saturating mismatch count
    output reg  [1:0] status,           // 0 running, 1 pass, 2 mismatches, 3 no ack
    output reg        done
);

    localparam [3:0] S_IDLE  = 4'd0,
                     S_SETUP = 4'd1,
                     S_ACK   = 4'd2,
                     S_WAIT  = 4'd3,
                     S_FIN   = 4'd4;

    reg [3:0]  st;
    reg [2:0]  idx;                     // which address in the set
    reg        half;                    // 0 first read of the pair, 1 second
    reg [15:0] first_word;              // what the first read returned
    reg [15:0] iter;                    // iterations still to run
    reg [15:0] next_mism;               // combinational helper for this pair
    reg [7:0]  timer;

    // Eight word addresses spread across a 1 MiB image, so a displacement or a
    // bank-selection fault shows up as a mismatch on some of them rather than
    // being averaged away.
    function [21:0] addr_of;
        input [2:0] i;
        begin
            case (i)
                3'd0:    addr_of = 22'd0;
                3'd1:    addr_of = 22'd40;         //  80 bytes in
                3'd2:    addr_of = 22'd400;        //   800 bytes
                3'd3:    addr_of = 22'd1000;       //     2 KiB
                3'd4:    addr_of = 22'd4000;       //     8 KiB
                3'd5:    addr_of = 22'd10000;      //    32 KiB
                3'd6:    addr_of = 22'd20000;      //    64 KiB
                default: addr_of = 22'd40000;      //   128 KiB
            endcase
        end
    endfunction

    always @(posedge clk) begin
        if (~resetn) begin
            st         <= S_IDLE;
            idx        <= 3'd0;
            half       <= 1'b0;
            first_word <= 16'd0;
            iter       <= ITERATIONS;
            timer      <= 8'd0;
            req        <= 1'b0;
            addr       <= 22'd0;
            mism       <= 16'd0;
            status     <= 2'd0;
            done       <= 1'b0;
        end else begin
            case (st)
            S_IDLE: begin
                if (loaded) begin
                    idx    <= 3'd0;
                    half   <= 1'b0;
                    iter   <= ITERATIONS;
                    st     <= S_SETUP;
                end
            end

            // Address is registered one cycle before the request is offered, so
            // the controller latches a settled value.
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
                    status <= 2'd3;                 // never acknowledged
                    done   <= 1'b1;
                    st     <= S_FIN;
                end
            end

            // Read data lands in cpu_port0 a few fclk after the ack.  Wait well
            // past that; DATA_WAIT is comfortably above the controller's
            // CAS-to-capture distance.
            S_WAIT: begin
                timer <= timer + 8'd1;
                if (timer == DATA_WAIT) begin
                    if (~half) begin
                        first_word <= dout;
                        half       <= 1'b1;
                        st         <= S_SETUP;      // same address, second read
                    end else begin
                        half <= 1'b0;
                        // The count for this pair, computed once and used both
                        // for the register and for the final verdict, so the
                        // verdict cannot disagree with the displayed count.
                        next_mism = mism + ((dout != first_word && mism != 16'hFFFF) ? 16'd1 : 16'd0);
                        mism <= next_mism;
                        if (idx == 3'd7) begin
                            idx <= 3'd0;
                            if (iter == 16'd1) begin
                                status <= (next_mism == 16'd0) ? 2'd1 : 2'd2;
                                done   <= 1'b1;
                                st     <= S_FIN;
                            end else begin
                                iter <= iter - 16'd1;
                                st   <= S_SETUP;
                            end
                        end else begin
                            idx <= idx + 3'd1;
                            st  <= S_SETUP;
                        end
                    end
                end
            end

            S_FIN: ;                    // hold the result until reset
            default: st <= S_IDLE;
            endcase
        end
    end

endmodule
