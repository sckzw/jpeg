`include "jpeg_defs.vh"
module jpeg_dma_write #(parameter ADDR_W=64,ID_W=1)(
 input clk,rst_n,start,clear,stop_request,input requests_complete,input [63:0] output_limit,
 input req_valid,output req_ready,input [ADDR_W-1:0] req_addr,input [3:0] req_len,input [2:0] req_size,input req_last,
 input s_valid,output s_ready,input [63:0] s_data,input [7:0] s_keep,input s_last,
 output [ID_W-1:0] m_axi_awid,output reg [ADDR_W-1:0] m_axi_awaddr,output reg [7:0] m_axi_awlen,output reg [2:0] m_axi_awsize,
 output [1:0] m_axi_awburst,output m_axi_awlock,output [3:0] m_axi_awcache,output [2:0] m_axi_awprot,output [3:0] m_axi_awqos,
 output reg m_axi_awvalid,input m_axi_awready,
 output [63:0] m_axi_wdata,output [7:0] m_axi_wstrb,output m_axi_wlast,output m_axi_wvalid,input m_axi_wready,
 input [ID_W-1:0] m_axi_bid,input [1:0] m_axi_bresp,input m_axi_bvalid,output m_axi_bready,
 output idle,output reg done,output reg error_valid,output reg [7:0] error_code,output reg [3:0] outstanding,output reg [63:0] output_bytes);
 reg [1:0] state;reg [63:0] data_mem[0:15];reg [7:0] keep_mem[0:15];reg [3:0] fill,send,len;reg aw_done,w_done,last_req,seen_last;
 reg [7:0] burst_bytes;reg [3:0] bytes;
 function [3:0] pop;input [7:0] k;integer j;begin pop=0;for(j=0;j<8;j=j+1)pop=pop+{3'd0,k[j]};end endfunction
 wire aw_fire=m_axi_awvalid&&m_axi_awready;wire w_fire=m_axi_wvalid&&m_axi_wready;wire b_fire=m_axi_bvalid&&m_axi_bready;
 assign req_ready=state==0&&outstanding<8&&!stop_request&&!error_valid;
 assign s_ready=state==1&&!stop_request&&!error_valid;
 assign m_axi_awid=0;assign m_axi_awburst=1;assign m_axi_awlock=0;assign m_axi_awcache=0;assign m_axi_awprot=0;assign m_axi_awqos=0;
 assign m_axi_wvalid=state==2&&!w_done;assign m_axi_wdata=data_mem[send];assign m_axi_wstrb=keep_mem[send];assign m_axi_wlast=send==len;
 assign m_axi_bready=outstanding!=0;
 assign idle=state==0&&outstanding==0&&!m_axi_awvalid;
 always @(posedge clk)begin
 if(!rst_n||clear||start)begin state<=0;m_axi_awvalid<=0;m_axi_awaddr<=0;m_axi_awlen<=0;m_axi_awsize<=0;fill<=0;send<=0;len<=0;aw_done<=0;w_done<=0;last_req<=0;seen_last<=0;burst_bytes<=0;outstanding<=0;if(!rst_n||start)output_bytes<=0;done<=0;error_valid<=0;error_code<=0;end
 else begin
 if(req_valid&&req_ready)begin state<=1;m_axi_awaddr<=req_addr;m_axi_awlen<={4'd0,req_len};m_axi_awsize<=req_size;len<=req_len;last_req<=req_last;fill<=0;send<=0;burst_bytes<=0;aw_done<=0;w_done<=0;end
 if(s_valid&&s_ready)begin
 bytes=pop(s_keep);
 data_mem[fill]<=s_data;keep_mem[fill]<=s_keep;burst_bytes<=burst_bytes+{4'd0,bytes};
 if(fill==len)begin
 if({1'b0,output_bytes}+{57'd0,burst_bytes}+{61'd0,bytes}>{1'b0,output_limit})begin error_valid<=1;error_code<=`JPEG_ERR_CAPACITY;state<=0;end
 else begin state<=2;m_axi_awvalid<=1;end
 end else fill<=fill+1'b1;
 end
 if(aw_fire)begin m_axi_awvalid<=0;aw_done<=1;end
 if(w_fire)begin
 output_bytes<=output_bytes+{60'd0,pop(m_axi_wstrb)};
 if(send==len)begin w_done<=1;if(last_req)seen_last<=1;end else send<=send+1'b1;
 end
 if(state==2&&(aw_done||aw_fire)&&(w_done||(w_fire&&send==len)))state<=0;
 if((stop_request||error_valid)&&state==1)state<=0;
 if(b_fire&&(m_axi_bresp!=0||m_axi_bid!=0))begin error_valid<=1;error_code<=`JPEG_ERR_WRITE;end
 case({aw_fire,b_fire})2'b10:outstanding<=outstanding+1'b1;2'b01:outstanding<=outstanding-1'b1;default:begin end endcase
 if(requests_complete&&seen_last&&idle&&!stop_request&&!error_valid)done<=1;
 end end
endmodule
