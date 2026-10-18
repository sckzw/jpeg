#include "Vjpeg_bitstream.h"
#include "verilated.h"
#include <vector>
#include <random>
#include <iostream>
#include <stdexcept>
struct Token{uint32_t bits;unsigned n;};
int main(int argc,char**argv){Verilated::commandArgs(argc,argv);try{
 Vjpeg_bitstream d;std::mt19937 rng(20261005);auto tick=[&](){d.clk=0;d.eval();d.clk=1;d.eval();};
 d.restart_enabled=0;d.restart_valid=0;d.restart_expected=0;d.rst_n=0;d.start=0;d.clear=0;d.mode=0;d.stop_request=0;d.token_valid=0;d.finish_valid=0;d.s_valid=0;d.consume_valid=0;d.decode_finish=0;d.byte_ready=0;tick();d.rst_n=1;
 auto start=[&](bool mode){d.mode=mode;d.start=1;d.token_valid=0;d.finish_valid=0;d.s_valid=0;d.consume_valid=0;d.decode_finish=0;tick();d.start=0;};
 unsigned bytes_total=0;
 for(int test=0;test<100;test++){
 std::vector<Token>tokens;std::vector<int>bits;
 for(unsigned j=0;j<100;j++){unsigned n=j<8?j+1:1+rng()%27;uint32_t v=(test==0?0xffffffffu:rng());tokens.push_back({v,n});for(int k=int(n)-1;k>=0;k--)bits.push_back((v>>k)&1);}
 std::vector<int>padded=bits;while(padded.size()%8)padded.push_back(1);std::vector<uint8_t>expected;
 for(unsigned j=0;j<padded.size();j+=8){unsigned b=0;for(int k=0;k<8;k++)b=(b<<1)|padded[j+k];expected.push_back(b);if(b==255)expected.push_back(0);}
 start(false);unsigned sent=0,received=0;bool finish=false,held=false;unsigned held_byte=0;bool held_last=false;
 for(unsigned cycle=0;!d.done;cycle++){
  if(cycle>10000)throw std::runtime_error("encode timeout");
  d.token_valid=sent<tokens.size()&&rng()%5!=0;if(sent<tokens.size()){d.token_bits=tokens[sent].bits;d.token_nbits=tokens[sent].n;}
  d.finish_valid=sent==tokens.size()&&!finish;d.byte_ready=rng()%4!=0;d.clk=0;d.eval();
  bool put=d.token_valid&&d.token_ready,ff=d.finish_valid&&d.finish_ready,pop=d.byte_valid&&d.byte_ready;
  if(held&&(!d.byte_valid||d.byte_data!=held_byte||bool(d.byte_last)!=held_last))throw std::runtime_error("byte hold");
  held=d.byte_valid&&!d.byte_ready;held_byte=d.byte_data;held_last=d.byte_last;
  if(pop){if(received>=expected.size()||d.byte_data!=expected[received]||bool(d.byte_last)!=(received==expected.size()-1))throw std::runtime_error("encode byte "+std::to_string(received));received++;}
  if(d.error_valid)throw std::runtime_error("encode error");tick();if(put)sent++;if(ff)finish=true;
 }
 if(received!=expected.size())throw std::runtime_error("encode length");bytes_total+=received;
 start(true);sent=0;unsigned consumed=0;
 for(unsigned cycle=0;!d.done;cycle++){
  if(cycle>10000)throw std::runtime_error("decode timeout");
  d.s_valid=sent<expected.size()&&rng()%5!=0;if(sent<expected.size()){d.s_byte=expected[sent];d.s_last=sent==expected.size()-1;}
  d.clk=0;d.eval();unsigned n=std::min(unsigned(bits.size()-consumed),std::min(unsigned(d.available),unsigned(1+rng()%16)));
  d.consume_valid=n&&rng()%4!=0;d.consume_nbits=n;d.decode_finish=consumed==bits.size();d.eval();
  bool put=d.s_valid&&d.s_ready,pop=d.consume_valid&&d.consume_ready;
  if(pop){for(unsigned j=0;j<n;j++)if(((d.peek_bits>>(15-j))&1)!=unsigned(bits[consumed+j]))throw std::runtime_error("decode bit order");consumed+=n;}
  if(d.error_valid)throw std::runtime_error("decode error "+std::to_string(d.error_code));tick();if(put)sent++;
 }
 if(consumed!=bits.size())throw std::runtime_error("decode bit count");
 }
 for(unsigned bad: {255u,256u,257u}){
 start(true);d.s_valid=1;d.s_byte=255;d.s_last=bad==255;tick();if(bad!=255){d.s_byte=bad==256?1:0;d.s_last=1;tick();}d.s_valid=0;
 if(bad==257){d.decode_finish=1;tick();}
 if(!d.error_valid||d.error_code!=(bad==257?10:6))throw std::runtime_error("malformed stream missing error");
 }
 // Decode-only restart marker tests, independent of RTL encoder output.
 d.restart_enabled=1;
 for(unsigned pad=0;pad<8;pad++)for(unsigned marker=0;marker<8;marker++){
  start(true);d.restart_expected=marker;d.restart_valid=0;
  unsigned value=(0xa5u & (0xffu<<pad))|((1u<<pad)-1);
  std::vector<unsigned> stream{value};if(value==255)stream.push_back(0);
  stream.push_back(255);stream.push_back(255);stream.push_back(0xd0+marker);
  unsigned sent=0;bool consumed=false;
  for(unsigned n=0;!d.restart_pending;n++){
   if(n>1000)throw std::runtime_error("restart parser timeout");
   d.s_valid=sent<stream.size()&&rng()%4!=0;d.s_last=0;if(sent<stream.size())d.s_byte=stream[sent];
   d.consume_valid=0;d.clk=0;d.eval();if(!consumed&&d.available>=8-pad){d.consume_nbits=8-pad;d.consume_valid=1;}
   d.eval();bool put=d.s_valid&&d.s_ready,pop=d.consume_valid&&d.consume_ready;tick();if(put)sent++;if(pop)consumed=true;
  }
  d.s_valid=0;d.consume_valid=0;if(!consumed){d.consume_nbits=8-pad;d.consume_valid=1;tick();d.consume_valid=0;}
  for(unsigned n=0;n<20;n++){d.clk=0;d.eval();if(d.s_ready||!d.restart_pending||d.available!=pad)throw std::runtime_error("restart boundary hold");tick();}
  d.restart_valid=1;d.clk=0;d.eval();if(!d.restart_ready)throw std::runtime_error("restart acknowledgment missing");tick();d.restart_valid=0;
  if(d.error_valid||d.restart_pending||d.available)throw std::runtime_error("restart reservoir reset");
 }
 // Marker number, non-one pad and unmatched final RST errors.
 for(unsigned bad=0;bad<3;bad++){
  start(true);d.restart_expected=0;d.restart_valid=0;d.s_valid=1;d.s_last=0;d.s_byte=bad==1?0:255;tick();
  if(bad==1){d.s_byte=255;tick();}
  d.s_byte=bad==0?0xd1:0xd0;tick();d.s_valid=0;
  if(bad==1){d.consume_nbits=1;d.consume_valid=1;tick();d.consume_valid=0;}
  if(bad==2)d.decode_finish=1;else d.restart_valid=1;tick();
  if(!d.error_valid||d.error_code!=(bad==1?10:6))throw std::runtime_error("restart malformed boundary error");
  d.restart_valid=0;d.decode_finish=0;
 }
 start(true);d.restart_valid=0;d.s_valid=1;d.s_last=0;d.s_byte=255;tick();tick();d.s_byte=0;tick();d.s_valid=0;
 if(!d.error_valid||d.error_code!=6)throw std::runtime_error("FF fill before stuffed zero accepted");
 d.restart_enabled=0;
 std::cout<<"PASS bitstream restart: 64 padding/number combinations, FF00, fill bytes, boundary stalls, malformed markers"<<std::endl;
 std::cout<<"PASS bitstream 100 roundtrips bytes="<<bytes_total<<" seed=20261005"<<std::endl;
 }catch(const std::exception&e){std::cerr<<"FAIL: "<<e.what()<<std::endl;return 1;}return 0;}
