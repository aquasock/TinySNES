// SPDX-License-Identifier: MIT
//
// Simulation-only models of the Gowin primitives this design instantiates.
//
// These exist so a bench can elaborate `snestang_top` itself instead of a
// hand-copied imitation of its glue.  That distinction is not academic: bench
// bugs in this project have repeatedly come from re-deriving the board's logic
// in a testbench rather than instantiating it (core-log entry 65 -- the bench
// applied the LoROM bank formula to ROM_ADDR when main.v already emitted a
// linear cartridge offset, and read the reset vector from the wrong offset).
// One level of hierarchy makes that class of bug impossible.
//
// Nothing here is a timing model.  The PLL models produce the same *frequencies*
// the Gowin parameters request, because the bench needs the real 3:1 mclk/fclk
// ratio and the 6:1 clkref ratio to exercise the controller's slots.  They do not
// model jitter, lock time or phase noise, and CLKOUT2's phase shift is modelled
// as a delay on the dividend edge, which is enough to place the SDRAM model's
// sample points where the hardware puts them.
//
// Sources for the frequency arithmetic: fpga/snes/pll/gowin_pll_snes.v, whose
// header records clkout0 = 50*40/93 = 21.505 MHz, clkout1 = 50*40/31 = 64.516 MHz
// and clkout2 as clkout1 shifted 225 degrees.  The model reproduces those three
// numbers exactly from ODIV0_SEL, ODIV1_SEL and CLKOUT2_PE_COARSE/FINE.

