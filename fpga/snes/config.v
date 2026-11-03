// TinySNES board configuration for the Tang Console 138K.
// SPDX-License-Identifier: GPL-3.0-only
//
// Replaces SNESTang's src/boards/console138k.v.  Read before snestang_top.v:
// the top checks for CONFIG_V and imports configPackage.
//
// Differences from nand2mario's console138k configuration:
//   - no USB1/USB2: the Console's controllers reach the core through the BL616
//     (iosys_bl616 hands over hid1/hid2), so the FPGA-side USB HID host, its
//     12 MHz PLL and usb_hid_host.v are not built.
//   - no CONTROLLER_DS2 and no CONTROLLER_SNES: no controller pads are wired
//     to this board; pads arrive over the UART link.
//   - MCU_BL616: the soft-CPU I/O system is the BL616 link, not PicoRV32.
//   - CHIP_GSU: the SuperFX coprocessor is built, which is what makes Star Fox
//     and other GSU cartridges runnable.  snestang_top.v resolves USE_GSU from
//     this define and defaults it to 0 without it, so a build that omits it has
//     no coprocessor at all and every GSU measurement would be meaningless.
//     Until core-log entry 73 this define existed only on diagnostic command
//     lines, so the committed configuration could not reproduce the builds
//     whose GSU behaviour the log records.

`define CONFIG_V

`define CHIP_DSPn
`define CHIP_GSU
`define MCU_BL616

package configPackage;

localparam SDRAM_DATA_WIDTH = 16;
localparam SDRAM_ROW_WIDTH = 13;

endpackage
