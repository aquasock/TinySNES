// Bench for the debug register endpoint: iosys_bl616's frame 0x10 in front of
// tinysnes_dbg, driven over a 2 Mbaud UART exactly as the BL616 drives it.
//
// It checks the reply framing and CRC against an independent model, every
// opcode and error status, the register bank, the knob, a BSRAM peek, a trace
// buffer written by synthetic GSU events, and that a joypad frame sent while a
// reply is pending no longer swallows the reply.  Run with run_dbg_link_sim.sh.

`timescale 1ns/1ps

module dbg_link_tb;

localparam real CLK_NS = 1e9 / 21_484_000.0;
localparam real BIT_NS = 500.0;                 // 2 Mbaud

reg clk = 0;
always #(CLK_NS/2) clk = ~clk;
reg resetn = 0;

reg  uart_rx = 1;
wire uart_tx;
reg  [11:0] joy1 = 0;

wire [31:0] bus_addr, bus_wdata, bus_rdata;
wire        bus_valid, bus_write;

iosys_bl616 #(.CORE_ID(2), .FREQ(21_484_000)) iosys (
    .clk(clk), .hclk(clk), .resetn(resetn),
    .overlay(), .overlay_x(8'd0), .overlay_y(8'd0), .overlay_color(),
    .joy1(joy1), .joy2(12'd0), .hid1(), .hid2(),
    .uart_tx(uart_tx), .uart_rx(uart_rx),
    .rom_loading(), .rom_do(), .rom_do_valid(),
    .debug_address(bus_addr), .debug_wdata(bus_wdata),
    .debug_valid(bus_valid), .debug_write(bus_write), .debug_rdata(bus_rdata)
);

reg  [34:0] gsu_rl = 0;
wire [3:0]  rom_cycles;
wire [16:0] peek_addr;
reg  [7:0]  bsram [0:131071];
reg  [7:0]  bsram_q, wram_q;
always @(posedge clk) begin
    bsram_q <= bsram[peek_addr];
    wram_q  <= ~bsram[peek_addr];
end

tinysnes_dbg #(.TRACE_AW(10)) dbg (
    .clk(clk), .resetn(resetn),
    .bus_addr(bus_addr), .bus_wdata(bus_wdata), .bus_valid(bus_valid),
    .bus_write(bus_write), .bus_rdata(bus_rdata),
    .status(8'h0e), .ev_frame(1'b0), .ev_bsram_wr(1'b0), .ev_rom_req(1'b0),
    .ev_rom_defer(1'b0), .ev_rom_timeout(1'b0),
    .gsu_go_cnt(16'h1234), .gsu_sfr(16'h0020), .gsu_flag_go(1'b0),
    .gsu_pc(24'h01b301), .gsu_state_seen(16'h0), .gsu_romst_seen(7'h0),
    .gsu_romst(3'h0), .gsu_en(1'b0), .gsu_in_cache(1'b0),
    .gsu_rom_cache_wait(1'b0), .gsu_rom_load_wait(1'b0), .gsu_cache_any(1'b0),
    .gsu_rl(gsu_rl), .gsu_op(35'h0), .gsu_mm(33'h0),
    .gsu_rom_cycles(rom_cycles),
    .peek_addr(peek_addr), .bsram_q(bsram_q), .wram_q(wram_q)
);

// ------------------------------------------------------------ host model
function automatic [15:0] crc16(input [15:0] crc, input [7:0] d);
    reg [15:0] v;
    integer i;
    begin
        v = crc ^ {d, 8'h00};
        for (i = 0; i < 8; i = i + 1)
            v = v[15] ? (v << 1) ^ 16'h1021 : v << 1;
        crc16 = v;
    end
endfunction

task automatic send_byte(input [7:0] b);
    integer i;
    begin
        uart_rx = 0; #(BIT_NS);
        for (i = 0; i < 8; i = i + 1) begin uart_rx = b[i]; #(BIT_NS); end
        uart_rx = 1; #(BIT_NS);
    end
endtask

// Receiver: every byte the FPGA sends goes into rxq.
reg [7:0] rxq [0:4095];
integer rx_wr = 0, rx_rd = 0;
initial begin : rx
    integer i;
    reg [7:0] b;
    forever begin
        @(negedge uart_tx);
        #(BIT_NS * 1.5);
        for (i = 0; i < 8; i = i + 1) begin b[i] = uart_tx; #(BIT_NS); end
        rxq[rx_wr] = b;
        rx_wr = rx_wr + 1;
    end
end

task automatic get_byte(output [7:0] b);
    integer guard;
    begin
        guard = 0;
        while (rx_rd == rx_wr) begin
            #(BIT_NS);
            guard = guard + 1;
            if (guard > 400) begin
                $display("FAIL: timeout waiting for a reply byte");
                $finish;
            end
        end
        b = rxq[rx_rd];
        rx_rd = rx_rd + 1;
    end
endtask

integer fails = 0, joy_frames = 0;
reg [15:0] seq = 16'h0100;

// One request, one reply.  Joypad frames in front of the reply are skipped and
// counted, which is what tools/tinysnes_dbg.py does.
task automatic xfer(input [7:0] ver, input [7:0] op, input [31:0] addr,
                    input [31:0] val, input corrupt,
                    output [7:0] st, output [31:0] data);
    reg [7:0] req [0:12];
    reg [7:0] rsp [0:15];
    reg [15:0] c, len;
    reg [7:0] b;
    integer i, got;
    begin
        seq = seq + 1;
        req[0] = 8'h10; req[1] = ver; req[2] = op;
        req[3] = seq[15:8]; req[4] = seq[7:0];
        req[5] = addr[31:24]; req[6] = addr[23:16]; req[7] = addr[15:8]; req[8] = addr[7:0];
        req[9] = val[31:24]; req[10] = val[23:16]; req[11] = val[15:8]; req[12] = val[7:0];
        c = 16'hffff;
        for (i = 0; i < 13; i = i + 1) c = crc16(c, req[i]);
        if (corrupt) c = c ^ 16'h0001;
        send_byte(8'hAA); send_byte(8'h00); send_byte(8'h0f);
        for (i = 0; i < 13; i = i + 1) send_byte(req[i]);
        send_byte(c[15:8]); send_byte(c[7:0]);

        got = 0;
        while (!got) begin
            get_byte(b);
            if (b != 8'hAA) begin
                $display("FAIL: frame start %02x", b); $finish;
            end
            get_byte(b); len[15:8] = b;
            get_byte(b); len[7:0] = b;
            get_byte(b);
            if (b == 8'h03) begin
                for (i = 1; i < len; i = i + 1) get_byte(b);
                joy_frames = joy_frames + 1;
            end else begin
                if (b != 8'h10 || len != 16) begin
                    $display("FAIL: reply type %02x len %0d", b, len); $finish;
                end
                rsp[0] = b;
                for (i = 1; i < 16; i = i + 1) begin get_byte(b); rsp[i] = b; end
                got = 1;
            end
        end

        c = 16'hffff;
        for (i = 0; i < 14; i = i + 1) c = crc16(c, rsp[i]);
        if (c != {rsp[14], rsp[15]}) begin
            $display("FAIL: reply CRC %02x%02x, model %04x", rsp[14], rsp[15], c);
            fails = fails + 1;
        end
        if (rsp[1] != 8'h01 || rsp[2] != (op | 8'h80) || {rsp[4], rsp[5]} != seq
            || {rsp[6], rsp[7], rsp[8], rsp[9]} != addr) begin
            $display("FAIL: reply header ver %02x op %02x seq %02x%02x addr %02x%02x%02x%02x",
                     rsp[1], rsp[2], rsp[4], rsp[5], rsp[6], rsp[7], rsp[8], rsp[9]);
            fails = fails + 1;
        end
        st = rsp[3];
        data = {rsp[10], rsp[11], rsp[12], rsp[13]};
    end
endtask

task automatic check(input [8*24-1:0] what, input [7:0] ver, input [7:0] op,
                      input [31:0] addr, input [31:0] val, input corrupt,
                      input [7:0] want_st, input [31:0] want);
    reg [7:0] st;
    reg [31:0] d;
    begin
        xfer(ver, op, addr, val, corrupt, st, d);
        if (st !== want_st || d !== want) begin
            $display("FAIL: %0s: status %0d data %08x, want %0d %08x", what, st, d, want_st, want);
            fails = fails + 1;
        end else
            $display("ok    %0s: status %0d data %08x", what, st, d);
    end
endtask

task automatic rd(input [31:0] addr, output [31:0] d);
    reg [7:0] st;
    begin
        xfer(8'h01, 8'h01, addr, 32'h0, 0, st, d);
        if (st != 0) begin $display("FAIL: read %08x status %0d", addr, st); fails = fails + 1; end
    end
endtask

initial begin : main
    integer i;
    reg [31:0] d, d0;
    for (i = 0; i < 131072; i = i + 1) bsram[i] = i[7:0] ^ 8'h5a;
    #(CLK_NS * 20);
    resetn = 1;
    #(BIT_NS * 20);

    check("capabilities",     8'h01, 8'h00, 32'h0,  32'h0, 0, 0, 32'h7);
    check("magic",            8'h01, 8'h01, 32'h0,  32'h0, 0, 0, 32'h54534431);
    check("layout",           8'h01, 8'h01, 32'h4,  32'h0, 0, 0, 32'h0001000a);
    check("gsu go/sfr",       8'h01, 8'h01, 32'h20, 32'h0, 0, 0, 32'h12340020);
    check("gsu pc",           8'h01, 8'h01, 32'h24, 32'h0, 0, 0, 32'h0001b301);
    check("status",           8'h01, 8'h01, 32'h10, 32'h0, 0, 0, 32'h0000000e);
    check("write scratch",    8'h01, 8'h02, 32'h44, 32'hcafebabe, 0, 0, 32'hcafebabe);
    check("read scratch",     8'h01, 8'h01, 32'h44, 32'h0, 0, 0, 32'hcafebabe);
    check("bad crc",          8'h01, 8'h02, 32'h44, 32'h11111111, 1, 3, 32'h0);
    check("scratch kept",     8'h01, 8'h01, 32'h44, 32'h0, 0, 0, 32'hcafebabe);
    check("bad version",      8'h02, 8'h01, 32'h0,  32'h0, 0, 1, 32'h0);
    check("bad opcode",       8'h01, 8'h07, 32'h0,  32'h0, 0, 2, 32'h0);
    check("knob write",       8'h01, 8'h02, 32'h40, 32'h5, 0, 0, 32'h5);
    if (rom_cycles !== 4'd5) begin $display("FAIL: knob %0d", rom_cycles); fails = fails + 1; end
    check("knob read",        8'h01, 8'h01, 32'h40, 32'h0, 0, 0, 32'h5);
    check("bsram peek 0x10",  8'h01, 8'h01, 32'h01000010, 32'h0, 0, 0,
           {8'h13 ^ 8'h5a, 8'h12 ^ 8'h5a, 8'h11 ^ 8'h5a, 8'h10 ^ 8'h5a});
    check("bsram peek 1fffc", 8'h01, 8'h01, 32'h0101fffc, 32'h0, 0, 0,
           {8'hff ^ 8'h5a, 8'hfe ^ 8'h5a, 8'hfd ^ 8'h5a, 8'hfc ^ 8'h5a});
    check("wram peek 0x10",   8'h01, 8'h01, 32'h02000010, 32'h0, 0, 0,
           ~{8'h13 ^ 8'h5a, 8'h12 ^ 8'h5a, 8'h11 ^ 8'h5a, 8'h10 ^ 8'h5a});

    // Trace: restart with only the ROM-latch buffer, linear mode, then post
    // 1030 events so the buffer fills and stops at 1024.
    check("trace ctrl",       8'h01, 8'h02, 32'h100, 32'h9, 0, 0, 32'h9);
    for (i = 0; i < 1030; i = i + 1) begin
        @(posedge clk) gsu_rl <= {1'b1, 2'd2, 3'b0, 21'(i * 3), 8'(i)};
        @(posedge clk) gsu_rl <= 0;
    end
    check("trace rl status",  8'h01, 8'h01, 32'h110, 32'h0, 0, 0, 32'h40000000);
    check("trace rl seen",    8'h01, 8'h01, 32'h120, 32'h0, 0, 0, 32'd1030);
    check("trace op status",  8'h01, 8'h01, 32'h114, 32'h0, 0, 0, 32'h0);
    check("rl[0] payload",    8'h01, 8'h01, 32'h10004, 32'h0, 0, 0, {3'b0, 21'd0, 8'd0});
    check("rl[700] payload",  8'h01, 8'h01, 32'h10000 + 700*8 + 4, 32'h0, 0, 0,
           {3'b0, 21'(700*3), 8'(700)});
    rd(32'h10000 + 1023*8, d);
    rd(32'h10000 + 1022*8, d0);
    if (d[31:28] !== 4'b0010 || d[27:0] - d0[27:0] !== 28'd2) begin
        $display("FAIL: rl entry tags/timestamps %08x %08x", d0, d); fails = fails + 1;
    end else
        $display("ok    rl[1022..1023] word0 %08x %08x", d0, d);

    // A joypad change lands while the reply is pending: the reply must still
    // arrive, after the joypad frame.
    fork
        check("read under joypad", 8'h01, 8'h01, 32'h44, 32'h0, 0, 0, 32'hcafebabe);
        begin #(BIT_NS * 10 * 17); joy1 = 12'h001; end
    join
    if (joy_frames == 0) begin $display("FAIL: no joypad frame seen"); fails = fails + 1; end

    if (fails == 0) $display("PASS (%0d joypad frames skipped)", joy_frames);
    else            $display("FAIL: %0d checks", fails);
    $finish;
end

endmodule
