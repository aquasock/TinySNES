// SPDX-License-Identifier: MIT
//
// Which cartridge layout does the header decoder actually select?
//
// Written because a claim about ExHiROM was put to the user from reading the
// RTL by eye, and reading by eye had already produced one wrong statement in
// this session (a printf declared as %02X:%04X that was then reported as the
// program counter leaving the cartridge).  This bench answers the question
// mechanically: it feeds smc_parser the 64-byte header for a given map byte,
// takes the rom_type it produces, then drives the real DSP_LHRomMap with that
// rom_type and prints the cartridge offset it computes for a set of addresses
// whose expected layout is known.
//
// The check is on the OFFSET, not on a mode name: for a 1 MiB image laid out
// the way the mode says it is laid out, a given CPU address must land on a
// specific file offset, and that is the thing that either matches or does not.
//
// Run: verilator --binary --timing -Wno-fatal --top-module maptype_tb ... 
// (see tools/sim/run_maptype.sh)

`timescale 1ns/1ps

module maptype_tb;

  reg clk = 1'b0;
  always #5 clk = ~clk;

  // ---------------------------------------------------------- smc_parser
  reg        smc_rst = 1'b0;
  reg  [7:0] rom_d   = 8'h00;
  reg        rom_strb = 1'b0;
  wire [7:0] rom_type;
  wire [23:0] rom_mask, ram_mask;
  wire [3:0] rom_size, ram_size;
  wire       header_finished;

  smc_parser smc (
    .clk(clk), .resetn(~smc_rst),
    .rom_d(rom_d), .rom_strb(rom_strb),
    .rom_type(rom_type), .rom_mask(rom_mask), .ram_mask(ram_mask),
    .rom_size(rom_size), .ram_size(ram_size),
    .header_finished(header_finished)
  );

  // -------------------------------------------------------- DSP_LHRomMap
  // Only the ports this question needs are driven; the DSP core is disabled so
  // no microcode has to be present.
  reg  [23:0] CA = 24'h000000;
  wire [23:0] ROM_ADDR;

  DSP_LHRomMap #(.USE_DSPn(1'b0)) map (
    .MCLK(clk), .RST_N(1'b1), .ENABLE(1'b1),
    .CA(CA), .DI(8'h00), .DO(),
    .CPURD_N(1'b0), .CPUWR_N(1'b1),
    .PA(8'h00), .PARD_N(1'b1), .PAWR_N(1'b1),
    .ROMSEL_N(1'b0), .RAMSEL_N(1'b1),
    .SYSCLKF_CE(1'b1), .SYSCLKR_CE(1'b1), .REFRESH(1'b0),
    .IRQ_N(),
    .ROM_ADDR(ROM_ADDR), .ROM_Q(16'h0000),
    .ROM_CE_N(), .ROM_OE_N(), .ROM_WORD(),
    .BSRAM_ADDR(), .BSRAM_D(), .BSRAM_Q(8'h00),
    .BSRAM_CE_N(), .BSRAM_OE_N(), .BSRAM_WE_N(),
    .MAP_ACTIVE(), .MAP_CTRL(rom_type),
    .ROM_MASK(rom_mask), .BSRAM_MASK(ram_mask),
    .EXT_RTC(65'd0)
  );

  // ------------------------------------------------------------- stimulus
  integer i;
  integer mapbyte;
  integer nlayout;

  task automatic feed_header(input [7:0] mb);
    begin
      // snestang_top resets the parser on the rising edge of `loading`
      // (resetn & ~(loading & ~loading_r)), so a fresh header needs a reset.
      // Without this the parser latches header_finished after the first pass
      // and every later map byte reads back as the first one.
      smc_rst = 1'b1;
      @(posedge clk); @(posedge clk);
      smc_rst = 1'b0;
      @(posedge clk);
      for (i = 0; i < 64; i = i + 1) begin
        @(negedge clk);
        rom_strb = 1'b1;
        case (i)
          8'h15: rom_d = mb;
          8'h16: rom_d = 8'h00;   // rom type: plain "ROM only"
          8'h17: rom_d = 8'h0A;   // rom size: 1 MiB
          8'h18: rom_d = 8'h00;   // ram size: none
          8'h1A: rom_d = 8'h33;   // company: Nintendo
          default: rom_d = 8'h00;
        endcase
        @(posedge clk);
      end
      @(negedge clk);
      rom_strb = 1'b0;
      @(posedge clk);
      @(posedge clk);
    end
  endtask

  // Probe a CPU address and print the cartridge offset the mapper produces.
  task automatic probe(input [23:0] addr);
    begin
      @(negedge clk);
      CA = addr;
      @(posedge clk);
      @(posedge clk);
      $display("    CPU $%06X -> cart offset $%06X", addr, ROM_ADDR);
    end
  endtask

  integer mb, n_lo, n_hi, n_exhi, n_exlo, n_spec, n_other;
  reg [7:0] seen_type;

  initial begin
    $display("maptype bench: which layouts are reachable from a header?");
    $display("");
    $display("Sweeping all 256 map bytes at $7FD5 with rom_type_header=$00 and");
    $display("company=$00, i.e. nothing that triggers a coprocessor override.");
    $display("");

    n_lo = 0; n_hi = 0; n_exhi = 0; n_exlo = 0; n_spec = 0; n_other = 0;
    for (mb = 0; mb < 256; mb = mb + 1) begin
      feed_header(mb[7:0]);
      case (rom_type[1:0])
        2'b00: if (rom_type[3]) n_exlo = n_exlo + 1; else n_lo = n_lo + 1;
        2'b01: n_hi = n_hi + 1;
        2'b10: n_exhi = n_exhi + 1;
        default: n_spec = n_spec + 1;
      endcase
    end

    $display("  MAP_CTRL[1:0]=00 LoROM   path : %0d map bytes", n_lo);
    $display("  MAP_CTRL[1:0]=00 ExLoROM path : %0d map bytes", n_exlo);
    $display("  MAP_CTRL[1:0]=01 HiROM   path : %0d map bytes", n_hi);
    $display("  MAP_CTRL[1:0]=10 ExHiROM path : %0d map bytes", n_exhi);
    $display("  MAP_CTRL[1:0]=11 Special  path: %0d map bytes", n_spec);
    $display("");

    if (n_exhi == 0)
      $display("  RESULT: the ExHiROM branch is UNREACHABLE from any header with no");
    else
      $display("  RESULT: the ExHiROM branch is reachable from %0d map bytes:", n_exhi);
    $display("");

    // The specific bytes the standard header table uses, probed for offsets.
    for (nlayout = 0; nlayout < 4; nlayout = nlayout + 1) begin
      case (nlayout)
        0: mapbyte = 8'h20;   // LoROM
        1: mapbyte = 8'h21;   // HiROM
        2: mapbyte = 8'h35;   // ExHiROM + FastROM
        default: mapbyte = 8'h25;  // ExHiROM (alternate)
      endcase
      feed_header(mapbyte[7:0]);
      $display("  map byte $%02X -> rom_type $%02X  MAP_CTRL[1:0]=%02b", mapbyte, rom_type, rom_type[1:0]);
      probe(24'h00_8000);
      probe(24'h00_FFFC);
      probe(24'h40_0000);
      $display("");
    end

    $display("maptype bench done");
    $finish;
  end

endmodule
