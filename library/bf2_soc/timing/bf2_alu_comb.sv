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
// ALU Module (standalone for timing measurement)
// ---------------------------------------------------------------------------
module bf2_alu_comb #(
  parameter int DataAddressWidth = `DADDR_WIDTH,
  parameter int CodeAddressWidth = `CADDR_WIDTH
)(
  input  logic signed [DataAddressWidth-1:0] alu_a,
  input  logic signed [CodeAddressWidth-1:0] alu_b,
  output logic [DataAddressWidth-1:0]        alu_c
);
  always_comb begin
    alu_c = alu_a + ($signed({alu_b, 2'b0}) >>> 2);
  end
endmodule
