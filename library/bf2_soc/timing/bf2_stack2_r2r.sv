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
// Stack2 (LIFO push/pop/top shift-register stack)
// Depth is the stack-pointer width in BITS (capacity = 2^Depth entries),
// matching bf2_phase / bf2_s34_comb (which use Depth as rsp width).
// ---------------------------------------------------------------------------
module bf2_stack2_r2r #(
  parameter int Depth = `DEPTH,     // stack-pointer width (bits) == log2 entries
  parameter int Width = `CADDR_WIDTH,
  localparam int Entries = (1 << Depth) - 1   // words in the tail shift register
)(
  input  logic                        clk,
  input  logic                        we,
  input  logic [1:0]                  delta,
  input  logic [Width-1:0]            wd,
  input  logic [Width-1:0]            head,
  input  logic [((Width*Entries)-1):0]  tail,
  output logic [Width-1:0]            rd,
  output logic [Width-1:0]            headN,
  output logic [((Width*Entries)-1):0]  tailN
);
  logic                   we_r;
  logic [1:0]             delta_r;
  logic [Width-1:0]       wd_r;
  logic [Width-1:0]       head_r;
  logic [((Width*Entries)-1):0] tail_r;
  logic [Width-1:0]       rd_c, rd_r;
  logic [Width-1:0]       headN_c, headN_r;
  logic [((Width*Entries)-1):0] tailN_c, tailN_r;

  always_ff @(posedge clk) begin
    we_r    <= we;
    delta_r <= delta;
    wd_r    <= wd;
    head_r  <= head;
    tail_r  <= tail;
  end

  bf2_stack2_comb #(.Depth(Depth), .Width(Width)) u_comb (
    .we   (we_r),
    .delta(delta_r),
    .wd   (wd_r),
    .head (head_r),
    .tail (tail_r),
    .rd   (rd_c),
    .headN(headN_c),
    .tailN(tailN_c)
  );

  always_ff @(posedge clk) begin
    rd_r    <= rd_c;
    headN_r <= headN_c;
    tailN_r <= tailN_c;
  end

  assign rd    = rd_r;
  assign headN = headN_r;
  assign tailN = tailN_r;
endmodule
