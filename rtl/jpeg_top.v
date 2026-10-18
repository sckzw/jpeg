`include "jpeg_defs.vh"
module jpeg_top #(parameter ADDR_W=64,ID_W=1)(
 input clk,rst_n,input psel,penable,pwrite,input [11:0] paddr,input [31:0] pwdata,output [31:0] prdata,output pready,pslverr,
 output [ID_W-1:0] m_axi_arid,output [ADDR_W-1:0] m_axi_araddr,output [7:0] m_axi_arlen,output [2:0] m_axi_arsize,
 output [1:0] m_axi_arburst,output m_axi_arlock,output [3:0] m_axi_arcache,output [2:0] m_axi_arprot,output [3:0] m_axi_arqos,output m_axi_arvalid,input m_axi_arready,
 input [ID_W-1:0] m_axi_rid,input [63:0] m_axi_rdata,input [1:0] m_axi_rresp,input m_axi_rlast,m_axi_rvalid,output m_axi_rready,
 output [ID_W-1:0] m_axi_awid,output [ADDR_W-1:0] m_axi_awaddr,output [7:0] m_axi_awlen,output [2:0] m_axi_awsize,
 output [1:0] m_axi_awburst,output m_axi_awlock,output [3:0] m_axi_awcache,output [2:0] m_axi_awprot,output [3:0] m_axi_awqos,output m_axi_awvalid,input m_axi_awready,
 output [63:0] m_axi_wdata,output [7:0] m_axi_wstrb,output m_axi_wlast,m_axi_wvalid,input m_axi_wready,
 input [ID_W-1:0] m_axi_bid,input [1:0] m_axi_bresp,input m_axi_bvalid,output m_axi_bready);
 wire busy,done,error,dma_idle;wire [7:0] error_code;wire [63:0] output_bytes;
 wire apb_start,apb_stop,clear_done,clear_error,idle_clear,mode;wire [15:0] width,height,restart_interval;wire [1:0] format;
 wire [63:0] input_bytes,output_limit,y_base,cb_base,cr_base,jpeg_base;wire [31:0] y_stride,cb_stride,cr_stride;
 wire [11:0] table_select;wire table_access,table_write,table_commit,table_ready,table_error;wire [2:0] table_kind;wire [1:0] table_id;wire [11:0] table_index;wire [31:0] table_wdata,table_rdata;wire [10:0] table_valid;
 wire start,clear,stop_request;wire [31:0] total_blocks;wire [63:0] samples;
 wire rd_idle,wr_idle,rd_done,wr_done,rd_err,wr_err;wire [7:0] rd_code,wr_code;wire [3:0] rd_outstanding,wr_outstanding;
 reg pipeline_done;wire fault_valid;wire [7:0] fault_code;
 wire [1:0] component;wire [31:0] block_seq,bx,by,cw,ch,stride;wire [63:0] image_base;wire last_block;reg advance;
 reg pixel_active,pixel_restart,desc_pending,desc_restart,pixels_done;reg [5:0] fill_index;reg [7:0] previous_byte;
 reg [3:0] issue_row,issue_col;reg rd_complete,wr_complete;reg [63:0] jpeg_read_offset,jpeg_write_offset;
 reg [63:0] request_addr;reg [3:0] request_len;reg [2:0] request_size;reg request_last,request_valid;
 wire request_ready;wire [10:0] reserved_bytes;wire [11:0] in_used,out_used;
 wire rd_valid,rd_ready;wire [63:0] rd_data;wire [7:0] rd_keep;wire rd_last;
 wire if_valid,if_ready;wire [63:0] if_data;wire [7:0] if_keep;wire if_last;
 wire ib_valid,ib_ready;wire [7:0] ib_byte;wire ib_last;
 wire ob_valid,ob_ready;wire [7:0] ob_byte;wire ob_last;
 wire pack_valid,pack_ready;wire [63:0] pack_data;wire [7:0] pack_keep;wire pack_last;
 wire of_valid,of_ready;wire [63:0] of_data;wire [7:0] of_keep;wire of_last;
 wire wr_req_ready,wr_s_ready;wire wr_req_valid,wr_s_valid,wr_request_last;wire [3:0] wr_request_len;wire [ADDR_W-1:0] wr_addr;wire [63:0] wr_data;wire [7:0] wr_keep;wire wr_last;
 reg [3:0] write_length,write_beat;reg output_eof;reg write_requested,row_pending;reg [63:0] row_data;reg [7:0] row_keep;reg [63:0] row_address;reg row_last;
 reg write_advance;
 wire [1:0] write_component;wire [31:0] write_seq,write_bx,write_by,write_cw,write_ch,write_stride;wire [63:0] write_base;wire write_last_block;
 jpeg_geometry write_geometry(.clk(clk),.rst_n(rst_n),.start(start),.clear(clear),.advance(write_advance),.width(width),.height(height),.format(format),.y_base(y_base),.cb_base(cb_base),.cr_base(cr_base),.y_stride(y_stride),.cb_stride(cb_stride),.cr_stride(cr_stride),.total_blocks(total_blocks),.component(write_component),.block_seq(write_seq),.last_block(write_last_block),.block_x(write_bx),.block_y(write_by),.component_width(write_cw),.component_height(write_ch),.base(write_base),.stride(write_stride));
 wire [63:0] read_remaining=input_bytes-jpeg_read_offset;
 integer row_width,remaining,chunk,page_left,rx,ry,burst_len;reg [63:0] address;
jpeg_apb apb(
 .restart_interval(restart_interval),
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
 .busy(busy),
 .done(done),
 .error(error),
 .dma_idle(dma_idle),
 .error_code(error_code),
 .output_bytes(output_bytes),
 .clear_done(clear_done),
 .clear_error(clear_error),
 .idle_clear(idle_clear),
 .mode(mode),
 .width(width),
 .height(height),
 .format(format),
 .input_bytes(input_bytes),
 .output_limit(output_limit),
 .y_base(y_base),
 .cb_base(cb_base),
 .cr_base(cr_base),
 .jpeg_base(jpeg_base),
 .y_stride(y_stride),
 .cb_stride(cb_stride),
 .cr_stride(cr_stride),
 .table_select(table_select),
 .table_access(table_access),
 .table_write(table_write),
 .table_commit(table_commit),
 .table_kind(table_kind),
 .table_id(table_id),
 .table_index(table_index),
 .table_wdata(table_wdata),
 .table_ready(table_ready),
 .table_error(table_error),
 .table_rdata(table_rdata),
 .table_valid(table_valid),
 .start(apb_start),
 .stop(apb_stop));
jpeg_ctrl #(.ADDR_W(ADDR_W)) ctrl(
 .restart_interval(restart_interval),
 .clk(clk),
 .rst_n(rst_n),
 .mode(mode),
 .width(width),
 .height(height),
 .format(format),
 .input_bytes(input_bytes),
 .output_limit(output_limit),
 .y_base(y_base),
 .cb_base(cb_base),
 .cr_base(cr_base),
 .jpeg_base(jpeg_base),
 .y_stride(y_stride),
 .cb_stride(cb_stride),
 .cr_stride(cr_stride),
 .table_select(table_select),
 .table_valid(table_valid),
 .clear_done(clear_done),
 .clear_error(clear_error),
 .idle_clear(idle_clear),
 .pipeline_done(pipeline_done),
 .fault_valid(fault_valid),
 .fault_code(fault_code),
 .start(start),
 .clear(clear),
 .stop_request(stop_request),
 .busy(busy),
 .done(done),
 .error(error),
 .error_code(error_code),
 .total_blocks(total_blocks),
 .samples(samples),
 .start_request(apb_start),
 .stop(apb_stop),
 .read_idle(rd_idle),
 .write_idle(wr_idle),
 .read_done(rd_done),
 .write_done(wr_done));
jpeg_geometry geometry(
 .clk(clk),
 .rst_n(rst_n),
 .start(start),
 .clear(clear),
 .advance(advance),
 .width(width),
 .height(height),
 .format(format),
 .y_base(y_base),
 .cb_base(cb_base),
 .cr_base(cr_base),
 .y_stride(y_stride),
 .cb_stride(cb_stride),
 .cr_stride(cr_stride),
 .total_blocks(total_blocks),
 .component(component),
 .block_seq(block_seq),
 .last_block(last_block),
 .stride(stride),
 .block_x(bx),
 .block_y(by),
 .component_width(cw),
 .component_height(ch),
 .base(image_base));
assign dma_idle=rd_idle&&wr_idle;
wire [5:0] q_index;wire [1:0] q_component;wire [7:0] q_value;wire [1:0] q_id=table_select[q_component*4+:2];
 wire h_ac,h_id;wire [7:0] h_symbol,dec_symbol_index,dec_symbol;wire [31:0] enc_entry;wire [2047:0] dec_header;
jpeg_tables tables(
 .clk(clk),
 .rst_n(rst_n),
 .q_id(q_id),
 .q_index(q_index),
 .q_value(q_value),
 .h_ac(h_ac),
 .h_id(h_id),
 .h_symbol(h_symbol),
 .enc_entry(enc_entry),
 .dec_header(dec_header),
 .dec_symbol_index(dec_symbol_index),
 .dec_symbol(dec_symbol),
 .table_valid(table_valid),
 .clear(idle_clear),
 .access_valid(table_access),
 .access_write(table_write),
 .commit(table_commit),
 .kind(table_kind),
 .id(table_id),
 .index(table_index),
 .wdata(table_wdata),
 .ready(table_ready),
 .access_error(table_error),
 .rdata(table_rdata));
jpeg_dma_read #(.ADDR_W(ADDR_W),.ID_W(ID_W)) dma_read(
 .clk(clk),
 .rst_n(rst_n),
 .start(start),
 .clear(clear),
 .stop_request(stop_request),
 .used_bytes(in_used),
 .reserved_bytes(reserved_bytes),
 .requests_complete(rd_complete),
 .req_valid(request_valid),
 .req_ready(request_ready),
 .req_addr(request_addr[ADDR_W-1:0]),
 .req_len(request_len),
 .req_size(request_size),
 .req_last(request_last),
 .m_valid(rd_valid),
 .m_ready(rd_ready),
 .m_data(rd_data),
 .m_keep(rd_keep),
 .m_last(rd_last),
 .idle(rd_idle),
 .done(rd_done),
 .error_valid(rd_err),
 .error_code(rd_code),
 .outstanding(rd_outstanding),
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
 .m_axi_rready(m_axi_rready));
jpeg_input_fifo input_fifo(
 .clk(clk),
 .rst_n(rst_n),
 .clear(clear||start),
 .s_valid(rd_valid),
 .s_ready(rd_ready),
 .s_data(rd_data),
 .s_keep(rd_keep),
 .s_last(rd_last),
 .m_valid(if_valid),
 .m_ready(if_ready),
 .m_data(if_data),
 .m_keep(if_keep),
 .m_last(if_last),
 .used_bytes(in_used),
 .empty());
jpeg_unpack unpack(
 .clk(clk),
 .rst_n(rst_n),
 .clear(clear||start),
 .s_valid(if_valid),
 .s_ready(if_ready),
 .s_data(if_data),
 .s_keep(if_keep),
 .s_last(if_last),
 .m_valid(ib_valid),
 .m_ready(ib_ready),
 .m_byte(ib_byte),
 .m_last(ib_last));
jpeg_pack pack(
 .clk(clk),
 .rst_n(rst_n),
 .clear(clear||start),
 .s_valid(ob_valid),
 .s_ready(ob_ready),
 .s_byte(ob_byte),
 .s_last(ob_last),
 .m_valid(pack_valid),
 .m_ready(pack_ready),
 .m_data(pack_data),
 .m_keep(pack_keep),
 .m_last(pack_last));
jpeg_stream_fifo output_fifo(
 .clk(clk),
 .rst_n(rst_n),
 .clear(clear||start),
 .s_valid(pack_valid),
 .s_ready(pack_ready),
 .s_data(pack_data),
 .s_keep(pack_keep),
 .s_last(pack_last),
 .m_valid(of_valid),
 .m_ready(of_ready),
 .m_data(of_data),
 .m_keep(of_keep),
 .m_last(of_last),
 .used_bytes(out_used),
 .empty());
jpeg_dma_write #(.ADDR_W(ADDR_W),.ID_W(ID_W)) dma_write(
 .clk(clk),
 .rst_n(rst_n),
 .start(start||apb_start),
 .clear(clear),
 .stop_request(stop_request),
 .output_limit(output_limit),
 .requests_complete(wr_complete),
 .req_valid(wr_req_valid),
 .req_ready(wr_req_ready),
 .req_addr(wr_addr),
 .req_len(wr_request_len),
 .req_size(3'd3),
 .req_last(wr_request_last),
 .s_valid(wr_s_valid),
 .s_ready(wr_s_ready),
 .s_data(wr_data),
 .s_keep(wr_keep),
 .s_last(wr_last),
 .idle(wr_idle),
 .done(wr_done),
 .error_valid(wr_err),
 .error_code(wr_code),
 .outstanding(wr_outstanding),
 .output_bytes(output_bytes),
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
 .m_axi_bready(m_axi_bready));
wire [63:0] jpeg_write_address=jpeg_base+jpeg_write_offset;
 wire [12:0] write_page_bytes=13'd4096-{1'b0,jpeg_write_address[11:0]};
 wire [9:0] write_page_beats=write_page_bytes[12:3];
 wire [4:0] desired_write_beats=out_used>=128?5'd16:({1'b0,out_used[6:3]}+{4'd0,(|out_used[2:0])});
 wire [4:0] selected_write_beats=write_page_beats<16&&write_page_beats<{5'd0,desired_write_beats}?write_page_beats[4:0]:desired_write_beats;
 assign wr_request_len=mode?4'd0:(selected_write_beats[3:0]-4'd1);
 assign wr_request_last=mode?row_last:(output_eof&&{1'b0,out_used}<=({8'd0,selected_write_beats}<<3));
 assign wr_req_valid=(mode?row_pending:(of_valid&&((out_used>=128)||output_eof||({1'b0,out_used}>=write_page_bytes))))&&!write_requested&&!stop_request;
 assign wr_s_valid=(mode?row_pending:of_valid)&&write_requested&&!stop_request;
 assign wr_addr=mode?row_address[ADDR_W-1:0]:(jpeg_base[ADDR_W-1:0]+jpeg_write_offset[ADDR_W-1:0]);
 assign wr_data=mode?row_data:of_data;assign wr_keep=mode?row_keep:of_keep;assign wr_last=mode?row_last:of_last;
 assign of_ready=!mode&&write_requested&&wr_s_ready&&!stop_request;
wire t_sv,t_sr,t_mv,t_mr,t_done,t_err,t_active;wire signed [31:0] t_si,t_mo;wire [5:0] t_sx,t_mx;wire [1:0] t_sc,t_mc;wire [31:0] t_ss,t_ms;wire t_sl,t_ml;wire [7:0] t_code;
wire q_sv,q_sr,q_mv,q_mr,q_done,q_err,q_active;wire signed [31:0] q_si,q_mo;wire [5:0] q_sx,q_mx;wire [1:0] q_sc,q_mc;wire [31:0] q_ss,q_ms;wire q_sl,q_ml;wire [7:0] q_code;
wire e_sv,e_sr,e_mv,e_mr,e_done,e_err,e_active;wire signed [31:0] e_si,e_mo;wire [5:0] e_sx,e_mx;wire [1:0] e_sc,e_mc;wire [31:0] e_ss,e_ms;wire e_sl,e_ml;wire [7:0] e_code;
jpeg_transform transform(
 .clk(clk),
 .rst_n(rst_n),
 .start(start),
 .clear(clear),
 .mode(mode),
 .stop_request(stop_request),
 .s_valid(t_sv),
 .s_ready(t_sr),
 .s_coef(t_si),
 .s_index(t_sx),
 .s_component(t_sc),
 .s_block_seq(t_ss),
 .s_last_block(t_sl),
 .m_valid(t_mv),
 .m_ready(t_mr),
 .m_coef(t_mo),
 .m_index(t_mx),
 .m_component(t_mc),
 .m_block_seq(t_ms),
 .m_last_block(t_ml),
 .active(t_active),
 .done(t_done),
 .error_valid(t_err),
 .error_code(t_code));
jpeg_quant quant(
 .clk(clk),
 .rst_n(rst_n),
 .start(start),
 .clear(clear),
 .mode(mode),
 .stop_request(stop_request),
 .s_valid(q_sv),
 .s_ready(q_sr),
 .s_coef(q_si),
 .s_index(q_sx),
 .s_component(q_sc),
 .s_block_seq(q_ss),
 .s_last_block(q_sl),
 .m_valid(q_mv),
 .m_ready(q_mr),
 .m_coef(q_mo),
 .m_index(q_mx),
 .m_component(q_mc),
 .m_block_seq(q_ms),
 .m_last_block(q_ml),
 .active(q_active),
 .done(q_done),
 .error_valid(q_err),
 .error_code(q_code),
 .q_index(q_index),
 .q_component(q_component),
 .q_value(q_value));
wire token_valid,token_ready,finish_valid,finish_ready;wire [31:0] token_bits;wire [5:0] token_nbits;
 wire [15:0] peek_bits;wire [4:0] available,consume_nbits;wire input_eof,consume_valid,consume_ready,decode_finish,b_done,b_err,b_active;wire [7:0] b_code;wire desc_ready;
wire restart_valid,restart_ready;wire restart_pending;wire [2:0] restart_expected;
jpeg_entropy entropy(
 .format(format),.restart_interval(restart_interval),
 .restart_valid(restart_valid),.restart_ready(restart_ready),.restart_expected(restart_expected),.segment_end(restart_pending),
 .clk(clk),
 .rst_n(rst_n),
 .start(start),
 .clear(clear),
 .mode(mode),
 .stop_request(stop_request),
 .table_select(table_select),
 .token_valid(token_valid),
 .token_ready(token_ready),
 .token_bits(token_bits),
 .token_nbits(token_nbits),
 .finish_valid(finish_valid),
 .finish_ready(finish_ready),
 .peek_bits(peek_bits),
 .available(available),
 .input_eof(input_eof),
 .consume_valid(consume_valid),
 .consume_ready(consume_ready),
 .consume_nbits(consume_nbits),
 .h_ac(h_ac),
 .h_id(h_id),
 .h_symbol(h_symbol),
 .enc_entry(enc_entry),
 .dec_header(dec_header),
 .dec_symbol_index(dec_symbol_index),
 .dec_symbol(dec_symbol),
 .decode_finish(decode_finish),
 .s_valid(e_sv),
 .s_ready(e_sr),
 .s_coef(e_si),
 .s_index(e_sx),
 .s_component(e_sc),
 .s_block_seq(e_ss),
 .s_last_block(e_sl),
 .m_valid(e_mv),
 .m_ready(e_mr),
 .m_coef(e_mo),
 .m_index(e_mx),
 .m_component(e_mc),
 .m_block_seq(e_ms),
 .m_last_block(e_ml),
 .active(e_active),
 .done(e_done),
 .error_valid(e_err),
 .error_code(e_code),
 .desc_valid(desc_pending),
 .desc_ready(desc_ready),
 .desc_component(component),
 .desc_block_seq(block_seq),
 .desc_last_block(last_block));
wire bs_ready;
jpeg_bitstream bitstream(
 .restart_enabled(restart_interval!=0),
 .restart_valid(restart_valid),.restart_ready(restart_ready),.restart_expected(restart_expected),.restart_pending(restart_pending),
 .clk(clk),
 .rst_n(rst_n),
 .start(start),
 .clear(clear),
 .mode(mode),
 .stop_request(stop_request),
 .token_valid(token_valid),
 .token_ready(token_ready),
 .token_bits(token_bits),
 .token_nbits(token_nbits),
 .finish_valid(finish_valid),
 .finish_ready(finish_ready),
 .peek_bits(peek_bits),
 .available(available),
 .input_eof(input_eof),
 .consume_valid(consume_valid),
 .consume_ready(consume_ready),
 .consume_nbits(consume_nbits),
 .decode_finish(decode_finish),
 .byte_valid(ob_valid),
 .byte_ready(ob_ready),
 .byte_data(ob_byte),
 .byte_last(ob_last),
 .s_valid(mode&&ib_valid),
 .s_ready(bs_ready),
 .s_byte(ib_byte),
 .s_last(ib_last),
 .done(b_done),
 .active(b_active),
 .error_valid(b_err),
 .error_code(b_code));
wire p_sv,p_sr,p_mv,p_mr;wire [7:0] p_sd,p_md;wire [5:0] p_sx,p_mx;wire [1:0] p_sc,p_mc;wire [31:0] p_ss,p_ms;wire p_sl,p_ml;
 jpeg_block_stream #(.DATA_W(8)) p_queue(
 .clk(clk),.rst_n(rst_n),.clear(clear||start),.stop_request(stop_request),.write_zigzag(1'b0),.read_zigzag(1'b0),
 .s_valid(p_sv),.s_ready(p_sr),.s_data(p_sd),.s_index(p_sx),.s_component(p_sc),.s_block_seq(p_ss),.s_last_block(p_sl),
 .m_valid(p_mv),.m_ready(p_mr),.m_data(p_md),.m_index(p_mx),.m_component(p_mc),.m_block_seq(p_ms),.m_last_block(p_ml));
wire r_sv,r_sr,r_mv,r_mr;wire [31:0] r_sd,r_md;wire [5:0] r_sx,r_mx;wire [1:0] r_sc,r_mc;wire [31:0] r_ss,r_ms;wire r_sl,r_ml;
 jpeg_block_stream #(.DATA_W(32)) r_queue(
 .clk(clk),.rst_n(rst_n),.clear(clear||start),.stop_request(stop_request),.write_zigzag(1'b0),.read_zigzag(1'b0),
 .s_valid(r_sv),.s_ready(r_sr),.s_data(r_sd),.s_index(r_sx),.s_component(r_sc),.s_block_seq(r_ss),.s_last_block(r_sl),
 .m_valid(r_mv),.m_ready(r_mr),.m_data(r_md),.m_index(r_mx),.m_component(r_mc),.m_block_seq(r_ms),.m_last_block(r_ml));
wire z_sv,z_sr,z_mv,z_mr;wire [31:0] z_sd,z_md;wire [5:0] z_sx,z_mx;wire [1:0] z_sc,z_mc;wire [31:0] z_ss,z_ms;wire z_sl,z_ml;
 jpeg_block_stream #(.DATA_W(32)) z_queue(
 .clk(clk),.rst_n(rst_n),.clear(clear||start),.stop_request(stop_request),.write_zigzag(mode),.read_zigzag(!mode),
 .s_valid(z_sv),.s_ready(z_sr),.s_data(z_sd),.s_index(z_sx),.s_component(z_sc),.s_block_seq(z_ss),.s_last_block(z_sl),
 .m_valid(z_mv),.m_ready(z_mr),.m_data(z_md),.m_index(z_mx),.m_component(z_mc),.m_block_seq(z_ms),.m_last_block(z_ml));

 assign p_sv=mode?t_mv:(pixel_active&&({29'd0,fill_index[2:0]}>=row_width||ib_valid));
 assign p_sd=mode?t_mo[7:0]:({29'd0,fill_index[2:0]}>=row_width?previous_byte:ib_byte);
 assign p_sx=mode?t_mx:fill_index;assign p_sc=mode?t_mc:component;assign p_ss=mode?t_ms:block_seq;assign p_sl=mode?t_ml:last_block;
 assign ib_ready=mode?bs_ready:(pixel_active&&{29'd0,fill_index[2:0]}<row_width&&p_sr);
 assign p_mr=mode?(!row_pending&&!stop_request):t_sr;
 assign t_sv=mode?r_mv:p_mv;assign t_si=mode?r_md:{24'd0,p_md};assign t_sx=mode?r_mx:p_mx;assign t_sc=mode?r_mc:p_mc;assign t_ss=mode?r_ms:p_ms;assign t_sl=mode?r_ml:p_ml;assign t_mr=mode?p_sr:r_sr;
 assign r_sv=mode?q_mv:t_mv;assign r_sd=mode?q_mo:t_mo;assign r_sx=mode?q_mx:t_mx;assign r_sc=mode?q_mc:t_mc;assign r_ss=mode?q_ms:t_ms;assign r_sl=mode?q_ml:t_ml;assign r_mr=mode?t_sr:q_sr;
 assign q_sv=mode?z_mv:r_mv;assign q_si=mode?z_md:r_md;assign q_sx=mode?z_mx:r_mx;assign q_sc=mode?z_mc:r_mc;assign q_ss=mode?z_ms:r_ms;assign q_sl=mode?z_ml:r_ml;assign q_mr=mode?r_sr:z_sr;
 assign z_sv=mode?e_mv:q_mv;assign z_sd=mode?e_mo:q_mo;assign z_sx=mode?e_mx:q_mx;assign z_sc=mode?e_mc:q_mc;assign z_ss=mode?e_ms:q_ms;assign z_sl=mode?e_ml:q_ml;assign z_mr=mode?q_sr:e_sr;
 assign e_sv=!mode&&z_mv;assign e_si=z_md;assign e_sx=z_mx;assign e_sc=z_mc;assign e_ss=z_ms;assign e_sl=z_ml;assign e_mr=mode&&z_sr;
 assign fault_valid=rd_err||wr_err||t_err||q_err||e_err||b_err;
 function [3:0] error_rank;input [7:0] code;begin
 case(code)`JPEG_ERR_READ:error_rank=0;`JPEG_ERR_WRITE:error_rank=1;`JPEG_ERR_CONFIG:error_rank=2;`JPEG_ERR_TABLE:error_rank=3;`JPEG_ERR_INPUT,`JPEG_ERR_PADDING:error_rank=4;`JPEG_ERR_ENTROPY:error_rank=5;`JPEG_ERR_CAPACITY:error_rank=6;`JPEG_ERR_NUMERIC:error_rank=7;`JPEG_ERR_STOP:error_rank=8;default:error_rank=15;endcase
 end endfunction
 reg [7:0] selected_fault;reg [3:0] best_rank;
 always @*begin
 selected_fault=0;best_rank=15;
 if(rd_err)begin selected_fault=rd_code;best_rank=error_rank(rd_code);end
 if(wr_err&&error_rank(wr_code)<best_rank)begin selected_fault=wr_code;best_rank=error_rank(wr_code);end
 if(q_err&&error_rank(q_code)<best_rank)begin selected_fault=q_code;best_rank=error_rank(q_code);end
 if(e_err&&error_rank(e_code)<best_rank)begin selected_fault=e_code;best_rank=error_rank(e_code);end
 if(b_err&&error_rank(b_code)<best_rank)begin selected_fault=b_code;best_rank=error_rank(b_code);end
 if(t_err&&error_rank(t_code)<best_rank)begin selected_fault=t_code;best_rank=error_rank(t_code);end
 end
 assign fault_code=selected_fault;
 // Read request generator. Right-edge access is naturally aligned 4/2/1 bytes.
 always @*begin
 row_width=bx>=cw?1:((cw-bx)>=8?8:(cw-bx));
 request_valid=0;request_addr=0;request_len=0;request_size=0;request_last=0;
 burst_len=0;remaining=0;chunk=0;page_left=0;rx=0;ry=0;address=0;
 if(mode&&!rd_complete&&busy&&!stop_request)begin
 address=jpeg_base+jpeg_read_offset;remaining=read_remaining>128?128:read_remaining[31:0];
 page_left=4096-{20'd0,address[11:0]};if(remaining>page_left)remaining=page_left;
 if(remaining>=8)begin request_size=3;burst_len=(remaining/8)-1;request_len=burst_len[3:0];chunk=({28'd0,request_len}+1)*8;end
 else if(remaining>=4&&address[1:0]==0)begin request_size=2;chunk=4;end
 else if(remaining>=2&&address[0]==0)begin request_size=1;chunk=2;end
 else begin request_size=0;chunk=1;end
 request_addr=address;request_valid=1;request_last=jpeg_read_offset+{32'd0,chunk[31:0]}==input_bytes;
 end else if(!mode&&pixel_active&&issue_row<8&&!stop_request)begin
 rx=bx>=cw?cw-1:bx+{28'd0,issue_col};ry=by+{28'd0,issue_row}>=ch?ch-1:by+{28'd0,issue_row};
 address=image_base+{32'd0,ry[31:0]}*{32'd0,stride}+{32'd0,rx[31:0]};remaining=row_width-{28'd0,issue_col};
 if(remaining>=8&&address[2:0]==0)begin request_size=3;chunk=8;end
 else if(remaining>=4&&address[1:0]==0)begin request_size=2;chunk=4;end
 else if(remaining>=2&&address[0]==0)begin request_size=1;chunk=2;end
 else begin request_size=0;chunk=1;end
 request_addr=address;request_valid=1;request_last=last_block&&issue_row==7&&{28'd0,issue_col}+chunk==row_width;
 end end
 always @(posedge clk)begin
 if(!rst_n||clear||start)begin
 pixel_active<=start&&!mode;pixel_restart<=0;desc_pending<=start&&mode;desc_restart<=0;pixels_done<=0;
 fill_index<=0;previous_byte<=0;issue_row<=0;issue_col<=0;rd_complete<=0;wr_complete<=0;jpeg_read_offset<=0;jpeg_write_offset<=0;advance<=0;write_advance<=0;pipeline_done<=0;write_length<=0;write_beat<=0;output_eof<=0;write_requested<=0;row_pending<=0;row_data<=0;row_keep<=0;row_address<=0;row_last<=0;
 end else if(!stop_request)begin
 advance<=0;write_advance<=0;
 if(pixel_restart)begin pixel_active<=1;pixel_restart<=0;fill_index<=0;issue_row<=0;issue_col<=0;end
 if(desc_restart)begin desc_pending<=1;desc_restart<=0;end
 if(mode&&desc_pending&&desc_ready)desc_pending<=0;
 if(request_valid&&request_ready)begin
 if(mode)jpeg_read_offset<=jpeg_read_offset+{32'd0,chunk[31:0]};
 else if({28'd0,issue_col}+chunk==row_width)begin issue_col<=0;issue_row<=issue_row+1'b1;end
 else issue_col<=issue_col+chunk[3:0];
 if(request_last)rd_complete<=1;
 end
 if(pack_valid&&pack_ready&&pack_last)output_eof<=1;
 if(wr_req_valid&&wr_req_ready)begin write_requested<=1;write_length<=wr_request_len;write_beat<=0;end
 if(wr_s_valid&&wr_s_ready)begin
 if(write_beat==write_length)write_requested<=0;else write_beat<=write_beat+1'b1;
 if(mode)begin row_pending<=0;row_data<=0;row_keep<=0;end else jpeg_write_offset<=jpeg_write_offset+8;
 if(wr_last)wr_complete<=1;
 end
 if(!mode&&p_sv&&p_sr)begin
 if({29'd0,fill_index[2:0]}<row_width)previous_byte<=ib_byte;
 if(fill_index==63)begin pixel_active<=0;if(!last_block)begin advance<=1;pixel_restart<=1;end end
 else fill_index<=fill_index+1'b1;
 end
 if(mode&&e_mv&&e_mr&&e_mx==63&&!e_ml)begin advance<=1;desc_restart<=1;end
 if(mode&&p_mv&&p_mr)begin
 row_data[p_mx[2:0]*8+:8]<=p_md;
 if(write_bx+{29'd0,p_mx[2:0]}<write_cw&&write_by+{29'd0,p_mx[5:3]}<write_ch)row_keep[p_mx[2:0]]<=1;
 if(p_mx[2:0]==7)begin
 if(write_bx<write_cw&&write_by+{29'd0,p_mx[5:3]}<write_ch)begin
 row_pending<=1;row_address<=write_base+({32'd0,write_by}+{61'd0,p_mx[5:3]})*{32'd0,write_stride}+{32'd0,write_bx};
 row_last<=p_ml&&(p_mx[5:3]==7||write_by+{29'd0,p_mx[5:3]}==write_ch-1);
 end else begin row_data<=0;row_keep<=0;end
 end
 if(p_mx==63)begin if(p_ml)pixels_done<=1;else write_advance<=1;end
 end
 pipeline_done<=t_done&&q_done&&e_done&&b_done&&(!mode||pixels_done);
 end end
endmodule
