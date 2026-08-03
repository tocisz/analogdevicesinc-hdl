`include "common.h"

// ============================================================================
// BF2: 4-Stage Pipeline with BRAM + Stack2 (LIFO return stack)
// ============================================================================
// Corrected stage partition.  BF1's single-cycle design has two combinational
// blocks, "before ALU" and "after ALU", written side by side.  In a pipeline
// they must be split by their TRUE data dependencies on alu_c:
//
//   S1 Fetch : PC -> IMEM (BRAM, registered out) -> insn
//   S2 Decode: pre-ALU operand setup (alu_a/alu_b) + pure control decode
//              (mem_wr, io_wr, io_rd, do_jmp, do_ret, lj, lj_offset).
//              NOTHING that consumes alu_c lives here.
//   S3 Exec  : ALU -> alu_c, then the post-ALU datapath that consumes alu_c:
//                mem_dout   = alu_c[7:0]     for '- +'
//                maddr_next = alu_c          for '< >'
//                pc_next    = alu_c[12:0]    when skipping a loop
//              plus rsp update and return-stack push/pop decode
//   S4 Mem/WB: DMEM (BRAM) access at maddr_next, stack2 push/pop,
//              architectural register update
//
// Return stack: bf2_stack2 (head + tail shift register).  rd = head is a
// register output, so the read path contributes ZERO combinational delay
// (vs the distributed-RAM read mux in bf2_stack).  Push = {we=1, delta=01},
// pop = {we=0, delta=11}.  Stack writes happen in S4, so during S3 an
// instruction reads the top as it was BEFORE its own push/pop -- exactly what
// ']' needs (loop again -> top is the return address pushed by the matching '[').
//
// NOTE: this file is a TIMING MODEL (critical-path measurement), not yet a
// functionally verified CPU.  Hazards (load-use on mem_din, branch fetch
// redirect) and long-jump state-machine alignment are TODO for the
// functional pass against the BF1 golden model.
// ============================================================================

/* verilator lint_off MULTITOP */
/* verilator lint_off UNUSEDSIGNAL */
/* verilator lint_off MULTIDRIVEN */
/* verilator lint_off WIDTHEXPAND */

// ---------------------------------------------------------------------------
// Stage 1: Instruction Fetch WITH IMEM
// ---------------------------------------------------------------------------
// Measures: PC register -> IMEM addr -> IMEM read -> insn register
// ---------------------------------------------------------------------------
module bf2_s1_fetch_with_imem #(
  parameter int CodeAddressWidth = `CADDR_WIDTH
)(
  input  logic                    clk,
  input  logic                    resetq,
  input  logic                    cpu_active,
  output logic [CodeAddressWidth-1:0]  code_addr,
  output logic [7:0]              insn,
  output logic [CodeAddressWidth-1:0]  pc_next
);

  logic [CodeAddressWidth-1:0] pc_r;

  // IMEM
  bf2_bram_icode #(.CodeAddressWidth(CodeAddressWidth)) imem_inst (
    .clk(clk), .addr(code_addr), .dout(insn)
  );

  always_ff @(posedge clk or negedge resetq) begin
    if (!resetq) begin
      pc_r <= '0;
    end else if (cpu_active) begin
      pc_r <= pc_next;
    end
  end

  assign code_addr = pc_r;
  assign pc_next   = pc_r + 1'b1;
endmodule
