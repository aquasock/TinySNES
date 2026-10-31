`timescale 1ns/1ps

// Bench for fpga/snes/src/aram_bist.v.
//
// The module under test is compiled from the shipping file, not retyped, so the
// bench always exercises what the board runs.
//
// The model behind the port reproduces the two things this test exists to
// catch.  A write is one byte into one lane, selected by addr[0], with the other
// lane left alone -- because that is what the controller does with
// next_ds[1] = {aram_addr[0], ~aram_addr[0]} on a duplicated data bus.  A read
// returns the whole word, {odd lane, even lane}.  Four memory models are run
// against the same DUT:
//
//   good     stores both lanes correctly                     -> PASS
//   swap     stores the byte in the other lane                -> FAIL, every bit
//   stuck    one data bit never leaves zero                   -> FAIL, that bit
//   noack    never acknowledges                              -> status 3
//
// A test that reported PASS on the 'good' model only would prove nothing, so the
// bench fails unless the three defective models are each caught.

module aram_bist_tb;

    // ---------------------------------------------------------------- model
    // 0 good, 1 swap, 2 stuck-low bit 3, 3 no acknowledge
    integer mode;

    reg         clk = 0;
    reg         resetn;
    reg         ready;
    wire [15:0] addr;
    wire  [7:0] din;
    wire        we, req;
    wire [15:0] dout;
    wire [15:0] mask;
    wire  [1:0] status;

    reg         ack = 0;
    reg  [15:0] mem [0:32767];      // 64 KiB as 32K words
    reg  [15:0] rd_word;
    integer     errors = 0;
    integer     timeout;

    always #5 clk = ~clk;

    aram_bist dut (
        .clk(clk), .resetn(resetn), .ready(ready),
        .addr(addr), .din(din), .we(we), .req(req), .ack(ack),
        .dout(dout), .mask(mask), .status(status)
    );

    // The controller: acknowledge a pending request, and perform it.
    always @(posedge clk) begin
        if (~resetn) begin
            ack <= 1'b0;
        end else if (ack != req) begin
            if (mode != 3) begin
                ack <= req;
                if (we) begin
                    // One byte into one lane; the other lane is untouched.
                    if (mode == 1) begin
                        // swap: the byte lands in the lane it was not addressed to
                        if (addr[0]) mem[addr[15:1]][7:0]  <= din;
                        else         mem[addr[15:1]][15:8] <= din;
                    end else if (mode == 2) begin
                        if (addr[0]) mem[addr[15:1]][15:8] <= din & 8'hF7;  // bit 3 stuck low
                        else         mem[addr[15:1]][7:0]  <= din & 8'hF7;
                    end else begin
                        if (addr[0]) mem[addr[15:1]][15:8] <= din;
                        else         mem[addr[15:1]][7:0]  <= din;
                    end
                end else begin
                    rd_word = mem[addr[15:1]];
                    if (mode == 2) rd_word = rd_word & 16'hFFF7;
                end
            end
        end
    end

    // The controller returns read data a few clocks after the ack, which is what
    // DATA_WAIT in the DUT is sized for.
    reg [15:0] dout_r = 16'h0;
    assign dout = dout_r;
    always @(posedge clk) begin
        if (ack == req && req == (ack ^ 1'b0) && ~we)
            ;
        if (~we && ack == req) dout_r <= rd_word;
    end

    task clear_mem;
        integer i;
        begin
            for (i = 0; i < 32768; i = i + 1) mem[i] = 16'h0;
        end
    endtask

    task run_case(input integer m, input [1:0] want_status,
                  input [15:0] want_mask, input [511:0] what);
        begin
            mode = m;
            clear_mem;
            resetn = 0; ready = 0; ack = 0;
            repeat (4) @(posedge clk);
            resetn = 1;
            repeat (2) @(posedge clk);
            ready = 1;
            timeout = 0;
            while (status == 2'd0 && timeout < 200000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (status == 2'd0) begin
                $display("FAIL %0s: never finished (timeout)", what);
                errors = errors + 1;
            end else if (status !== want_status) begin
                $display("FAIL %0s: status %0d, want %0d", what, status, want_status);
                errors = errors + 1;
            end else if (want_mask !== 16'hxxxx && mask !== want_mask) begin
                $display("FAIL %0s: mask %04x, want %04x", what, mask, want_mask);
                errors = errors + 1;
            end else
                $display("ok   %0s: status %0d mask %04x", what, status, mask);
        end
    endtask

    initial begin
        run_case(0, 2'd1, 16'h0000, "good model passes");
        run_case(1, 2'd2, 16'hFFFF, "swapped lane is caught on all 16 bits");
        run_case(2, 2'd2, 16'h0808, "one stuck data bit is caught, both lanes");
        run_case(3, 2'd3, 16'h0000, "no acknowledge is reported");

        if (errors == 0) $display("PASS");
        else             $display("FAIL: %0d mismatches", errors);
        $finish;
    end

endmodule
