// SPDX-License-Identifier: MIT
//
// The SDRAM clock pair, split out of gowin_pll_snes onto its own PLL so that
// `fclk` can reach the global clock plane.  See core-log entry 25 and
// core-reference TCL-015.
//
// Why this exists.  apicula's `_gw5a_pll_clk_wires` carries only three pips
// into the clock plane for this device: `CLKOUT0` at slots 0 and 4, and
// `CLKOUT2` at slot 0.  A PLL output with no entry has no way onto the plane,
// and nextpnr then routes it as ordinary interconnect.  gowin_pll_snes drove
// `fclk` from `CLKOUT1` at `PLL_R[0]`, which has no entry, and the routed
// netlist showed it on 1281 general-routing segments with no spine and no
// global tap, clocking 225 flip-flops spread across 40 tiles -- the SDRAM
// controller, and with it ROM, WRAM, ARAM and the loader.
//
// This PLL sits at `PLL_L[0]` (slot 0) and puts `fclk` on `CLKOUT2`, whose pip
// `(0, 'CLKOUT2') -> 'TLPLL0CLK2'` TinyGBA measured from the vendor flow and
// added to the fork at 495661a.  That wire takes the centre clock mux at
// `(54,93)` onto SPINE10 through CBRIDGEOUT_TOP2, which is a path TinyNES
// measured as running (core-reference DEV-009) rather than one of the dead
// ones.  The phase-shifted output stays on the same PLL so the phase relation
// between `fclk` and `fclk_p` is preserved, which the SDRAM DQ capture depends
// on (TCL-007): 225 degrees of 64.516 MHz is what gowin_pll_snes produced with
// CLKOUT2_PE_COARSE 19 / PE_FINE 3, and the same values now phase CLKOUT1.
//
// VCO arithmetic is unchanged: 50 * 40 / 1 = 2000 MHz, divided by 31 for both
// outputs, so `fclk` is 64.516 MHz exactly as before.
//
// The module name, port list and inner instance name follow gowin_pll_snes so
// the top level and the constraint file read alike.

module gowin_pll_sdram (clkout1, clkout2, clkin);

output clkout1;      // fclk_p, 64.516 MHz shifted 225 degrees, drives O_sdram_clk
output clkout2;      // fclk,   64.516 MHz on the clock plane
input  clkin;

wire lock, clkout0, clkout3, clkout4, clkout5, clkout6, clkfbout;
wire gw_vcc, gw_gnd;

assign gw_vcc = 1'b1;
assign gw_gnd = 1'b0;

PLL #(
    .FCLKIN("50"),
    .IDIV_SEL(1),
    .FBDIV_SEL(1),
    .MDIV_SEL(40),
    .MDIV_FRAC_SEL(0),
    // CLKOUT0 is disabled: at this slot its plane wire is TLPLL0CLK0, which
    // TinyNES measured as producing a dead core (DEV-009), so nothing may be
    // driven from it.
    .ODIV0_SEL(8),
    .ODIV0_FRAC_SEL(0),
    .ODIV1_SEL(31),
    .ODIV2_SEL(31),
    .ODIV3_SEL(8),
    .ODIV4_SEL(8),
    .ODIV5_SEL(8),
    .ODIV6_SEL(8),
    .CLKOUT0_EN("FALSE"),
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
    // The 225-degree shift moves from CLKOUT2 to CLKOUT1 with the outputs, so
    // fclk (CLKOUT2) is the unshifted clock and fclk_p (CLKOUT1) is the late
    // one, exactly the relation gowin_pll_snes produced.
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
