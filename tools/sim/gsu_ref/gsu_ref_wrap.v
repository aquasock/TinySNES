// Generated sim-only wrapper: GSU port list around ref, with a register trace.
module GSU(
    input CLK,
    input RST_N,
    input ENABLE,
    input [23:0] ADDR,
    input [7:0] DI,
    output [7:0] DO,
    input RD_N,
    input WR_N,
    input SYSCLKF_CE,
    input SYSCLKR_CE,
    input TURBO,
    output IRQ_N,
    output [20:0] ROM_A,
    input [7:0] ROM_DI,
    output ROM_RD_N,
    input ROM_RDY,          // unused: the reference latches after its own count
    output [16:0] RAM_A,
    input [7:0] RAM_DI,
    output [7:0] RAM_DO,
    output RAM_WE_N,
    output RAM_CE_N,
    output [15:0] DBG_GO_CNT,
    output DBG_FLAG_GO,
    output DBG_CACHE_ANY,
    output DBG_EN,
    output [2:0] DBG_ROMST,
    output DBG_IN_CACHE,
    output DBG_ROM_CACHE_WAIT,
    output DBG_ROM_LOAD_WAIT,
    output DBG_CACHE_FILL_SEEN,
    output DBG_CACHE_MMIO_SEEN,
    output [6:0] DBG_ROMST_SEEN,
    output [7:0] DBG_SFR_LO_LAST,
    output DBG_SFR_LO_READ,
    output DBG_SFR31_RD_WHILE_SET,
    output DBG_RESTART_AFTER,
    output [7:0] DBG_GO_WRITES,
    output [15:0] DBG_SFR,
    output [15:0] DBG_STATE_SEEN,
    output DBG_FLAG_GO_INT,
    output DBG_FLAG_R_INT,
    output DBG_STOP_SEEN,
    output [7:0] DBG_CF_ADDR,
    output [7:0] DBG_CF_B0,
    output [7:0] DBG_CF_B1,
    output [7:0] DBG_CF_B2,
    output [7:0] DBG_CF_B3,
    output [7:0] DBG_FIRST_OP,
    output DBG_CACHE_EN,
    output DBG_FETCH_OP_SEEN,
    output [23:0] DBG_PC,
    output [34:0] DBG_RL,
    output [34:0] DBG_OP,
    output [32:0] DBG_MM,
    input [3:0] DBG_ROM_CYCLES
);
GSU_ref u_ref(
    .CLK(CLK),
    .RST_N(RST_N),
    .ENABLE(ENABLE),
    .ADDR(ADDR),
    .DI(DI),
    .DO(DO),
    .RD_N(RD_N),
    .WR_N(WR_N),
    .SYSCLKF_CE(SYSCLKF_CE),
    .SYSCLKR_CE(SYSCLKR_CE),
    .TURBO(TURBO),
    .IRQ_N(IRQ_N),
    .ROM_A(ROM_A),
    .ROM_DI(ROM_DI),
    .ROM_RD_N(ROM_RD_N),
    .RAM_A(RAM_A),
    .RAM_DI(RAM_DI),
    .RAM_DO(RAM_DO),
    .RAM_WE_N(RAM_WE_N),
    .RAM_CE_N(RAM_CE_N),
    .DBG_IN_CACHE(DBG_IN_CACHE),
    .DBG_GO_CNT(DBG_GO_CNT));
assign DBG_FLAG_GO = 0;
assign DBG_CACHE_ANY = 0;
assign DBG_EN = 0;
assign DBG_ROMST = 0;
assign DBG_ROM_CACHE_WAIT = 0;
assign DBG_ROM_LOAD_WAIT = 0;
assign DBG_CACHE_FILL_SEEN = 0;
assign DBG_CACHE_MMIO_SEEN = 0;
assign DBG_ROMST_SEEN = 0;
assign DBG_SFR_LO_LAST = 0;
assign DBG_SFR_LO_READ = 0;
assign DBG_SFR31_RD_WHILE_SET = 0;
assign DBG_RESTART_AFTER = 0;
assign DBG_GO_WRITES = 0;
assign DBG_SFR = 0;
assign DBG_STATE_SEEN = 0;
assign DBG_FLAG_GO_INT = 0;
assign DBG_FLAG_R_INT = 0;
assign DBG_STOP_SEEN = 0;
assign DBG_CF_ADDR = 0;
assign DBG_CF_B0 = 0;
assign DBG_CF_B1 = 0;
assign DBG_CF_B2 = 0;
assign DBG_CF_B3 = 0;
assign DBG_FIRST_OP = 0;
assign DBG_CACHE_EN = 0;
assign DBG_FETCH_OP_SEEN = 0;
assign DBG_PC = 0;
assign DBG_RL = 0;
assign DBG_OP = 0;
assign DBG_MM = 0;
wire [255:0] rnow = u_ref.r;

// +rtrace=path +rtracejob=N: log R0-R15 on every change while start N runs.
reg [4095:0] rtrace_path;
integer rtrace_fd = 0, rtrace_job = -1, rk;
reg [255:0] rprev = 0;
initial begin
    rtrace_path = 0;
    void'($value$plusargs("rtracejob=%d", rtrace_job));
    if ($value$plusargs("rtrace=%s", rtrace_path)) rtrace_fd = $fopen(rtrace_path, "w");
end
always @(posedge CLK) begin
    if (rtrace_fd != 0 && DBG_GO_CNT == rtrace_job[15:0] && rnow != rprev) begin
        rprev <= rnow;
        for (rk = 0; rk < 16; rk = rk + 1) $fwrite(rtrace_fd, "%04x ", rnow[rk*16 +: 16]);
        $fwrite(rtrace_fd, "\n");
    end
end

endmodule
