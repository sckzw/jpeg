`include "jpeg_defs.vh"
// 256 x 64-bit FIFO. keep is low-contiguous; ownership ends at word transfer.
module jpeg_stream_fifo #(parameter DEPTH=256)(
 input clk,rst_n,clear,
 input s_valid, output s_ready, input [63:0] s_data, input [7:0] s_keep,input s_last,
 output m_valid,input m_ready,output [63:0] m_data,output [7:0] m_keep,output m_last,
 output reg [11:0] used_bytes,output empty);
 reg [63:0] data_mem[0:DEPTH-1]; reg [7:0] keep_mem[0:DEPTH-1]; reg last_mem[0:DEPTH-1];
 integer wr,rd,count;
 function [3:0] pop; input [7:0] k; integer i; begin pop=0;for(i=0;i<8;i=i+1)pop=pop+{3'd0,k[i]};end endfunction
 assign m_valid=count!=0; assign empty=count==0;
 assign s_ready=(count<DEPTH || (m_valid&&m_ready)) && s_keep!=0;
 assign m_data=data_mem[rd]; assign m_keep=keep_mem[rd]; assign m_last=last_mem[rd];
 wire push=s_valid&&s_ready, pull=m_valid&&m_ready;
 always @(posedge clk) begin
 if(!rst_n||clear) begin wr<=0;rd<=0;count<=0;used_bytes<=0;end
 else begin
 if(push)begin data_mem[wr]<=s_data;keep_mem[wr]<=s_keep;last_mem[wr]<=s_last;wr<=wr==DEPTH-1?0:wr+1;end
 if(pull)rd<=rd==DEPTH-1?0:rd+1;
 case({push,pull})
 2'b10:begin count<=count+1;used_bytes<=used_bytes+{8'd0,pop(s_keep)};end
 2'b01:begin count<=count-1;used_bytes<=used_bytes-{8'd0,pop(m_keep)};end
 2'b11:used_bytes<=used_bytes+{8'd0,pop(s_keep)}-{8'd0,pop(m_keep)};
 default:begin end
 endcase
 end end
endmodule

// The source FIFO word is released only with its final byte.
module jpeg_unpack(input clk,rst_n,clear,input s_valid,output s_ready,input [63:0] s_data,input [7:0] s_keep,input s_last,
 output m_valid,input m_ready,output [7:0] m_byte,output m_last);
 reg [2:0] byte_index;
 wire [7:0] remaining_keep=s_keep>>({1'b0,byte_index}+4'd1);
 wire final_byte=remaining_keep==0;
 assign m_valid=s_valid&&s_keep!=0;assign m_byte=s_data[byte_index*8+:8];assign m_last=s_last&&final_byte;
 assign s_ready=m_valid&&m_ready&&final_byte;
 always @(posedge clk)begin
 if(!rst_n||clear)byte_index<=0;
 else if(m_valid&&m_ready)begin if(final_byte)byte_index<=0;else byte_index<=byte_index+1'b1;end
 end
endmodule

module jpeg_pack(input clk,rst_n,clear,input s_valid,output s_ready,input [7:0] s_byte,input s_last,
 output reg m_valid,input m_ready,output reg [63:0] m_data,output reg [7:0] m_keep,output reg m_last);
 reg [63:0] data;reg [2:0] count;
 assign s_ready=!m_valid||m_ready;
 always @(posedge clk)begin
 if(!rst_n||clear)begin data<=0;count<=0;m_valid<=0;m_data<=0;m_keep<=0;m_last<=0;end
 else begin
 if(m_valid&&m_ready)m_valid<=0;
 if(s_valid&&s_ready)begin
 data[count*8+:8]<=s_byte;
 if(count==7||s_last)begin
 m_data<=data | ({56'd0,s_byte} << (count*8));
 m_keep<=8'hff >> (7-count);m_last<=s_last;m_valid<=1;count<=0;data<=0;
 end else count<=count+1'b1;
 end end end
endmodule
