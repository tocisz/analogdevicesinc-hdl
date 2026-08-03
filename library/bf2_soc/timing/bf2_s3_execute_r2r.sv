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
// Stage 3: ALU Execute
// ---------------------------------------------------------------------------
module bf2_s3_execute_r2r #(
  parameter int DataAddressWidth = `DADDR_WIDTH,
  parameter int CodeAddressWidth = `CADDR_WIDTH,
  parameter int DataWidth  = `DATA_WIDTH,
  parameter int Depth       = `DEPTH
)(
  input  logic                              clk,
  input  logic signed [DataAddressWidth-1:0]     alu_a,
  input  logic signed [CodeAddressWidth-1:0]     alu_b,
  input  logic [7:0]                        insn,
  input  logic                              do_jmp,
  input  logic                              do_ret,
  input  logic                              lj,
  input  logic [CodeAddressWidth-1:0]            pj_result,
  input  logic [CodeAddressWidth-1:0]            pc,
  input  logic [DataAddressWidth-1:0]            maddr,
  input  logic [DataWidth-1:0]             mem_din,
  input  logic [DataWidth-1:0]             io_din,
  input  logic [Depth-1:0]                  rsp,
  input  logic [CodeAddressWidth-1:0]            rst0,
  output logic [DataAddressWidth-1:0]            alu_c,
  output logic [CodeAddressWidth-1:0]            pc_next,
  output logic [Depth-1:0]                  rsp_next,
  output logic                              rstk_push,
  output logic                              rstk_pop,
  output logic [CodeAddressWidth-1:0]            rstk_data,
  output logic [DataAddressWidth-1:0]            maddr_next,
  output logic [DataWidth-1:0]             mem_dout
);
  logic signed [DataAddressWidth-1:0] alu_a_r;
  logic signed [CodeAddressWidth-1:0] alu_b_r;
  logic [7:0]                    insn_r;
  logic                          do_jmp_r, do_ret_r, lj_r;
  logic [CodeAddressWidth-1:0]        pj_result_r;
  logic [CodeAddressWidth-1:0]        pc_r;
  logic [DataAddressWidth-1:0]        maddr_r;
  logic [DataWidth-1:0]         mem_din_r, io_din_r;
  logic [Depth-1:0]              rsp_r;
  logic [CodeAddressWidth-1:0]        rst0_r;

  logic [DataAddressWidth-1:0] alu_c_c, alu_c_r;
  logic [CodeAddressWidth-1:0] pc_next_c, pc_next_r;
  logic [Depth-1:0]       rsp_next_c, rsp_next_r;
  logic                   rstk_push_c, rstk_push_r;
  logic                   rstk_pop_c, rstk_pop_r;
  logic [CodeAddressWidth-1:0] rstk_data_c, rstk_data_r;
  logic [DataAddressWidth-1:0] maddr_next_c, maddr_next_r;
  logic [DataWidth-1:0]  mem_dout_c, mem_dout_r;

  always_ff @(posedge clk) begin
    alu_a_r    <= alu_a;
    alu_b_r    <= alu_b;
    insn_r     <= insn;
    do_jmp_r   <= do_jmp;
    do_ret_r   <= do_ret;
    lj_r       <= lj;
    pj_result_r<= pj_result;
    pc_r       <= pc;
    maddr_r    <= maddr;
    mem_din_r  <= mem_din;
    io_din_r   <= io_din;
    rsp_r      <= rsp;
    rst0_r     <= rst0;
  end

  bf2_s3_execute_comb #(
    .DataAddressWidth(DataAddressWidth),
    .CodeAddressWidth(CodeAddressWidth),
    .DataWidth (DataWidth),
    .Depth      (Depth)
  ) u_comb (
    .alu_a      (alu_a_r),
    .alu_b      (alu_b_r),
    .insn       (insn_r),
    .do_jmp     (do_jmp_r),
    .do_ret     (do_ret_r),
    .lj         (lj_r),
    .pj_result  (pj_result_r),
    .pc         (pc_r),
    .maddr      (maddr_r),
    .mem_din    (mem_din_r),
    .io_din     (io_din_r),
    .rsp        (rsp_r),
    .rst0       (rst0_r),
    .alu_c      (alu_c_c),
    .pc_next    (pc_next_c),
    .rsp_next   (rsp_next_c),
    .rstk_push  (rstk_push_c),
    .rstk_pop   (rstk_pop_c),
    .rstk_data  (rstk_data_c),
    .maddr_next (maddr_next_c),
    .mem_dout   (mem_dout_c)
  );

  always_ff @(posedge clk) begin
    alu_c_r     <= alu_c_c;
    pc_next_r   <= pc_next_c;
    rsp_next_r  <= rsp_next_c;
    rstk_push_r <= rstk_push_c;
    rstk_pop_r  <= rstk_pop_c;
    rstk_data_r <= rstk_data_c;
    maddr_next_r<= maddr_next_c;
    mem_dout_r  <= mem_dout_c;
  end

  assign alu_c      = alu_c_r;
  assign pc_next    = pc_next_r;
  assign rsp_next   = rsp_next_r;
  assign rstk_push  = rstk_push_r;
  assign rstk_pop   = rstk_pop_r;
  assign rstk_data  = rstk_data_r;
  assign maddr_next = maddr_next_r;
  assign mem_dout   = mem_dout_r;
endmodule
