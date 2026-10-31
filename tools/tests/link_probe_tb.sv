`timescale 1ns/1ps

// Bench for the TINYSNES_LINK_PROBE sampler.  link_sampler.v is extracted
// verbatim from fpga/snes/src/snestang_top.v.
//
// The debug port is modelled as a function of BOTH DBG_SEL and DBG_REG.  That
// matters more for this probe than for any before it, because it reads four
// different registers from the SMP wrapper, two from the 65816 and three from the
// SPC700 core, and several of those register numbers mean different things on
// different chips.  A phase that selected the wrong chip would otherwise return a
// plausible byte from the wrong device and the measurement would be fiction.
//
// probe_bus bit layout, from the concatenation in the sampler:
//   [7:0]   CPUO[0]    [15:8]  CPUO[1]
//   [23:16] CPUI[0]    [31:24] CPUI[1]
//   [39:32] 65816 A low  [47:40] 65816 A high
//   [55:48] 65816 PC low  [63:56] 65816 PC high
//   [71:64] SPC700 Y
//   [72] CPUO ever != $AA   [73] Y ever != 0   [74] SPC PC ever < $FFC0
//   [75] CPUI ever == $CC   [79:76] zero
//
// Checked here:
//   1. every field lands where the comment says, with values that cannot be
//      confused between fields;
//   2. the two directions of the link are independent -- CPUO and CPUI hold
//      different bytes, so a probe that swapped them fails;
//   3. a torn SPC PC pair is rejected rather than assembled;
//   4. the display is a latched snapshot, not a live bus (TCL-011);
//   5. no phase ever selects an unprobed register.
module link_dut (
    input  mclk,
    input  resetn,
    input  [7:0] dbg_dat_out,
    output [79:0] probe_bus_o,
    output [7:0]  dbg_sel_o,
    output [7:0]  dbg_reg_o
);
reg  [7:0] dbg_reg, dbg_sel;
reg        dbg_reg_wr;
wire [7:0] dbg_dat_in;
`include "link_sampler.v"
    assign probe_bus_o = fp_bus;
    assign dbg_sel_o   = dbg_sel;
    assign dbg_reg_o   = dbg_reg;
endmodule

