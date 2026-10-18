`include "jpeg_defs.vh"
module jpeg_transform(
 input clk,rst_n,start,clear,mode,stop_request,
 input s_valid,output s_ready,input signed [31:0] s_coef,input [5:0] s_index,
 input [1:0] s_component,input [31:0] s_block_seq,input s_last_block,
 output m_valid,input m_ready,output signed [31:0] m_coef,output [5:0] m_index,
 output [1:0] m_component,output [31:0] m_block_seq,output m_last_block,
 output active,output reg done,output reg error_valid,output reg [7:0] error_code);
 `include "jpeg_c.vh"
 reg signed [31:0] x[0:127];reg signed [47:0] t[0:63];reg signed [31:0] y[0:63];
 reg fill_bank,process_bank;reg [1:0] input_full;reg [1:0] input_comp[0:1];reg [31:0] input_seq[0:1];reg input_last[0:1];
 reg [2:0] state;reg [6:0] issue;reg [5:0] out_idx;reg [1:0] comp;reg [31:0] seq;reg last;
 reg [4:0] pv;reg [5:0] pi[0:4];reg pp[0:4];
 reg signed [63:0] prod[0:7];reg signed [71:0] a[0:3],b[0:1],sum,rounded;
 reg signed [47:0] operand;reg signed [15:0] constant;
 reg signed [71:0] round_now;integer j;
 function signed [71:0] r14;input signed [71:0] z;begin if(z<0)r14=-(((-z)+72'sd8192)>>>14);else r14=(z+72'sd8192)>>>14;end endfunction
 assign s_ready=!input_full[fill_bank]&&!stop_request&&!error_valid;
 assign m_valid=state==5&&!stop_request&&!error_valid;
 assign m_coef=y[out_idx];assign m_index=out_idx;assign m_component=comp;assign m_block_seq=seq;assign m_last_block=last;
 assign active=state!=0||(|input_full);
 always @(posedge clk)begin
 if(!rst_n||clear||start)begin fill_bank<=0;process_bank<=0;input_full<=0;state<=0;issue<=0;out_idx<=0;pv<=0;done<=0;error_valid<=0;error_code<=0;comp<=0;seq<=0;last<=0;
 for(j=0;j<5;j=j+1)begin pi[j]<=0;pp[j]<=0;end end
 else if(!stop_request&&!error_valid)begin
 pv<={pv[3:0],((state==1||state==3)&&issue<64)};
 for(j=1;j<5;j=j+1)begin pi[j]<=pi[j-1];pp[j]<=pp[j-1];end
 if(s_valid&&s_ready)begin
 x[{fill_bank,s_index}]<=mode?s_coef:s_coef-32'sd128;
 if(s_index==0)begin input_comp[fill_bank]<=s_component;input_seq[fill_bank]<=s_block_seq;input_last[fill_bank]<=s_last_block;end
 if(s_index==63)begin input_full[fill_bank]<=1;fill_bank<=!fill_bank;end end
 if(state==0&&input_full[process_bank])begin state<=1;issue<=0;comp<=input_comp[process_bank];seq<=input_seq[process_bank];last<=input_last[process_bank];end
 if((state==1||state==3)&&issue<64)begin
 pi[0]<=issue[5:0];pp[0]<=state==3;
 for(j=0;j<8;j=j+1)begin
 if(state==1)operand={{16{x[{25'd0,process_bank,issue[5:3],3'b000}+j][31]}},x[{25'd0,process_bank,issue[5:3],3'b000}+j]};
 else operand=t[j*8+{29'd0,issue[2:0]}];
 if(state==1)constant=mode?cval(j[2:0],issue[2:0]):cval(issue[2:0],j[2:0]);
 else constant=mode?cval(j[2:0],issue[5:3]):cval(issue[5:3],j[2:0]);
 prod[j]<=operand*constant;
 end
 issue<=issue+1'b1;
 if(issue==63)state<=state==1?2:4;
 end
 for(j=0;j<4;j=j+1)a[j]<={{8{prod[j*2][63]}},prod[j*2]}+{{8{prod[j*2+1][63]}},prod[j*2+1]};
 for(j=0;j<2;j=j+1)b[j]<=a[j*2]+a[j*2+1];
 sum<=b[0]+b[1];rounded<=r14(sum);
 if(pv[4])begin
 if(!pp[4])begin t[pi[4]]<=rounded[47:0];if(pi[4]==63)begin state<=3;issue<=0;input_full[process_bank]<=0;process_bank<=!process_bank;end end
 else begin
 round_now=rounded;
 if(mode)begin round_now=rounded+72'sd128;y[pi[4]]<=round_now<0?0:(round_now>255?255:round_now[31:0]);end
 else if(rounded>72'sd2147483647||rounded< -72'sd2147483648)begin error_valid<=1;error_code<=`JPEG_ERR_NUMERIC;end
 else y[pi[4]]<=rounded[31:0];
 if(pi[4]==63)begin state<=5;out_idx<=0;end
 end end
 if(m_valid&&m_ready)begin if(out_idx==63)begin state<=0;if(last)done<=1;end else out_idx<=out_idx+1'b1;end
 end end
endmodule
