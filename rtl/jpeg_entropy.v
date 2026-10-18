`include "jpeg_defs.vh"
module jpeg_entropy(
 input clk,rst_n,start,clear,mode,stop_request,input [11:0] table_select,
 input [1:0] format,input [15:0] restart_interval,input segment_end,
 output restart_valid,input restart_ready,output [2:0] restart_expected,
 input s_valid,output s_ready,input signed [31:0] s_coef,input [5:0] s_index,input [1:0] s_component,input [31:0] s_block_seq,input s_last_block,
 input desc_valid,output desc_ready,input [1:0] desc_component,input [31:0] desc_block_seq,input desc_last_block,
 output token_valid,input token_ready,output [31:0] token_bits,output [5:0] token_nbits,
 output finish_valid,input finish_ready,
 input [15:0] peek_bits,input [4:0] available,input input_eof,
 output consume_valid,input consume_ready,output [4:0] consume_nbits,
 output m_valid,input m_ready,output signed [31:0] m_coef,output [5:0] m_index,output [1:0] m_component,output [31:0] m_block_seq,output m_last_block,
 output h_ac,output h_id,output [7:0] h_symbol,input [31:0] enc_entry,input [2047:0] dec_header,
 output [7:0] dec_symbol_index,input [7:0] dec_symbol,
 output decode_finish,output active,output reg done,output reg error_valid,output reg [7:0] error_code);
 localparam E_IN=0,E_TOKEN=1,E_FINISH=2,D_DESC=3,D_CODE=4,D_EXTRA=5,D_OUT=6,D_END=7,D_RESTART=10;
 reg [3:0] state;reg [2:0] block_slot,rst_number;reg [15:0] interval_mcus;
 wire [2:0] blocks_per_mcu=format==0?3'd3:(format==1?3'd4:3'd6);
 assign restart_valid=mode&&state==D_RESTART&&!stop_request&&!error_valid;
 assign restart_expected=rst_number;
 reg signed [31:0] pred[0:2];reg [1:0] comp;reg [31:0] seq;reg last;reg [5:0] idx;
 reg [6:0] run;reg [7:0] symbol;reg [4:0] size;reg [31:0] extra;reg [31:0] tok;reg [5:0] toklen;
 reg signed [31:0] value;reg [6:0] zeros;reg pending_value;reg token_dc,token_final,token_retry;reg signed [31:0] new_pred;
 reg signed [32:0] diff,dc_sum;reg [32:0] magnitude;integer i,cat,l;reg [15:0] code,mn,mx,symbol_offset;reg [8:0] cnt;reg [7:0] fst;
 reg match;reg [4:0] match_len;reg [7:0] match_pos;reg signed [32:0] decoded;
 assign s_ready=!mode&&state==E_IN&&!stop_request&&!error_valid;
 assign desc_ready=mode&&state==D_DESC&&!stop_request&&!error_valid;
 assign h_ac=mode?(idx!=0):(symbol[7:4]!=0||!token_dc);
 assign h_id=table_select[comp*4+(h_ac?3:2)];
 assign h_symbol=symbol;
 assign token_valid=state==E_TOKEN&&!error_valid&&!stop_request;
 assign token_bits=tok;assign token_nbits=toklen;
 assign finish_valid=state==E_FINISH&&!stop_request;
 assign m_valid=state==D_OUT&&!error_valid&&!stop_request;
 assign m_coef=zeros!=0?32'sd0:value;assign m_index=idx;assign m_component=comp;assign m_block_seq=seq;assign m_last_block=last;
 assign dec_symbol_index=match_pos;
 assign consume_valid=mode&&!stop_request&&!error_valid&&((state==D_CODE&&match)||(state==D_EXTRA&&available>=size));
 assign consume_nbits=state==D_CODE?match_len:size;
 assign decode_finish=state==D_END;assign active=state!=E_IN&&state!=D_DESC;
 // Parallel comparison of all sixteen code lengths, including short EOF tails.
 always @*begin
 match=0;match_len=0;match_pos=0;symbol_offset=0;
 for(l=1;l<=16;l=l+1)begin
 mn=dec_header[(l-1)*128+:16];mx=dec_header[(l-1)*128+32+:16];fst=dec_header[(l-1)*128+64+:8];cnt=dec_header[(l-1)*128+96+:9];code=peek_bits>>(16-l);
 if(!match&&{27'd0,available}>=l&&cnt!=0&&code>=mn&&code<=mx)begin match=1;match_len=l[4:0];symbol_offset={8'd0,fst}+(code-mn);match_pos=symbol_offset[7:0];end
 end end
 always @(posedge clk)begin
 if(!rst_n||clear||start)begin state<=mode?D_DESC:E_IN;block_slot<=0;rst_number<=0;interval_mcus<=0;pred[0]<=0;pred[1]<=0;pred[2]<=0;comp<=0;seq<=0;last<=0;idx<=0;run<=0;symbol<=0;size<=0;extra<=0;tok<=0;toklen<=0;value<=0;zeros<=0;pending_value<=0;token_dc<=1;token_final<=0;token_retry<=0;new_pred<=0;done<=0;error_valid<=0;error_code<=0;end
 else if(!stop_request&&!error_valid)begin
 if(!mode)begin
 if(s_valid&&s_ready)begin
 comp<=s_component;seq<=s_block_seq;last<=s_last_block;idx<=s_index;
 token_dc<=s_index==0;token_final<=s_index==63&&s_last_block;token_retry<=0;
 if(s_index==0)begin diff=$signed({s_coef[31],s_coef})-$signed({pred[s_component][31],pred[s_component]});new_pred<=s_coef;run<=0;end
 else diff=$signed({s_coef[31],s_coef});
 magnitude=diff<0?-diff:diff;cat=0;for(i=0;i<33;i=i+1)if(magnitude[i])cat=i+1;
 if((s_index==0&&cat>11)||(s_index!=0&&cat>10))begin error_valid<=1;error_code<=`JPEG_ERR_ENTROPY;end
 else if(s_index!=0&&s_coef==0&&s_index!=63)run<=run+1'b1;
 else begin
 if(s_index!=0&&s_coef==0)begin symbol<=0;size<=0;extra<=0;run<=0;end
 else if(s_index!=0&&run>=16)begin
 symbol<=8'hf0;size<=0;extra<=0;value<=s_coef;token_retry<=1;run<=run-16;
 end else begin
 symbol<=s_index==0?{4'd0,cat[3:0]}:{run[3:0],cat[3:0]};size<=cat[4:0];extra<=diff<0?(magnitude[31:0]^(32'hffffffff>>(32-cat))):magnitude[31:0];run<=0;
 end
 state<=8; // table lookup stage, so component/symbol are stable
 end end
 if(state==8)begin
 if(!enc_entry[21]||enc_entry[20:16]==0||enc_entry[20:16]>16)begin error_valid<=1;error_code<=`JPEG_ERR_TABLE;end
 else begin tok<=({16'd0,enc_entry[15:0]}<<size)|extra;toklen<={1'b0,enc_entry[20:16]}+{1'b0,size};state<=E_TOKEN;end
 end
 if(token_valid&&token_ready)begin
 if(token_dc)pred[comp]<=new_pred;
 if(token_retry)begin
 if(run>=16)begin symbol<=8'hf0;size<=0;extra<=0;run<=run-16;end
 else begin
 magnitude=value<0?-$signed({value[31],value}):{1'b0,value};cat=0;for(i=0;i<32;i=i+1)if(magnitude[i])cat=i+1;
 symbol<={run[3:0],cat[3:0]};size<=cat[4:0];extra<=value<0?(magnitude[31:0]^(32'hffffffff>>(32-cat))):magnitude[31:0];run<=0;token_retry<=0;
 end
 state<=8;
 end else state<=token_final?E_FINISH:E_IN;
 end
 if(finish_valid&&finish_ready)begin done<=1;state<=9;end
 end else begin
 if(desc_valid&&desc_ready)begin comp<=desc_component;seq<=desc_block_seq;last<=desc_last_block;idx<=0;state<=D_CODE;end
 if(state==D_CODE)begin
 if(match&&consume_ready)begin
 symbol<=dec_symbol;size<={1'b0,dec_symbol[3:0]};
 if(idx==0)begin
 if(dec_symbol>11)begin error_valid<=1;error_code<=`JPEG_ERR_ENTROPY;end
 else if(dec_symbol==0)begin value<=pred[comp];zeros<=0;pending_value<=1;state<=D_OUT;end
 else state<=D_EXTRA;
 end else if(dec_symbol==0)begin zeros<=64-{1'b0,idx};pending_value<=0;state<=D_OUT;end
 else if(dec_symbol==8'hf0)begin
 if({1'b0,idx}+16>64)begin error_valid<=1;error_code<=`JPEG_ERR_ENTROPY;end else begin zeros<=16;pending_value<=0;state<=D_OUT;end
 end else if(dec_symbol[3:0]==0||dec_symbol[3:0]>10||{1'b0,idx}+{3'd0,dec_symbol[7:4]}>=64)begin error_valid<=1;error_code<=`JPEG_ERR_ENTROPY;end
 else begin zeros<={3'd0,dec_symbol[7:4]};pending_value<=1;state<=D_EXTRA;end
 end else if(!match&&((available==16)||input_eof||segment_end))begin error_valid<=1;error_code<=input_eof&&available<16?`JPEG_ERR_INPUT:`JPEG_ERR_ENTROPY;end
 end
 if(state==D_EXTRA)begin
 if(available>=size&&consume_ready)begin
 decoded=$signed({17'd0,peek_bits}>>(16-size));
 if(!peek_bits[15])decoded=decoded-((33'sd1<<size)-1);
 if(idx==0)begin
 dc_sum=$signed({pred[comp][31],pred[comp]})+decoded;
 if(dc_sum>33'sd2147483647||dc_sum< -33'sd2147483648)begin error_valid<=1;error_code<=`JPEG_ERR_NUMERIC;end
 else begin pred[comp]<=dc_sum[31:0];value<=dc_sum[31:0];end
 zeros<=0;
 end else value<=decoded[31:0];
 pending_value<=1;state<=D_OUT;
 end else if((input_eof||segment_end)&&available<size)begin error_valid<=1;error_code<=input_eof?`JPEG_ERR_INPUT:`JPEG_ERR_ENTROPY;end
 end
 if(m_valid&&m_ready)begin
 if(zeros!=0)zeros<=zeros-1'b1;
 if(idx==63)begin
 state<=last?D_END:D_DESC;
 if(block_slot==blocks_per_mcu-1'b1)begin
 block_slot<=0;
 if(restart_interval!=0)begin
 if(interval_mcus==restart_interval-1'b1&&!last)begin interval_mcus<=0;state<=D_RESTART;end
 else interval_mcus<=interval_mcus+1'b1;
 end
 end else block_slot<=block_slot+1'b1;
 end
 else begin idx<=idx+1'b1;
 if(zeros==0||(zeros==1&&!pending_value))state<=D_CODE;
 end end
 if(restart_valid&&restart_ready)begin
 pred[0]<=0;pred[1]<=0;pred[2]<=0;rst_number<=rst_number+1'b1;state<=D_DESC;
 end
 if(state==D_END&&input_eof)done<=1;
 end
 end end
endmodule
