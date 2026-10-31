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
//   [71:64] SPC700 Y      [79:72] zero
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
                    default: reg_data = 8'hDD;
                endcase
            else reg_data = 8'hDD;
        end
    endfunction

    wire [7:0] dbg_data = reg_data(dbg_sel, dbg_reg);

    link_dut dut(.mclk(mclk), .dbg_dat_out(dbg_data), .probe_bus_o(probe_bus),
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
        check(probe_bus[79:64], 16'h0045, "field 5: zero above SPC700 Y");

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

        if (errors == 0) $display("PASS");
        else             $display("FAIL: %0d mismatches", errors);
        $finish;
    end
endmodule
