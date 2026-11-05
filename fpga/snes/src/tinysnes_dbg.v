// TinySNES debug register bank, served over the BL616 link by iosys_bl616's
// frame 0x10 (TinyTang `fpgar`, or tools/tinysnes_dbg.py through `fpgapipe`).
//
// Everything here runs on mclk, the clock the GSU, the SNES and iosys share, so
// nothing crosses a clock domain.  The bank observes and has one knob; with the
// knob at its reset value the machine behaves exactly as it does without it.
//
// Register map (byte addresses, 32-bit words, RO unless marked):
//
//   0x000  magic 'TSD1' (0x54534431)
//   0x004  layout {16'h0001, 16'(TRACE_AW)}
//   0x008  frames: vblank starts since reset
//   0x00c  uptime in mclk
//   0x010  board {24'b0, status}
//   0x020  GSU {GO_CNT, SFR}
//   0x024  GSU {8'b0, PBR, R15}
//   0x028  GSU {STATE_SEEN, 1'b0, ROMST_SEEN[6:0], ROMST[2:0], EN, IN_CACHE,
//               ROM_CACHE_WAIT, ROM_LOAD_WAIT, CACHE_ANY}
//   0x02c  GSU stops: FLAG_GO falls since reset
//   0x030  BSRAM write strobes since reset
//   0x034  cartridge SDRAM reads posted
//   0x038  cartridge reads deferred because the CPU port was busy
//   0x03c  cartridge reads that hit the sd_wait_age bound (lost data)
//   0x040  RW knob: GSU ROM_CYCLES override, 1..13; 0 = built-in 9
//   0x044  RW scratch
//   0x048  mclk with FLAG_GO high since reset
//   0x050  HDMI audio FIFO overflows: a sample offered to a full FIFO
//   0x054  HDMI audio FIFO underruns: a read taken from an empty FIFO
//   0x058  Pmod I2S {samples lost to a full FIFO, samples taken}
//          Both are i2s_out's own 16-bit counters, carried through unchanged.
//          The taken count free-runs since reset and saturates at 65535 within
//          about 20 seconds on the board, so it is a delta (take two readings)
//          and not an absolute; the overwritten count is the one to read.
//   0x05c  Pmod I2S resampler underruns
//
//   0x100  RW trace control
//            [0] run     [1] ring (else stop each buffer when full)
//            [2] start on a GSU GO rising edge, after skipping [31:16] of them
//            [3] ROM-latch buffer on   [4] opcode buffer on   [5] MMIO buffer on
//            [6] MMIO buffer also records reads
//          Writing with [0] set restarts all three buffers from empty.
//   0x104  trace state {30'b0, waiting_for_go, recording}
//   0x110 + 4*b  buffer b {wrapped, stopped_full, 14'b0, write_pointer}
//   0x120 + 4*b  buffer b events seen while recording (stored or not)
//
//   0x10000 + b*0x4000 + i*8      entry i of buffer b, word 0 {tag[3:0], ts[27:0]}
//   0x10000 + b*0x4000 + i*8 + 4  entry i of buffer b, payload
//            b 0 ROM latch:  tag {2'b00, kind}  payload {3'b0, ROM_A[20:0], data}
//            b 1 opcode:     tag {2'b01, src}   payload {PBR, R15, opcode}
//            b 2 S-CPU MMIO: tag {3'b100, wr}   payload {wr, 7'b0, addr[15:0], data}
//          ts is mclk, the low 28 bits of 0x00c.  Kinds and sources are as
//          documented at GSU.v's DBG_RL / DBG_OP ports.
//
//   0x01000000 + a  BSRAM bytes a..a+3, little-endian (a is 17 bits, word aligned)
//   0x02000000 + a  WRAM bytes a..a+3, little-endian
//
// Reset state of the trace is run, ring, all buffers, reads included, so a
// board that has just gone wrong can be frozen and read with no setup.

