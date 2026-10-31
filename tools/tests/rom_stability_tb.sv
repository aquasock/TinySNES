`timescale 1ns/1ps

// Bench for fpga/snes/src/rom_stability.v, compiled from the shipping source.
//
// The model behind the port acknowledges a request and returns a word after a
// few clocks, which is the controller's shape.  Three memory behaviours are run
// against the same DUT:
//
//   good     every read of an address returns the same word    -> PASS, mask 0
//   flaky    one read in every N returns a different word      -> FAIL, count > 0
//   noack    the port never acknowledges                       -> status 3
//
// The flaky model is the one that matters: it is the refresh-steals-the-slot
// fault this build exists to detect, and a test that could not see it would be
// worse than no test.  Its injection is keyed to the read index so it is
// deterministic and lands inside the run rather than at the edges.

module rom_stability_tb;

    // 0 good, 1 flaky, 2 no acknowledge
    integer mode;

    reg         clk = 0;
    reg         resetn;
    reg         loaded;
    wire [21:0] addr;
    wire        req;
    reg         ack = 0;
    wire [15:0] dout;
    wire [15:0] mism;
    wire  [1:0] status;
    wire        done;

    reg  [15:0] dout_r = 16'h0;
    assign dout = dout_r;

    integer reads = 0;
    integer errors = 0;
    integer timeout;

    always #5 clk = ~clk;

    // Each address has a fixed true value, so a correct port is stable by
    // construction and any disagreement is injected rather than data-dependent.
    function [15:0] true_word(input [21:0] a);
        begin
            true_word = a[15:0] ^ 16'hA5C3;
        end
    endfunction

    rom_stability #(.ITERATIONS(16'd4)) dut (
        .clk(clk), .resetn(resetn), .loaded(loaded),
        .dout(dout), .addr(addr), .req(req), .ack(ack),
        .mism(mism), .status(status), .done(done)
    );

    // The controller: acknowledge a pending request after a clock or two, and
    // return the word after the ack.
    reg [3:0] lat;
    always @(posedge clk) begin
        if (~resetn) begin
            ack    <= 1'b0;
            lat    <= 4'd0;
            dout_r <= 16'h0;
        end else begin
            if (ack != req) begin
                if (mode != 2) ack <= req;
                lat <= 4'd6;
            end else if (lat != 4'd0) begin
                lat <= lat - 4'd1;
                if (lat == 4'd1) begin
                    reads = reads + 1;
                    // The flaky model corrupts every seventeenth read, which is
                    // far rarer than the good model's agreement and far more
                    // often than never -- the shape of a slot being stolen.
                    if (mode == 1 && (reads % 17) == 0)
                        dout_r <= true_word(addr) ^ 16'h0100;
                    else
                        dout_r <= true_word(addr);
                end
            end
        end
    end

    task run_case(input integer m, input [1:0] want_status,
                  input [511:0] what);
        begin
            mode = m;
            resetn = 0; loaded = 0; ack = 0; reads = 0;
            repeat (4) @(posedge clk);
            resetn = 1;
            repeat (4) @(posedge clk);
            loaded = 1;
            timeout = 0;
            while (done !== 1'b1 && timeout < 400000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (done !== 1'b1) begin
                $display("FAIL %0s: never finished (timeout after %0d clocks)", what, timeout);
                errors = errors + 1;
            end else if (status !== want_status) begin
                $display("FAIL %0s: status %0d, want %0d", what, status, want_status);
                errors = errors + 1;
            end else
                $display("ok   %0s: status %0d mism %04x after %0d reads", what, status, mism, reads);
        end
    endtask

    initial begin
        run_case(0, 2'd1, "good model passes");
        if (mism !== 16'd0) begin
            $display("FAIL good model reported %0d mismatches", mism);
            errors = errors + 1;
        end else
            $display("ok   good model reported zero mismatches");

        // 4 iterations x 8 addresses x 2 reads = 64 reads; every 17th is
        // corrupted, so 64/17 gives 3 corrupt reads and therefore 3 pairs that
        // disagree -- the count must be non-zero, not merely present.
        run_case(1, 2'd2, "flaky model is caught");
        if (mism == 16'd0) begin
            $display("FAIL flaky model was not counted");
            errors = errors + 1;
        end else
            $display("ok   flaky model counted %0d mismatching pairs", mism);

        run_case(2, 2'd3, "no acknowledge is reported");

        if (errors == 0) $display("PASS");
        else             $display("FAIL: %0d mismatches", errors);
        $finish;
    end

endmodule
