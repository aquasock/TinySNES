// NES video and sound to HDMI converter
// nand2mario, 2022.9

`timescale 1ns / 1ps

// The probe builds share one display: five stripes of 16 bars plus a status
// band.  Which fields the stripes carry belongs to snestang_top, which is where
// the two probes differ, so this file only needs to know that a probe is
// selected.  Defined here rather than with the other diagnostics because the
// port list above depends on it.
`ifdef TINYSNES_FETCH_PROBE
  `define TINYSNES_PROBE_BARS 1
`endif
`ifdef TINYSNES_CPU_PROBE
  `define TINYSNES_PROBE_BARS 1
`endif
`ifdef TINYSNES_TRACE_PROBE
  `define TINYSNES_PROBE_BARS 1
`endif
`ifdef TINYSNES_LIVE_PROBE
  `define TINYSNES_PROBE_BARS 1
  `define TINYSNES_PROBE_SPLIT 1
`endif
`ifdef TINYSNES_APU_PROBE
  `define TINYSNES_PROBE_BARS 1
`endif
`ifdef TINYSNES_IPL_PROBE
  `define TINYSNES_PROBE_BARS 1
`endif
`ifdef TINYSNES_LINK_PROBE
  `define TINYSNES_PROBE_BARS 1
`endif
`ifdef TINYSNES_WHERE_PROBE
  `define TINYSNES_PROBE_BARS 1
`endif
`ifdef TINYSNES_JUMP_PROBE
  `define TINYSNES_PROBE_BARS 1
`endif
`ifdef TINYSNES_STACK_PROBE
  `define TINYSNES_PROBE_BARS 1
`endif
`ifdef TINYSNES_STACKBYTES_PROBE
  `define TINYSNES_PROBE_BARS 1
`endif
`ifdef TINYSNES_INSN_PROBE
  `define TINYSNES_PROBE_BARS 1
`endif
`ifdef TINYSNES_IRQ_PROBE
  `define TINYSNES_PROBE_BARS 1
`endif
`ifdef TINYSNES_WAIT_PROBE
  `define TINYSNES_PROBE_BARS 1
`endif
`ifdef TINYSNES_PIXEL_PROBE
  `define TINYSNES_PROBE_BARS 1
`endif
`ifdef TINYSNES_SELFTEST_PROBE
  `define TINYSNES_PROBE_BARS 1
`endif
`ifdef TINYSNES_TIMING_PROBE
  `define TINYSNES_PROBE_BARS 1
`endif
`ifdef TINYSNES_LINEFILL_PROBE
  `define TINYSNES_PROBE_BARS 1
`endif
`ifdef TINYSNES_GSU_PROBE
  `define TINYSNES_PROBE_BARS 1
`endif

// The two memory self-tests share one display, so they are folded into a single
// define rather than tested in one `elsif` expression.  `elsif A || B does NOT
// work here: with only B defined, slang resolves the whole expression false, so
// a build defining the second macro alone silently drew the production picture
// instead of the test result.  The nested form above for TINYSNES_PROBE_BARS is
// the shape that does work.
`ifdef TINYSNES_SDRAM_TEST
  `define TINYSNES_BIST_BARS 1
`endif
`ifdef TINYSNES_ARAM_TEST
  `define TINYSNES_BIST_BARS 1
`endif
`ifdef TINYSNES_READ_STABILITY
  `define TINYSNES_BIST_BARS 1
`endif
`ifdef TINYSNES_WRAM_TEST
  `define TINYSNES_BIST_BARS 1
`endif

// Any build that draws a display of its own in place of the picture must not
// have the boot screen in front of it.  The memory self-tests are why this is
// not merely tidy: they run at power-up with no cartridge loaded, which is
// exactly the condition the boot screen covers, so an ungated boot screen would
// hide the result the test exists to show.  Written as the nested form for the
// reason recorded above -- `elsif A || B` resolves false when only B is defined.
`ifdef TINYSNES_PROBE_BARS
  `define TINYSNES_DIAG_DISPLAY 1
`endif
`ifdef TINYSNES_BIST_BARS
  `define TINYSNES_DIAG_DISPLAY 1
`endif
`ifdef TINYSNES_PROBE_SPLIT
  `define TINYSNES_DIAG_DISPLAY 1
`endif
`ifdef TINYSNES_OVERLAY_ONLY
  `define TINYSNES_DIAG_DISPLAY 1
`endif
`ifdef TINYSNES_TEST_PATTERN
  `define TINYSNES_DIAG_DISPLAY 1
`endif
`ifdef TINYSNES_LOAD_COUNT
  `define TINYSNES_DIAG_DISPLAY 1
`endif
`ifdef TINYSNES_ROM_CHECK
  `define TINYSNES_DIAG_DISPLAY 1
`endif
`ifdef TINYSNES_LIVE_TESTPATTERN
  `define TINYSNES_DIAG_DISPLAY 1
`endif
`ifdef TINYSNES_SOLID_WHITE
  `define TINYSNES_DIAG_DISPLAY 1