module tinysnes_dbg #(
    parameter TRACE_AW = 10
) (
    input             clk,
    input             resetn,

    input      [31:0] bus_addr,
    input      [31:0] bus_wdata,
    input             bus_valid,
    input             bus_write,
    output reg [31:0] bus_rdata,

    input      [7:0]  status,
    input             ev_frame,
    input             ev_bsram_wr,
    input             ev_rom_req,
    input             ev_rom_defer,
    input             ev_rom_timeout,

    // Audio FIFO health.  Each is a toggle rather than a counter so the source
    // can live in whatever clock domain the fault does; this bank counts edges
    // in its own domain.  See snes2hdmi.v and i2s_out.sv.
    input             audio_ovf_tog,
    input             audio_unf_tog,
    input      [15:0] i2s_taken,
    input      [15:0] i2s_overwritten,
    input      [15:0] i2s_underrun,

    input      [15:0] gsu_go_cnt,
    input      [15:0] gsu_sfr,
    input             gsu_flag_go,
    input      [23:0] gsu_pc,
    input      [15:0] gsu_state_seen,
    input      [6:0]  gsu_romst_seen,
    input      [2:0]  gsu_romst,
    input             gsu_en,
    input             gsu_in_cache,
    input             gsu_rom_cache_wait,
    input             gsu_rom_load_wait,
    input             gsu_cache_any,
    input      [34:0] gsu_rl,
    input      [34:0] gsu_op,
    input      [32:0] gsu_mm,

    output reg [3:0]  gsu_rom_cycles,

    output     [16:0] peek_addr,
    input      [7:0]  bsram_q,
    input      [7:0]  wram_q
);

localparam [31:0] MAGIC = 32'h54534431;
localparam DEPTH = 1 << TRACE_AW;

wire wr = bus_valid & bus_write;

// ---------------------------------------------------------------- counters
reg [31:0] uptime = 0, frames = 0, stops = 0, bsram_wrs = 0;
reg [31:0] rom_reqs = 0, rom_defers = 0, rom_timeouts = 0, go_time = 0;
reg [31:0] scratch = 0;
reg        flag_go_r = 1'b0;

// Audio FIFO health, counted from toggles.  Three flops per source: the first
// captures a possibly metastable edge and the last two give a stable
// comparison, so one visible edge is one lost or starved sample.
reg [15:0] audio_ovf = 0, audio_unf = 0;
reg        ovf_s1 = 1'b0, ovf_s2 = 1'b0, ovf_s3 = 1'b0;
reg        unf_s1 = 1'b0, unf_s2 = 1'b0, unf_s3 = 1'b0;

