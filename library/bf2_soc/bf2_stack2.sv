`include "common.h"

// ============================================================================
// Stack2: LIFO Stack for Return Addresses (push/pop/top interface)
// ============================================================================
// Replaces the random-access stack.v with a proper call stack:
// - 1-cycle read latency (registered output)
// - shift-register sized (2^Depth x Width) vs a 2^(2^Depth) RAM
// - Push/pop semantics match BF1 usage exactly
//
// Depth is the stack-pointer width in BITS (log2 of the number of entries):
//   capacity       = 2^Depth entries  (head + tail)
//   tail words     = 2^Depth - 1      (everything under the head)
// Defaults come from common.h (`DEPTH = 4 -> 16 entries, `CADDR_WIDTH).
// ============================================================================
module bf2_stack2 #(
  parameter int Depth = `DEPTH,     // stack-pointer width in bits (== log2 entries)
  parameter int Width = `CADDR_WIDTH // return-address width (== CodeAddressWidth)
)(
  input  logic              clk,
  input  logic              we,       // push (write enable)
  input  logic [1:0]        delta,    // {pop, push}: 00=hold, 01=push, 11=pop
  output logic [Width-1:0]  rd,       // top of stack (registered)
  input  logic [Width-1:0]  wd        // push data
);
  // stack capacity = 2^Depth; tail holds all entries under the head.
  localparam int Entries = (1 << Depth) - 1;   // words in the tail shift register
  localparam int Bits = (Width * Entries) - 1;

  logic move = delta[0];
  logic dir  = delta[1];  // 0=push (grow), 1=pop (shrink)

  logic [Width-1:0] head;
  logic [Bits:0]    tail;
  logic [Width-1:0] headN;
  logic [Bits:0]    tailN;

  // Zero-initialize for simulation (synthesis: FFs power up at 0)
  initial begin
    head = '0;
    tail = '0;
  end

  assign headN = we ? wd : tail[Width-1:0];
  assign tailN = dir ? {{Width{1'b0}}, tail[Bits:Width]} : {tail[Bits-Width:0], head};

  always_ff @(posedge clk) begin
    if (we | move)
      head <= headN;
    if (move)
      tail <= tailN;
  end

  assign rd = head;
endmodule
