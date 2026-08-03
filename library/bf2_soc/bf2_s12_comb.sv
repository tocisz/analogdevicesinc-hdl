`include "common.h"

// ============================================================================
// BF2-PHASE: Phase A cloud — fetch + decode + branch resolution (S1+S2)
// ============================================================================
// Combinational only.  Inputs are the committed architectural state
// (pc_r, maddr, lj_r, lj_offset_r, pj_*, rst0) plus the fetched insn and
// the (bypassed) DMEM read.  Outputs are captured into pc_r and the FD/EX
// registers when FD advances.
//
// Branch resolution lives HERE (not in S3): pc_next is a pure function of
// the committed state + mem_din, so the next fetch address is known in the
// same cycle as decode (code_addr prefetch = pc_next).
// ============================================================================
module bf2_s12_comb #(
  parameter int DataAddressWidth = `DADDR_WIDTH,
  parameter int CodeAddressWidth = `CADDR_WIDTH,
  parameter int DataWidth  = `DATA_WIDTH
)(
  input  logic [7:0]              insn,
  input  logic [CodeAddressWidth-1:0]  pc,
  input  logic [DataAddressWidth-1:0]  maddr,
  input  logic [DataWidth-1:0]   mem_din,
  input  logic                    lj,          // long-jump pending (jump byte)
  input  logic [4:0]              lj_offset,   // arch lj_offset (prefix value)
  input  logic                    pj_carry5,   // arch long-jump helper regs
  input  logic [7:0]              pj_pc_high,
  input  logic [CodeAddressWidth-1:0]  rst0,        // return stack top

  output logic signed [DataAddressWidth-1:0] alu_a,
  output logic signed [CodeAddressWidth-1:0] alu_b,
  output logic                          lj_next,        // prefix seen this instr
  output logic [4:0]                    lj_offset_next, // pc[4:0] + insn[4:0]
  output logic                          pj_carry5_next, // carry of that add
  output logic [7:0]                    pj_pc_high_next,// pc[12:5] of the prefix
  output logic                          mem_wr,         // '-' '+' ','
  output logic                          io_wr,          // '.'
  output logic                          io_rd,          // ','
  output logic [CodeAddressWidth-1:0]        pc_next,        // branch-resolved pc
  output logic                          push,           // enter loop: push pc+1
  output logic                          pop             // leave loop: pop
);

  // ---- Long-jump step 1 (prefix cycle, computed for every insn like BF1):
  // low 5 bits of pc + insn and the carry out.  Used as lj_offset for the
  // jump byte two phases later and captured into pj_carry5/pj_pc_high when
  // this instruction IS a prefix.
  logic [5:0] pj_low_sum;
  assign pj_low_sum = pc[4:0] + insn[4:0];
  assign lj_offset_next = pj_low_sum[4:0];
  assign pj_carry5_next = pj_low_sum[5];
  assign pj_pc_high_next = pc[12:5];

  // ---- Long-jump step 2 (jump cycle): target = {high8, low5}
  // parallel adds from the committed pj registers + the current (jump byte)
  // insn; only used when lj=1.  8-bit sum (carry-out unused -> no pj_mid_sum bit 8).
  logic [7:0] pj_mid_sum;
  assign pj_mid_sum = pj_pc_high + insn + {{(7){1'b0}}, pj_carry5};
  logic [CodeAddressWidth-1:0] pj_result;
  assign pj_result = {pj_mid_sum[7:0], lj_offset[4:0]};

  // ---- Short-`[` skip target: pc + sign-extended insn[5:0] (BF1's ALU
  // for the [ opcode: alu_a = {0,pc}, alu_b = signext(insn[5:0]))
  logic [CodeAddressWidth-1:0] skip_target;
  assign skip_target = pc + {{(CodeAddressWidth-6){insn[5]}}, insn[5:0]};

  // ---- Pre-ALU operand setup (identical to BF1 "before ALU" block)
  always_comb begin
    alu_a = 'x;
    alu_b = 'x;
    casez ({lj, insn[7:6]})
      3'b0_00: begin
        alu_a = maddr;
        alu_b = $signed({insn[5:0], 7'b0}) >>> 7;  // < >
      end
      3'b0_01: begin
        alu_a = {7'b0, mem_din};
        alu_b = $signed({insn[5:0], 7'b0}) >>> 7;  // - +
      end
      3'b0_10: begin
        alu_a = {2'b0, pc};
        alu_b = $signed({insn[5:0], 7'b0}) >>> 7;  // [
      end
      3'b1_??: ; // long jump - result from the pj registers
      3'b0_11: ; // ALU not used
      default: ;
    endcase
  end

  // ---- Pure control decode (identical to BF1 "after ALU" block flags)
  always_comb begin
    mem_wr  = 1'b0;
    io_wr   = 1'b0;
    io_rd   = 1'b0;
    lj_next = 1'b0;
    casez ({lj, insn[7:5]})
      4'b0_00?: ;                          // < >: maddr_next = alu_c (EX)
      4'b0_01?: mem_wr = 1'b1;             // - +: mem_dout = alu_c[7:0] (EX)
      4'b0_100: ;                          // [ or ]: handled by branch below
      4'b1_???: ;                          // long jump - unconditional branch
      4'b0_101: lj_next = 1'b1;            // begin long jump (prefix byte)
      4'b0_110: begin mem_wr = 1'b1; io_rd = 1'b1; end // ,
      4'b0_111: io_wr = 1'b1;              // .
      default: ;
    endcase
  end

  // ---- Branch resolution: pc_next + return-stack action
  // BF1 semantics: default pc+1; [ / jump-byte enters the loop (push pc+1)
  // when the cell is non-zero, otherwise skips; ] loops to rst0 while the
  // cell is non-zero, otherwise falls through and pops.
  logic do_jmp;
  logic do_ret;
  always_comb begin
    do_jmp = 1'b0;
    do_ret = 1'b0;
    if (!lj && insn[7:5] == 3'b100) begin
      do_jmp = |insn[4:0];      // [ (length != 0)
      do_ret = ~do_jmp;         // ] (0x80)
    end
  end

  always_comb begin
    pc_next = pc + 1'b1;
    push    = 1'b0;
    pop     = 1'b0;

    if (do_jmp || lj) begin
      if (mem_din != 8'b0) begin
        push = 1'b1;            // enter the loop: push the return address
      end else begin
        pc_next = lj ? pj_result : skip_target;  // skip the loop
      end
    end else if (do_ret) begin
      if (mem_din != 8'b0) begin
        pc_next = rst0;         // loop again
      end else begin
        pop = 1'b1;             // leave the loop
      end
    end
  end
endmodule
