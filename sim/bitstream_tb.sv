`timescale 1ns/1ps

module bitstream_tb;
  reg clk = 0;
  reg rst_n = 0;
  reg start = 0;
  reg clear = 0;
  reg mode = 0;
  reg stop_request = 0;
  reg restart_enabled = 0;
  reg [2:0] restart_expected = 0;
  reg restart_valid = 0;
  wire restart_ready;
  wire restart_pending;

  reg token_valid = 0;
  wire token_ready;
  reg [31:0] token_bits = 0;
  reg [5:0] token_nbits = 0;
  reg finish_valid = 0;
  wire finish_ready;

  wire byte_valid;
  reg byte_ready = 0;
  wire [7:0] byte_data;
  wire byte_last;

  reg s_valid = 0;
  wire s_ready;
  reg [7:0] s_byte = 0;
  reg s_last = 0;

  wire [15:0] peek_bits;
  wire [4:0] available;
  wire input_eof;
  reg consume_valid = 0;
  wire consume_ready;
  reg [4:0] consume_nbits = 0;
  reg decode_finish = 0;

  wire active;
  wire done;
  wire error_valid;
  wire [7:0] error_code;

  jpeg_bitstream dut (
    .clk(clk),
    .rst_n(rst_n),
    .start(start),
    .clear(clear),
    .mode(mode),
    .stop_request(stop_request),
    .restart_enabled(restart_enabled),
    .restart_expected(restart_expected),
    .restart_valid(restart_valid),
    .restart_ready(restart_ready),
    .restart_pending(restart_pending),
    .token_valid(token_valid),
    .token_ready(token_ready),
    .token_bits(token_bits),
    .token_nbits(token_nbits),
    .finish_valid(finish_valid),
    .finish_ready(finish_ready),
    .byte_valid(byte_valid),
    .byte_ready(byte_ready),
    .byte_data(byte_data),
    .byte_last(byte_last),
    .s_valid(s_valid),
    .s_ready(s_ready),
    .s_byte(s_byte),
    .s_last(s_last),
    .peek_bits(peek_bits),
    .available(available),
    .input_eof(input_eof),
    .consume_valid(consume_valid),
    .consume_ready(consume_ready),
    .consume_nbits(consume_nbits),
    .decode_finish(decode_finish),
    .active(active),
    .done(done),
    .error_valid(error_valid),
    .error_code(error_code)
  );

  task tick;
    begin
      clk = 0; #1;
      clk = 1; #1;
    end
  endtask

  reg [31:0] rng = 32'd20261005;
  function automatic [31:0] rand32;
    rng = rng ^ (rng << 13);
    rng = rng ^ (rng >> 17);
    rng = rng ^ (rng << 5);
    return rng;
  endfunction

  typedef struct {
    bit [31:0] bits;
    int n;
  } token_t;

  task automatic start_job(input bit job_mode);
    mode = job_mode;
    start = 1;
    token_valid = 0;
    finish_valid = 0;
    s_valid = 0;
    consume_valid = 0;
    decode_finish = 0;
    tick();
    start = 0;
  endtask

  initial begin
    int test, j, k;
    int bytes_total;
    token_t tokens[$];
    bit bits_q[$];
    bit padded_q[$];
    byte expected_q[$];
    int sent, received;
    bit finish, held;
    byte held_byte;
    bit held_last;
    int cycle;
    bit put, ff, pop;
    int consumed;
    int n_consume;
    int pad, marker;
    int val;
    byte rst_stream[$];
    bit rst_consumed;
    int bad;
    int tok_n;
    bit [31:0] tok_v;
    byte enc_b;
    token_t tok;
    int n_rand;

    bytes_total = 0;

    // Reset sequence
    restart_enabled = 0;
    restart_valid = 0;
    restart_expected = 0;
    rst_n = 0;
    start = 0;
    clear = 0;
    mode = 0;
    stop_request = 0;
    token_valid = 0;
    finish_valid = 0;
    s_valid = 0;
    consume_valid = 0;
    decode_finish = 0;
    byte_ready = 0;
    tick();
    rst_n = 1;

    // 100 roundtrip tests
    for (test = 0; test < 100; test++) begin
      tokens.delete();
      bits_q.delete();
      padded_q.delete();
      expected_q.delete();

      for (j = 0; j < 100; j++) begin
        tok_n = (j < 8) ? (j + 1) : (1 + int'(rand32() % 27));
        tok_v = (test == 0) ? 32'hffffffff : rand32();
        tok.bits = tok_v;
        tok.n = tok_n;
        tokens.push_back(tok);
        for (k = tok_n - 1; k >= 0; k--) begin
          bits_q.push_back(tok_v[k]);
        end
      end

      padded_q = bits_q;
      while ((padded_q.size() % 8) != 0) begin
        padded_q.push_back(1'b1);
      end

      for (j = 0; j < padded_q.size(); j += 8) begin
        enc_b = 0;
        for (k = 0; k < 8; k++) begin
          enc_b = (enc_b << 1) | byte'(padded_q[j + k]);
        end
        expected_q.push_back(enc_b);
        if (enc_b == 8'hff) expected_q.push_back(8'h00);
      end

      // Encode
      start_job(1'b0);
      sent = 0;
      received = 0;
      finish = 0;
      held = 0;
      held_byte = 0;
      held_last = 0;

      cycle = 0;
      while (!done) begin
        if (cycle > 10000) $fatal(1, "encode timeout");
        token_valid = (sent < tokens.size()) && ((rand32() % 5) != 0);
        if (sent < tokens.size()) begin
          token_bits = tokens[sent].bits;
          token_nbits = tokens[sent].n;
        end
        finish_valid = (sent == tokens.size()) && !finish;
        byte_ready = (rand32() % 4) != 0;

        clk = 0; #1;
        put = token_valid && token_ready;
        ff = finish_valid && finish_ready;
        pop = byte_valid && byte_ready;

        if (held && (!byte_valid || byte_data !== held_byte || byte_last !== held_last))
          $fatal(1, "byte hold");

        held = byte_valid && !byte_ready;
        held_byte = byte_data;
        held_last = byte_last;

        if (pop) begin
          if (received >= expected_q.size() || byte_data !== expected_q[received] ||
              byte_last !== (received == expected_q.size() - 1))
            $fatal(1, "encode byte %0d got=%02x exp=%02x last=%0d", received, byte_data, expected_q[received], byte_last);
          received++;
        end

        if (error_valid) $fatal(1, "encode error code=%0d", error_code);
        clk = 1; #1;
        if (put) sent++;
        if (ff) finish = 1;
        cycle++;
      end

      if (received != expected_q.size()) $fatal(1, "encode length mismatch");
      bytes_total += received;

      // Decode
      start_job(1'b1);
      sent = 0;
      consumed = 0;

      cycle = 0;
      while (!done) begin
        if (cycle > 10000) $fatal(1, "decode timeout");
        s_valid = (sent < expected_q.size()) && ((rand32() % 5) != 0);
        if (sent < expected_q.size()) begin
          s_byte = expected_q[sent];
          s_last = (sent == expected_q.size() - 1);
        end

        clk = 0; #1;
        n_rand = 1 + int'(rand32() % 16);
        n_consume = bits_q.size() - consumed;
        if (int'(available) < n_consume) n_consume = int'(available);
        if (n_rand < n_consume) n_consume = n_rand;

        consume_valid = (n_consume > 0) && ((rand32() % 4) != 0);
        consume_nbits = 5'(n_consume);
        decode_finish = (consumed == bits_q.size());
        #1;

        put = s_valid && s_ready;
        pop = consume_valid && consume_ready;

        if (pop) begin
          for (j = 0; j < n_consume; j++) begin
            if (peek_bits[15 - j] !== bits_q[consumed + j])
              $fatal(1, "decode bit order mismatch at bit %0d", consumed + j);
          end
          consumed += n_consume;
        end

        if (error_valid) $fatal(1, "decode error %0d", error_code);
        clk = 1; #1;
        if (put) sent++;
        cycle++;
      end

      if (consumed != bits_q.size()) $fatal(1, "decode bit count");
    end

    // Malformed stream tests
    for (bad = 255; bad <= 257; bad++) begin
      start_job(1'b1);
      s_valid = 1;
      s_byte = 8'hff;
      s_last = (bad == 255);
      tick();
      if (bad != 255) begin
        s_byte = (bad == 256) ? 8'h01 : 8'h00;
        s_last = 1;
        tick();
      end
      s_valid = 0;
      if (bad == 257) begin
        decode_finish = 1;
        tick();
      end
      if (!error_valid || error_code != ((bad == 257) ? 8'd10 : 8'd6))
        $fatal(1, "malformed stream missing error bad=%0d got=%0d", bad, error_code);
    end

    // Restart marker tests (decode only)
    restart_enabled = 1;
    for (pad = 0; pad < 8; pad++) begin
      for (marker = 0; marker < 8; marker++) begin
        start_job(1'b1);
        restart_expected = 3'(marker);
        restart_valid = 0;

        val = (32'ha5 & (32'hff << pad)) | ((32'h1 << pad) - 1);
        rst_stream.delete();
        rst_stream.push_back(byte'(val));
        if (byte'(val) == 8'hff) rst_stream.push_back(8'h00);
        rst_stream.push_back(8'hff);
        rst_stream.push_back(8'hff);
        rst_stream.push_back(byte'(8'hd0 + marker));

        sent = 0;
        rst_consumed = 0;
        cycle = 0;
        while (!restart_pending) begin
          if (cycle > 1000) $fatal(1, "restart parser timeout");
          s_valid = (sent < rst_stream.size()) && ((rand32() % 4) != 0);
          s_last = 0;
          if (sent < rst_stream.size()) s_byte = rst_stream[sent];

          consume_valid = 0;
          clk = 0; #1;
          if (!rst_consumed && int'(available) >= (8 - pad)) begin
            consume_nbits = 5'(8 - pad);
            consume_valid = 1;
          end
          #1;
          put = s_valid && s_ready;
          pop = consume_valid && consume_ready;
          tick();
          if (put) sent++;
          if (pop) rst_consumed = 1;
          cycle++;
        end

        s_valid = 0;
        consume_valid = 0;
        if (!rst_consumed) begin
          consume_nbits = 5'(8 - pad);
          consume_valid = 1;
          tick();
          consume_valid = 0;
        end

        for (j = 0; j < 20; j++) begin
          clk = 0; #1;
          if (s_ready || !restart_pending || int'(available) != pad)
            $fatal(1, "restart boundary hold");
          tick();
        end

        restart_valid = 1;
        clk = 0; #1;
        if (!restart_ready) $fatal(1, "restart acknowledgment missing");
        tick();
        restart_valid = 0;

        if (error_valid || restart_pending || available != 0)
          $fatal(1, "restart reservoir reset");
      end
    end

    // Marker number, non-one pad, and unmatched final RST errors
    for (bad = 0; bad < 3; bad++) begin
      start_job(1'b1);
      restart_expected = 0;
      restart_valid = 0;
      s_valid = 1;
      s_last = 0;
      s_byte = (bad == 1) ? 8'h00 : 8'hff;
      tick();
      if (bad == 1) begin
        s_byte = 8'hff;
        tick();
      end
      s_byte = (bad == 0) ? 8'hd1 : 8'hd0;
      tick();
      s_valid = 0;
      if (bad == 1) begin
        consume_nbits = 5'd1;
        consume_valid = 1;
        tick();
        consume_valid = 0;
      end
      if (bad == 2) decode_finish = 1;
      else restart_valid = 1;
      tick();
      if (!error_valid || error_code != ((bad == 1) ? 8'd10 : 8'd6))
        $fatal(1, "restart malformed boundary error bad=%0d", bad);
      restart_valid = 0;
      decode_finish = 0;
    end

    // FF fill before stuffed zero
    start_job(1'b1);
    restart_valid = 0;
    s_valid = 1;
    s_last = 0;
    s_byte = 8'hff;
    tick(); tick();
    s_byte = 8'h00;
    tick();
    s_valid = 0;
    if (!error_valid || error_code != 8'd6)
      $fatal(1, "FF fill before stuffed zero accepted");

    restart_enabled = 0;

    $display("PASS bitstream restart: 64 padding/number combinations, FF00, fill bytes, boundary stalls, malformed markers");
    $display("PASS bitstream 100 roundtrips bytes=%0d seed=20261005", bytes_total);
    $finish;
  end
endmodule
