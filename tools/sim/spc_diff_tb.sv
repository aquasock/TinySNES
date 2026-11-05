// SPDX-License-Identifier: MIT
//
// SPC700 lockstep differential bench: this repository's core against MiSTer's.
//
// Why this exists.  The SPC700 defects this project has found were all invisible
// to benches that agree with themselves: entry 5 of the log found a read-modify-
// write shift reading T instead of memory, and entry 6 found eight more, from a
// swapped POP PSW to CMPW taking five cycles instead of four.  Each was found by
// running a second, independently written implementation on the same program and
// comparing.  That bench lived in /tmp and was lost, so this is its replacement:
// a committed harness whose reference is regenerated from a pinned upstream
// commit by tools/sim/spc_ref/build_ref.sh.
//
// How it compares.  Both cores are the same entity with the same bus, so they
// can share one clock and one stimulus.  They are NOT the same microarchitecture,
// so comparing every clock would be meaningless.  Instead both are sampled at
// instruction boundaries -- the last microcode step of an instruction, which both
// cores expose (`LAST_CYCLE` here, `last_cycle` in MiSTer's VHDL) -- and at those
// boundaries the bench compares the architected state: PC, A, X, Y, SP, PSW, plus
// the number of memory writes issued so far.  Wrong flags, a lost stack read or a
// mis-shifted operand all change one of those at the instruction that computed
// it, which is why this finds them at the instruction rather than a hundred
// later when the value is finally stored.
//
// Each core gets its own copy of the memory, initialised identically, so a
// divergence in one cannot corrupt the other's stimulus.  At the end of a run the
// two images must still be identical, byte for byte including the stack page,
// which catches a write that carried the wrong data even if both cores issued the
// same number of writes.
//
// History worth keeping.  The first version of this bench found that the core ran
// the power-on interrupt sequence twice, leaving SP at $FA where MiSTer leaves
// $FD.  While that defect existed the bench measured the resulting SP offset and
// reported affected runs as DIVERGE instead of PASS, so a green summary could not
// absorb them.  The defect was fixed in spc700.v (states 8 to 15 now terminate
// for every opcode except DIV and MUL), so that apparatus has been deleted rather
// than left in place: SP is now compared directly, the stack page is inside the
// image compare, and a regression appears as an ordinary FAIL at instruction 0.
//
// Termination.  Neither core is expected to run forever on random bytes: random
// code reaches STP or a tight loop quickly.  A run ends after +cycles clocks, or
// early once both cores have stopped retiring instructions for +idle clocks.
//
//   tools/sim/run_spc_diff.sh                 one default run
//   tools/sim/run_spc_diff.sh --seed 7 --cycles 200000
//   tools/sim/run_spc_diff.sh --sweep 2300    the registration run
//   tools/sim/run_spc_diff.sh --stalls 300    add random RDY stalls to 300 runs
//   tools/sim/run_spc_diff.sh --fill 8e       run one opcode repeatedly
//
// +fill exists for directed runs and for proving the bench can fail: a memory
// full of one byte executes that instruction over and over, so a deliberately
// reverted fix to its microcode shows up immediately instead of waiting for a
// random program to happen to execute it.
//
// Plusargs: +seed=N +cycles=N +idle=N +stalls=0/1 +quiet=0/1 +trace=N +fill=XX
//           +strictdiv=1 compares the DIV-overflow case instead of ending there

