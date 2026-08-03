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
// Stack Module (for reference - same as stack.v)
// ---------------------------------------------------------------------------
module bf2_stack #(
  parameter int Depth = `DEPTH,
  parameter int Width = 16
)(
  input  logic              clk,
  input  logic [Depth-1:0]  ra,
  output logic [Width-1:0]  rd,
  input  logic              we,
  input  logic [Depth-1:0]  wa,
  input  logic [Width-1:0]  wd
);
  logic [Width-1:0] store [2**Depth];

  initial begin
    integer k;
    for (k = 0; k < (2**Depth); k++) store[k] = '0;
  end

  always_ff @(posedge clk) if (we) store[wa] <= wd;
  assign rd = store[ra];
endmodule