`endif

module snes2hdmi (
	input clk,      // snes clock
	input resetn,

    // snes video and audio signals
    input dotclk,
    input hblank,
    input vblank,
    input [14:0] rgb5,
    input [8:0] xs, // {x,dotclk}
    input [8:0] ys, // {field,y}

    // The picture's shape, from the desktop window's Video page (iosys frame
    // 0x1B).  `aspect` picks how wide the 256-pixel line is drawn and
    // `show_overscan` whether the PPU's extra fifteen lines are shown when a
    // game asks for them; `v224` says whether it did.
    //
    // Aspect is a real choice on this console rather than a palette question:
    // the pixels are digital BGR555 with one correct rendering, but their
    // shape is not fixed.  The three settings are the ones every emulator
    // offers, and the widths come from the 224-line picture scaled to 720:
    //   4:3  960 px, the SNES's own display aspect
    //   8:7  940 px, the pixel aspect ratio the hardware documents
    //   1:1  823 px, square pixels
    input [1:0] aspect,
    input       show_overscan,
    input       v224,

    input overlay,
    output [7:0] overlay_x,
    output [7:0] overlay_y,
    input [14:0] overlay_color,

    // TinyDesk, from iosys_bl616 on the machine clock; see desk_layer.v.
    input desk_on,
    input desk_wr_tog,
    input [11:0] desk_wr_addr,
    input [36:0] desk_wr_data,

    input [15:0] audio_l,
    input [15:0] audio_r,
    input audio_ready,
    output audio_en,

    // Audio FIFO health for the debug register bank.  A write offered to a full
    // FIFO and a read taken from an empty one are each reduced to a toggle, so
    // the underrun -- which happens on the pixel clock -- can cross into the
    // bank's mclk domain as one bit rather than a counter.
    output        audio_ovf_tog,
    output        audio_unf_tog,

    // frame-sync pause happens during snes_refresh
    input snes_refresh,

    // No cartridge image in the SDRAM yet.  Comes from the top level's `loaded`
    // on the machine clock and is synchronised into this unit's pixel clock, so
    // a machine with no cartridge shows the boot screen instead of the picture.
    input rom_loaded,

	// video clocks
	input clk_pixel,
	input clk_5x_pixel,
	input locked,

    output reg pause_snes_for_frame_sync,

    // TinySNES diagnostic: three machine-state bits shown as the border colour,
    // because the OSD text page is blank on this core and there is no other way
    // to see inside the machine from the bench.  Bit order: R = header_finished,
    // G = loaded, B = loading.
    input [2:0] dbg,

    // TinySNES diagnostic: per-DQ-bit result of sdram_bist, drawn as 16 bars
    // across the active area in the TINYSNES_SDRAM_TEST build.  Unused (and
    // tied off) in every other build.
    input [15:0] bist_mask,

`ifdef TINYSNES_PROBE_BARS
    // TinySNES diagnostic: five 16-bit fields of machine state, drawn as one
    // stripe each.  Present only under a probe define so the shipped core
    // carries no extra port.  The field order is set by the probe in
    // snestang_top.v and repeated in its comment:
    //   TINYSNES_FETCH_PROBE: ROM_Q at the first ROMSEL assertion, at +2 mclk,
    //     at +4 mclk, then ROM_ADDR[15:0] and ROM_ADDR[23:8] for that access
    //   TINYSNES_CPU_PROBE:   ROM access counter low and high halves, then PC at
    //     the most recent sample, SP, and the CPU's status byte from DBG_REG
    //     0x15 (7 GotInterrupt, 6 IsResetInterrupt, 5 IsNMIInterrupt,
    //     4 IsIRQInterrupt, 3 RDY_IN, 2 EN, 1 WAIExec, 0 STPExec)
    //   TINYSNES_TRACE_PROBE: the last four ROM addresses, newest first, then
    //     ROM_ADDR[23:8] of the newest
    //   TINYSNES_APU_PROBE:   CPUO ports 1 and 0, the 65816's A, the 65816's
    //     PC, the SPC700's PC, then the 65816's P above CPUI port 0
    //   TINYSNES_IPL_PROBE:   the SPC700 PC at the first sample outside the IPL
    //     ROM, then its live Y and A, the current SPC700 PC, CPUI ports 3 and 2,
    //     and CPUI ports 1 and 0
    //   TINYSNES_IRQ_PROBE:   the sticky interrupt bits, the core's status
    //     byte, the halt PC and then zeros
    //   TINYSNES_LINK_PROBE:  both directions of the APU link and both CPUs --
    //     CPUO ports 1 and 0, CPUI ports 1 and 0, the 65816's A and its PC, then
    //     the SPC700's Y, and in the top stripe a 3-bit count of sightings at
    //     $8888 above five bits: [4] the 65816 has been past the first handshake,
    //     [3] CPUI port 0 has ever held $CC, [2] CPUO has ever left $AA,
    //     [1] Y has ever been non-zero, [0] the SPC700's PC has ever been
    //     outside its IPL ROM
    //   TINYSNES_WHERE_PROBE: the 65816's PC, its PBR, its SP and its P, then a
    //     sticky byte ([0] STP has fired, [1] WAI has fired, [2] armed at a PC
    //     of $8000 or above, [3] the CPU has left the cartridge at a PC below
    //     $8000, [4] PBR has ever been non-zero, [5] RDY_IN has ever read low,
    //     [7:6] zero), then the first PC below $8000 seen while armed above the
    //     newest ROM address the mapper served
    //   TINYSNES_JUMP_PROBE: the PC the CPU departed to, the ROM bank and the
    //     newest ROM address fetched before it left, the two fetches before
    //     that, and the 65816's PBR at the departure
    //   TINYSNES_STACK_PROBE: the PC the CPU departed to, its SP at that moment,
    //     then the last three writes to the stack page newest first as address
    //     above data, and a count of stack-page writes in the top stripe
    //   TINYSNES_STACKBYTES_PROBE: the departure PC, the SP at that sample, then
    //     the last byte written to each of $01FA, $01FB, $01FC and $01FD, a byte
    //     of valid bits for those four, the PBR, and a count of stack-page writes
    //   TINYSNES_INSN_PROBE: the departure PC, the SP beside it, the CPU's
    //     call/return flag byte (bit 0 JSR, 1 JSL, 2 RTL, 3 RTS, 4 an RTL with
    //     no outstanding JSL), the outstanding long-call balance, the PBR at the
    //     departure, and the newest ROM address
    input [79:0] probe_bus,
`ifdef TINYSNES_LINEFILL_PROBE
    output [79:0] linefill_bus,     // write-side counts, driven below
    output [2:0]  linefill_dbg,
`endif
`endif

`ifdef TINYSNES_RGB_TAP
    // Simulation tap: the colour this module decided for the pixel at (tap_x,
    // tap_y), and whether that position is inside the visible area.  Added so a
    // bench can reconstruct exactly what the board would show, through the real
    // line buffer rather than through a model of it.
    output [23:0] tap_rgb,
    output        tap_de,
    output [7:0]  tap_x,
    output [7:0]  tap_y,
    output        tap_active,
    output        tap_we,
    output [12:0] tap_waddr,
