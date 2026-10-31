`timescale 1ns/1ps

// Bench for the TINYSNES_IPL_PROBE sampler.  ipl_sampler.v is extracted verbatim
// from fpga/snes/src/snestang_top.v.
//
// The debug port is modelled as a function of BOTH DBG_SEL and DBG_REG, so a
// phase that selects the wrong chip shows up as a mismatch rather than as a
// plausible byte from the wrong device -- the SPC700 core, the SMP wrapper and
// the 65816 all use overlapping register numbers.
//
// probe_bus bit layout, from the concatenation in the sampler:
//   [15:0]  exit_pc   [23:16] A (live)  [31:24] Y (live) [47:32] cur_pc
//   [55:48] CPUI[2]   [63:56] CPUI[3]   [71:64] CPUI[0]  [79:72] CPUI[1]
//
// What is checked, in the order the machine would break it:
//   1. the field order and byte order match that layout;
//   2. the exit is latched on the FIRST sample outside the IPL, and a later
//      wander does not overwrite it -- the point is the address it jumped to,
//      not where it ended up;
//   3. nothing is latched before the IPL range has been seen, so a reset PC of
//      zero cannot be mistaken for a jump;
//   4. a PC pair whose high byte moves between the two reads is rejected, which
//      is observable as cur_pc standing still rather than jumping to a value the
//      SPC was never at;
//   5. the display is a latched snapshot, not a live bus (core-reference
//      TCL-011: a live bus is painted as a different value in every raster row).
module ipl_dut (
    input  mclk,
    input  [7:0] dbg_dat_out,
    output [79:0] probe_bus_o,
    output [7:0]  dbg_sel_o,
    output [7:0]  dbg_reg_o
);
reg  [7:0] dbg_reg, dbg_sel;
reg        dbg_reg_wr;
wire [7:0] dbg_dat_in;
`include "ipl_sampler.v"
    assign probe_bus_o = fp_bus;
    assign dbg_sel_o   = dbg_sel;
    assign dbg_reg_o   = dbg_reg;
endmodule

