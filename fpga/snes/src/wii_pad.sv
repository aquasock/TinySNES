// SPDX-License-Identifier: GPL-3.0-only
//
// Wii Classic Controller on an open-drain I2C bus, polled by fabric, decoded
// into the 12-bit button word this core's controller_adapter already accepts.
//
// Why this shape.  The Wii Classic Controller is not a USB device: it is an I2C
// peripheral on a Wii Remote expansion connector, at address 0x52.  It reaches
// this board through Adafruit's Wii Nunchuck Breakout Adapter fed from USB-A
// VBUS, which level-shifts SCL/SDA onto that port's data pair -- SDA on D+ and
// SCL on D-.  The adapter only pulls the lines low and a pull-up raises them, so
// both pads are open drain.  This is the same wiring TinyNES uses for its
// controller 1 on this same board, and its records carry the measured pin
// assignments and the controller's identity bytes.
//
// The FPGA-side USB HID host in this tree cannot serve this controller: it sits
// behind `ifdef USB1/USB2, which config.v deliberately does not define, the USB
// pins are unconstrained, and the pll_12 module it needs is not in the tree at
// all.  I2C needs no PLL and no USB stack, so it is the shorter path and the one
// with a working reference on this hardware.
//
// Protocol, as the NES and SNES Classic consoles perform it and as TinyNES
// measured it:
//   write 0xF0 = 0x55, wait 10 ms   wake the controller unencrypted
//   write 0xFB = 0x00, wait 20 ms   finish disabling encryption
//   write 0xFE = 0x03, wait 20 ms   select data format 3
//   write 0xFA, read 6 bytes        identity; accept a Classic Controller
//   then about every millisecond: write 0x00 to set the pointer, wait for the
//   controller's conversion, and read the 8 data bytes.  In format 3 the first
//   six are LX RX LY RY LT RT and the last two are the buttons.
//
// A byte the controller does not acknowledge, or a clock line held low for
// 1 ms, marks it absent; the sequencer then rewinds to the wake-up and tries
// again, so a controller plugged in at any time starts working.
//
// The output is the same 12-bit word controller_snes.v produces and
// usb_hid_host.v declares: (R L X A RT LT DN UP START SELECT Y B), where RT and
// LT are the RIGHT and LEFT d-pad directions, not the shoulder triggers -- see
// usb_hid_host.v's own concatenation for that ordering.
//
// Provenance: the sequencer, the open-drain bit timing and the Classic identity
// check follow TinyNES's fpga/ae350_soc/wii_pads.sv (MIT, same author).  This is
// a single-bus port without that module's AHB register interface, retimed for
// this core's 21.477 MHz mclk rather than 75 MHz, and it packs nothing: the
// buttons are decoded straight to this core's layout.
//
//   US_CLOCKS  clocks per microsecond on clk.  mclk is 21.477 MHz, so 21.
//   QUARTER    quarter of a bit time, in clocks.  54 gives 4 * 54 / 21.477 MHz
//              = 10.06 us, about 99 kHz, near the 100 kHz the protocol expects.
//   CONVERT_US how long the controller takes to convert after the pointer
//              write; 200 us is the documented worst case.

