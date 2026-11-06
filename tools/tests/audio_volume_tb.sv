// Bench for fpga/snes/src/audio_volume.v: the master volume.
//
// The module the board runs is instantiated directly, so what is checked here
// is the arithmetic in the tree rather than a restatement of it.  The checks
// are, in order of how much they would catch:
//
//   1. Unity (gain 256) is bit-exact for EVERY 16-bit sample, both channels.
//      This is the property that makes the feature safe to ship: a core that
//      never receives frame 0x1C, and a player who leaves the slider at 100
//      percent, must hear exactly what they heard before.  It is checked
//      against a pass-through rather than against a model of the formula, so a
//      wrong formula cannot agree with itself here.
//   2. Silence (gain 0) is exactly zero for every sample, including the most
//      negative one, where a signed multiply is easiest to get wrong.
//   3. Every intermediate gain is within half an LSB of the exact ratio, and
//      never exceeds full scale.  The bound is what catches a missing rounding
//      term or a shift by the wrong amount.
//   4. A gain above unity is clamped, so a host cannot ask for clipping.
//   5. out_ready arrives exactly one clock after audio_ready and the pair
//      beside it belongs to the same sample the pulse did.

`timescale 1ns/1ps

module audio_volume_tb;

localparam int CLK_NS = 10;

reg clk = 1'b0;
always #(CLK_NS/2) clk = ~clk;

reg resetn = 1'b0;
reg [15:0] audio_l = 16'd0, audio_r = 16'd0;
reg audio_ready = 1'b0;
reg [8:0] gain = 9'd256;
wire [15:0] out_l, out_r;
wire out_ready;

audio_volume dut (
    .clk(clk), .resetn(resetn),
    .audio_l(audio_l), .audio_r(audio_r), .audio_ready(audio_ready),
    .gain(gain),
    .out_l(out_l), .out_r(out_r), .out_ready(out_ready)
);

int errors = 0;
int checks = 0;

// The exact ratio, as a reference for the half-LSB bound.  Computed in 64 bits
// so the comparison itself cannot overflow.
function automatic longint exact(input signed [15:0] s, input [8:0] g);
    exact = (longint'(s) * longint'(g));
endfunction

// Drive one sample and return what the module produced for the left channel.
// audio_r carries a different pattern so a swapped or duplicated channel shows
// up instead of passing.
task automatic apply(input logic signed [15:0] s, input logic [8:0] g,
                     output logic signed [15:0] got_l, output logic signed [15:0] got_r,
                     output logic ready_seen);
    reg [15:0] r;
    begin
        r = s ^ 16'h5A5A;
        @(negedge clk);
        gain      = g;
        audio_l   = s;
        audio_r   = r;
        audio_ready = 1'b1;
        @(negedge clk);           // one posedge has passed: outputs are valid
        audio_ready = 1'b0;
        ready_seen = out_ready;
        got_l = out_l;
        got_r = out_r;
    end
endtask

task automatic expect_l(input string what, input logic signed [15:0] got,
                        input logic signed [15:0] want);
    begin
        checks++;
        if (got !== want) begin
            errors++;
            if (errors <= 20)
                $display("FAIL %0s: got %0d want %0d", what, got, want);
        end
    end
endtask

initial begin
    logic signed [15:0] gl, gr;
    logic seen;

    // ---- reset state -------------------------------------------------------
    repeat (4) @(posedge clk);
    checks++;
    if (out_ready !== 1'b0 || out_l !== 16'd0 || out_r !== 16'd0) begin
        errors++;
        $display("FAIL reset: out_ready %b out_l %0d out_r %0d",
                 out_ready, out_l, out_r);
    end
    @(negedge clk) resetn = 1'b1;
    repeat (2) @(posedge clk);

    // ---- 1. unity is a pass-through, over the whole 16-bit range -----------
    $display("=== unity (gain 256) over all 65536 samples ===");
    for (int v = 0; v < 65536; v++) begin
        apply($signed(v[15:0]), 9'd256, gl, gr, seen);
        checks++;
        if (gl !== $signed(v[15:0]) || gr !== $signed((v[15:0]) ^ 16'h5A5A)) begin
            errors++;
            if (errors <= 20)
                $display("FAIL unity at %0d: l %0d r %0d", $signed(v[15:0]), gl, gr);
        end
        if (!seen) begin
            errors++;
            if (errors <= 20) $display("FAIL unity at %0d: out_ready absent", $signed(v[15:0]));
        end
    end
    $display("    unity: %0d samples, %0d errors so far", 65536, errors);

    // ---- 2. silence is silence --------------------------------------------
    $display("=== gain 0 ===");
    for (int v = 0; v < 65536; v++) begin
        apply($signed(v[15:0]), 9'd0, gl, gr, seen);
        expect_l($sformatf("silence at %0d", $signed(v[15:0])), gl, 16'sd0);
        expect_l($sformatf("silence r at %0d", $signed(v[15:0])), gr, 16'sd0);
    end
    $display("    silence: %0d errors so far", errors);

    // ---- 3. intermediate gains: within half an LSB, never over full scale --
    // The gains are the ones the square-law slider actually produces for the
    // steps a player is most likely to sit on, plus the two edge values.
    begin
        int gains[] = '{256, 231, 205, 179, 154, 128, 102, 77, 51, 26, 5, 1};
        $display("=== intermediate gains, half-LSB bound ===");
        // A stride of 61 visits every residue class mod 256 over the full
        // range without spending 65536 clocks per gain.
        for (int gi = 0; gi < gains.size(); gi++) begin
            int g = gains[gi];
            int bad = 0;
            for (int k = 0; k < 1100; k++) begin
                int v = (k * 61) & 17'hFFFF;
                apply($signed(v[15:0]), g[8:0], gl, gr, seen);
                checks++;
                // |out*256 - s*g| must be at most 128, and out must fit.
                begin
                    longint want = exact($signed(v[15:0]), g[8:0]);
                    longint err  = longint'(gl) * 256 - want;
                    if (err > 128 || err < -128) begin
                        bad++;
                        if (bad <= 3)
                            $display("FAIL gain %0d at %0d: l %0d err %0d",
                                     g, $signed(v[15:0]), gl, err);
                    end
                end
            end
            if (bad > 0) errors += bad;
            else $display("    gain %3d: within half an LSB", g);
        end
    end

    // ---- 4. above unity is clamped ----------------------------------------
    $display("=== clamp above unity ===");
    apply(16'sd20000, 9'd511, gl, gr, seen);
    expect_l("clamp 511", gl, 16'sd20000);
    apply(-16'sd20000, 9'd300, gl, gr, seen);
    expect_l("clamp 300", gl, -16'sd20000);

    // ---- 5. the extremes at unity, named ----------------------------------
    $display("=== extremes ===");
    apply(-16'sd32768, 9'd256, gl, gr, seen);
    expect_l("min at unity", gl, -16'sd32768);
    apply(16'sd32767, 9'd256, gl, gr, seen);
    expect_l("max at unity", gl, 16'sd32767);
    apply(-16'sd32768, 9'd128, gl, gr, seen);
    expect_l("min at half", gl, -16'sd16384);
    apply(16'sd32767, 9'd128, gl, gr, seen);
    expect_l("max at half", gl, 16'sd16384);

    // ---- 6. out_ready is exactly one clock, and only on a sample -----------
    $display("=== ready pulse ===");
    @(negedge clk); audio_ready = 1'b1; gain = 9'd256; audio_l = 16'sd1234;
    @(negedge clk); audio_ready = 1'b0;
    checks++;
    if (out_ready !== 1'b1) begin errors++; $display("FAIL ready: absent after one clock"); end
    @(negedge clk);
    checks++;
    if (out_ready !== 1'b0) begin errors++; $display("FAIL ready: stuck high"); end
    // With no pulse, the outputs hold the last sample rather than decaying.
    checks++;
    if ($signed(out_l) !== 16'sd1234) begin
        errors++; $display("FAIL hold: %0d", $signed(out_l));
    end

    $display("");
    if (errors == 0)
        $display("PASS: %0d checks, no errors", checks);
    else
        $display("FAIL: %0d checks, %0d errors", checks, errors);
    $finish;
end

endmodule
