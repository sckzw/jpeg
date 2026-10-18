`timescale 1ns/1ps
module width_tb;
 reg clk=0,rst_n=0,clear=0,sv=0,sl=0,ready=0;reg [63:0] sd=0;reg [7:0] sk=0;wire sr,wv,wr,wl,bv,bl,empty;wire [63:0] wd;wire [7:0] wk,byte_data;wire [11:0] used;
 jpeg_input_fifo input_fifo(.clk(clk),.rst_n(rst_n),.clear(clear),.s_valid(sv),.s_ready(sr),.s_data(sd),.s_keep(sk),.s_last(sl),.m_valid(wv),.m_ready(wr),.m_data(wd),.m_keep(wk),.m_last(wl),.used_bytes(used),.empty(empty));
 jpeg_unpack unpack(.clk(clk),.rst_n(rst_n),.clear(clear),.s_valid(wv),.s_ready(wr),.s_data(wd),.s_keep(wk),.s_last(wl),.m_valid(bv),.m_ready(ready),.m_byte(byte_data),.m_last(bl));
 integer i,j,frame,length,produced,consumed,chunk,cycles;reg push,pull;reg [31:0] seed=32'd20261005;
 function [31:0] next_random(input [31:0] x);reg [31:0] y;begin y=x^(x<<13);y=y^(y>>17);next_random=y^(y<<5);end endfunction
 task tick;begin clk=0;#1;clk=1;#1;end endtask
 initial begin
 tick();rst_n=1;tick();sv=1;sk=255;sd=64'h0706050403020100;sl=1;tick();sv=0;ready=1;
 for(i=0;i<8;i=i+1)begin clk=0;#1;if(!bv||byte_data!=8'(i)||bl!=(i==7)||used!=8)$fatal(1,"unpack ownership or byte order");clk=1;#1;if(i<7&&used!=8)$fatal(1,"word released before last byte");end
 if(used!=0)$fatal(1,"word not released");ready=0;
 for(frame=0;frame<30;frame=frame+1)begin
 clear=1;sv=0;tick();clear=0;produced=0;consumed=0;chunk=0;cycles=0;length=frame<8?frame+1:(frame==8?5000:37+frame*19);
 while(consumed<length)begin
 clk=0;seed=next_random(seed);ready=seed[2:0]==0;
 if(!sv&&produced<length&&seed[4:3]!=0)begin
 chunk=1+int'(seed[7:5]);if(chunk>length-produced)chunk=length-produced;
 sd=64'hffffffffffffffff;for(j=0;j<chunk;j=j+1)sd[j*8+:8]=8'((produced+j)%251);
 sk=8'hff>>(8-chunk);sl=produced+chunk==length;sv=1;
 end
 #1;push=sv&&sr;pull=bv&&ready;
 if(wv&&wk!=255&&!wl)$fatal(1,"nonfinal short FIFO word");
 if(pull)begin if(byte_data!=8'(consumed%251)||bl!=(consumed==length-1))$fatal(1,"packed byte/last order");consumed=consumed+1;end
 clk=1;#1;if(push)begin produced=produced+chunk;sv=0;end
 if(used>2048)$fatal(1,"logical FIFO capacity");cycles=cycles+1;if(cycles>100000)$fatal(1,"width conversion timeout");
 end
 if(produced!=length||used!=0||!empty)$fatal(1,"width conversion drain");sv=0;ready=0;
 end
 $display("PASS repack/unpack 30 frames, final keeps 1..8, FIFO full and last-byte ownership");$finish;
 end
endmodule
