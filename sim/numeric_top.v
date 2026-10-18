module numeric_top(input clk,rst_n,start,mode,select_quant,input [7:0] q_value,
 input s_valid,output s_ready,input signed [31:0] s_coef,input [5:0] s_index,input [1:0] s_component,input [31:0] s_block_seq,input s_last_block,
 output m_valid,input m_ready,output signed [31:0] m_coef,output [5:0] m_index,output [1:0] m_component,output [31:0] m_block_seq,output m_last_block,
 output error_valid,output [7:0] error_code);
 wire qs,ts,qv,tv;wire [31:0] qc,tc,qseq,tseq;wire [5:0] qi,ti;wire [1:0] qcomp,tcomp;wire qlast,tlast,qe,te;wire [7:0] qerr,terr;
 jpeg_quant q(.clk(clk),.rst_n(rst_n),.start(start),.clear(1'b0),.mode(mode),.stop_request(1'b0),
 .s_valid(s_valid&&select_quant),.s_ready(qs),.s_coef(s_coef),.s_index(s_index),.s_component(s_component),.s_block_seq(s_block_seq),.s_last_block(s_last_block),
 .q_value(q_value),.q_index(),.q_component(),.m_valid(qv),.m_ready(m_ready&&select_quant),.m_coef(qc),.m_index(qi),.m_component(qcomp),.m_block_seq(qseq),.m_last_block(qlast),.active(),.done(),.error_valid(qe),.error_code(qerr));
 jpeg_transform transform_inst(.clk(clk),.rst_n(rst_n),.start(start),.clear(1'b0),.mode(mode),.stop_request(1'b0),
 .s_valid(s_valid&&!select_quant),.s_ready(ts),.s_coef(s_coef),.s_index(s_index),.s_component(s_component),.s_block_seq(s_block_seq),.s_last_block(s_last_block),
 .m_valid(tv),.m_ready(m_ready&&!select_quant),.m_coef(tc),.m_index(ti),.m_component(tcomp),.m_block_seq(tseq),.m_last_block(tlast),.active(),.done(),.error_valid(te),.error_code(terr));
 assign s_ready=select_quant?qs:ts;assign m_valid=select_quant?qv:tv;assign m_coef=select_quant?qc:tc;assign m_index=select_quant?qi:ti;assign m_component=select_quant?qcomp:tcomp;assign m_block_seq=select_quant?qseq:tseq;assign m_last_block=select_quant?qlast:tlast;assign error_valid=select_quant?qe:te;assign error_code=select_quant?qerr:terr;
endmodule
