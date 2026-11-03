// SPDX-License-Identifier: MIT
//
// SNESTang's clock trio, from the 50 MHz crystal:
//   clkout0 50 * 40 / 93 = 21.505 MHz  SNES master clock (mclk)
//   clkout1 50 * 40 / 31 = 64.516 MHz, phase-shifted 225 degrees (fclk_p,
//           drives O_sdram_clk)
//   clkout2 50 * 40 / 31 = 64.516 MHz  SDRAM controller clock (fclk)
//
// TinySNES: clkout1 and clkout2 are swapped from upstream's arrangement, and
// the reason is the clock plane rather than the clock arithmetic.  apicula's
// `_gw5a_pll_clk_wires` table for GW5AST-138C carries exactly three PLL-to-
// plane wires: CLKOUT0 on the left edge (TLPLL0CLK0), CLKOUT0 on the right edge
// (TRPLL0CLK0), and CLKOUT2 on the left edge only (TLPLL0CLK2).  CLKOUT1 has no
// plane wire on this device at all.  Upstream put fclk -- which clocks the
// entire SDRAM controller, the design's widest fast domain -- on CLKOUT1, so it
// never reached the global clock spine and was routed point to point across
// 18,400 characters of interconnect with no spine tap.  Measured on the routed
// netlist: `iosys.clk` (mclk, CLKOUT0) enters the plane through TRPLL0CLK0
// while `fclk` carries no bridge pip of any kind.  Moving fclk onto CLKOUT2 and
// placing this PLL at PLL_L[0] gives it TLPLL0CLK2, which TinyGBA measured
// against the vendor flow on 2026-10-31 (its core-log entry 4) as reaching the
// plane and clocking 48 GB00 sinks.  The 225-degree shift therefore moves to
// CLKOUT1, which drives one pin and needs no plane access.  See core-log entry
// 75 and TCL-015.
//
// Hand-written instantiation of the PLL primitive, carried over from TinyTang's
// fpga/desktop/pll/gowin_pll_nes.v, whose parameters are identical.  The Gowin
// IP-generator wrapper that carried this name opened with "Copyright (C)2014
// Gowin Semiconductor Corporation.  All rights reserved.", and this project's
// rule is that no vendor-generated file is brought into the repository, so the
// configuration is expressed here instead.  See THIRD_PARTY.md.
//
// The module name, the port list, the inner instance name and the net structure
// match the generated wrapper.  snestang_top instantiates this by name, and on
// this device and toolchain the netlist decides the placement, the placement
// decides where the clocks land, and that decides whether the core runs at all.
// Tidying these dangling nets is therefore not a safe refactor.

module gowin_pll_snes (clkout0, clkout1, clkout2, clkin);

output clkout0;
output clkout1;
output clkout2;
input  clkin;

wire lock, clkout1, clkout2, clkout3, clkout4, clkout5, clkout6, clkfbout;
wire gw_vcc, gw_gnd;

assign gw_vcc = 1'b1;
assign gw_gnd = 1'b0;

PLL #(
    .FCLKIN("50"),
    .IDIV_SEL(1),
    .FBDIV_SEL(1),
    .MDIV_SEL(40),
    .MDIV_FRAC_SEL(0),
    .ODIV0_SEL(93),
    .ODIV0_FRAC_SEL(0),
    .ODIV1_SEL(31),
    .ODIV2_SEL(31),
    .ODIV3_SEL(8),
    .ODIV4_SEL(8),
    .ODIV5_SEL(8),
    .ODIV6_SEL(8),
    .CLKOUT0_EN("TRUE"),
    .CLKOUT1_EN("TRUE"),
    .CLKOUT2_EN("TRUE"),
    .CLKOUT3_EN("FALSE"),
    .CLKOUT4_EN("FALSE"),
    .CLKOUT5_EN("FALSE"),
    .CLKOUT6_EN("FALSE"),
    .CLKFB_SEL("INTERNAL"),
    .CLKOUT0_DT_DIR(1'b1),
    .CLKOUT0_DT_STEP(0),
    .CLKOUT0_PE_COARSE(0),
    .CLKOUT0_PE_FINE(0),
    // 225 degrees of shift, moved from CLKOUT2 to CLKOUT1 with the swap above.
    // 19 coarse steps of 22.5 degrees plus 3 fine steps of 2.8125 degrees is
    // 435.9 degrees, i.e. 225 plus one full turn, which is the figure the
    // previous arrangement produced and the capture points were tuned against.
    .CLKOUT1_PE_COARSE(19),
    .CLKOUT1_PE_FINE(3),
    .CLKOUT2_PE_COARSE(0),
    .CLKOUT2_PE_FINE(0)
) PLL_inst (
    .LOCK(lock),
    .CLKOUT0(clkout0),
    .CLKOUT1(clkout1),
    .CLKOUT2(clkout2),
    .CLKOUT3(clkout3),
    .CLKOUT4(clkout4),
    .CLKOUT5(clkout5),
    .CLKOUT6(clkout6),
    .CLKFBOUT(clkfbout),
    .CLKIN(clkin),
    .CLKFB(gw_gnd),
    .RESET(gw_gnd),
    .PLLPWD(gw_gnd),
    .RESET_I(gw_gnd),
    .RESET_O(gw_gnd),
    .FBDSEL(6'b0),
    .IDSEL(6'b0),
    .MDSEL(7'b0),
    .MDSEL_FRAC(3'b0),
    .ODSEL0(7'b0),
    .ODSEL0_FRAC(3'b0),
    .ODSEL1(7'b0),
    .ODSEL2(7'b0),
    .ODSEL3(7'b0),
    .ODSEL4(7'b0),
    .ODSEL5(7'b0),
    .ODSEL6(7'b0),
    .DT0(4'b0),
    .DT1(4'b0),
    .DT2(4'b0),
    .DT3(4'b0),
    .ICPSEL(6'b0),
    .LPFRES(3'b0),
    .LPFCAP(2'b0),
    .PSSEL(3'b0),
    .PSDIR(gw_gnd),
    .PSPULSE(gw_gnd),
    .ENCLK0(gw_vcc),
    .ENCLK1(gw_vcc),
    .ENCLK2(gw_vcc),
    .ENCLK3(gw_vcc),
    .ENCLK4(gw_vcc),
    .ENCLK5(gw_vcc),
    .ENCLK6(gw_vcc),
    .SSCPOL(gw_gnd),
    .SSCON(gw_gnd),
    .SSCMDSEL(7'b0),
    .SSCMDSEL_FRAC(3'b0)
);

endmodule
