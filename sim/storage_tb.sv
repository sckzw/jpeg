`timescale 1ns/1ps
module storage_tb;
 reg clk=0,rst_n=0,clear=0;
 reg sv=0,mr=0,sl=0;reg [63:0] sd=0;reg [7:0] sk=0;wire sr,mv,ml,empty;wire [63:0] md;wire [7:0] mk;wire [11:0] used;
 jpeg_stream_fifo fifo(.clk(clk),.rst_n(rst_n),.clear(clear),.s_valid(sv),.s_ready(sr),.s_data(sd),.s_keep(sk),.s_last(sl),.m_valid(mv),.m_ready(mr),.m_data(md),.m_keep(mk),.m_last(ml),.used_bytes(used),.empty(empty));
 reg reserve=0,bank=0,wv=0,rv=0,rmr=0,wzig=0,rzig=0;
 reg [5:0] wi=0,ri=0;reg [31:0] wd=0;wire reserve_ready,wr,rr,rmv,rml;wire [31:0] rmd,rseq;wire [5:0] rmi;wire [1:0] rcomp,full,free;
 jpeg_block_ram ram(.clk(clk),.rst_n(rst_n),.clear(clear),.reserve_valid(reserve),.reserve_bank(bank),.reserve_ready(reserve_ready),.s_valid(wv),.s_ready(wr),.s_bank(bank),.s_index(wi),.s_data(wd),.s_zigzag(wzig),.s_component(2'd2),.s_block_seq(32'd42),.s_last_block(1'b1),.req_valid(rv),.req_ready(rr),.req_bank(bank),.req_index(ri),.req_zigzag(rzig),.m_valid(rmv),.m_ready(rmr),.m_data(rmd),.m_index(rmi),.m_component(rcomp),.m_block_seq(rseq),.m_last_block(rml),.full(full),.free(free));
 `include "jpeg_zigzag.vh"
 reg [72:0] queue[$];reg [72:0] expected;integer total,i,j,n,pushed,popped;reg do_push,do_pop;reg [31:0] random_state=32'd20261005;
 function [31:0] random_next(input [31:0] seed);reg [31:0] z;begin z=seed^(seed<<13);z=z^(z>>17);random_next=z^(z<<5);end endfunction
 function integer popcount(input [7:0] k);integer a;begin popcount=0;for(a=0;a<8;a=a+1)popcount=popcount+int'(k[a]);end endfunction
 task tick;begin clk=0;#1;clk=1;#1;end endtask
 initial begin
 tick();rst_n=1;tick();total=0;pushed=0;popped=0;
 for(i=0;i<7000;i=i+1)begin
 clk=0;random_state=random_next(random_state);sv=i<6000&&(random_state[1:0]!=0);mr=i>=6000||random_state[4:2]==0;
 n=1+int'(random_state[7:5]);sd={random_state,32'(i)};sk=8'hff>>(8-n);sl=i%13==0;#1;
 do_push=sv&&sr;do_pop=mv&&mr;
 if(do_pop)begin if(queue.size()==0)$fatal(1,"unexpected FIFO output");expected=queue.pop_front();if({ml,mk,md}!==expected)$fatal(1,"FIFO order/keep/last");total=total-popcount(mk);popped=popped+1;end
 if(do_push)begin queue.push_back({sl,sk,sd});total=total+popcount(sk);pushed=pushed+1;end
 clk=1;#1;if(int'(used)!=total)$fatal(1,"FIFO used bytes");
 end
 if(queue.size()!=0||!empty||pushed!=popped)$fatal(1,"FIFO drain");sv=0;mr=0;
 for(j=0;j<2;j=j+1)begin
 bank=1'(j);reserve=1;clk=0;#1;if(!reserve_ready)$fatal(1,"reserve");tick();reserve=0;
 for(i=0;i<64;i=i+1)begin wi=6'(i);wd=32'(i+j*1000);wv=1;tick();if(i!=63&&!wr)$fatal(1,"fill ready");end
 wv=0;if(!full[j])$fatal(1,"bank not full");end
 for(j=0;j<2;j=j+1)begin
 bank=1'(j);rzig=1;
 for(i=0;i<64;i=i+1)begin
 ri=6'(i);rv=1;rmr=0;clk=0;#1;if(!rr)$fatal(1,"read ready");tick();rv=0;
 if(!rmv||rmd!=32'(zigzag(6'(i)))+32'(j*1000)||rmi!=6'(i)||rcomp!=2||rseq!=42||!rml)$fatal(1,"RAM zigzag/descriptor");
 expected={41'd0,rmd};repeat(3)begin tick();if(!rmv||rmd!=expected[31:0])$fatal(1,"RAM response hold");end
 rmr=1;tick();rmr=0;
 end
 if(!free[j])$fatal(1,"bank release");end
 // Decode writes zigzag; natural reads must reverse the same mapping.
 bank=0;reserve=1;tick();reserve=0;wzig=1;
 for(i=0;i<64;i=i+1)begin wi=6'(i);wd=32'(zigzag(6'(i)));wv=1;tick();end
 wv=0;rzig=0;
 for(i=0;i<64;i=i+1)begin ri=6'(i);rv=1;rmr=0;tick();rv=0;if(!rmv||rmd!=32'(i))$fatal(1,"inverse zigzag");rmr=1;tick();end
 $display("PASS FIFO wrap/full/used/keep/last words=%0d; two-bank RAM, zigzag, synchronous response stalls",pushed);$finish;
 end
endmodule
