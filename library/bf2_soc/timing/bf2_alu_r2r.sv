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
// ALU (standalone)
// ---------------------------------------------------------------------------
module bf2_alu_r2r #(
  parameter int DataAddressWidth = `DADDR_WIDTH,
  parameter int CodeAddressWidth = `CADDR_WIDTH
)(
  input  logic                              clk,
  input  logic signed [DataAddressWidth-1:0]     alu_a,
  input  logic signed [CodeAddressWidth-1:0]     alu_b,
  output logic [DataAddressWidth-1:0]            alu_c
);
  logic signed [DataAddressWidth-1:0] alu_a_r;
  logic signed [CodeAddressWidth-1:0] alu_b_r;
  logic [DataAddressWidth-1:0]        alu_c_c, alu_c_r;

  always_ff @(posedge clk) begin
    alu_a_r <= alu_a;
    alu_b_r <= alu_b;
  end

  bf2_alu_comb #(.DataAddressWidth(DataAddressWidth), .CodeAddressWidth(CodeAddressWidth)) u_comb (
    .alu_a(alu_a_r),
    .alu_b(alu_b_r),
    .alu_c(alu_c_c)
  );

  always_ff @(posedge clk) alu_c_r <= alu_c_c;
  assign alu_c = alu_c_r;
endmodule
