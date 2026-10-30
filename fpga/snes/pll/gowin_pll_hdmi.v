// SPDX-License-Identifier: MIT
//
// The HDMI clocks, from the 27 MHz PLL that gowin_pll_27 makes from the 50 MHz
// crystal: 27 * 55 / 4 = 371.25 MHz (clkout0, the serialiser bit clock, hclk5)
// and 27 * 55 / 20 = 74.25 MHz (clkout1, the 720p pixel clock, hclk).
//
// Hand-written instantiation of the PLL primitive, derived from TinyTang's
// fpga/desktop/pll/gowin_pll_hdmi.v -- that core enables clkout0 only, and
// SNESTang needs the pixel clock from clkout1 as well, so ODIV1_SEL is 20
// instead of 8 and CLKOUT1_EN is TRUE, matching the parameters in the Gowin
// IP-generator wrapper this replaces.  This project brings no vendor-generated
// file into the repository.  See THIRD_PARTY.md.
//
// The module name, the port list, the inner instance name and the net structure
// match the generated wrapper; snestang_top and snes2hdmi instantiate them by
// name.

module gowin_pll_hdmi (clkout0, clkout1, clkin);

output clkout0;
output clkout1;
input  clkin;

wire lock, clkout2, clkout3, clkout4, clkout5, clkout6, clkfbout;
wire gw_vcc, gw_gnd;

assign gw_vcc = 1'b1;
assign gw_gnd = 1'b0;

PLL #(
    .FCLKIN("27"),
    .IDIV_SEL(1),
    .FBDIV_SEL(1),
    .MDIV_SEL(55),
    .MDIV_FRAC_SEL(0),
    .ODIV0_SEL(4),
    .ODIV0_FRAC_SEL(0),
    .ODIV1_SEL(20),
    .ODIV2_SEL(8),
    .ODIV3_SEL(8),
    .ODIV4_SEL(8),
    .ODIV5_SEL(8),
    .ODIV6_SEL(8),
    .CLKOUT0_EN("TRUE"),
    .CLKOUT1_EN("TRUE"),
    .CLKOUT2_EN("FALSE"),
    .CLKOUT3_EN("FALSE"),
    .CLKOUT4_EN("FALSE"),
    .CLKOUT5_EN("FALSE"),
    .CLKOUT6_EN("FALSE"),
    .CLKFB_SEL("INTERNAL"),
    .CLKOUT0_DT_DIR(1'b1),
    .CLKOUT0_DT_STEP(0),
    .CLKOUT0_PE_COARSE(0),
    .CLKOUT0_PE_FINE(0)
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
