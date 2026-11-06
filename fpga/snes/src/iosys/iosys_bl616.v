// IOSys_bl616 - BL616-based IO system
// 
// This manages UART connection to the companion bl616 MCU, accepts ROM loading and other requests,
// and display the text overlay when needed.
// 
// Author: nand2mario, 2/2025

`define MCU_BL616

module iosys_bl616 #(
    parameter FREQ=21_477_000,
    parameter [14:0] COLOR_LOGO=15'b00000_10101_00000,
    parameter [15:0] CORE_ID=1,     // 1: nestang, 2: snestang
    parameter [7:0] LOADING_STATE=0,
    // Clocks between joypad report ticks: 20 ms, the rate TinyTang expects.
    // A bench shortens it so a report does not take a simulated 20 ms.
    parameter integer REPORT_CLOCKS=FREQ/50
)
(
    input clk,                      // main logic clock
    // input clk50,                    // 50mhz clock for UART
    input hclk,                     // hdmi clock
    input resetn,

    // OSD display interface
    output overlay,
    input [7:0] overlay_x,          // 0-255
    input [7:0] overlay_y,          // 0-223
    output [14:0] overlay_color,    // BGR5
    input [11:0] joy1,              // DS2/SNES joystick 1: (R L X A RT LT DN UP START SELECT Y B)
    input [11:0] joy2,              // DS2/SNES joystick 2
    output reg [15:0] hid1,         // USB HID joystick 1
    output reg [15:0] hid2,         // USB HID joystick 2
    input home,                     // Wii Classic HOME, 1 = pressed

    // TinyDesk overlay, drawn by desk_layer in snes2hdmi.  desk_on is 1 while
    // the desk should be shown and the game's pads should read idle.  Each cell
    // written by a 0x14 frame toggles desk_wr_tog with its address and data
    // already set; they then hold for the rest of that cell's five bytes
    // (~25 us), long enough for the pixel clock to synchronise the toggle and
    // take them without a handshake.
    output desk_on,
    output reg        desk_wr_tog,
    output reg [11:0] desk_wr_addr,
    output reg [36:0] desk_wr_data, // {char[6:0], fg[14:0], bg[14:0]}, colours {b,g,r}

    // ROM loading interface
    output [7:0] rom_loading,   // 0-to-1 loading starts, 1-to-0 loading is finished
    output reg [7:0] rom_do,        // first 64 bytes are snes header + 32 bytes after snes header 
    output reg rom_do_valid,        // strobe for rom_do

    // Battery-save window onto the cartridge SRAM, frames 0x18 and 0x19.
    // The address, data and write strobe are presented together and sampled by
    // the array on one master clock, so the host must hold the core in reset
    // (rom_loading non-zero) while it uses them; both frames are refused
    // otherwise.  sav_rdata is the array's registered output, one clock behind
    // sav_addr, which is what lets the read reply stream bytes back to back.
    output      [16:0] sav_addr,
    output reg  [7:0] sav_wdata,
    output reg        sav_we,
    input       [7:0] sav_rdata,

    // The pad map, frame 0x1A: twelve 4-bit selectors, in the order the pad
    // word carries the buttons.  Identity out of reset.
    output reg [47:0] pad_map,

    // The picture's shape, frame 0x1B.  See VIDEO_MODE below.
    output reg [1:0] video_aspect,
    output reg       video_overscan,

    // PCXT management interface
    output reg [15:0] mgmt_address,
    output reg        mgmt_read,
    input      [15:0] mgmt_readdata,
    output reg        mgmt_write,
    output reg [15:0] mgmt_writedata,
    input      [1:0]  fdd_request,      // [1]: write, [0]: read

    // Keyboard interface
    output reg       kbd_data_valid,
    
    output reg [31:0] core_config,

    // TinySNES: debug register endpoint, frame type 0x10, served by
    // tinysnes_dbg.v.  debug_address is set from the request before the CRC
    // arrives, so debug_rdata has six character times (~600 clk) to settle;
    // debug_valid pulses only for a request whose CRC and version check.
    output reg [31:0] debug_address,
    output reg [31:0] debug_wdata,
    output reg        debug_valid,
    output reg        debug_write,
    input      [31:0] debug_rdata,

    // UART interface
    input  uart_rx,
    output uart_tx
);
// TinySNES: written from the UART command handler, never read, and left
// unconnected by snestang_top; a local reg rather than an assigned input.
reg [7:0] kbd_data;

localparam integer STR_LEN = 73; // number of characters in the config string
localparam [8*STR_LEN-1:0] CONF_STR = "Tangcores;-;O12,OSD key,Right+Select,Select+Start,Select+RB;-;V,v20240101";

// Remove SPI parameters and add UART parameters
localparam CLK_FREQ = FREQ;
localparam BAUD_RATE = 2_000_000;

// The extended request TinyTang's firmware sends for `fpgar` (fpga_ext_read32
// in ports/bl616/tang_fpga_uart.c), and the same endpoint Tang-Phosphor serves:
//
//   request  0x10 version opcode seq[15:0] addr[31:0] value[31:0] crc[15:0]
//   reply    0x10 version opcode|0x80 status seq[15:0] addr[31:0] value[31:0] crc[15:0]
//
// CRC-16/CCITT-FALSE (poly 0x1021, init 0xffff) over the type byte and the
// twelve bytes before the CRC.  Opcode 0 is capabilities, 1 read32, 2 write32.
// Status 0 ok, 1 bad version, 2 bad opcode, 3 bad CRC.
localparam [7:0] EXT_COMMAND = 8'h10;
localparam [7:0] EXT_VERSION = 8'h01;
localparam [7:0] EXT_CAPABILITIES = 8'h00;
localparam [7:0] EXT_READ32 = 8'h01;
localparam [7:0] EXT_WRITE32 = 8'h02;

// Battery-save frames.  0x18 carries a 24-bit address in its first three
// payload bytes and then a run of data bytes to store from that address on;
// it replies with nothing, because the host verifies a block by reading it
// back with 0x19 rather than by trusting a write acknowledgement.  0x19
// carries the same address and then a byte count, and its reply is that many
// bytes followed by a CRC-16 over the type byte and the data.
localparam [7:0] SAVE_WRITE = 8'h18;
localparam [7:0] SAVE_READ  = 8'h19;
// The pad map: twelve 4-bit selectors packed into six bytes, one per SNES
// button in the order the pad word carries them (R L X A RT LT DN UP START
// SELECT Y B).  Selector i says which SOURCE button drives output button i,
// and 12 to 15 mean that button is not produced at all.  Identity --
// 0,1,2,...,11 -- is the wiring every earlier build had and what the register
// resets to, so a host that never sends this frame gets a pad it cannot tell
// apart from before.
//
// This has to live in fabric because the pad never reaches the BL616: the Wii
// Classic Controller is read by wii_pad.sv over I2C on USB-A's data pair, and
// the BL616's own wiipad command goes through the desktop core's I2C engine,
// which is not loaded while this core runs.  A remapping UI can therefore only
// be honoured here.
localparam [7:0] PAD_MAP = 8'h1a;
// The picture's shape: one byte, bits 1:0 the aspect (0 4:3, 1 8:7, 2 1:1)
// and bit 2 whether the PPU's extra fifteen lines are shown when a game asks
// for them.  Out of reset it is 4:3 with the extra lines shown, which is the
// geometry and the line count this core had before the setting existed.
localparam [7:0] VIDEO_MODE = 8'h1b;
// Largest reply that still fits the BL616's 256-byte frame payload, counting
// its four-byte header and the two-byte CRC.
localparam [7:0] SAVE_READ_MAX = 8'd250;

function [15:0] crc16_byte;
    input [15:0] crc;
    input [7:0] data;
    integer bit_index;
    reg [15:0] value;
    begin
        value = crc ^ {data, 8'b0};
        for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1)
            value = value[15] ? (value << 1) ^ 16'h1021 : value << 1;
        crc16_byte = value;
    end
endfunction

// The on-screen display is removed from this build.
//
// Why, rather than left as a runtime toggle.  `overlay_reg` powers up set, and
// `snes2hdmi` draws the overlay in preference to the picture while it is set, so
// the machine is invisible until the host sends the OSD-off command over the
// UART.  That command is sent at the end of `tools/load_snes_rom.py`, which means
// everything before it -- the whole upload, and any load where the command is
// dropped -- shows the OSD instead of the SNES.  That is a second, independent
// reason for a black or corrupt screen that has nothing to do with the core.
//
// It also has no consumer here.  TinySNES has no menu, the character buffer is
// never written by anything in this tree, and the tool that is meant to provide
// the OSD later is TinyDesk.  So the display is tied off rather than toggleable:
// a runtime flag that can silently come back on is exactly the kind of state that
// produced the wrong readings this project has already paid for twice.
//
// What remains is `textdisp` itself, kept instantiated and clocked so nothing
// else in the iosys hierarchy changes shape, but with its output unused.  The
// menu BRAM is initialised from font.vh and logo.vh and is ~2 KB of block RAM;
// that is left in place rather than removed, because deleting it is a separate
// change to a vendor-primitive wrapper and this one is about the picture.
assign overlay = 1'b0;

// TinyDesk.  0x08 is TinyTang's overlay show/hide (tang_osd_toggle) and 0x15 its
// desk enable; the desk is drawn only while both are set, the condition TinyNES
// uses.  Both power up clear so a game is never hidden behind a desk that
// nothing has painted.
localparam integer DESK_CELLS = 80 * 45;
reg desk_overlay = 1'b0;
reg desk_enable = 1'b0;
reg [11:0] desk_cursor = 12'd0;
reg [7:0] desk_x = 8'd0;
reg [2:0] desk_nth = 3'd0;     // byte of the current 0x14 cell
assign desk_on = desk_overlay & desk_enable;

reg [7:0] rom_loading_reg = LOADING_STATE;
assign rom_loading = rom_loading_reg;

// UART receiver signals
wire [7:0] rx_data;
wire rx_valid;

// UART transmitter signals
reg [7:0] tx_data;
reg tx_valid;
wire tx_ready;

// synchronize uart_rx to clk
reg uart_rx_r = 1, uart_rx_rr = 1;
always @(posedge clk) begin
    uart_rx_r <= uart_rx;
    uart_rx_rr <= uart_rx_r;
end

// Instantiate UART modules
async_receiver #(
    .ClkFrequency(CLK_FREQ),
    .Baud(BAUD_RATE)
) uart_receiver (
    .clk(clk),
    .RxD(uart_rx_rr),
    .RxD_data(rx_data),
    .RxD_data_ready(rx_valid)
);

async_transmitter #(
    .ClkFrequency(CLK_FREQ),
    .Baud(BAUD_RATE)
) uart_transmitter (
    .clk(clk),
    .TxD(uart_tx),
    .TxD_data(tx_data),
    .TxD_start(tx_valid),
    .TxD_busy(tx_busy)
);
assign tx_ready = ~tx_busy;

// Command processing state machine
localparam RECV_IDLE         = 7'b0000001; // waiting for command
localparam RECV_LEN1         = 7'b0000010; // receiving length msb
localparam RECV_LEN2         = 7'b0000100; // receiving length lsb
localparam RECV_CMD          = 7'b0001000; // receiving command
localparam RECV_PARAM        = 7'b0010000; // receiving parameters
localparam RECV_RESPONSE_REQ = 7'b0100000; // sending response
localparam RECV_RESPONSE_ACK = 7'b1000000; // waiting for response sending to finish 
reg [6:0] recv_state = RECV_IDLE;

// UART command buffer
reg [7:0] cmd_reg;
reg [15:0] len_reg;
reg [31:0] data_reg;
reg [23:0] rom_remain;
reg [15:0] data_cnt;
reg [3:0] kbd_len;

// Add new registers for textdisp interface
reg [7:0] x_wr;
reg [7:0] y_wr;
reg [7:0] char_wr;
reg we;

// Add these registers for cursor management
reg [7:0] cursor_x;
reg [7:0] cursor_y;

reg [7:0] response_type;
reg response_req = 1'b0;          // power-up values, which the FPGA gives them anyway;
reg response_ack = 1'b0;          // explicit so a simulator does not start at X

// Extended request fields and its reply.
reg [7:0]  ext_version;
reg [7:0]  ext_opcode;
reg [15:0] ext_sequence;
reg [31:0] ext_address;
reg [31:0] ext_value;
reg [15:0] ext_crc;
reg [7:0]  ext_crc_hi;
reg [7:0]  response_opcode;
reg [7:0]  response_status;
reg [15:0] response_sequence;
reg [31:0] response_address;
reg [31:0] response_data;

// Battery-save frame state.
reg [23:0] sav_base = 24'd0;    // address carried by the frame's first 3 bytes
reg [15:0] sav_len  = 16'd0;    // bytes to send back for a 0x19

// One owner per direction, because a register written from two always blocks is
// a multiple driver: the synthesiser picks one assignment and drops the other
// silently, and on the board that left the address frozen so a 16-byte read
// returned the same byte sixteen times.  The write address belongs to the
// receive handler and the read address to the sender, and the port is the mux.
reg [16:0] sav_wr_addr = 17'd0;
reg [16:0] sav_rd_addr = 17'd0;

// mgmt_* multiplex
reg mgmt_rx;
reg [15:0] mgmt_address_rx;
reg [15:0] mgmt_address_tx;
assign mgmt_address = mgmt_rx ? mgmt_address_rx : mgmt_address_tx;

localparam FDD_READY = 0;
localparam FDD_READ_WAIT = 1;
localparam FDD_DONE_WAIT = 2;

reg [1:0] fdd_state;
reg fdd_read_start, fdd_read_finish, fdd_write_finish;

// The TangCore bl616-fpga UART protocol
//
// Since 0.9, we've introduce a data frame to avoid spurious messages:
//
//         0xAA frame_len[15:0] payload_of_frame_len_bytes
//
// Command payloads from BL616 to FPGA:
// 0x01                       get core ID (response type 0x01, see below), frame_len = 1
// 0x02                       get core config string (response type 0x02, see below)
// 0x03 x[31:0]               set core config status
// 0x04 x[7:0] y[7:0]         move overlay text cursor to (x, y)
// 0x05 <string>              display string from cursor (len implied by frame header, =frame_len-1)
// 0x06 loading_state[7:0]    set loading state (0: core running, non-0: loading)
// 0x07 <data>                load data to rom_do (len implied by frame header)
// 0x08 x[7:0]                x[0]: turn overlay on/off
// 0x09 hid1[15:0] hid2[15:0] send USB joystick state to FPGA
// 0x0a <data_sector>         send a sector (512 bytes) of data to floppy data FIFO
// 0x0b addr[15:0] data[15:0] write to disk management interface (mgmt_address and mgmt_writedata)
// 0x0c <scancode>            send PS/2 scancode (len specified by frame header)
// 0x0d <string>              debug printf. core ignores this.
// 0x10 <extended request>    TinySNES: debug register read/write with CRC-16
// 0x13 x[7:0] y[7:0]         TinyDesk: move the cell cursor to (x, y) of 80x45
// 0x14 <cells>               TinyDesk: 5 bytes per cell from the cursor on,
//                            char[7:0] fg[15:0] bg[15:0], colours 15-bit {b,g,r}
// 0x15 x[7:0]                TinyDesk: x[0] enables the desk (0x08 then shows it)
// 0x18 addr[23:0] <data>     TinySNES: store the data bytes in cartridge SRAM
//                            from addr on.  Refused unless loading; no reply.
// 0x1a map[47:0]             TinySNES: 12 nibbles, the pad map; button i of
//                            the pad word takes source map[i], 12..15 = none
// 0x1b x[7:0]                TinySNES: x[1:0] aspect (0 4:3, 1 8:7, 2 1:1),
//                            x[2] show the PPU's extra fifteen lines
// 0x19 addr[23:0] n[7:0]     TinySNES: reply with n bytes of cartridge SRAM
//                            from addr, then a CRC-16.  Refused unless loading,
//                            and a refusal is a reply with no data bytes.
//
// Response payloads from FPGA to BL616:
// 0x01 core_id[7:0]          core ID
// 0x02 <string>              core config string (len specified by frame header)
// 0x03 joy1[15:0] joy2[15:0] joypad state in TinyTang's pad word (see below),
//                            on a change at a 20 ms tick and every 500 ms
// 0x04 lba[15:0] <data_512>  write a sector to disk
// 0x05 lba[15:0]             read a sector from disk (followed by command 0x0a)
// 0x10 <extended response>   TinySNES: debug register reply with CRC-16

// UART RX: command processing
always @(posedge clk) begin
    if (!resetn) begin
        recv_state <= RECV_IDLE;
        cmd_reg <= 0;
        data_reg <= 0;
        rom_loading_reg <= 0;
        rom_remain <= 0;
        core_config <= 0;
        data_cnt <= 0;
        x_wr <= 0;
        y_wr <= 0;
        char_wr <= 0;
        we <= 0;
        cursor_x <= 0;
        cursor_y <= 0;
        desk_overlay <= 0;
        desk_enable <= 0;
        desk_cursor <= 0;
        desk_nth <= 0;
        desk_wr_tog <= 0;
        sav_wr_addr <= 0;
        sav_wdata <= 0;
        sav_we <= 1'b0;
        sav_base <= 0;
        sav_len <= 0;
        // Identity: output i takes source i.  Written as a literal so the reset
        // value is visible rather than computed.
        pad_map <= {4'd11, 4'd10, 4'd9, 4'd8, 4'd7, 4'd6,
                    4'd5,  4'd4,  4'd3, 4'd2, 4'd1, 4'd0};
        video_aspect <= 2'd0;       // 4:3
        video_overscan <= 1'b1;     // show the extra lines when offered
    end else begin
        rom_do_valid <= 0;
        we <= 0;
        mgmt_write <= 0;
        fdd_read_finish <= 0;
        mgmt_rx <= 0;
        kbd_data_valid <= 0;
        debug_valid <= 0;
        debug_write <= 0;
        sav_we <= 1'b0;

        case (recv_state)

            RECV_IDLE: if (rx_valid && rx_data == 8'hAA) begin
                recv_state <= RECV_LEN1;
            end

            RECV_LEN1: if (rx_valid) begin
                len_reg[15:8] <= rx_data;
                if (rx_data < 8)                      // max frame length 2047
                    recv_state <= RECV_LEN2;
                else
                    recv_state <= RECV_IDLE;
            end

            RECV_LEN2: if (rx_valid) begin
                len_reg[7:0] <= rx_data;
                recv_state <= RECV_CMD;
            end

            RECV_CMD: if (rx_valid) begin
                cmd_reg <= rx_data;
                ext_crc <= crc16_byte(16'hffff, rx_data);
                if (rx_data == 1 || rx_data == 2) 
                    recv_state <= RECV_RESPONSE_REQ;    // request sending core id / config string
                else if (len_reg > 1)
                    recv_state <= RECV_PARAM;
                else
                    recv_state <= RECV_IDLE;
                data_cnt <= 0;
                desk_nth <= 0;
            end
            
            RECV_PARAM: if (rx_valid) begin
                data_reg <= {data_reg[23:0], rx_data};
                data_cnt <= data_cnt + 1;
                // e.g. set_overlay x[7:0], the 1st param byte is the last 
                //      (data_cnt == 0, len_reg == 2)
                if (data_cnt + 2 == len_reg)
                    recv_state <= RECV_IDLE;
                
                case (cmd_reg)
                    3: begin
                        if (data_cnt == 3) begin    // Received 4 bytes
                            core_config <= {data_reg[23:0], rx_data};
                        end
                    end
                    4: case (data_cnt)              // cursor
                        0: cursor_x <= rx_data;
                        1: cursor_y <= rx_data;
                        default: ;
                    endcase
                    5: begin                        // print
                        x_wr <= cursor_x;
                        y_wr <= cursor_y;
                        char_wr <= rx_data;
                        if (cursor_x < 32) begin
                            cursor_x <= cursor_x + 1;
                            we <= 1;
                        end
                    end
                    6: begin
                        rom_loading_reg <= rx_data;
                        recv_state <= RECV_IDLE;    // Single byte command
                    end
                    7: begin
                        rom_do <= rx_data;
                        rom_do_valid <= 1;      // pulse data valid
                    end
                    8: begin
                        // Overlay show/hide.  Drives the desk only; the legacy
                        // SNESTang text page stays tied off above.
                        if (data_cnt == 0)
                            desk_overlay <= rx_data[0];
                    end
                    8'h13: case (data_cnt)          // desk cursor, x then y
                        0: desk_x <= rx_data;
                        1: desk_cursor <= (desk_x < 80 && rx_data < 45) ?
                                          {rx_data[5:0], 6'd0} + {2'd0, rx_data[5:0], 4'd0} + {4'd0, desk_x} :
                                          DESK_CELLS[11:0];
                        default: ;
                    endcase
                    8'h14: begin                    // desk cells
                        desk_nth <= desk_nth == 3'd4 ? 3'd0 : desk_nth + 3'd1;
                        if (desk_nth == 3'd4 && desk_cursor < DESK_CELLS) begin
                            // data_reg holds the cell's first four bytes.
                            desk_wr_addr <= desk_cursor;
                            desk_wr_data <= {data_reg[30:24], data_reg[22:16], data_reg[15:8],
                                             data_reg[6:0], rx_data};
                            desk_wr_tog <= ~desk_wr_tog;
                            desk_cursor <= desk_cursor + 12'd1;
                        end
                    end
                    8'h15: if (data_cnt == 0)       // desk enable
                        desk_enable <= rx_data[0];
                    VIDEO_MODE: if (data_cnt == 0) begin // aspect and overscan
                        video_aspect   <= rx_data[1:0];
                        video_overscan <= rx_data[2];
                    end
                    PAD_MAP: begin                  // pad map: 12 nibbles, 6 bytes
                        case (data_cnt)
                            0: pad_map[47:40] <= rx_data;
                            1: pad_map[39:32] <= rx_data;
                            2: pad_map[31:24] <= rx_data;
                            3: pad_map[23:16] <= rx_data;
                            4: pad_map[15:8]  <= rx_data;
                            5: pad_map[7:0]   <= rx_data;
                            default: ;
                        endcase
                    end
                    SAVE_WRITE: begin               // battery save: store bytes
                        case (data_cnt)
                            0: sav_base[23:16] <= rx_data;
                            1: sav_base[15:8] <= rx_data;
                            2: sav_base[7:0] <= rx_data;
                            default: if (rom_loading_reg != 8'd0) begin
                                sav_wr_addr <= sav_base[16:0] + (data_cnt - 16'd3);
                                sav_wdata <= rx_data;
                                sav_we    <= 1'b1;
                            end
                        endcase
                    end
                    SAVE_READ: begin                // battery save: read bytes
                        case (data_cnt)
                            0: sav_base[23:16] <= rx_data;
                            1: sav_base[15:8] <= rx_data;
                            2: sav_base[7:0] <= rx_data;   // the sender latches it
                            3: begin
                                // A refusal is a reply with no data bytes, so
                                // the host still gets a frame back and can tell
                                // a refused read from a timed-out one.
                                sav_len <= (rom_loading_reg != 8'd0 &&
                                            rx_data != 8'd0 &&
                                            rx_data <= SAVE_READ_MAX) ? {8'd0, rx_data}
                                                                     : 16'd0;
                                recv_state <= RECV_RESPONSE_REQ;
                            end
                            default: ;
                        endcase
                    end
                    9: begin
                        case (data_cnt)
                            0: hid1[15:8] <= rx_data;
                            1: hid1[7:0] <= rx_data;
                            2: hid2[15:8] <= rx_data;
                            3: hid2[7:0] <= rx_data;
                            default: ;
                        endcase
                    end
                    'ha: begin                      // send read data to disk controller
                        mgmt_rx <= 1;
                        mgmt_address_rx <= 16'hf20f;
                        mgmt_writedata <= rx_data;
                        mgmt_write <= '1;
                        if (data_cnt == 511) 
                            fdd_read_finish <= 1;
                    end
                    'hb: begin                      // write disk controller register
                        mgmt_rx <= 1;
                        case (data_cnt)
                            0: mgmt_address_rx[15:8] <= rx_data;
                            1: mgmt_address_rx[7:0] <= rx_data;
                            2: mgmt_writedata[15:8] <= rx_data;
                            3: begin
                                mgmt_writedata[7:0] <= rx_data;
                                mgmt_write <= '1;
                            end
                            default: ;
                        endcase
                    end
                    'hc: begin                      // send PS/2 scancode to PCXT
                        kbd_data <= rx_data;
                        kbd_data_valid <= 1;
                    end
                    EXT_COMMAND: begin
                        if (data_cnt < 12)
                            ext_crc <= crc16_byte(ext_crc, rx_data);
                        case (data_cnt)
                            0: ext_version <= rx_data;
                            1: ext_opcode <= rx_data;
                            2: ext_sequence[15:8] <= rx_data;
                            3: ext_sequence[7:0] <= rx_data;
                            4: ext_address[31:24] <= rx_data;
                            5: ext_address[23:16] <= rx_data;
                            6: ext_address[15:8] <= rx_data;
                            7: begin
                                ext_address[7:0] <= rx_data;
                                debug_address <= {ext_address[31:8], rx_data};
                            end
                            8: ext_value[31:24] <= rx_data;
                            9: ext_value[23:16] <= rx_data;
                            10: ext_value[15:8] <= rx_data;
                            11: begin
                                ext_value[7:0] <= rx_data;
                                debug_wdata <= {ext_value[31:8], rx_data};
                            end
                            12: ext_crc_hi <= rx_data;
                            13: if (len_reg == 16'd15) begin
                                response_opcode <= ext_opcode;
                                response_sequence <= ext_sequence;
                                response_address <= ext_address;
                                if (ext_crc != {ext_crc_hi, rx_data}) begin
                                    response_status <= 8'd3;
                                    response_data <= 0;
                                end else if (ext_version != EXT_VERSION) begin
                                    response_status <= 8'd1;
                                    response_data <= 0;
                                end else if (ext_opcode == EXT_CAPABILITIES) begin
                                    response_status <= 0;
                                    response_data <= 32'h0000_0007;
                                end else if (ext_opcode == EXT_READ32) begin
                                    response_status <= 0;
                                    response_data <= debug_rdata;
                                    debug_valid <= 1;
                                end else if (ext_opcode == EXT_WRITE32) begin
                                    response_status <= 0;
                                    response_data <= ext_value;
                                    debug_valid <= 1;
                                    debug_write <= 1;
                                end else begin
                                    response_status <= 8'd2;
                                    response_data <= 0;
                                end
                                recv_state <= RECV_RESPONSE_REQ;
                            end
                            default: ;
                        endcase
                    end
                    default: begin
                        // unknown command: consume all data and return
                    end
                endcase
            end

            RECV_RESPONSE_REQ:                      // request to send config string
                case (cmd_reg)
                    1,2,EXT_COMMAND,SAVE_READ: begin    // 1: core ID, 2: config string,
                                                        // 0x10: debug reply, 0x19: save read
                        response_type <= cmd_reg;
                        response_req ^= 1;
                        recv_state <= RECV_RESPONSE_ACK;
                    end
                    default:
                        recv_state <= RECV_IDLE;
                endcase

            RECV_RESPONSE_ACK:                      // wait for TX to finish
                if (response_req == response_ack) begin
                    recv_state <= RECV_IDLE;
                end
        endcase
        
    end
end

localparam SEND_IDLE = 0;

localparam SEND_CORE_ID = 1;        // doubles as response type in message header
localparam SEND_CONFIG_STRING = 2;
localparam SEND_JOYPAD = 3;
localparam SEND_FDD_WRITE = 4;
localparam SEND_FDD_READ = 5;

localparam SEND_HEADER = 6;
localparam SEND_DONE = 7;
localparam SEND_DEBUG = 8;          // header type byte is EXT_COMMAND, not the state
localparam SEND_SAVE_READ = 9;      // header type byte is SAVE_READ, not the state

// One owner per direction, because a register written from two always blocks is
// a multiple driver: the synthesiser keeps one assignment and drops the other
// silently.  On the board that left the address frozen, so a 16-byte read
// returned the same byte sixteen times even though the reply and its CRC were
// well formed.  The write address belongs to the receive handler and the read
// address to the sender; the port is this mux.
assign sav_addr = (send_state == SEND_SAVE_READ) ? sav_rd_addr : sav_wr_addr;

reg [3:0] send_state, send_state_next;
// Eight bits, because a save read replies with up to 250 data bytes plus the
// two CRC bytes while the config string only needed seven.
reg [7:0] send_idx;

// Every state number below 0x10 doubles as its own frame type, which is why
// SEND_JOYPAD is 3 and SEND_CONFIG_STRING is 2.  The two states whose type
// byte is above the state range get it from this mux instead.
wire [7:0] resp_type_byte = send_state_next == SEND_DEBUG     ? EXT_COMMAND
                          : send_state_next == SEND_SAVE_READ ? SAVE_READ
                          : {4'b0, send_state_next};
reg [15:0] tx_crc;
reg [7:0] debug_tx_byte;
always @* begin
    case (send_idx[3:0])
        0: debug_tx_byte = EXT_VERSION;
        1: debug_tx_byte = response_opcode | 8'h80;
        2: debug_tx_byte = response_status;
        3: debug_tx_byte = response_sequence[15:8];
        4: debug_tx_byte = response_sequence[7:0];
        5: debug_tx_byte = response_address[31:24];
        6: debug_tx_byte = response_address[23:16];
        7: debug_tx_byte = response_address[15:8];
        8: debug_tx_byte = response_address[7:0];
        9: debug_tx_byte = response_data[31:24];
        10: debug_tx_byte = response_data[23:16];
        11: debug_tx_byte = response_data[15:8];
        12: debug_tx_byte = response_data[7:0];
        13: debug_tx_byte = tx_crc[15:8];
        default: debug_tx_byte = tx_crc[7:0];
    endcase
end
// Joypad report, in TinyTang's pad word (tang_pad.h) rather than the raw SNES
// word, as TinyNES sends it: D-pad, Classic B as A (0x100), Classic Y as B
// (0x001), and LB (0x400) only for a tap of HOME.  The raw word has SNES L at
// 0x400, which TinyTang's desk task reads as the desk toggle, so it is not
// passed through.  A report goes out at a 20 ms tick when the word changed and
// at every 25th tick regardless, so a dropped frame cannot leave a button stuck.
localparam integer REFRESH_TICKS = 25;      // 500 ms
localparam [7:0] TAP_TICKS = 8'd13;         // LB held ~260 ms for a HOME tap
function [15:0] pad_word;
    input [11:0] j;                         // (R L X A RT LT DN UP START SELECT Y B)
    pad_word = {7'd0, j[0], j[7:4], 3'd0, j[1]};
endfunction
reg [$clog2(REPORT_CLOCKS+1)-1:0] tick_count = 0;
wire tick = tick_count == REPORT_CLOCKS - 1;
reg [4:0] refresh = 5'd0;
reg [7:0] tap = 8'd0;
reg home_prev = 1'b0, home_alone = 1'b0;
// HOME with SELECT is the exit-and-save gesture, reported as bit 15 of the pad
// word.  It is a level, not a tap, so the app sees it for as long as the two
// are held.  SELECT being down means `home_alone` never arms, so the desk does
// not open at the same moment the exit is asked for.
wire save_exit = home & joy1[2];            // joy1[2] is SELECT
wire [15:0] joy1_now = pad_word(joy1) | (tap != 8'd0 ? 16'h0400 : 16'h0000)
                     | (save_exit ? 16'h8000 : 16'h0000);
wire [15:0] joy2_now = pad_word(joy2);
reg pad_pending = 1'b0;
reg [15:0] joy1_reg = 16'd0;
reg [15:0] joy2_reg = 16'd0;
reg [15:0] resp_frame_len;

// UART TX: command responses, joystick updates and FDD requests
always @(posedge clk) begin
    if (!resetn) begin
        tick_count <= 0;
        refresh <= 0;
        tap <= 0;
        home_prev <= 0;
        home_alone <= 0;
        pad_pending <= 0;
        joy1_reg <= 0;
        joy2_reg <= 0;
        send_state <= 0;
        sav_rd_addr <= 0;
    end else begin
        tx_valid <= 0;
        mgmt_read <= 0;
        fdd_read_start <= 0;
        fdd_write_finish <= 0;
        
        // Joypad report: decide at each tick, send when the sender is idle.
        tick_count <= tick ? 0 : tick_count + 1'b1;
        if (tick) begin
            if (tap != 8'd0)
                tap <= tap - 8'd1;
            refresh <= refresh == REFRESH_TICKS - 1 ? 5'd0 : refresh + 5'd1;
            if (joy1_now != joy1_reg || joy2_now != joy2_reg || refresh == REFRESH_TICKS - 1) begin
                pad_pending <= 1'b1;
                joy1_reg <= joy1_now;
                joy2_reg <= joy2_now;
            end
        end

        // A tap of HOME: pressed and released with nothing else held.  After
        // the tick, so a new tap wins over the count running down.
        home_prev <= home;
        if (home && !home_prev)
            home_alone <= joy1 == 12'd0;
        else if (home && joy1 != 12'd0)
            home_alone <= 1'b0;
        if (!home && home_prev && home_alone)
            tap <= TAP_TICKS;

        // UART transmission state machine
        case (send_state)
            SEND_IDLE: begin
                send_idx <= 0;
                if (pad_pending) begin
                    pad_pending <= 1'b0;
                    send_state_next <= SEND_JOYPAD;
                    send_state <= SEND_HEADER;
                    resp_frame_len <= 5;
                end else if (fdd_request[1] && fdd_state == FDD_READY) begin
                    send_state_next <= SEND_FDD_WRITE;
                    send_state <= SEND_HEADER;
                    mgmt_address_tx <= 16'hf200;    // read {drive, sector}
                    resp_frame_len <= 515;
                end else if (fdd_request[0] && fdd_state == FDD_READY) begin
                    send_state_next <= SEND_FDD_READ;
                    send_state <= SEND_HEADER;
                    mgmt_address_tx <= 16'hf200;    // read {drive, sector}
                    resp_frame_len <= 3;
                end else if (response_req != response_ack) begin
                    if (response_type == EXT_COMMAND) begin
                        send_state_next <= SEND_DEBUG;
                        send_state <= SEND_HEADER;
                        resp_frame_len <= 16;
                    end else if (response_type == SAVE_READ) begin
                        send_state_next <= SEND_SAVE_READ;
                        send_state <= SEND_HEADER;
                        sav_rd_addr <= sav_base[16:0];
                        // frame_len counts the type byte as well as the
                        // payload, so it is the data bytes plus the two CRC
                        // bytes plus one.  Two short and the receiver takes
                        // the last CRC byte as the start of a new frame.
                        resp_frame_len <= sav_len + 16'd3;
                    end else if (response_type == 2) begin
                        send_state_next <= SEND_CONFIG_STRING;
                        send_state <= SEND_HEADER;
                        resp_frame_len <= STR_LEN + 1;
                    end else if (response_type == 1) begin
                        send_state_next <= SEND_CORE_ID;
                        send_state <= SEND_HEADER;
                        resp_frame_len <= 2;
                    end
                end
            end

            SEND_HEADER: begin              // 4 byte header: 0xAA, resp_frame_len[15:0], resp_type[7:0]
                if (tx_ready && ~tx_valid) begin
                    tx_valid <= 1;
                    send_idx <= send_idx + 1;
                    case (send_idx[1:0])
                        0: tx_data <= 8'hAA;
                        1: tx_data <= resp_frame_len[15:8];
                        2: tx_data <= resp_frame_len[7:0];
                        3: begin
                            tx_data <= resp_type_byte;
                            tx_crc <= crc16_byte(16'hffff, resp_type_byte);
                            send_state <= send_state_next;
                            send_idx <= 0;
                        end
                        default: ;
                    endcase
                end
            end

            // The reply CRC is folded one byte per transmitted byte rather than
            // computed over all thirteen at once, so it adds no long XOR path.
            SEND_DEBUG: begin
                if (tx_ready && ~tx_valid) begin
                    tx_data <= debug_tx_byte;
                    if (send_idx <= 12)
                        tx_crc <= crc16_byte(tx_crc, debug_tx_byte);
                    tx_valid <= 1;
                    send_idx <= send_idx + 1;
                    if (send_idx == 14) begin
                        send_state <= SEND_IDLE;
                        response_ack <= response_req;
                    end
                end
            end

            // A save read streams the array's registered output.  sav_addr was
            // set to the base address while the request was parsed and is
            // advanced once per byte sent, so the byte put on the wire at index
            // i is the array's answer for base+i: the output lags the address
            // by one clock and the UART takes hundreds, so it is always settled.
            SEND_SAVE_READ: begin
                if (tx_ready && ~tx_valid) begin
                    if (send_idx < sav_len[7:0]) begin
                        tx_data <= sav_rdata;
                        tx_crc <= crc16_byte(tx_crc, sav_rdata);
                        sav_rd_addr <= sav_rd_addr + 17'd1;
                    end else if (send_idx == sav_len[7:0]) begin
                        tx_data <= tx_crc[15:8];
                    end else begin
                        tx_data <= tx_crc[7:0];
                        send_state <= SEND_IDLE;
                        response_ack <= response_req;
                    end
                    tx_valid <= 1;
                    send_idx <= send_idx + 1;
                end
            end

            SEND_CORE_ID: begin
                if (tx_ready && ~tx_valid) begin
                    tx_data <= CORE_ID[7:0];
                    tx_valid <= 1;
                    send_state <= SEND_IDLE;
                    response_ack <= response_req;
                end
            end

            SEND_CONFIG_STRING: begin
                if (tx_ready && ~tx_valid) begin
                    tx_data <= CONF_STR[8*(STR_LEN - send_idx - 1) +: 8];
                    tx_valid <= 1;
                    send_idx <= send_idx + 1;
                    if (send_idx == STR_LEN-1) begin
                        send_state <= SEND_IDLE;
                        response_ack <= response_req;
                    end
                end
            end

            SEND_JOYPAD: begin
                if (tx_ready && ~tx_valid) begin
                    case (send_idx)
                        0: tx_data <= joy1_reg[15:8]; // Joy1 high byte
                        1: tx_data <= joy1_reg[7:0];  // Joy1 low byte
                        2: tx_data <= joy2_reg[15:8]; // Joy2 high byte
                        3: tx_data <= joy2_reg[7:0];  // Joy2 low byte
                        default: ;
                    endcase
                    tx_valid <= 1;
                    send_idx <= send_idx + 1;
                    // TinySNES: no response_ack here.  A joypad frame is not
                    // a reply, and acking on it dropped whatever reply was
                    // pending when a button changed -- a debug read included.
                    if (send_idx == 3)
                        send_state <= SEND_IDLE;
                end
            end

            // fdd write. Send {drive, sector} followed by 512 bytes data to bl616
            SEND_FDD_WRITE: begin
                if (tx_ready && ~tx_valid) begin
                    case (send_idx)
                        0: tx_data <= mgmt_readdata[15:8];  // sector number
                        1: begin
                            tx_data <= mgmt_readdata[7:0];  // sector number
                            mgmt_address_tx <= 16'hf20f;    // start reading FIFO data
                        end
                        default: begin 
                            tx_data <= mgmt_readdata[7:0];  // send FIFO data
                            mgmt_read <= '1;                // advance FIFO pointer
                        end
                    endcase
                    tx_valid <= 1;
                    send_idx <= send_idx + 1;
                    if (send_idx == 511+2) begin
                        send_state <= SEND_DONE;
                        response_ack <= response_req;
                        fdd_write_finish <= 1;              // notify FDD state machine
                    end
                end
            end

            // FDD read. Just second the sector number. BL616 will send the data later via command 0x0b.
            SEND_FDD_READ: begin
                if (tx_ready && ~tx_valid) begin
                    case (send_idx)
                        0: tx_data <= mgmt_readdata[15:8];
                        1: tx_data <= mgmt_readdata[7:0];
                        default: ;
                    endcase
                    tx_valid <= 1;
                    send_idx <= send_idx + 1;
                    if (send_idx == 1) begin
                        send_state <= SEND_DONE;
                        response_ack <= response_req;
                        fdd_read_start <= 1;                // notify FDD state machine
                    end
                end
            end

            SEND_DONE: send_state <= SEND_IDLE;     // extra state for fdd_state to transition
        endcase
    end
end

// FDD state machine. UART TX only serves FDD requests when fdd_state == FDD_READY.
reg [3:0] fdd_cnt;
always @(posedge clk) begin
    if (!resetn) begin
        fdd_state <= FDD_READY;
    end else case (fdd_state)
        FDD_READY: begin
            if (fdd_read_start) begin
                fdd_state <= FDD_READ_WAIT;
            end else if (fdd_write_finish) begin
                fdd_state <= FDD_DONE_WAIT;
                fdd_cnt <= 15;
            end
        end
        FDD_READ_WAIT: begin
            if (fdd_read_finish) begin
                fdd_state <= FDD_DONE_WAIT;
                fdd_cnt <= 15;
            end
        end
        FDD_DONE_WAIT: begin            // delay 15 cycles before we serve floppy requests again
            fdd_cnt <= fdd_cnt - 1;
            if (fdd_cnt == 0) begin
                fdd_state <= FDD_READY;
            end
        end
    endcase
end

// text display
`ifndef SIM
wire [31:0] reg_char_di = {8'b0, x_wr, y_wr, char_wr};
wire [3:0] reg_char_we = {4{we}};

textdisp #(.COLOR_LOGO(COLOR_LOGO)) disp (
    .clk(clk), .hclk(hclk), .resetn(resetn),
    .x(overlay_x), .y(overlay_y), .color(overlay_color),
    .reg_char_di(reg_char_di), .reg_char_we(reg_char_we)
);
`endif

endmodule
