module GSUMap(
    input MCLK,
    input RST_N,
    input ENABLE,
    input [23:0] CA,
    input [7:0] DI,
    output [7:0] DO,
    input CPURD_N,
    input CPUWR_N,
    input [7:0] PA,
    input PARD_N,
    input PAWR_N,
    input ROMSEL_N,
    input RAMSEL_N,
    input SYSCLKF_CE,
    input SYSCLKR_CE,
    input REFRESH,
    output IRQ_N,
    output [22:0] ROM_ADDR,
    input [15:0] ROM_Q,
    input ROM_RDY,
    output ROM_CE_N,
    output ROM_OE_N,
    output ROM_WORD,
    output [19:0] BSRAM_ADDR,
    output [7:0] BSRAM_D,
    input [7:0] BSRAM_Q,
    output BSRAM_CE_N,
    output BSRAM_OE_N,
    output BSRAM_WE_N,
    output MAP_ACTIVE,
    input [7:0] MAP_CTRL,
    input [23:0] ROM_MASK,
    input [23:0] BSRAM_MASK,
    input TURBO,

    // TinySNES: GSU debug outputs, threaded out so a top-level probe can read
    // them.  See the note in GSU.v's port list.
    output [15:0] DBG_GO_CNT,
    output        DBG_FLAG_GO,
    output        DBG_CACHE_ANY,
    output        DBG_EN,
    output [2:0]  DBG_ROMST,
    output        DBG_IN_CACHE,
    output        DBG_ROM_CACHE_WAIT,
    output        DBG_ROM_LOAD_WAIT,
    output        DBG_CACHE_FILL_SEEN,
    output        DBG_CACHE_MMIO_SEEN,
    output [6:0]  DBG_ROMST_SEEN,
    // What the 65816 actually reads from the SFR low byte, and whether it was
    // ever read while the core already reported the GSU finished.
    output [7:0]  DBG_SFR_LO_LAST,
    output        DBG_SFR_LO_READ,
    output        DBG_SFR31_RD_WHILE_SET,
    output        DBG_RESTART_AFTER,
    output [7:0]  DBG_GO_WRITES,
    output [15:0] DBG_SFR,
    output [15:0] DBG_STATE_SEEN,
    output        DBG_FLAG_GO_INT,
    output        DBG_FLAG_R_INT,
    output        DBG_STOP_SEEN,
    output [7:0]  DBG_CF_ADDR,
    output [7:0]  DBG_CF_B0,
    output [7:0]  DBG_CF_B1,
    output [7:0]  DBG_CF_B2,
    output [7:0]  DBG_CF_B3,
    output [7:0]  DBG_FIRST_OP,
    output        DBG_CACHE_EN,
    output        DBG_FETCH_OP_SEEN,
    // Debug endpoint taps; layouts are documented at GSU.v's port list.
    output [23:0] DBG_PC,
    output [34:0] DBG_RL,
    output [34:0] DBG_OP,
    output [32:0] DBG_MM,
    input  [3:0]  DBG_ROM_CYCLES
);

wire [20:0] ROM_A;
wire [16:0] RAM_A;
wire RAM_WE_N;
wire MAP_SEL;

assign MAP_SEL = MAP_CTRL[7:4] == 4'h7 ? 1'b1 : 1'b0;
assign MAP_ACTIVE = MAP_SEL;

GSU GSU(
    .CLK(MCLK), .RST_N(RST_N & MAP_SEL), .ENABLE(ENABLE),
    .ADDR(CA), .DO(DO), .DI(DI), .RD_N(CPURD_N), .WR_N(CPUWR_N),
    .SYSCLKF_CE(SYSCLKF_CE), .SYSCLKR_CE(SYSCLKR_CE),
    .IRQ_N(IRQ_N), .ROM_A(ROM_A),
    .ROM_DI(ROM_Q[7:0]), .ROM_RD_N(ROM_OE_N), .ROM_RDY(ROM_RDY),
    .RAM_A(RAM_A), .RAM_DI(BSRAM_Q), .RAM_DO(BSRAM_D),
    .RAM_WE_N(RAM_WE_N), .RAM_CE_N(BSRAM_CE_N),
    .TURBO(TURBO),
    .DBG_GO_CNT(DBG_GO_CNT), .DBG_FLAG_GO(DBG_FLAG_GO),
    .DBG_CACHE_ANY(DBG_CACHE_ANY), .DBG_EN(DBG_EN),
    .DBG_ROMST(DBG_ROMST), .DBG_IN_CACHE(DBG_IN_CACHE),
    .DBG_ROM_CACHE_WAIT(DBG_ROM_CACHE_WAIT), .DBG_ROM_LOAD_WAIT(DBG_ROM_LOAD_WAIT),
    .DBG_CACHE_FILL_SEEN(DBG_CACHE_FILL_SEEN), .DBG_CACHE_MMIO_SEEN(DBG_CACHE_MMIO_SEEN),
    .DBG_ROMST_SEEN(DBG_ROMST_SEEN),
    .DBG_SFR_LO_LAST(DBG_SFR_LO_LAST), .DBG_SFR_LO_READ(DBG_SFR_LO_READ),
    .DBG_SFR31_RD_WHILE_SET(DBG_SFR31_RD_WHILE_SET),
    .DBG_RESTART_AFTER(DBG_RESTART_AFTER), .DBG_GO_WRITES(DBG_GO_WRITES),
    .DBG_SFR(DBG_SFR), .DBG_STATE_SEEN(DBG_STATE_SEEN),
    .DBG_FLAG_GO_INT(DBG_FLAG_GO_INT), .DBG_FLAG_R_INT(DBG_FLAG_R_INT),
    .DBG_STOP_SEEN(DBG_STOP_SEEN),
    .DBG_CF_ADDR(DBG_CF_ADDR),
    .DBG_CF_B0(DBG_CF_B0), .DBG_CF_B1(DBG_CF_B1),
    .DBG_CF_B2(DBG_CF_B2), .DBG_CF_B3(DBG_CF_B3),
    .DBG_FIRST_OP(DBG_FIRST_OP),
    .DBG_CACHE_EN(DBG_CACHE_EN),
    .DBG_FETCH_OP_SEEN(DBG_FETCH_OP_SEEN),
    .DBG_PC(DBG_PC), .DBG_RL(DBG_RL), .DBG_OP(DBG_OP), .DBG_MM(DBG_MM),
    .DBG_ROM_CYCLES(DBG_ROM_CYCLES)
);

assign ROM_ADDR = ({2'b00,ROM_A}) & ROM_MASK[22:0];
assign ROM_CE_N = 1'b0;
assign ROM_WORD = 1'b0;
assign BSRAM_ADDR = {4'b0000,RAM_A[15:0]};
assign BSRAM_OE_N =  ~RAM_WE_N;
assign BSRAM_WE_N = RAM_WE_N;

endmodule
