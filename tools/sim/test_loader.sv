// SPDX-License-Identifier: MIT
//
// Embedded-ROM cartridge loader, for simulation only.
//
// snestang_top.v already instantiates a module of this name inside its
// `ifdef VERILATOR branch, but no definition of it survived the port to this
// repository: the branch is dead code that fails to elaborate, which is one
// reason no bench in this project has ever instantiated snestang_top.  This is
// that definition.
//
// It reproduces the bytes the real BL616 link delivers, in the order
// fpga/snes/src/iosys/iosys_bl616.v delivers them and tools/load_snes_rom.py
// sends them (EXT-003): the 64-byte cartridge header at file offset $7FC0
// first, then the image from offset 0, with `loading` high for the duration and
// released at the end.  snestang_top resets its byte counter on the rising edge
// of `loading`, passes the first 64 strobes through smc_parser to derive
// ROM_TYPE/ROM_MASK, and starts writing SDRAM once header_finished rises.
//
// The byte rate is the one thing that must match the hardware rather than being
// convenient.  The real loader sends 2 Mbaud over UART, about 200000 bytes/s,
// which at mclk 21.505 MHz is roughly 107 master clocks per byte.  Sending
// faster would overrun the SDRAM write path -- the controller's req/ack pair is
// a toggle that silently loses a request when a second arrives before the first
// is served -- and the bench would then report a corrupt image as a machine
// fault.  That exact confusion is what this bench exists to avoid, so the rate
// is a parameter and the default reproduces the link.
//
// Plusargs:
//   +hex=<path>       one byte per line, the format run_gsu_sim.sh generates
//   +romlen=<bytes>   image length; with neither, 1 MiB is assumed

`timescale 1ns/1ps

module test_loader (
    input  wire       clk,
    input  wire       resetn,
    output reg  [7:0] dout,
    output reg        dout_valid,
    output reg        loading,
    output reg        fail
);

  // The largest image this project loads is 1 MiB; Star Fox is 1 MiB and Zelda
  // is 1 MiB, so the array is sized once rather than per run.
  localparam integer MAXLEN = 4 * 1024 * 1024;   // the largest cart the board loads

  reg [7:0] img [0:MAXLEN-1];

  reg [1023:0] hex_path;
  integer romlen;
  integer bitrate_clk;
  integer have_file;

  integer i;
  initial begin
    for (i = 0; i < MAXLEN; i = i + 1) img[i] = 8'h00;
    dout       = 8'h00;
    dout_valid = 1'b0;
    loading    = 1'b0;
    fail       = 1'b0;

    romlen      = MAXLEN;
    bitrate_clk = 108;          // ~2 Mbaud at 21.505 MHz, see the header
    have_file   = 0;

    if ($value$plusargs("hex=%s", hex_path)) begin
      $readmemh(hex_path, img);
      have_file = 1;
    end else begin
      $display("test_loader: no +hex=<path> given, the cartridge is all zeros");
      fail = 1'b1;
    end
    void'($value$plusargs("romlen=%d", romlen));
    void'($value$plusargs("byteclk=%d", bitrate_clk));
    if (bitrate_clk < 4) bitrate_clk = 4;
  end

  // Stream position.  0 .. 63 is the header block taken from $7FC0; from 64 on
  // it is the image from offset 0.  This mirrors EXT-003 and iosys_bl616.
  integer pos;          // index within the current phase
  integer total;        // total bytes to send
  integer sent;
  reg     sending;
  reg     finished = 1'b0;
  integer pace;

  // The header is always 64 bytes; the image follows.
  always @(posedge clk) begin
    if (~resetn) begin
      loading    <= 1'b0;
      dout_valid <= 1'b0;
      sent       <= 0;
      pace       <= 0;
      sending    <= 1'b0;
      finished   <= 1'b0;
      pos        <= 0;
      total      <= 64 + romlen;
    end else if (finished) begin
      // The link stays released.  Without this the state machine re-entered its
      // start state on the cycle after completion and reloaded the cartridge
      // forever, which is exactly what the first run of this bench did: the
      // loader reported "link released" and snestang_top still read loading=1.
      loading    <= 1'b0;
      dout_valid <= 1'b0;
    end else begin
      if (~sending) begin
        // Hold `loading` for a few clocks before the first byte so
        // snestang_top's rising-edge detector has seen it and cleared its
        // counters, exactly as a real link's gap does.
        if (pace < 8) begin
          pace <= pace + 1;
          loading <= 1'b1;
        end else begin
          sending <= 1'b1;
          pace <= 0;
          sent <= 0;
        end
      end else if (pace < bitrate_clk - 1) begin
        pace <= pace + 1;
        dout_valid <= 1'b0;
      end else begin
        pace <= 0;
        if (sent >= total) begin
          // Release the link.  snestang_top sets `loaded` on this falling edge
          // and only then allows the machine to start.
          loading    <= 1'b0;
          dout_valid <= 1'b0;
          sending    <= 1'b0;
          finished   <= 1'b1;
          $display("test_loader: %0d bytes streamed (64 header + %0d image); link released",
                   total, romlen);
        end else begin
          dout_valid <= 1'b1;
          if (sent % 100000 == 0)
            $display("test_loader: byte %0d of %0d at %0t", sent, total, $time);
          if (sent < 64)
            dout <= img[16'h7FC0 + sent];
          else
            dout <= img[sent - 64];
          sent <= sent + 1;
        end
      end
    end
  end

endmodule
