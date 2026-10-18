`include "jpeg_defs.vh"
module jpeg_ctrl #(parameter ADDR_W=64)(
 input clk,rst_n,input start_request,stop,clear_done,clear_error,idle_clear,
 input mode,input [15:0] width,height,restart_interval,input [1:0] format,
 input [63:0] input_bytes,output_limit,y_base,cb_base,cr_base,jpeg_base,input [31:0] y_stride,cb_stride,cr_stride,
 input [11:0] table_select,input [10:0] table_valid,
 input read_idle,write_idle,read_done,write_done,pipeline_done,input fault_valid,input [7:0] fault_code,
 output reg start,output reg clear,output reg stop_request,output busy,output reg done,error,output reg [7:0] error_code,
 output reg [31:0] total_blocks,output reg [63:0] samples);
 reg running,drained;integer cw,ch,mw,mh,qid,dcid,acid,i;reg config_ok,tables_ok;reg [63:0] count_samples;reg [64:0] endaddr;reg [63:0] base;reg [31:0] stride;integer w,h;
 function address_ok;input [64:0] a;begin address_ok=(a>>ADDR_W)==0;end endfunction
 always @*begin
 cw=format==0?{16'd0,width}:({16'd0,width}+1)/2;
 ch=format==2?({16'd0,height}+1)/2:{16'd0,height};
 mw=({16'd0,width}+(format==0?7:15))/(format==0?8:16);
 mh=({16'd0,height}+(format==2?15:7))/(format==2?16:8);
 count_samples={48'd0,width}*{48'd0,height}+2*({32'd0,cw[31:0]}*{32'd0,ch[31:0]});
 config_ok=(mode||restart_interval==0)&&width!=0&&height!=0&&format!=3&&jpeg_base[2:0]==0&&address_ok({1'b0,jpeg_base});
 endaddr={1'b0,jpeg_base}+{1'b0,(mode?input_bytes:output_limit)}-1;
 if(!address_ok(endaddr)||(mode?input_bytes:output_limit)==0)config_ok=0;
 if((!mode&&input_bytes!=count_samples)||(mode&&output_limit<count_samples))config_ok=0;
 tables_ok=1;qid=0;dcid=0;acid=0;base=0;stride=0;w=0;h=0;
 for(i=0;i<3;i=i+1)begin
 qid={30'd0,table_select[i*4+:2]};dcid={31'd0,table_select[i*4+2]};acid={31'd0,table_select[i*4+3]};
 if(qid>2||!table_valid[qid]||!table_valid[(mode?7:3)+dcid]||!table_valid[(mode?9:5)+acid])tables_ok=0;
 base=i==0?y_base:(i==1?cb_base:cr_base);stride=i==0?y_stride:(i==1?cb_stride:cr_stride);w=i==0?{16'd0,width}:cw;h=i==0?{16'd0,height}:ch;
 endaddr={1'b0,base}+({33'd0,stride}*{33'd0,(h-1)})+{33'd0,(w-1)};
 if(base[2:0]!=0||stride[2:0]!=0||{32'd0,stride}<{32'd0,w[31:0]}||!address_ok(endaddr))config_ok=0;
 end end
 assign busy=running||(error&&(!read_idle||!write_idle));
 always @(posedge clk)begin
 if(!rst_n)begin running<=0;drained<=0;done<=0;error<=0;error_code<=0;start<=0;clear<=0;stop_request<=0;total_blocks<=0;samples<=0;end
 else begin
 start<=0;clear<=0;
 if(clear_done)done<=0;
 if(((clear_error&&error)||idle_clear)&&read_idle&&write_idle)begin error<=0;error_code<=0;stop_request<=0;clear<=1;done<=0;end
 if(idle_clear&&!busy)clear<=1;
 if(start_request&&!busy&&!done&&!error)begin
 if(!config_ok||!tables_ok)begin error<=1;error_code<=config_ok?`JPEG_ERR_TABLE:`JPEG_ERR_CONFIG;end
 else begin running<=1;drained<=0;start<=1;total_blocks<=mw*mh*(format==0?3:(format==1?4:6));samples<=count_samples;end
 end
 if(running&&!error&&!start)begin
 if(fault_valid||stop)begin error<=1;error_code<=fault_valid?fault_code:`JPEG_ERR_STOP;stop_request<=1;end
 else if(read_done&&write_done&&pipeline_done)begin running<=0;done<=1;end
 end
 if(error&&read_idle&&write_idle&&!drained)begin running<=0;clear<=1;drained<=1;end
 end end
endmodule

module jpeg_geometry(
 input clk,rst_n,start,clear,advance,input [15:0] width,height,input [1:0] format,
 input [63:0] y_base,cb_base,cr_base,input [31:0] y_stride,cb_stride,cr_stride,input [31:0] total_blocks,
 output reg [1:0] component,output reg [31:0] block_seq,output last_block,
 output reg [31:0] block_x,block_y,component_width,component_height,output reg [63:0] base,output reg [31:0] stride);
 reg [31:0] mx,my;reg [2:0] slot;integer yblocks,mcu_w;
 assign last_block=block_seq==total_blocks-1;
 always @*begin
 yblocks=format==0?1:(format==1?2:4);mcu_w=({16'd0,width}+(format==0?7:15))/(format==0?8:16);
 if({29'd0,slot}<yblocks)begin
 component=0;base=y_base;stride=y_stride;component_width={16'd0,width};component_height={16'd0,height};
 block_x=mx*(format==0?8:16)+(({29'd0,slot}&1)*8);block_y=my*(format==2?16:8)+(({29'd0,slot}>>1)*8);
 end else begin
 component={29'd0,slot}==yblocks?1:2;base=component==1?cb_base:cr_base;stride=component==1?cb_stride:cr_stride;
 component_width=format==0?{16'd0,width}:({16'd0,width}+1)/2;component_height=format==2?({16'd0,height}+1)/2:{16'd0,height};
 block_x=mx*8;block_y=my*8;
 end end
 always @(posedge clk)begin
 if(!rst_n||start||clear)begin mx<=0;my<=0;slot<=0;block_seq<=0;end
 else if(advance)begin
 block_seq<=block_seq+1'b1;
 if({29'd0,slot}==yblocks+1)begin slot<=0;if(mx==mcu_w-1)begin mx<=0;my<=my+1'b1;end else mx<=mx+1'b1;end
 else slot<=slot+1'b1;
 end end
endmodule
