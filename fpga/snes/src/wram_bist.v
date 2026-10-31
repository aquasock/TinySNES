// WRAM self-test, TinyNES diagnostic build (TINYSNES_WRAM_TEST).
//
// Why this and not the vector latch cycle 19 proposed: reading the loaded image's
// own code at the upload call site showed the routine depends on WRAM in three
// separate ways, and every measured failure has the shape of one of them.
//
//   $8901  A9 00 / 85 00   STA $00    a 24-bit data pointer in direct page
//   $8907  A9 80 / 85 01   STA $01
//   $890B  A9 19 / 85 02   STA $02
//   $890D  78              SEI
//   $890E  20 88 88        JSR $8888  return address onto the stack
//   $88CC  48              PHA         another stack push
//   $88CD  C2 20           REP #$20
//   $88CF  B7 00           LDA [$00],Y reads the source data THROUGH that pointer
//   $88FF  28              PLP
//   $8900  60              RTS         return address pulled back off the stack
//
// Direct page and the stack both live in WRAM.  A corrupted pointer makes the CPU
// copy the wrong bytes into the SPC, which is the SPC-executing-garbage behaviour
// every boot shows; a corrupted return address makes RTS jump to garbage, which is
// the open-bus execution at $7C7F that three of five boots reached.  WRAM is also
// the one memory this project has never byte-lane tested -- sdram_bist covers the
// ROM region and aram_bist covers the SPC's port, but WRAM's lane select,
// {WRAM_ADDR[0], ~WRAM_ADDR[0]}, is a different mechanism and has never been
// exercised.
//
// The test is therefore byte-lane aware, for the reason aram_bist.v is: each word
// gets a DIFFERENT byte in each lane, so a swapped pair fails on all 16 bits
// rather than passing by symmetry, and the second write must not disturb the
// first.  Sets, each written in full then read back:
//
//   set 0  walking one on the even lane, complement on the odd
//   set 1  walking one on the odd lane, complement on the even
//   set 2  walking zero on both lanes
//   set 3  the low 256 words -- $0000-$01FF, where the direct page and the stack
//          actually live, which are the addresses the upload routine uses
//
//   mask bit k,   k = 0..7  : mismatch on the even-lane byte, data bit k
//   mask bit k+8, k = 0..7  : mismatch on the odd-lane byte,  data bit k
//
//   status 0 running, 1 pass (mask == 0), 2 mismatch, 3 no acknowledge
//
// snes2hdmi draws the mask as 16 bars, red where the bit is set, over a status
// band, the same display as TINYSNES_SDRAM_TEST and TINYSNES_ARAM_TEST.

