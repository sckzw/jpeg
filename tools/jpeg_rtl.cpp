// File-based CPU driver. Compression/decompression is performed by jpeg_top RTL.
#include "../sim/jpeg_sim_bus.h"
#include <limits>
int main(int argc,char **argv) {
 Verilated::commandArgs(argc,argv);
 try {
  if(argc!=2)throw std::runtime_error("usage: jpeg_rtl JOB_DIRECTORY");
  std::string dir=argv[1];std::ifstream config(dir+"/config.txt");
  unsigned mode,w,h,fmt,select,restart_interval=0;uint64_t input_size;
  if(!(config>>mode>>w>>h>>fmt>>select>>input_size)||mode>1||!w||w>65535||!h||h>65535||fmt>2||select>4095)
   throw std::runtime_error("invalid job configuration");
  if(config>>restart_interval){if(restart_interval>65535)throw std::runtime_error("restart interval range");}
  unsigned hs=fmt?2:1,vs=fmt==2?2:1;
  unsigned widths[3]={w,(w+hs-1)/hs,(w+hs-1)/hs};
  unsigned heights[3]={h,(h+vs-1)/vs,(h+vs-1)/vs};
  unsigned strides[3];for(unsigned c=0;c<3;c++)strides[c]=(widths[c]+7)&~7u;
  uint64_t samples=0,bases[3],cursor=4096;
  for(unsigned c=0;c<3;c++){bases[c]=cursor;uint64_t n=uint64_t(widths[c])*heights[c];samples+=n;cursor=(cursor+uint64_t(strides[c])*heights[c]+4095)&~uint64_t(4095);}
  uint64_t blocks=uint64_t((w+hs*8-1)/(hs*8))*((h+vs*8-1)/(vs*8))*(hs*vs+2);
  uint64_t jpeg_base=cursor,capacity=mode?input_size:blocks*512+64;
  if(cursor+capacity+4096>1024ull*1024*1024)throw std::runtime_error("job exceeds simulator 1 GiB memory limit");
  if(!mode&&input_size!=samples)throw std::runtime_error("input sample count mismatch");
  Bus b;b.random=false;b.mem.resize(cursor+capacity+4096,0);b.reset();
  for(unsigned c=0;c<3;c++){
   auto q=file(dir+"/q"+std::to_string(c)+".bin");if(q.size()!=64)throw std::runtime_error("Q table size");
   b.wr(0x20,c<<12);for(auto x:q)b.wr(0x24,x);b.wr(0x34,1);
  }
  for(unsigned kind=mode?3:1;kind<=(mode?4:2);kind++)for(unsigned id=0;id<2;id++){
   auto data=file(dir+"/table"+std::to_string(kind)+"_"+std::to_string(id)+".bin");
   if(data.size()!=(mode?320:256)*4)throw std::runtime_error("Huffman table size");
   b.wr(0x20,(kind<<14)|(id<<12));
   for(unsigned i=0;i<data.size();i+=4)b.wr(0x24,uint32_t(data[i])|(uint32_t(data[i+1])<<8)|(uint32_t(data[i+2])<<16)|(uint32_t(data[i+3])<<24));
   b.wr(0x34,1);
  }
  b.wr(0x6c,restart_interval);b.wr(0x3c,select);b.wr(8,(h<<16)|w);b.wr(0xc,fmt);
  b.wr(0x10,input_size);b.wr(0x28,input_size>>32);
  uint64_t limit=mode?samples:capacity;b.wr(0x14,limit);b.wr(0x2c,limit>>32);
  for(unsigned c=0;c<3;c++){b.wr(0x40+c*8,bases[c]);b.wr(0x44+c*8,bases[c]>>32);b.wr(0x60+c*4,strides[c]);}
  b.wr(0x58,jpeg_base);b.wr(0x5c,jpeg_base>>32);
  if(mode){auto scan=file(dir+"/input.scan");if(scan.size()!=input_size)throw std::runtime_error("scan size");std::copy(scan.begin(),scan.end(),b.mem.begin()+jpeg_base);}
  else for(unsigned c=0;c<3;c++){
   auto plane=file(dir+"/input"+std::to_string(c)+".bin");if(plane.size()!=uint64_t(widths[c])*heights[c])throw std::runtime_error("plane size");
   for(unsigned y=0;y<heights[c];y++)std::copy(plane.begin()+uint64_t(y)*widths[c],plane.begin()+uint64_t(y+1)*widths[c],b.mem.begin()+bases[c]+uint64_t(y)*strides[c]);
  }
  auto begin=b.cycle;b.wr(0,mode?3:1);
  auto status=b.wait_job(static_cast<unsigned>(std::min<uint64_t>(blocks*4000+1000000,std::numeric_limits<unsigned>::max())));
  if(status&4)throw std::runtime_error("RTL error code "+std::to_string(b.rd(0x1c)));
  uint64_t bytes=b.rd(0x18);bytes|=uint64_t(b.rd(0x30))<<32;
  if(mode&&bytes!=samples)throw std::runtime_error("decoded sample count mismatch");
  if(!mode&&bytes>capacity)throw std::runtime_error("encoded capacity exceeded");
  if(mode)for(unsigned c=0;c<3;c++){
   std::ofstream out(dir+"/output"+std::to_string(c)+".bin",std::ios::binary);
   for(unsigned y=0;y<heights[c];y++)out.write(reinterpret_cast<char*>(b.mem.data()+bases[c]+uint64_t(y)*strides[c]),widths[c]);if(!out)throw std::runtime_error("output write failed");
  }else{
   std::ofstream out(dir+"/output.scan",std::ios::binary);out.write(reinterpret_cast<char*>(b.mem.data()+jpeg_base),bytes);if(!out)throw std::runtime_error("output write failed");
  }
  std::cout<<"RTL "<<(mode?"decode":"encode")<<" cycles="<<b.cycle-begin<<" output_bytes="<<bytes<<"\n";
 }catch(const std::exception &e){std::cerr<<"ERROR: "<<e.what()<<"\n";return 1;}
 return 0;
}
