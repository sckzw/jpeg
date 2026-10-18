`include "jpeg_defs.vh"
module jpeg_apb(
 input clk,rst_n,input psel,penable,pwrite,input [11:0] paddr,input [31:0] pwdata,
 output reg [31:0] prdata,output reg pready,output reg pslverr,
 input busy,done,error,dma_idle,input [7:0] error_code,input [63:0] output_bytes,
 output reg start,output reg stop,output reg clear_done,output reg clear_error,output reg idle_clear,
 output reg mode,output reg [15:0] width,height,restart_interval,output reg [1:0] format,
 output reg [63:0] input_bytes,output_limit,y_base,cb_base,cr_base,jpeg_base,
 output reg [31:0] y_stride,cb_stride,cr_stride,output reg [11:0] table_select,
 output table_access,output table_write,output table_commit,output [2:0] table_kind,output [1:0] table_id,output [11:0] table_index,output [31:0] table_wdata,
 input table_ready,table_error,input [31:0] table_rdata,input [10:0] table_valid);
 reg [16:0] table_addr;reg [63:0] snapshot;reg known,writable;
 assign table_access=psel&&penable&&(paddr==`JPEG_REG_TABLE_DATA||paddr==`JPEG_REG_TABLE_COMMIT)&&!busy&&paddr[1:0]==0;
 assign table_write=pwrite&&paddr==`JPEG_REG_TABLE_DATA;assign table_commit=pwrite&&paddr==`JPEG_REG_TABLE_COMMIT&&pwdata==1;
 assign table_kind=table_addr[16:14];assign table_id=table_addr[13:12];assign table_index=table_addr[11:0];assign table_wdata=pwdata;
 always @*begin
 prdata=0;known=1;writable=1;pready=1;pslverr=0;
 case(paddr)
 `JPEG_REG_CONTROL:prdata={30'd0,mode,1'b0};
 `JPEG_REG_STATUS:prdata={28'd0,dma_idle,error,done,busy};
 `JPEG_REG_IMAGE_SIZE:prdata={height,width};`JPEG_REG_FORMAT:prdata={30'd0,format};
 `JPEG_REG_INPUT_LO:prdata=input_bytes[31:0];`JPEG_REG_INPUT_HI:prdata=input_bytes[63:32];
 `JPEG_REG_LIMIT_LO:prdata=output_limit[31:0];`JPEG_REG_LIMIT_HI:prdata=output_limit[63:32];
 `JPEG_REG_OUTPUT_LO:begin prdata=output_bytes[31:0];writable=0;end
 `JPEG_REG_OUTPUT_HI:begin prdata=snapshot[63:32];writable=0;end
 `JPEG_REG_ERROR_CODE:begin prdata={24'd0,error_code};writable=0;end
 `JPEG_REG_TABLE_ADDR:prdata={15'd0,table_addr};`JPEG_REG_TABLE_DATA:prdata=table_rdata;
 `JPEG_REG_TABLE_COMMIT:begin if(!pwrite)known=0;end
 `JPEG_REG_TABLE_VALID:begin prdata={21'd0,table_valid};writable=0;end
 `JPEG_REG_TABLE_SELECT:prdata={20'd0,table_select};
 `JPEG_REG_Y_LO:prdata=y_base[31:0];`JPEG_REG_Y_HI:prdata=y_base[63:32];
 `JPEG_REG_CB_LO:prdata=cb_base[31:0];`JPEG_REG_CB_HI:prdata=cb_base[63:32];
 `JPEG_REG_CR_LO:prdata=cr_base[31:0];`JPEG_REG_CR_HI:prdata=cr_base[63:32];
 `JPEG_REG_JPEG_LO:prdata=jpeg_base[31:0];`JPEG_REG_JPEG_HI:prdata=jpeg_base[63:32];
 `JPEG_REG_RESTART_INTERVAL:prdata={16'd0,restart_interval};
 `JPEG_REG_Y_STRIDE:prdata=y_stride;`JPEG_REG_CB_STRIDE:prdata=cb_stride;`JPEG_REG_CR_STRIDE:prdata=cr_stride;
 default:known=0;
 endcase
 if(psel&&penable)begin
 if(!known||paddr[1:0]!=0||(pwrite&&!writable))pslverr=1;
 if(pwrite&&busy&&paddr!=`JPEG_REG_STATUS&&!(paddr==0&&pwdata[2]&&!pwdata[0]&&pwdata[31:3]==0))pslverr=1;
 if(pwrite&&paddr==0)begin
 if(pwdata[31:3]!=0||(pwdata[0]&&pwdata[2])||(pwdata[0]&&(done||error)))pslverr=1;
 end
 if(pwrite&&paddr==4&&(pwdata[31:3]!=0||pwdata[0]||(pwdata[2]&&!dma_idle)))pslverr=1;
 if(pwrite&&paddr==`JPEG_REG_RESTART_INTERVAL&&pwdata[31:16]!=0)pslverr=1;
 if(pwrite&&paddr==`JPEG_REG_FORMAT&&pwdata[31:2]!=0)pslverr=1;
 if(pwrite&&paddr==`JPEG_REG_TABLE_ADDR&&pwdata[31:17]!=0)pslverr=1;
 if(pwrite&&paddr==`JPEG_REG_TABLE_SELECT&&pwdata[31:12]!=0)pslverr=1;
 if(paddr==`JPEG_REG_TABLE_DATA||paddr==`JPEG_REG_TABLE_COMMIT)begin
 if(busy||(paddr==`JPEG_REG_TABLE_COMMIT&&pwdata!=1))pslverr=1;
 else begin pready=table_ready;pslverr=pslverr||table_error;end
 end
 end end
 always @(posedge clk)begin
 if(!rst_n)begin start<=0;stop<=0;clear_done<=0;clear_error<=0;idle_clear<=0;mode<=0;width<=0;height<=0;restart_interval<=0;format<=0;input_bytes<=0;output_limit<=0;y_base<=0;cb_base<=0;cr_base<=0;jpeg_base<=0;y_stride<=0;cb_stride<=0;cr_stride<=0;table_select<=0;table_addr<=0;snapshot<=0;end
 else begin
 start<=0;stop<=0;clear_done<=0;clear_error<=0;idle_clear<=0;
 if(psel&&penable&&pready&&!pslverr)begin
 if(paddr==`JPEG_REG_OUTPUT_LO&&!pwrite)snapshot<=output_bytes;
 if(paddr==`JPEG_REG_TABLE_DATA)table_addr[11:0]<=table_addr[11:0]+1'b1;
 if(pwrite)case(paddr)
 `JPEG_REG_CONTROL:begin if(!busy)mode<=pwdata[1];start<=pwdata[0];stop<=pwdata[2]&&busy;idle_clear<=pwdata[2]&&!busy;if(pwdata[0])snapshot<=0;end
 `JPEG_REG_STATUS:begin clear_done<=pwdata[1];clear_error<=pwdata[2];end
 `JPEG_REG_IMAGE_SIZE:begin width<=pwdata[15:0];height<=pwdata[31:16];end
 `JPEG_REG_FORMAT:format<=pwdata[1:0];
 `JPEG_REG_RESTART_INTERVAL:restart_interval<=pwdata[15:0];
 `JPEG_REG_INPUT_LO:input_bytes[31:0]<=pwdata;`JPEG_REG_INPUT_HI:input_bytes[63:32]<=pwdata;
 `JPEG_REG_LIMIT_LO:output_limit[31:0]<=pwdata;`JPEG_REG_LIMIT_HI:output_limit[63:32]<=pwdata;
 `JPEG_REG_TABLE_ADDR:table_addr<=pwdata[16:0];`JPEG_REG_TABLE_SELECT:table_select<=pwdata[11:0];
 `JPEG_REG_Y_LO:y_base[31:0]<=pwdata;`JPEG_REG_Y_HI:y_base[63:32]<=pwdata;
 `JPEG_REG_CB_LO:cb_base[31:0]<=pwdata;`JPEG_REG_CB_HI:cb_base[63:32]<=pwdata;
 `JPEG_REG_CR_LO:cr_base[31:0]<=pwdata;`JPEG_REG_CR_HI:cr_base[63:32]<=pwdata;
 `JPEG_REG_JPEG_LO:jpeg_base[31:0]<=pwdata;`JPEG_REG_JPEG_HI:jpeg_base[63:32]<=pwdata;
 `JPEG_REG_Y_STRIDE:y_stride<=pwdata;`JPEG_REG_CB_STRIDE:cb_stride<=pwdata;`JPEG_REG_CR_STRIDE:cr_stride<=pwdata;
 default:begin end endcase
 end end end
endmodule