always @(posedge clk) begin
    if (~resetn) begin
        uptime <= 0; frames <= 0; stops <= 0; bsram_wrs <= 0;
        rom_reqs <= 0; rom_defers <= 0; rom_timeouts <= 0; go_time <= 0;
        scratch <= 0; gsu_rom_cycles <= 4'd0; flag_go_r <= 1'b0;
        audio_ovf <= 0; audio_unf <= 0;
        ovf_s1 <= 1'b0; ovf_s2 <= 1'b0; ovf_s3 <= 1'b0;
        unf_s1 <= 1'b0; unf_s2 <= 1'b0; unf_s3 <= 1'b0;
    end else begin
        uptime <= uptime + 1;
        flag_go_r <= gsu_flag_go;
        if (ev_frame)       frames <= frames + 1;
        if (flag_go_r & ~gsu_flag_go) stops <= stops + 1;
        if (gsu_flag_go)    go_time <= go_time + 1;
        if (ev_bsram_wr)    bsram_wrs <= bsram_wrs + 1;
        if (ev_rom_req)     rom_reqs <= rom_reqs + 1;
        if (ev_rom_defer)   rom_defers <= rom_defers + 1;
        if (ev_rom_timeout) rom_timeouts <= rom_timeouts + 1;
        if (wr && bus_addr == 32'h40) gsu_rom_cycles <= bus_wdata[3:0];
        if (wr && bus_addr == 32'h44) scratch <= bus_wdata;

        ovf_s1 <= audio_ovf_tog; ovf_s2 <= ovf_s1; ovf_s3 <= ovf_s2;
        unf_s1 <= audio_unf_tog; unf_s2 <= unf_s1; unf_s3 <= unf_s2;
        if ((ovf_s2 ^ ovf_s3) && (audio_ovf != 16'hFFFF))
            audio_ovf <= audio_ovf + 16'd1;
        if ((unf_s2 ^ unf_s3) && (audio_unf != 16'hFFFF))
            audio_unf <= audio_unf + 16'd1;
    end
end

// ------------------------------------------------------------------- trace
localparam [31:0] CTRL_RESET = 32'h0000_007b;
reg  [31:0] ctrl = CTRL_RESET;
reg         waiting = 1'b0;
reg  [15:0] skip_left = 16'd0;
wire        recording = ctrl[0] & ~waiting;
wire        go_rise = gsu_flag_go & ~flag_go_r;
wire        restart = wr && bus_addr == 32'h100 && bus_wdata[0];

always @(posedge clk) begin
    if (~resetn) begin
        ctrl <= CTRL_RESET;
        waiting <= 1'b0;
        skip_left <= 16'd0;
    end else if (wr && bus_addr == 32'h100) begin
        ctrl <= bus_wdata;
        waiting <= bus_wdata[0] & bus_wdata[2];
        skip_left <= bus_wdata[31:16];
    end else if (waiting && go_rise) begin
        if (skip_left == 16'd0)
            waiting <= 1'b0;
        else
            skip_left <= skip_left - 16'd1;
    end
end

wire        mm_take = gsu_mm[32] & (gsu_mm[31] | ctrl[6]);
wire [2:0]  ev_hit  = {mm_take & ctrl[5], gsu_op[34] & ctrl[4], gsu_rl[34] & ctrl[3]};
wire [63:0] ev_word [0:2];
assign ev_word[0] = {2'b00, gsu_rl[33:32], uptime[27:0], gsu_rl[31:0]};
assign ev_word[1] = {2'b01, gsu_op[33:32], uptime[27:0], gsu_op[31:0]};
assign ev_word[2] = {3'b100, gsu_mm[31], uptime[27:0], gsu_mm[31:0]};

wire [TRACE_AW-1:0] rd_index = bus_addr[TRACE_AW+2:3];
wire [63:0]         tr_q [0:2];
reg  [TRACE_AW-1:0] wp [0:2];
reg  [2:0]          wrapped, full;
reg  [31:0]         seen [0:2];

genvar b;
generate for (b = 0; b < 3; b = b + 1) begin : trace
    wire take = recording & ev_hit[b] & ~full[b];

    tsd_ram #(.AW(TRACE_AW), .DW(64)) ram (
        .clk(clk), .we(take), .wa(wp[b]), .wd(ev_word[b]),
        .ra(rd_index), .rd(tr_q[b])
    );

    always @(posedge clk) begin
        if (~resetn || restart) begin
            wp[b] <= 0;
            wrapped[b] <= 1'b0;
            full[b] <= 1'b0;
            seen[b] <= 0;
        end else begin
            if (recording & ev_hit[b])
                seen[b] <= seen[b] + 1;
            if (take) begin
                wp[b] <= wp[b] + 1'b1;
                if (wp[b] == DEPTH - 1) begin
                    if (ctrl[1]) wrapped[b] <= 1'b1;
                    else         full[b] <= 1'b1;
                end
            end
        end
    end
end endgenerate

// -------------------------------------------------------------------- peek
// The two RAMs' debug read ports share one address that walks the four bytes
// of the addressed word continuously, so the packed word is current a few
// clocks after bus_addr changes -- long before iosys samples bus_rdata.
reg  [1:0]  peek_lane = 2'd0, peek_lane_r = 2'd0;
reg  [31:0] peek_bs = 0, peek_wr = 0;
assign peek_addr = {bus_addr[16:2], peek_lane};

always @(posedge clk) begin
    peek_lane <= peek_lane + 2'd1;
    peek_lane_r <= peek_lane;
    peek_bs[8*peek_lane_r +: 8] <= bsram_q;
    peek_wr[8*peek_lane_r +: 8] <= wram_q;
end

// ------------------------------------------------------------------- reads
wire [1:0] tr_sel = bus_addr[15:14];
wire [63:0] tr_word = tr_sel == 2'd0 ? tr_q[0] : tr_sel == 2'd1 ? tr_q[1] : tr_q[2];

always @(posedge clk) begin
    if (bus_addr[31:24] == 8'h01)
        bus_rdata <= peek_bs;
    else if (bus_addr[31:24] == 8'h02)
        bus_rdata <= peek_wr;
    else if (bus_addr[31:16] == 16'h0001)
        bus_rdata <= tr_sel == 2'd3 ? 32'h0 : bus_addr[2] ? tr_word[31:0] : tr_word[63:32];
    else case (bus_addr[15:0])
        16'h000: bus_rdata <= MAGIC;
        16'h004: bus_rdata <= {16'h0001, 16'(TRACE_AW)};
        16'h008: bus_rdata <= frames;
        16'h00c: bus_rdata <= uptime;
        16'h010: bus_rdata <= {24'b0, status};
        16'h020: bus_rdata <= {gsu_go_cnt, gsu_sfr};
        16'h024: bus_rdata <= {8'b0, gsu_pc};
        16'h028: bus_rdata <= {gsu_state_seen, 1'b0, gsu_romst_seen, gsu_romst, gsu_en,
                               gsu_in_cache, gsu_rom_cache_wait, gsu_rom_load_wait, gsu_cache_any};
        16'h02c: bus_rdata <= stops;
        16'h030: bus_rdata <= bsram_wrs;
        16'h034: bus_rdata <= rom_reqs;
        16'h038: bus_rdata <= rom_defers;
        16'h03c: bus_rdata <= rom_timeouts;
        16'h040: bus_rdata <= {28'b0, gsu_rom_cycles};
        16'h044: bus_rdata <= scratch;
        16'h048: bus_rdata <= go_time;
        16'h050: bus_rdata <= {16'b0, audio_ovf};
        16'h054: bus_rdata <= {16'b0, audio_unf};
        16'h058: bus_rdata <= {i2s_overwritten, i2s_taken};
        16'h05c: bus_rdata <= {16'b0, i2s_underrun};
        16'h100: bus_rdata <= ctrl;
        16'h104: bus_rdata <= {30'b0, waiting, recording};
        16'h110: bus_rdata <= {wrapped[0], full[0], 14'b0, 16'(wp[0])};
        16'h114: bus_rdata <= {wrapped[1], full[1], 14'b0, 16'(wp[1])};
        16'h118: bus_rdata <= {wrapped[2], full[2], 14'b0, 16'(wp[2])};
        16'h120: bus_rdata <= seen[0];
        16'h124: bus_rdata <= seen[1];
        16'h128: bus_rdata <= seen[2];
        default: bus_rdata <= 32'hDEAD_0000 | {16'b0, bus_addr[15:0]};
    endcase
end

endmodule

// One trace buffer: a simple dual-port block RAM, one write and one registered
// read on the same clock.
module tsd_ram #(
    parameter AW = 10,
    parameter DW = 64
) (
    input               clk,
    input               we,
    input      [AW-1:0] wa,
    input      [DW-1:0] wd,
    input      [AW-1:0] ra,
    output reg [DW-1:0] rd
);
reg [DW-1:0] m [0:(1<<AW)-1];
always @(posedge clk) begin
    if (we) m[wa] <= wd;
    rd <= m[ra];
end
endmodule
