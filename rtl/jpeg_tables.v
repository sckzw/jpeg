`include "jpeg_defs.vh"
module jpeg_tables(
 input clk,rst_n,clear,
 input access_valid,input access_write,input commit,input [2:0] kind,input [1:0] id,input [11:0] index,input [31:0] wdata,
 output reg ready,output reg access_error,output reg [31:0] rdata,output reg [10:0] table_valid,
 input [1:0] q_id,input [5:0] q_index,output [7:0] q_value,
 input h_ac,input h_id,input [7:0] h_symbol,output [31:0] enc_entry,
 output reg [2047:0] dec_header,input [7:0] dec_symbol_index,output [7:0] dec_symbol);
 reg [31:0] mem[0:3519];reg [319:0] loaded[0:10];
 reg checking,completed,failed;reg [3:0] check_table;reg [2:0] check_kind;reg [8:0] pos;
 reg [17:0] canonical;reg [8:0] symbol_count;reg [31:0] entry;reg [8:0] cnt;reg [15:0] mn,mx;reg [7:0] fst;integer length,i,slot,limit;
 function symbol_ok;input ac;input [7:0] symbol;begin symbol_ok=ac?((symbol[3:0]>=1&&symbol[3:0]<=10)||symbol==0||symbol==8'hf0):(symbol<=11);end endfunction
 always @*begin
 slot=0;limit=0;
 case(kind)
 0:begin slot={30'd0,id};limit=64;end
 1:begin slot=3+{30'd0,id};limit=256;end
 2:begin slot=5+{30'd0,id};limit=256;end
 3:begin slot=7+{30'd0,id};limit=320;end
 4:begin slot=9+{30'd0,id};limit=320;end
 default:begin slot=0;limit=0;end
 endcase
 access_error=(kind>4||(kind==0?id>2:id>1)||(!commit&&{20'd0,index}>=limit));
 rdata=0;if(!access_error&&!commit)rdata=mem[slot*320+{20'd0,index}];
 if(access_write&&!commit&&!access_error)begin
 if(kind==0&&(wdata[31:8]!=0||wdata[7:0]==0))access_error=1;
 if((kind==1||kind==2)&&wdata[31:22]!=0)access_error=1;
 end
 ready=!commit||access_error||completed;
 if(commit&&completed)access_error=failed;
 end
 assign q_value=q_id<3?mem[{30'd0,q_id}*320+{26'd0,q_index}][7:0]:8'd0;
 wire [31:0] enc_actual=mem[((h_ac?5:3)+{31'd0,h_id})*320+{24'd0,h_symbol}];
 assign enc_entry=enc_actual;
 // Header RAM exposes sixteen canonical ranges in parallel.
 always @*begin
 for(i=0;i<64;i=i+1)dec_header[i*32+:32]=mem[((h_ac?9:7)+{31'd0,h_id})*320+i];
 end
 assign dec_symbol=mem[((h_ac?9:7)+{31'd0,h_id})*320+64+{24'd0,dec_symbol_index}][7:0];
 always @(posedge clk)begin
 if(!rst_n||clear)begin table_valid<=0;checking<=0;completed<=0;failed<=0;pos<=0;check_table<=0;check_kind<=0;canonical<=0;symbol_count<=0;
 for(i=0;i<11;i=i+1)loaded[i]<=0;end
 else begin
 if(!access_valid)completed<=0;
 if(access_valid&&access_write&&!commit&&ready&&!access_error)begin
 mem[slot*320+{20'd0,index}]<=wdata;
 if(table_valid[slot])begin loaded[slot]<=0;loaded[slot][index[8:0]]<=1;end else loaded[slot][index[8:0]]<=1;
 table_valid[slot]<=0;
 end
 if(access_valid&&commit&&!checking&&!completed&&!access_error)begin
 checking<=1;check_table<=slot[3:0];check_kind<=kind;pos<=0;failed<=0;canonical<=0;symbol_count<=0;table_valid[slot]<=0;
 end
 if(checking)begin
 entry=mem[{28'd0,check_table}*320+{23'd0,pos}];
 if(!loaded[check_table][pos])failed<=1;
 if(check_kind==0)begin if(entry[31:8]!=0||entry[7:0]==0)failed<=1;end
 else if(check_kind<=2)begin
 if(entry[21])begin
 if(entry[20:16]==0||entry[20:16]>16||({16'd0,entry[15:0]}>>entry[20:16])!=0||!symbol_ok(check_kind==2,pos[7:0]))failed<=1;
 end else if(entry!=0)failed<=1;
 end else if(pos<64&&pos[1:0]==3)begin
 length=({23'd0,pos}>>2)+1;
 mn=mem[{28'd0,check_table}*320+{23'd0,pos}-3][15:0];mx=mem[{28'd0,check_table}*320+{23'd0,pos}-2][15:0];fst=mem[{28'd0,check_table}*320+{23'd0,pos}-1][7:0];cnt=entry[8:0];
 if(entry[31:9]!=0||symbol_count+cnt>256||(cnt!=0&&{1'b0,fst}!=symbol_count))failed<=1;
 if(cnt!=0&&(canonical!={2'd0,mn}||{16'd0,mx}!={16'd0,mn}+{23'd0,cnt}-1||{16'd0,mx}>=(32'd1<<length)-1))failed<=1;
 canonical<=(canonical+{9'd0,cnt})<<1;symbol_count<=symbol_count+cnt;
 if(mem[{28'd0,check_table}*320+{23'd0,pos}-3][31:16]!=0||mem[{28'd0,check_table}*320+{23'd0,pos}-2][31:16]!=0||mem[{28'd0,check_table}*320+{23'd0,pos}-1][31:8]!=0)failed<=1;
 end else if(pos>=64)begin
 if(entry[31:8]!=0||(pos<64+symbol_count&&!symbol_ok(check_kind==4,entry[7:0])))failed<=1;
 end
 if(pos==(check_kind==0?63:(check_kind<=2?255:319)))begin checking<=0;completed<=1;end else pos<=pos+1'b1;
 end
 if(completed&&!failed)table_valid[check_table]<=1;
 end end
endmodule