module tb;
    reg mclk = 0;
    wire [79:0] probe_bus;
    wire [7:0] dbg_sel, dbg_reg;
    integer errors = 0;
    integer changes;

    // Machine state the debug port reports.
    reg [15:0] spc_pc = 16'hFFC0;   // starts at the IPL's reset vector
    reg  [7:0] spc_a  = 8'h00;
    reg  [7:0] spc_x  = 8'h00;
    reg  [7:0] spc_y  = 8'h00;
    reg  [7:0] cpui0  = 8'h00, cpui1 = 8'h00, cpui2 = 8'h00, cpui3 = 8'h00;

    function [7:0] reg_data(input [7:0] sel, input [7:0] regno);
        begin
            if (sel == 8'h08)                       // SPC700 core
                case (regno)
                    8'h00:   reg_data = spc_a;
                    8'h01:   reg_data = spc_x;
                    8'h02:   reg_data = spc_y;
                    8'h03:   reg_data = spc_pc[7:0];
                    8'h04:   reg_data = spc_pc[15:8];
                    default: reg_data = 8'hDD;
                endcase
            else if (sel == 8'h10)                  // SMP wrapper: the APU banks
                case (regno)
                    8'h00:   reg_data = cpui0;
                    8'h01:   reg_data = cpui1;
                    8'h02:   reg_data = cpui2;
                    8'h03:   reg_data = cpui3;
                    default: reg_data = 8'hDD;
                endcase
            else reg_data = 8'hDD;
        end
    endfunction

    wire [7:0] dbg_data = reg_data(dbg_sel, dbg_reg);

    ipl_dut dut(.mclk(mclk), .dbg_dat_out(dbg_data), .probe_bus_o(probe_bus),
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

    // Every phase must land on a register the probe wants; $DD means the decode
    // selected something unprobed.  Sampled on the falling edge so it does not
    // race the combinational select against ipl_ph changing on the rising edge.
    always @(negedge mclk) begin
        if (dbg_sel === 8'hxx || dbg_reg === 8'hxx) begin
            $display("FAIL phase select is undriven");
            errors = errors + 1;
        end else if (dbg_data === 8'hDD) begin
            $display("FAIL phase selects sel=%02x reg=%02x, unprobed", dbg_sel, dbg_reg);
            errors = errors + 1;
        end
    end

    // Wind the display refresh counter to its terminal value and run the few
    // cycles it takes the probe to wrap its phases and latch.  The latch logic
    // itself is untouched.
    task latch_display;
        begin
            @(negedge mclk);
            dut.ipl_wrap = 19'h7FFFF;
            repeat (40) @(posedge mclk);
            #1;
        end
    endtask

    reg [15:0] pc_before_tear;
    reg        tearing;
    reg        tear_watch = 1'b0;
    integer    tear_changes = 0;
    reg [15:0] tear_last;

    // Count changes of the sampler's own cur_pc while the tear window is open.
    always @(posedge mclk) begin
        if (tear_watch) begin
            if (dut.cur_pc !== tear_last) begin
                tear_changes = tear_changes + 1;
                tear_last    = dut.cur_pc;
            end
        end else
            tear_last = dut.cur_pc;
    end

    // Move the PC's high byte the instant the probe reads the low byte, so the
    // two high reads straddle a change and no pair is ever whole.
    always @(negedge mclk)
        if (tearing && dbg_sel == 8'h08 && dbg_reg == 8'h03)
            spc_pc[15:8] <= spc_pc[15:8] + 8'd1;

    initial begin
        tearing = 1'b0;

        // ---- 3. nothing latched before the IPL has been seen -------------
        // Hold PC at zero: the probe must not call that a jump.
        spc_pc = 16'h0000;
        repeat (80) @(posedge mclk);
        latch_display;
        check(probe_bus[15:0], 16'h0000, "no exit latched while PC has only ever been zero");

        // ---- 1. run the IPL, then jump ----------------------------------
        // CPUI 3:2 is deliberately a different high byte from the jump target,
        // so a transposition between field 1 and field 4 cannot pass.
        spc_pc = 16'hFFC0;  spc_a = 8'h00; spc_x = 8'hEF;
        cpui0 = 8'hAA; cpui1 = 8'h02; cpui2 = 8'h55; cpui3 = 8'h0B;
        repeat (40) @(posedge mclk);
        spc_pc = 16'hFFC9; repeat (20) @(posedge mclk);
        spc_pc = 16'hFFCF; repeat (20) @(posedge mclk);
        // The jump.  Y and A are deliberately different from each other and from
        // every other field, so a transposed pair cannot pass.
        spc_pc = 16'h0A55; spc_a = 8'h34; spc_x = 8'h02; spc_y = 8'h5C;
        repeat (60) @(posedge mclk);
        latch_display;

        check(probe_bus[15:0],  16'h0A55, "field 1: first PC outside the IPL is the jump target");
        check(probe_bus[31:16], 16'h5C34, "field 2: live Y above live A");
        check(probe_bus[47:32], 16'h0A55, "field 3: current PC");
        check(probe_bus[63:48], 16'h0B55, "field 4: CPUI 3 above CPUI 2");
        check(probe_bus[79:64], 16'h02AA, "field 5: CPUI 1 above CPUI 0");

        // ---- 2. a later wander must not overwrite the exit --------------
        spc_pc = 16'h0A60; repeat (30) @(posedge mclk);
        spc_pc = 16'h0A72; repeat (30) @(posedge mclk);
        spc_pc = 16'hFFFF; repeat (30) @(posedge mclk);   // back in the IPL
        spc_pc = 16'h1234; repeat (30) @(posedge mclk);
        latch_display;
        check(probe_bus[15:0],  16'h0A55, "exit latched once and not overwritten");
        check(probe_bus[47:32], 16'h1234, "current PC does keep moving");

        // Y and A must be live, not frozen at the exit moment: move both and
        // confirm the stripe follows, because the whole point of this cycle is
        // reading the SPC's index against CPUI port 0 as the machine runs.
        spc_y = 8'h7E; spc_a = 8'h11; cpui0 = 8'h9F;
        repeat (30) @(posedge mclk);
        latch_display;
        check(probe_bus[31:16], 16'h7E11, "field 2 follows live Y and A");
        check(probe_bus[79:72], 8'h02, "field 5 high byte is CPUI 1, unchanged at $02");
        check(probe_bus[71:64], 8'h9F, "field 5 low byte follows live CPUI 0");

        // ---- 4. a tearing PC pair is rejected ---------------------------
        // The invariant: while the high byte moves between the probe's two reads
        // of it, cur_pc must not change at all.  Counting its changes is the
        // direct test; asserting a particular value is not, because the value
        // after the tear stops is a legitimate PC and would pass either way --
        // the first version of this test made exactly that mistake.
        repeat (30) @(posedge mclk);
        $display("     (cur_pc before the tear: %04x)", dut.cur_pc);
        spc_pc  = 16'h4000;
        tear_changes = 0;
        tear_watch = 1'b1;
        tearing = 1'b1;
        repeat (300) @(posedge mclk);
        tearing = 1'b0;
        tear_watch = 1'b0;
        if (tear_changes == 0)
            $display("ok   tear rejected: cur_pc never changed across 300 mclk of tearing");
        else begin
            $display("FAIL tear guard: cur_pc changed %0d times while the high byte was moving",
                     tear_changes);
            errors = errors + 1;
        end

        // A clean pair must still be accepted afterwards, or the guard would
        // simply wedge the sampler.
        spc_pc = 16'h4321;
        repeat (40) @(posedge mclk);
        if (dut.cur_pc == 16'h4321)
            $display("ok   clean pair accepted after the tear: %04x", dut.cur_pc);
        else begin
            $display("FAIL clean pair rejected after the tear: cur_pc %04x, want 4321", dut.cur_pc);
            errors = errors + 1;
        end
        latch_display;
        check(probe_bus[15:0], 16'h0A55, "exit still not overwritten after the tear");

        // ---- 5. the display is latched ----------------------------------
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

        if (errors == 0) $display("PASS");
        else             $display("FAIL: %0d mismatches", errors);
        $finish;
    end
endmodule