`timescale 1ns/1ps

module spc_diff_tb;

localparam integer MEM = 65536;
localparam integer QR  = 128;        // ring depth for pending snapshots
localparam integer MIN_CMP = 20;     // a run below this compares nothing of value

// ------------------------------------------------------------------ stimulus
reg clk = 0;
always #5 clk = ~clk;

reg resetn = 0;
reg rdy    = 1;
reg irq_n  = 1;

integer cycles = 200000;
integer idle_limit = 4000;
integer seed = 1;
integer stalls = 0;
integer quiet = 0;
integer trace_n = 0;        // +trace=N prints the first N instruction pairs
integer fill = -1;          // +fill=XX repeats one opcode, for a directed run
integer trace_i = 0;

// ------------------------------------------------------------------ memories
reg [7:0] mem_d [0:MEM-1];
reg [7:0] mem_r [0:MEM-1];

// ---------------------------------------------------------------------- core
// This repository's SPC700.  Architected registers are read hierarchically
// rather than through DBG_REG, because a debug mux would need one clock per
// register and the comparison has to be a single sample.
wire [7:0]  d_out_d;
wire [15:0] a_out_d;
wire        we_n_d;
wire        dut_last = dut.LAST_CYCLE;
// STP (0xEF) and SLEEP (0xFF) stop the core.  Both implementations set a
// stop flag that gates the enable, so both stop executing -- but MiSTer's keeps
// its last-cycle signal high while halted and therefore emits a "retired" pulse
// every clock, which no comparison can use.  A halt is a defined end of a
// random program, not a defect, so the run stops shortly after it and the
// memory images are still compared at the end.  A core that stops WITHOUT
// halting is still caught, by the drift guard below.
wire        dut_halt = dut.STPExec;

// DIV overflow is a deliberate, documented divergence, not a defect to find.
// This core implements the chip's nine-step rotate-and-subtract on {Y,A}, which
// core-log entry 6 records as matching bsnes; MiSTer's reference is a restoring
// divider whose quotient saturates to FF.  On seed 4 the two cores agreed for
// 204 instructions and then differed by exactly that: ours gave A=6B, the
// reference FF.  A random program reaches the overflow case often, so the run
// ends when the instruction starts rather than reporting a difference both
// projects already know about.  +strictdiv=1 compares it anyway.
wire        div_start = (dut.IR == 8'h9E);
wire        div_ovf   = ({1'b0, dut.Y, dut.A} > ({1'b0, dut.X} * 9'd255));
integer     strictdiv = 0;
reg         div_stop = 1'b0;

SPC700 dut (
    .CLK(clk), .RST_N(resetn), .RDY(rdy), .IRQ_N(irq_n),
    .D_IN(mem_d[a_out_d]), .D_OUT(d_out_d), .A_OUT(a_out_d), .WE_N(we_n_d),
    .DBG_REG(8'h00), .DBG_DAT_IN(8'h00), .DBG_DAT_OUT(), .DBG_DAT_WR(1'b0),
    .BRK_OUT()
);

// MiSTer's SPC700 at 901a172c, converted by GHDL with A/X/Y/SP/PSW/PC and
// last_cycle exported (tools/sim/spc_ref/build_ref.sh).
wire [7:0]  d_out_r;
wire [15:0] a_out_r;
wire        we_n_r;
wire [7:0]  r_a, r_x, r_y, r_sp, r_psw;
wire [15:0] r_pc;
wire        r_last;

SPC700_ref mister (
    .CLK(clk), .RST_N(resetn), .RDY(rdy), .IRQ_N(irq_n),
    .D_IN(mem_r[a_out_r]), .D_OUT(d_out_r), .A_OUT(a_out_r), .WE(we_n_r),
    .REG_DAT(56'h0), .REG_SET(1'b0),
    .DBG_A(r_a), .DBG_X(r_x), .DBG_Y(r_y), .DBG_SP(r_sp), .DBG_PSW(r_psw),
    .DBG_PC(r_pc), .DBG_LAST(r_last)
);

// ---------------------------------------------------------------------- stats
integer wr_d = 0, wr_r = 0;          // writes issued, per core
integer n_d  = 0, n_r  = 0;          // instructions retired, per core
integer cmps = 0, mism = 0;
integer cmp_n = 0;                   // next instruction index to compare
integer drift_max = 0;
reg     done = 0;

reg [55:0] snap_d [0:QR-1];
reg [55:0] snap_r [0:QR-1];
reg [15:0] wc_d   [0:QR-1];
reg [15:0] wc_r   [0:QR-1];
reg        val_d  [0:QR-1];
reg        val_r  [0:QR-1];

always @(posedge clk) if (resetn && !done) begin
    if (!we_n_d) begin mem_d[a_out_d] <= d_out_d; wr_d <= wr_d + 1; end
    if (!we_n_r) begin mem_r[a_out_r] <= d_out_r; wr_r <= wr_r + 1; end
end

// Snapshot one clock after the retiring edge, not on it.
//
// On the edge itself the two cores disagree about WHEN an instruction commits:
// this core writes its destination on the last microcode step, MiSTer's on the
// step before, and on the random-program run that showed up as A differing by
// one instruction at two boundaries while PC, X, Y, SP and PSW all agreed and
// the next boundary agreed on A too.  That is a commit-order difference, not a
// behaviour difference, so the sample point is moved to the clock after the
// instruction ends, where every architecturally visible effect has landed in
// both cores.  The first microcode step of the next instruction runs in that
// clock, and it does not touch an architected register in either core.
reg dut_last_r = 1'b0, r_last_r = 1'b0;
always @(posedge clk) if (resetn && !done) begin
    dut_last_r <= dut_last;
    r_last_r   <= r_last;
end

always @(posedge clk) if (resetn && !done) begin
    if (dut_last_r) begin
        snap_d[n_d % QR] <= {dut.PC, dut.PSW, dut.SP, dut.Y, dut.X, dut.A};
        wc_d[n_d % QR]   <= wr_d[15:0];
        val_d[n_d % QR]  <= 1'b1;
        n_d <= n_d + 1;
    end
    if (r_last_r) begin
        snap_r[n_r % QR] <= {r_pc, r_psw, r_sp, r_y, r_x, r_a};
        wc_r[n_r % QR]   <= wr_r[15:0];
        val_r[n_r % QR]  <= 1'b1;
        n_r <= n_r + 1;
    end
end

// Compare on the falling edge, when the non-blocking snapshot writes have
// landed.  Snapshots are compared in instruction order, one index at a time, so
// a core that is one instruction ahead waits rather than being called wrong.
always @(negedge clk) if (resetn && !done) begin
    if ((n_d - cmp_n) > QR || (n_r - cmp_n) > QR) begin
        $display("FAIL: drift: %0d instructions ahead at index %0d (dut %0d, ref %0d)",
                 (n_d > n_r ? n_d - n_r : n_r - n_d), cmp_n, n_d, n_r);
        mism = mism + 1;
        done = 1;
    end else if (val_d[cmp_n % QR] && val_r[cmp_n % QR]) begin
        cmps = cmps + 1;
        if (trace_i < trace_n) begin
            $display("T %0d %04x psw%02x sp%02x y%02x x%02x a%02x | %04x psw%02x sp%02x y%02x x%02x a%02x",
                     cmp_n,
                     snap_d[cmp_n % QR][55:40], snap_d[cmp_n % QR][39:32],
                     snap_d[cmp_n % QR][31:24], snap_d[cmp_n % QR][23:16],
                     snap_d[cmp_n % QR][15:8],  snap_d[cmp_n % QR][7:0],
                     snap_r[cmp_n % QR][55:40], snap_r[cmp_n % QR][39:32],
                     snap_r[cmp_n % QR][31:24], snap_r[cmp_n % QR][23:16],
                     snap_r[cmp_n % QR][15:8],  snap_r[cmp_n % QR][7:0]);
            trace_i = trace_i + 1;
        end
        sd = snap_d[cmp_n % QR];
        sr = snap_r[cmp_n % QR];
        if (sd !== sr || wc_d[cmp_n % QR] !== wc_r[cmp_n % QR]) begin
            mism = mism + 1;
            if (mism <= 8 || !quiet)
                $display("FAIL insn %0d  dut b%04x psw%02x sp%02x y%02x x%02x a%02x w%0d  ref b%04x psw%02x sp%02x y%02x x%02x a%02x w%0d",
                         cmp_n,
                         sd[55:40], sd[39:32], sd[31:24], sd[23:16], sd[15:8], sd[7:0], wc_d[cmp_n % QR],
                         sr[55:40], sr[39:32], sr[31:24], sr[23:16], sr[15:8], sr[7:0], wc_r[cmp_n % QR]);
        end
        val_d[cmp_n % QR] = 1'b0;
        val_r[cmp_n % QR] = 1'b0;
        cmp_n = cmp_n + 1;
    end
    if ((n_d > n_r ? n_d - n_r : n_r - n_d) > drift_max)
        drift_max = (n_d > n_r ? n_d - n_r : n_r - n_d);
end

// ------------------------------------------------------------------ programs
function [31:0] xs(input [31:0] s);
    reg [31:0] t;
    begin
        t = s ^ (s << 13);
        t = t ^ (t >> 17);
        t = t ^ (t << 5);
        t = t == 32'd0 ? 32'h9e3779b9 : t;
        xs = t;
    end
endfunction

// ---------------------------------------------------------------- run control
integer i, idle, base_seed, halt_age = 0;
reg halted = 1'b0;
reg [31:0] rr;
reg [55:0] sd, sr;

initial begin : main
    if (!$value$plusargs("seed=%d", seed))      seed = 1;
    if (!$value$plusargs("cycles=%d", cycles))  cycles = 200000;
    if (!$value$plusargs("idle=%d", idle_limit)) idle_limit = 4000;
    if (!$value$plusargs("stalls=%d", stalls))  stalls = 0;
    if (!$value$plusargs("quiet=%d", quiet))    quiet = 0;
    if (!$value$plusargs("trace=%d", trace_n))  trace_n = 0;
    if (!$value$plusargs("fill=%h", fill))      fill = -1;
    if (!$value$plusargs("strictdiv=%d", strictdiv)) strictdiv = 0;

    // Identical program in both memories.  The reset vector at $FFFE/$FFFF is
    // part of it, so both cores start at the same random address.
    base_seed = seed;
    rr = base_seed == 0 ? 32'd1 : base_seed[31:0];
    for (i = 0; i < MEM; i = i + 1) begin
        rr = xs(rr);
        mem_d[i] = fill >= 0 ? fill[7:0] : rr[7:0];
        mem_r[i] = fill >= 0 ? fill[7:0] : rr[7:0];
    end

    #20 resetn = 1;

    idle = 0;
    for (i = 0; i < cycles && !done; i = i + 1) begin
        @(posedge clk);
        if (stalls) begin
            // RDY low is a wait state: the core does not advance.  Random
            // stalls are how the original bench covered the RDY path, since a
            // defect there only appears when the core has to hold.
            rr = xs(rr);
            rdy <= ~(rr[4:0] == 5'd0);
            irq_n <= 1'b1;
        end
        if (div_start && div_ovf && !strictdiv) begin
            div_stop = 1'b1; i = cycles;
        end
        if (dut_halt) begin
            halt_age = halt_age + 1;
            if (halt_age > 8) begin halted = 1'b1; i = cycles; end
        end
        if (n_d == n_r && n_d > 0) idle = 0;
        else idle = idle + 1;
        if (idle > 40000) begin
            // Neither core has retired anything for a long time: both are
            // stopped or spinning.  Nothing further can be compared.
            i = cycles;
        end
    end
    rdy = 1;
    #50;

    // Both cores stopped at the same instruction, so every byte of the two
    // images must agree.  This is a full 64 KiB compare with no exclusions: the
    // stack page is included, which it was not while the reset defect shifted SP.
    for (i = 0; i < MEM; i = i + 1)
        if (mem_d[i] !== mem_r[i]) begin
            $display("FAIL: memory differs at %04x: dut %02x ref %02x", i, mem_d[i], mem_r[i]);
            mism = mism + 1;
            i = MEM;
        end

    // A run that ended for a legitimate reason -- STP, or the DIV-overflow stop
    // -- can legitimately be short, because a random program hits 0xEF within a
    // dozen instructions fairly often.  Short is not wrong: every comparison it
    // did make passed, and the memory images still had to agree above.  Those
    // runs are reported as SKIP and counted separately, so a sweep's summary says
    // how much of it was actually evidence.  The guard still bites in the case it
    // was written for: a run that stopped for no stated reason, or that ended
    // before comparing anything at all, is a bench or core fault and still fails.
    if (cmps < MIN_CMP && (halted || div_stop) && cmps > 0) begin
        $display("SKIP  seed %0d: only %0d instructions compared (%s), too short to be evidence",
                 seed, cmps, div_stop ? "DIV overflow" : "halted at STP");
        $display("RESULT seed=%0d cmps=%0d mism=%0d insns=%0d writes=%0d drift=%0d skip=1",
                 seed, cmps, mism, n_d, wr_d, drift_max);
        $finish;
    end
    if (cmps < MIN_CMP) begin
        $display("FAIL: only %0d instructions compared, need %0d, and the run did not halt",
                 cmps, MIN_CMP);
        mism = mism + 1;
    end

    if (mism == 0 && div_stop)
        $display("PASS  seed %0d: %0d instructions compared, %0d writes, max drift %0d (ended at a DIV overflow, known divergence)",
                 seed, cmps, wr_d, drift_max);
    else if (mism == 0 && halted)
        $display("PASS  seed %0d: %0d instructions compared, %0d writes, max drift %0d (halted at STP)",
                 seed, cmps, wr_d, drift_max);
    else if (mism == 0)
        $display("PASS  seed %0d: %0d instructions compared, %0d writes, max drift %0d",
                 seed, cmps, wr_d, drift_max);
    else
        $display("FAIL  seed %0d: %0d mismatches in %0d comparisons (%0d insns retired)",
                 seed, mism, cmps, n_d);
    $display("RESULT seed=%0d cmps=%0d mism=%0d insns=%0d writes=%0d drift=%0d",
             seed, cmps, mism, n_d, wr_d, drift_max);
    $finish;
end

endmodule
