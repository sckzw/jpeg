`include "jpeg_defs.vh"
module jpeg_quant(
 input clk,rst_n,start,clear,mode,stop_request,
 input s_valid,output s_ready,input signed [31:0] s_coef,input [5:0] s_index,
 input [1:0] s_component,input [31:0] s_block_seq,input s_last_block,
 output [5:0] q_index,output [1:0] q_component,input [7:0] q_value,
 output m_valid,input m_ready,output signed [31:0] m_coef,output [5:0] m_index,
 output [1:0] m_component,output [31:0] m_block_seq,output m_last_block,
 output active,output reg done,output reg error_valid,output reg [7:0] error_code);
 // Stage 0 table read, stages 1..32 restoring division, stage 33 rounding.
 reg [33:0] valid;
 reg [31:0] dividend[0:32],quotient[0:32];reg [8:0] remn[0:32];reg [7:0] divisor[0:32];
 reg neg[0:32];reg [5:0] idx[0:33];reg [1:0] comp[0:33];reg [31:0] seq[0:33];reg last[0:33];
 reg signed [39:0] inverse[0:32];reg signed [31:0] result;reg bad[0:33];reg zero_bad[0:33];
 wire ce=(!valid[33]||m_ready)&&!stop_request&&!error_valid;
 reg [8:0] trial;reg [32:0] magnitude;reg signed [33:0] signed_result;integer i;
 function signed [39:0] positive_product;
 input signed [31:0] coef;input [7:0] q_byte;
 reg signed [40:0] a,b,z;
 begin a={{9{coef[31]}},coef};b=$signed({33'd0,q_byte});z=a*b;positive_product=z[39:0];end
 endfunction
 assign s_ready=ce;assign q_index=s_index;assign q_component=s_component;
 assign m_valid=valid[33]&&!stop_request&&!error_valid&&!bad[33];assign m_coef=result;
 assign m_index=idx[33];assign m_component=comp[33];assign m_block_seq=seq[33];assign m_last_block=last[33];assign active=|valid;
 always @(posedge clk)begin
 if(!rst_n||clear||start)begin valid<=0;result<=0;done<=0;error_valid<=0;error_code<=0;
 for(i=0;i<34;i=i+1)begin idx[i]<=0;comp[i]<=0;seq[i]<=0;last[i]<=0;bad[i]<=0;zero_bad[i]<=0;end end
 else begin
 if(m_valid&&m_ready&&m_index==63&&m_last_block)done<=1;
 if(valid[33]&&bad[33])begin error_valid<=1;error_code<=zero_bad[33]?`JPEG_ERR_TABLE:`JPEG_ERR_NUMERIC;end
 if(ce)begin
 valid<={valid[32:0],s_valid};
 if(s_valid)begin
 dividend[0]<=s_coef[31]?(~s_coef+32'd1):s_coef;quotient[0]<=0;remn[0]<=0;divisor[0]<=q_value;neg[0]<=s_coef[31];
 inverse[0]<=positive_product(s_coef,q_value);
 idx[0]<=s_index;comp[0]<=s_component;seq[0]<=s_block_seq;last[0]<=s_last_block;bad[0]<=q_value==0;zero_bad[0]<=q_value==0;
 end
 for(i=1;i<=32;i=i+1)begin
 trial={remn[i-1][7:0],dividend[i-1][31]};
 remn[i]<=trial>={1'b0,divisor[i-1]}?trial-{1'b0,divisor[i-1]}:trial;
 quotient[i]<={quotient[i-1][30:0],trial>={1'b0,divisor[i-1]}};
 dividend[i]<=dividend[i-1]<<1;divisor[i]<=divisor[i-1];neg[i]<=neg[i-1];inverse[i]<=inverse[i-1];
 idx[i]<=idx[i-1];comp[i]<=comp[i-1];seq[i]<=seq[i-1];last[i]<=last[i-1];bad[i]<=bad[i-1];zero_bad[i]<=zero_bad[i-1];
 end
 magnitude={1'b0,quotient[32]}+{32'd0,({remn[32],1'b0}>={2'd0,divisor[32]})};
 signed_result=neg[32]?-$signed({1'b0,magnitude}):$signed({1'b0,magnitude});
 result<=mode?inverse[32][31:0]:signed_result[31:0];
 bad[33]<=bad[32]||(mode?(inverse[32]>40'sd2147483647||inverse[32]< -40'sd2147483648):(signed_result>34'sd2147483647||signed_result< -34'sd2147483648));
 zero_bad[33]<=zero_bad[32];idx[33]<=idx[32];comp[33]<=comp[32];seq[33]<=seq[32];last[33]<=last[32];
 end end end
endmodule
