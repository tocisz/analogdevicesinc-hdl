`include "common.h"

// ============================================================================
// BF2: Pipeline Stage Combinational Logic for Timing Analysis
// ============================================================================
// This version has ONLY combinational logic (no output registers) so we can
// measure the critical path delay through each stage's combinational logic.
// ============================================================================

/* verilator lint_off MULTITOP */
/* verilator lint_off UNUSEDSIGNAL */
/* verilator lint_off MULTIDRIVEN */
/* verilator lint_off WIDTHEXPAND */

// ---------------------------------------------------------------------------
// Stage 2: Decode / ALU Operand Setup (combinational only)
// ---------------------------------------------------------------------------
// Corrected pipeline partition:
//   S2 does ONLY pre-ALU operand setup + pure control decode (flags that do NOT
//   consume alu_c).  Signals that depend on alu_c (mem_dout, maddr_next, and the
//   skip pc_next) live in S3 Execute AFTER the ALU -- see bf2_s3_execute_comb.
//   (In BF1 these were all written in the "after ALU" block, but the flags are
//   pure opcode decode and can be produced one stage early.)
// ---------------------------------------------------------------------------
module bf2_s2_decode_comb #(
  parameter int DataAddressWidth = `DADDR_WIDTH,
  parameter int CodeAddressWidth = `CADDR_WIDTH,
  parameter int DataWidth  = `DATA_WIDTH
)(
  input  logic [7:0]              insn,
  input  logic [DataAddressWidth-1:0]  maddr,
  input  logic [DataWidth-1:0]   mem_din,
  input  logic                    lj,
  input  logic [4:0]              lj_offset,
  input  logic [CodeAddressWidth-1:0]  pc,

  output logic signed [DataAddressWidth-1:0] alu_a,
  output logic signed [CodeAddressWidth-1:0] alu_b,
  output logic                          lj_out,
  output logic [4:0]                    lj_offset_out,
  output logic                          mem_wr,
  output logic                          io_wr,
  output logic                          io_rd,
  output logic                          do_jmp,
  output logic                          do_ret
);

  // 6-bit low sum with carry (shared between pipeline step 1 and lj_offset update)
  logic [5:0] pj_low_sum;
  assign pj_low_sum = pc[4:0] + insn[4:0];
  assign lj_offset_out = pj_low_sum[4:0];

  // Suppress unused warning
  logic _unused;
  assign _unused = ^lj_offset;

  // --- Before ALU (decode operands) ---
  always_comb begin
    alu_a = 'x;
    alu_b = 'x;
    casez ({lj, insn[7:6]})
      3'b0_00: begin alu_a = maddr; alu_b = $signed({insn[5:0], 7'b0}) >>> 7; end // < >
      3'b0_01: begin alu_a = {7'b0, mem_din}; alu_b = $signed({insn[5:0], 7'b0}) >>> 7; end // - +
      3'b0_10: begin alu_a = {2'b0, pc}; alu_b = $signed({insn[5:0], 7'b0}) >>> 7; end // [
      3'b1_??: ; // long jump - result from pipeline registers
      3'b0_11: ; // ALU not used
      default: ;
    endcase
  end

  // --- Control decode: pure instruction decode, independent of alu_c ---
  always_comb begin
    mem_wr   = 1'b0;
    io_wr    = 1'b0;
    io_rd    = 1'b0;
    lj_out   = 1'b0;
    do_jmp   = 1'b0;
    do_ret   = 1'b0;

    casez ({lj, insn[7:5]})
      4'b0_00?: ; // < or >: maddr_next = alu_c computed in S3
      4'b0_01?: mem_wr = 1'b1; // - or +: mem_dout = alu_c[7:0] computed in S3
      4'b0_100: begin do_jmp = |insn[4:0]; do_ret = ~do_jmp; end // [ or ]
      4'b1_???: ; // long jump - handled by lj in pc logic
      4'b0_101: begin lj_out = 1'b1; end // begin long jump
      4'b0_110: begin mem_wr = 1'b1; io_rd = 1'b1; end // ,
      4'b0_111: begin io_wr = 1'b1; end // .
      default: ;
    endcase
  end
endmodule
