`timescale 1ns/1ps

// Stand-in for the HDMI serialiser, for simulation only.
//
// snes2hdmi instantiates the hdl-util `hdmi` transmitter, which is built around
// Gowin OSER10 primitives and differential output buffers.  None of that can run
// under Verilator, and none of it needs to for the question this bench asks: the
// serialiser is the one part of the video path this project has already proven on
// hardware, because a build that forced the active area to a constant white drew
// a solid white screen.
//
// So this module keeps the transmitter's *interface* and replaces its body with a
// raster generator.  cx and cy walk the frame exactly as the real one does, the
// frame geometry outputs carry the real 720p numbers, and tmds is left at zero
// because nothing in snes2hdmi reads it.  Everything snes2hdmi does with those
// signals -- deriving xx and yy, reading the line buffer, choosing the colour --
// runs unmodified against this.
module hdmi
#(
    parameter int  VIDEO_ID_CODE = 1,
    parameter bit  IT_CONTENT = 1'b1,
    parameter int  BIT_WIDTH = 11,
    parameter int  BIT_HEIGHT = 10,
    parameter bit  DVI_OUTPUT = 1'b0,
    parameter real VIDEO_REFRESH_RATE = 59.94,
    parameter int  AUDIO_RATE = 44100,
    parameter int  AUDIO_BIT_WIDTH = 16,
    parameter bit [8*8-1:0]   VENDOR_NAME = {"Unknown", 8'd0},
    parameter bit [8*16-1:0]  PRODUCT_DESCRIPTION = {"FPGA", 96'd0},
    parameter bit [7:0] SOURCE_DEVICE_INFORMATION = 8'h00,
    parameter int  START_X = 0,
    parameter int  START_Y = 0
)
(
    input  logic clk_pixel_x5,
    input  logic clk_pixel,
    input  logic clk_audio,
    input  logic reset,
    input  logic [23:0] rgb,
    input  logic [AUDIO_BIT_WIDTH-1:0] audio_sample_word [1:0],

    output logic [2:0] tmds,
    output logic tmds_clock,

    output logic [BIT_WIDTH-1:0]  cx = START_X,
    output logic [BIT_HEIGHT-1:0] cy = START_Y,
    output logic [BIT_WIDTH-1:0]  frame_width,
    output logic [BIT_HEIGHT-1:0] frame_height,
    output logic [BIT_WIDTH-1:0]  screen_width,
    output logic [BIT_HEIGHT-1:0] screen_height
);

    // The same totals snes2hdmi uses for 720p, so xx and yy derive identically.
    localparam int TOTALWIDTH  = 1650;
    localparam int TOTALHEIGHT = 750;

    initial begin
        frame_width  = TOTALWIDTH;
        frame_height = TOTALHEIGHT;
        screen_width = 1280;
        screen_height = 720;
    end

    always @(posedge clk_pixel) begin
        if (reset) begin
            cx <= START_X;
            cy <= START_Y;
        end else begin
            if (cx == TOTALWIDTH - 1) begin
                cx <= 0;
                if (cy == TOTALHEIGHT - 1) cy <= 0;
                else                       cy <= cy + 1'b1;
            end else begin
                cx <= cx + 1'b1;
            end
        end
    end

    assign tmds      = 3'b000;
    assign tmds_clock = 1'b0;

endmodule

// Stand-in for the Gowin differential output buffer.  snes2hdmi drives the TMDS
// lanes through four of these; in simulation the single-ended form is enough.
module ELVDS_OBUF (input I, output O, output OB);
    assign O  = I;
    assign OB = ~I;
endmodule
