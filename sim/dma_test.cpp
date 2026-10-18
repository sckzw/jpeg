#include "Vdma_top.h"
#include "verilated.h"
#include <cstdint>
#include <vector>
#include <deque>
#include <iostream>
#include <stdexcept>
#include <algorithm>
struct Read {uint64_t addr,due;unsigned len,size,beat=0;};
struct Write {uint64_t addr;unsigned len,size,beat=0;};
struct Beat {uint64_t data;unsigned strb;bool last;uint64_t cycle;};
struct Bus {
 Vdma_top d; std::vector<uint8_t> mem=std::vector<uint8_t>(1<<22,0xa5);
 std::deque<std::pair<uint64_t,unsigned>> received;std::deque<Read> reads;std::deque<Write> writes;std::deque<Beat> beats;std::deque<uint64_t> responses;
 unsigned latency=128;uint64_t cycle=0;uint32_t rng=20261005;bool random=true,ar_block=false,aw_block=false,w_block=false;int read_error=0,write_error=0;unsigned max_rd=0,max_wr=0;
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
  if(d.r_valid&&d.r_ready)received.push_back({d.r_data,unsigned(d.r_keep)|(unsigned(d.r_last)<<8)});
  bool ar=d.m_axi_arvalid&&d.m_axi_arready,rr=d.m_axi_rvalid&&d.m_axi_rready,aw=d.m_axi_awvalid&&d.m_axi_awready,ww=d.m_axi_wvalid&&d.m_axi_wready,bb=d.m_axi_bvalid&&d.m_axi_bready;
  Read r{d.m_axi_araddr,cycle+latency,d.m_axi_arlen,d.m_axi_arsize};Write w{d.m_axi_awaddr,d.m_axi_awlen,d.m_axi_awsize};Beat b{d.m_axi_wdata,d.m_axi_wstrb,bool(d.m_axi_wlast),cycle};
  if(ar&&((r.addr&4095)+((r.len+1)<<r.size)>4096))throw std::runtime_error("read crosses 4K");
  if(aw&&((w.addr&4095)+((w.len+1)<<w.size)>4096))throw std::runtime_error("write crosses 4K");
  d.clk=1;d.eval();cycle++;
  if(rr){if(reads.front().beat++==reads.front().len)reads.pop_front();}
  if(ar)reads.push_back(r);
  if(aw)writes.push_back(w);
  if(ww)beats.push_back(b);
  if(bb)responses.pop_front();
  while(!writes.empty()&&!beats.empty()){
   auto &x=writes.front();auto y=beats.front();beats.pop_front();auto addr=x.addr+(uint64_t(x.beat)<<x.size);auto aligned=addr&~7ull;
   if(y.last!=(x.beat==x.len))throw std::runtime_error("WLAST mismatch");
   for(unsigned i=0;i<8;i++)if(y.strb&(1<<i)){if(aligned+i>=mem.size())throw std::runtime_error("W address");mem[aligned+i]=(y.data>>(i*8))&255;}
   if(x.beat++==x.len){responses.push_back(y.cycle+latency);writes.pop_front();}
  }
  max_rd=std::max(max_rd,unsigned(reads.size()));max_wr=std::max(max_wr,unsigned(writes.size()+responses.size()));
 }
 void reset(){d.rst_n=0;d.start=0;d.stop_request=0;d.r_req_valid=0;d.w_req_valid=0;d.w_valid=0;d.r_complete=0;d.w_complete=0;d.r_ready=0;for(int i=0;i<3;i++)tick();d.rst_n=1;tick();}
};

uint8_t pattern(uint64_t address){return ((address*73)^(address>>5)^0x5a)&255;}
uint64_t word(uint64_t address){uint64_t v=0;for(unsigned i=0;i<8;i++)v|=uint64_t(pattern(address+i))<<(8*i);return v;}
void run(unsigned latency){
 Bus b;b.latency=latency;b.reset();for(unsigned i=0;i<4096;i++)b.mem[0x2000+i]=pattern(0x2000+i);b.d.start=1;b.tick();b.d.start=0;b.d.output_limit=4095;
 unsigned issued=0,returned=0,wissued=0,wsent=0;bool filling=false;
 for(unsigned cycle=0;!(b.d.r_done&&b.d.w_done);cycle++){
 if(cycle>20000)throw std::runtime_error("DMA timeout");
 auto &d=b.d;d.r_req_valid=issued<32;d.r_req_addr=0x2000+issued*128;d.r_req_len=15;d.r_req_size=3;d.r_req_last=issued==31;d.r_ready=b.rand()%4!=0;d.r_complete=issued==32;
 d.w_req_valid=wissued<32&&!filling;d.w_req_addr=0x10000+wissued*128;d.w_req_len=15;d.w_req_size=3;d.w_req_last=wissued==31;d.w_complete=wissued==32&&!filling;
 d.w_valid=filling&&b.rand()%5!=0;d.w_data=word(0x10000+wsent*8);d.w_keep=wsent==511?127:255;d.w_last=wsent==511;
 d.clk=0;d.eval();bool ar=d.r_req_valid&&d.r_req_ready,rr=d.r_valid&&d.r_ready,aw=d.w_req_valid&&d.w_req_ready,ww=d.w_valid&&d.w_ready;
 
 if(d.r_error||d.w_error)throw std::runtime_error("DMA error");
 b.tick();while(!b.received.empty()){auto data=b.received.front();b.received.pop_front();if(data.first!=word(0x2000+returned*8)||(data.second&255)!=255||bool(data.second&256)!=(returned==511))throw std::runtime_error("read burst payload/last index="+std::to_string(returned));returned++;}if(ar)issued++;if(aw){wissued++;filling=true;}if(ww){wsent++;if(wsent%16==0)filling=false;}
 }
 if(returned!=512||b.d.output_bytes!=4095||!b.d.r_idle||!b.d.w_idle)throw std::runtime_error("DMA completion");
 for(unsigned i=0;i<4096;i++)if(b.mem[0x10000+i]!=(i==4095?0xa5:pattern(0x10000+i)))throw std::runtime_error("DMA written byte");
 if(b.max_rd!=8||(latency==512&&b.max_wr!=8))throw std::runtime_error("outstanding slots");
 std::cout<<"PASS DMA 32x16-beat read/write bursts latency="<<latency<<" max_outstanding="<<b.max_rd<<","<<b.max_wr<<" cycles="<<b.cycle<<std::endl;
}
int main(int argc,char**argv){Verilated::commandArgs(argc,argv);try{run(128);run(512);}catch(const std::exception&e){std::cerr<<"FAIL: "<<e.what()<<std::endl;return 1;}return 0;}
