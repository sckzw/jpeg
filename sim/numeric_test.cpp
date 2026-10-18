#include "Vnumeric_top.h"
#include "verilated.h"
#include <vector>
#include <random>
#include <iostream>
#include <stdexcept>
#include <climits>
#include <cstdint>
static const int C[8][8]={{5793,5793,5793,5793,5793,5793,5793,5793},{8035,6811,4551,1598,-1598,-4551,-6811,-8035},{7568,3135,-3135,-7568,-7568,-3135,3135,7568},{6811,-1598,-8035,-4551,4551,8035,1598,-6811},{5793,-5793,-5793,5793,5793,-5793,-5793,5793},{4551,-8035,1598,6811,-6811,-1598,8035,-4551},{3135,-7568,7568,-3135,-3135,7568,-7568,3135},{1598,-4551,6811,-8035,8035,-6811,4551,-1598}};
long long round14(long long a){return a<0?-((-a+8192)/16384):(a+8192)/16384;}
std::vector<int32_t> transform(std::vector<int32_t>x,bool mode){long long t[64];std::vector<int32_t> y(64);for(int r=0;r<8;r++)for(int k=0;k<8;k++){long long a=0;for(int n=0;n<8;n++)a+=(long long)(mode?C[n][k]:C[k][n])*(mode?x[r*8+n]:x[r*8+n]-128);t[r*8+k]=round14(a);}for(int r=0;r<8;r++)for(int c=0;c<8;c++){long long a=0;for(int n=0;n<8;n++)a+=(long long)(mode?C[n][r]:C[r][n])*t[n*8+c];a=round14(a);if(mode)a=std::max(0ll,std::min(255ll,a+128));y[r*8+c]=a;}return y;}
struct Sample{int32_t in,out;unsigned q,index,component,seq;bool last;};
int main(int argc,char**argv){Verilated::commandArgs(argc,argv);try{
 Vnumeric_top d;std::mt19937 rng(20261005);uint64_t clocks=0;
 auto tick=[&](){d.clk=0;d.eval();d.clk=1;d.eval();clocks++;};
 d.rst_n=0;d.s_valid=0;d.m_ready=0;d.start=0;tick();d.rst_n=1;tick();
 auto run=[&](bool mode,bool qmode,std::vector<Sample> samples){
 d.mode=mode;d.select_quant=qmode;d.start=1;tick();d.start=0;unsigned sent=0,received=0;uint64_t begin=clocks;
 bool stalled=false;int32_t held=0;unsigned hi=0,hc=0,hs=0;bool hl=false;
 while(received<samples.size()){
  if(clocks-begin>samples.size()*400+1000)throw std::runtime_error("numeric timeout");
  d.s_valid=sent<samples.size()&&rng()%5!=0;d.m_ready=rng()%4!=0;
  if(sent<samples.size()){auto x=samples[sent];d.s_coef=x.in;d.q_value=x.q;d.s_index=x.index;d.s_component=x.component;d.s_block_seq=x.seq;d.s_last_block=x.last;}
  d.clk=0;d.eval();bool put=d.s_valid&&d.s_ready,pop=d.m_valid&&d.m_ready;
  if(d.error_valid)throw std::runtime_error("numeric error "+std::to_string(d.error_code));
  if(stalled&&(!d.m_valid||int32_t(d.m_coef)!=held||d.m_index!=hi||d.m_component!=hc||d.m_block_seq!=hs||bool(d.m_last_block)!=hl))throw std::runtime_error("unstable numeric output");
  stalled=d.m_valid&&!d.m_ready;held=d.m_coef;hi=d.m_index;hc=d.m_component;hs=d.m_block_seq;hl=d.m_last_block;
  if(pop){auto x=samples[received];if(int32_t(d.m_coef)!=x.out||d.m_index!=x.index||d.m_component!=x.component||d.m_block_seq!=x.seq||bool(d.m_last_block)!=x.last)throw std::runtime_error("numeric mismatch sample="+std::to_string(received)+" got="+std::to_string(int32_t(d.m_coef))+" expected="+std::to_string(x.out));received++;}
  tick();if(put)sent++;
 }
 return clocks-begin;
 };
 unsigned total=0;
 for(bool mode:{false,true}){
 std::vector<Sample> samples;
 for(unsigned q=1;q<=255;q++)for(unsigned i=0;i<72;i++){
  int32_t x=i==0?0:(i==1?INT_MIN:(i==2?INT_MAX:int32_t(rng())));
  if(i>=3&&i<=8){int32_t b=17*q+q/2+int(i/2)-2;x=i%2?-b:b;}
  if(mode)x=int32_t(rng()%16000001)-8000000;
  int64_t a=x,out;if(mode)out=a*q;else{out=((2*std::abs(a)+q)/(2*q));if(a<0)out=-out;}
  samples.push_back({x,int32_t(out),q,i%64,q%3,q,bool(i==71)});
 }
 auto cycles=run(mode,true,samples);total+=samples.size();std::cout<<"quant mode="<<mode<<" vectors="<<samples.size()<<" cycles="<<cycles<<std::endl;
 }
 for(bool mode:{false,true}){
 std::vector<Sample> samples;
 for(unsigned b=0;b<128;b++){
 std::vector<int32_t>x(64);for(auto &v:x)v=mode?int32_t(rng()%40001)-20000:int32_t(rng()%256);
 if(b==0)std::fill(x.begin(),x.end(),mode?0:128);
 if(b==1)std::fill(x.begin(),x.end(),mode?INT_MAX:255);
 if(b==2)std::fill(x.begin(),x.end(),mode?INT_MIN:0);
 auto y=transform(x,mode);for(unsigned i=0;i<64;i++)samples.push_back({x[i],y[i],16,i,b%3,b,b==127});
 }
 auto cycles=run(mode,false,samples);total+=samples.size();std::cout<<"transform mode="<<mode<<" blocks=128 cycles="<<cycles<<std::endl;
 }
 d.select_quant=1;d.mode=1;d.s_valid=0;d.m_ready=1;d.start=1;tick();d.start=0;d.s_valid=1;d.s_coef=INT_MAX;d.q_value=255;tick();d.s_valid=0;for(int i=0;i<40;i++)tick();if(!d.error_valid||d.error_code!=8)throw std::runtime_error("inverse overflow missing");
 for(bool mode:{false,true}){d.mode=mode;d.start=1;d.s_valid=0;tick();d.start=0;d.s_valid=1;d.s_coef=123;d.q_value=0;tick();d.s_valid=0;for(int i=0;i<40;i++)tick();if(!d.error_valid||d.error_code!=2)throw std::runtime_error("zero Q missing error");}
 std::cout<<"PASS numeric vectors="<<total<<" seed=20261005"<<std::endl;
 }catch(const std::exception&e){std::cerr<<"FAIL: "<<e.what()<<std::endl;return 1;}return 0;}