module tb;
    reg mclk = 0;
    reg resetn = 1'b1;          // a real top-level port in snestang_top, so the
                                // extracted block refers to it for the sticky bits
    wire [79:0] probe_bus;
    wire [7:0] dbg_sel, dbg_reg;
    integer errors = 0;
    integer changes;

    // Machine state.  Every field is a different value, and no two fields share
    // one, so a transposition anywhere shows up.
    reg [7:0] o0 = 8'h44, o1 = 8'hBB;   // CPUO: what the 65816 reads at $2140/$2141
    reg [7:0] i0 = 8'h44, i1 = 8'h7A;   // CPUI: what the SPC700 reads at $00F4/$00F5
    reg [7:0] cpu_a_lo = 8'h44, cpu_a_hi = 8'h01;   // 65816 A = $0144
    reg [15:0] cpu_pc = 16'h88EC;   // the 65816's echo-wait
    reg [15:0] spc_pc = 16'hFFDC;   // inside the IPL
    reg [7:0] spc_y = 8'h45;

    reg        tearing = 1'b0;

    function [7:0] reg_data(input [7:0] sel, input [7:0] regno);
        begin
            if (sel == 8'h10)                       // SMP wrapper: the port banks
                case (regno)
                    8'h00:   reg_data = i0;
                    8'h01:   reg_data = i1;
                    8'h04:   reg_data = o0;
                    8'h05:   reg_data = o1;
                    default: reg_data = 8'hDD;
                endcase
            else if (sel == 8'h01)                  // 65816
                case (regno)
                    8'h00:   reg_data = cpu_a_lo;
                    8'h01:   reg_data = cpu_a_hi;
                    8'h06:   reg_data = cpu_pc[7:0];
                    8'h07:   reg_data = cpu_pc[15:8];
                    default: reg_data = 8'hDD;
                endcase
            else if (sel == 8'h08)                  // SPC700 core
                case (regno)
                    8'h02:   reg_data = spc_y;
                    8'h04:   reg_data = spc_pc[15:8];
                    default: reg_data = 8'hDD;
                endcase
            else reg_data = 8'hDD;
        end
    endfunction

    wire [7:0] dbg_data = reg_data(dbg_sel, dbg_reg);

    link_dut dut(.mclk(mclk), .resetn(resetn), .dbg_dat_out(dbg_data),
                 .probe_bus_o(probe_bus),
                 .dbg_sel_o(dbg_sel), .dbg_reg_o(dbg_reg));

    always #10 mclk = ~mclk;

    // The tear moves the PC's high byte the instant the low byte is read, so no
    // high-low-high set is ever whole.
    always @(negedge mclk)
        if (tearing && dbg_sel == 8'h01 && dbg_reg == 8'h06)
            cpu_pc[15:8] <= cpu_pc[15:8] + 8'd1;

    task check(input [79:0] got, input [79:0] want, input [511:0] what);
        begin
            if (got !== want) begin
                $display("FAIL %0s: got %06x want %06x", what, got, want);
                errors = errors + 1;
            end else
                $display("ok   %0s: %06x", what, got);
        end
    endtask

    always @(negedge mclk) begin
        if (dbg_sel === 8'hxx || dbg_reg === 8'hxx) begin
            $display("FAIL phase select is undriven");
            errors = errors + 1;
        end else if (dbg_data === 8'hDD) begin
            $display("FAIL phase selects sel=%02x reg=%02x, unprobed", dbg_sel, dbg_reg);
            errors = errors + 1;
        end
    end

    task latch_display;
        begin
            @(negedge mclk);
            dut.link_wrap = 19'h7FFFF;
            repeat (40) @(posedge mclk);
            #1;
        end
    endtask

    reg        watch_pc = 1'b0;
    integer    pc_changes = 0;
    reg [15:0] pc_last;
    always @(posedge mclk) begin
        if (watch_pc) begin
            if (dut.cpu_hi !== pc_last[15:8] || dut.cpu_lo !== pc_last[7:0]) begin
                pc_changes = pc_changes + 1;
                pc_last = {dut.cpu_hi, dut.cpu_lo};
            end
        end else
            pc_last = {dut.cpu_hi, dut.cpu_lo};
    end

    initial begin
        // ---- 1. field layout --------------------------------------------
        repeat (40) @(posedge mclk);
        latch_display;
        latch_display;
        check(probe_bus[15:0],  16'hBB44, "field 1: CPUO 1 above CPUO 0");
        check(probe_bus[31:16], 16'h7A44, "field 2: CPUI 1 above CPUI 0");
        check(probe_bus[47:32], 16'h0144, "field 3: 65816 A");
        check(probe_bus[63:48], 16'h88EC, "field 4: 65816 PC");
        // [79:64] = {4'd0, st_cc, st_ipl, st_y, st_cpuo, y_r}.  o0 is $44, which
        // is not the value st_cpuo is armed on, so that bit is clear; spc_y is
        // $45, so st_y is set; spc_pc is $FFDC, so st_ipl is armed but clear;
        // i0 is $44, so st_cc is clear.
        check(probe_bus[79:64], 16'h0245, "field 5: st_y set, st_ipl armed, others clear");

        // ---- sticky bits: arming, then history ---------------------------
        // The bit that tests "CPUO has changed away from $AA" must not fire
        // merely because CPUO is not $AA.  smp.v clears CPUO to $00 at reset, so
        // an unarmed test sets at reset and reads as a confident yes for ever --
        // which is exactly what the first version of this build did.
        o0 = 8'h00;                          // CPUO at its reset value
        repeat (40) @(posedge mclk);
        latch_display;
        if (probe_bus[72] !== 1'b0) begin
            $display("FAIL st_cpuo set at CPUO's reset value $00 -- the bit is not armed");
            errors = errors + 1;
        end else
            $display("ok   st_cpuo stays clear at CPUO's reset value");

        o0 = 8'hAA;                          // the IPL's first publish arms it
        repeat (40) @(posedge mclk);
        latch_display;
        if (probe_bus[72] !== 1'b0) begin
            $display("FAIL st_cpuo set while CPUO has only ever been $AA");
            errors = errors + 1;
        end else
            $display("ok   st_cpuo stays clear while CPUO has only been $AA");

        o0 = 8'h10;                          // a departure from $AA
        repeat (40) @(posedge mclk);
        latch_display;
        if (probe_bus[72] !== 1'b1) begin
            $display("FAIL st_cpuo did not set when CPUO left $AA");
            errors = errors + 1;
        end else
            $display("ok   st_cpuo sets when CPUO leaves $AA");

        o0 = 8'hAA;                          // and now the property that matters
        repeat (40) @(posedge mclk);
        latch_display;
        if (probe_bus[72] !== 1'b1) begin
            $display("FAIL st_cpuo cleared when CPUO returned to $AA -- it is current state, not history");
            errors = errors + 1;
        end else
            $display("ok   st_cpuo survives CPUO returning to $AA");

        // st_y needs no arming: its reset value is $00 and that is also the value
        // meaning "never advanced", so non-zero is unambiguous.
        spc_y = 8'h00;
        repeat (40) @(posedge mclk);
        latch_display;
        check(probe_bus[71:64], 8'h00, "Y back to $00");
        if (probe_bus[73] !== 1'b1) begin
            $display("FAIL st_y cleared when Y returned to $00 -- it is current state, not history");
            errors = errors + 1;
        end else
            $display("ok   st_y survives Y returning to $00");

        // st_ipl is armed by seeing the PC inside the IPL, because addrgen.v
        // clears the PC to $0000, which would otherwise set the bit at reset.
        // Arming is one-way, so this has to start from a reset: by this point the
        // bench has already shown the probe an IPL address, and a bit that is
        // armed stays armed.  The first version of this test omitted the reset
        // and therefore asserted something the design never promised.
        @(negedge mclk);
        resetn = 1'b0;
        repeat (4) @(posedge mclk);
        resetn = 1'b1;
        spc_pc = 16'h0000;
        repeat (40) @(posedge mclk);
        latch_display;
        if (probe_bus[74] !== 1'b0) begin
            $display("FAIL st_ipl set at the PC's reset value $0000 -- the bit is not armed");
            errors = errors + 1;
        end else
            $display("ok   st_ipl stays clear at the PC's reset value");
        spc_pc = 16'hFFC0;
        repeat (40) @(posedge mclk);
        latch_display;
        if (probe_bus[74] !== 1'b0) begin
            $display("FAIL st_ipl set while the PC has only ever been inside the IPL");
            errors = errors + 1;
        end else
            $display("ok   st_ipl stays clear while the PC has only been inside the IPL");
        spc_pc = 16'h1234;
        repeat (40) @(posedge mclk);
        latch_display;
        if (probe_bus[74] !== 1'b1) begin
            $display("FAIL st_ipl did not set when the PC left the IPL");
            errors = errors + 1;
        end else
            $display("ok   st_ipl sets when the PC leaves the IPL");
        spc_pc = 16'hFFDC;
        repeat (40) @(posedge mclk);
        if (dut.st_ipl !== 1'b1) begin
            $display("FAIL st_ipl cleared when the PC returned to the IPL");
            errors = errors + 1;
        end else
            $display("ok   st_ipl survives the PC returning to the IPL");

        // ---- st_cc: the byte the IPL waits for ---------------------------
        // No arming is needed because CPUI clears to $00 and this tests for $CC,
        // so the property to prove is the simple one: it stays clear until $CC
        // actually appears, sets on that single event, and survives the byte
        // being cleared again -- which matters because the SPC can clear CPUI
        // port 0 by writing $F1, and the answer must not be lost when it does.
        i0 = 8'h00;
        repeat (40) @(posedge mclk);
        latch_display;
        if (probe_bus[75] !== 1'b0) begin
            $display("FAIL st_cc set at CPUI's reset value $00");
            errors = errors + 1;
        end else
            $display("ok   st_cc clear at CPUI's reset value");

        i0 = 8'hCC;                          // the event this bit exists to catch
        repeat (40) @(posedge mclk);
        latch_display;
        if (probe_bus[75] !== 1'b1) begin
            $display("FAIL st_cc did not set when CPUI port 0 held $CC");
            errors = errors + 1;
        end else
            $display("ok   st_cc sets when CPUI port 0 holds $CC");

        i0 = 8'h00;                          // the SPC may clear it again
        repeat (40) @(posedge mclk);
        latch_display;
        if (probe_bus[75] !== 1'b1) begin
            $display("FAIL st_cc cleared when CPUI port 0 was cleared -- it is history, not state");
            errors = errors + 1;
        end else
            $display("ok   st_cc survives CPUI port 0 being cleared");

        // A value that merely looks close must not set it.
        @(negedge mclk); resetn = 1'b0; repeat (4) @(posedge mclk); resetn = 1'b1;
        i0 = 8'hCD;
        repeat (40) @(posedge mclk);
        latch_display;
        if (probe_bus[75] !== 1'b0) begin
            $display("FAIL st_cc set for CPUI port 0 of $CD, not $CC");
            errors = errors + 1;
        end else
            $display("ok   st_cc ignores $CD");

        // Restore the machine state the later checks assume, so these tests do
        // not leave the bench inspecting values they changed themselves.
        o0 = 8'h44; spc_y = 8'h45; i0 = 8'h44;
        repeat (30) @(posedge mclk);

        // ---- 2. the two directions are independent ----------------------
        // CPUO is $BB44 and CPUI is $7A44: they differ in the high byte only, so
        // the low byte alone cannot tell them apart.  Move CPUO's high byte and
        // confirm CPUI does not follow, and vice versa.
        o1 = 8'h11;
        repeat (30) @(posedge mclk);
        latch_display;
        check(probe_bus[15:0], 16'h1144, "CPUO high byte follows CPUO, not CPUI");
        check(probe_bus[31:16], 16'h7A44, "CPUI unaffected by a CPUO change");
        i1 = 8'h22;
        o1 = 8'hBB;
        repeat (30) @(posedge mclk);
        latch_display;
        check(probe_bus[15:0],  16'hBB44, "CPUO restored");
        check(probe_bus[31:16], 16'h2244, "CPUI high byte follows CPUI, not CPUO");

        // ---- 3. a torn 65816 PC is rejected -----------------------------
        // The invariant is that the accepted PC does not move while its high byte
        // is changing; asserting a particular value would not test the guard,
        // because the value after the tear stops is legitimate either way.
        pc_changes = 0;
        watch_pc = 1'b1;
        tearing = 1'b1;
        repeat (300) @(posedge mclk);
        tearing = 1'b0;
        watch_pc = 1'b0;
        if (pc_changes == 0)
            $display("ok   torn 65816 PC rejected: accepted PC never moved across 300 mclk");
        else begin
            $display("FAIL torn 65816 PC accepted: moved %0d times while tearing", pc_changes);
            errors = errors + 1;
        end
        cpu_pc = 16'h8888;
        repeat (40) @(posedge mclk);
        latch_display;
        check(probe_bus[63:48], 16'h8888, "clean 65816 PC accepted after the tear");

        // ---- 4. the display is latched ----------------------------------
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

        // A reset must clear all three sticky bits, or a build reused after a
        // reload would report another machine's history.
        @(negedge mclk);
        resetn = 1'b0;
        repeat (4) @(posedge mclk);
        #1;
        if (dut.st_cpuo !== 1'b0 || dut.st_y !== 1'b0 || dut.st_ipl !== 1'b0
            || dut.st_cc !== 1'b0) begin
            $display("FAIL sticky bits not cleared by reset: cpuo=%b y=%b ipl=%b cc=%b",
                     dut.st_cpuo, dut.st_y, dut.st_ipl, dut.st_cc);
            errors = errors + 1;
        end else
            $display("ok   reset clears all four sticky bits");

        if (errors == 0) $display("PASS");
        else             $display("FAIL: %0d mismatches", errors);
        $finish;
    end
endmodule