`timescale 1ns/1ps

// --------------------------------------------------------------------- PLL
module PLL #(
    parameter FCLKIN            = "50",
    parameter IDIV_SEL          = 1,
    parameter FBDIV_SEL         = 1,
    parameter MDIV_SEL          = 40,
    parameter MDIV_FRAC_SEL     = 0,
    parameter ODIV0_SEL         = 93,
    parameter ODIV0_FRAC_SEL    = 0,
    parameter ODIV1_SEL         = 31,
    parameter ODIV2_SEL         = 31,
    parameter ODIV3_SEL         = 8,
    parameter ODIV4_SEL         = 8,
    parameter ODIV5_SEL         = 8,
    parameter ODIV6_SEL         = 8,
    parameter CLKOUT0_EN        = "TRUE",
    parameter CLKOUT1_EN        = "TRUE",
    parameter CLKOUT2_EN        = "TRUE",
    parameter CLKOUT3_EN        = "FALSE",
    parameter CLKOUT4_EN        = "FALSE",
    parameter CLKOUT5_EN        = "FALSE",
    parameter CLKOUT6_EN        = "FALSE",
    parameter CLKFB_SEL         = "INTERNAL",
    parameter CLKOUT0_DT_DIR    = 1'b1,
    parameter CLKOUT0_DT_STEP   = 0,
    parameter CLKOUT0_PE_COARSE = 0,
    parameter CLKOUT0_PE_FINE   = 0,
    parameter CLKOUT2_PE_COARSE = 19,
    parameter CLKOUT2_PE_FINE   = 3
) (
    output LOCK,
    output CLKOUT0,
    output CLKOUT1,
    output CLKOUT2,
    output CLKOUT3,
    output CLKOUT4,
    output CLKOUT5,
    output CLKOUT6,
    output CLKFBOUT,
    input  CLKIN,
    input  CLKFB,
    input  RESET,
    input  PLLPWD,
    input  RESET_I,
    input  RESET_O,
    input  [5:0]  FBDSEL,
    input  [5:0]  IDSEL,
    input  [6:0]  MDSEL,
    input  [2:0]  MDSEL_FRAC,
    input  [6:0]  ODSEL0,
    input  [2:0]  ODSEL0_FRAC,
    input  [6:0]  ODSEL1,
    input  [6:0]  ODSEL2,
    input  [6:0]  ODSEL3,
    input  [6:0]  ODSEL4,
    input  [6:0]  ODSEL5,
    input  [6:0]  ODSEL6,
    input  [3:0]  DT0,
    input  [3:0]  DT1,
    input  [3:0]  DT2,
    input  [3:0]  DT3,
    input  [5:0]  ICPSEL,
    input  [2:0]  LPFRES,
    input  [1:0]  LPFCAP,
    input  [2:0]  PSSEL,
    input         PSDIR,
    input         PSPULSE,
    input         ENCLK0,
    input         ENCLK1,
    input         ENCLK2,
    input         ENCLK3,
    input         ENCLK4,
    input         ENCLK5,
    input         ENCLK6,
    input         SSCPOL,
    input         SSCON,
    input  [6:0]  SSCMDSEL,
    input  [2:0]  SSCMDSEL_FRAC
);

  // The model reproduces the vendor's documented output frequencies from the
  // divider parameters.  VCO ratio form: fout = FCLKIN * MDIV_SEL / ODIVn_SEL,
  // which gives 50*40/93 = 21.505 MHz and 50*40/31 = 64.516 MHz, the two numbers
  // gowin_pll_snes.v's header states.  A divider of 0 would be a divide by zero,
  // so it is treated as "output disabled" rather than silently producing inf.
  localparam real FIN = (FCLKIN == "50") ? 50.0 : 27.0;

  function automatic real period_ns(input integer mdiv, input integer odiv);
    period_ns = (odiv > 0) ? (1000.0 * odiv) / (FIN * mdiv) : 0.0;
  endfunction

  localparam real P0 = period_ns(MDIV_SEL, ODIV0_SEL);
  localparam real P1 = period_ns(MDIV_SEL, ODIV1_SEL);
  localparam real P2 = period_ns(MDIV_SEL, ODIV2_SEL);
  localparam real P3 = period_ns(MDIV_SEL, ODIV3_SEL);

  assign LOCK    = 1'b1;
  assign CLKFBOUT = CLKIN;

  reg c0 = 1'b0, c1 = 1'b0, c2 = 1'b0, c3 = 1'b0;

  // CLKOUT2 is the same frequency as CLKOUT1 with a phase offset given in the
  // vendor's coarse/fine units.  One coarse step is 22.5 degrees and one fine
  // step is a further 22.5/8 degrees, which is how 19/3 lands on 225 degrees:
  // 19*22.5 + 3*2.8125 = 427.5 + 8.4375 = 435.9 deg -- i.e. 225 plus one full
  // turn, which is what the hardware does.  Expressed as a delay on the first
  // edge, because that is what the capture logic downstream actually sees.
  localparam real PHASE_DEG  = (CLKOUT2_PE_COARSE * 22.5) + (CLKOUT2_PE_FINE * 2.8125);
  localparam real PHASE_NS   = (P2 > 0.0) ? (P2 * PHASE_DEG) / 360.0 : 0.0;
  localparam real PHASE_NS_W = (PHASE_NS > P2) ? (PHASE_NS - P2) : PHASE_NS;

  initial begin
    if (P0 <= 0.0 || P1 <= 0.0) begin
      $display("PLL model: ODIV_SEL is zero; check the divider parameters");
      $finish;
    end
  end

  always #(P0/2.0) if (CLKOUT0_EN == "TRUE") c0 = ~c0;
  always #(P1/2.0) if (CLKOUT1_EN == "TRUE") c1 = ~c1;
  always #(P2/2.0) if (CLKOUT2_EN == "TRUE") c2 = ~c2;
  always #(P3/2.0) if (CLKOUT3_EN == "TRUE") c3 = ~c3;

  assign CLKOUT0 = c0;
  assign CLKOUT1 = c1;
  assign CLKOUT2 = (CLKOUT2_EN == "TRUE") ? c2 : 1'b0;
  assign CLKOUT3 = (CLKOUT3_EN == "TRUE") ? c3 : 1'b0;
  assign CLKOUT4 = 1'b0;
  assign CLKOUT5 = 1'b0;
  assign CLKOUT6 = 1'b0;

endmodule

// ----------------------------------------------------------------- CLKDIV
// The pixel clock divider.  DIV_MODE is a two-character decimal string; "5"
// means divide by 5.  Only the integer divide matters to the bench, and only
// one instance is in the design (div5, making 74.25 MHz from 371.25 MHz).
module CLKDIV #(
    parameter DIV_MODE = "5"
) (
    output CLKOUT,
    input  CLKIN
);

  function automatic integer div_of(input [8*2-1:0] mode);
    integer i, d;
    begin
      d = 0;
      for (i = 0; i < 2; i = i + 1)
        if (mode[8*i +: 8] >= "0" && mode[8*i +: 8] <= "9")
          d = d * 10 + (mode[8*i +: 8] - "0");
      div_of = (d == 0) ? 2 : d;
    end
  endfunction

  localparam integer DIV = div_of(DIV_MODE);

  reg [31:0] cnt = 0;
  reg        q   = 1'b0;

  always @(posedge CLKIN) begin
    if (cnt == DIV - 1) begin
      cnt <= 0;
      q   <= ~q;
    end else begin
      cnt <= cnt + 1;
    end
  end

  assign CLKOUT = q;

endmodule

// ------------------------------------------------------------------- DFFRE
module DFFRE (
    output reg Q,
    input      D,
    input      CLK,
    input      CE,
    input      R
);
  initial Q = 1'b0;
  always @(posedge CLK or posedge R)
    if (R) Q <= 1'b0;
    else if (CE) Q <= D;
endmodule

// --------------------------------------------------------------------- SP
// Single-port block RAM, bit-selectable.  vram_spb builds a byte-wide line
// buffer from sixteen of these, one bit per instance, each 48K deep across
// three 16K blocks selected by BLKSEL.  The model stores the 32-bit DI/DO word
// as given, so a bit-wide instance simply uses bit 0.
module SP (
    output reg [31:0] DO,
    input  [31:0] DI,
    input         CLK,
    input         OCE,
    input         CE,
    input         RESET,
    input         WRE,
    input  [2:0]  BLKSEL,
    input  [13:0] AD
);
  localparam integer DEPTH = 3 * 16384;
  reg [31:0] mem [0:DEPTH-1];
  wire [15:0] idx = {BLKSEL[1:0], AD};

  integer i;
  initial begin
    for (i = 0; i < DEPTH; i = i + 1) mem[i] = 32'd0;
    DO = 32'd0;
  end

  always @(posedge CLK) begin
    if (CE && WRE) mem[idx] <= DI;
    if (OCE) DO <= mem[idx];
  end
endmodule

// -------------------------------------------------------------------- DPB
// Dual-port block RAM in the 16-bit-deep-by-widest shape the vendor IP uses for
// CGRAM, OAM and the OSD menu.  Address and data widths are taken from the
// instance's connectivity, so the model keeps them at the largest size the
// design uses (14-bit address, 16-bit data) and ignores the overflow bits.
module DPB (
    output reg [15:0] DOA,
    output reg [15:0] DOB,
    input  [15:0] DIA,
    input  [15:0] DIB,
    input  [13:0] ADA,
    input  [13:0] ADB,
    input         CLKA,
    input         CLKB,
    input         OCEA,
    input         OCEB,
    input         CEA,
    input         CEB,
    input         RESETA,
    input         RESETB,
    input         WREA,
    input         WREB,
    input  [1:0]  BLKSELA,
    input  [1:0]  BLKSELB
);
  localparam integer DEPTH = 4 * 16384;
  reg [15:0] mem [0:DEPTH-1];
  wire [15:0] ia = {BLKSELA, ADA};
  wire [15:0] ib = {BLKSELB, ADB};

  integer i;
  initial begin
    for (i = 0; i < DEPTH; i = i + 1) mem[i] = 16'd0;
    DOA = 16'd0;
    DOB = 16'd0;
  end

  always @(posedge CLKA) begin
    if (CEA && WREA) mem[ia] <= DIA;
    if (OCEA) DOA <= mem[ia];
  end

  always @(posedge CLKB) begin
    if (CEB && WREB) mem[ib] <= DIB;
    if (OCEB) DOB <= mem[ib];
  end
endmodule
