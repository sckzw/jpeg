#pragma once
// Shared Verilator APB driver and AXI memory model for tests and CLI.
#include "Vjpeg_top.h"
#include "Vjpeg_top___024root.h"
#include "verilated.h"
#include <cstdint>
#include <vector>
#include <deque>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <algorithm>
struct Read {uint64_t addr,due;unsigned len,size,beat=0;uint64_t accepted=0;};
struct Write {uint64_t addr;unsigned len,size,beat=0;};
struct Beat {uint64_t data;unsigned strb;bool last;uint64_t cycle;};
struct Stats{uint64_t ar_wait=0,aw_wait=0,w_wait=0,r_wait=0,t_wait=0,q_wait=0,e_wait=0;unsigned input_peak=0,output_peak=0,reserved_peak=0;uint64_t read_delay_sum=0,read_count=0;};
struct Bus {
 Stats stats;Vjpeg_top d; std::vector<uint8_t> mem=std::vector<uint8_t>(1<<22,0xa5);
 std::deque<Read> reads;std::deque<Write> writes;std::deque<Beat> beats;std::deque<uint64_t> responses;
 uint64_t cycle=0;uint32_t rng=20261005;bool variable_delay=false;uint64_t delay_sum=0,delay_count=0;bool random=true,ar_block=false,aw_block=false,w_block=false;int read_error=0,write_error=0;unsigned max_rd=0,max_wr=0;
 uint32_t rand(){rng^=rng<<13;rng^=rng>>17;rng^=rng<<5;return rng;}
 void tick(){
  d.clk=0;
  d.m_axi_arready=!ar_block&&reads.size()<8&&(!random||rand()%5!=0);
  d.m_axi_awready=!aw_block&&writes.size()+responses.size()<8&&(!random||rand()%5!=0);
  d.m_axi_wready=!w_block&&beats.size()<128&&(!random||rand()%5!=0);
  d.m_axi_rvalid=!reads.empty()&&reads.front().due<=cycle;d.m_axi_rdata=0;d.m_axi_rid=0;d.m_axi_rresp=read_error;
  d.m_axi_rlast=0;
  if(d.m_axi_rvalid){auto r=reads.front();auto addr=r.addr+(uint64_t(r.beat)<<r.size);d.m_axi_rlast=r.beat==r.len;for(unsigned i=0;i<(1u<<r.size);i++){if(addr+i>=mem.size())throw std::runtime_error("R address");d.m_axi_rdata|=uint64_t(mem[addr+i])<<(((addr+i)&7)*8);}}
  d.m_axi_bvalid=!responses.empty()&&responses.front()<=cycle;d.m_axi_bid=0;d.m_axi_bresp=write_error;
  d.eval();
  bool ar=d.m_axi_arvalid&&d.m_axi_arready,rr=d.m_axi_rvalid&&d.m_axi_rready,aw=d.m_axi_awvalid&&d.m_axi_awready,ww=d.m_axi_wvalid&&d.m_axi_wready,bb=d.m_axi_bvalid&&d.m_axi_bready;
  unsigned rdelay=variable_delay?64+rand()%129:128;Read r{d.m_axi_araddr,cycle+rdelay,d.m_axi_arlen,d.m_axi_arsize};r.accepted=cycle;Write w{d.m_axi_awaddr,d.m_axi_awlen,d.m_axi_awsize};Beat b{d.m_axi_wdata,d.m_axi_wstrb,bool(d.m_axi_wlast),cycle};
  if(ar&&((r.addr&4095)+((r.len+1)<<r.size)>4096))throw std::runtime_error("read crosses 4K");
  if(aw&&((w.addr&4095)+((w.len+1)<<w.size)>4096))throw std::runtime_error("write crosses 4K");
  stats.ar_wait+=d.m_axi_arvalid&&!d.m_axi_arready;stats.aw_wait+=d.m_axi_awvalid&&!d.m_axi_awready;stats.w_wait+=d.m_axi_wvalid&&!d.m_axi_wready;stats.r_wait+=d.m_axi_rvalid&&!d.m_axi_rready;
  stats.t_wait+=d.rootp->jpeg_top__DOT__t_sv&&!d.rootp->jpeg_top__DOT__t_sr;stats.q_wait+=d.rootp->jpeg_top__DOT__q_sv&&!d.rootp->jpeg_top__DOT__q_sr;stats.e_wait+=d.rootp->jpeg_top__DOT__e_sv&&!d.rootp->jpeg_top__DOT__e_sr;
  stats.input_peak=std::max(stats.input_peak,unsigned(d.rootp->jpeg_top__DOT__in_used));stats.output_peak=std::max(stats.output_peak,unsigned(d.rootp->jpeg_top__DOT__out_used));stats.reserved_peak=std::max(stats.reserved_peak,unsigned(d.rootp->jpeg_top__DOT__reserved_bytes));
  if(unsigned(d.rootp->jpeg_top__DOT__in_used)+unsigned(d.rootp->jpeg_top__DOT__reserved_bytes)>2048)throw std::runtime_error("read reservation exceeded FIFO capacity");
  if(rr&&reads.front().beat==0){stats.read_delay_sum+=cycle-reads.front().accepted;stats.read_count++;}
  d.clk=1;d.eval();cycle++;
  if(rr){if(reads.front().beat++==reads.front().len)reads.pop_front();}
  if(ar){reads.push_back(r);delay_sum+=rdelay;delay_count++;}
  if(aw)writes.push_back(w);
  if(ww)beats.push_back(b);
  if(bb)responses.pop_front();
  while(!writes.empty()&&!beats.empty()){
   auto &x=writes.front();auto y=beats.front();beats.pop_front();auto addr=x.addr+(uint64_t(x.beat)<<x.size);auto aligned=addr&~7ull;
   if(y.last!=(x.beat==x.len))throw std::runtime_error("WLAST mismatch");
   for(unsigned i=0;i<8;i++)if(y.strb&(1<<i)){if(aligned+i>=mem.size())throw std::runtime_error("W address");mem[aligned+i]=(y.data>>(i*8))&255;}
   if(x.beat++==x.len){unsigned bdelay=variable_delay?64+rand()%129:128;responses.push_back(y.cycle+bdelay);delay_sum+=bdelay;delay_count++;writes.pop_front();}
  }
  max_rd=std::max(max_rd,unsigned(reads.size()));max_wr=std::max(max_wr,unsigned(writes.size()+responses.size()));
 }
 void reset(){d.rst_n=0;d.psel=0;d.penable=0;for(int i=0;i<3;i++)tick();d.rst_n=1;tick();}
 uint32_t apb(unsigned addr,bool write,uint32_t val=0,bool expected_error=false){
  d.psel=1;d.penable=0;d.pwrite=write;d.paddr=addr;d.pwdata=val;tick();d.penable=1;
  uint32_t data=0;bool err=false;
  for(unsigned n=0;;n++){d.clk=0;d.eval();if(d.pready){data=d.prdata;err=d.pslverr;tick();break;}tick();if(n>2000)throw std::runtime_error("APB timeout");}
  d.psel=0;d.penable=0;tick();if(err!=expected_error)throw std::runtime_error("APB error addr="+std::to_string(addr)+" value="+std::to_string(val));return data;
 }
 void wr(unsigned a,uint32_t v,bool err=false){apb(a,true,v,err);}uint32_t rd(unsigned a){return apb(a,false);}
 uint32_t wait_job(unsigned max=2000000){auto begin=cycle;while(cycle-begin<max){auto st=rd(4);if(max>2000000&&(cycle-begin)%30000000<3)std::cout<<"performance progress cycles="<<cycle-begin<<std::endl;if((st&6)&&!(st&1))return st;}throw std::runtime_error("job timeout status="+std::to_string(rd(4))+" error="+std::to_string(rd(0x1c)));}
};
inline std::vector<uint8_t> file(std::string p){std::ifstream f(p,std::ios::binary);if(!f)throw std::runtime_error("missing "+p);return std::vector<uint8_t>(std::istreambuf_iterator<char>(f),{});}
