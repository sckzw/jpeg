`include "jpeg_defs.vh"
// Ordered two-bank block queue. Writer/reader ownership is independent.
module jpeg_block_stream #(parameter DATA_W=32)(
 input clk,rst_n,clear,stop_request,input write_zigzag,read_zigzag,
 input s_valid,output s_ready,input [DATA_W-1:0] s_data,input [5:0] s_index,
 input [1:0] s_component,input [31:0] s_block_seq,input s_last_block,
 output m_valid,input m_ready,output [DATA_W-1:0] m_data,output [5:0] m_index,
 output [1:0] m_component,output [31:0] m_block_seq,output m_last_block);
 reg fill_bank,read_bank,filling,requests_finished;reg [5:0] request_index;
 wire reserve_ready,write_ready,request_ready,response_valid;wire [1:0] full,free;
 wire reserve_valid=!filling&&!stop_request&&free[fill_bank];
 wire request_valid=full[read_bank]&&!requests_finished&&!stop_request;
 assign s_ready=filling&&write_ready&&!stop_request;assign m_valid=response_valid&&!stop_request;
 jpeg_block_ram #(.DATA_W(DATA_W)) storage(
 .clk(clk),.rst_n(rst_n),.clear(clear),.reserve_valid(reserve_valid),.reserve_bank(fill_bank),.reserve_ready(reserve_ready),
 .s_valid(s_valid&&filling&&!stop_request),.s_ready(write_ready),.s_bank(fill_bank),.s_index(s_index),.s_data(s_data),.s_zigzag(write_zigzag),.s_component(s_component),.s_block_seq(s_block_seq),.s_last_block(s_last_block),
 .req_valid(request_valid),.req_ready(request_ready),.req_bank(read_bank),.req_index(request_index),.req_zigzag(read_zigzag),
 .m_valid(response_valid),.m_ready(m_ready&&!stop_request),.m_data(m_data),.m_index(m_index),.m_component(m_component),.m_block_seq(m_block_seq),.m_last_block(m_last_block),.full(full),.free(free));
 always @(posedge clk)begin
 if(!rst_n||clear)begin fill_bank<=0;read_bank<=0;filling<=0;requests_finished<=0;request_index<=0;end
 else begin
 if(reserve_valid&&reserve_ready)filling<=1;
 if(s_valid&&s_ready&&s_index==63)begin filling<=0;fill_bank<=!fill_bank;end
 if(request_valid&&request_ready)begin if(request_index==63)requests_finished<=1;else request_index<=request_index+1'b1;end
 if(m_valid&&m_ready&&m_index==63)begin read_bank<=!read_bank;request_index<=0;requests_finished<=0;end
 end end
endmodule
