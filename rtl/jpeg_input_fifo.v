// Logical 2048-byte capacity includes the short-read packing registers.
module jpeg_input_fifo(
 input clk,rst_n,clear,input s_valid,output s_ready,input [63:0] s_data,input [7:0] s_keep,input s_last,
 output m_valid,input m_ready,output [63:0] m_data,output [7:0] m_keep,output m_last,
 output [11:0] used_bytes,output empty);
 wire pv,pr,pl,repack_ready;wire [63:0] pd;wire [7:0] pk;wire [4:0] pack_used;wire [11:0] fifo_used;
 function [3:0] pop;input [7:0] k;integer i;begin pop=0;for(i=0;i<8;i=i+1)pop=pop+{3'd0,k[i]};end endfunction
 wire [12:0] accepted_used={1'b0,used_bytes}+{9'd0,pop(s_keep)}-{9'd0,(m_valid&&m_ready?pop(m_keep):4'd0)};
 wire capacity_ready=accepted_used<=2048;
 assign s_ready=repack_ready&&capacity_ready;
 jpeg_repack repack(.clk(clk),.rst_n(rst_n),.clear(clear),.s_valid(s_valid&&capacity_ready),.s_ready(repack_ready),.s_data(s_data),.s_keep(s_keep),.s_last(s_last),.m_valid(pv),.m_ready(pr),.m_data(pd),.m_keep(pk),.m_last(pl),.used_bytes(pack_used));
 jpeg_stream_fifo fifo(.clk(clk),.rst_n(rst_n),.clear(clear),.s_valid(pv),.s_ready(pr),.s_data(pd),.s_keep(pk),.s_last(pl),.m_valid(m_valid),.m_ready(m_ready),.m_data(m_data),.m_keep(m_keep),.m_last(m_last),.used_bytes(fifo_used),.empty());
 assign used_bytes=fifo_used+{7'd0,pack_used};assign empty=used_bytes==0;
endmodule
