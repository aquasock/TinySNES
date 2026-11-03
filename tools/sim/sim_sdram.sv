// SPDX-License-Identifier: MIT
//
// Behavioural model of the Winbond W9825G6KH-6 the Tang Console carries, in the
// shape sdram_cl2_2ch.v drives it.
//
// This exists so a bench can run the *real* SDRAM controller
// (fpga/snes/src/sdram_cl2_2ch.v) instead of an array that always answers in
// zero time.  That difference is the whole point: this project's bench models
// have never contained the controller, the two clock domains or the req/ack
// toggle handshakes, which is the entire layer where a fault that appears only
// on the board has to live (core-log entry 72).
//
// What is modelled faithfully:
//   - command decode from {nCS, nRAS, nCAS, nWE}
//   - bank activate latching the row, precharge clearing it
//   - read data appearing CAS latency cycles after the READ command
//   - write data sampled with the WRITE command, honouring DQM byte masks
//   - the part's 4 banks x 8192 rows x 512 columns x 16 bits geometry
//   - mode-register writes latching the CAS latency the controller programs
//
// What is deliberately NOT modelled: refresh timing requirements, tRCD/tRP/tRC
// violation detection, power-up sequencing, and any analogue behaviour.  The
// controller is written for a part that meets those timings, so a model that
// enforces them would only add false failures.  A violation here shows up as
// wrong data rather than as an assertion, which is the same way it would show up
// on the bench, and the bench's own tests are the thing that catches it.
//
// The clock this is driven by is O_sdram_clk -- the PLL's 225-degree shifted
// output -- not fclk, because that is the edge the real part sees and the
// controller's capture points were tuned against it (core-log entry 3).

