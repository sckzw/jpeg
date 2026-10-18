`timescale 1ns/1ps

module dma_tb;
  reg clk = 0;
  reg rst_n = 0;
  reg start = 0;
  reg stop_request = 0;
  reg r_complete = 0;
  reg w_complete = 0;

  reg r_req_valid = 0;
  wire r_req_ready;
  reg [63:0] r_req_addr = 0;
  reg [3:0] r_req_len = 0;
  reg [2:0] r_req_size = 0;
  reg r_req_last = 0;

  wire r_valid;
  reg r_ready = 0;
  wire [63:0] r_data;
  wire [7:0] r_keep;
  wire r_last;
  wire r_idle;
  wire r_done;
  wire r_error;
  wire [7:0] r_code;
  wire [3:0] r_count;

  reg w_req_valid = 0;
  wire w_req_ready;
  reg [63:0] w_req_addr = 0;
  reg [3:0] w_req_len = 0;
  reg [2:0] w_req_size = 0;
  reg w_req_last = 0;
  reg [63:0] output_limit = 0;

  reg w_valid = 0;
  wire w_ready;
  reg [63:0] w_data = 0;
  reg [7:0] w_keep = 0;
  reg w_last = 0;
  wire w_idle;
  wire w_done;
  wire w_error;
  wire [7:0] w_code;
  wire [3:0] w_count;
  wire [63:0] output_bytes;

  wire [0:0] m_axi_arid;
  wire [63:0] m_axi_araddr;
  wire [7:0] m_axi_arlen;
  wire [2:0] m_axi_arsize;
  wire [1:0] m_axi_arburst;
  wire m_axi_arlock;
  wire [3:0] m_axi_arcache;
  wire [2:0] m_axi_arprot;
  wire [3:0] m_axi_arqos;
  wire m_axi_arvalid;
  reg m_axi_arready = 0;

  reg [0:0] m_axi_rid = 0;
  reg [63:0] m_axi_rdata = 0;
  reg [1:0] m_axi_rresp = 0;
  reg m_axi_rlast = 0;
  reg m_axi_rvalid = 0;
  wire m_axi_rready;

  wire [0:0] m_axi_awid;
  wire [63:0] m_axi_awaddr;
  wire [7:0] m_axi_awlen;
  wire [2:0] m_axi_awsize;
  wire [1:0] m_axi_awburst;
  wire m_axi_awlock;
  wire [3:0] m_axi_awcache;
  wire [2:0] m_axi_awprot;
  wire [3:0] m_axi_awqos;
  wire m_axi_awvalid;
  reg m_axi_awready = 0;

  wire [63:0] m_axi_wdata;
  wire [7:0] m_axi_wstrb;
  wire m_axi_wlast;
  wire m_axi_wvalid;
  reg m_axi_wready = 0;

  reg [0:0] m_axi_bid = 0;
  reg [1:0] m_axi_bresp = 0;
  reg m_axi_bvalid = 0;
  wire m_axi_bready;

  dma_top #(.ADDR_W(64), .ID_W(1)) dut (
    .clk(clk),
    .rst_n(rst_n),
    .start(start),
    .stop_request(stop_request),
    .r_complete(r_complete),
    .w_complete(w_complete),
    .r_req_valid(r_req_valid),
    .r_req_ready(r_req_ready),
    .r_req_addr(r_req_addr),
    .r_req_len(r_req_len),
    .r_req_size(r_req_size),
    .r_req_last(r_req_last),
    .r_valid(r_valid),
    .r_ready(r_ready),
    .r_data(r_data),
    .r_keep(r_keep),
    .r_last(r_last),
    .r_idle(r_idle),
    .r_done(r_done),
    .r_error(r_error),
    .r_code(r_code),
    .r_count(r_count),
    .w_req_valid(w_req_valid),
    .w_req_ready(w_req_ready),
    .w_req_addr(w_req_addr),
    .w_req_len(w_req_len),
    .w_req_size(w_req_size),
    .w_req_last(w_req_last),
    .output_limit(output_limit),
    .w_valid(w_valid),
    .w_ready(w_ready),
    .w_data(w_data),
    .w_keep(w_keep),
    .w_last(w_last),
    .w_idle(w_idle),
    .w_done(w_done),
    .w_error(w_error),
    .w_code(w_code),
    .w_count(w_count),
    .output_bytes(output_bytes),
    .m_axi_arid(m_axi_arid),
    .m_axi_araddr(m_axi_araddr),
    .m_axi_arlen(m_axi_arlen),
    .m_axi_arsize(m_axi_arsize),
    .m_axi_arburst(m_axi_arburst),
    .m_axi_arlock(m_axi_arlock),
    .m_axi_arcache(m_axi_arcache),
    .m_axi_arprot(m_axi_arprot),
    .m_axi_arqos(m_axi_arqos),
    .m_axi_arvalid(m_axi_arvalid),
    .m_axi_arready(m_axi_arready),
    .m_axi_rid(m_axi_rid),
    .m_axi_rdata(m_axi_rdata),
    .m_axi_rresp(m_axi_rresp),
    .m_axi_rlast(m_axi_rlast),
    .m_axi_rvalid(m_axi_rvalid),
    .m_axi_rready(m_axi_rready),
    .m_axi_awid(m_axi_awid),
    .m_axi_awaddr(m_axi_awaddr),
    .m_axi_awlen(m_axi_awlen),
    .m_axi_awsize(m_axi_awsize),
    .m_axi_awburst(m_axi_awburst),
    .m_axi_awlock(m_axi_awlock),
    .m_axi_awcache(m_axi_awcache),
    .m_axi_awprot(m_axi_awprot),
    .m_axi_awqos(m_axi_awqos),
    .m_axi_awvalid(m_axi_awvalid),
    .m_axi_awready(m_axi_awready),
    .m_axi_wdata(m_axi_wdata),
    .m_axi_wstrb(m_axi_wstrb),
    .m_axi_wlast(m_axi_wlast),
    .m_axi_wvalid(m_axi_wvalid),
    .m_axi_wready(m_axi_wready),
    .m_axi_bid(m_axi_bid),
    .m_axi_bresp(m_axi_bresp),
    .m_axi_bvalid(m_axi_bvalid),
    .m_axi_bready(m_axi_bready)
  );

  typedef struct {
    longint addr;
    longint due;
    int len;
    int size;
    int beat;
  } read_t;

  typedef struct {
    longint addr;
    int len;
    int size;
    int beat;
  } write_t;

  typedef struct {
    bit [63:0] data;
    bit [7:0] strb;
    bit last;
    longint cycle;
  } beat_t;

  typedef struct {
    bit [63:0] data;
    int keep;
    bit last;
  } rx_beat_t;

  byte mem[0:(1<<22)-1];
  rx_beat_t received_q[$];
  read_t reads_q[$];
  write_t writes_q[$];
  beat_t beats_q[$];
  longint responses_q[$];

  int latency = 128;
  longint cycle_cnt = 0;
  reg [31:0] rng = 32'd20261005;
  bit random_ready = 1;
  bit ar_block = 0;
  bit aw_block = 0;
  bit w_block = 0;
  int read_error = 0;
  int write_error = 0;
  int max_rd = 0;
  int max_wr = 0;

  function automatic [31:0] rand32;
    rng = rng ^ (rng << 13);
    rng = rng ^ (rng >> 17);
    rng = rng ^ (rng << 5);
    return rng;
  endfunction

  function automatic bit [7:0] pattern(input longint address);
    longint v;
    v = ((address * 73) ^ (address >> 5) ^ 64'h5a) & 64'hff;
    return v[7:0];
  endfunction

  function automatic bit [63:0] word_pattern(input longint address);
    bit [63:0] v = 0;
    for (int i = 0; i < 8; i++) begin
      v |= ({56'd0, pattern(address + i)} << (8 * i));
    end
    return v;
  endfunction

  task automatic bus_tick;
    longint r_addr;
    longint w_addr, w_aligned;
    bit ar, rr, aw, ww, bb;
    read_t r;
    write_t w;
    beat_t b;
    rx_beat_t rx;
    int current_wr;

    clk = 0;
    m_axi_arready = !ar_block && (reads_q.size() < 8) && (!random_ready || ((rand32() % 5) != 0));
    m_axi_awready = !aw_block && ((writes_q.size() + responses_q.size()) < 8) && (!random_ready || ((rand32() % 5) != 0));
    m_axi_wready = !w_block && (beats_q.size() < 128) && (!random_ready || ((rand32() % 5) != 0));

    m_axi_rvalid = (reads_q.size() > 0) && (reads_q[0].due <= cycle_cnt);
    m_axi_rdata = 0;
    m_axi_rid = 0;
    m_axi_rresp = 2'(read_error);
    m_axi_rlast = 0;

    if (m_axi_rvalid) begin
      r = reads_q[0];
      r_addr = r.addr + (longint'(r.beat) << r.size);
      m_axi_rlast = (r.beat == r.len);
      for (int i = 0; i < (1 << r.size); i++) begin
        if (r_addr + i >= (1 << 22)) $fatal(1, "R address out of bounds");
        m_axi_rdata |= ({56'd0, mem[r_addr + i]} << (((r_addr + i) & 7) * 8));
      end
    end

    m_axi_bvalid = (responses_q.size() > 0) && (responses_q[0] <= cycle_cnt);
    m_axi_bid = 0;
    m_axi_bresp = 2'(write_error);

    #1;

    if (r_valid && r_ready) begin
      rx.data = r_data;
      rx.keep = int'(r_keep);
      rx.last = r_last;
      received_q.push_back(rx);
    end

    ar = m_axi_arvalid && m_axi_arready;
    rr = m_axi_rvalid && m_axi_rready;
    aw = m_axi_awvalid && m_axi_awready;
    ww = m_axi_wvalid && m_axi_wready;
    bb = m_axi_bvalid && m_axi_bready;

    r.addr = m_axi_araddr;
    r.due = cycle_cnt + latency;
    r.len = int'(m_axi_arlen);
    r.size = int'(m_axi_arsize);
    r.beat = 0;

    w.addr = m_axi_awaddr;
    w.len = int'(m_axi_awlen);
    w.size = int'(m_axi_awsize);
    w.beat = 0;

    b.data = m_axi_wdata;
    b.strb = m_axi_wstrb;
    b.last = m_axi_wlast;
    b.cycle = cycle_cnt;

    if (ar && (((r.addr & 4095) + ((r.len + 1) << r.size)) > 4096))
      $fatal(1, "read crosses 4K boundary at %08x", r.addr);
    if (aw && (((w.addr & 4095) + ((w.len + 1) << w.size)) > 4096))
      $fatal(1, "write crosses 4K boundary at %08x", w.addr);

    clk = 1; #1;
    cycle_cnt++;

    if (rr) begin
      reads_q[0].beat++;
      if (reads_q[0].beat > reads_q[0].len) void'(reads_q.pop_front());
    end
    if (ar) reads_q.push_back(r);
    if (aw) writes_q.push_back(w);
    if (ww) beats_q.push_back(b);
    if (bb) void'(responses_q.pop_front());

    while ((writes_q.size() > 0) && (beats_q.size() > 0)) begin
      write_t cur_w = writes_q[0];
      beat_t cur_b = beats_q.pop_front();
      w_addr = cur_w.addr + (longint'(cur_w.beat) << cur_w.size);
      w_aligned = w_addr & ~64'd7;

      if (cur_b.last !== (cur_w.beat == cur_w.len))
        $fatal(1, "WLAST mismatch");

      for (int i = 0; i < 8; i++) begin
        if (cur_b.strb[i]) begin
          if (w_aligned + i >= (1 << 22)) $fatal(1, "W address out of bounds");
          mem[w_aligned + i] = byte'((cur_b.data >> (i * 8)) & 64'hff);
        end
      end

      writes_q[0].beat++;
      if (writes_q[0].beat > writes_q[0].len) begin
        responses_q.push_back(cur_b.cycle + latency);
        void'(writes_q.pop_front());
      end
    end

    if (reads_q.size() > max_rd) max_rd = reads_q.size();
    current_wr = writes_q.size() + responses_q.size();
    if (current_wr > max_wr) max_wr = current_wr;
  endtask

  task automatic bus_reset;
    rst_n = 0;
    start = 0;
    stop_request = 0;
    r_req_valid = 0;
    w_req_valid = 0;
    w_valid = 0;
    r_complete = 0;
    w_complete = 0;
    r_ready = 0;
    repeat (3) bus_tick();
    rst_n = 1;
    bus_tick();
  endtask

  task automatic run_dma_test(input int lat);
    int issued, returned, wissued, wsent;
    bit filling;
    bit ar_h, rr_h, aw_h, ww_h;
    rx_beat_t cur_rx;
    int cycle;

    latency = lat;
    cycle_cnt = 0;
    max_rd = 0;
    max_wr = 0;
    reads_q.delete();
    writes_q.delete();
    beats_q.delete();
    responses_q.delete();
    received_q.delete();

    for (int i = 0; i < (1 << 22); i++) mem[i] = 8'ha5;
    bus_reset();

    for (int i = 0; i < 4096; i++) begin
      mem[32'h2000 + i] = pattern(32'h2000 + i);
    end

    start = 1;
    bus_tick();
    start = 0;
    output_limit = 64'd4095;

    issued = 0;
    returned = 0;
    wissued = 0;
    wsent = 0;
    filling = 0;

    cycle = 0;
    while (!(r_done && w_done)) begin
      if (cycle > 20000) $fatal(1, "DMA timeout");

      r_req_valid = (issued < 32);
      r_req_addr = 64'h2000 + issued * 128;
      r_req_len = 4'd15;
      r_req_size = 3'd3;
      r_req_last = (issued == 31);
      r_ready = (rand32() % 4) != 0;
      r_complete = (issued == 32);

      w_req_valid = (wissued < 32) && !filling;
      w_req_addr = 64'h10000 + wissued * 128;
      w_req_len = 4'd15;
      w_req_size = 3'd3;
      w_req_last = (wissued == 31);
      w_complete = (wissued == 32) && !filling;

      w_valid = filling && ((rand32() % 5) != 0);
      w_data = word_pattern(64'h10000 + wsent * 8);
      w_keep = (wsent == 511) ? 8'h7f : 8'hff;
      w_last = (wsent == 511);

      clk = 0; #1;
      ar_h = r_req_valid && r_req_ready;
      rr_h = r_valid && r_ready;
      aw_h = w_req_valid && w_req_ready;
      ww_h = w_valid && w_ready;

      if (r_error || w_error) $fatal(1, "DMA error r_code=%0d w_code=%0d", r_code, w_code);

      bus_tick();

      while (received_q.size() > 0) begin
        cur_rx = received_q.pop_front();
        if (cur_rx.data !== word_pattern(64'h2000 + returned * 8) ||
            cur_rx.keep !== 8'hff ||
            cur_rx.last !== (returned == 511))
          $fatal(1, "read burst payload/last index=%0d got_last=%0d exp_last=%0d",
                 returned, cur_rx.last, (returned == 511));
        returned++;
      end

      if (ar_h) issued++;
      if (aw_h) begin
        wissued++;
        filling = 1;
      end
      if (ww_h) begin
        wsent++;
        if ((wsent % 16) == 0) filling = 0;
      end
      cycle++;
    end

    if (returned != 512 || output_bytes !== 64'd4095 || !r_idle || !w_idle)
      $fatal(1, "DMA completion error: ret=%0d bytes=%0d r_idle=%0d w_idle=%0d",
             returned, output_bytes, r_idle, w_idle);

    for (int i = 0; i < 4096; i++) begin
      byte exp = (i == 4095) ? 8'ha5 : pattern(32'h10000 + i);
      if (mem[32'h10000 + i] !== exp)
        $fatal(1, "DMA written byte mismatch at %08x: got=%02x exp=%02x",
               32'h10000 + i, mem[32'h10000 + i], exp);
    end

    if (max_rd != 8 || (lat == 512 && max_wr != 8))
      $fatal(1, "outstanding slots mismatch max_rd=%0d max_wr=%0d", max_rd, max_wr);

    $display("PASS DMA 32x16-beat read/write bursts latency=%0d max_outstanding=%0d,%0d cycles=%0d",
             lat, max_rd, max_wr, cycle_cnt);
  endtask

  initial begin
    run_dma_test(128);
    run_dma_test(512);
    $finish;
  end
endmodule