`endif

    // output [7:0] led,

	// output signals
	output       tmds_clk_n,
	output       tmds_clk_p,
	output [2:0] tmds_d_n,
	output [2:0] tmds_d_p
);

    localparam FRAMEWIDTH = 1280;       // 720P
    localparam FRAMEHEIGHT = 720;
    localparam TOTALWIDTH = 1650;
    localparam TOTALHEIGHT = 750;
    localparam SCALE = 5;
    localparam VIDEOID = 4;
    localparam VIDEO_REFRESH = 60.0;

    localparam IDIV_SEL_X5 = 3;
    localparam FBDIV_SEL_X5 = 54;
    localparam ODIV_SEL_X5 = 2;
    localparam DUTYDA_SEL_X5 = "1000";
    localparam DYN_SDIV_SEL_X5 = 2;
    
    localparam CLKFRQ = 74250;

    // The geometry used to be three localparams chosen for 4:3 at 224 lines.
    // It is now a function of the two settings above: the width from the
    // aspect, and the height from whether the frame is 224 or 239 lines and
    // whether the operator wants the extra ones shown.
    reg [10:0] disp_w;                  // output pixels the 256-wide line fills
    reg [8:0]  disp_h;                  // source lines this frame carries
    reg [10:0] xstart, xstop;

    always @* begin
        case (aspect)
            2'd1:    disp_w = 11'd940;  // 8:7
            2'd2:    disp_w = 11'd823;  // 1:1
            default: disp_w = 11'd960;  // 4:3
        endcase
        // A 224-line game has no extra lines to show; a 239-line one has them
        // cropped unless the operator asked for them.
        disp_h = (v224 || !show_overscan) ? 9'd224 : 9'd239;
        xstart = (11'd1280 - disp_w) >> 1;
        xstop  = xstart + disp_w;
    end

    localparam AUDIO_BIT_WIDTH = 16;

    // video stuff
    wire [9:0] cy, frameHeight;
    wire [10:0] cx, frameWidth;
    reg active, r_active;
    wire [7:0] x, y;                    // SNES pixel position

    //
    // BRAM line buffer for 16 lines. Each pixel is 5:5:5 RGB
    // Each BRAM block holds 4 lines. So 16 lines needs 4 blocks.
    //
    localparam BUF_WIDTH = 5;        // 2 ^ BUF_WIDTH lines
    localparam BUF_SIZE = 1 << BUF_WIDTH;
    reg [14:0] mem [0:BUF_SIZE*256-1];
    reg [BUF_WIDTH+8-1:0] mem_portA_addr;
    reg [14:0] mem_portA_wdata;
    reg mem_portA_we;
    wire [BUF_WIDTH+8-1:0] mem_portB_addr;
    reg [14:0] mem_portB_rdata;
    reg mem_writeto = 1'b0;     // current line we are writing to. we read from the other line
   
    // We need to do a bit of synchronization as the SNES and HDMI run on separate clocks and they
    // do not align perfectly.
    // - Let SNES execute a bit faster (0.5%) than the HDMI stack. This way we always have enough pixels.
    // - For each frame, we let the SNES run until the first line is rendered, and written to line buffer.
    //   Then we pause the SNES and wait (through pause_snes_for_frame_sync) for HDMI to catch up.
    // - Once HDMI started the frame, start SNES again.
    reg sync_done = 1'b0;
    reg hdmi_first_line;
    reg pause_sync;     // pause for even number of cycles for PPU sdram access to stay in sync
    reg hdmi_first_line_r, hdmi_first_line_rr;
    always @(posedge clk) begin
        hdmi_first_line_r <= hdmi_first_line;
        hdmi_first_line_rr <= hdmi_first_line_r;
        if (pause_snes_for_frame_sync) pause_sync <= ~pause_sync;
        if (~sync_done) begin
            if (~pause_snes_for_frame_sync) begin
                if (ys[7:0] == 8'd1 && snes_refresh) begin      // halt SNES after first line is buffered
                    pause_snes_for_frame_sync <= 1'b1;
                    pause_sync <= 0;
                end
            end else if (hdmi_first_line_rr && pause_sync) begin                 // HDMI frame start, now resume SNES
                pause_snes_for_frame_sync <= 1'b0;
                sync_done <= 1'b1;
            end
        end else
            pause_snes_for_frame_sync <= 1'b0;
        if (ys[7:0] == 8'd200) sync_done <= 1'b0;               // reset sync_done for next frame
    end
    always @(posedge clk_pixel) begin
        if (cy == 0 && cx >= 11'd160)      
            hdmi_first_line <= 1;
        else
            hdmi_first_line <= 0;
    end

    // BRAM port A read/write
	always_ff @(posedge clk) begin
		if (mem_portA_we) begin
			mem[mem_portA_addr] <= mem_portA_wdata;
		end
	end

    // BRAM port B read
    always_ff @(posedge clk_pixel) begin
        mem_portB_rdata <= mem[mem_portB_addr];
    end

    integer j;
    initial begin
        // On power-up, fill line buffer with a gradient
        for (j = 0; j < 512; j=j+1) begin
            mem[j][14:10] = j;
            mem[j][9:5] = j;
            mem[j][4:0] = j;
        end
    end

    // 
    // Data input
    //
    reg r_dotclk, r_vblank, r_hblank;
`ifdef TINYSNES_LINEFILL_PROBE
// Diagnostic build: is the line buffer being written?
//
// Every earlier attempt to answer this from the top level asked about hblankn and
// vblankn, which are the PPU's HDE and VDE after two inversions and a port rename.
// A hardware probe that counted `hblankn === 1'b1` and `hblankn === 1'b0` came back
// zero for both, which is not a measurement: synthesis of a four-state comparison
// against a constant folds both branches to false and increments a third counter
// that was never displayed.  Simulation then showed HDE and VDE are healthy -- 2942
// HDE edges, 12 VDE edges, both high 64.6 percent of the time, no X -- so the
// signals were never the problem and the probe was.
//
// So this measures the write itself, inside the module that owns it, with no
// polarity argument in the way: every assertion of mem_portA_we is a pixel going
// into the buffer.
//
//   [15:0]  mem_portA_we assertions in the window
//   [31:16] cycles with hblank low  (HDE asserted)
//   [47:32] cycles with vblank low  (VDE asserted)
//   [63:48] the whole condition without the hblank term
//   [79:64] {mem_portA_we, dotclk, vblank, hblank, mem_portB_rdata[2:0], 9'b0}
//
// If mem_portA_we is zero while dotclk, hde and vde all count, the fault is in the
// write condition and the numbers say which term; if it is non-zero the buffer is
// being filled and the fault is in the read side or the HDMI path.
reg [15:0] lf_we    = 16'd0;
reg [15:0] lf_dot   = 16'd0;
reg [15:0] lf_hb    = 16'd0;
reg [15:0] lf_and   = 16'd0;
reg [15:0] lf_vb    = 16'd0;
reg [15:0] lf_ys    = 16'd0;
reg [13:0] lf_win   = 14'd0;
reg [79:0] lf_bus   = 80'd0;
reg  [2:0] lf_dbg   = 3'b000;