`timescale 1ns/1ps

module sim_sdram #(
    parameter integer ROWS = 8192,
    parameter integer COLS = 512,
    parameter integer CL_DEFAULT = 2
) (
    inout  wire [15:0] DQ,
    input  wire [12:0] A,
    input  wire [1:0]  BA,
    input  wire [1:0]  DQM,
    input  wire        nCS,
    input  wire        nRAS,
    input  wire        nCAS,
    input  wire        nWE,
    input  wire        CKE,
    input  wire        CLK            // O_sdram_clk
);

  localparam integer DEPTH = 4 * ROWS * COLS;

  reg [15:0] mem [0:DEPTH-1];

  // Address of a word.  The controller drives {bank, row, col} across the same
  // A bus in two phases: the row on ACT, the column on READ/WRITE.  Rows are 13
  // bits, columns 9, and the part has 4 banks.
  function automatic [31:0] addr_of(
      input [1:0]  bank,
      input [12:0] row_i,
      input [8:0]  col_i
  );
    addr_of = ((bank * ROWS) + row_i) * COLS + col_i;
  endfunction

  // Command decode.  A command is only valid when the part is selected.
  wire cmd_valid = ~nCS;
  wire is_mrs    = cmd_valid & ~nRAS & ~nCAS & ~nWE;
  wire is_ref    = cmd_valid & ~nRAS & ~nCAS &  nWE;
  wire is_pre    = cmd_valid & ~nRAS &  nCAS & ~nWE;
  wire is_act    = cmd_valid & ~nRAS &  nCAS &  nWE;
  // nWE is active LOW, so a read asserts no write enable (nWE=1) and a write
  // asserts it (nWE=0).  The controller's own encodings are CMD_Read=4'b0101
  // and CMD_Write=4'b0100 (sdram_cl2_2ch.v:141-142).  The first version of this
  // model had these two the wrong way round, which made every one of the
  // loader's writes decode as a read: the image never landed, the CPU fetched
  // opcode $00 forever, and the bench reported a machine fault that was really
  // a fault in the instrument.
  wire is_read   = cmd_valid &  nRAS & ~nCAS &  nWE;
  wire is_write  = cmd_valid &  nRAS & ~nCAS & ~nWE;

  reg [12:0] row_lat [0:3];
  reg [1:0]  cl = CL_DEFAULT;

  wire [8:0] col = A[8:0];
  wire [8:0] row = A[8:0];      // ACT uses A[12:0] for the row; see below

  integer i;
  initial begin
    for (i = 0; i < DEPTH; i = i + 1) mem[i] = 16'h0000;
    for (i = 0; i < 4; i = i + 1) row_lat[i] = 13'd0;
  end

  // ------------------------------------------------------------------ writes
  // DQ is driven by the controller during a WRITE and is captured here on the
  // same edge, which is what CL=2 with a write command means on this part.
  wire [15:0] dq_in = DQ;

  // ------------------------------------------------------- address and data
  // One index, computed combinationally, used by both the read and the write
  // path.  Verilator rejects two non-blocking assignments to different bit
  // ranges of the same memory element, so a byte-masked write is done as a
  // read-modify-write into a single full-word target instead.
  wire [31:0] word_index = addr_of(BA, row_lat[BA], col);


  reg [15:0] wr_word;
  always @(*) begin
    wr_word = mem[word_index];          // lanes held at DQM keep their old value
    if (~DQM[0]) wr_word[7:0]  = dq_in[7:0];
    if (~DQM[1]) wr_word[15:8] = dq_in[15:8];
  end

  // ------------------------------------------------------------------- reads
  // A 2-stage pipeline covers the CAS latencies the controller can program.
  // Each stage carries a valid bit, so a read followed by idle cycles does not
  // re-drive stale data onto the bus.
  reg [15:0] rd_data  [0:3];
  reg [3:0]  rd_valid;
  reg [15:0] dq_drive;
  reg        dq_oe;

  integer k;
  initial begin
    for (k = 0; k < 4; k = k + 1) begin
      rd_data[k]  = 16'h0000;
      rd_valid[k] = 1'b0;
    end
    dq_drive = 16'h0000;
    dq_oe    = 1'b0;
  end

  always @(posedge CLK) begin
    rd_valid[3] <= rd_valid[2];
    rd_data[3]  <= rd_data[2];
    rd_valid[2] <= rd_valid[1];
    rd_data[2]  <= rd_data[1];
    rd_valid[1] <= rd_valid[0];
    rd_data[1]  <= rd_data[0];

    if (is_read) begin
      rd_valid[0] <= 1'b1;
      rd_data[0]  <= mem[word_index];
    end else begin
      rd_valid[0] <= 1'b0;
      rd_data[0]  <= 16'h0000;
    end
  end

  // Drive DQ `cl` cycles after the command.  With cl == 2 the word is taken from
  // stage 1, which is the timing this design's capture points were tuned to.
  always @(*) begin
    case (cl)
      3: begin dq_oe = rd_valid[2]; dq_drive = rd_data[2]; end
      default: begin dq_oe = rd_valid[1]; dq_drive = rd_data[1]; end
    endcase
  end

  assign DQ = dq_oe ? dq_drive : 16'hzzzz;


  // ----------------------------------------------------------------- control
  always @(posedge CLK) begin
    if (is_act)  row_lat[BA] <= A;
    if (is_mrs)  cl <= A[6:4];      // mode register: CL in A[6:4] per JEDEC
    if (is_write && CKE) mem[word_index] <= wr_word;
  end

  // ------------------------------------------------------------ diagnostics
  // Counters, so a bench can prove the controller actually talked to the part
  // rather than silently reading zeros from an untouched array.
  integer n_act = 0, n_read = 0, n_write = 0, n_ref = 0, n_mrs = 0;
  integer n_clk = 0, n_cs_low = 0, n_cke_low = 0;

  integer hist [0:15];
  integer hi;
  initial for (hi = 0; hi < 16; hi = hi + 1) hist[hi] = 0;

  // Arming.  Until the controller runs its configuration sequence, `cmd` is
  // still at its power-on value; under Verilator an uninitialised reg reads as
  // zero, which decodes as a ModeRegisterSet command.  That produced 196,609
  // phantom MRS commands in the first run -- one per fclk edge of the 65535-mclk
  // reset, which is what identified them as an artefact rather than traffic.
  // The first PreCharge of the init sequence is the marker that the controller
  // is alive, so nothing is counted before it.
  reg armed = 1'b0;

  always @(posedge CLK) begin
    if (is_pre) armed <= 1'b1;
    if (armed)
      hist[{nCS, nRAS, nCAS, nWE}] = hist[{nCS, nRAS, nCAS, nWE}] + 1;
    n_clk <= n_clk + 1;
    if (armed && ~nCS) n_cs_low  <= n_cs_low + 1;
    if (~CKE)    n_cke_low <= n_cke_low + 1;
  end

  always @(posedge CLK) begin
    if (armed) begin
      if (is_act)   n_act   <= n_act   + 1;
      if (is_read)  n_read  <= n_read  + 1;
      if (is_write) n_write <= n_write + 1;
      if (is_ref)   n_ref   <= n_ref   + 1;
      if (is_mrs)   n_mrs   <= n_mrs   + 1;
    end
  end

  // A preload port would make the ROM image visible before the machine starts
  // without needing the loader path.  It is driven from the bench by
  // hierarchical reference rather than as a port, so the model's pin list stays
  // identical to the real part.

endmodule
