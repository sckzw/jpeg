`include "jpeg_defs.vh"
// Two banks. Explicit fill reserve / seal and synchronous held read response.
module jpeg_block_ram #(parameter DATA_W=32)(
 input clk,rst_n,clear,
 input reserve_valid,input reserve_bank,output reserve_ready,
 input s_valid,output s_ready,input s_bank,input [5:0] s_index,input [DATA_W-1:0] s_data,input s_zigzag,
 input [1:0] s_component,input [31:0] s_block_seq,input s_last_block,
 input req_valid,output req_ready,input req_bank,input [5:0] req_index,input req_zigzag,
 output reg m_valid,input m_ready,output reg [DATA_W-1:0] m_data,output reg [5:0] m_index,
 output reg [1:0] m_component,output reg [31:0] m_block_seq,output reg m_last_block,
 output [1:0] full,output [1:0] free);
 `include "jpeg_zigzag.vh"
 reg [DATA_W-1:0] mem[0:127];reg [1:0] state[0:1];reg [1:0] comp[0:1];reg [31:0] seq[0:1];reg last[0:1];reg response_bank;
 assign free={state[1]==0,state[0]==0};assign full={state[1]>=2,state[0]>=2};
 assign reserve_ready=state[reserve_bank]==0;
 assign s_ready=state[s_bank]==1;
 assign req_ready=state[req_bank]>=2 && (!m_valid||m_ready);
 always @(posedge clk)begin
 if(!rst_n||clear)begin state[0]<=0;state[1]<=0;m_valid<=0;m_data<=0;m_index<=0;m_component<=0;m_block_seq<=0;m_last_block<=0;response_bank<=0;end
 else begin
 if(reserve_valid&&reserve_ready)state[reserve_bank]<=1;
 if(s_valid&&s_ready)begin
 mem[{s_bank,s_zigzag?zigzag(s_index):s_index}]<=s_data;
 if(s_index==0)begin comp[s_bank]<=s_component;seq[s_bank]<=s_block_seq;last[s_bank]<=s_last_block;end
 if(s_index==63)state[s_bank]<=2;
 end
 if(m_valid&&m_ready)begin m_valid<=0;if(m_index==63)state[response_bank]<=0;end
 if(req_valid&&req_ready)begin
 m_valid<=1;m_data<=mem[{req_bank,req_zigzag?zigzag(req_index):req_index}];m_index<=req_index;
 m_component<=comp[req_bank];m_block_seq<=seq[req_bank];m_last_block<=last[req_bank];response_bank<=req_bank;state[req_bank]<=3;
 end end end
endmodule
