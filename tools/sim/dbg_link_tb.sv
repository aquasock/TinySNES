// Bench for the debug register endpoint: iosys_bl616's frame 0x10 in front of
// tinysnes_dbg, driven over a 2 Mbaud UART exactly as the BL616 drives it.
//
// It checks the reply framing and CRC against an independent model, every
// opcode and error status, the register bank, the knob, a BSRAM peek, a trace
// buffer written by synthetic GSU events, the audio FIFO counters the bank
// gained for the Pmod I2S and HDMI paths, and that a joypad frame sent while a
// reply is pending no longer swallows the reply.  It also drives TinyTang's desk
// frames (0x13 cursor, 0x14 cells, 0x15 enable, 0x08 show) and checks the cell
// writes and desk_on they produce, and checks the joypad report: TinyTang's pad
// word, LB only for a tap of HOME, and the periodic resend.  The report tick is
// shortened to REPORT_CLOCKS so a 20 ms tick is 4.7 us here.  Run with
// run_dbg_link_sim.sh.

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

// Audio FIFO health.  The two toggles stand in for snes2hdmi's overflow and
// underrun flags; the I2S counters are constants because i2s_out already counts
// on mclk and only needs carrying to the bank.
reg  audio_ovf_tog = 1'b0;
reg  audio_unf_tog = 1'b0;
reg         home = 0;
wire        desk_on, desk_wr_tog;
wire [11:0] desk_wr_addr;
wire [36:0] desk_wr_data;
localparam integer REPORT_CLOCKS = 100;

wire [31:0] bus_addr, bus_wdata, bus_rdata;
wire        bus_valid, bus_write;

