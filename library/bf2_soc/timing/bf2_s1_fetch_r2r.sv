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
// Stage 1: Fetch
// ---------------------------------------------------------------------------
module bf2_s1_fetch_r2r #(
  parameter int CodeAddressWidth = `CADDR_WIDTH
)(
  input  logic                         clk,
  input  logic [CodeAddressWidth-1:0]       pc,
  output logic [CodeAddressWidth-1:0]       code_addr,
  output logic [CodeAddressWidth-1:0]       pc_next
);
  logic [CodeAddressWidth-1:0] pc_r;
  logic [CodeAddressWidth-1:0] code_addr_c, pc_next_c;

  always_ff @(posedge clk) pc_r <= pc;

  bf2_s1_fetch_comb #(.CodeAddressWidth(CodeAddressWidth)) u_comb (
    .pc       (pc_r),
    .code_addr(code_addr_c),
    .pc_next  (pc_next_c)
  );

  always_ff @(posedge clk) begin
    code_addr_r <= code_addr_c;
    pc_next_r   <= pc_next_c;
  end

  logic [CodeAddressWidth-1:0] code_addr_r, pc_next_r;
  assign code_addr = code_addr_r;
  assign pc_next   = pc_next_r;
endmodule
