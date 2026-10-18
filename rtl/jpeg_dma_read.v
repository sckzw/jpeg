`include "jpeg_defs.vh"
module jpeg_dma_read #(parameter ADDR_W=64,ID_W=1)(
 input clk,rst_n,start,clear,stop_request,input requests_complete,
 input req_valid,output req_ready,input [ADDR_W-1:0] req_addr,input [3:0] req_len,input [2:0] req_size,input req_last,
 input [11:0] used_bytes,output reg [10:0] reserved_bytes,
 output [ID_W-1:0] m_axi_arid,output reg [ADDR_W-1:0] m_axi_araddr,output reg [7:0] m_axi_arlen,output reg [2:0] m_axi_arsize,
 output [1:0] m_axi_arburst,output m_axi_arlock,output [3:0] m_axi_arcache,output [2:0] m_axi_arprot,output [3:0] m_axi_arqos,
 output reg m_axi_arvalid,input m_axi_arready,
 input [ID_W-1:0] m_axi_rid,input [63:0] m_axi_rdata,input [1:0] m_axi_rresp,input m_axi_rlast,input m_axi_rvalid,output m_axi_rready,
 output m_valid,input m_ready,output [63:0] m_data,output [7:0] m_keep,output m_last,
 output idle,output reg done,output reg error_valid,output reg [7:0] error_code,output reg [3:0] outstanding);
 reg [2:0] sizes[0:7],lanes[0:7];reg [3:0] lens[0:7];reg lasts[0:7];reg [2:0] wp,rp;reg [3:0] beat;
 reg pending_last;reg [2:0] pending_lane;wire [10:0] allocation=({7'd0,req_len}+11'd1)<<req_size;
 wire [3:0] nbytes=4'd1<<sizes[rp];
 wire ar_fire=m_axi_arvalid&&m_axi_arready;wire r_fire=m_axi_rvalid&&m_axi_rready;
 wire release_req=r_fire&&m_axi_rlast;wire accept=req_valid&&req_ready;
 assign req_ready=!stop_request&&!error_valid&&!m_axi_arvalid&&outstanding<8&&({1'b0,reserved_bytes}+used_bytes+{1'b0,allocation}<=2048);
 assign m_axi_arid=0;assign m_axi_arburst=1;assign m_axi_arlock=0;assign m_axi_arcache=0;assign m_axi_arprot=0;assign m_axi_arqos=0;
 assign m_valid=m_axi_rvalid&&outstanding!=0&&!stop_request&&!error_valid;
 assign m_axi_rready=outstanding!=0&&(stop_request||error_valid||m_ready);
 wire [6:0] lane_offset={4'd0,lanes[rp]}+({3'd0,beat}<<sizes[rp]);
 assign m_data=m_axi_rdata>>(lane_offset[2:0]*8);assign m_keep=8'hff>>(8-nbytes);assign m_last=lasts[rp]&&m_axi_rlast;
 assign idle=outstanding==0&&!m_axi_arvalid;
 always @(posedge clk)begin
 if(!rst_n||clear||start)begin reserved_bytes<=0;m_axi_arvalid<=0;m_axi_araddr<=0;m_axi_arlen<=0;m_axi_arsize<=0;wp<=0;rp<=0;beat<=0;outstanding<=0;done<=0;error_valid<=0;error_code<=0;pending_last<=0;pending_lane<=0;end
 else begin
 if(accept)begin m_axi_arvalid<=1;m_axi_araddr<=req_addr;m_axi_arlen<={4'd0,req_len};m_axi_arsize<=req_size;pending_last<=req_last;pending_lane<=req_addr[2:0];end
 if(ar_fire)begin m_axi_arvalid<=0;sizes[wp]<=m_axi_arsize;lanes[wp]<=pending_lane;lens[wp]<=m_axi_arlen[3:0];lasts[wp]<=pending_last;wp<=wp+1'b1;end
 if(r_fire)begin
 if(m_axi_rresp!=0||m_axi_rid!=0||m_axi_rlast!=(beat==lens[rp]))begin error_valid<=1;error_code<=`JPEG_ERR_READ;end
 if(m_axi_rlast)begin rp<=rp+1'b1;beat<=0;end else beat<=beat+1'b1;
 end
 case({ar_fire,release_req})2'b10:outstanding<=outstanding+1'b1;2'b01:outstanding<=outstanding-1'b1;default:begin end endcase
 case({accept,r_fire})
 2'b10:reserved_bytes<=reserved_bytes+allocation;
 2'b01:reserved_bytes<=reserved_bytes-{7'd0,nbytes};
 2'b11:reserved_bytes<=reserved_bytes+allocation-{7'd0,nbytes};
 default:begin end endcase
 if(requests_complete&&idle&&!error_valid&&!stop_request)done<=1;
 end end
endmodule
