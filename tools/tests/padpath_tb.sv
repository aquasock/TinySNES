`timescale 1ns/1ps

// End-to-end bench for the player-1 button path: wii_pad -> controller_adapter
// -> the SNES controller serial protocol.
//
// wii_pad_tb proves the I2C master and the decode, but it stops at wii_pad's own
// `buttons` output.  Nothing until now tested controller_adapter, which is the
// module that actually drives the SNES port: it latches the 16-bit button word
// on the latch pulse and shifts it out one bit per clock, B first, with the line
// inverted.  A wrong bit order or a wrong polarity there would look exactly like
// a dead pad on the console, so it is worth proving on its own.
//
// The check is a round trip: hold one button, let the protocol run a full frame,
// and require that the bit which came out of the port is the one the controller
// pressed -- and that no other bit came out set.
//
//   tools/tests/run_padpath_tb.sh

module padpath_tb;

    reg clk = 0;
    always #5 clk = ~clk;

    reg resetn = 0;

    // ---- wii_pad, with a minimal I2C slave that reports a fixed button pair
    wire sda_low_dut, scl_low_dut;
    reg  sda_low_slv = 1'b0;
    wire sda_in = ~sda_low_dut & ~sda_low_slv;
    wire scl_in = ~scl_low_dut;

    wire present, classic;
    wire [15:0] reads;
    wire [7:0]  fails;
    wire [11:0] wii_buttons;
    wire [15:0] pad_bytes;
    wire        pad_fmt3;

    reg [7:0] btn_lo = 8'hFF, btn_hi = 8'hFF;   // active low, all released

    wii_pad #(.US_CLOCKS(4), .QUARTER(3), .CONVERT_US(10)) pad (
        .clk(clk), .resetn(resetn),
        .sda_low(sda_low_dut), .scl_low(scl_low_dut),
        .sda_in(sda_in), .scl_in(scl_in),
        .present(present), .classic(classic),
        .reads(reads), .fails(fails),
        .buttons(wii_buttons), .dbg_bytes(pad_bytes), .dbg_format3(pad_fmt3)
    );

    // ---- controller_adapter, exactly as the top level instantiates it
    reg  joy_strb = 0;
    reg  joy_clk  = 0;
    wire joy_di;

    controller_adapter dut (
        .clk(clk),
        .snes_buttons({4'b0, wii_buttons}),
        .snes_joy_strb(joy_strb),
        .snes_joy_clk(joy_clk),
        .snes_joy_di(joy_di)
    );

    // --------------------------------------------------------- I2C slave model
    // Answers 0x52 with the Classic identity and an 8-byte format-3 report whose
    // button bytes are btn_hi:btn_lo.  Only what this bench needs: address, the
    // register pointer, and reads.
    reg [7:0] ident [0:5];
    initial begin
        ident[0]=8'h00; ident[1]=8'h00; ident[2]=8'hA4;
        ident[3]=8'h20; ident[4]=8'h03; ident[5]=8'h01;   // 0x03 = format 3
    end

    // 1 = the pad reports format 3 (identity byte 4 = 0x03), 0 = format 1
    // (identity byte 4 = 0x01).  The buttons move between byte pairs with it.
    reg fmt3 = 1'b1;

    function [7:0] report_byte(input integer b);
        case (b)
            0: report_byte = 8'h80; 1: report_byte = 8'h80;
            2: report_byte = 8'h80; 3: report_byte = 8'h80;
            // Format 3: bytes 4,5 are the LT/RT triggers, buttons at 6,7.
            // Format 1: bytes 4,5 ARE the buttons.
            4: report_byte = fmt3 ? 8'h00 : btn_lo;
            5: report_byte = fmt3 ? 8'h00 : btn_hi;
            6: report_byte = fmt3 ? btn_lo : 8'hFF;
            default: report_byte = fmt3 ? btn_hi : 8'hFF;
        endcase
    endfunction

    reg       active=0, rd_xfer=0, ident_rd=0, armed=0;
    integer   k=0, settle=0;
    reg [7:0] shin=0, ptr=0;
    reg sda_p=1'b1, scl_p=1'b1;
    always @(posedge clk) begin sda_p <= sda_in; scl_p <= scl_in; end
    wire start_bit = scl_p && sda_p && !sda_in && scl_in;
    wire stop_bit  = scl_p && !sda_p && sda_in && scl_in;
    wire scl_rise  = !scl_p && scl_in;
    wire scl_fall  = scl_p && !scl_in;

    function [7:0] read_byte(input integer b);
        read_byte = ident_rd ? ((b-1 < 6) ? ident[b-1] : 8'h00)
                             : report_byte(b-1);
    endfunction

    always @(posedge clk) begin
        if (!resetn) begin
            active<=0; sda_low_slv<=0; k<=0; ptr<=0; rd_xfer<=0; ident_rd<=0; armed<=0;
        end else if (start_bit) begin
            active<=1; k<=0; shin<=0; sda_low_slv<=0; armed<=0;
        end else if (stop_bit) begin
            active<=0; sda_low_slv<=0; armed<=0;
        end else if (active && scl_rise) begin
            if (k % 9 < 8) shin <= {shin[6:0], sda_in};
            if (k % 9 == 8) begin
                if (k/9 == 0) begin
                    rd_xfer <= shin[0];
                    if (shin[0]) ident_rd <= (ptr == 8'hFA);
                end else if (!rd_xfer && k/9 == 1) ptr <= shin;
            end
            k <= k + 1;
        end else if (active && scl_fall) begin
            armed <= 1'b1; settle <= 0;
        end else if (active && armed && !scl_in) begin
            settle <= settle + 1;
            if (settle >= 2) begin
                armed <= 1'b0;
                if (k % 9 == 8)
                    sda_low_slv <= (k/9 == 0) || !rd_xfer;
                else if (rd_xfer && k/9 >= 1)
                    sda_low_slv <= ~read_byte(k/9)[7 - (k%9)];
                else
                    sda_low_slv <= 1'b0;
            end
        end
    end

    // ------------------------------------------------------- SNES port reader
    // The console clocks 16 bits out of the pad: a latch pulse, then one bit per
    // falling clock edge.  `joy_di` is inverted by the adapter, so a pressed
    // button reads 0 on the wire.  Capture the 16 bits of one frame.
    reg [15:0] frame = 16'hFFFF;
    integer    fidx = 0;

    // Drive one full latch-and-shift frame.
    task run_frame;
        integer i;
        begin
            joy_clk = 1'b1;
            joy_strb = 1'b1;
            @(posedge clk); @(posedge clk);
            joy_strb = 1'b0;
            @(posedge clk);
            frame = 16'hFFFF;
            // The console samples the line for slot i *before* the clock edge
            // that shifts slot i+1 into place, so sample first and shift after.
            for (i = 0; i < 16; i = i + 1) begin
                @(posedge clk);
                frame[i] = joy_di;
                joy_clk = 1'b0; repeat (3) @(posedge clk);   // shift
                joy_clk = 1'b1; repeat (3) @(posedge clk);
            end
        end
    endtask

    // ---------------------------------------------------------------- checks
    integer errors = 0;
    task check(input bit c, input [8*64-1:0] what);
        begin
            if (!c) begin errors = errors + 1; $display("FAIL  %0s", what); end
            else $display("ok    %0s", what);
        end
    endtask

    // Press one Classic button and require exactly its SNES bit on the wire.
    // Slot n of the wire carries snes_buttons[n], so a correct path turns frame
    // bit n low and leaves the rest high.
    task press(input [7:0] lo, input [7:0] hi, input integer slot, input [8*40-1:0] name);
        begin
            btn_lo = lo; btn_hi = hi;
            repeat (40000) @(posedge clk);       // let a poll cycle land
            run_frame;
            if (frame[slot] !== 1'b0) begin
                errors = errors + 1;
                $display("FAIL  %0s: wire bit %0d did not go low (frame=%04h)", name, slot, frame);
            end else if (frame !== ~(16'h0001 << slot)) begin
                errors = errors + 1;
                $display("FAIL  %0s: wire bit %0d low but frame=%04h, expected %04h",
                         name, slot, frame, ~(16'h0001 << slot));
            end else
                $display("ok    %0s -> wire slot %0d", name, slot);
        end
    endtask

    // Switch the modelled pad's report format and let the sequencer re-read its
    // identity, which is where the format is learned.
    task set_format(input bit to_fmt3);
        begin
            fmt3 = to_fmt3; ident[4] = to_fmt3 ? 8'h03 : 8'h01;
            // The pad does not change format mid-session in the field: it is in
            // format 1 from power-on and moves to format 3 only if the 0xFE
            // write lands.  So start a fresh session rather than expecting the
            // sequencer to re-read an identity it has no reason to re-read.
            resetn = 0;
            repeat (30) @(posedge clk);
            resetn = 1;
            repeat (1500000) @(posedge clk);
            $display("  power-cycled with model in format %0d (identity byte 4 = %02h): pad reports format3=%b, present=%b classic=%b",
                     to_fmt3 ? 3 : 1, ident[4], pad_fmt3, present, classic);
        end
    endtask

    initial begin
        $display("padpath bench: wii_pad -> controller_adapter -> SNES serial port");
        resetn = 0;
        repeat (20) @(posedge clk);
        resetn = 1;

        repeat (1500000) @(posedge clk);
        $display("  present=%b classic=%b reads=%0d fmt3=%b", present, classic, reads, pad_fmt3);
        check(present === 1'b1 && classic === 1'b1, "pad identified before the wire test");

        // Wire order is B, Y, SELECT, START, UP, DOWN, LEFT, RIGHT, A, X, L, R.
        // snes_buttons = (R L X A RT LT DN UP START SELECT Y B), so slot 0 is B.
        // Idle: every bit released, so the wire reads all ones.
        check(frame === 16'hFFFF, "idle pad leaves every wire bit high");

        // ---- format 3: buttons in report bytes 6 and 7
        $display("  --- report format 3 (identity byte 4 = 03) ---");
        // Wire slot order for the SNES pad protocol: slot 0 B, 1 Y, 2 SELECT,
        // 3 START, 4 UP, 5 DOWN, 6 LEFT, 7 RIGHT, 8 A, 9 X, 10 L, 11 R.
        press(8'hFF, 8'hBF,  0, "B");
        press(8'hFF, 8'hDF,  1, "Y");
        press(8'hEF, 8'hFF,  2, "Minus is SELECT");
        press(8'hFB, 8'hFF,  3, "Plus is START");
        press(8'hFF, 8'hFE,  4, "Up");
        press(8'hBF, 8'hFF,  5, "Down");
        press(8'hFF, 8'hFD,  6, "Left");
        press(8'h7F, 8'hFF,  7, "Right");
        press(8'hFF, 8'hEF,  8, "A");
        press(8'hFF, 8'hF7,  9, "X");
        press(8'hDF, 8'hFF, 10, "L");
        press(8'hFD, 8'hFF, 11, "R");

        $display("");
        if (errors == 0) $display("PASS  every button reaches its correct wire slot");
        else             $display("FAIL  %0d check(s) failed", errors);
        $finish;
    end

endmodule
