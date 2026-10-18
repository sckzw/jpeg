`timescale 1ns/1ps

module numeric_tb;
  reg clk = 0;
  reg rst_n = 0;
  reg start = 0;
  reg mode = 0;
  reg select_quant = 0;
  reg [7:0] q_value = 0;

  reg s_valid = 0;
  wire s_ready;
  reg signed [31:0] s_coef = 0;
  reg [5:0] s_index = 0;
  reg [1:0] s_component = 0;
  reg [31:0] s_block_seq = 0;
  reg s_last_block = 0;

  wire m_valid;
  reg m_ready = 0;
  wire signed [31:0] m_coef;
  wire [5:0] m_index;
  wire [1:0] m_component;
  wire [31:0] m_block_seq;
  wire m_last_block;

  wire error_valid;
  wire [7:0] error_code;

  numeric_top dut (
    .clk(clk),
    .rst_n(rst_n),
    .start(start),
    .mode(mode),
    .select_quant(select_quant),
    .q_value(q_value),
    .s_valid(s_valid),
    .s_ready(s_ready),
    .s_coef(s_coef),
    .s_index(s_index),
    .s_component(s_component),
    .s_block_seq(s_block_seq),
    .s_last_block(s_last_block),
    .m_valid(m_valid),
    .m_ready(m_ready),
    .m_coef(m_coef),
    .m_index(m_index),
    .m_component(m_component),
    .m_block_seq(m_block_seq),
    .m_last_block(m_last_block),
    .error_valid(error_valid),
    .error_code(error_code)
  );

  task tick;
    begin
      clk = 0; #1;
      clk = 1; #1;
    end
  endtask

  const int C[8][8] = '{
    '{5793, 5793, 5793, 5793, 5793, 5793, 5793, 5793},
    '{8035, 6811, 4551, 1598, -1598, -4551, -6811, -8035},
    '{7568, 3135, -3135, -7568, -7568, -3135, 3135, 7568},
    '{6811, -1598, -8035, -4551, 4551, 8035, 1598, -6811},
    '{5793, -5793, -5793, 5793, 5793, -5793, -5793, 5793},
    '{4551, -8035, 1598, 6811, -6811, -1598, 8035, -4551},
    '{3135, -7568, 7568, -3135, -3135, 7568, -7568, 3135},
    '{1598, -4551, 6811, -8035, 8035, -6811, 4551, -1598}
  };

  function automatic longint round14(input longint a);
    if (a < 0) return -((-a + 8192) / 16384);
    else return (a + 8192) / 16384;
  endfunction

  function automatic void transform(input int x[64], input bit t_mode, output int y[64]);
    longint t[64];
    longint a;
    for (int r = 0; r < 8; r++) begin
      for (int k = 0; k < 8; k++) begin
        a = 0;
        for (int n = 0; n < 8; n++) begin
          longint c_val = t_mode ? C[n][k] : C[k][n];
          longint x_val = t_mode ? x[r*8+n] : (x[r*8+n] - 128);
          a += c_val * x_val;
        end
        t[r*8+k] = round14(a);
      end
    end
    for (int r = 0; r < 8; r++) begin
      for (int c = 0; c < 8; c++) begin
        a = 0;
        for (int n = 0; n < 8; n++) begin
          longint c_val = t_mode ? C[n][r] : C[r][n];
          a += c_val * t[n*8+c];
        end
        a = round14(a);
        if (t_mode) begin
          a = a + 128;
          if (a < 0) a = 0;
          if (a > 255) a = 255;
        end
        y[r*8+c] = a;
      end
    end
  endfunction

  typedef struct {
    int in_val;
    int out_val;
    bit [7:0] q;
    bit [5:0] index;
    bit [1:0] component;
    bit [31:0] seq;
    bit last;
  } sample_t;

  reg [31:0] rng = 32'd20261005;
  function automatic [31:0] rand32;
    rng = rng ^ (rng << 13);
    rng = rng ^ (rng >> 17);
    rng = rng ^ (rng << 5);
    return rng;
  endfunction

  longint clocks = 0;

  task automatic run_samples(
    input bit t_mode,
    input bit q_mode,
    ref sample_t samples[$],
    output longint elapsed_cycles
  );
    longint begin_cycles;
    int sent, received;
    bit stalled;
    int held_coef;
    bit [5:0] held_idx;
    bit [1:0] held_comp;
    bit [31:0] held_seq;
    bit held_last;
    sample_t cur_sample;
    bit put, pop;

    mode = t_mode;
    select_quant = q_mode;
    start = 1;
    tick(); clocks++;
    start = 0;
    sent = 0;
    received = 0;
    begin_cycles = clocks;
    stalled = 0;
    held_coef = 0;
    held_idx = 0;
    held_comp = 0;
    held_seq = 0;
    held_last = 0;

    while (received < samples.size()) begin
      if (clocks - begin_cycles > samples.size() * 400 + 1000)
        $fatal(1, "numeric timeout");

      s_valid = (sent < samples.size()) && ((rand32() % 5) != 0);
      m_ready = (rand32() % 4) != 0;

      if (sent < samples.size()) begin
        cur_sample = samples[sent];
        s_coef = cur_sample.in_val;
        q_value = cur_sample.q;
        s_index = cur_sample.index;
        s_component = cur_sample.component;
        s_block_seq = cur_sample.seq;
        s_last_block = cur_sample.last;
      end

      clk = 0; #1;
      put = s_valid && s_ready;
      pop = m_valid && m_ready;

      if (error_valid)
        $fatal(1, "numeric error code=%0d", error_code);

      if (stalled && (!m_valid || m_coef !== held_coef || m_index !== held_idx ||
                      m_component !== held_comp || m_block_seq !== held_seq || m_last_block !== held_last))
        $fatal(1, "unstable numeric output");

      stalled = m_valid && !m_ready;
      held_coef = m_coef;
      held_idx = m_index;
      held_comp = m_component;
      held_seq = m_block_seq;
      held_last = m_last_block;

      if (pop) begin
        sample_t exp_sample = samples[received];
        if (m_coef !== exp_sample.out_val || m_index !== exp_sample.index ||
            m_component !== exp_sample.component || m_block_seq !== exp_sample.seq ||
            m_last_block !== exp_sample.last) begin
          $fatal(1, "numeric mismatch sample=%0d got=%0d exp=%0d", received, m_coef, exp_sample.out_val);
        end
        received++;
      end

      clk = 1; #1; clocks++;
      if (put) sent++;
    end
    elapsed_cycles = clocks - begin_cycles;
  endtask

  initial begin
    sample_t quant_samples[$];
    sample_t trans_samples[$];
    longint cycles;
    longint total_samples;
    int x_blk[64], y_blk[64];
    int x;
    longint a, out_val, abs_a;
    sample_t s;
    int b_val;

    total_samples = 0;

    // Reset sequence
    rst_n = 0;
    s_valid = 0;
    m_ready = 0;
    start = 0;
    tick(); clocks++;
    rst_n = 1;
    tick(); clocks++;

    // Quantization tests
    for (int t_mode = 0; t_mode <= 1; t_mode++) begin
      quant_samples.delete();
      for (int q = 1; q <= 255; q++) begin
        for (int i = 0; i < 72; i++) begin
          if (i == 0) x = 0;
          else if (i == 1) x = -2147483648;
          else if (i == 2) x = 2147483647;
          else x = int'(rand32());

          if (i >= 3 && i <= 8) begin
            b_val = 17 * q + q / 2 + (i / 2) - 2;
            x = (i % 2) ? -b_val : b_val;
          end
          if (t_mode) begin
            x = int'(rand32() % 16000001) - 8000000;
          end

          a = x;
          if (t_mode) begin
            out_val = a * q;
          end else begin
            abs_a = a < 0 ? -a : a;
            out_val = (2 * abs_a + q) / (2 * q);
            if (a < 0) out_val = -out_val;
          end

          s.in_val = x;
          s.out_val = int'(out_val);
          s.q = 8'(q);
          s.index = 6'(i % 64);
          s.component = 2'(q % 3);
          s.seq = q;
          s.last = (i == 71);
          quant_samples.push_back(s);
        end
      end
      run_samples(t_mode[0], 1'b1, quant_samples, cycles);
      total_samples += quant_samples.size();
      $display("quant mode=%0d vectors=%0d cycles=%0d", t_mode, quant_samples.size(), cycles);
    end

    // Transform tests
    for (int t_mode = 0; t_mode <= 1; t_mode++) begin
      trans_samples.delete();
      for (int b = 0; b < 128; b++) begin
        for (int i = 0; i < 64; i++) begin
          x_blk[i] = t_mode ? (int'(rand32() % 40001) - 20000) : int'(rand32() % 256);
        end
        if (b == 0) for (int i = 0; i < 64; i++) x_blk[i] = t_mode ? 0 : 128;
        if (b == 1) for (int i = 0; i < 64; i++) x_blk[i] = t_mode ? 2147483647 : 255;
        if (b == 2) for (int i = 0; i < 64; i++) x_blk[i] = t_mode ? -2147483648 : 0;

        transform(x_blk, t_mode[0], y_blk);
        for (int i = 0; i < 64; i++) begin
          s.in_val = x_blk[i];
          s.out_val = y_blk[i];
          s.q = 8'd16;
          s.index = 6'(i);
          s.component = 2'(b % 3);
          s.seq = b;
          s.last = (b == 127);
          trans_samples.push_back(s);
        end
      end
      run_samples(t_mode[0], 1'b0, trans_samples, cycles);
      total_samples += trans_samples.size();
      $display("transform mode=%0d blocks=128 cycles=%0d", t_mode, cycles);
    end

    // Inverse overflow error test
    select_quant = 1;
    mode = 1;
    s_valid = 0;
    m_ready = 1;
    start = 1;
    tick(); clocks++;
    start = 0;
    s_valid = 1;
    s_coef = 32'h7fffffff;
    q_value = 8'd255;
    tick(); clocks++;
    s_valid = 0;
    for (int i = 0; i < 40; i++) begin tick(); clocks++; end
    if (!error_valid || error_code != 8'd8)
      $fatal(1, "inverse overflow missing");

    // Zero Q error test
    for (int t_mode = 0; t_mode <= 1; t_mode++) begin
      mode = t_mode[0];
      start = 1;
      s_valid = 0;
      tick(); clocks++;
      start = 0;
      s_valid = 1;
      s_coef = 32'd123;
      q_value = 8'd0;
      tick(); clocks++;
      s_valid = 0;
      for (int i = 0; i < 40; i++) begin tick(); clocks++; end
      if (!error_valid || error_code != 8'd2)
        $fatal(1, "zero Q missing error");
    end

    $display("PASS numeric vectors=%0d seed=20261005", total_samples);
    $finish;
  end
endmodule
