`timescale 1ns/1ps
// SPDX-License-Identifier: MIT
//
// Clock wrapper around gsu_tb for the headless --binary flow.
//
// gsu_tb takes its clock as a top-level input because the C++ harness in
// tools/sim/sim_main.cpp drives it directly.  A pure-SV run has nothing to drive
// it, so this wrapper supplies the 21.477 MHz master clock and leaves everything
// else to the bench.
module gsu_tb_top;
  reg clk = 1'b0;
  localparam real MCLK_HZ = 21477272.0;
  localparam real MCLK_NS = 1.0e9 / MCLK_HZ;
  always #(MCLK_NS / 2.0) clk = ~clk;

  gsu_tb dut (
    .clk(clk),
    .o_dotclk(), .o_hblankn(), .o_vblankn(), .o_x(), .o_y(), .o_rgb(),
    .o_pbr(), .o_pc_hi(), .o_pc_lo(), .o_go_cnt(), .o_sfr(),
    .o_state_seen(), .o_stop_seen()
  );
endmodule
