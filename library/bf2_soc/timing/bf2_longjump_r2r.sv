`include "common.h"

// ============================================================================
// BF2: Register-to-Register Wrappers for Pipeline Stage Timing Analysis
// ============================================================================
// Each wrapper places an input register (the pipeline stage before) and an
// output register (the pipeline stage after) around a combinational stage
// core, so the measured timing path is ONLY:
//
//     FF_in -> stage combinational logic -> FF_out
//
// The ports feed/tap only flip-flops -- IBUF/OBUF delays are not on any
// measured path. This simulates the stage used internally in the pipeline
// and reports the true logic+routing delay per stage at 100 MHz (10 ns).
// ============================================================================

/* verilator lint_off MULTITOP */
/* verilator lint_off UNUSEDSIGNAL */
/* verilator lint_off MULTIDRIVEN */
/* verilator lint_off WIDTHEXPAND */

// ---------------------------------------------------------------------------
// Long Jump Target Computation (2-cycle helper, faithful to bf2_pipeline.sv)
// ---------------------------------------------------------------------------
// NOT an alternative S3: this is the separate 2-cycle jump-target state
// machine that feeds the pc_next mux in S3 (pc_next = lj ? pj_result : alu_c).
//   prefix cycle: pj_low_sum = pc_r[4:0] + insn[4:0]; capture pj_carry5,
//                 pj_pc_high = pc_r[12:5]            (REGISTERED between cycles)
//   jump cycle:   pj_result  = {pj_pc_high_r + insn + {7'b0, pj_carry5_r},
//                                pj_low_sum[4:0]}    (parallel adds from regs)
// The two additions are NOT chained in the pipeline -- the carry is registered
// -- so the measured path is max(5-bit add, 8-bit add) + output register.
// ---------------------------------------------------------------------------
module bf2_longjump_r2r #(
  parameter int CodeAddressWidth = `CADDR_WIDTH
)(
  input  logic                       clk,
  input  logic [7:0]                 insn,          // jump instruction ([ or ])
  input  logic [CodeAddressWidth-1:0]     pc,            // architectural PC
  input  logic                       pj_carry5,     // prefix-cycle carry (saved)
  input  logic [7:0]                 pj_pc_high,    // prefix-cycle pc[12:5] (saved)
  output logic [CodeAddressWidth-1:0]     jump_target
);
  logic [7:0]             insn_r;
  logic [CodeAddressWidth-1:0] pc_r;
  logic                   pj_carry5_r;
  logic [7:0]             pj_pc_high_r;
  logic [CodeAddressWidth-1:0] jump_target_c, jump_target_r;
  logic [5:0]             pj_low_sum_c;

  always_ff @(posedge clk) begin
    insn_r      <= insn;
    pc_r        <= pc;
    pj_carry5_r <= pj_carry5;
    pj_pc_high_r<= pj_pc_high;
  end

  // Same combinational cloud as bf2_pipeline.sv (parallel, not chained):
  assign pj_low_sum_c  = pc_r[4:0] + insn_r[4:0];
  assign jump_target_c = {pj_pc_high_r + insn_r + {7'b0, pj_carry5_r},
                          pj_low_sum_c[4:0]};

  always_ff @(posedge clk) jump_target_r <= jump_target_c;
  assign jump_target = jump_target_r;
endmodule