module wram_bist #(
    parameter [7:0] ACK_TIMEOUT = 8'd200,
    parameter [7:0] DATA_WAIT   = 8'd12
)(
    input             clk,              // mclk
    input             resetn,
    input             ready,            // controller finished its init
    output reg [16:0] addr,             // WRAM byte address
    output reg  [7:0] din,              // one byte; the controller duplicates it
    output reg        we,
    output reg        req,
    input             ack,
    input      [15:0] dout,             // the whole word: {odd lane, even lane}
    output reg [15:0] mask,             // per-bit mismatch, sticky
    output reg  [1:0] status
);

    reg  [1:0] set;
    reg  [2:0] idx;
    reg  [1:0] phase;                   // 0 write even, 1 write odd, 2 read
    reg  [7:0] timer;
    reg  [2:0] st;

    localparam [2:0] S_IDLE  = 3'd0,
                     S_SETUP = 3'd1,
                     S_ACK   = 3'd2,
                     S_DATA  = 3'd3,
                     S_FIN   = 3'd4;

    // Eight words per set; the low-address set uses eight too.
    localparam [2:0] LAST_IDX = 3'd7;

    // Word addresses.  Sets 0-2 spread eight words across the 128 KiB space; the
    // fourth set stays in the low 512 bytes, which is where the direct page and
    // the stack are, so a fault confined to the region the upload routine
    // actually touches cannot hide behind a passing test elsewhere.
    function [16:0] word_of;
        input [1:0] s;
        input [2:0] i;
        begin
            if (s == 2'd3)
                word_of = {11'd0, i, 5'd0};      // i * 32, inside $0000-$00FF
            else
                word_of = {8'd0, i, 11'd0};      // i * 2048, across 128 KiB
        end
    endfunction

    // Both lanes always differ from each other, so a lane swap cannot pass.
    function [7:0] even_of;
        input [1:0] s;
        input [2:0] i;
        begin
            case (s)
                2'd0:    even_of = 8'd1 << i;
                2'd1:    even_of = ~(8'd1 << i);
                2'd2:    even_of = ~(8'd1 << i);
                default: even_of = i[0] ? 8'hA5 : 8'h5A;
            endcase
        end
    endfunction

    function [7:0] odd_of;
        input [1:0] s;
        input [2:0] i;
        begin
            case (s)
                2'd0:    odd_of = ~(8'd1 << i);
                2'd1:    odd_of = 8'd1 << i;
                2'd2:    odd_of = ~(8'd1 << i);
                default: odd_of = i[0] ? 8'h5A : 8'hA5;
            endcase
        end
    endfunction

    wire [15:0] want = {odd_of(set, idx), even_of(set, idx)};
    wire [15:0] diff = dout ^ want;

    always @(posedge clk) begin
        if (~resetn) begin
            st     <= S_IDLE;
            set    <= 2'd0;
            idx    <= 3'd0;
            phase  <= 2'd0;
            timer  <= 8'd0;
            req    <= 1'b0;
            we     <= 1'b1;
            addr   <= 17'd0;
            din    <= 8'd0;
            mask   <= 16'd0;
            status <= 2'd0;
        end else begin
            case (st)
            S_IDLE: begin
                if (ready) begin
                    set   <= 2'd0;
                    idx   <= 3'd0;
                    phase <= 2'd0;
                    st    <= S_SETUP;
                end
            end

            // Address and data are registered one cycle before the request is
            // offered, so the controller latches a settled value.  The odd lane
            // is addressed through addr[0], which is what selects it.
            S_SETUP: begin
                addr  <= (phase == 2'd1) ? (word_of(set, idx) | 17'd1)
                                         : word_of(set, idx);
                din   <= (phase == 2'd1) ? odd_of(set, idx) : even_of(set, idx);
                we    <= (phase != 2'd2);
                req   <= ~req;
                timer <= 8'd0;
                st    <= S_ACK;
            end

            S_ACK: begin
                timer <= timer + 8'd1;
                if (ack == req) begin
                    if (phase != 2'd2) begin
                        phase <= phase + 2'd1;
                        st    <= S_SETUP;
                    end else begin
                        timer <= 8'd0;
                        st    <= S_DATA;
                    end
                end else if (timer == ACK_TIMEOUT) begin
                    status <= 2'd3;
                    st     <= S_FIN;
                end
            end

            // Read data lands in cpu_port1 a few fclk after the ack.
            S_DATA: begin
                timer <= timer + 8'd1;
                if (timer == DATA_WAIT) begin
                    mask <= mask | diff;
                    if (idx != LAST_IDX) begin
                        idx   <= idx + 3'd1;
                        phase <= 2'd0;
                        st    <= S_SETUP;
                    end else if (set == 2'd3) begin
                        status <= ((mask | diff) == 16'd0) ? 2'd1 : 2'd2;
                        st     <= S_FIN;
                    end else begin
                        set   <= set + 2'd1;
                        idx   <= 3'd0;
                        phase <= 2'd0;
                        st    <= S_SETUP;
                    end
                end
            end

            S_FIN: ;
            default: st <= S_IDLE;
            endcase
        end
    end

endmodule
