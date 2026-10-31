`timescale 1ns/1ps

// Bench for the TINYSNES_CPU_PROBE sampler.  cpu_sampler.v is extracted verbatim
// from fpga/snes/src/snestang_top.v, so this exercises the shipped text.  The
// debug port is modelled the way the CPU answers it: DBG_DAT_OUT is
// combinational in DBG_REG, and each register returns a constant that could not
// be confused with another, so a field captured from the wrong register shows up
// as a mismatch rather than as a plausible number.
module cpu_dut (
    input  mclk,
    input  ROM_CE_N,
    input  [7:0] dbg_dat_out,
    output [79:0] probe_bus_o,
    output [15:0] pc_now_o,
    output        pc_changed_o,
    output [7:0]  dbg_sel_o,
    output [7:0]  dbg_reg_o,
    output        dbg_reg_wr_o
);
// Declared here because snestang_top keeps them outside the conditional block:
// the probe drives the core's debug port, whose nets already exist upstream.
reg  [7:0] dbg_reg, dbg_sel;
reg        dbg_reg_wr;
wire [7:0] dbg_dat_in;
`include "cpu_sampler.v"
    assign probe_bus_o  = fp_bus;
    assign pc_now_o     = pc_now;
    assign pc_changed_o = pc_changed;
    assign dbg_sel_o    = dbg_sel;
    assign dbg_reg_o    = dbg_reg;
    assign dbg_reg_wr_o = dbg_reg_wr;
endmodule

module tb;
    reg mclk = 0;
    reg ROM_CE_N = 1;
    reg [7:0] dbg_reg_seen = 8'hxx;
    wire [79:0] probe_bus;
    wire [15:0] pc_now;
    wire pc_changed;
    wire [7:0] dbg_sel, dbg_reg;
    wire dbg_reg_wr;
    integer errors = 0;
    integer i;

    // Through a named wire rather than a function call in the port list, so the
    // port follows dbg_reg the way the CPU's combinational DBG_DAT_OUT does.
    wire [7:0] dbg_data_now = reg_data(dbg_reg);

    cpu_dut dut(.mclk(mclk), .ROM_CE_N(ROM_CE_N), .dbg_dat_out(dbg_data_now),
                .probe_bus_o(probe_bus), .pc_now_o(pc_now), .pc_changed_o(pc_changed),
                .dbg_sel_o(dbg_sel), .dbg_reg_o(dbg_reg), .dbg_reg_wr_o(dbg_reg_wr));

    // What the CPU's debug port answers, one distinct constant per register.
    function [7:0] reg_data(input [7:0] r);
        case (r)
            8'h06: reg_data = 8'h34;   // PC[7:0]
            8'h07: reg_data = 8'h12;   // PC[15:8]
            8'h09: reg_data = 8'hFF;   // SP[7:0]
            8'h0A: reg_data = 8'h01;   // SP[15:8]
            default: reg_data = 8'hEE;
        endcase
    endfunction

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
        // Let the debug-port rotation capture all four registers.
        repeat (8) @(posedge mclk);
        #1;
        // The bus carries samples, which the first tick has not taken yet, so
        // the assembled value is read from the live pixel here and from the bus
        // after the tick below.
        check(pc_now, 16'h1234, "live PC assembled from 0x07 then 0x06");
        check(probe_bus[79:64], 16'h01FF, "field 4: SP assembled from 0x0A/0x09");
        if (dbg_sel !== 8'b0000_0001) begin
            $display("FAIL dbg_sel is %02x, want 0000_0001", dbg_sel);
            errors = errors + 1;
        end
        if (dbg_reg_wr !== 1'b0) begin
            $display("FAIL dbg_reg_wr is not held low");
            errors = errors + 1;
        end
        if (dbg_reg != 8'h06 && dbg_reg != 8'h07 && dbg_reg != 8'h09 && dbg_reg != 8'h0A) begin
            $display("FAIL dbg_reg selects %02x, not a probe register", dbg_reg);
            errors = errors + 1;
        end

        // Five ROM accesses; ROMSEL must be released between two to count.
        for (i = 1; i <= 5; i = i + 1) begin
            ROM_CE_N = 0; repeat (2) @(posedge mclk); #1;
            ROM_CE_N = 1; repeat (2) @(posedge mclk); #1;
            if (probe_bus[15:0] !== i[15:0]) begin
                $display("FAIL counter after %0d accesses: %04x", i, probe_bus[15:0]);
                errors = errors + 1;
            end
        end
        check(probe_bus[31:16], 16'h0000, "field 1: counter high half is zero");
        $display("ok   counter counted %0d accesses", probe_bus[15:0]);

        // PC is sampled every 2^22 mclk; one sample takes that long to appear.
        repeat (22'h3F_FFFF + 4) @(posedge mclk);
        #1;
        check(probe_bus[47:32], 16'h1234, "field 2: most recent PC sample");
        check(probe_bus[63:48], 16'h0000, "field 3: older sample still at reset");
        if (pc_changed !== 1'b1) begin
            $display("FAIL pc_changed is %b after two different samples", pc_changed);
            errors = errors + 1;
        end

        if (errors == 0) $display("PASS");
        else             $display("FAIL: %0d mismatches", errors);
        $finish;
    end
endmodule
