`include "jpeg_defs.vh"
module jpeg_bitstream(
 input clk,rst_n,start,clear,mode,stop_request,
 input restart_enabled,restart_valid,input [2:0] restart_expected,
 output restart_ready,output reg restart_pending,
 input token_valid,output token_ready,input [31:0] token_bits,input [5:0] token_nbits,
 input finish_valid,output finish_ready,
 output byte_valid,input byte_ready,output [7:0] byte_data,output byte_last,
 input s_valid,output s_ready,input [7:0] s_byte,input s_last,
 output [15:0] peek_bits,output [4:0] available,output input_eof,
 input consume_valid,output consume_ready,input [4:0] consume_nbits,input decode_finish,
 output active,output reg done,output reg error_valid,output reg [7:0] error_code);
 reg [63:0] bits;reg [6:0] count;reg finishing,stuff,held_valid,finalized;
 reg [7:0] held;reg expect_zero,marker_fill,eof;reg [63:0] next_bits;reg [6:0] next_count;
 reg [2:0] marker_number;
 reg [63:0] shifted;reg emit;reg [7:0] emitted;reg pop_held;reg [7:0] pad;integer n;
 assign token_ready=!mode&&!finishing&&count<=32&&!stop_request&&!error_valid;
 assign finish_ready=!mode&&!finishing&&!stop_request&&!error_valid;
 // Hold the last candidate byte; emit only when a successor or finish exists.
 wire successor=stuff||count>=8||(finishing&&count!=0);
 assign byte_valid=!mode&&held_valid&&(successor||finalized)&&!stop_request;
 assign byte_data=held;assign byte_last=finalized&&!successor;
 assign available=count>=16?5'd16:count[4:0];
 wire [63:0] peek_full=count>=16?(bits>>(count-16)):(bits<<(16-count));
 assign peek_bits=peek_full[15:0];
 assign input_eof=eof;
 assign consume_ready=mode&&consume_nbits!=0&&{2'd0,consume_nbits}<=count&&!stop_request;
 assign s_ready=mode&&!eof&&!restart_pending&&count<=48&&!stop_request&&!error_valid;
 wire restart_padding_ok=count<=7&&bits==(64'hffffffffffffffff>>(64-count));
 assign restart_ready=mode&&restart_pending&&restart_padding_ok&&marker_number==restart_expected&&!stop_request&&!error_valid;
 assign active=count!=0||held_valid||stuff||expect_zero||restart_pending;
 always @(posedge clk)begin
 if(!rst_n||clear||start)begin bits<=0;count<=0;finishing<=0;stuff<=0;held_valid<=0;held<=0;finalized<=0;expect_zero<=0;marker_fill<=0;eof<=0;restart_pending<=0;marker_number<=0;done<=0;error_valid<=0;error_code<=0;end
 else if(!stop_request&&!error_valid)begin
 next_bits=bits;next_count=count;
 if(mode)begin
 if(consume_valid&&consume_ready)begin
 next_count=count-{2'd0,consume_nbits};next_bits=bits & (64'hffffffffffffffff>>(64-next_count));
 end
if(s_valid&&s_ready)begin
 if(expect_zero)begin
 if(s_byte==0)begin
 if(marker_fill)begin error_valid<=1;error_code<=`JPEG_ERR_ENTROPY;end
 else begin next_bits=(next_bits<<8)|64'hff;next_count=next_count+8;end
 expect_zero<=0;marker_fill<=0;end
 else if(s_byte==8'hff)begin expect_zero<=1;marker_fill<=1;end // marker fill byte
 else if(restart_enabled&&s_byte>=8'hd0&&s_byte<=8'hd7)begin
 restart_pending<=1;marker_number<=s_byte[2:0];expect_zero<=0;
 end else begin error_valid<=1;error_code<=`JPEG_ERR_ENTROPY;expect_zero<=0;end
 end else if(s_byte==8'hff)begin expect_zero<=1;marker_fill<=0;end
 else begin next_bits=(next_bits<<8)|{56'd0,s_byte};next_count=next_count+8;end
 if(s_last)begin
 eof<=1;
 if(s_byte==8'hff)begin error_valid<=1;error_code<=`JPEG_ERR_ENTROPY;end
 end
 end
 if(restart_valid)begin
 if(count>7)begin error_valid<=1;error_code<=`JPEG_ERR_PADDING;end
 else if(restart_pending)begin
 if(!restart_padding_ok)begin error_valid<=1;error_code<=`JPEG_ERR_PADDING;end
 else if(marker_number!=restart_expected)begin error_valid<=1;error_code<=`JPEG_ERR_ENTROPY;end
 else begin restart_pending<=0;next_bits=0;next_count=0;end
 end else if(eof)begin error_valid<=1;error_code<=`JPEG_ERR_INPUT;end
 end
 if(decode_finish&&(eof||count>7||restart_pending))begin
 if(restart_pending)begin error_valid<=1;error_code<=`JPEG_ERR_ENTROPY;end
 else if(expect_zero||count>7||bits!=(64'hffffffffffffffff>>(64-count)))begin error_valid<=1;error_code<=`JPEG_ERR_PADDING;end
 else begin done<=1;next_bits=0;next_count=0;end
 end
 end else begin
 emit=0;emitted=0;pop_held=byte_valid&&byte_ready;
 if(pop_held)begin held_valid<=0;if(byte_last)done<=1;end
 if(finishing&&count==0&&!stuff)begin finalized<=1;if(!held_valid)done<=1;end
 if((!held_valid||pop_held)&&!finalized)begin
 if(stuff)begin emit=1;emitted=0;stuff<=0;end
 else if(count>=8)begin
 shifted=bits>>(count-8);emitted=shifted[7:0];emit=1;next_count=count-8;next_bits=bits & (64'hffffffffffffffff>>(64-next_count));
 if(emitted==8'hff)stuff<=1;
 end else if(finishing&&count!=0)begin
 n=8-{25'd0,count};pad=8'hff>>(8-n);emitted=(bits[7:0]<<n)|pad;emit=1;next_bits=0;next_count=0;if(emitted==8'hff)stuff<=1;
 end else if(finishing)begin finalized<=1;if(!held_valid)done<=1;end
 if(emit)begin held<=emitted;held_valid<=1;end
 end
 if(token_valid&&token_ready)begin
 if(token_nbits==0||token_nbits>27)begin error_valid<=1;error_code<=`JPEG_ERR_ENTROPY;end
 else begin next_bits=(next_bits<<token_nbits)|({32'd0,token_bits}&(64'hffffffffffffffff>>(64-token_nbits)));next_count=next_count+{1'b0,token_nbits};end
 end
 if(finish_valid&&finish_ready)finishing<=1;
 end
 bits<=next_bits;count<=next_count;
 end end
endmodule