iosys_bl616 #(.CORE_ID(2), .FREQ(21_484_000), .REPORT_CLOCKS(REPORT_CLOCKS)) iosys (
    .clk(clk), .hclk(clk), .resetn(resetn),
    .overlay(), .overlay_x(8'd0), .overlay_y(8'd0), .overlay_color(),
    .joy1(joy1), .joy2(12'd0), .hid1(), .hid2(), .home(home),
    .desk_on(desk_on), .desk_wr_tog(desk_wr_tog), .desk_wr_addr(desk_wr_addr),
    .desk_wr_data(desk_wr_data),
    .uart_tx(uart_tx), .uart_rx(uart_rx),
    .rom_loading(rom_loading_w), .rom_do(), .rom_do_valid(),
    .sav_addr(sav_addr), .sav_wdata(sav_wdata), .sav_we(sav_we), .sav_rdata(sav_rdata),
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

// The cartridge SRAM as the board's top level models it: one synchronous array
// on the same master clock, chosen by whichever owns the port.
wire        sav_we;
wire [16:0] sav_addr;
wire  [7:0] sav_wdata, sav_rdata;
wire  [7:0] rom_loading_w;
reg  [7:0]  sav_mem [0:131071];
reg  [7:0]  sav_q;
always @(posedge clk) begin
    if (sav_we) sav_mem[sav_addr] <= sav_wdata;
    sav_q <= sav_mem[sav_addr];
end
assign sav_rdata = sav_q;

tinysnes_dbg #(.TRACE_AW(10)) dbg (
    .clk(clk), .resetn(resetn),
    .bus_addr(bus_addr), .bus_wdata(bus_wdata), .bus_valid(bus_valid),
    .bus_write(bus_write), .bus_rdata(bus_rdata),
    .status(8'h0e), .ev_frame(1'b0), .ev_bsram_wr(1'b0), .ev_rom_req(1'b0),
    .ev_rom_defer(1'b0), .ev_rom_timeout(1'b0),
    .audio_ovf_tog(audio_ovf_tog), .audio_unf_tog(audio_unf_tog),
    .i2s_taken(16'h1234), .i2s_overwritten(16'h0002), .i2s_underrun(16'h0007),
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
time rxt [0:4095];                          // when each byte finished
integer rx_wr = 0, rx_rd = 0;
time last_t;                                // rxt of the last byte taken
initial begin : rx
    integer i;
    reg [7:0] b;
    forever begin
        @(negedge uart_tx);
        #(BIT_NS * 1.5);
        for (i = 0; i < 8; i = i + 1) begin b[i] = uart_tx; #(BIT_NS); end
        rxq[rx_wr % 4096] = b;
        rxt[rx_wr % 4096] = $time;
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
        b = rxq[rx_rd % 4096];
        last_t = rxt[rx_rd % 4096];
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

// ------------------------------------------------------------ desk model
// Every cell write iosys makes: the toggle flips with address and data set.
reg [11:0] wr_addr_q [0:63];
reg [36:0] wr_data_q [0:63];
integer wr_n = 0;
reg tog_prev = 0;
always @(posedge clk) begin
    tog_prev <= desk_wr_tog;
    if (desk_wr_tog != tog_prev) begin
        wr_addr_q[wr_n] = desk_wr_addr;
        wr_data_q[wr_n] = desk_wr_data;
        wr_n = wr_n + 1;
    end
end

task automatic frame1(input [7:0] t, input [7:0] b);
    begin
        send_byte(8'hAA); send_byte(8'h00); send_byte(8'h02); send_byte(t); send_byte(b);
    end
endtask

task automatic desk_cursor(input [7:0] x, input [7:0] y);
    begin
        send_byte(8'hAA); send_byte(8'h00); send_byte(8'h03);
        send_byte(8'h13); send_byte(x); send_byte(y);
    end
endtask

// A cell as TinyTang sends it: char, then fg and bg big-endian.
function automatic [39:0] cell_bytes(input [7:0] ch, input [15:0] fg, input [15:0] bg);
    cell_bytes = {ch, fg, bg};
endfunction

task automatic desk_cells(input integer n, input [8*40-1:0] cells);
    integer i;
    reg [15:0] len;
    begin
        len = 1 + 5 * n;
        send_byte(8'hAA); send_byte(len[15:8]); send_byte(len[7:0]); send_byte(8'h14);
        for (i = 5 * n - 1; i >= 0; i = i - 1) send_byte(cells[8*i +: 8]);
    end
endtask

task automatic want_writes(input [8*40-1:0] what, input integer n,
                           input [11:0] a0, input [36:0] d0,
                           input [11:0] a1, input [36:0] d1);
    begin
        #(BIT_NS * 20);
        if (wr_n !== n || (n > 0 && (wr_addr_q[0] !== a0 || wr_data_q[0] !== d0))
                       || (n > 1 && (wr_addr_q[1] !== a1 || wr_data_q[1] !== d1))) begin
            $display("FAIL: %0s: %0d writes, [0] %0d %010x, [1] %0d %010x", what, wr_n,
                     wr_addr_q[0], wr_data_q[0], wr_addr_q[1], wr_data_q[1]);
            fails = fails + 1;
        end else
            $display("ok    %0s: %0d writes", what, wr_n);
        wr_n = 0;
    end
endtask

task automatic want_on(input [8*40-1:0] what, input want);
    begin
        #(BIT_NS * 20);
        if (desk_on !== want) begin
            $display("FAIL: %0s: desk_on %b", what, desk_on); fails = fails + 1;
        end else
            $display("ok    %0s: desk_on %b", what, desk_on);
    end
endtask

// ------------------------------------------------------- battery save model
// A block of `n` bytes from `addr`, with byte i equal to addr[7:0]+i+seed so a
// mistake in the address shows up as a wrong byte rather than a wrong length.
function automatic [7:0] sav_byte(input [23:0] addr, input integer i, input integer seed);
    sav_byte = (addr[7:0] + i[7:0] + seed[7:0]);
endfunction

task automatic save_write(input [23:0] addr, input integer n, input integer seed);
    integer i;
    reg [15:0] len;
    begin
        // frame_len counts the type byte plus the payload: 3 address bytes and
        // n data bytes, so 4 + n.  One short and the receiver drops the last
        // data byte as the start of a new frame.
        len = 4 + n;
        send_byte(8'hAA); send_byte(len[15:8]); send_byte(len[7:0]); send_byte(8'h18);
        send_byte(addr[23:16]); send_byte(addr[15:8]); send_byte(addr[7:0]);
        for (i = 0; i < n; i = i + 1) send_byte(sav_byte(addr, i, seed));
    end
endtask

// Ask for n bytes and check them plus the reply CRC.  `refuse` expects a reply
// carrying no data bytes at all, which is how the core answers when the host is
// not holding it in reset.  Joypad reports that land first are skipped, as
// tools/tinysnes_dbg.py does, because one can arrive while the reply is queued.
task automatic save_read_check(input [8*34-1:0] what, input [23:0] addr,
                               input [7:0] n, input integer seed, input refuse);
    reg [7:0] b;
    reg [15:0] len, c;
    integer i, cnt, bad, done;
    begin
        bad = 0; done = 0;
        send_byte(8'hAA); send_byte(8'h00); send_byte(8'h05); send_byte(8'h19);
        send_byte(addr[23:16]); send_byte(addr[15:8]); send_byte(addr[7:0]); send_byte(n);
        while (!done) begin
            get_byte(b);
            if (b != 8'hAA) begin
                $display("FAIL: %0s: frame start %02x", what, b); $finish;
            end
            get_byte(b); len[15:8] = b;
            get_byte(b); len[7:0] = b;
            get_byte(b);
            if (b == 8'h03) begin
                for (i = 1; i < len; i = i + 1) get_byte(b);
                joy_frames = joy_frames + 1;
            end else if (b != 8'h19) begin
                $display("FAIL: %0s: reply type %02x", what, b);
                bad = 1; done = 1;
            end else begin
                // frame_len counts the type byte, so the payload is len-1 and
                // is the data bytes plus the two CRC bytes.  Checked against
                // the request rather than inferred from `len`, because an
                // inferred expectation agrees with a wrong header.
                if (len != (refuse ? 16'd3 : (n + 16'd3))) begin
                    $display("FAIL: %0s: frame_len %0d, want %0d", what, len,
                             refuse ? 3 : n + 3);
                    bad = 1;
                end
                cnt = len - 1 - 2;
                if (refuse && cnt != 0) begin
                    $display("FAIL: %0s: refused read returned %0d bytes", what, cnt);
                    bad = 1;
                end else if (!refuse && cnt != n) begin
                    $display("FAIL: %0s: %0d bytes, want %0d", what, cnt, n);
                    bad = 1;
                end
                c = crc16(16'hffff, 8'h19);
                for (i = 0; i < cnt; i = i + 1) begin
                    get_byte(b);
                    c = crc16(c, b);
                    if (!refuse && i < n && b !== sav_byte(addr, i, seed)) begin
                        if (bad == 0)
                            $display("FAIL: %0s: byte %0d is %02x, want %02x",
                                     what, i, b, sav_byte(addr, i, seed));
                        bad = 1;
                    end
                end
                get_byte(b);
                if (b !== c[15:8]) begin
                    $display("FAIL: %0s: crc hi %02x, want %02x", what, b, c[15:8]); bad = 1;
                end
                get_byte(b);
                if (b !== c[7:0]) begin
                    $display("FAIL: %0s: crc lo %02x, want %02x", what, b, c[7:0]); bad = 1;
                end
                done = 1;
            end
        end
        if (bad) fails = fails + 1;
        else if (refuse) $display("ok    %0s: refused, no data bytes", what);
        else $display("ok    %0s: %0d bytes", what, n);
    end
endtask

// ------------------------------------------------------------ pad model
// The next unsolicited frame, which must be a joypad report.
task automatic next_pad(output [15:0] j1, output [15:0] j2);
    reg [7:0] b;
    reg [15:0] len;
    begin
        get_byte(b);
        if (b != 8'hAA) begin $display("FAIL: frame start %02x", b); $finish; end
        get_byte(b); len[15:8] = b;
        get_byte(b); len[7:0] = b;
        get_byte(b);
        if (b != 8'h03 || len != 5) begin
            $display("FAIL: unsolicited frame type %02x len %0d", b, len); $finish;
        end
        get_byte(b); j1[15:8] = b;
        get_byte(b); j1[7:0] = b;
        get_byte(b); j2[15:8] = b;
        get_byte(b); j2[7:0] = b;
    end
endtask

// Read reports until one carries `want`, within `limit` reports; any report
// carrying a bit of `never` on the way fails.
task automatic want_pad(input [8*40-1:0] what, input [15:0] want, input [15:0] never,
                        input integer limit);
    reg [15:0] j1, j2;
    integer n;
    begin
        n = 0;
        j1 = ~want;
        while (j1 !== want && n < limit) begin
            next_pad(j1, j2);
            n = n + 1;
            if ((j1 & never) != 0) begin
                $display("FAIL: %0s: report %04x has %04x", what, j1, never); fails = fails + 1;
            end
        end
        if (j1 !== want) begin
            $display("FAIL: %0s: no report of %04x in %0d", what, want, limit); fails = fails + 1;
        end else
            $display("ok    %0s: %04x after %0d report(s)", what, j1, n);
    end
endtask

// How long the reported word carried LB, from iosys's latched report: frame
// timing would add whatever frame was on the wire ahead of the clearing one.
time lb_rise = 0, lb_len = 0;
always @(posedge iosys.joy1_reg[10]) lb_rise = $time;
always @(negedge iosys.joy1_reg[10]) lb_len = $time - lb_rise;

task automatic ticks(input integer n);
    #(CLK_NS * REPORT_CLOCKS * n);
endtask

initial begin : main
    integer i;
    reg [31:0] d, d0;
    reg [15:0] j1, j2;
    time t0;
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

    // Audio FIFO health: a toggle is one lost or starved sample, so two edges on
    // the overflow line must read 2 and one on the underrun line must read 1.
    // (Each toggle is one edge; the RTL counts edges in its own domain.)
    check("audio counters 0", 8'h01, 8'h01, 32'h50, 32'h0, 0, 0, 32'h0);
    check("audio counters 0b", 8'h01, 8'h01, 32'h54, 32'h0, 0, 0, 32'h0);
    check("i2s counters",     8'h01, 8'h01, 32'h58, 32'h0, 0, 0, 32'h00021234);
    check("i2s underrun",     8'h01, 8'h01, 32'h5c, 32'h0, 0, 0, 32'h00000007);
    audio_ovf_tog = 1'b1; #(CLK_NS * 10);
    audio_ovf_tog = 1'b0; #(CLK_NS * 10);
    audio_unf_tog = 1'b1; #(CLK_NS * 10);
    check("audio overflow 2",  8'h01, 8'h01, 32'h50, 32'h0, 0, 0, 32'h2);
    check("audio underrun 1",  8'h01, 8'h01, 32'h54, 32'h0, 0, 0, 32'h1);

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

    // ---- desk frames
    want_on("power-up", 0);
    desk_cursor(8'd3, 8'd2);
    desk_cells(2, {280'd0, cell_bytes(8'h41, 16'h7fff, 16'h0000),
                           cell_bytes(8'hC2, 16'h801f, 16'h7c00)});
    // The top bits of char and colours are not stored.
    want_writes("cells at (3,2)", 2, 12'd163, {7'h41, 15'h7fff, 15'h0000},
                                     12'd164, {7'h42, 15'h001f, 15'h7c00});
    desk_cursor(8'd79, 8'd44);
    desk_cells(2, {280'd0, cell_bytes(8'h20, 16'h1234, 16'h4321),
                           cell_bytes(8'h21, 16'h1111, 16'h2222)});
    want_writes("last cell, then stop", 1, 12'd3599, {7'h20, 15'h1234, 15'h4321}, 0, 0);
    desk_cursor(8'd80, 8'd0);
    desk_cells(1, {320'd0, cell_bytes(8'h20, 16'h0, 16'h0)});
    want_writes("cursor off the grid", 0, 0, 0, 0, 0);
    frame1(8'h15, 8'h01);
    want_on("enabled, not shown", 0);
    frame1(8'h08, 8'h01);
    want_on("enabled and shown", 1);
    frame1(8'h15, 8'h00);
    want_on("disabled", 0);
    frame1(8'h15, 8'h01);
    want_on("re-enabled, still shown", 1);
    check("read after desk",  8'h01, 8'h01, 32'h44, 32'h0, 0, 0, 32'hcafebabe);
    frame1(8'h08, 8'h00);
    want_on("hidden", 0);

    // ---- battery save.  The window is refused unless the loader holds the
    // core in reset, so the refusal comes first and proves the gate.
    save_read_check("read while running", 24'h000100, 8'd16, 0, 1);
    frame1(8'h06, 8'h01);
    #(BIT_NS * 20);
    if (rom_loading_w !== 8'd1) begin
        $display("FAIL: rom_loading %0d after 0x06 0x01", rom_loading_w); fails = fails + 1;
    end else
        $display("ok    loading asserted");
    save_write(24'h000100, 16, 0);
    save_read_check("read back 16", 24'h000100, 8'd16, 0, 0);
    // A block that crosses the 17-bit window, to catch an address that only
    // carries the low byte.
    save_write(24'h01FF00, 4, 3);
    save_read_check("read back 0x1FF00", 24'h01FF00, 8'd4, 3, 0);
    // The largest reply the BL616 frame allows.
    save_write(24'h000000, 250, 7);
    save_read_check("read back 250", 24'h000000, 8'd250, 7, 0);
    // A zero-length read is refused rather than answered with a bare CRC.
    save_read_check("zero length", 24'h000000, 8'd0, 0, 1);
    // The write is what lands in the array, not a read that happened to match.
    if (sav_mem[17'h000100] !== 8'h00 || sav_mem[17'h00010f] !== 8'h0f ||
        sav_mem[17'h01ff00] !== 8'h03) begin
        $display("FAIL: array [100] %02x [10f] %02x [1ff00] %02x",
                 sav_mem[17'h000100], sav_mem[17'h00010f], sav_mem[17'h01ff00]);
        fails = fails + 1;
    end else
        $display("ok    bytes present in the array");
    frame1(8'h06, 8'h00);
    #(BIT_NS * 20);
    save_read_check("read after release", 24'h000100, 8'd16, 0, 1);

    // ---- joypad report.  From here every frame from the FPGA is a report.
    joy1 = 12'h000;
    want_pad("released", 16'h0000, 16'h0000, 30);
    joy1 = 12'h010;                                 // UP
    want_pad("up", 16'h0010, 16'h0000, 3);
    joy1 = 12'h003;                                 // B and Y
    want_pad("B -> A, Y -> B", 16'h0101, 16'h0000, 3);
    joy1 = 12'h0c0;                                 // LEFT and RIGHT
    want_pad("left+right", 16'h00c0, 16'h0000, 3);
    joy1 = 12'h000;
    want_pad("released", 16'h0000, 16'h0000, 3);

    // Raw SNES L is the desk toggle's bit in TinyTang's word: never sent.
    joy1 = 12'h400;
    ticks(3);
    joy1 = 12'h000;
    next_pad(j1, j2);
    if (j1 !== 16'h0000) begin
        $display("FAIL: raw L: report %04x", j1); fails = fails + 1;
    end else
        $display("ok    raw L: not reported; next report (the resend) %04x", j1);

    // HOME held with SELECT is the exit-and-save gesture: bit 15 of the pad
    // word, and no LB, because the chord must not also open the desk.
    home = 1; joy1 = 12'h004; ticks(3);
    want_pad("HOME+SELECT exit", 16'h8000, 16'h0400, 3);
    home = 0; joy1 = 12'h000; ticks(3);
    want_pad("exit released", 16'h0000, 16'h0400, 3);

    // A tap of HOME: LB for 13 ticks, then clear.
    home = 1; ticks(3); home = 0;
    want_pad("HOME tap", 16'h0400, 16'h0000, 2);
    want_pad("tap over", 16'h0000, 16'h0000, 2);
    if (lb_len < CLK_NS * REPORT_CLOCKS * 12.5 || lb_len > CLK_NS * REPORT_CLOCKS * 13.5) begin
        $display("FAIL: tap held %0t", lb_len); fails = fails + 1;
    end else
        $display("ok    tap held %0t (13 ticks)", lb_len);

    // HOME held with another button is a chord, not a tap.
    home = 1; ticks(2); joy1 = 12'h001; ticks(2); home = 0; ticks(2); joy1 = 12'h000;
    want_pad("HOME+B pressed", 16'h0100, 16'h0400, 2);
    want_pad("HOME+B released", 16'h0000, 16'h0400, 2);
    ticks(20);
    next_pad(j1, j2);
    if (j1 !== 16'h0000) begin
        $display("FAIL: HOME chord: later report %04x", j1); fails = fails + 1;
    end else
        $display("ok    HOME chord: no LB");

    // Nothing changes: a report every 25 ticks anyway.
    next_pad(j1, j2);
    t0 = last_t;
    next_pad(j1, j2);
    if (last_t - t0 < CLK_NS * REPORT_CLOCKS * 24 || last_t - t0 > CLK_NS * REPORT_CLOCKS * 26) begin
        $display("FAIL: resend interval %0t", last_t - t0); fails = fails + 1;
    end else
        $display("ok    resend every %0t (25 ticks)", last_t - t0);

    if (fails == 0) $display("PASS (%0d joypad frames skipped)", joy_frames);
    else            $display("FAIL: %0d checks", fails);
    $finish;
end

endmodule
