`timescale 1ns/1ps
`include "jpeg_defs.vh"

module jpeg_tool_tb;
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

  localparam longint MEM_SIZE = 128 * 1024 * 1024;
  byte mem[0:MEM_SIZE-1];
  read_t reads_q[$];
  write_t writes_q[$];
  beat_t beats_q[$];
  longint responses_q[$];

  longint cycle_cnt = 0;

  localparam real CLK_HALF_PERIOD = 1.953125; // 256 MHz clock: Period = 3.90625 ns

  task automatic bus_tick;
    longint r_addr, w_addr, w_aligned;
    bit ar, rr, aw, ww, bb;
    int rdelay, bdelay;
    read_t r;
    write_t w;
    beat_t b;

    clk = 0;
    m_axi_arready = (reads_q.size() < 8);
    m_axi_awready = ((writes_q.size() + responses_q.size()) < 8);
    m_axi_wready = (beats_q.size() < 128);

    m_axi_rvalid = (reads_q.size() > 0) && (reads_q[0].due <= cycle_cnt);
    m_axi_rdata = 0;
    m_axi_rid = 0;
    m_axi_rresp = 2'b00;
    m_axi_rlast = 0;

    if (m_axi_rvalid) begin
      r = reads_q[0];
      r_addr = r.addr + (longint'(r.beat) << r.size);
      m_axi_rlast = (r.beat == r.len);
      for (int i = 0; i < (1 << r.size); i++) begin
        if (r_addr + i >= MEM_SIZE) $fatal(1, "R address out of bounds: %08x", r_addr + i);
        m_axi_rdata |= ({56'd0, mem[r_addr + i]} << (((r_addr + i) & 7) * 8));
      end
    end

    m_axi_bvalid = (responses_q.size() > 0) && (responses_q[0] <= cycle_cnt);
    m_axi_bid = 0;
    m_axi_bresp = 2'b00;

    #(CLK_HALF_PERIOD);

    ar = m_axi_arvalid && m_axi_arready;
    rr = m_axi_rvalid && m_axi_rready;
    aw = m_axi_awvalid && m_axi_awready;
    ww = m_axi_wvalid && m_axi_wready;
    bb = m_axi_bvalid && m_axi_bready;

    rdelay = 128;
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

    clk = 1; #(CLK_HALF_PERIOD);
    cycle_cnt++;

    if (rr) begin
      reads_q[0].beat++;
      if (reads_q[0].beat > reads_q[0].len) void'(reads_q.pop_front());
    end
    if (ar) begin
      reads_q.push_back(r);
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
          if (w_aligned + i >= MEM_SIZE) $fatal(1, "W address out of bounds: %08x", w_aligned + i);
          mem[w_aligned + i] = byte'((cur_b.data >> (i * 8)) & 64'hff);
        end
      end

      writes_q[0].beat++;
      if (writes_q[0].beat > writes_q[0].len) begin
        bdelay = 128;
        responses_q.push_back(cur_b.cycle + bdelay);
        void'(writes_q.pop_front());
      end
    end
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
    longint begin_cycle, elapsed, last_log_cycle;
    longint log_interval;
    bit [31:0] st, err_st, err_code;
    begin_cycle = cycle_cnt;
    last_log_cycle = 0;
    log_interval = (max_cycles > 10000000) ? 500000 : 100000;
    while (cycle_cnt - begin_cycle < max_cycles) begin
      apb_rd(`JPEG_REG_STATUS, st);
      elapsed = cycle_cnt - begin_cycle;
      if (elapsed - last_log_cycle >= log_interval) begin
        $display("[jpeg_tool_tb] Progress: elapsed %0d cycles (status=0x%08x)...", elapsed, st);
        last_log_cycle = elapsed;
      end
      if ((st & 6) && !(st & 1)) begin
        status_out = st;
        return;
      end
    end
    apb_rd(`JPEG_REG_STATUS, err_st);
    apb_rd(`JPEG_REG_ERROR_CODE, err_code);
    $fatal(1, "job timeout status=%0d error=%0d", err_st, err_code);
  endtask

  // Main task
  task automatic run_tool;
    string job_dir;
    string config_path;
    int cfg_fd;
    int scan_res;
    int mode_in, w_in, h_in, fmt_in, select_in;
    longint unsigned input_size_in;
    int restart_interval_in;
    int hs, vs;
    int widths[3], heights[3], strides[3];
    longint samples, cursor;
    longint unsigned bases[3], jpeg_base, capacity, limit;
    longint blocks;
    longint begin_cycle, cycles;
    bit [31:0] status;
    bit [31:0] bytes_lo, bytes_hi;
    longint unsigned bytes_out;
    longint max_cycles;

    if (!$value$plusargs("JOB_DIR=%s", job_dir)) begin
      $fatal(1, "JOB_DIR argument is missing (+JOB_DIR=<path>)");
    end

    config_path = {job_dir, "/config.txt"};
    cfg_fd = $fopen(config_path, "r");
    if (cfg_fd == 0) $fatal(1, "Could not open %s", config_path);

    restart_interval_in = 0;
    scan_res = $fscanf(cfg_fd, "%d %d %d %d %d %d %d", mode_in, w_in, h_in, fmt_in, select_in, input_size_in, restart_interval_in);
    $fclose(cfg_fd);

    if (scan_res < 6 || mode_in > 1 || !w_in || w_in > 65535 || !h_in || h_in > 65535 || fmt_in > 2 || select_in > 4095)
      $fatal(1, "invalid job configuration");
    if (restart_interval_in > 65535)
      $fatal(1, "restart interval range");

    hs = fmt_in ? 2 : 1;
    vs = (fmt_in == 2) ? 2 : 1;
    widths[0] = w_in;
    widths[1] = (w_in + hs - 1) / hs;
    widths[2] = (w_in + hs - 1) / hs;
    heights[0] = h_in;
    heights[1] = (h_in + vs - 1) / vs;
    heights[2] = (h_in + vs - 1) / vs;

    for (int c = 0; c < 3; c++) begin
      strides[c] = (widths[c] + 7) & ~7;
    end

    samples = 0;
    cursor = 64'd4096;
    for (int c = 0; c < 3; c++) begin
      bases[c] = cursor;
      samples += longint'(widths[c]) * heights[c];
      cursor = (cursor + longint'(strides[c]) * heights[c] + 64'd4095) & ~64'd4095;
    end

    blocks = longint'((w_in + hs * 8 - 1) / (hs * 8)) *
             ((h_in + vs * 8 - 1) / (vs * 8)) *
             (hs * vs + 2);
    jpeg_base = cursor;
    capacity = mode_in ? input_size_in : (blocks * 512 + 64);

    if (cursor + capacity + 4096 > MEM_SIZE)
      $fatal(1, "job exceeds simulator memory limit (%0d bytes)", MEM_SIZE);
    if (!mode_in && input_size_in != samples)
      $fatal(1, "input sample count mismatch");

    $display("[jpeg_tool_tb] === Starting RTL %s Simulation ===", mode_in ? "DECODE" : "ENCODE");
    $display("[jpeg_tool_tb] Dimensions: %0dx%0d, Format: %0d (%s), Blocks: %0d",
             w_in, h_in, fmt_in, (fmt_in == 0 ? "4:4:4" : (fmt_in == 1 ? "4:2:2" : "4:2:0")), blocks);

    bus_reset();

    // Load Q tables
    for (int c = 0; c < 3; c++) begin
      string q_path;
      int q_fd;
      byte q_byte;
      $sformat(q_path, "%s/q%0d.bin", job_dir, c);
      q_fd = $fopen(q_path, "rb");
      if (q_fd == 0) $fatal(1, "missing Q table file %s", q_path);
      apb_wr(`JPEG_REG_TABLE_ADDR, c << 12);
      for (int i = 0; i < 64; i++) begin
        if ($fread(q_byte, q_fd) != 1) $fatal(1, "Q table size mismatch: %s", q_path);
        apb_wr(`JPEG_REG_TABLE_DATA, {24'd0, q_byte});
      end
      if ($fread(q_byte, q_fd) == 1) $fatal(1, "Q table size mismatch (too long): %s", q_path);
      $fclose(q_fd);
      apb_wr(`JPEG_REG_TABLE_COMMIT, 1);
    end

    // Load Huffman tables
    begin
      int kind_start, kind_end;
      kind_start = mode_in ? 3 : 1;
      kind_end = mode_in ? 4 : 2;
      for (int kind = kind_start; kind <= kind_end; kind++) begin
        for (int id = 0; id < 2; id++) begin
          string h_path;
          int h_fd;
          int expected_words;
          byte b0, b1, b2, b3;
          bit [31:0] word;
          $sformat(h_path, "%s/table%0d_%0d.bin", job_dir, kind, id);
          h_fd = $fopen(h_path, "rb");
          if (h_fd == 0) $fatal(1, "missing Huffman table file %s", h_path);
          expected_words = mode_in ? 320 : 256;
          apb_wr(`JPEG_REG_TABLE_ADDR, (kind << 14) | (id << 12));
          for (int i = 0; i < expected_words; i++) begin
            if ($fread(b0, h_fd) != 1 || $fread(b1, h_fd) != 1 ||
                $fread(b2, h_fd) != 1 || $fread(b3, h_fd) != 1) begin
              $fatal(1, "Huffman table size mismatch: %s", h_path);
            end
            word = {b3, b2, b1, b0};
            apb_wr(`JPEG_REG_TABLE_DATA, word);
          end
          if ($fread(b0, h_fd) == 1) $fatal(1, "Huffman table size mismatch (too long): %s", h_path);
          $fclose(h_fd);
          apb_wr(`JPEG_REG_TABLE_COMMIT, 1);
        end
      end
    end

    $display("[jpeg_tool_tb] Q tables and Huffman tables loaded via APB.");

    // Configure registers
    apb_wr(`JPEG_REG_RESTART_INTERVAL, restart_interval_in);
    apb_wr(`JPEG_REG_TABLE_SELECT, select_in);
    apb_wr(`JPEG_REG_IMAGE_SIZE, (h_in << 16) | w_in);
    apb_wr(`JPEG_REG_FORMAT, fmt_in);
    apb_wr(`JPEG_REG_INPUT_LO, input_size_in[31:0]);
    apb_wr(`JPEG_REG_INPUT_HI, input_size_in[63:32]);
    limit = mode_in ? samples : capacity;
    apb_wr(`JPEG_REG_LIMIT_LO, limit[31:0]);
    apb_wr(`JPEG_REG_LIMIT_HI, limit[63:32]);

    for (int c = 0; c < 3; c++) begin
      apb_wr(`JPEG_REG_Y_LO + c * 8, bases[c][31:0]);
      apb_wr(`JPEG_REG_Y_HI + c * 8, bases[c][63:32]);
      apb_wr(`JPEG_REG_Y_STRIDE + c * 4, strides[c]);
    end

    apb_wr(`JPEG_REG_JPEG_LO, jpeg_base[31:0]);
    apb_wr(`JPEG_REG_JPEG_HI, jpeg_base[63:32]);

    // Load inputs to memory
    if (mode_in) begin
      string scan_path;
      int scan_fd;
      byte b;
      $sformat(scan_path, "%s/input.scan", job_dir);
      scan_fd = $fopen(scan_path, "rb");
      if (scan_fd == 0) $fatal(1, "missing scan file %s", scan_path);
      for (longint unsigned i = 0; i < input_size_in; i++) begin
        if ($fread(b, scan_fd) != 1) $fatal(1, "scan size mismatch: %s", scan_path);
        mem[jpeg_base + i] = b;
      end
      if ($fread(b, scan_fd) == 1) $fatal(1, "scan size mismatch (too long): %s", scan_path);
      $fclose(scan_fd);
    end else begin
      for (int c = 0; c < 3; c++) begin
        string in_path;
        int in_fd;
        byte b;
        $sformat(in_path, "%s/input%0d.bin", job_dir, c);
        in_fd = $fopen(in_path, "rb");
        if (in_fd == 0) $fatal(1, "missing plane file %s", in_path);
        for (int y = 0; y < heights[c]; y++) begin
          longint unsigned row_addr = bases[c] + longint'(y) * strides[c];
          for (int x = 0; x < widths[c]; x++) begin
            if ($fread(b, in_fd) != 1) $fatal(1, "plane size mismatch in %s at y=%0d x=%0d", in_path, y, x);
            mem[row_addr + x] = b;
          end
        end
        if ($fread(b, in_fd) == 1) $fatal(1, "plane size mismatch (too long): %s", in_path);
        $fclose(in_fd);
      end
    end

    $display("[jpeg_tool_tb] Input data loaded to memory (%0d bytes). Starting RTL core...", mode_in ? input_size_in : samples);

    // Start job
    begin_cycle = cycle_cnt;
    apb_wr(`JPEG_REG_CONTROL, mode_in ? 3 : 1);

    max_cycles = (blocks * 4000 + 1000000);
    if (max_cycles > 32'hffff_ffff) max_cycles = 32'hffff_ffff;
    wait_job(max_cycles, status);
    cycles = cycle_cnt - begin_cycle;

    if (status & 4) begin
      bit [31:0] err_code;
      apb_rd(`JPEG_REG_ERROR_CODE, err_code);
      $display("ERROR: RTL error code %0d", err_code);
      $fatal(1, "RTL error code %0d", err_code);
    end

    $display("[jpeg_tool_tb] RTL core completed in %0d cycles (status=0x%08x).", cycles, status);

    apb_rd(`JPEG_REG_OUTPUT_LO, bytes_lo);
    apb_rd(`JPEG_REG_OUTPUT_HI, bytes_hi);
    bytes_out = (longint'(bytes_hi) << 32) | bytes_lo;

    if (mode_in && bytes_out != samples)
      $fatal(1, "decoded sample count mismatch: got %0d, exp %0d", bytes_out, samples);
    if (!mode_in && bytes_out > capacity)
      $fatal(1, "encoded capacity exceeded: got %0d, cap %0d", bytes_out, capacity);

    // Save outputs
    if (mode_in) begin
      for (int c = 0; c < 3; c++) begin
        string out_path;
        int out_fd;
        $sformat(out_path, "%s/output%0d.bin", job_dir, c);
        out_fd = $fopen(out_path, "wb");
        if (out_fd == 0) $fatal(1, "output write failed: %s", out_path);
        for (int y = 0; y < heights[c]; y++) begin
          longint unsigned row_addr = bases[c] + longint'(y) * strides[c];
          for (int x = 0; x < widths[c]; x++) begin
            $fwrite(out_fd, "%c", mem[row_addr + x]);
          end
        end
        $fclose(out_fd);
      end
    end else begin
      string out_path;
      int out_fd;
      $sformat(out_path, "%s/output.scan", job_dir);
      out_fd = $fopen(out_path, "wb");
      if (out_fd == 0) $fatal(1, "output write failed: %s", out_path);
      for (longint unsigned i = 0; i < bytes_out; i++) begin
        $fwrite(out_fd, "%c", mem[jpeg_base + i]);
      end
      $fclose(out_fd);
    end

    $display("[jpeg_tool_tb] Output data saved successfully (%0d bytes).", bytes_out);
    $display("RTL %s cycles=%0d output_bytes=%0d", mode_in ? "decode" : "encode", cycles, bytes_out);
    $finish;
  endtask

  initial run_tool();

endmodule
