`timescale 1ns/1ps

// Bench for the TINYSNES_APU_PROBE sampler.  apu_sampler.v is extracted verbatim
// from fpga/snes/src/snestang_top.v.  The debug port is modelled the way the
// machine answers it: the value returned depends on BOTH DBG_SEL and DBG_REG, so
// a phase that selects the wrong chip — the SPC700 core versus the SMP wrapper
// around it, which share register numbers — shows up as a mismatch instead of a
// plausible byte from the wrong device.
module apu_dut (
    input  mclk,
    input  [7:0] dbg_dat_out,       // what the machine's debug port answers
    output [79:0] probe_bus_o,
    output [7:0]  dbg_sel_o,
    output [7:0]  dbg_reg_o
);
// Declared here because snestang_top keeps these nets outside the conditional
// block: the probe drives the core's existing debug port.
reg  [7:0] dbg_reg, dbg_sel;
reg        dbg_reg_wr;
wire [7:0] dbg_dat_in;
`include "apu_sampler.v"
    assign probe_bus_o = fp_bus;
    assign dbg_sel_o   = dbg_sel;
    assign dbg_reg_o   = dbg_reg;
endmodule

module tb;
    reg mclk = 0;
    wire [79:0] probe_bus;
    wire [7:0] dbg_sel, dbg_reg;
    integer errors = 0;
    integer i;

    // What the machine's debug port answers, per selected chip and register.
    // The port numbers are the ones that matter: port 0 must read 0xAA and port
    // 1 must read 0xBB for the handshake to be the 65816's fault rather than the
    // SPC700's.
    function [7:0] reg_data(input [7:0] sel, input [7:0] regno);
        begin
            if (sel == 8'h10)                       // SMP wrapper: APU ports
                case (regno)
                    8'h00: reg_data = 8'hAA;        // CPUI 0
                    8'h01: reg_data = 8'hBB;        // CPUI 1
                    8'h04: reg_data = 8'h11;        // CPUO 0
                    8'h05: reg_data = 8'h22;        // CPUO 1
                    default: reg_data = 8'hEE;
                endcase
            else if (sel == 8'h08)                  // SPC700 core
                case (regno)
                    8'h03: reg_data = 8'h34;        // PC low
                    8'h04: reg_data = 8'hFF;        // PC high
                    default: reg_data = 8'hEE;
                endcase
            else if (sel == 8'h01)                  // 65816
                case (regno)
                    8'h06: reg_data = 8'h91;        // PC low
                    8'h07: reg_data = 8'h88;        // PC high
                    default: reg_data = 8'hEE;
                endcase
            else reg_data = 8'hDD;
        end
    endfunction

    wire [7:0] dbg_data = reg_data(dbg_sel, dbg_reg);

    apu_dut dut(.mclk(mclk), .dbg_dat_out(dbg_data), .probe_bus_o(probe_bus),
                .dbg_sel_o(dbg_sel), .dbg_reg_o(dbg_reg));

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

    initial begin
        // Two full rotations so every phase has been captured and refreshed.
        repeat (24) @(posedge mclk);
        #1;
        check(probe_bus[15:0],  16'hBBAA, "field 1: CPUI ports 1 and 0");
        check(probe_bus[31:16], 16'h2211, "field 2: CPUO ports 1 and 0");
        check(probe_bus[47:32], 16'hFF34, "field 3: SPC700 PC from 0x04/0x03");
        check(probe_bus[63:48], 16'h8891, "field 4: 65816 PC from 0x07/0x06");

        if (dbg_sel !== 8'h08 && dbg_sel !== 8'h10 && dbg_sel !== 8'h01) begin
            $display("FAIL dbg_sel selects %02x, not a probed chip", dbg_sel);
            errors = errors + 1;
        end

        if (errors == 0) $display("PASS");
        else             $display("FAIL: %0d mismatches", errors);
        $finish;
    end
endmodule