module wii_pad #(
    parameter integer US_CLOCKS  = 21,
    parameter integer QUARTER    = 54,
    parameter integer CONVERT_US = 200
) (
    input  wire        clk,
    input  wire        resetn,

    // Open-drain pad control, kept as plain logic so the protocol can be
    // benched without tristate resolution.  The pad itself is made from these
    // at the top level: the line is pulled low when *_low is high and released
    // otherwise, and *_in reads back the resolved level.
    output reg         sda_low,
    output reg         scl_low,
    input  wire        sda_in,
    input  wire        scl_in,

    // 1 while a Classic Controller is woken, identified and answering.
    output reg         present,
    // 1 once its identity has been read and accepted as a Classic Controller.
    output reg         classic,
    // Saturating transfer counters, for the interface's own diagnostics.
    output reg  [15:0] reads,
    output reg  [7:0]  fails,
    // (R L X A RT LT DN UP START SELECT Y B), 1 = pressed.
    output reg  [11:0] buttons,
    // The two raw button bytes of the last data report, byte 6 in 15:8 and
    // byte 7 in 7:0, active low.  Present so a probe build can show what the
    // controller actually sent rather than what this module decoded it to.
    output wire [15:0] dbg_bytes,
    // 1 when the pad reported format 3, 0 when it reported format 1.
    output wire        dbg_format3
);

    // ------------------------------------------------------------- timing
    // Synchronise both line levels: they cross from the controller's own
    // clock domain and are sampled throughout the bit timing.
    reg [1:0] scl_s = 2'b11, sda_s = 2'b11;
    wire scl_hi = scl_s[1], sda_hi = sda_s[1];

    // One microsecond tick, for the waits between transfers.
    reg [7:0] us_div = 8'd0;
    wire us_tick = us_div == US_CLOCKS[7:0] - 8'd1;

    // ---------------------------------------------------- transfer layer --
    // go starts one transfer: START, the address byte (read when rd), then
    // `len` bytes written from wbytes or `rlen` bytes read into rbuf with the
    // last byte in 63:56, then STOP.  done pulses at the end, with nack set if
    // any byte was not acknowledged or a line stayed low for 1 ms.
    localparam [3:0] T_IDLE   = 4'd0,  T_START0 = 4'd1, T_START1 = 4'd2,
                     T_START2 = 4'd3,  T_BIT0   = 4'd4, T_BIT1   = 4'd5,
                     T_BIT2   = 4'd6,  T_BIT3   = 4'd7, T_STOP0  = 4'd8,
                     T_STOP1  = 4'd9,  T_STOP2  = 4'd10, T_DONE  = 4'd11;

    localparam [7:0] ADDR_W = 8'hA4;   // 0x52 shifted left, write
    localparam [7:0] ADDR_R = 8'hA5;   // 0x52 shifted left, read

    reg [3:0]  t = T_IDLE;
    reg        go = 1'b0, rd = 1'b0;
    reg [1:0]  len = 2'd0;             // bytes written after the address
    reg [15:0] wbytes = 16'd0;         // first byte in 15:8
    reg [3:0]  rlen = 4'd6;            // bytes read: 6 identity, 8 data
    reg [7:0]  rbuf [0:7];        // read bytes, index 0 first
    // The identity, kept apart from rbuf: rbuf is overwritten by every data
    // poll, and identity byte 4 -- which report format the pad is using -- has
    // to survive so the decode can consult it.
    reg [7:0]  rbuf_id4 = 8'h00;
    // The live report format, latched from the identity so both the sequencer
    // and the decode can use it.  Kept separate from `format3` below because
    // that is a wire derived from rbuf_id4 inside the decode block.
    reg        fmt3_reg = 1'b0;
    // How many times the format-3 request has been re-issued for this session.
    reg [1:0]  fmt_tries = 2'd0;
    reg        done = 1'b0, nack = 1'b0;
    reg [11:0] qcount = 12'd0;
    reg [9:0]  stretch_us = 10'd0;
    reg [7:0]  shift = 8'd0;
    reg [3:0]  bitn = 4'd0;            // 8 is the acknowledge bit
    reg [3:0]  byten = 4'd0;           // 0 is the address

    wire last_byte = rd ? byten == rlen : byten == {2'b0, len};
    wire q_end = qcount == QUARTER[11:0];

    always @(posedge clk) begin
        if (!resetn) begin
            t <= T_IDLE;
            scl_low <= 1'b0;
            sda_low <= 1'b0;
            done <= 1'b0;
            nack <= 1'b0;
            qcount <= 12'd0;
            stretch_us <= 10'd0;
            scl_s <= 2'b11;
            sda_s <= 2'b11;
            us_div <= 8'd0;
        end else begin
            scl_s <= {scl_s[0], scl_in};
            sda_s <= {sda_s[0], sda_in};
            us_div <= us_tick ? 8'd0 : us_div + 8'd1;
            done <= 1'b0;
            qcount <= q_end ? 12'd0 : qcount + 12'd1;
            case (t)
                T_IDLE: begin
                    qcount <= 12'd0;
                    if (go) begin
                        nack <= 1'b0;
                        byten <= 4'd0;
                        bitn <= 4'd0;
                        shift <= rd ? ADDR_R : ADDR_W;
                        scl_low <= 1'b0;
                        sda_low <= 1'b0;
                        stretch_us <= 10'd0;
                        t <= T_START0;
                    end
                end
                // Both lines released with SCL high, then SDA falls, then SCL.
                T_START0:
                    if (!scl_hi) begin
                        qcount <= 12'd0;
                        if (us_tick) stretch_us <= stretch_us + 10'd1;
                        if (stretch_us == 10'd1000) begin
                            nack <= 1'b1;
                            t <= T_DONE;
                        end
                    end else if (q_end) begin
                        sda_low <= 1'b1;
                        t <= T_START1;
                    end
                T_START1:
                    if (q_end) begin
                        scl_low <= 1'b1;
                        t <= T_START2;
                    end
                T_START2:
                    if (q_end) t <= T_BIT0;
                // One bit: SCL low while SDA is set, SCL released, sampled in
                // the high half, then SCL pulled low again.
                T_BIT0: begin
                    if (bitn == 4'd8)
                        // Acknowledge: this master drives it after a read byte
                        // that is not the last; otherwise SDA belongs to the
                        // controller.
                        sda_low <= rd && byten != 4'd0 && !last_byte;
                    else if (rd && byten != 4'd0)
                        sda_low <= 1'b0;
                    else
                        sda_low <= !shift[7];
                    if (q_end) begin
                        scl_low <= 1'b0;
                        stretch_us <= 10'd0;
                        t <= T_BIT1;
                    end
                end
                T_BIT1:
                    // Wait for SCL to read high, which absorbs a slow rise and
                    // a controller stretching the clock.
                    if (!scl_hi) begin
                        qcount <= 12'd0;
                        if (us_tick) stretch_us <= stretch_us + 10'd1;
                        if (stretch_us == 10'd1000) begin
                            nack <= 1'b1;
                            t <= T_STOP0;
                        end
                    end else if (q_end)
                        t <= T_BIT2;
                T_BIT2:
                    if (q_end) begin
                        if (bitn == 4'd8) begin
                            if (!(rd && byten != 4'd0) && sda_hi)
                                nack <= 1'b1;
                        end else
                            shift <= {shift[6:0], sda_hi};
                        scl_low <= 1'b1;
                        t <= T_BIT3;
                    end
                T_BIT3:
                    if (q_end) begin
                        if (bitn == 4'd8) begin
                            bitn <= 4'd0;
                            if (last_byte) begin

                                t <= T_STOP0;
                            end else begin
                                byten <= byten + 4'd1;
                                shift <= rd ? 8'h00
                                            : (byten == 4'd0 ? wbytes[15:8]
                                                             : wbytes[7:0]);
                                t <= T_BIT0;
                            end
                        end else begin
                            bitn <= bitn + 4'd1;
                            t <= T_BIT0;
                        end
                    end
                // SDA low with SCL low, SCL released, then SDA released.
                T_STOP0: begin
                    sda_low <= 1'b1;
                    if (q_end) begin
                        scl_low <= 1'b0;
                        stretch_us <= 10'd0;
                        t <= T_STOP1;
                    end
                end
                T_STOP1:
                    if (!scl_hi) begin
                        qcount <= 12'd0;
                        if (us_tick) stretch_us <= stretch_us + 10'd1;
                        if (stretch_us == 10'd1000) begin
                            nack <= 1'b1;
                            sda_low <= 1'b0;
                            t <= T_DONE;
                        end
                    end else if (q_end) begin
                        sda_low <= 1'b0;
                        t <= T_STOP2;
                    end
                T_STOP2:
                    if (q_end) t <= T_DONE;
                T_DONE: begin
                    scl_low <= 1'b0;
                    sda_low <= 1'b0;
                    done <= 1'b1;
                    t <= T_IDLE;
                end
                default: t <= T_IDLE;
            endcase
        end
    end

    // Store each read byte where its index says it belongs.  An explicit index
    // is used rather than a shift register because every reader of these bytes
    // -- the identity check and the button decode -- then names the byte it
    // wants, and a miscount cannot silently move them.
    integer bi;
    always @(posedge clk) begin
        if (!resetn) begin
            for (bi = 0; bi < 8; bi = bi + 1) rbuf[bi] <= 8'h00;
        end else if (t == T_BIT3 && q_end && bitn == 4'd8 && rd && byten != 4'd0)
            rbuf[byten - 4'd1] <= shift;
    end

    // --------------------------------------------------------- sequencer --
    localparam [3:0] Q_WAIT = 4'd0, Q_WAKE1 = 4'd1, Q_WAKE2 = 4'd2,
                     Q_FORMAT = 4'd3, Q_IDPTR = 4'd4, Q_IDREAD = 4'd5,
                     Q_PTR = 4'd6, Q_READ = 4'd7, Q_BUSY = 4'd8;

    reg [3:0]  q = Q_WAIT, q_next = Q_WAKE1;
    reg [16:0] wait_us = 17'd20000;    // first wake 20 ms after reset
    reg [16:0] after_us = 17'd0;       // the wait after the transfer in flight

    // What the transfer in flight is for, so its result lands in the right
    // place: the identity read is not a data report.
    reg ident_pending = 1'b0;

    // Consecutive failed transfers.  A single NACK must NOT be read as the
    // controller having gone away: this bus has one master and one slave with a
    // long cable and a level-shifting adapter on it, and an occasional failed
    // byte is normal.  Clearing presence on the first one made the pad look dead
    // for the whole retry interval, which is what a working controller plugged
    // into a working bus looked like from the console.
    localparam [3:0] GIVE_UP = 4'd8;
    reg [3:0] consec_fail = 4'd0;

    always @(posedge clk) begin
        if (!resetn) begin
            q <= Q_WAIT;
            q_next <= Q_WAKE1;
            wait_us <= 17'd20000;
            after_us <= 17'd0;
            go <= 1'b0;
            rd <= 1'b0;
            present <= 1'b0;
            classic <= 1'b0;
            reads <= 16'd0;
            fails <= 8'd0;
            ident_pending <= 1'b0;
            consec_fail <= 4'd0;
        end else begin
            go <= 1'b0;
            case (q)
                Q_WAIT:
                    if (wait_us == 17'd0)
                        q <= q_next;
                    else if (us_tick)
                        wait_us <= wait_us - 17'd1;
                Q_WAKE1: begin
                    rd <= 1'b0; len <= 2'd2; wbytes <= 16'hF055;
                    after_us <= 17'd10000; q_next <= Q_WAKE2;
                    go <= 1'b1; q <= Q_BUSY;
                end
                Q_WAKE2: begin
                    rd <= 1'b0; len <= 2'd2; wbytes <= 16'hFB00;
                    after_us <= 17'd20000; q_next <= Q_FORMAT;
                    go <= 1'b1; q <= Q_BUSY;
                end
                Q_FORMAT: begin
                    rd <= 1'b0; len <= 2'd2; wbytes <= 16'hFE03;
                    after_us <= 17'd20000; q_next <= Q_IDPTR;
                    go <= 1'b1; q <= Q_BUSY;
                end
                Q_IDPTR: begin
                    rd <= 1'b0; len <= 2'd1; wbytes <= 16'hFA00;
                    after_us <= CONVERT_US[16:0]; q_next <= Q_IDREAD;
                    go <= 1'b1; q <= Q_BUSY;
                end
                Q_IDREAD: begin
                    rd <= 1'b1; rlen <= 4'd6;
                    ident_pending <= 1'b1;
                    after_us <= 17'd1000; q_next <= Q_PTR;
                    go <= 1'b1; q <= Q_BUSY;
                end
                Q_PTR: begin
                    rd <= 1'b0; len <= 2'd1; wbytes <= 16'h0000;
                    after_us <= CONVERT_US[16:0]; q_next <= Q_READ;
                    ident_pending <= 1'b0;
                    go <= 1'b1; q <= Q_BUSY;
                end
                Q_READ: begin
                    rd <= 1'b1; rlen <= 4'd8;
                    after_us <= 17'd1000; q_next <= Q_PTR;
                    go <= 1'b1; q <= Q_BUSY;
                end
                Q_BUSY: begin
                    if (done) begin
                        if (nack) begin
                            // One failed transfer is a glitch, not a removal.
                            // Keep the pad's identity and keep reporting its last
                            // buttons; only after several consecutive failures
                            // is it treated as gone, and then the sequencer
                            // rewinds to the wake-up so a pad plugged in later
                            // works without a reset.
                            if (fails != 8'hFF) fails <= fails + 8'd1;
                            if (consec_fail == GIVE_UP) begin
                                present <= 1'b0;
                                classic <= 1'b0;
                                q_next <= Q_WAKE1;
                                wait_us <= 17'd100000;
                            end else begin
                                consec_fail <= consec_fail + 4'd1;
                                q_next <= Q_PTR;   // just try the next poll
                                wait_us <= 17'd2000;
                            end
                            q <= Q_WAIT;
                        end else begin
                            consec_fail <= 4'd0;
                            wait_us <= after_us;
                            q <= Q_WAIT;
                            if (ident_pending) begin
                                // The Classic identity is 00 00 A4 20 xx 01:
                                // bytes 2 and 4 and the low nibble of byte 5
                                // are what distinguish it from other Wii
                                // extensions.
                                // A Classic Controller's identity is
                                // 00 00 A4 20 xx 01.
                                if (rbuf[2] == 8'hA4 &&
                                    rbuf[3] == 8'h20 &&
                                    rbuf[5][3:0] == 4'h1) begin
                                    classic <= 1'b1;
                                    present <= 1'b1;
                                    rbuf_id4 <= rbuf[4];
                                    fmt3_reg <= rbuf[4][3:0] == 4'h3;
                                end else begin
                                    classic <= 1'b0;
                                    present <= 1'b0;
                                    q_next <= Q_WAKE1;
                                    wait_us <= 17'd100000;
                                end

                            end else if (classic) begin
                                present <= 1'b1;
                                if (reads != 16'hFFFF) reads <= reads + 16'd1;
                            end
                        end
                    end
                end
                default: q <= Q_WAIT;
            endcase
        end
    end

    // ----------------------------------------------------------- buttons
    // Where the buttons are depends on the report format the controller is
    // actually sending, and that is not something to assume.  A genuine Classic
    // Controller reads 0xFE as 0x01 and only switches to format 3 when 0x03 is
    // written, reporting the change in identity byte 4; 8BitDo's Retro Receiver
    // sends format 3 whatever 0xFE says.  So a pad that ignored the format write
    // here would still answer, still look identified, and still send format 1 --
    // whose buttons are in bytes 4 and 5.  Reading bytes 6 and 7 of a format-1
    // report returns the bytes after it, which are filler, and a constant
    // all-released pattern looks exactly like a dead pad.
    //
    // Identity byte 4 says which format is live, so decode from the pair it
    // names: 0x03 is format 3 (bytes 6,7), anything else is format 1 (bytes
    // 4,5).  Format 3's button bytes use format 1's bit layout, so only the byte
    // position differs between the two.
    // Format 3, which the wake-up selects and the reference proves the pad
    // accepts: buttons in report bytes 6 and 7, using format 1's bit layout.
    wire [7:0] btn_lo = rbuf[6];
    wire [7:0] btn_hi = rbuf[7];
    assign dbg_bytes = {btn_hi, btn_lo};
    assign dbg_format3 = 1'b1;
    wire       b_r     = ~btn_lo[1];
    wire       b_plus  = ~btn_lo[2];
    wire       b_minus = ~btn_lo[4];
    wire       b_l     = ~btn_lo[5];
    wire       b_down  = ~btn_lo[6];
    wire       b_right = ~btn_lo[7];
    wire       b_up    = ~btn_hi[0];
    wire       b_left  = ~btn_hi[1];
    wire       b_x     = ~btn_hi[3];
    wire       b_a     = ~btn_hi[4];
    wire       b_y     = ~btn_hi[5];
    wire       b_b     = ~btn_hi[6];

    always @(posedge clk) begin
        if (!resetn || !(present && classic))
            buttons <= 12'd0;
        else
            // (R L X A RT LT DN UP START SELECT Y B)
            buttons <= {b_r, b_l, b_x, b_a, b_right, b_left,
                        b_down, b_up, b_plus, b_minus, b_y, b_b};
    end

endmodule
