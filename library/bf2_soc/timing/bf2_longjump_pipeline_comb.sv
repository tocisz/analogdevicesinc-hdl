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
// Long Jump Pipeline Helper (2-cycle: prefix + jump) - Combinational Core
// ---------------------------------------------------------------------------
module bf2_longjump_pipeline_comb #(
  parameter int CodeAddressWidth = `CADDR_WIDTH
)(
  input  logic [7:0]              prefix_insn,
  input  logic [7:0]              jump_insn,
  input  logic [CodeAddressWidth-1:0]  pc,

  output logic [CodeAddressWidth-1:0]  jump_target
);

  // Stage 1: Prefix cycle - compute low 5 bits + carry
  logic [5:0] low_sum;
  logic [4:0] pj_low;
  logic       carry5;
  logic [7:0] pc_high;

  always_comb begin
    low_sum = pc[4:0] + prefix_insn[4:0];
    pj_low  = low_sum[4:0];
    carry5  = low_sum[5];
    pc_high = pc[12:5];
  end

  // Stage 2: Jump cycle - mid addition with carry
  logic [7:0] mid_sum;
  always_comb begin
    mid_sum = pc_high + jump_insn + {7'b0, carry5};
  end

  assign jump_target = {mid_sum, pj_low};
endmodule
