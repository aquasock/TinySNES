`timescale 1ns/1ps

// Bench for the TINYSNES_FETCH_PROBE sampler.  sampler.v is extracted verbatim
// from fpga/snes/src/snestang_top.v, so this exercises the shipped text and not
// a retyped copy.  Stimulus is driven one nanosecond after each posedge so no
// assignment races a clock edge, and ROM_Q carries a different value every
// cycle, which makes each captured field's provenance provable.
module fp_dut (
    input  mclk,
    input  enable,
    input  ROM_CE_N,
    input  [15:0] ROM_Q,
    input  [23:0] ROM_ADDR,
    output [79:0] fp_bus_o,
    output        fetch_seen_o
);
`include "sampler.v"
    assign fp_bus_o     = fp_bus;
    assign fetch_seen_o = fetch_seen;
endmodule

module tb;
    reg mclk = 0;
    reg enable = 0;
    reg ROM_CE_N = 1;
    reg [15:0] ROM_Q = 16'h0000;
    reg [23:0] ROM_ADDR = 24'h000000;
    wire [79:0] fp_bus;
    wire fetch_seen;
    integer errors = 0;
    integer i;

    fp_dut dut(.mclk(mclk), .enable(enable), .ROM_CE_N(ROM_CE_N),
               .ROM_Q(ROM_Q), .ROM_ADDR(ROM_ADDR),
               .fp_bus_o(fp_bus), .fetch_seen_o(fetch_seen));

    always #10 mclk = ~mclk;

    task check(input [79:0] got, input [79:0] want, input [511:0] what);
        begin
            if (got !== want) begin
                $display("FAIL %0s: got %020x want %020x", what, got, want);
                errors = errors + 1;
            end else
                $display("ok   %0s: %020x", what, got);
        end
    endtask

    initial begin
        @(posedge mclk); #1;

        // Decoy: ROMSEL asserted while the machine is not enabled.  The probe
        // must ignore it, exactly as the machine does not fetch before enable.
        enable = 0; ROM_CE_N = 0; ROM_ADDR = 24'h123456; ROM_Q = 16'hDEAD;
        repeat (4) @(posedge mclk); #1;
        ROM_CE_N = 1;

        // First real access: the reset vector at ROM offset 0x7FFC.  ROM_Q is
        // stamped with a cycle counter so field N must read the value that was
        // on the bus on the Nth sample point and no other.
        repeat (2) @(posedge mclk); #1;
        enable = 1; ROM_CE_N = 0; ROM_ADDR = 24'h007FFC; ROM_Q = 16'h0001;
        for (i = 2; i <= 8; i = i + 1) begin
            @(posedge mclk); #1;
            ROM_Q = i[15:0];
            if (i == 7) ROM_CE_N = 1;           // six-mclk LoROM read window
        end

        repeat (2) @(posedge mclk); #1;
        check(fp_bus[15:0],  16'd1, "field 0 = ROM_Q at the first assertion");
        check(fp_bus[31:16], 16'd3, "field 1 = ROM_Q two mclk later");
        check(fp_bus[47:32], 16'd5, "field 2 = ROM_Q four mclk later");
        check(fp_bus[63:48], 16'h7FFC, "field 3 = ROM_ADDR[15:0]");
        check(fp_bus[79:64], 16'h007F, "field 4 = ROM_ADDR[23:8]");
        if (fetch_seen !== 1'b1) begin
            $display("FAIL fetch_seen never set");
            errors = errors + 1;
        end

        // A later access must not rewrite the captured window.
        ROM_CE_N = 0; ROM_ADDR = 24'h007FFD; ROM_Q = 16'hBEEF;
        repeat (6) @(posedge mclk); #1;
        ROM_CE_N = 1;
        repeat (2) @(posedge mclk); #1;
        check(fp_bus[15:0],  16'd1,    "field 0 unchanged by a second access");
        check(fp_bus[47:32], 16'd5,    "field 2 unchanged by a second access");
        check(fp_bus[63:48], 16'h7FFC, "address unchanged by a second access");

        if (errors == 0) $display("PASS");
        else             $display("FAIL: %0d mismatches", errors);
        $finish;
    end
endmodule
