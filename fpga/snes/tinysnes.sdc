# TinySNES clocks on the Tang Console 138K.
# SPDX-License-Identifier: GPL-3.0-only
#
# Adapted from SNESTang's src/snestang.sdc (nand2mario), which was written for
# the Tang Primer 25K's clock plan.  The 138K's PLL divides the 50 MHz crystal
# differently -- fclk is 50 * 40 / 31 = 64.516 MHz, not 85.9375 -- so the
# periods below follow gowin_pll_snes rather than the original file.

create_clock -name sys_clk -period 20.000 [get_ports {sys_clk}]

# SDRAM clock and the master logic clock divided from it.  The SNES core, the
# SDRAM controller and the CEGen all run from these.
create_clock -name fclk -period 15.500 [get_nets {fclk}]

# nextpnr does not support create_generated_clock, so mclk is declared with its
# own period: 50 * 40 / 93 = 21.505 MHz, one fclk in three (46.5 ns).  yosys
# drops the `mclk` net name (the PLL output is shared with an alias), so the
# clock is taken from the PLL cell's output pin instead.
create_clock -name mclk -period 46.500 [get_pins {pll_snes.PLL_inst/CLKOUT0}]

# HDMI: 371.25 MHz serialiser bit clock and the 74.25 MHz 720p pixel clock.
create_clock -name hclk5 -period 2.694 [get_nets {hclk5}]
create_clock -name hclk -period 13.468 [get_nets {hclk}]

# SNESTang's own constraint file relaxes the mclk<->fclk paths to three cycles,
# because an SDRAM access takes three fclk (see the timing notes at the head of
# sdram_cl2_2ch.v).  nextpnr's SDC parser has neither get_clocks nor
# set_multicycle_path, so those statements are omitted here and the crossings
# stay at the conservative single-cycle assumption.  That over-constrains rather
# than under-constrains; if the SDRAM paths fail timing, this is where to look,
# and the fix belongs in the controller's handshake, not in a hidden exception.
