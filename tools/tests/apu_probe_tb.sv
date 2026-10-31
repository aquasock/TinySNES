`timescale 1ns/1ps

// Bench for the TINYSNES_APU_PROBE sampler.  apu_sampler.v is extracted verbatim
// from fpga/snes/src/snestang_top.v.  The debug port is modelled the way the
// machine answers it: the value returned depends on BOTH DBG_SEL and DBG_REG, so
// a phase that selects the wrong chip -- the SPC700 core versus the SMP wrapper
// around it versus the 65816, which all use overlapping register numbers -- shows
// up as a mismatch instead of a plausible byte from the wrong device.
//
// Three things are checked, and each of them has already been wrong once in this
// project's probes:
//   1. the field order and byte order are what the comment claims;
//   2. fp_bus is a latched snapshot, not a live bus -- a live bus scans a
//      different value into every row of the raster and no stripe can be read;
//   3. a 16-bit PC whose high byte changes between the two reads is rejected
//      rather than assembled into a value neither instruction had.
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

    // Machine state the debug port reports.  Held in variables so the bench can
    // move a value between the probe's two reads of a 16-bit PC.
    reg [15:0] pc16  = 16'h8891;     // 65816 PC
    reg [15:0] spc16 = 16'hFFCF;     // SPC700 PC
    reg        tear  = 1'b0;         // when set, PC's high byte moves mid-read

    // A real tear is a byte boundary: the instruction finishes and PC moves to a
    // new high byte between the probe's reads.  Modelled by moving the high byte
    // the moment the probe has taken the low byte, and moving it again on every
    // revolution so the pair can never settle: the guard must then reject every
    // time rather than lock onto a value that was never read whole.  (A byte that
    // merely toggles every clock and returns to its old value across a two-clock
    // read pair is undetectable by any read scheme, and no CPU produces it.)
    always @(negedge mclk)
        if (tear && dbg_sel == 8'h01 && dbg_reg == 8'h06)
            pc16[15:8] <= pc16[15:8] + 8'd1;

    function [7:0] reg_data(input [7:0] sel, input [7:0] regno);
        begin
            if (sel == 8'h10)                       // SMP wrapper: the APU banks
                case (regno)
                    8'h00: reg_data = 8'h80;        // CPUI 0
                    8'h04: reg_data = 8'hAA;        // CPUO 0
                    8'h05: reg_data = 8'hBB;        // CPUO 1
                    default: reg_data = 8'hDD;
                endcase
            else if (sel == 8'h08)                  // SPC700 core
                case (regno)
                    8'h03: reg_data = spc16[7:0];
                    8'h04: reg_data = spc16[15:8];
                    default: reg_data = 8'hDD;
                endcase
            else if (sel == 8'h01)                  // 65816
                case (regno)
                    8'h00: reg_data = 8'h34;        // A low
                    8'h01: reg_data = 8'h12;        // A high
                    8'h06: reg_data = pc16[7:0];    // PC low
                    8'h07: reg_data = pc16[15:8];   // PC high
                    8'h08: reg_data = 8'h0C;        // P: M and X clear
                    default: reg_data = 8'hDD;
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

    // Every phase must land on a register the probe actually wants.  A phase
    // decode that asks for an unprobed register is fetched as $DD and would
    // otherwise sit in a stripe looking like a plausible machine value.  Sampled
    // on the falling edge: on the rising edge apu_ph changes in the same instant
    // and this would race the combinational select and read the previous phase.
    always @(negedge mclk) begin
        if (dbg_sel === 8'hxx || dbg_reg === 8'hxx) begin
            $display("FAIL phase select is undriven (sel=%02x reg=%02x)", dbg_sel, dbg_reg);
            errors = errors + 1;
        end else if (dbg_data === 8'hDD) begin
            $display("FAIL phase selects sel=%02x reg=%02x, which no probe field uses",
                     dbg_sel, dbg_reg);
            errors = errors + 1;
        end
    end

    // Advance to the next display latch.  The real cadence is 2^19 phase
    // revolutions, which no simulation wants to sit through, so the revolution
    // counter is wound to its terminal value and the machine is clocked the few
    // cycles it takes the probe to wrap and latch.  The latch logic is untouched.
    task latch_display;
        begin
            @(negedge mclk);
            dut.apu_wrap = 19'h7FFFF;
            repeat (40) @(posedge mclk);
            #1;
        end
    endtask

    integer changes;

    initial begin
        latch_display;
        latch_display;
        check(probe_bus[15:0],  16'hBBAA, "field 1: CPUO ports 1 and 0");
        check(probe_bus[31:16], 16'h1234, "field 2: 65816 A");
        check(probe_bus[47:32], 16'h8891, "field 3: 65816 PC");
        check(probe_bus[63:48], 16'hFFCF, "field 4: SPC700 PC");
        check(probe_bus[79:64], 16'h0C80, "field 5: 65816 P above CPUI 0");

        // P specifically: M (bit 5) and X (bit 4) must both be clear for the
        // $8889 REP #$30 to have taken effect, because the $8891 CMP's operand
        // width depends on them.
        if (probe_bus[77] !== 1'b0 || probe_bus[76] !== 1'b0) begin
            $display("FAIL field 5: M/X not clear, P = %02x", probe_bus[71:64]);
            errors = errors + 1;
        end else
            $display("ok   field 5: M and X clear in P");

        // 2. The display must stand still between latches, or the raster paints
        // a different value into every row and the frame cannot be decoded.
        changes = 0;
        fork
            begin
                repeat (2000) @(posedge mclk);
            end
            begin
                @(negedge mclk);
                while (1) begin
                    @(probe_bus);
                    changes = changes + 1;
                end
            end
        join_any
        disable fork;
        if (changes > 4) begin
            $display("FAIL display is live, not latched: %0d changes in 2000 mclk", changes);
            errors = errors + 1;
        end else
            $display("ok   display is latched: %0d changes in 2000 mclk", changes);

        // 3. Tear guard: the high byte moves on every revolution between the two
        // reads of it, so no pair is ever whole.  The accepted PC must not change
        // at all -- a guard that let any torn pair through would show a value
        // that neither instruction had.
        tear = 1'b1;
        latch_display;
        latch_display;
        check(probe_bus[47:32], 16'h8891, "field 3: torn PC rejected, last good kept");
        tear = 1'b0;
        pc16 = 16'h8891;

        // A sane PC must be accepted again once it stops tearing.
        pc16  = 16'h88A0;
        spc16 = 16'hFFD2;
        latch_display;
        latch_display;
        check(probe_bus[47:32], 16'h88A0, "field 3: clean PC accepted again");
        check(probe_bus[63:48], 16'hFFD2, "field 4: clean SPC PC accepted again");

        if (errors == 0) $display("PASS");
        else             $display("FAIL: %0d mismatches", errors);
        $finish;
    end
endmodule
