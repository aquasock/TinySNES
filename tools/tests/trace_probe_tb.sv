`timescale 1ns/1ps

// Bench for the TINYSNES_TRACE_PROBE sampler.  trace_sampler.v is extracted
// verbatim from fpga/snes/src/snestang_top.v, so this exercises the shipped text.
// Each access carries an address that cannot be confused with any other, so a
// ring that shifts the wrong way, drops an entry or admits an SRAM access shows
// up as a mismatch rather than as a plausible trace.
module trace_dut (
    input  mclk,
    input  enable,
    input  ROM_CE_N,
    input  BSRAM_CE_N,
    input  [23:0] ROM_ADDR,
    output [79:0] probe_bus_o,
    output        rom_recent_o
);
`include "trace_sampler.v"
    assign probe_bus_o  = fp_bus;
    assign rom_recent_o = rom_recent;
endmodule

module tb;
    reg mclk = 0;
    reg enable = 0;
    reg ROM_CE_N = 1;
    reg BSRAM_CE_N = 1;
    reg [23:0] ROM_ADDR = 24'h000000;
    wire [79:0] probe_bus;
    wire rom_recent;
    integer errors = 0;
    integer i;

    trace_dut dut(.mclk(mclk), .enable(enable), .ROM_CE_N(ROM_CE_N),
                  .BSRAM_CE_N(BSRAM_CE_N), .ROM_ADDR(ROM_ADDR),
                  .probe_bus_o(probe_bus), .rom_recent_o(rom_recent));

    always #10 mclk = ~mclk;

    task check(input [79:0] got, input [79:0] want, input [511:0] what);
        begin
            if (got !== want) begin
                $display("FAIL %0s: got %06x want %06x", what, got, want);
                errors = errors + 1;
            end else
                $display("ok   %0s: %06x", what, got);
        end
    endtask

    // One ROM access, held for six clocks like a real slow access, released
    // between accesses.  The ring must shift exactly once per access: a level
    // detector instead of an edge detector shifts it every clock and the trace
    // becomes noise, which is what happened on hardware.
    task rom_access(input [23:0] addr);
        begin
            @(posedge mclk); #1;
            ROM_ADDR = addr; ROM_CE_N = 0;
            repeat (6) @(posedge mclk); #1;
            ROM_CE_N = 1;
        end
    endtask

    initial begin
        @(posedge mclk); #1;
        enable = 1;                 // the sampler is gated the way main is

        // Five ROM accesses; the first must fall off a four-deep ring.
        rom_access(24'h000A01);
        rom_access(24'h000B02);
        rom_access(24'h000C03);
        rom_access(24'h000D04);
        rom_access(24'h000E05);
        #1;
        check(probe_bus[15:0],  16'h0E05, "stripe 1: newest ROM address");
        check(probe_bus[31:16], 16'h0D04, "stripe 2: one access earlier");
        check(probe_bus[47:32], 16'h0C03, "stripe 3: two accesses earlier");
        check(probe_bus[63:48], 16'h0B02, "stripe 4: three accesses earlier");
        check(probe_bus[79:64], 16'h000E, "stripe 5: ROM_ADDR[23:8] of newest");
        if (rom_recent !== 1'b1) begin
            $display("FAIL rom_recent not set after accesses");
            errors = errors + 1;
        end

        // An SRAM access asserts ROMSEL too, but it is not a code fetch and must
        // not enter the ring.
        @(posedge mclk); #1;
        ROM_ADDR = 24'h007777; ROM_CE_N = 0; BSRAM_CE_N = 0;
        repeat (2) @(posedge mclk); #1;
        ROM_CE_N = 1; BSRAM_CE_N = 1;
        #1;
        check(probe_bus[15:0], 16'h0E05, "SRAM access left the ring alone");

        // Nothing more happens: the ring must stay where it is.
        repeat (20) @(posedge mclk); #1;
        check(probe_bus[15:0],  16'h0E05, "idle bus: newest unchanged");
        check(probe_bus[63:48], 16'h0B02, "idle bus: oldest unchanged");

        // One more access and the ring shifts by exactly one.
        rom_access(24'h001234);
        #1;
        check(probe_bus[15:0],  16'h1234, "after one more: newest");
        check(probe_bus[31:16], 16'h0E05, "after one more: previous");
        check(probe_bus[79:64], 16'h0012, "after one more: high half");

        if (errors == 0) $display("PASS");
        else             $display("FAIL: %0d mismatches", errors);
        $finish;
    end
endmodule
