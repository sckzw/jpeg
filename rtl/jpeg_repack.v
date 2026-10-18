// Merge low-contiguous short words; only the final output word may be short.
module jpeg_repack(
 input clk,rst_n,clear,input s_valid,output s_ready,input [63:0] s_data,input [7:0] s_keep,input s_last,
 output m_valid,input m_ready,output [63:0] m_data,output [7:0] m_keep,output m_last,output [4:0] used_bytes);
 reg [63:0] partial_data,out_data;reg [2:0] partial_count;reg [7:0] out_keep;reg out_valid,out_last,finish_pending;
 reg [127:0] combined;reg [4:0] total;
 function [3:0] pop;input [7:0] k;integer i;begin pop=0;for(i=0;i<8;i=i+1)pop=pop+{3'd0,k[i]};end endfunction
 wire [3:0] nbytes=pop(s_keep);
 wire bypass=!out_valid&&partial_count==0&&!finish_pending&&s_keep==8'hff;
 assign s_ready=s_keep!=0&&!finish_pending&&(bypass?m_ready:(!out_valid||m_ready));
 assign m_valid=bypass?s_valid:out_valid;assign m_data=bypass?s_data:out_data;assign m_keep=bypass?s_keep:out_keep;assign m_last=bypass?s_last:out_last;
 assign used_bytes={2'd0,partial_count}+(out_valid?{1'b0,pop(out_keep)}:5'd0);
 always @(posedge clk)begin
 if(!rst_n||clear)begin partial_data<=0;partial_count<=0;out_data<=0;out_keep<=0;out_valid<=0;out_last<=0;finish_pending<=0;end
 else begin
 if(out_valid&&m_ready)out_valid<=0;
 if(finish_pending&&(!out_valid||m_ready))begin out_data<=partial_data;out_keep<=8'hff>>(8-partial_count);out_last<=1;out_valid<=1;partial_data<=0;partial_count<=0;finish_pending<=0;end
 if(s_valid&&s_ready&&!bypass)begin
 combined={64'd0,partial_data}|({64'd0,(s_data&(64'hffffffffffffffff>>(64-nbytes*8)))}<<(partial_count*8));
 total={2'd0,partial_count}+{1'b0,nbytes};
 if(total>=8)begin
 out_data<=combined[63:0];out_keep<=8'hff;out_last<=s_last&&total==8;out_valid<=1;
 partial_data<=combined[127:64];partial_count<=total[2:0];finish_pending<=s_last&&total>8;
 end else if(s_last)begin
 out_data<=combined[63:0];out_keep<=8'hff>>(8-total);out_last<=1;out_valid<=1;partial_data<=0;partial_count<=0;
 end else begin partial_data<=combined[63:0];partial_count<=total[2:0];end
 end end end
endmodule
