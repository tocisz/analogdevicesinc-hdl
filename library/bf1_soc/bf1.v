`include "common.h"

module bf1 (
   input wire clk,
   input wire resetq,
   input wire cpu_active,       // clock enable: 0 = stall
   input wire ctrl_reset_i,     // synchronous reset from PS register (1-cycle pulse)

   output wire [`DADDR_WIDTH-1:0] mem_addr,
   output reg  mem_wr,
   output reg  [`DATA_WIDTH-1:0] mem_dout,
   input  wire [`DATA_WIDTH-1:0] mem_din,

   output reg  io_wr,
   output reg  io_rd,           // high during ',' instruction
   input  wire [`DATA_WIDTH-1:0] io_din,
   output wire [`DATA_WIDTH-1:0] io_dout,

   output wire [`CADDR_WIDTH-1:0] code_addr,
   input  wire [7:0] insn,

   output wire [`DEPTH-1:0] _rsp,
   output wire [`CADDR_WIDTH-1:0] pc_debug
);

   reg [`CADDR_WIDTH-1:0] pc, pcN;
   reg [`DADDR_WIDTH-1:0] maddr, maddrN; // Tape address
   reg [`DEPTH-1:0] rsp, rspN;

   // for debug only
   assign _rsp = rspN;
   assign pc_debug = pc;
   assign code_addr = pcN; // output next value as soon as it propagates
   assign mem_addr = maddrN; // output next value as soon as it propagates
   reg rstkW = 0;                 // R stack write
   wire [`CADDR_WIDTH-1:0] rstkD;   // R stack write value
   wire [`CADDR_WIDTH-1:0] rst0;
   stack #(.DEPTH(`DEPTH),.WIDTH(`CADDR_WIDTH)) rstack (
     .clk(clk),
     .ra(rsp),
     .rd(rst0),
     .we(rstkW),
     .wa(rspN),
     .wd(rstkD)
   );

   // ALU
   reg signed [`DADDR_WIDTH-1:0] alu_a;
   reg signed [`CADDR_WIDTH-1:0] alu_b;
   reg [`DADDR_WIDTH-1:0] alu_c;

   reg lj, ljN;
   reg  [4:0] lj_offset;
   wire [4:0] lj_offsetN;
   reg        pj_carry5;          // carry from prefix low addition
   reg  [7:0] pj_pc_high;        // pc[12:5] captured in prefix cycle

   // Pipeline result for long jump (step 2: mid addition with saved carry + pc_high)
   wire [7:0] pj_mid_sum;
   wire [12:0] pj_result;
   assign pj_mid_sum = pj_pc_high + insn + pj_carry5;
   assign pj_result = {pj_mid_sum[7:0], lj_offset[4:0]};

   // 6-bit low sum with carry (shared between pipeline step 1 and lj_offset update)
   wire [5:0] pj_low_sum = pc[4:0] + insn[4:0];

   // before ALU
   always @(maddr, insn, mem_din, lj, lj_offset, pc)
   begin
     alu_a  = 15'bX; // let synthesis decide what takes least resources
     alu_b  = 13'bX;
     casez ({lj,insn[7:6]})
       3'b0_00: begin alu_a = maddr;           alu_b = $signed({insn[5:0],7'b0}) >>> 7; end // < >
       3'b0_01: begin alu_a = {7'b0,mem_din};  alu_b = $signed({insn[5:0],7'b0}) >>> 7; end // - +
       3'b0_10: begin alu_a = {2'b0,pc};       alu_b = $signed({insn[5:0],7'b0}) >>> 7; end // [
       3'b1_??: ; // long jump - result from pipeline registers
       3'b0_11: ; // ALU not used
     endcase
   end

   // ALU
   always @(alu_a, alu_b)
   begin
      alu_c = alu_a + ($signed({alu_b,2'b0}) >>> 2);
   end

   reg do_jump_or_ret;
   reg do_jump;

   // after ALU
   assign io_dout = mem_din; // nothing else can go as IO output
   always @(pc, maddr, insn, alu_c, io_din, lj)
   begin
     // defaults
     mem_wr = 0;
     io_wr  = 0;
     io_rd  = 0;
     ljN = 0;
     maddrN = maddr;
     mem_dout = io_din;
     do_jump_or_ret = 0;
     do_jump = 0;

     casez ({lj,insn[7:5]})
       4'b0_00?: begin   maddrN = alu_c; end // < or >
       4'b0_01?: begin mem_dout = alu_c[7:0]; mem_wr = 1; end // - or +
       4'b0_100: begin do_jump_or_ret = 1; do_jump = |insn[4:0]; end // [ or ]
       4'b1_???: ; // long jump - handled by lj in pcN logic (unconditional)
       4'b0_101: begin     ljN = 1; end // begin long jump
       4'b0_110: begin  mem_wr = 1; io_rd = 1; end // ,
       4'b0_111: begin   io_wr = 1; end // .
     endcase
   end

   // calculate pc
   assign rstkD = pcN; // if we put anything on stack, it's pcN
   // Low 5 bits of pc[4:0] + prefix_insn[4:0] (step 1 of pipeline)
   // lj_offset serves as pj_low (pj_low = lj_offset)
   assign lj_offsetN = (pc[4:0] + insn[4:0]);
   always @ (do_jump_or_ret, do_jump, pc, mem_din, rsp, rst0, alu_c, lj, pj_result)
   begin
     // default: go to the next instruction
     pcN   = pc + 1'b1;
     rspN  = rsp;
     rstkW = 0;

     if (do_jump_or_ret)
     begin
       if (do_jump)
       begin // [
         if (mem_din != 0) begin
           rspN = rsp + 1'b1; // into the loop
           rstkW = 1;
         end else begin
           pcN = alu_c[12:0]; // skip the loop
         end
       end
       else
       begin // ]
         if (mem_din != 0) pcN = rst0; // loop again
         else rspN = rsp - 1'b1; // leave the loop
       end
     end

     if (lj) begin
       if (mem_din == 0)
         pcN = pj_result; // skip the loop
       else begin
         rspN = rsp + 1'b1; // enter the loop, push return address
         rstkW = 1;
       end
     end
   end

   always @(negedge resetq or posedge clk)
   begin
     if (!resetq || ctrl_reset_i) begin
       { pc, rsp, maddr, lj, lj_offset, pj_carry5, pj_pc_high } <= 0;
     end else if (cpu_active) begin
       { pc, rsp, maddr, lj, lj_offset }
       <= { pcN, rspN, maddrN, ljN, lj_offsetN };
       if (ljN) begin
         // --- Long jump pipeline step 1 (prefix cycle) ---
         pj_carry5  <= pj_low_sum[5];   // carry out of low 5-bit addition
         pj_pc_high <= pc[12:5];
       end
     end
   end

endmodule
