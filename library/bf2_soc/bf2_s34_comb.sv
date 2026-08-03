`include "common.h"

// ============================================================================
// BF2-PHASE: EX cloud — execute + writeback (S3+S4)
// ============================================================================
// Combinational only.  Inputs are the FD/EX registers plus committed
// architectural state.  Outputs commit when EX advances.  pc_next / push /
// pop are NOT recomputed here — they were resolved in FD and ride in EX.
// ============================================================================
module bf2_s34_comb #(
    parameter int DataAddressWidth = `DADDR_WIDTH,
    parameter int CodeAddressWidth = `CADDR_WIDTH,
    parameter int DataWidth        = `DATA_WIDTH,
    parameter int Depth            = `DEPTH
) (
    input logic signed [DataAddressWidth-1:0] alu_a,    // FD/EX operands
    input logic signed [CodeAddressWidth-1:0] alu_b,
    input logic        [                 2:0] insn_op,  // FD/EX opcode = insn[7:5]
    input logic                               lj,       // FD/EX: lj flag of this insn
    input logic        [DataAddressWidth-1:0] maddr,    // committed tape pointer
    input logic        [       DataWidth-1:0] io_din,   // ',' write data (async)
    input logic        [           Depth-1:0] rsp,      // committed stack depth
    input logic                               push,     // from FD (enter loop)
    input logic                               pop,      // from FD (leave loop)

    output logic [DataAddressWidth-1:0] maddr_next,
    output logic [       DataWidth-1:0] mem_dout,
    output logic [           Depth-1:0] rsp_next
);

  // ALU result (summed only internally: maddr_next / mem_dout).
  logic [DataAddressWidth-1:0] alu_c;

  // ---- ALU (identical formula to BF1: a + signext(b))
  always_comb begin
    alu_c = alu_a + ($signed({alu_b, 2'b0}) >>> 2);
  end

  // ---- Post-ALU datapath: the two alu_c consumers
  always_comb begin
    maddr_next = maddr;
    mem_dout   = io_din;  // default; ',' writes IO data to memory
    casez ({
      lj, insn_op[2:0]
    })
      4'b0_00?: maddr_next = alu_c;  // < or >
      4'b0_01?: mem_dout = alu_c[7:0];  // - or +
      default:  ;  // [ ] , . prefix : defaults
    endcase
  end

  // ---- Return-stack depth
  always_comb begin
    rsp_next = rsp + {{(Depth - 1) {1'b0}}, push} - {{(Depth - 1) {1'b0}}, pop};
  end
endmodule
