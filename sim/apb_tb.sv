`timescale 1ns/1ps
module apb_tb;
 reg clk=0,rst_n=0,psel=0,penable=0,pwrite=0,busy=0,done=0,error=0,dma_idle=1,table_ready=1,table_error=0;
 reg [11:0] paddr=0;reg [31:0] pwdata=0;reg [63:0] output_bytes=0;
 wire [31:0] prdata;wire pready,pslverr,start,stop,clear_done,clear_error,idle_clear,mode;
 wire [15:0] width,height,restart_interval;wire [1:0] format;wire [63:0] input_bytes,output_limit,y_base,cb_base,cr_base,jpeg_base;wire [31:0] y_stride,cb_stride,cr_stride;wire [11:0] table_select,table_index;wire table_access,table_write,table_commit;wire [2:0] table_kind;wire [1:0] table_id;wire [31:0] table_wdata;
 jpeg_apb apb(.restart_interval(restart_interval),.clk(clk),.rst_n(rst_n),.psel(psel),.penable(penable),.pwrite(pwrite),.paddr(paddr),.pwdata(pwdata),.prdata(prdata),.pready(pready),.pslverr(pslverr),.busy(busy),.done(done),.error(error),.dma_idle(dma_idle),.error_code(8'd9),.output_bytes(output_bytes),.start(start),.stop(stop),.clear_done(clear_done),.clear_error(clear_error),.idle_clear(idle_clear),.mode(mode),.width(width),.height(height),.format(format),.input_bytes(input_bytes),.output_limit(output_limit),.y_base(y_base),.cb_base(cb_base),.cr_base(cr_base),.jpeg_base(jpeg_base),.y_stride(y_stride),.cb_stride(cb_stride),.cr_stride(cr_stride),.table_select(table_select),.table_access(table_access),.table_write(table_write),.table_commit(table_commit),.table_kind(table_kind),.table_id(table_id),.table_index(table_index),.table_wdata(table_wdata),.table_ready(table_ready),.table_error(table_error),.table_rdata(32'hdeadc0de),.table_valid(11'h2af));
 task tick;begin clk=0;#1;clk=1;#1;end endtask
 reg [31:0] result;integer i;
 task transfer(input bit write,input [11:0] addr,input [31:0] value,input bit bad);
 begin
 psel=1;penable=0;pwrite=write;paddr=addr;pwdata=value;tick();penable=1;clk=0;#1;
 if(!pready||pslverr!=bad)$fatal(1,"APB access response at %h",addr);result=prdata;clk=1;#1;
 if(write&&!bad&&addr==0)begin if(start!=value[0]||stop!=(value[2]&&busy)||idle_clear!=(value[2]&&!busy))$fatal(1,"APB CONTROL pulses");end
 if(write&&!bad&&addr==4)begin if(clear_done!=value[1]||clear_error!=value[2])$fatal(1,"APB W1C pulses");end
 psel=0;penable=0;tick();
 end endtask
 initial begin
 tick();rst_n=1;tick();
 if(restart_interval!=0)$fatal(1,"restart reset");
 transfer(1,12'h06c,65535,0);transfer(0,12'h06c,0,0);if(result!=65535||restart_interval!=65535)$fatal(1,"restart register");
 transfer(1,12'h06c,65536,1);busy=1;transfer(1,12'h06c,0,1);busy=0;transfer(1,12'h06c,0,0);
 transfer(1,12'h010,32'h89abcdef,0);transfer(1,12'h028,32'h12345678,0);if(input_bytes!=64'h1234567889abcdef)$fatal(1,"INPUT_BYTES upper/lower");
 transfer(1,12'h014,32'h76543210,0);transfer(1,12'h02c,32'hfedcba98,0);if(output_limit!=64'hfedcba9876543210)$fatal(1,"OUTPUT_LIMIT upper/lower");
 output_bytes=64'h00000001ffffffff;transfer(0,12'h018,0,0);if(result!=32'hffffffff)$fatal(1,"counter LO");
 output_bytes=64'h0000000200000001;transfer(0,12'h030,0,0);if(result!=1)$fatal(1,"counter coherent snapshot");
 transfer(0,12'h018,0,0);if(result!=1)$fatal(1,"counter new LO");output_bytes=64'h0000000300000002;transfer(0,12'h030,0,0);if(result!=2)$fatal(1,"counter new HI");
 transfer(1,12'h000,1,0);transfer(0,12'h030,0,0);if(result!=0)$fatal(1,"snapshot reset on start");
 transfer(1,12'h018,1,1);transfer(1,12'h009,1,1);transfer(1,12'h000,5,1);
 transfer(1,12'h000,2,0);busy=1;dma_idle=0;transfer(1,12'h000,4,0);if(!mode)$fatal(1,"busy stop changed mode");
 transfer(1,12'h008,1,1);transfer(1,12'h004,2,0);transfer(1,12'h004,4,1);dma_idle=1;transfer(1,12'h004,4,0);busy=0;
 transfer(1,12'h020,(2<<14)|(1<<12)|123,0);transfer(0,12'h024,0,0);if(result!=32'hdeadc0de||table_index!=124)$fatal(1,"table read/index");
 table_error=1;transfer(0,12'h024,0,1);if(table_index!=124)$fatal(1,"failed table access changed index");table_error=0;
 table_ready=0;psel=1;penable=0;pwrite=1;paddr=12'h034;pwdata=1;tick();penable=1;
 repeat(5)begin clk=0;#1;if(pready||!table_access||!table_commit||table_kind!=2||table_id!=1)$fatal(1,"commit wait");clk=1;#1;end
 table_ready=1;tick();psel=0;penable=0;tick();
 $display("PASS APB 64-bit settings/snapshot rollover, pulses, busy restrictions, table wait/index");$finish;
 end
endmodule
