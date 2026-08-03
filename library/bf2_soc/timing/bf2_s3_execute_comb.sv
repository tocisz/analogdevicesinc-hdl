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
// Stage 3: ALU Execute (combinational only)
// ---------------------------------------------------------------------------
// Corrected pipeline partition:
//   S3 does the ALU and then ALL signals that consume alu_c:
//     - mem_dout   = alu_c[7:0]  for '- +'
//     - maddr_next = alu_c       for '< >'
//     - pc_next    = alu_c[12:0] when skipping a loop
//   plus the PC/RSP/return-stack updates (which need mem_din + rst0).
//   rstk_push/rstk_pop are decoded here for the stack2 (push/pop) interface.
// ---------------------------------------------------------------------------
module bf2_s3_execute_comb #(
  parameter int DataAddressWidth = `DADDR_WIDTH,
  parameter int CodeAddressWidth = `CADDR_WIDTH,
  parameter int DataWidth  = `DATA_WIDTH,
  parameter int Depth       = `DEPTH
)(
  input  logic signed [DataAddressWidth-1:0] alu_a,
  input  logic signed [CodeAddressWidth-1:0] alu_b,
  input  logic [7:0]                    insn,
  input  logic                          do_jmp,
  input  logic                          do_ret,
  input  logic                          lj,
  input  logic [CodeAddressWidth-1:0]        pj_result,
  input  logic [CodeAddressWidth-1:0]        pc,
  input  logic [DataAddressWidth-1:0]        maddr,
  input  logic [DataWidth-1:0]         mem_din,
  input  logic [DataWidth-1:0]         io_din,
  input  logic [Depth-1:0]              rsp,
  input  logic [CodeAddressWidth-1:0]        rst0,

  output logic [DataAddressWidth-1:0]        alu_c,
  output logic [CodeAddressWidth-1:0]        pc_next,
  output logic [Depth-1:0]              rsp_next,
  output logic                          rstk_push,
  output logic                          rstk_pop,
  output logic [CodeAddressWidth-1:0]        rstk_data,
  output logic [DataAddressWidth-1:0]        maddr_next,
  output logic [DataWidth-1:0]         mem_dout
);

  // ALU computation
  always_comb begin
    alu_c = alu_a + ($signed({alu_b, 2'b0}) >>> 2);
  end

  // --- Post-ALU datapath: signals that consume alu_c ---
  always_comb begin
    maddr_next = maddr;
    mem_dout   = io_din; // default; ',' writes IO data to memory
    casez ({lj, insn[7:5]})
      4'b0_00?: maddr_next = alu_c;          // < or >
      4'b0_01?: mem_dout   = alu_c[7:0];     // - or +
      default:  ;                            // [ ] , . : defaults
    endcase
  end

  // --- PC / RSP / return-stack logic ---
  always_comb begin
    pc_next     = pc + 1'b1;
    rsp_next    = rsp;
    rstk_push   = 1'b0;
    rstk_pop    = 1'b0;
    rstk_data   = pc_next;

    if (do_jmp || lj) begin
      if (mem_din != 0) begin
        rsp_next    = rsp + 1'b1;
        rstk_push   = 1'b1;
      end else begin
        pc_next = lj ? pj_result : alu_c[CodeAddressWidth-1:0];
      end
    end else if (do_ret) begin
      if (mem_din != 0) pc_next = rst0;
      else begin
        rsp_next = rsp - 1'b1;
        rstk_pop = 1'b1;
      end
    end
  end
endmodule