always @(posedge clk) begin
    if (~resetn) begin
        lf_we <= 16'd0; lf_dot <= 16'd0; lf_hb <= 16'd0; lf_vb <= 16'd0;
        lf_and <= 16'd0;
    end else begin
        // The write condition is counted term by term and then whole, so a zero
        // can be attributed instead of guessed at.  `lf_and` is the condition
        // with the hblank term omitted: if it is large while `lf_we` is zero, the
        // hblank term is the only thing stopping writes; if `lf_and` is itself
        // small, the terms that do not involve hblank are the problem.
        if (mem_portA_we)  lf_we   <= lf_we   + 16'd1;
        if (dotclk && ~r_dotclk) lf_dot <= lf_dot + 16'd1;
        if (~hblank) lf_hb <= lf_hb + 16'd1;
        if (~vblank) lf_vb <= lf_vb + 16'd1;
        if (dotclk && ~r_dotclk && ~vblank && ys[7:0] < 8'd224)
            lf_and <= lf_and + 16'd1;

        lf_win <= lf_win + 14'd1;
        if (lf_win == 14'd0) begin
            lf_bus <= {mem_portA_we, dotclk, vblank, hblank,
                       mem_portB_rdata[2:0], 9'b0,
                       lf_and, lf_vb, lf_hb, lf_we};
            lf_we <= 16'd0; lf_dot <= 16'd0; lf_hb <= 16'd0; lf_vb <= 16'd0;
            lf_and <= 16'd0;
        end
    end
end

always @(*) lf_dbg = {mem_portA_we, ~vblank, ~hblank};
assign linefill_bus = lf_bus;
assign linefill_dbg = lf_dbg;
`endif

`ifdef TINYSNES_BUF_ADDRTEST
// Diagnostic build: write the buffer unconditionally, but address it with the
// PPU's own coordinates.
//
// BUF_PATTERN proves the memory and both its ports work: writing a counter into
// every address fills the screen with colour bands, 693,505 pixels different from
// the grid.  What it does not test is whether the PPU's xs and ys -- the
// coordinates the shipping write uses for its address -- are any good, because it
// replaces them with a counter.
//
// Here the write enable is unconditional, so synthesis has nothing to prove and
// cannot fold anything, while the address comes from {ys[4:0], xs[8:1]} exactly as
// the shipping path builds it.  The value written is a constant bright colour.
//
// If the screen fills with a solid colour, xs and ys span their whole range and the
// address path is sound, which puts the fault back on the gate.  If only part of
// the screen changes -- a column, or a band -- then xs or ys is not advancing, and
// the picture of a single changed column seen in the counter build is explained.
    always @(posedge clk) begin
        mem_portA_addr  <= {ys[BUF_WIDTH-1:0], xs[8:1]};
        mem_portA_wdata <= 15'h7FFF;
        mem_portA_we    <= 1'b1;
    end
`elsif TINYSNES_BUF_PATTERN
// Diagnostic build: prove the line buffer and its read path on hardware, with no
// dependence on the SNES, the PPU or the write gate.
//
// Every other buffer experiment in this project has been gated on a condition
// derived from the PPU, and `synth_gowin` proves that condition constant and
// deletes the write port.  This one has nothing to prove: port A is written every
// master clock from a free-running counter, address and data both, so the cone
// cannot fold.  Port B and the HDMI path are untouched.
//
// What appears on screen is therefore a property of the memory and the read path
// alone.  Coloured bands that move means the BRAM, its two clock domains and the
// scan-out all work, and the picture fault is entirely in what fills the buffer.
// The same picture as before means the buffer is not the problem and the read
// side is.
    reg [19:0] bp_cnt = 20'd0;
    always @(posedge clk) begin
        bp_cnt <= bp_cnt + 20'd1;
        mem_portA_addr  <= bp_cnt[12:0];
        mem_portA_wdata <= bp_cnt[19:5];
        mem_portA_we    <= 1'b1;
    end
`elsif TINYSNES_LINEFILL_COUNTER
// Diagnostic build: write a free-running counter into the line buffer through the
// same ungated path the RAW build uses, and display the buffer normally.
//
// The RAW build proves the write port survives synthesis and that mem_portA_we
// asserts 4096 times per window -- once per dot clock -- yet the screen it
// produces is still the power-up grid, unchanged across every frame.  Writes that
// happen and a picture that does not move means the read side is not seeing them.
//
// So this build makes the written data impossible to miss: a counter in the top
// bits, a fixed coordinate pattern in the rest.  If the screen shows moving
// blocks, port B reads what port A wrote and only the PPU data path is at fault.
// If the screen stays put, the two ports are not the same memory as far as this
// device is concerned, and that is a placement or BRAM-mode problem rather than
// anything in the SNES core.
    reg [19:0] lb_cnt = 20'd0;
    always @(posedge clk) lb_cnt <= lb_cnt + 20'd1;

    always @(posedge clk) begin
        r_dotclk <= dotclk;
        r_vblank <= vblank;
        mem_portA_we <= 1'b0;
        if (dotclk && ~r_dotclk && ys[7:0] < 8'd224) begin
            mem_portA_addr  <= {ys[BUF_WIDTH-1:0], xs[8:1]};
            mem_portA_wdata <= {lb_cnt[19:15], xs[8:4], ys[4:0]};
            mem_portA_we    <= 1'b1;
        end
    end
`elsif TINYSNES_LINEFILL_RAW
// Diagnostic build: write every SNES pixel into the line buffer, with no display
// gating at all.
//
// This is the end of a chain of narrowing.  The write gate is
// `dotclk rising && ~hblank && ~vblank && ys < 224`, and synthesis proves that
// conjunction constant, deletes the memory's write port, and leaves the buffer
// holding whatever it powered up with.  Removing only the `~hblank` term lifts
// the fold and the hardware then writes 120 to 128 pixels per window, which is
// too few to fill a 57,344-pixel frame but proves the buffer, its port A and its
// two clock domains all work.
//
// So this build removes the remaining gating as well and writes on every dot
// clock edge while the SNES is on a visible line.  It cannot be the shipping
// behaviour -- writing outside the display window would smear the picture -- but
// it answers the one question that has been open since the grid was first
// photographed: can this video path put a picture on the screen at all?
//
// A picture here means everything downstream of the buffer works and only the
// gating terms are at fault.  No picture means the fault is in the read side,
// the HDMI serialiser or the panel, and no amount of gate arithmetic will help.
    always @(posedge clk) begin
        r_dotclk <= dotclk;
        r_vblank <= vblank;
        mem_portA_we <= 1'b0;
        if (dotclk && ~r_dotclk && ys[7:0] < 8'd224) begin
            mem_portA_addr  <= {ys[BUF_WIDTH-1:0], xs[8:1]};
            mem_portA_wdata <= rgb5;
            mem_portA_we    <= 1'b1;
        end
    end
`elsif TINYSNES_LINEFILL_NO_HDE
// Diagnostic build: write the line buffer without the horizontal-enable term.
//
// Measured on the board: mem_portA_we never asserts, while dotclk runs, ys is in
// the visible range 86 percent of the time, and VDE asserts -- but HDE never
// does, so the write condition `dotclk rising && ~hblank && ~vblank && ys < 224`
// can never be met and the picture stays whatever the buffer powered up with.
// Simulation says HDE asserts once per scanline, so the disagreement is between
// the RTL and what the board does with it, and this build answers the question
// that matters more than why: if HDE is the only thing standing between the
// machine and a picture, then dropping it here should draw one.
//
// It is not a fix.  HDE exists to mark the horizontal display period, and writing
// the buffer outside it would smear the picture sideways.  It is an isolation
// experiment: a picture here says every other part of the video path works and
// the HDE term is the sole blocker, which makes the next question sharp.
    always @(posedge clk) begin
        r_dotclk <= dotclk;
        r_vblank <= vblank;
        mem_portA_we <= 1'b0;
        if (dotclk && ~r_dotclk && ~vblank && ys[7:0] < 224) begin
            mem_portA_addr  <= {ys[BUF_WIDTH-1:0], xs[8:1]};
            mem_portA_wdata <= rgb5;
            mem_portA_we    <= 1'b1;
        end
    end
`elsif TINYSNES_LINEBUF_TEST
    // Diagnostic build: write the line buffer from a free-running counter rather
    // than from the PPU, so the buffer, its two clock domains (port A on mclk,
    // port B on the pixel clock) and the read path are exercised with no
    // dependence on the CPU, the PPU, the cartridge or SDRAM.
    //
    // This exists because the picture this project has been staring at for two
    // days may not be the PPU's picture at all.  Core-log entry 40 concluded the
    // static grid is uninitialised line-buffer content rather than PPU output,
    // and nothing has ever tested that claim: every probe build draws its bars
    // by assigning rgb directly and so bypasses the buffer entirely.  If this
    // build shows a moving 16x16 field of colour cells, the buffer and the read
    // path work and the fault is upstream of them.  If it still shows the grid,
    // the buffer is where the picture dies and no CPU work could ever have been
    // visible.
    //
    //   red   = a slow free-running counter, so the field shifts over time
    //   green = xs[8:4], 16 vertical bands
    //   blue  = ys[4:0], 16 horizontal bands
    reg [19:0] lb_cnt = 20'd0;
    always @(posedge clk) lb_cnt <= lb_cnt + 20'd1;

    always @(posedge clk) begin
        r_dotclk <= dotclk;
        r_vblank <= vblank;
        mem_portA_we <= 1'b0;
        if (dotclk && ~r_dotclk && ~hblank && ~vblank && ys[7:0] < 224) begin
            mem_portA_addr  <= {ys[BUF_WIDTH-1:0], xs[8:1]};
            mem_portA_wdata <= {lb_cnt[19:15], xs[8:4], ys[4:0]};
            mem_portA_we    <= 1'b1;
        end
    end
`else
    always @(posedge clk) begin
        r_dotclk <= dotclk;
        r_vblank <= vblank;
        mem_portA_we <= 1'b0;
        if (dotclk && ~r_dotclk && ~hblank && ~vblank && ys[7:0] < disp_h[7:0]) begin   // on posedge of dotclk, read a pixel
            mem_portA_addr <= {ys[BUF_WIDTH-1:0], xs[8:1]};
            mem_portA_wdata <= rgb5;
            mem_portA_we <= 1'b1;
        end
    end
`endif

    always @(posedge clk) begin
        r_hblank <= hblank;
        if (hblank & ~r_hblank) begin       // flip active line on hblank
            mem_writeto <= ~mem_writeto;
        end
    end
    

    // HDMI TX audio, nominally 32 kHz, with clk_audio servoed to the S-DSP's
    // real rate (see hdmi_audio_clock.v).
    localparam AUDIO_OUT_RATE = 32000;              // header value only
    reg [15:0] audio_sample_word [1:0];
    wire [15:0] audio_word_l, audio_word_r;
    wire clk_audio;
    wire audio_rinc;
    wire audio_full, audio_empty;
    wire [31:0] audio_sample;
    wire [4:0] audio_level;

    hdmi_audio_clock #(.CLK_HZ(CLKFRQ * 1000)) audio_clock (
        .clk(clk_pixel), .resetn(resetn),
        .level(audio_level), .empty(audio_empty), .sample(audio_sample),
        .clk_audio(clk_audio), .rinc(audio_rinc),
        .word_l(audio_word_l), .word_r(audio_word_r)
    );

    always @* begin
        audio_sample_word[0] = audio_word_l;
        audio_sample_word[1] = audio_word_r;
    end

    // Audio sample FIFO for 16 samples
    dual_clk_fifo #(.DATESIZE(32), .ADDRSIZE(4)) audio_fifo (
        .clk(clk), .wrst_n(1'b1), 
        .winc(audio_ready), .wdata({audio_l, audio_r}), .wfull(audio_full),
        .rclk(clk_pixel), .rrst_n(1'b1),
        .rinc(audio_rinc), .rdata(audio_sample), .rempty(audio_empty),
        .almost_full(), .almost_empty(), .rlevel(audio_level)
    );

    // The two ways this path can lose a sample, each as a toggle that the debug
    // bank counts.  Overflow is a write the FIFO refused; underrun is a read
    // that found nothing, which the clock regenerator repeats as a held sample.
    // With the audio servo locked neither should ever move.
    reg audio_ovf_tog_r = 1'b0;
    reg audio_unf_tog_r = 1'b0;
    assign audio_ovf_tog = audio_ovf_tog_r;
    assign audio_unf_tog = audio_unf_tog_r;

    always @(posedge clk)
        if (resetn && audio_ready && audio_full)
            audio_ovf_tog_r <= ~audio_ovf_tog_r;

    always @(posedge clk_pixel)
        if (resetn && audio_rinc && audio_empty)
            audio_unf_tog_r <= ~audio_unf_tog_r;

    //
    // Video
    //
    reg [23:0] rgb;             // actual RGB output
    // TinySNES: `active` is declared once, above, at line 68.  Gowin's
    // synthesiser tolerated the second declaration; slang rejects it.
    reg [7:0] xx;               // scaled-down pixel position
    reg [7:0] yy;
    reg [10:0] xcnt;
    reg [10:0] ycnt;            // fractional scaling counters
    reg [9:0] cy_r;
    assign mem_portB_addr = {yy[BUF_WIDTH-1:0], xx};
    assign overlay_x = xx;
    assign overlay_y = yy;

    // address calculation
    // Assume the video occupies fully on the Y direction, we are upscaling the video by `720/height`.
    // xcnt and ycnt are fractional scaling counters.
    always @(posedge clk_pixel) begin
        reg active_t;
        reg [10:0] xcnt_next;
        reg [10:0] ycnt_next;
        xcnt_next = xcnt + 256;
        ycnt_next = ycnt + disp_h;

        active_t = 0;
        if (cx == xstart - 1) begin
            active_t = 1;
            active <= 1;
        end else if (cx == xstop - 1) begin
            active_t = 0;
            active <= 0;
        end

        if (active_t | active) begin        // increment xx
            xcnt <= xcnt_next;
            if (xcnt_next >= disp_w) begin
                xcnt <= xcnt_next - disp_w;
                xx <= xx + 1;
            end
        end

        cy_r <= cy;
        if (cy[0] != cy_r[0]) begin         // increment yy at new lines
            ycnt <= ycnt_next;
            if (ycnt_next >= 720) begin
                ycnt <= ycnt_next - 720;
                yy <= yy + 1;
            end
        end

        if (cx == 0) begin
            xx <= 0;
            xcnt <= 0;
        end
        
        if (cy == 0) begin
            yy <= 0;
            ycnt <= 0;
        end 

    end

`ifdef TINYSNES_PROBE_BARS
    // Pick the stripe this row belongs to.  yy[7:5] selects a 32-row block and
    // the bottom 8 rows of each block are the gap, so every stripe is 24 rows
    // of bars.  Five blocks are used; block 5 is left black and block 6 is the
    // status band.
    reg [15:0] fp_stripe;
    always @(*) begin
        case (yy[7:5])
            3'd0: fp_stripe = probe_bus[15:0];
            3'd1: fp_stripe = probe_bus[31:16];
            3'd2: fp_stripe = probe_bus[47:32];
            3'd3: fp_stripe = probe_bus[63:48];
            3'd4: fp_stripe = probe_bus[79:64];
            default: fp_stripe = 16'd0;
        endcase
    end
`endif

`ifdef TINYSNES_PROBE_SPLIT
    // The split build draws over the machine's own picture instead of replacing
    // it, so the two stripes it shows are selected here: the top 32 rows carry
    // probe_bus[15:0] and the next 32 rows probe_bus[47:32].
    wire [15:0] live_stripe = yy[5] ? probe_bus[47:32] : probe_bus[15:0];
`endif

`ifdef TINYSNES_LIVE_TESTPATTERN
    // Free-running pixel counter for the display-path test.  Declared at module
    // level because Verilog does not allow an always block inside another one,
    // which is what the first version of this diagnostic did.
    reg [23:0] ltp_cnt = 24'd0;
    always @(posedge clk_pixel) ltp_cnt <= ltp_cnt + 24'd1;
`endif

`ifndef TINYSNES_DIAG_DISPLAY
    // ------------------------------------------------------------ boot screen
    //
    // With no cartridge image in the SDRAM there is nothing to show, and the
    // line buffer still holds the ramp its `initial` block fills it with, so the
    // screen shows a fixed tile pattern instead of a boot screen.  TinyNES and
    // TinyGBC draw eight equal vertical colour bars in exactly this state -- see
    // `fpga/ae350_soc/video.sv` in either tree, where the output colour is
    // `!en3 ? bars : picture` -- so this core draws the same thing, with the same
    // bar order and the same levels.
    //
    // Two deliberate differences from the siblings.  The bars span the whole
    // 1280-column active raster rather than only this core's 4:3 picture area,
    // so the boot screen has no grey pillarbox around it.  And the active-area
    // test is explicit here, because `cx` counts the whole 1650-column raster
    // (the hdmi module's frame_width is the total, not the visible part), so
    // without it the bars would run on into horizontal blanking.
    //
    // Order, as in both siblings: white, yellow, cyan, green, magenta, red,
    // blue, black.  On is 0xC0 and off is 0x10, again as there.
    localparam integer BOOT_BAR_W = FRAMEWIDTH / 8;

    // `loaded` is produced on the machine clock, so it enters this domain
    // through two flops.  It changes once per cartridge load, so the two clocks
    // of latency cost nothing, and without them the bit that swaps the whole
    // screen is the one bit sampled by a 74.25 MHz flop from an unrelated
    // domain.
    reg [1:0] rom_loaded_sync = 2'b00;
    always @(posedge clk_pixel) rom_loaded_sync <= {rom_loaded_sync[0], rom_loaded};
    wire boot_screen = ~rom_loaded_sync[1];

    wire [2:0] boot_bar = cx < BOOT_BAR_W     ? 3'd0 :
                          cx < BOOT_BAR_W * 2 ? 3'd1 :
                          cx < BOOT_BAR_W * 3 ? 3'd2 :
                          cx < BOOT_BAR_W * 4 ? 3'd3 :
                          cx < BOOT_BAR_W * 5 ? 3'd4 :
                          cx < BOOT_BAR_W * 6 ? 3'd5 :
                          cx < BOOT_BAR_W * 7 ? 3'd6 : 3'd7;
    wire boot_r = boot_bar == 3'd0 || boot_bar == 3'd1 ||
                  boot_bar == 3'd4 || boot_bar == 3'd5;
    wire boot_g = boot_bar == 3'd0 || boot_bar == 3'd1 ||
                  boot_bar == 3'd2 || boot_bar == 3'd3;
    wire boot_b = boot_bar == 3'd0 || boot_bar == 3'd2 ||
                  boot_bar == 3'd4 || boot_bar == 3'd6;
    wire [23:0] boot_rgb = {boot_r ? 8'hC0 : 8'h10,
                            boot_g ? 8'hC0 : 8'h10,
                            boot_b ? 8'hC0 : 8'h10};
    wire boot_visible = boot_screen && cx < FRAMEWIDTH && cy < FRAMEHEIGHT;
`endif

    // TinyDesk over the whole frame, ahead of the boot screen and the picture.
    wire desk_px;
    wire [23:0] desk_rgb;
    desk_layer desk (
        .clk(clk_pixel), .cx(cx), .cy(cy),
        .on(desk_on), .wr_tog(desk_wr_tog), .wr_addr(desk_wr_addr), .wr_data(desk_wr_data),
        .px(desk_px), .rgb(desk_rgb)
    );

    // calc rgb value to hdmi
    always @(posedge clk_pixel) begin
        if (desk_px) begin
            rgb <= desk_rgb;
        end else
`ifndef TINYSNES_DIAG_DISPLAY
        if (boot_visible) begin
            rgb <= boot_rgb;
        end else
`endif
        if (active) begin
`ifdef TINYSNES_PROBE_SPLIT
            // Diagnostic build: the machine's picture with the probe laid over
            // its top 64 rows, so one screenshot shows both what the CPU is
            // doing and what the PPU is drawing.  Bars are 16 pixels wide with
            // a 2-pixel gap, green = 1 and red = 0, and both fields are latched
            // every 0.2 s by the sampler so they can be photographed.
            if (yy < 8'd64)
                rgb <= (xx[3:0] > 4'd13) ? 24'h000000
                                         : (live_stripe[xx[7:4]] ? 24'h00C000 : 24'hC00000);
            else if (overlay)
                rgb <= {overlay_color[4:0],3'b0,overlay_color[9:5],3'b0,overlay_color[14:10],3'b0};
            else
                rgb <= {mem_portB_rdata[4:0], 3'b0, mem_portB_rdata[9:5], 3'b0, mem_portB_rdata[14:10], 3'b0};
`elsif TINYSNES_OVERLAY_ONLY
            // Diagnostic build: the overlay path only, no line-buffer BRAM read,
            // so the picture proves the raster and the overlay meter without
            // involving the SNES-side clock domain.
            rgb <= overlay ? {overlay_color[4:0],3'b0,overlay_color[9:5],3'b0,overlay_color[14:10],3'b0}
                           : 24'h101010;
`elsif TINYSNES_TEST_PATTERN
            // Diagnostic build: fixed vertical colour bars every 16 pixels, so a
            // picture proves the HDMI plumbing (PLL, OSER10s, ELVDS, packets)
            // independently of the SNES machine and the overlay.  Never in a
            // core meant to play a game.
            rgb <= {xx[7:5]==3'd0 ? 8'hFF : 8'h00,
                    xx[7:5]==3'd1 ? 8'hFF : (xx[7:5]==3'd3 ? 8'hC0 : 8'h00),
                    xx[7:5]==3'd2 ? 8'hFF : 8'h00};
`elsif TINYSNES_BIST_BARS
            // Diagnostic build: one bar per SDRAM data bit, 16 pixels apart with a
            // 2-pixel black gap between bars so a run of same-coloured bars can
            // never read as one block.  bist_mask is a MISMATCH mask, so a set bit
            // is drawn red (that bit was wrong at least once) and a clear bit
            // green (it read back correctly at every test address).  The bottom
            // 32 rows are a solid status band in the dbg colour.  Under
            // TINYSNES_ARAM_TEST the same 16 bits are the two byte lanes of the
            // ARAM port, bits 0-7 even and 8-15 odd, which is why one display
            // serves both tests.
            if (yy[7:5] == 3'd6)
                rgb <= {dbg[2] ? 8'hC0 : 8'h00, dbg[1] ? 8'hC0 : 8'h00, dbg[0] ? 8'hC0 : 8'h00};
            else if (xx[3:0] > 4'd13)
                rgb <= 24'h000000;
            else
                rgb <= bist_mask[xx[7:4]] ? 24'hC00000 : 24'h00C000;
`elsif TINYSNES_PROBE_BARS
            // Diagnostic build: five stripes of 16 bars, left to right = bit
            // 0..15, green = 1 and red = 0, 16 pixels per bar with a 2-pixel
            // gap.  What each stripe is belongs to the probe build: under
            // TINYSNES_FETCH_PROBE the top three are ROM_Q at the first ROMSEL
            // assertion and two and four mclk later, so three identical red
            // stripes mean the sample is stale at every point while red, red,
            // correct means the data only arrives late; the last two are the
            // mapper's ROM_ADDR halves.  Under TINYSNES_CPU_PROBE they are the
            // ROM access counter and the CPU's program counter, so a counter
            // that stands still and a PC that does not move mean the CPU is not
            // executing.  Under TINYSNES_TRACE_PROBE they are the last four ROM
            // addresses the CPU asked for, newest in the top stripe, and the
            // high half of the newest, so a machine that has left the ROM shows
            // the fetches it made just before that.  The band in rows 192-223 is
            // R = fetch_seen, pc_changed or a recent ROM access depending on the
            // probe, G = loaded, B = enable.
            if (yy[7:5] == 3'd6)                        // status band
                rgb <= {dbg[2] ? 8'hC0 : 8'h00, dbg[1] ? 8'hC0 : 8'h00, dbg[0] ? 8'hC0 : 8'h00};
            else if (yy[7:5] > 3'd4 || yy[4:3] == 2'b11 || xx[3:0] > 4'd13)
                rgb <= 24'h000000;                      // unused rows, stripe gaps, bar gaps
            else
                rgb <= fp_stripe[xx[7:4]] ? 24'h00C000 : 24'hC00000;
`elsif TINYSNES_LOAD_COUNT
            // Diagnostic build: eight thresholds on the loader's SDRAM write
            // count, left to right >=1, >=16, >=256, >=4096, >=32768, >=131072,
            // >=262144, >=500000.  Green = that threshold was reached.
            rgb <= (xx[4:0] > 5'd29) ? 24'h000000
                                     : (bist_mask[xx[7:5]] ? 24'h00C000 : 24'hC00000);
`elsif TINYSNES_ROM_CHECK
            // Diagnostic build: eight fat bars, one per ROM word the probe read
            // back from SDRAM.  Green = that word matched the loaded image,
            // red = it did not.
            rgb <= (xx[4:0] > 5'd29) ? 24'h000000
                                     : (bist_mask[xx[7:5]] ? 24'hC00000 : 24'h00C000);
`else

`ifdef TINYSNES_LIVE_TESTPATTERN
    // Free-running pixel counter for the display-path test, declared outside the
    // pixel always block because Verilog does not allow one always inside another.
`endif
`ifdef TINYSNES_LIVE_TESTPATTERN
// Diagnostic build: does the display path carry a moving image at all?
//
// A build forcing a constant white proved the path from this assignment to the
// HDMI pins works, and a build writing a counter into the line buffer every
// master clock -- with its write port verified present in the netlist -- produced
// no change on screen.  Those two results together say the picture is not coming
// from the line buffer, so this removes the buffer from the question entirely and
// drives the colour from a counter directly.
//
// Moving colour bars here mean the raster, the serialiser and the panel are all
// fine and only the source of the colour is in doubt.  No change means the fault
// is downstream of this assignment after all, and the white build's result was
// about something narrower than it appeared.
    rgb <= {ltp_cnt[23:16], ltp_cnt[15:8], ltp_cnt[7:0]};
`elsif TINYSNES_SOLID_WHITE
    // Diagnostic build: the active area is a constant white, whatever the buffer
    // and the overlay hold.  This settles where the picture is made.  If the
    // screen goes white, everything from this assignment to the HDMI pins works
    // and the grid was data; if the grid survives a constant here, the picture is
    // not being produced by this assignment at all and the fault is downstream.
    rgb <= 24'hFFFFFF;
`else
            if (overlay)
                rgb <= {overlay_color[4:0],3'b0,overlay_color[9:5],3'b0,overlay_color[14:10],3'b0};       // BGR5 to RGB8
            else
                rgb <= {mem_portB_rdata[4:0], 3'b0, mem_portB_rdata[9:5], 3'b0, mem_portB_rdata[14:10], 3'b0};                
`endif
`endif
        end else
`ifdef TINYSNES_DBG_BORDER
            rgb <= {dbg[2] ? 8'hFF : 8'h00, dbg[1] ? 8'hFF : 8'h00, dbg[0] ? 8'hFF : 8'h00};
`else
  `ifdef TINYSNES_DIAG_DISPLAY
            // Diagnostic builds keep the grey pillarbox, and the reason is the
            // instrument rather than the look: `tools/frame_stats.py` reads this
            // colour to prove the transmitter is producing a frame, which is the
            // whole difference between "no signal" and "the PPU is drawing
            // black".  With black bars those two become the same measurement.
            rgb <= 24'h303030;
  `else
            // Production: black outside the 4:3 picture, which is what the
            // sibling cores draw.  TinyNES and TinyGBC end their colour decision
            // with `pic3 ? rgb3 : 24'd0` in fpga/ae350_soc/video.sv, so anything
            // outside the picture area is pure black rather than a grey frame.
            rgb <= 24'h000000;
  `endif
`endif
    end

`ifdef TINYSNES_RGB_TAP
    // The pixel the module decided, exposed for simulation.  `active` is high
    // across the letterboxed picture, and xx/yy are the buffer coordinates, so a
    // bench can drop this straight into a 256x224 image and compare it with what
    // the board shows.
    assign tap_rgb = rgb;
    // xx and yy are eight bits, so they are always inside a 256x224 image; an
    // earlier version compared them against 8'd256 and 8'd224, and 8'd256
    // truncates to zero, which silently made the tap never fire while every
    // stage behind it was working.
    assign tap_de  = active;
    assign tap_x   = xx;
    assign tap_y   = yy;
    assign tap_active = active;
    assign tap_we     = mem_portA_we;
    assign tap_waddr  = mem_portA_addr;
`endif

    // HDMI output.
    logic[2:0] tmds;

    hdmi #( .VIDEO_ID_CODE(VIDEOID), 
            .DVI_OUTPUT(0), 
            .VIDEO_REFRESH_RATE(VIDEO_REFRESH),
            .IT_CONTENT(1),
            .AUDIO_RATE(AUDIO_OUT_RATE), 
            .AUDIO_BIT_WIDTH(AUDIO_BIT_WIDTH),
            .START_X(0),
            .START_Y(0) )

    hdmi( .clk_pixel_x5(clk_5x_pixel), 
          .clk_pixel(clk_pixel), 
          .clk_audio(clk_audio),
          .rgb(rgb), 
          .reset( ~resetn ),
          .audio_sample_word(audio_sample_word),
          .tmds(tmds), 
          .tmds_clock(tmdsClk), 
          .cx(cx), 
          .cy(cy),
          .frame_width( frameWidth ),
          .frame_height( frameHeight ) );

    // Gowin LVDS output buffer
    ELVDS_OBUF tmds_bufds [3:0] (
        .I({clk_pixel, tmds}),
        .O({tmds_clk_p, tmds_d_p}),
        .OB({tmds_clk_n, tmds_d_n})
    );

endmodule
