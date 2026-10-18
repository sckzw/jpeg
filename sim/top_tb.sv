`timescale 1ns/1ps
`include "jpeg_defs.vh"

module top_tb;
  reg clk = 0;
  reg rst_n = 0;

  reg psel = 0;
  reg penable = 0;
  reg pwrite = 0;
  reg [11:0] paddr = 0;
  reg [31:0] pwdata = 0;
  wire [31:0] prdata;
  wire pready;
  wire pslverr;

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

  jpeg_top #(.ADDR_W(64), .ID_W(1)) dut (
    .clk(clk),
    .rst_n(rst_n),
    .psel(psel),
    .penable(penable),
    .pwrite(pwrite),
    .paddr(paddr),
    .pwdata(pwdata),
    .prdata(prdata),
    .pready(pready),
    .pslverr(pslverr),
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
    longint accepted;
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
    longint ar_wait;
    longint aw_wait;
    longint w_wait;
    longint r_wait;
    longint t_wait;
    longint q_wait;
    longint e_wait;
    int input_peak;
    int output_peak;
    int reserved_peak;
    longint read_delay_sum;
    longint read_count;
  } stats_t;

  typedef struct {
    string name;
    int w;
    int h;
    int fmt;
    int q;
  } vector_t;

  byte mem[0:(128*1024*1024)-1];
  read_t reads_q[$];
  write_t writes_q[$];
  beat_t beats_q[$];
  longint responses_q[$];

  longint cycle_cnt = 0;
  reg [31:0] rng = 32'd20261005;
  bit variable_delay = 0;
  longint delay_sum = 0;
  longint delay_count = 0;
  bit random_ready = 1;
  bit ar_block = 0;
  bit aw_block = 0;
  bit w_block = 0;
  int read_error = 0;
  int write_error = 0;
  int max_rd = 0;
  int max_wr = 0;
  stats_t stats;

  function automatic [31:0] rand32;
    rng = rng ^ (rng << 13);
    rng = rng ^ (rng >> 17);
    rng = rng ^ (rng << 5);
    return rng;
  endfunction

  localparam real CLK_HALF_PERIOD = 1.953125; // 256 MHz clock: Period = 3.90625 ns

  task automatic bus_tick;
    longint r_addr, w_addr, w_aligned;
    bit ar, rr, aw, ww, bb;
    int rdelay, bdelay;
    read_t r;
    write_t w;
    beat_t b;
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
        if (r_addr + i >= (128 * 1024 * 1024)) $fatal(1, "R address out of bounds: %08x", r_addr + i);
        m_axi_rdata |= ({56'd0, mem[r_addr + i]} << (((r_addr + i) & 7) * 8));
      end
    end

    m_axi_bvalid = (responses_q.size() > 0) && (responses_q[0] <= cycle_cnt);
    m_axi_bid = 0;
    m_axi_bresp = 2'(write_error);

    #(CLK_HALF_PERIOD);

    ar = m_axi_arvalid && m_axi_arready;
    rr = m_axi_rvalid && m_axi_rready;
    aw = m_axi_awvalid && m_axi_awready;
    ww = m_axi_wvalid && m_axi_wready;
    bb = m_axi_bvalid && m_axi_bready;

    rdelay = variable_delay ? (64 + int'(rand32() % 129)) : 128;
    r.addr = m_axi_araddr;
    r.due = cycle_cnt + rdelay;
    r.len = int'(m_axi_arlen);
    r.size = int'(m_axi_arsize);
    r.beat = 0;
    r.accepted = cycle_cnt;

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

    stats.ar_wait += (m_axi_arvalid && !m_axi_arready);
    stats.aw_wait += (m_axi_awvalid && !m_axi_awready);
    stats.w_wait += (m_axi_wvalid && !m_axi_wready);
    stats.r_wait += (m_axi_rvalid && !m_axi_rready);
    stats.t_wait += (dut.t_sv && !dut.t_sr);
    stats.q_wait += (dut.q_sv && !dut.q_sr);
    stats.e_wait += (dut.e_sv && !dut.e_sr);

    if (int'(dut.in_used) > stats.input_peak) stats.input_peak = int'(dut.in_used);
    if (int'(dut.out_used) > stats.output_peak) stats.output_peak = int'(dut.out_used);
    if (int'(dut.reserved_bytes) > stats.reserved_peak) stats.reserved_peak = int'(dut.reserved_bytes);

    if (int'(dut.in_used) + int'(dut.reserved_bytes) > 2048)
      $fatal(1, "read reservation exceeded FIFO capacity");

    if (rr && reads_q[0].beat == 0) begin
      stats.read_delay_sum += (cycle_cnt - reads_q[0].accepted);
      stats.read_count++;
    end

    clk = 1; #(CLK_HALF_PERIOD);
    cycle_cnt++;

    if (rr) begin
      reads_q[0].beat++;
      if (reads_q[0].beat > reads_q[0].len) void'(reads_q.pop_front());
    end
    if (ar) begin
      reads_q.push_back(r);
      delay_sum += rdelay;
      delay_count++;
    end
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
          if (w_aligned + i >= (128 * 1024 * 1024)) $fatal(1, "W address out of bounds: %08x", w_aligned + i);
          mem[w_aligned + i] = byte'((cur_b.data >> (i * 8)) & 64'hff);
        end
      end

      writes_q[0].beat++;
      if (writes_q[0].beat > writes_q[0].len) begin
        bdelay = variable_delay ? (64 + int'(rand32() % 129)) : 128;
        responses_q.push_back(cur_b.cycle + bdelay);
        delay_sum += bdelay;
        delay_count++;
        void'(writes_q.pop_front());
      end
    end

    if (reads_q.size() > max_rd) max_rd = reads_q.size();
    current_wr = writes_q.size() + responses_q.size();
    if (current_wr > max_wr) max_wr = current_wr;
  endtask

  task automatic bus_reset;
    rst_n = 0;
    psel = 0;
    penable = 0;
    repeat (3) bus_tick();
    rst_n = 1;
    bus_tick();
  endtask

  task automatic apb_access(
    input [11:0] addr,
    input bit write,
    input [31:0] wdata_val,
    input bit expected_error,
    output [31:0] rdata_val
  );
    int n;
    bit err;

    psel = 1;
    penable = 0;
    pwrite = write;
    paddr = addr;
    pwdata = wdata_val;
    bus_tick();

    penable = 1;
    rdata_val = 0;
    err = 0;

    n = 0;
    while (1) begin
      if (pready) begin
        rdata_val = prdata;
        err = pslverr;
        bus_tick();
        break;
      end
      bus_tick();
      n++;
      if (n > 2000) $fatal(1, "APB timeout at addr=%03x", addr);
    end

    psel = 0;
    penable = 0;
    bus_tick();

    if (err !== expected_error)
      $fatal(1, "APB error mismatch at addr=%03x val=%08x exp_err=%0d got_err=%0d",
             addr, wdata_val, expected_error, err);
  endtask

  task automatic apb_wr(input [11:0] addr, input [31:0] val, input bit expected_error = 0);
    bit [31:0] dummy;
    apb_access(addr, 1'b1, val, expected_error, dummy);
  endtask

  task automatic apb_rd(input [11:0] addr, output [31:0] val, input bit expected_error = 0);
    apb_access(addr, 1'b0, 32'd0, expected_error, val);
  endtask

  task automatic wait_job(input longint max_cycles, output [31:0] status_out);
    longint begin_cycle;
    bit [31:0] st, err_st, err_code;
    begin_cycle = cycle_cnt;
    while (cycle_cnt - begin_cycle < max_cycles) begin
      apb_rd(`JPEG_REG_STATUS, st);
      if (max_cycles > 2000000 && ((cycle_cnt - begin_cycle) % 30000000) < 3)
        $display("performance progress cycles=%0d", cycle_cnt - begin_cycle);
      if ((st & 6) && !(st & 1)) begin
        status_out = st;
        return;
      end
    end
    apb_rd(`JPEG_REG_STATUS, err_st);
    apb_rd(`JPEG_REG_ERROR_CODE, err_code);
    $fatal(1, "job timeout status=%0d error=%0d", err_st, err_code);
  endtask

  // File I/O helpers
  function automatic int read_file_to_queue(input string path, output byte q[$]);
    int fd;
    byte b;
    q.delete();
    fd = $fopen(path, "rb");
    if (fd == 0) return -1;
    while ($fread(b, fd) == 1) begin
      q.push_back(b);
    end
    $fclose(fd);
    return q.size();
  endfunction

  function automatic int read_file_to_mem(input string path, input longint target_addr);
    int fd;
    int count;
    fd = $fopen(path, "rb");
    if (fd == 0) return -1;
    count = $fread(mem, fd, target_addr);
    $fclose(fd);
    return count;
  endfunction

  task automatic write_mem_to_file(input string path, input longint addr, input int size);
    int fd;
    fd = $fopen(path, "wb");
    if (fd == 0) $fatal(1, "could not open %s for writing", path);
    for (int i = 0; i < size; i++) begin
      $fwrite(fd, "%c", mem[addr + i]);
    end
    $fclose(fd);
  endtask

  // Load tables
  task automatic load_tables(input int q);
    byte tbl[$];
    bit [31:0] wval;
    bit [31:0] tv;

    for (int c = 0; c < 3; c++) begin
      apb_wr(`JPEG_REG_TABLE_ADDR, c << 12);
      for (int i = 0; i < 64; i++) apb_wr(`JPEG_REG_TABLE_DATA, q);
      apb_wr(`JPEG_REG_TABLE_COMMIT, 1);
    end

    for (int kind = 1; kind <= 4; kind++) begin
      string path;
      int sz;
      $sformat(path, "tests/data/table%0d.bin", kind);
      sz = read_file_to_queue(path, tbl);
      if (sz <= 0) $fatal(1, "missing table file %s", path);
      apb_wr(`JPEG_REG_TABLE_ADDR, kind << 14);
      for (int i = 0; i < tbl.size(); i += 4) begin
        wval = {56'd0, tbl[i]} | ({56'd0, tbl[i+1]} << 8) | ({56'd0, tbl[i+2]} << 16) | ({56'd0, tbl[i+3]} << 24);
        apb_wr(`JPEG_REG_TABLE_DATA, wval);
      end
      apb_wr(`JPEG_REG_TABLE_COMMIT, 1);
    end

    apb_wr(`JPEG_REG_TABLE_SELECT, 32'h210);
    apb_rd(`JPEG_REG_TABLE_VALID, tv);
    if ((tv & 32'h2af) != 32'h2af) $fatal(1, "table valid mismatch: %08x", tv);
  endtask

  // Configure registers
  task automatic configure_job(input vector_t v, input bit decode, input longint jpeg_addr = 64'h80000);
    int hs, vs, cw, ch;
    longint samples_cnt;
    byte scan_bytes[$];
    int scan_sz;
    string scan_path;

    hs = v.fmt ? 2 : 1;
    vs = (v.fmt == 2) ? 2 : 1;
    cw = (v.w + hs - 1) / hs;
    ch = (v.h + vs - 1) / vs;
    samples_cnt = longint'(v.w) * v.h + 2 * longint'(cw) * ch;

    $sformat(scan_path, "tests/data/%s.scan", v.name);
    scan_sz = read_file_to_queue(scan_path, scan_bytes);

    apb_wr(`JPEG_REG_IMAGE_SIZE, (v.h << 16) | v.w);
    apb_wr(`JPEG_REG_FORMAT, v.fmt);
    apb_wr(`JPEG_REG_INPUT_LO, decode ? scan_sz : int'(samples_cnt));
    apb_wr(`JPEG_REG_INPUT_HI, 0);
    apb_wr(`JPEG_REG_LIMIT_LO, decode ? int'(samples_cnt) : 32'h40000);
    apb_wr(`JPEG_REG_LIMIT_HI, 0);

    for (int c = 0; c < 3; c++) begin
      apb_wr(`JPEG_REG_Y_LO + c * 8, 32'h10000 + c * 32'h10000);
      apb_wr(`JPEG_REG_Y_HI + c * 8, 0);
      apb_wr(`JPEG_REG_Y_STRIDE + c * 4, ((c ? cw : v.w) + 7) & ~7);
    end

    apb_wr(`JPEG_REG_JPEG_LO, jpeg_addr[31:0]);
    apb_wr(`JPEG_REG_JPEG_HI, jpeg_addr[63:32]);
  endtask

  // Test vector
  task automatic test_vector(input vector_t v, input longint jpeg_addr = 64'h80000);
    int hs, vs;
    longint begin_cyc, cycles;
    bit [31:0] st, bytes_out;
    byte exp_scan[$];
    byte in_pixels[$];
    byte exp_pixels[$];
    string path;
    longint samples_total;

    load_tables(v.q);
    configure_job(v, 1'b0, jpeg_addr);

    hs = v.fmt ? 2 : 1;
    vs = (v.fmt == 2) ? 2 : 1;

    for (int c = 0; c < 3; c++) begin
      int w = c ? ((v.w + hs - 1) / hs) : v.w;
      int h = c ? ((v.h + vs - 1) / vs) : v.h;
      int stride = (w + 7) & ~7;
      $sformat(path, "tests/data/%s_in%0d.bin", v.name, c);
      void'(read_file_to_queue(path, in_pixels));
      for (int y = 0; y < h; y++) begin
        for (int x = 0; x < w; x++) begin
          mem[32'h10000 + c * 32'h10000 + y * stride + x] = in_pixels[y * w + x];
        end
      end
    end

    begin_cyc = cycle_cnt;
    apb_wr(`JPEG_REG_CONTROL, 1);
    apb_rd(`JPEG_REG_OUTPUT_LO, bytes_out);
    if (bytes_out != 0) $fatal(1, "new job counter not reset");
    wait_job(2000000, st);
    cycles = cycle_cnt - begin_cyc;

    if (st & 4) begin
      bit [31:0] err_code;
      apb_rd(`JPEG_REG_ERROR_CODE, err_code);
      $fatal(1, "%s encode error code=%0d", v.name, err_code);
    end

    apb_rd(`JPEG_REG_OUTPUT_LO, bytes_out);
    $sformat(path, "tests/data/%s.scan", v.name);
    void'(read_file_to_queue(path, exp_scan));

    if (bytes_out != exp_scan.size())
      $fatal(1, "%s scan length %0d expected %0d", v.name, bytes_out, exp_scan.size());

    for (int i = 0; i < bytes_out; i++) begin
      if (mem[jpeg_addr + i] !== exp_scan[i])
        $fatal(1, "%s scan mismatch at %0d actual=%02x exp=%02x", v.name, i, mem[jpeg_addr + i], exp_scan[i]);
    end

    $sformat(path, "build/%s.scan", v.name);
    write_mem_to_file(path, jpeg_addr, bytes_out);

    $display("%s encode cycles=%0d scan_bytes=%0d", v.name, cycles, bytes_out);

    apb_wr(`JPEG_REG_STATUS, 2); // W1C done
    configure_job(v, 1'b1, jpeg_addr);

    // Decode CPU reference scan
    for (int i = 0; i < exp_scan.size(); i++) begin
      mem[jpeg_addr + i] = exp_scan[i];
    end
    for (int c = 0; c < 3; c++) begin
      for (int i = 0; i < 32'h10000; i++) mem[32'h10000 + c * 32'h10000 + i] = 8'ha5;
    end

    begin_cyc = cycle_cnt;
    apb_wr(`JPEG_REG_CONTROL, 3);
    wait_job(2000000, st);
    cycles = cycle_cnt - begin_cyc;

    if (st & 4) begin
      bit [31:0] err_code;
      apb_rd(`JPEG_REG_ERROR_CODE, err_code);
      $fatal(1, "%s decode error code=%0d", v.name, err_code);
    end

    samples_total = 0;
    for (int c = 0; c < 3; c++) begin
      int w = c ? ((v.w + hs - 1) / hs) : v.w;
      int h = c ? ((v.h + vs - 1) / vs) : v.h;
      int stride = (w + 7) & ~7;
      $sformat(path, "tests/data/%s_out%0d.bin", v.name, c);
      void'(read_file_to_queue(path, exp_pixels));
      samples_total += w * h;

      for (int y = 0; y < h; y++) begin
        for (int x = 0; x < stride; x++) begin
          byte actual = mem[32'h10000 + c * 32'h10000 + y * stride + x];
          byte exp = (x < w) ? exp_pixels[y * w + x] : 8'ha5;
          if (actual !== exp)
            $fatal(1, "%s pixel mismatch c=%0d x=%0d y=%0d actual=%02x exp=%02x",
                   v.name, c, x, y, actual, exp);
        end
      end
    end

    apb_rd(`JPEG_REG_OUTPUT_LO, bytes_out);
    if (bytes_out != samples_total)
      $fatal(1, "%s output sample count mismatch", v.name);

    $display("%s decode cycles=%0d samples=%0d", v.name, cycles, samples_total);
    apb_wr(`JPEG_REG_STATUS, 2);
  endtask

  // External images test
  task automatic test_external(input int fmt);
    vector_t v;
    string path;
    byte q_data[$];
    byte tbl_data[$];
    byte scan_data[$];
    byte exp_pixels[$];
    bit [31:0] wval, st;
    longint begin_cyc;
    int hs, vs;

    $sformat(v.name, "external%0d", fmt);
    v.w = 17;
    v.h = 13;
    v.fmt = fmt;
    v.q = 0;

    for (int c = 0; c < 3; c++) begin
      $sformat(path, "tests/data/%s_q%0d.bin", v.name, c);
      void'(read_file_to_queue(path, q_data));
      apb_wr(`JPEG_REG_TABLE_ADDR, c << 12);
      for (int i = 0; i < q_data.size(); i++) apb_wr(`JPEG_REG_TABLE_DATA, {24'd0, q_data[i]});
      apb_wr(`JPEG_REG_TABLE_COMMIT, 1);
    end

    for (int kind = 1; kind <= 4; kind++) begin
      for (int id = 0; id < 2; id++) begin
        $sformat(path, "tests/data/%s_table%0d_%0d.bin", v.name, kind, id);
        void'(read_file_to_queue(path, tbl_data));
        apb_wr(`JPEG_REG_TABLE_ADDR, (kind << 14) | (id << 12));
        for (int i = 0; i < tbl_data.size(); i += 4) begin
          wval = {56'd0, tbl_data[i]} | ({56'd0, tbl_data[i+1]} << 8) | ({56'd0, tbl_data[i+2]} << 16) | ({56'd0, tbl_data[i+3]} << 24);
          apb_wr(`JPEG_REG_TABLE_DATA, wval);
        end
        apb_wr(`JPEG_REG_TABLE_COMMIT, 1);
      end
    end

    apb_wr(`JPEG_REG_TABLE_SELECT, 32'hed0);
    configure_job(v, 1'b1, 64'h80000);

    $sformat(path, "tests/data/%s.scan", v.name);
    void'(read_file_to_queue(path, scan_data));
    for (int i = 0; i < scan_data.size(); i++) mem[32'h80000 + i] = scan_data[i];

    for (int c = 0; c < 3; c++) begin
      for (int i = 0; i < 32'h10000; i++) mem[32'h10000 + c * 32'h10000 + i] = 8'ha5;
    end

    begin_cyc = cycle_cnt;
    apb_wr(`JPEG_REG_CONTROL, 3);
    wait_job(2000000, st);
    if (st & 4) begin
      bit [31:0] err_code;
      apb_rd(`JPEG_REG_ERROR_CODE, err_code);
      $fatal(1, "%s error code=%0d", v.name, err_code);
    end

    hs = fmt ? 2 : 1;
    vs = (fmt == 2) ? 2 : 1;

    for (int c = 0; c < 3; c++) begin
      int w = c ? ((v.w + hs - 1) / hs) : v.w;
      int h = c ? ((v.h + vs - 1) / vs) : v.h;
      int stride = (w + 7) & ~7;
      $sformat(path, "tests/data/%s_out%0d.bin", v.name, c);
      void'(read_file_to_queue(path, exp_pixels));
      for (int y = 0; y < h; y++) begin
        for (int x = 0; x < stride; x++) begin
          byte actual = mem[32'h10000 + c * 32'h10000 + y * stride + x];
          byte exp = (x < w) ? exp_pixels[y * w + x] : 8'ha5;
          if (actual !== exp) $fatal(1, "%s external pixel mismatch", v.name);
        end
      end
    end

    $display("%s decode cycles=%0d scan_bytes=%0d", v.name, cycle_cnt - begin_cyc, scan_data.size());
    apb_wr(`JPEG_REG_STATUS, 2);
  endtask

  // Error tests
  task automatic expect_error(input int code);
    bit [31:0] st, err_code;
    wait_job(2000000, st);
    apb_rd(`JPEG_REG_ERROR_CODE, err_code);
    if (!(st & 4) || err_code != code)
      $fatal(1, "expected job error %0d actual=%0d", code, err_code);
    if (reads_q.size() > 0 || writes_q.size() > 0 || beats_q.size() > 0 || responses_q.size() > 0)
      $fatal(1, "DMA not drained");
    apb_wr(`JPEG_REG_STATUS, 4); // W1C error
  endtask

  task automatic load_ac1(input bit all_ones);
    apb_wr(`JPEG_REG_TABLE_ADDR, (4 << 14) | (1 << 12));
    for (int i = 0; i < 320; i++) begin
      bit [31:0] value = 0;
      if (all_ones) begin
        if (i == 1) value = 1;
        if (i == 3) value = 2;
      end else begin
        if (i == 33) value = 254;
        if (i == 35) value = 255;
        if (i == 36 || i == 37) value = 510;
        if (i == 38) value = 255;
        if (i == 39) value = 1;
      end
      apb_wr(`JPEG_REG_TABLE_DATA, value);
    end
    apb_wr(`JPEG_REG_TABLE_COMMIT, 1, all_ones);
  endtask

  task automatic error_tests;
    vector_t v;
    longint addr_hold;
    bit [63:0] wa, wd;
    bit [7:0] wk;
    byte scan_bytes[$];
    bit [31:0] dummy, tv_check, st_check, out_check, err_check;

    v.name = "flat";
    v.w = 8;
    v.h = 8;
    v.fmt = 0;
    v.q = 16;

    load_tables(16);
    configure_job(v, 1'b0);

    load_ac1(1'b0);
    apb_rd(`JPEG_REG_TABLE_VALID, tv_check);
    if (!(tv_check & 1024)) $fatal(1, "256-symbol commit missing");
    load_ac1(1'b1);
    apb_rd(`JPEG_REG_TABLE_VALID, tv_check);
    if (tv_check & 1024) $fatal(1, "all-one code commit accepted");

    apb_wr(`JPEG_REG_CONTROL, 5, 1);
    apb_wr(12'h100, 0, 1);
    apb_wr(`JPEG_REG_IMAGE_SIZE, 0);
    apb_wr(`JPEG_REG_CONTROL, 1);
    expect_error(1);
    configure_job(v, 1'b0);

    apb_wr(`JPEG_REG_TABLE_ADDR, 0);
    apb_wr(`JPEG_REG_TABLE_DATA, 16);
    apb_wr(`JPEG_REG_TABLE_COMMIT, 1, 1);
    apb_rd(`JPEG_REG_TABLE_VALID, tv_check);
    if (tv_check & 1) $fatal(1, "partial Q commit");
    apb_wr(`JPEG_REG_CONTROL, 1);
    expect_error(2);
    load_tables(16);

    apb_wr(`JPEG_REG_TABLE_ADDR, 0);
    apb_wr(`JPEG_REG_TABLE_DATA, 0, 1);
    apb_wr(`JPEG_REG_TABLE_ADDR, (3 << 14) | 320);
    apb_rd(`JPEG_REG_TABLE_VALID, tv_check);
    apb_access(`JPEG_REG_TABLE_DATA, 1'b0, 0, 1, dummy);

    // Pending AR survives stop
    configure_job(v, 1'b0);
    ar_block = 1;
    apb_wr(`JPEG_REG_CONTROL, 1);
    for (int i = 0; i < 50 && !m_axi_arvalid; i++) bus_tick();
    if (!m_axi_arvalid) $fatal(1, "no pending AR");
    addr_hold = m_axi_araddr;
    apb_wr(`JPEG_REG_IMAGE_SIZE, 0, 1);
    apb_wr(`JPEG_REG_CONTROL, 1, 1);
    apb_wr(`JPEG_REG_CONTROL, 4);
    for (int i = 0; i < 20; i++) bus_tick();
    apb_rd(`JPEG_REG_STATUS, st_check);
    if (!m_axi_arvalid || m_axi_araddr !== addr_hold || !(st_check & 1))
      $fatal(1, "stop retracted AR");
    apb_wr(`JPEG_REG_STATUS, 4, 1);
    ar_block = 0;
    expect_error(9);

    // Spurious error W1C test
    configure_job(v, 1'b0);
    for (int c = 0; c < 3; c++) begin
      for (int i = 0; i < 64; i++) mem[32'h10000 + c * 32'h10000 + i] = 8'd128;
    end
    apb_wr(`JPEG_REG_CONTROL, 1);
    for (int i = 0; i < 2000 && !dut.rd_done; i++) bus_tick();
    apb_wr(`JPEG_REG_STATUS, 4);
    begin
      bit [31:0] st;
      wait_job(2000000, st);
      if (st & 4) $fatal(1, "spurious error W1C");
    end
    apb_wr(`JPEG_REG_STATUS, 2);

    // Read error
    configure_job(v, 1'b0);
    read_error = 2;
    apb_wr(`JPEG_REG_CONTROL, 1);
    expect_error(3);
    read_error = 0;

    // Write error
    configure_job(v, 1'b0);
    write_error = 2;
    apb_wr(`JPEG_REG_CONTROL, 1);
    begin
      bit [31:0] st;
      wait_job(2000000, st);
      apb_rd(`JPEG_REG_ERROR_CODE, err_check);
      apb_rd(`JPEG_REG_OUTPUT_LO, out_check);
      if (!(st & 4) || err_check != 4 || out_check == 0)
        $fatal(1, "write error/count");
    end
    write_error = 0;
    apb_wr(`JPEG_REG_STATUS, 4);

    // Capacity error
    configure_job(v, 1'b0);
    apb_wr(`JPEG_REG_LIMIT_LO, 1);
    apb_wr(`JPEG_REG_CONTROL, 1);
    expect_error(7);
    apb_rd(`JPEG_REG_OUTPUT_LO, out_check);
    if (out_check != 0) $fatal(1, "capacity wrote data");

    // Scan truncated
    void'(read_file_to_queue("tests/data/flat.scan", scan_bytes));
    for (int i = 0; i < scan_bytes.size(); i++) mem[32'h80000 + i] = scan_bytes[i];
    configure_job(v, 1'b1);
    apb_wr(`JPEG_REG_INPUT_LO, scan_bytes.size() - 1);
    apb_wr(`JPEG_REG_CONTROL, 3);
    expect_error(5);

    // Padding error
    configure_job(v, 1'b1);
    mem[32'h80000 + scan_bytes.size()] = 0;
    apb_wr(`JPEG_REG_INPUT_LO, scan_bytes.size() + 1);
    apb_wr(`JPEG_REG_CONTROL, 3);
    expect_error(10);

    // Bad marker error
    configure_job(v, 1'b1);
    mem[32'h80000] = 8'hff;
    mem[32'h80001] = 8'h01;
    apb_wr(`JPEG_REG_INPUT_LO, 2);
    apb_wr(`JPEG_REG_CONTROL, 3);
    expect_error(6);

    // AW / W stop test
    configure_job(v, 1'b0);
    aw_block = 1;
    w_block = 1;
    apb_wr(`JPEG_REG_CONTROL, 1);
    for (int i = 0; i < 10000 && !m_axi_awvalid; i++) bus_tick();
    if (!m_axi_awvalid) $fatal(1, "no pending AW");
    wa = m_axi_awaddr;
    wd = m_axi_wdata;
    wk = m_axi_wstrb;
    apb_wr(`JPEG_REG_CONTROL, 4);
    for (int i = 0; i < 20; i++) bus_tick();
    if (!m_axi_awvalid || !m_axi_wvalid || m_axi_awaddr !== wa || m_axi_wdata !== wd || m_axi_wstrb !== wk)
      $fatal(1, "stop retracted AW/W");
    aw_block = 0;
    w_block = 0;
    expect_error(9);

    // Maximum dimensions test
    for (int fmt = 0; fmt < 3; fmt++) begin
      longint max_samples;
      int expected_blocks;
      configure_job(v, 1'b0);
      apb_wr(`JPEG_REG_IMAGE_SIZE, 32'hffffffff);
      apb_wr(`JPEG_REG_FORMAT, fmt);
      max_samples = 65535 * 65535 + 2 * (fmt ? 32768 : 65535) * ((fmt == 2) ? 32768 : 65535);
      apb_wr(`JPEG_REG_INPUT_LO, max_samples[31:0]);
      apb_wr(`JPEG_REG_INPUT_HI, max_samples[63:32]);
      for (int c = 0; c < 3; c++) apb_wr(`JPEG_REG_Y_STRIDE + c * 4, 65536);
      ar_block = 1;
      apb_wr(`JPEG_REG_CONTROL, 1);
      for (int n = 0; n < 20; n++) bus_tick();
      expected_blocks = (fmt == 0) ? 201326592 : ((fmt == 1) ? 134217728 : 100663296);
      apb_rd(`JPEG_REG_STATUS, st_check);
      if (dut.total_blocks != expected_blocks || (st_check & 4))
        $fatal(1, "maximum dimensions/counts mismatch");
      apb_wr(`JPEG_REG_CONTROL, 4);
      ar_block = 0;
      expect_error(9);
    end

    apb_wr(`JPEG_REG_CONTROL, 4);
    apb_rd(`JPEG_REG_TABLE_VALID, tv_check);
    if (tv_check != 0) $fatal(1, "idle stop did not clear tables");

    $display("PASS APB, partial commit, configuration, capacity, EOF, marker, AXI faults, held AR/AW/W stop/drain");
  endtask

  // Restart tests
  task automatic restart_tests;
    int fd;
    string name;
    int w, h, fmt, interval, sel, exp_err;
    int tested = 0;

    fd = $fopen("tests/data/restart/manifest.txt", "r");
    if (fd == 0) $fatal(1, "restart manifest missing");

    while ($fscanf(fd, "%s %d %d %d %d %d %d", name, w, h, fmt, interval, sel, exp_err) == 7) begin
      run_restart_subtest(name, w, h, fmt, interval, sel, exp_err, 1'b0);
      tested++;
    end
    $fclose(fd);

    run_restart_subtest("fmt2_ri1", 79, 35, 2, 1, 528, 9, 1'b1);
    run_restart_subtest("fmt2_ri1", 79, 35, 2, 1, 528, 0, 1'b0);

    apb_wr(`JPEG_REG_RESTART_INTERVAL, 1);
    load_tables(16);
    begin
      vector_t fv;
      bit [31:0] st, err_check;
      fv.name = "flat"; fv.w = 8; fv.h = 8; fv.fmt = 0; fv.q = 16;
      configure_job(fv, 1'b0);
      apb_wr(`JPEG_REG_CONTROL, 1);
      wait_job(2000000, st);
      apb_rd(`JPEG_REG_ERROR_CODE, err_check);
      if (!(st & 4) || err_check != 1)
        $fatal(1, "encode nonzero restart config accepted");
      apb_wr(`JPEG_REG_STATUS, 4);
      apb_wr(`JPEG_REG_RESTART_INTERVAL, 0);
    end

    $display("PASS %0d restart vectors, MCU 444/422/420, sequence wrap, padding/EOF/errors, stop/recovery, encode config rejection", tested);
  endtask

  task automatic run_restart_subtest(
    input string name,
    input int w,
    input int h,
    input int fmt,
    input int interval,
    input int sel,
    input int exp_err,
    input bit stop
  );
    vector_t v;
    string path;
    byte q_data[$];
    byte tbl_data[$];
    byte scan_data[$];
    byte exp_pixels[$];
    bit [31:0] wval, st;
    longint begin_cyc;
    int code;
    int hs, vs;

    $sformat(v.name, "restart/%s", name);
    v.w = w;
    v.h = h;
    v.fmt = fmt;
    v.q = 0;

    for (int c = 0; c < 3; c++) begin
      $sformat(path, "tests/data/%s_q%0d.bin", v.name, c);
      void'(read_file_to_queue(path, q_data));
      apb_wr(`JPEG_REG_TABLE_ADDR, c << 12);
      for (int i = 0; i < q_data.size(); i++) apb_wr(`JPEG_REG_TABLE_DATA, {24'd0, q_data[i]});
      apb_wr(`JPEG_REG_TABLE_COMMIT, 1);
    end

    for (int kind = 3; kind <= 4; kind++) begin
      for (int id = 0; id < 2; id++) begin
        $sformat(path, "tests/data/%s_table%0d_%0d.bin", v.name, kind, id);
        void'(read_file_to_queue(path, tbl_data));
        apb_wr(`JPEG_REG_TABLE_ADDR, (kind << 14) | (id << 12));
        for (int i = 0; i < tbl_data.size(); i += 4) begin
          wval = {56'd0, tbl_data[i]} | ({56'd0, tbl_data[i+1]} << 8) | ({56'd0, tbl_data[i+2]} << 16) | ({56'd0, tbl_data[i+3]} << 24);
          apb_wr(`JPEG_REG_TABLE_DATA, wval);
        end
        apb_wr(`JPEG_REG_TABLE_COMMIT, 1);
      end
    end

    apb_wr(`JPEG_REG_TABLE_SELECT, sel);
    apb_wr(`JPEG_REG_RESTART_INTERVAL, interval);
    configure_job(v, 1'b1, 64'h80000);

    $sformat(path, "tests/data/%s.scan", v.name);
    void'(read_file_to_queue(path, scan_data));
    for (int i = 0; i < scan_data.size(); i++) mem[32'h80000 + i] = scan_data[i];

    for (int c = 0; c < 3; c++) begin
      for (int i = 0; i < 32'h10000; i++) mem[32'h10000 + c * 32'h10000 + i] = 8'ha5;
    end

    begin_cyc = cycle_cnt;
    apb_wr(`JPEG_REG_CONTROL, 3);

    if (stop) begin
      int n = 0;
      while (!dut.restart_pending) begin
        bus_tick();
        n++;
        if (n > 100000) $fatal(1, "restart stop boundary timeout");
      end
      apb_wr(`JPEG_REG_CONTROL, 4);
    end

    wait_job(2000000, st);
    apb_rd(`JPEG_REG_ERROR_CODE, code);

    if (exp_err) begin
      if (!(st & 4) || (exp_err != 255 && code != exp_err))
        $fatal(1, "%s expected error %0d actual=%0d", name, exp_err, code);
      apb_wr(`JPEG_REG_STATUS, 4);
    end else begin
      if (st & 4) $fatal(1, "%s restart decode error %0d", name, code);
      hs = fmt ? 2 : 1;
      vs = (fmt == 2) ? 2 : 1;
      for (int c = 0; c < 3; c++) begin
        int cw = c ? ((w + hs - 1) / hs) : w;
        int ch = c ? ((h + vs - 1) / vs) : h;
        int stride = (cw + 7) & ~7;
        $sformat(path, "tests/data/%s_out%0d.bin", v.name, c);
        void'(read_file_to_queue(path, exp_pixels));
        for (int y = 0; y < ch; y++) begin
          for (int x = 0; x < stride; x++) begin
            byte actual = mem[32'h10000 + c * 32'h10000 + y * stride + x];
            byte exp = (x < cw) ? exp_pixels[y * cw + x] : 8'ha5;
            if (actual !== exp) $fatal(1, "%s restart pixel/stride mismatch", name);
          end
        end
      end
      apb_wr(`JPEG_REG_STATUS, 2);
    end

    if (reads_q.size() > 0 || writes_q.size() > 0 || beats_q.size() > 0 || responses_q.size() > 0)
      $fatal(1, "restart job not drained");

    $display("%s restart decode cycles=%0d status=%s code=%0d",
             name, cycle_cnt - begin_cyc, exp_err ? "expected error" : "PASS", code);
  endtask

  // Standard vectors
  task automatic run_standard_tests;
    vector_t vectors[11];
    vectors[0] = '{"flat", 8, 8, 0, 16};
    vectors[1] = '{"edge444", 17, 13, 0, 16};
    vectors[2] = '{"edge422", 17, 13, 1, 16};
    vectors[3] = '{"edge420", 17, 13, 2, 16};
    vectors[4] = '{"q255", 9, 9, 2, 255};
    vectors[5] = '{"dense", 16, 16, 0, 1};
    vectors[6] = '{"gradient", 32, 24, 0, 8};
    vectors[7] = '{"tiny444", 1, 1, 0, 1};
    vectors[8] = '{"tiny420", 1, 1, 2, 16};
    vectors[9] = '{"small422", 7, 5, 1, 13};
    vectors[10] = '{"small420", 7, 5, 2, 13};

    apb_wr(12'h009, 1, 1);

    for (int i = 0; i < 11; i++) begin
      test_vector(vectors[i]);
    end

    // Unaligned jpeg base
    test_vector('{"gradient", 32, 24, 0, 8}, 64'hff8);

    for (int fmt = 0; fmt < 3; fmt++) begin
      test_external(fmt);
    end

    error_tests();

    $display("PASS top vectors; max_read_outstanding=%0d max_write_outstanding=%0d nominal_mean_response_cycles=%0f",
             max_rd, max_wr, (delay_count > 0) ? (real'(delay_sum) / real'(delay_count)) : 0.0);
  endtask

  // Performance test
  task automatic performance_test(input bit stress = 0, input bit variable = 0);
    string prefix;
    int w, h;
    longint samples_cnt;
    longint bases[3];
    longint jp;
    longint begin_cyc, enc_cycles, dec_cycles;
    stats_t enc_stats;
    real encode_nominal_delay, decode_nominal_delay;
    bit [31:0] st, bytes_out, err_code;
    string path;
    byte q_data[$];
    byte tbl_data[$];
    byte dec_scan[$];
    bit [31:0] wval;
    int report_fd;
    int read_count;
    bit [31:0] s_seed;

    w = 2480;
    h = 3508;
    samples_cnt = longint'(w) * h * 3;
    bases[0] = 32'h100000;
    bases[1] = 32'h1100000;
    bases[2] = 32'h2100000;
    jp = 32'h3100000;

    random_ready = variable;
    variable_delay = variable;
    prefix = stress ? "a4_stress" : (variable ? "a4_variable" : "a4");

    for (int i = 0; i < (128 * 1024 * 1024); i++) mem[i] = 8'ha5;

    $display("Loading tests/data/a4_planar.bin...");
    read_count = read_file_to_mem("tests/data/a4_planar.bin", bases[0]);
    if (read_count <= 0) $fatal(1, "could not read tests/data/a4_planar.bin");

    if (stress) begin
      s_seed = 32'd20261005;
      for (longint i = 0; i < samples_cnt; i++) begin
        s_seed = s_seed ^ (s_seed << 13);
        s_seed = s_seed ^ (s_seed >> 17);
        s_seed = s_seed ^ (s_seed << 5);
        mem[bases[0] + i] = byte'(s_seed[7:0]);
      end
    end

    // Move planes to bases[1] and bases[2]
    for (longint i = longint'(w) * h - 1; i >= 0; i--) begin
      mem[bases[2] + i] = mem[bases[0] + 2 * longint'(w) * h + i];
      mem[bases[1] + i] = mem[bases[0] + longint'(w) * h + i];
    end

    load_tables(16);
    apb_wr(`JPEG_REG_IMAGE_SIZE, (h << 16) | w);
    apb_wr(`JPEG_REG_FORMAT, 0);
    apb_wr(`JPEG_REG_INPUT_LO, samples_cnt[31:0]);
    apb_wr(`JPEG_REG_INPUT_HI, samples_cnt[63:32]);
    apb_wr(`JPEG_REG_LIMIT_LO, 32'h2000000);
    apb_wr(`JPEG_REG_LIMIT_HI, 0);
    apb_wr(`JPEG_REG_JPEG_LO, jp[31:0]);
    apb_wr(`JPEG_REG_JPEG_HI, jp[63:32]);

    for (int c = 0; c < 3; c++) begin
      apb_wr(`JPEG_REG_Y_LO + c * 8, bases[c][31:0]);
      apb_wr(`JPEG_REG_Y_HI + c * 8, bases[c][63:32]);
      apb_wr(`JPEG_REG_Y_STRIDE + c * 4, w);
    end

    stats = '{0,0,0,0,0,0,0,0,0,0,0,0};
    delay_sum = 0;
    delay_count = 0;
    begin_cyc = cycle_cnt;

    apb_wr(`JPEG_REG_CONTROL, 1);
    wait_job(1000000000, st);
    enc_cycles = cycle_cnt - begin_cyc;
    enc_stats = stats;
    encode_nominal_delay = (delay_count > 0) ? (real'(delay_sum) / real'(delay_count)) : 0.0;

    apb_rd(`JPEG_REG_OUTPUT_LO, bytes_out);
    if (st & 4) begin
      apb_rd(`JPEG_REG_ERROR_CODE, err_code);
      $fatal(1, "A4 encode error code=%0d", err_code);
    end

    $sformat(path, "build/%s.scan", prefix);
    write_mem_to_file(path, jp, bytes_out);
    $display("A4 encode cycles=%0d scan_bytes=%0d samples=%0d", enc_cycles, bytes_out, samples_cnt);

    apb_wr(`JPEG_REG_STATUS, 2);
    apb_wr(`JPEG_REG_INPUT_LO, bytes_out);
    apb_wr(`JPEG_REG_INPUT_HI, 0);
    apb_wr(`JPEG_REG_LIMIT_LO, samples_cnt[31:0]);
    apb_wr(`JPEG_REG_LIMIT_HI, samples_cnt[63:32]);

    $sformat(path, "build/%s_decode_input.scan", prefix);
    void'(read_file_to_queue(path, dec_scan));
    for (int i = 0; i < dec_scan.size(); i++) mem[jp + i] = dec_scan[i];
    apb_wr(`JPEG_REG_INPUT_LO, dec_scan.size());

    for (int c = 0; c < 3; c++) begin
      $sformat(path, "build/%s_decode_q%0d.bin", prefix, c);
      void'(read_file_to_queue(path, q_data));
      apb_wr(`JPEG_REG_TABLE_ADDR, c << 12);
      for (int i = 0; i < q_data.size(); i++) apb_wr(`JPEG_REG_TABLE_DATA, {24'd0, q_data[i]});
      apb_wr(`JPEG_REG_TABLE_COMMIT, 1);
    end

    for (int kind = 3; kind <= 4; kind++) begin
      for (int id = 0; id < 2; id++) begin
        $sformat(path, "build/%s_decode_table%0d_%0d.bin", prefix, kind, id);
        void'(read_file_to_queue(path, tbl_data));
        apb_wr(`JPEG_REG_TABLE_ADDR, (kind << 14) | (id << 12));
        for (int i = 0; i < tbl_data.size(); i += 4) begin
          wval = {56'd0, tbl_data[i]} | ({56'd0, tbl_data[i+1]} << 8) | ({56'd0, tbl_data[i+2]} << 16) | ({56'd0, tbl_data[i+3]} << 24);
          apb_wr(`JPEG_REG_TABLE_DATA, wval);
        end
        apb_wr(`JPEG_REG_TABLE_COMMIT, 1);
      end
    end

    apb_wr(`JPEG_REG_TABLE_SELECT, 32'hed0);

    for (int c = 0; c < 3; c++) begin
      for (longint i = 0; i < longint'(w) * h; i++) mem[bases[c] + i] = 8'ha5;
    end

    stats = '{0,0,0,0,0,0,0,0,0,0,0,0};
    delay_sum = 0;
    delay_count = 0;
    begin_cyc = cycle_cnt;

    apb_wr(`JPEG_REG_CONTROL, 3);
    wait_job(1000000000, st);
    dec_cycles = cycle_cnt - begin_cyc;
    decode_nominal_delay = (delay_count > 0) ? (real'(delay_sum) / real'(delay_count)) : 0.0;

    if (st & 4) begin
      apb_rd(`JPEG_REG_ERROR_CODE, err_code);
      $fatal(1, "A4 decode error code=%0d", err_code);
    end

    apb_rd(`JPEG_REG_OUTPUT_LO, bytes_out);
    if (bytes_out != samples_cnt) $fatal(1, "A4 samples mismatch");

    $sformat(path, "build/%s_decoded.bin", prefix);
    begin
      int out_fd = $fopen(path, "wb");
      if (out_fd == 0) $fatal(1, "could not open %s", path);
      for (int c = 0; c < 3; c++) begin
        for (longint i = 0; i < longint'(w) * h; i++) begin
          $fwrite(out_fd, "%c", mem[bases[c] + i]);
        end
      end
      $fclose(out_fd);
    end

    $sformat(path, "build/%s.json", (stress ? "performance_stress" : (variable ? "performance_variable" : "performance")));
    report_fd = $fopen(path, "w");
    if (report_fd != 0) begin
      $fwrite(report_fd, "{\"width\":2480,\"height\":3508,\"blocks\":408270,\"encode_cycles\":%0d,\"decode_cycles\":%0d,\"scan_bytes\":%0d,\"decode_input_bytes\":%0d,\"samples\":%0d,\"axi_latency_cycles\":128,\"variable_latency\":%s,\"seed\":20261005,\"encode_nominal_delay_mean\":%0f,\"decode_nominal_delay_mean\":%0f",
              enc_cycles, dec_cycles, bytes_out, dec_scan.size(), samples_cnt, variable ? "true" : "false", encode_nominal_delay, decode_nominal_delay);
      $fwrite(report_fd, ",\"encode_stats\":{\"input_fifo_peak\":%0d,\"output_fifo_peak\":%0d,\"reserved_peak\":%0d,\"ar_wait\":%0d,\"aw_wait\":%0d,\"w_wait\":%0d,\"r_wait\":%0d,\"transform_input_wait\":%0d,\"quant_input_wait\":%0d,\"entropy_input_wait\":%0d,\"observed_first_r_handshake_delay_mean\":%0f}",
              enc_stats.input_peak, enc_stats.output_peak, enc_stats.reserved_peak, enc_stats.ar_wait, enc_stats.aw_wait, enc_stats.w_wait, enc_stats.r_wait, enc_stats.t_wait, enc_stats.q_wait, enc_stats.e_wait,
              (enc_stats.read_count > 0) ? (real'(enc_stats.read_delay_sum) / real'(enc_stats.read_count)) : 0.0);
      $fwrite(report_fd, ",\"decode_stats\":{\"input_fifo_peak\":%0d,\"output_fifo_peak\":%0d,\"reserved_peak\":%0d,\"ar_wait\":%0d,\"aw_wait\":%0d,\"w_wait\":%0d,\"r_wait\":%0d,\"transform_input_wait\":%0d,\"quant_input_wait\":%0d,\"entropy_input_wait\":%0d,\"observed_first_r_handshake_delay_mean\":%0f}}\n",
              stats.input_peak, stats.output_peak, stats.reserved_peak, stats.ar_wait, stats.aw_wait, stats.w_wait, stats.r_wait, stats.t_wait, stats.q_wait, stats.e_wait,
              (stats.read_count > 0) ? (real'(stats.read_delay_sum) / real'(stats.read_count)) : 0.0);
      $fclose(report_fd);
    end

    $display("A4 decode cycles=%0d 100ppm_budget=153600000", dec_cycles);
  endtask

  initial begin
    bus_reset();

    if ($test$plusargs("performance-stress")) begin
      performance_test(1'b1, 1'b0);
      $finish;
    end
    if ($test$plusargs("performance-variable")) begin
      performance_test(1'b0, 1'b1);
      $finish;
    end
    if ($test$plusargs("performance")) begin
      performance_test(1'b0, 1'b0);
      $finish;
    end
    if ($test$plusargs("restart-variable")) begin
      variable_delay = 1;
      restart_tests();
      $finish;
    end
    if ($test$plusargs("restart")) begin
      restart_tests();
      $finish;
    end
    if ($test$plusargs("variable")) begin
      variable_delay = 1;
    end

    run_standard_tests();
    $finish;
  end
endmodule
