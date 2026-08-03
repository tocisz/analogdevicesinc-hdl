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
// Stack2 (LIFO push/pop/top) - combinational core for timing measurement
// head is the top of stack (registered output -> zero read-path
// delay); the tail shift register holds the remaining 2^Depth - 1 entries.
// Depth is the stack-pointer width in BITS (capacity = 2^Depth entries),
// matching bf2_phase / bf2_s34_comb (which use Depth as rsp width).
// ---------------------------------------------------------------------------
module bf2_stack2_comb #(
  parameter int Depth = `DEPTH,     // stack-pointer width (bits) == log2 entries
  parameter int Width = `CADDR_WIDTH,
  localparam int Entries = (1 << Depth) - 1   // words in the tail shift register
)(
  input  logic              we,       // push (write enable)
  input  logic [1:0]        delta,    // {dir, move}: 00=hold, 01=push, 11=pop
  input  logic [Width-1:0]  wd,       // push data
  output logic [Width-1:0]  rd,       // top of stack
  input  logic [Width-1:0]  head,     // current head register value
  input  logic [((Width*Entries)-1):0] tail, // current tail register value
  output logic [Width-1:0]  headN,    // next head
  output logic [((Width*Entries)-1):0] tailN // next tail
);
  localparam int Bits = (Width * Entries) - 1;

  assign headN = we ? wd : tail[Width-1:0];
  assign tailN = delta[1] ? {{Width{1'b0}}, tail[Bits:Width]} : {tail[Bits-Width:0], head};
  assign rd = head;
endmodule
