`timescale 1ns/1ps

// Bench for wii_pad.sv: a Wii Classic Controller modelled on an I2C bus.
//
// There is nothing off-the-shelf to point this at -- the controller is an I2C
// peripheral, not a USB device -- so the model here answers at 0x52, accepts the
// wake and format writes, returns the genuine controller's identity at register
// 0xFA, and returns an eight-byte format-3 report from register 0x00 with the
// buttons in the last two bytes, active low.  Each button is then pressed in
// turn and the decoded 12-bit word is checked, so a wrong bit assignment or a
// wrong polarity fails here instead of on the board.
//
// It also checks `report`, the six bytes sent to TinyTang as frame 0x21: that
// it is report bytes 0 to 3, 6 and 7 in that order and nothing else, that it
// is only ever a whole report (a monitor checks every clock while it is valid,
// with every byte of the model's report changing together), that the identity
// read never lands in it, and that report_valid falls when the controller is
// unplugged and is set again only by a read after it is found again.
//
// The bus is modelled without tristate.  Both ends only ever pull a line low or
// release it, and a released line is high, so the resolved level is simply
// "neither end is pulling low".  That keeps the bench two-state and
// deterministic under Verilator.
//
//   tools/tests/run_wii_pad_tb.sh

module wii_pad_tb;

    // ---------------------------------------------------------------- clock
    // Not the production 21.477 MHz: the module's timing is expressed in
    // US_CLOCKS, and both that and the bus quarter are scaled down here so the
    // 20 ms wake-up does not cost minutes of wall time.  What is under test is
    // the protocol and the decode, not the wall-clock rate.
    reg clk = 0;
    always #5 clk = ~clk;                  // 100 MHz

    localparam integer US_CLOCKS  = 4;     // clocks per "microsecond" here
    localparam integer QUARTER    = 3;     // quarter bit time in clocks
    localparam integer CONVERT_US = 10;

    reg resetn = 0;

    // ------------------------------------------------------------- the bus
    wire sda_low_dut, scl_low_dut;
    reg  sda_low_slv = 1'b0;
    wire sda_in = ~sda_low_dut & ~sda_low_slv;
    wire scl_in = ~scl_low_dut;            // the model never stretches the clock

    wire present, classic;
    wire [15:0] reads;
    wire [7:0]  fails;
    wire [11:0] buttons;
    wire [47:0] report;
    wire        report_valid;

    wii_pad #(
        .US_CLOCKS(US_CLOCKS), .QUARTER(QUARTER), .CONVERT_US(CONVERT_US)
    ) dut (
        .clk(clk), .resetn(resetn),
        .sda_low(sda_low_dut), .scl_low(scl_low_dut),
        .sda_in(sda_in), .scl_in(scl_in),
        .present(present), .classic(classic),
        .reads(reads), .fails(fails), .buttons(buttons),
        .report(report), .report_valid(report_valid)
    );

    // ------------------------------------------------ Classic Controller model
    // The genuine controller's identity as measured: 00 00 A4 20 01 01.
    reg [7:0] ident [0:5];
    initial begin
        ident[0] = 8'h00; ident[1] = 8'h00; ident[2] = 8'hA4;
        // identity byte 4 declares the report format: 0x03 is format 3, and this
        // model sends format-3 reports (buttons in bytes 6 and 7), so it must say
        // so.  Leaving it at 0x01 made the bench agree with a decode that assumed
        // format 3 -- two places encoding the same assumption, which is exactly
        // how a real pad in format 1 went unnoticed.
        ident[3] = 8'h20; ident[4] = 8'h03; ident[5] = 8'h01;
    end

    // Format 3 report: LX RX LY RY LT RT then the two button bytes.
    // Buttons are active low, so idle is FF FF.  The six other bytes all come
    // from one generation number g, each differently, so a report built from
    // two reads, or with a byte in the wrong place, is not any generation's.
    // The triggers are distinct from all of them, so one that leaks into
    // `report` shows.  In the last phase (gen_buttons) the button bytes are
    // made from g too, and the model moves g on after every read.
    reg [7:0] g = 8'h10;
    reg       gen_buttons = 1'b0;
    reg       gen_check = 1'b0;    // the monitor checks the buttons too
    reg       unplugged = 1'b0;    // the model acknowledges nothing
    wire [7:0] rep_lx = g, rep_rx = g ^ 8'h11, rep_ly = g ^ 8'h22, rep_ry = g ^ 8'h33;
    reg [7:0] rep_lt = 8'hE7, rep_rt = 8'hE8;
    reg [7:0] btn_lo_p = 8'hFF, btn_hi_p = 8'hFF;
    wire [7:0] btn_lo = gen_buttons ? g ^ 8'h44 : btn_lo_p;
    wire [7:0] btn_hi = gen_buttons ? g ^ 8'h55 : btn_hi_p;

    function [7:0] report_byte(input [3:0] b);
        case (b)
            4'd0: report_byte = rep_lx;
            4'd1: report_byte = rep_rx;
            4'd2: report_byte = rep_ly;
            4'd3: report_byte = rep_ry;
            4'd4: report_byte = rep_lt;
            4'd5: report_byte = rep_rt;
            4'd6: report_byte = btn_lo;
            default: report_byte = btn_hi;
        endcase
    endfunction

    // ------------------------------------------------------------ slave state
    reg       active   = 1'b0;     // inside a transfer
    integer   k        = 0;        // SCL rising edges seen since START
    reg [7:0] shin     = 8'd0;     // byte being received
    reg [7:0] ptr      = 8'd0;     // register pointer
    reg       rd_xfer  = 1'b0;     // current transfer is a read
    reg       ident_rd = 1'b0;     // the read in progress is the identity
    reg       armed    = 1'b0;     // an SDA update is pending
    // The master NACKed a read byte: the read is over, so the slave lets go
    // of SDA until the next START.  Without this the model drove a seventh
    // identity byte's first bit into the master's STOP, missed the STOP, and
    // answered the next few transfers out of step -- the first reports after
    // identification were garbage in the bench only.
    reg       mnack    = 1'b0;
    integer   settle   = 0;        // clocks waited for SCL to be low

    reg sda_prev = 1'b1, scl_prev = 1'b1;
    always @(posedge clk) begin
        sda_prev <= sda_in;
        scl_prev <= scl_in;
    end
    wire start_bit = scl_prev && sda_prev && !sda_in && scl_in;
    wire stop_bit  = scl_prev && !sda_prev && sda_in && scl_in;
    wire scl_rise  = !scl_prev && scl_in;
    wire scl_fall  = scl_prev && !scl_in;

    // The byte a read returns for read-byte index b (b = 1 is the first data
    // byte after the address byte).
    function [7:0] read_byte(input integer b);
        begin
            if (ident_rd)
                read_byte = (b - 1 < 6) ? ident[b - 1] : 8'h00;
            else
                read_byte = report_byte(b - 1);
        end
    endfunction

    always @(posedge clk) begin
        if (!resetn) begin
            active <= 1'b0;
            sda_low_slv <= 1'b0;
            k <= 0;
            ptr <= 8'd0;
            rd_xfer <= 1'b0;
            ident_rd <= 1'b0;
            armed <= 1'b0;
        end else if (start_bit) begin
            active <= 1'b1;
            k <= 0;
            shin <= 8'd0;
            sda_low_slv <= 1'b0;
            armed <= 1'b0;
            mnack <= 1'b0;
        end else if (stop_bit) begin
            active <= 1'b0;
            sda_low_slv <= 1'b0;
            armed <= 1'b0;
            if (gen_buttons && rd_xfer && !ident_rd)
                g <= g + 8'd1;
        end else if (active && scl_rise) begin
            if (k % 9 < 8)
                shin <= {shin[6:0], sda_in};
            if (k % 9 == 8 && rd_xfer && k / 9 >= 1 && sda_in)
                mnack <= 1'b1;
            if (k % 9 == 8) begin
                // A whole byte has just finished.
                if (k / 9 == 0) begin
                    // Address byte: 0xA4 write, 0xA5 read.
                    rd_xfer <= shin[0];
                    if (shin[0])
                        ident_rd <= (ptr == 8'hFA);
                end else if (!rd_xfer && k / 9 == 1) begin
                    ptr <= shin;
                end
            end
            k <= k + 1;
        end else if (active && scl_fall) begin
            // SDA may only change while SCL is low, or a release looks like a
            // STOP to anything watching.  Hold off a couple of clocks so the
            // clock line is unambiguously low before touching data.
            armed <= 1'b1;
            settle <= 0;
        end else if (active && armed && !scl_in) begin
            // Prepare SDA for the rising edge that is about to be index k.
            settle <= settle + 1;
            if (settle >= 2) begin
                armed <= 1'b0;
                if (unplugged || mnack)
                    sda_low_slv <= 1'b0;
                else if (k % 9 == 8)
                    // The slave acknowledges its address byte and every byte
                    // it is sent.  During a read the MASTER owns the
                    // acknowledge, so the slave must release here -- holding
                    // SDA low through it would keep the line down and the
                    // STOP could never be seen.
                    sda_low_slv <= (k / 9 == 0) || !rd_xfer;
                else if (rd_xfer && k / 9 >= 1)
                    sda_low_slv <= ~read_byte(k / 9)[7 - (k % 9)];   // data, MSB first
                else
                    sda_low_slv <= 1'b0;
            end
        end
    end

    // ------------------------------------------------------------ checking
    integer errors = 0;
    task check(input bit cond, input [8*72-1:0] what);
        begin
            if (!cond) begin
                errors = errors + 1;
                $display("FAIL  %0s", what);
            end else
                $display("ok    %0s", what);
        end
    endtask

    // Press one Classic Controller button and require the exact SNES word.
    // The expected word is (R L X A RT LT DN UP START SELECT Y B), so a single
    // button sets exactly one bit -- which is the check that would catch a
    // wrong bit position or a reversed polarity.
    task press(input [7:0] lo, input [7:0] hi, input [11:0] want, input [8*48-1:0] name);
        integer settle;
        begin
            btn_lo_p = lo;
            btn_hi_p = hi;
            // Several poll cycles: the sequencer re-reads about every
            // millisecond of its own scaled time.
            repeat (15000) @(posedge clk);
            if (buttons !== want) begin
                errors = errors + 1;
                $display("FAIL  %0s: buttons=%03h expected %03h", name, buttons, want);
            end else
                $display("ok    %0s -> %03h", name, buttons);
            if (^buttons === 1'bx) begin
                errors = errors + 1;
                $display("FAIL  %0s: buttons has X", name);
            end
            if (report !== {hi, lo, rep_ry, rep_ly, rep_rx, rep_lx}) begin
                errors = errors + 1;
                $display("FAIL  %0s: report=%012h expected %012h", name, report,
                         {hi, lo, rep_ry, rep_ly, rep_rx, rep_lx});
            end
        end
    endtask

    // Every clock the report is valid it must be one generation's sticks --
    // and in the last phase one generation's buttons too.
    integer torn = 0, valid_clocks = 0;
    wire [7:0] rg = report[7:0];
    wire whole = report[15:8] == (rg ^ 8'h11) && report[23:16] == (rg ^ 8'h22) &&
                 report[31:24] == (rg ^ 8'h33) &&
                 (!gen_check || (report[39:32] == (rg ^ 8'h44) &&
                                   report[47:40] == (rg ^ 8'h55)));
    always @(posedge clk) if (resetn && report_valid) begin
        valid_clocks = valid_clocks + 1;
        if (!whole) begin
            if (torn < 5)
                $display("FAIL  report %012h is not one whole report", report);
            torn = torn + 1;
        end
    end

    initial begin
        $display("wii_pad bench: Classic Controller decode over I2C");
        resetn = 0;
        repeat (20) @(posedge clk);
        resetn = 1;

        // Halfway through the wake-up nothing has been read.
        repeat (150000) @(posedge clk);
        check(report_valid === 1'b0, "no report before the controller is read");

        // The wake-up sequence is 20 + 10 + 20 + 20 ms before the identity
        // read; at four bench clocks per microsecond that is 280k clocks.
        repeat (250000) @(posedge clk);
        check(report_valid === 1'b1, "the report is valid once data is read");

        $display("  present=%b classic=%b reads=%0d fails=%0d",
                 present, classic, reads, fails);
        check(present === 1'b1, "controller is detected and present");
        check(classic === 1'b1, "identity is accepted as a Classic Controller");
        check(fails === 8'd0, "no failed transfers");
        check(reads > 16'd0, "at least one data report was read");

        // Idle: nothing held.  btn bytes FF FF -> no buttons.
        press(8'hFF, 8'hFF, 12'h000, "nothing held");

        // byte 6: bit1 R, 2 Plus, 3 Home, 4 Minus, 5 L, 6 Down, 7 Right
        press(8'hFD, 8'hFF, 12'h800, "R");
        press(8'hFB, 8'hFF, 12'h008, "Plus is START");
        press(8'hEF, 8'hFF, 12'h004, "Minus is SELECT");
        press(8'hDF, 8'hFF, 12'h400, "L");
        press(8'hBF, 8'hFF, 12'h020, "Down");
        press(8'h7F, 8'hFF, 12'h080, "Right");

        // byte 7: bit0 Up, 1 Left, 3 X, 4 A, 5 Y, 6 B
        press(8'hFF, 8'hFE, 12'h010, "Up");
        press(8'hFF, 8'hFD, 12'h040, "Left");
        press(8'hFF, 8'hF7, 12'h200, "X");
        press(8'hFF, 8'hEF, 12'h100, "A");
        press(8'hFF, 8'hDF, 12'h002, "Y");
        press(8'hFF, 8'hBF, 12'h001, "B");

        // Two at once, to show it is a bit vector and not a one-hot decoder.
        press(8'hFB, 8'hFF, 12'h008, "Plus alone again");
        press(8'hFB, 8'hBF, 12'h009, "B with START");

        // Home is not in the SNES word: pressing it must not invent a button.
        press(8'hF7, 8'hFF, 12'h000, "Home maps to nothing");
        press(8'hFF, 8'hFF, 12'h000, "released");

        // Every byte changing at every read: the report must stay whole.
        gen_buttons = 1'b1;
        // The report already held is the last press's, so the monitor starts
        // checking its buttons once a few reads have replaced it.
        repeat (20000) @(posedge clk);
        gen_check = 1'b1;
        begin : gens
            reg [7:0] g0;
            g0 = g;
            repeat (150000) @(posedge clk);
            check(g - g0 > 8'd10, "the model changed its report at every read");
            check(report_valid === 1'b1 && whole, "report follows a changing controller");
        end

        // Unplugged: every transfer fails until the controller is given up.
        unplugged = 1'b1;
        repeat (200000) @(posedge clk);
        check(present === 1'b0, "an unplugged controller is given up");
        check(report_valid === 1'b0, "and its report is no longer valid");

        // Plugged back in: found, identified and read again.
        unplugged = 1'b0;
        repeat (500000) @(posedge clk);
        check(present === 1'b1 && report_valid === 1'b1, "replugged, read again");

        check(torn == 0, "the report was whole at every valid clock");
        $display("  report valid for %0d clocks, %0d torn", valid_clocks, torn);

        $display("");
        if (errors == 0) $display("PASS  Classic Controller decode is correct for every button");
        else             $display("FAIL  %0d check(s) failed", errors);
        $finish;
    end

endmodule
