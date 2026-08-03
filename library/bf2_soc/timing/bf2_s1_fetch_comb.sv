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
// Stage 1: Instruction Fetch (combinational only)
// ---------------------------------------------------------------------------
module bf2_s1_fetch_comb #(
  parameter int CodeAddressWidth = `CADDR_WIDTH
)(
  input  logic [CodeAddressWidth-1:0]  pc,
  output logic [CodeAddressWidth-1:0]  code_addr,
  output logic [CodeAddressWidth-1:0]  pc_next
);
  assign code_addr = pc;
  assign pc_next   = pc + 1'b1;
endmodule
