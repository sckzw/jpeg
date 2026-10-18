#include "jpeg_sim_bus.h"
void tables(Bus &b,unsigned q){
 for(unsigned c=0;c<3;c++){b.wr(0x20,c<<12);for(unsigned i=0;i<64;i++)b.wr(0x24,q);b.wr(0x34,1);}
 for(unsigned kind=1;kind<=4;kind++){
  auto data=file("tests/data/table"+std::to_string(kind)+".bin");b.wr(0x20,kind<<14);
  for(unsigned i=0;i<data.size();i+=4)b.wr(0x24,uint32_t(data[i])|(uint32_t(data[i+1])<<8)|(uint32_t(data[i+2])<<16)|(uint32_t(data[i+3])<<24));
  b.wr(0x34,1);
 }
 b.wr(0x3c,0x210);
 if((b.rd(0x38)&0x2af)!=0x2af)throw std::runtime_error("table valid "+std::to_string(b.rd(0x38)));
}
struct Vector{std::string name;unsigned w,h,fmt,q;};
void configure(Bus &b,const Vector &v,bool decode,uint64_t jpeg=0x80000){
 unsigned hs=v.fmt?2:1,vs=v.fmt==2?2:1;unsigned cw=(v.w+hs-1)/hs,ch=(v.h+vs-1)/vs;
 uint64_t samples=uint64_t(v.w)*v.h+2ull*cw*ch;
 b.wr(8,(v.h<<16)|v.w);b.wr(0xc,v.fmt);b.wr(0x10,decode?file("tests/data/"+v.name+".scan").size():samples);b.wr(0x28,0);b.wr(0x14,decode?samples:0x40000);b.wr(0x2c,0);
 for(unsigned c=0;c<3;c++){b.wr(0x40+c*8,0x10000+c*0x10000);b.wr(0x44+c*8,0);b.wr(0x60+c*4,((c?cw:v.w)+7)&~7u);}
 b.wr(0x58,jpeg);b.wr(0x5c,0);
}
void test_vector(Bus &b,Vector v,uint64_t jpeg=0x80000){
 tables(b,v.q);configure(b,v,false,jpeg);
 unsigned hs=v.fmt?2:1,vs=v.fmt==2?2:1;
 for(unsigned c=0;c<3;c++){
  unsigned w=c?(v.w+hs-1)/hs:v.w,h=c?(v.h+vs-1)/vs:v.h,stride=(w+7)&~7u;auto bytes=file("tests/data/"+v.name+"_in"+std::to_string(c)+".bin");
  for(unsigned y=0;y<h;y++)std::copy(bytes.begin()+y*w,bytes.begin()+(y+1)*w,b.mem.begin()+0x10000+c*0x10000+y*stride);
 }
 auto begin=b.cycle;b.wr(0,1);if(b.rd(0x18)!=0)throw std::runtime_error("new job counter not reset");auto st=b.wait_job();auto cycles=b.cycle-begin;
 if(st&4)throw std::runtime_error(v.name+" encode error "+std::to_string(b.rd(0x1c)));
 auto bytes=b.rd(0x18);auto expected=file("tests/data/"+v.name+".scan");
 if(bytes!=expected.size())throw std::runtime_error(v.name+" scan length "+std::to_string(bytes)+" expected "+std::to_string(expected.size()));
 for(unsigned i=0;i<bytes;i++)if(b.mem[jpeg+i]!=expected[i])throw std::runtime_error(v.name+" scan mismatch index="+std::to_string(i)+" actual="+std::to_string(b.mem[jpeg+i])+" expected="+std::to_string(expected[i]));
 std::ofstream actual_scan("build/"+v.name+".scan",std::ios::binary);actual_scan.write(reinterpret_cast<char*>(b.mem.data()+jpeg),bytes);actual_scan.close();
 std::cout<<v.name<<" encode cycles="<<cycles<<" scan_bytes="<<bytes<<std::endl;
 b.wr(4,2);configure(b,v,true,jpeg);
 // Decode a separately generated CPU reference scan, never the RTL encoder output.
 std::copy(expected.begin(),expected.end(),b.mem.begin()+jpeg);
 for(unsigned c=0;c<3;c++)std::fill(b.mem.begin()+0x10000+c*0x10000,b.mem.begin()+0x20000+c*0x10000,0xa5);
 begin=b.cycle;b.wr(0,3);st=b.wait_job();cycles=b.cycle-begin;
 if(st&4)throw std::runtime_error(v.name+" decode error "+std::to_string(b.rd(0x1c)));
 uint64_t samples=0;
 for(unsigned c=0;c<3;c++){
  unsigned w=c?(v.w+hs-1)/hs:v.w,h=c?(v.h+vs-1)/vs:v.h,stride=(w+7)&~7u;auto expected_pixels=file("tests/data/"+v.name+"_out"+std::to_string(c)+".bin");samples+=w*h;
  for(unsigned y=0;y<h;y++)for(unsigned x=0;x<stride;x++){
   auto actual=b.mem[0x10000+c*0x10000+y*stride+x];auto exp=x<w?expected_pixels[y*w+x]:0xa5;
   if(actual!=exp)throw std::runtime_error(v.name+" pixel mismatch c="+std::to_string(c)+" x="+std::to_string(x)+" y="+std::to_string(y)+" actual="+std::to_string(actual)+" expected="+std::to_string(exp));
  }
 }
 if(b.rd(0x18)!=samples)throw std::runtime_error("output sample count");
 std::cout<<v.name<<" decode cycles="<<cycles<<" samples="<<samples<<std::endl;b.wr(4,2);
}
void error_tests(Bus &b){
 Vector v{"flat",8,8,0,16};tables(b,16);configure(b,v,false);
 auto expect=[&](unsigned code){auto st=b.wait_job();if(!(st&4)||b.rd(0x1c)!=code)throw std::runtime_error("expected job error "+std::to_string(code)+" actual="+std::to_string(b.rd(0x1c)));if(!b.reads.empty()||!b.writes.empty()||!b.beats.empty()||!b.responses.empty())throw std::runtime_error("DMA not drained");b.wr(4,4);};
 auto load_ac1=[&](bool all_ones){b.wr(0x20,(4<<14)|(1<<12));for(unsigned i=0;i<320;i++){unsigned value=0;if(all_ones){if(i==1)value=1;if(i==3)value=2;}else{if(i==33)value=254;if(i==35)value=255;if(i==36||i==37)value=510;if(i==38)value=255;if(i==39)value=1;}b.wr(0x24,value);}b.wr(0x34,1,all_ones);};
 load_ac1(false);if(!(b.rd(0x38)&1024))throw std::runtime_error("256-symbol commit");load_ac1(true);if(b.rd(0x38)&1024)throw std::runtime_error("all-one code commit accepted");

 b.wr(0,5,true);b.wr(0x100,0,true);b.wr(8,0);b.wr(0,1);expect(1);configure(b,v,false);
 b.wr(0x20,0);b.wr(0x24,16);b.wr(0x34,1,true);if(b.rd(0x38)&1)throw std::runtime_error("partial Q commit");b.wr(0,1);expect(2);tables(b,16);
 b.wr(0x20,0);b.wr(0x24,0,true);b.wr(0x20,(3<<14)|320);b.rd(0x38);b.apb(0x24,false,0,true);
 // A pending AR must survive stop. It is accepted only after release below.
 configure(b,v,false);b.ar_block=true;b.wr(0,1);for(unsigned i=0;i<50&&!b.d.m_axi_arvalid;i++)b.tick();if(!b.d.m_axi_arvalid)throw std::runtime_error("no pending AR");
 auto addr=b.d.m_axi_araddr;b.wr(8,0,true);b.wr(0,1,true);b.wr(0,4);for(int i=0;i<20;i++)b.tick();if(!b.d.m_axi_arvalid||b.d.m_axi_araddr!=addr||!(b.rd(4)&1))throw std::runtime_error("stop retracted AR");b.wr(4,4,true);b.ar_block=false;expect(9);
 configure(b,v,false);for(unsigned c=0;c<3;c++)std::fill(b.mem.begin()+0x10000+c*0x10000,b.mem.begin()+0x10040+c*0x10000,128);b.wr(0,1);for(unsigned i=0;i<2000&&!b.d.rootp->jpeg_top__DOT__rd_done;i++)b.tick();b.wr(4,4);if(b.wait_job()&4)throw std::runtime_error("spurious error W1C");b.wr(4,2);
 configure(b,v,false);b.read_error=2;b.wr(0,1);expect(3);b.read_error=0;
 configure(b,v,false);b.write_error=2;b.wr(0,1);auto st=b.wait_job();if(!(st&4)||b.rd(0x1c)!=4||b.rd(0x18)==0)throw std::runtime_error("write error/count");b.write_error=0;b.wr(4,4);
 configure(b,v,false);b.wr(0x14,1);b.wr(0,1);expect(7);if(b.rd(0x18)!=0)throw std::runtime_error("capacity wrote data");
 auto scan=file("tests/data/flat.scan");std::copy(scan.begin(),scan.end(),b.mem.begin()+0x80000);
 configure(b,v,true);b.wr(0x10,scan.size()-1);b.wr(0,3);expect(5);
 configure(b,v,true);b.mem[0x80000+scan.size()]=0;b.wr(0x10,scan.size()+1);b.wr(0,3);expect(10);
 configure(b,v,true);b.mem[0x80000]=255;b.mem[0x80001]=1;b.wr(0x10,2);b.wr(0,3);expect(6);
 // Pending AW and all W data must also survive a stop.
 configure(b,v,false);b.aw_block=true;b.w_block=true;b.wr(0,1);for(unsigned i=0;i<10000&&!b.d.m_axi_awvalid;i++)b.tick();if(!b.d.m_axi_awvalid)throw std::runtime_error("no pending AW");
 auto wa=b.d.m_axi_awaddr,wd=b.d.m_axi_wdata;auto wk=b.d.m_axi_wstrb;b.wr(0,4);for(int i=0;i<20;i++)b.tick();if(!b.d.m_axi_awvalid||!b.d.m_axi_wvalid||b.d.m_axi_awaddr!=wa||b.d.m_axi_wdata!=wd||b.d.m_axi_wstrb!=wk)throw std::runtime_error("stop retracted AW/W");b.aw_block=false;b.w_block=false;expect(9);
 for(unsigned fmt=0;fmt<3;fmt++){
 configure(b,v,false);b.wr(8,0xffffffff);b.wr(0xc,fmt);uint64_t samples=65535ull*65535+2ull*(fmt?32768:65535)*(fmt==2?32768:65535);b.wr(0x10,samples);b.wr(0x28,samples>>32);for(unsigned c=0;c<3;c++)b.wr(0x60+c*4,65536);
 b.ar_block=true;b.wr(0,1);for(unsigned n=0;n<20;n++)b.tick();unsigned expected_blocks=fmt==0?201326592:(fmt==1?134217728:100663296);if(b.d.rootp->jpeg_top__DOT__total_blocks!=expected_blocks||(b.rd(4)&4))throw std::runtime_error("maximum dimensions/counts");b.wr(0,4);b.ar_block=false;expect(9);
 }
 b.wr(0,4);if(b.rd(0x38)!=0)throw std::runtime_error("idle stop did not clear tables");
 std::cout<<"PASS APB, partial commit, configuration, capacity, EOF, marker, AXI faults, held AR/AW/W stop/drain"<<std::endl;
}
void external(Bus &b,unsigned fmt){
 Vector v{"external"+std::to_string(fmt),17,13,fmt,0};
 for(unsigned c=0;c<3;c++){auto q=file("tests/data/"+v.name+"_q"+std::to_string(c)+".bin");b.wr(0x20,c<<12);for(auto x:q)b.wr(0x24,x);b.wr(0x34,1);}
 for(unsigned kind=1;kind<=4;kind++)for(unsigned id=0;id<2;id++){
 auto data=file("tests/data/"+v.name+"_table"+std::to_string(kind)+"_"+std::to_string(id)+".bin");b.wr(0x20,(kind<<14)|(id<<12));for(unsigned i=0;i<data.size();i+=4)b.wr(0x24,uint32_t(data[i])|(uint32_t(data[i+1])<<8)|(uint32_t(data[i+2])<<16)|(uint32_t(data[i+3])<<24));b.wr(0x34,1);
 }
 b.wr(0x3c,0xed0);configure(b,v,true);auto scan=file("tests/data/"+v.name+".scan");std::copy(scan.begin(),scan.end(),b.mem.begin()+0x80000);
 for(unsigned c=0;c<3;c++)std::fill(b.mem.begin()+0x10000+c*0x10000,b.mem.begin()+0x20000+c*0x10000,0xa5);
 auto begin=b.cycle;b.wr(0,3);auto st=b.wait_job();if(st&4)throw std::runtime_error(v.name+" error "+std::to_string(b.rd(0x1c)));
 unsigned hs=fmt?2:1,vs=fmt==2?2:1;
 for(unsigned c=0;c<3;c++){unsigned w=c?(v.w+hs-1)/hs:v.w,h=c?(v.h+vs-1)/vs:v.h,stride=(w+7)&~7u;auto expected=file("tests/data/"+v.name+"_out"+std::to_string(c)+".bin");for(unsigned y=0;y<h;y++)for(unsigned x=0;x<stride;x++)if(b.mem[0x10000+c*0x10000+y*stride+x]!=(x<w?expected[y*w+x]:0xa5))throw std::runtime_error(v.name+" external pixel mismatch");}
 std::cout<<v.name<<" decode cycles="<<b.cycle-begin<<" scan_bytes="<<scan.size()<<std::endl;b.wr(4,2);
}
void restart_tests(Bus &b){
 std::ifstream manifest("tests/data/restart/manifest.txt");if(!manifest)throw std::runtime_error("restart manifest missing");
 std::string name;unsigned w,h,fmt,interval,select,expected_error;unsigned tested=0;
 auto run=[&](std::string name,unsigned w,unsigned h,unsigned fmt,unsigned interval,unsigned select,unsigned expected_error,bool stop){
  Vector v{"restart/"+name,w,h,fmt,0};
  for(unsigned c=0;c<3;c++){auto q=file("tests/data/"+v.name+"_q"+std::to_string(c)+".bin");b.wr(0x20,c<<12);for(auto x:q)b.wr(0x24,x);b.wr(0x34,1);}
  for(unsigned kind=3;kind<=4;kind++)for(unsigned id=0;id<2;id++){
   auto data=file("tests/data/"+v.name+"_table"+std::to_string(kind)+"_"+std::to_string(id)+".bin");b.wr(0x20,(kind<<14)|(id<<12));
   for(unsigned i=0;i<data.size();i+=4)b.wr(0x24,uint32_t(data[i])|(uint32_t(data[i+1])<<8)|(uint32_t(data[i+2])<<16)|(uint32_t(data[i+3])<<24));b.wr(0x34,1);
  }
  b.wr(0x3c,select);b.wr(0x6c,interval);configure(b,v,true);auto scan=file("tests/data/"+v.name+".scan");std::copy(scan.begin(),scan.end(),b.mem.begin()+0x80000);
  for(unsigned c=0;c<3;c++)std::fill(b.mem.begin()+0x10000+c*0x10000,b.mem.begin()+0x20000+c*0x10000,0xa5);
  auto begin=b.cycle;b.wr(0,3);
  if(stop){unsigned n=0;while(!b.d.rootp->jpeg_top__DOT__restart_pending){b.tick();if(++n>100000)throw std::runtime_error("restart stop boundary timeout");}b.wr(0,4);}
  auto status=b.wait_job();unsigned code=b.rd(0x1c);
  if(expected_error){if(!(status&4)||(expected_error!=255&&code!=expected_error))throw std::runtime_error(name+" expected error "+std::to_string(expected_error)+" actual="+std::to_string(code));b.wr(4,4);}
  else{
   if(status&4)throw std::runtime_error(name+" restart decode error "+std::to_string(code));
   unsigned hs=fmt?2:1,vs=fmt==2?2:1;
   for(unsigned c=0;c<3;c++){unsigned cw=c?(w+hs-1)/hs:w,ch=c?(h+vs-1)/vs:h,stride=(cw+7)&~7u;auto exp=file("tests/data/"+v.name+"_out"+std::to_string(c)+".bin");
    for(unsigned y=0;y<ch;y++)for(unsigned x=0;x<stride;x++)if(b.mem[0x10000+c*0x10000+y*stride+x]!=(x<cw?exp[y*cw+x]:0xa5))throw std::runtime_error(name+" restart pixel/stride mismatch");
   }
   b.wr(4,2);
  }
  if(!b.reads.empty()||!b.writes.empty()||!b.beats.empty()||!b.responses.empty())throw std::runtime_error("restart job not drained");
  std::cout<<name<<" restart decode cycles="<<b.cycle-begin<<" status="<<(expected_error?"expected error":"PASS")<<" code="<<code<<std::endl;
 };
 while(manifest>>name>>w>>h>>fmt>>interval>>select>>expected_error){run(name,w,h,fmt,interval,select,expected_error,false);tested++;}
 run("fmt2_ri1",79,35,2,1,528,9,true);
 run("fmt2_ri1",79,35,2,1,528,0,false);
 b.wr(0x6c,1);tables(b,16);configure(b,{"flat",8,8,0,16},false);b.wr(0,1);auto status=b.wait_job();if(!(status&4)||b.rd(0x1c)!=1)throw std::runtime_error("encode nonzero restart config accepted");b.wr(4,4);b.wr(0x6c,0);
 std::cout<<"PASS "<<tested<<" restart vectors, MCU 444/422/420, sequence wrap, padding/EOF/errors, stop/recovery, encode config rejection"<<std::endl;
}
void performance(Bus &b,bool stress=false,bool variable=false){
 b.random=variable;b.variable_delay=variable;std::string prefix=stress?"a4_stress":(variable?"a4_variable":"a4");b.mem.resize(128*1024*1024,0xa5);auto input=file("tests/data/a4_planar.bin");unsigned w=2480,h=3508;uint64_t samples=uint64_t(w)*h*3;unsigned bases[3]={0x100000,0x1100000,0x2100000};unsigned jp=0x3100000;
 if(stress){uint32_t seed=20261005;for(auto &x:input){seed^=seed<<13;seed^=seed>>17;seed^=seed<<5;x=seed&255;}}
 tables(b,16);b.wr(8,(h<<16)|w);b.wr(0xc,0);b.wr(0x10,samples);b.wr(0x28,0);b.wr(0x14,0x2000000);b.wr(0x2c,0);b.wr(0x58,jp);b.wr(0x5c,0);
 for(unsigned c=0;c<3;c++){b.wr(0x40+c*8,bases[c]);b.wr(0x44+c*8,0);b.wr(0x60+c*4,w);std::copy(input.begin()+c*w*h,input.begin()+(c+1)*w*h,b.mem.begin()+bases[c]);}
 b.stats=Stats{};b.delay_sum=0;b.delay_count=0;auto begin=b.cycle;b.wr(0,1);auto st=b.wait_job(1000000000);auto enc_cycles=b.cycle-begin;auto enc_stats=b.stats;double encode_nominal_delay=double(b.delay_sum)/b.delay_count;auto bytes=b.rd(0x18);if(st&4)throw std::runtime_error("A4 encode error "+std::to_string(b.rd(0x1c)));
 std::ofstream scan("build/"+prefix+".scan",std::ios::binary);scan.write(reinterpret_cast<char*>(b.mem.data()+jp),bytes);scan.close();
 std::cout<<"A4 encode cycles="<<enc_cycles<<" scan_bytes="<<bytes<<" samples="<<samples<<std::endl;b.wr(4,2);b.wr(0x10,bytes);b.wr(0x14,samples);
 // Independent libjpeg-produced JPEG for the decoder performance job.
 auto decoder_scan=file("build/"+prefix+"_decode_input.scan");
 std::copy(decoder_scan.begin(),decoder_scan.end(),b.mem.begin()+jp);b.wr(0x10,decoder_scan.size());
 for(unsigned c=0;c<3;c++){auto q=file("build/"+prefix+"_decode_q"+std::to_string(c)+".bin");b.wr(0x20,c<<12);for(auto x:q)b.wr(0x24,x);b.wr(0x34,1);}
 for(unsigned kind=3;kind<=4;kind++)for(unsigned id=0;id<2;id++){
 auto data=file("build/"+prefix+"_decode_table"+std::to_string(kind)+"_"+std::to_string(id)+".bin");b.wr(0x20,(kind<<14)|(id<<12));for(unsigned i=0;i<data.size();i+=4)b.wr(0x24,uint32_t(data[i])|(uint32_t(data[i+1])<<8)|(uint32_t(data[i+2])<<16)|(uint32_t(data[i+3])<<24));b.wr(0x34,1);}
 b.wr(0x3c,0xed0);
 for(auto base:bases)std::fill(b.mem.begin()+base,b.mem.begin()+base+w*h,0xa5);
 b.stats=Stats{};b.delay_sum=0;b.delay_count=0;begin=b.cycle;b.wr(0,3);st=b.wait_job(1000000000);auto dec_cycles=b.cycle-begin;if(st&4)throw std::runtime_error("A4 decode error "+std::to_string(b.rd(0x1c)));if(b.rd(0x18)!=samples)throw std::runtime_error("A4 samples");
 std::ofstream raw("build/"+prefix+"_decoded.bin",std::ios::binary);for(auto base:bases)raw.write(reinterpret_cast<char*>(b.mem.data()+base),w*h);raw.close();
 std::ofstream report("build/"+(stress?std::string("performance_stress"):(variable?std::string("performance_variable"):std::string("performance")))+".json");
 report<<"{\"width\":2480,\"height\":3508,\"blocks\":408270,\"encode_cycles\":"<<enc_cycles<<",\"decode_cycles\":"<<dec_cycles<<",\"scan_bytes\":"<<bytes<<",\"decode_input_bytes\":"<<decoder_scan.size()<<",\"samples\":"<<samples<<",\"axi_latency_cycles\":128,\"variable_latency\":"<<(variable?"true":"false")<<",\"seed\":20261005,\"encode_nominal_delay_mean\":"<<encode_nominal_delay<<",\"decode_nominal_delay_mean\":"<<double(b.delay_sum)/b.delay_count;
 auto stats=[&](std::string name,const Stats &x){report<<",\""<<name<<"\":{\"input_fifo_peak\":"<<x.input_peak<<",\"output_fifo_peak\":"<<x.output_peak<<",\"reserved_peak\":"<<x.reserved_peak<<",\"ar_wait\":"<<x.ar_wait<<",\"aw_wait\":"<<x.aw_wait<<",\"w_wait\":"<<x.w_wait<<",\"r_wait\":"<<x.r_wait<<",\"transform_input_wait\":"<<x.t_wait<<",\"quant_input_wait\":"<<x.q_wait<<",\"entropy_input_wait\":"<<x.e_wait<<",\"observed_first_r_handshake_delay_mean\":"<<double(x.read_delay_sum)/x.read_count<<"}";};stats("encode_stats",enc_stats);stats("decode_stats",b.stats);report<<"}\n";
 std::cout<<"A4 decode cycles="<<dec_cycles<<" 100ppm_budget=153600000"<<std::endl;
}
int main(int argc,char**argv){Verilated::commandArgs(argc,argv);try{
 Bus b;b.reset();if(argc>1&&std::string(argv[1])=="--restart"){restart_tests(b);return 0;}if(argc>1&&std::string(argv[1])=="--restart-variable"){b.variable_delay=true;restart_tests(b);return 0;}if(argc>1&&std::string(argv[1]).find("--performance")==0){performance(b,std::string(argv[1])=="--performance-stress",std::string(argv[1])=="--performance-variable");return 0;}if(argc>1&&std::string(argv[1])=="--variable")b.variable_delay=true;b.wr(0x9,1,true);
 for(auto v:std::vector<Vector>{{"flat",8,8,0,16},{"edge444",17,13,0,16},{"edge422",17,13,1,16},{"edge420",17,13,2,16},{"q255",9,9,2,255},{"dense",16,16,0,1},{"gradient",32,24,0,8},{"tiny444",1,1,0,1},{"tiny420",1,1,2,16},{"small422",7,5,1,13},{"small420",7,5,2,13}})test_vector(b,v);
 test_vector(b,{"gradient",32,24,0,8},0xff8);
 for(unsigned fmt=0;fmt<3;fmt++)external(b,fmt);
 error_tests(b);
 std::cout<<"PASS top vectors; max_read_outstanding="<<b.max_rd<<" max_write_outstanding="<<b.max_wr<<" nominal_mean_response_cycles="<<double(b.delay_sum)/b.delay_count<<std::endl;
 }catch(const std::exception&e){std::cerr<<"FAIL: "<<e.what()<<std::endl;return 1;}return 0;}
