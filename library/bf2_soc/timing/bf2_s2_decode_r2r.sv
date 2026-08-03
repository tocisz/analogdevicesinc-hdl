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
// Stage 2: Decode / ALU Operand Setup
// ---------------------------------------------------------------------------
module bf2_s2_decode_r2r #(
  parameter int DataAddressWidth = `DADDR_WIDTH,
  parameter int CodeAddressWidth = `CADDR_WIDTH,
  parameter int DataWidth  = `DATA_WIDTH
)(
  input  logic                              clk,
  input  logic [7:0]                        insn,
  input  logic [DataAddressWidth-1:0]            maddr,
  input  logic [DataWidth-1:0]             mem_din,
  input  logic                              lj,
  input  logic [4:0]                        lj_offset,
  input  logic [CodeAddressWidth-1:0]            pc,
  output logic signed [DataAddressWidth-1:0]     alu_a,
  output logic signed [CodeAddressWidth-1:0]     alu_b,
  output logic                              lj_out,
  output logic [4:0]                        lj_offset_out,
  output logic                              mem_wr,
  output logic                              io_wr,
  output logic                              io_rd,
  output logic                              do_jmp,
  output logic                              do_ret
);
  logic [7:0]                   insn_r;
  logic [DataAddressWidth-1:0]       maddr_r;
  logic [DataWidth-1:0]        mem_din_r;
  logic                         lj_r;
  logic [4:0]                   lj_offset_r;
  logic [CodeAddressWidth-1:0]       pc_r;

  logic signed [DataAddressWidth-1:0] alu_a_c, alu_a_r;
  logic signed [CodeAddressWidth-1:0] alu_b_c, alu_b_r;
  logic                          lj_out_c, lj_out_r;
  logic [4:0]                    lj_offset_out_c, lj_offset_out_r;
  logic                          mem_wr_c, mem_wr_r;
  logic                          io_wr_c, io_wr_r;
  logic                          io_rd_c, io_rd_r;
  logic                          do_jmp_c, do_jmp_r;
  logic                          do_ret_c, do_ret_r;

  always_ff @(posedge clk) begin
    insn_r      <= insn;
    maddr_r     <= maddr;
    mem_din_r   <= mem_din;
    lj_r        <= lj;
    lj_offset_r <= lj_offset;
    pc_r        <= pc;
  end

  bf2_s2_decode_comb #(
    .DataAddressWidth(DataAddressWidth),
    .CodeAddressWidth(CodeAddressWidth),
    .DataWidth (DataWidth)
  ) u_comb (
    .insn          (insn_r),
    .maddr         (maddr_r),
    .mem_din       (mem_din_r),
    .lj            (lj_r),
    .lj_offset     (lj_offset_r),
    .pc            (pc_r),
    .alu_a         (alu_a_c),
    .alu_b         (alu_b_c),
    .lj_out        (lj_out_c),
    .lj_offset_out (lj_offset_out_c),
    .mem_wr        (mem_wr_c),
    .io_wr         (io_wr_c),
    .io_rd         (io_rd_c),
    .do_jmp        (do_jmp_c),
    .do_ret        (do_ret_c)
  );

  always_ff @(posedge clk) begin
    alu_a_r         <= alu_a_c;
    alu_b_r         <= alu_b_c;
    lj_out_r        <= lj_out_c;
    lj_offset_out_r <= lj_offset_out_c;
    mem_wr_r        <= mem_wr_c;
    io_wr_r         <= io_wr_c;
    io_rd_r         <= io_rd_c;
    do_jmp_r        <= do_jmp_c;
    do_ret_r        <= do_ret_c;
  end

  assign alu_a         = alu_a_r;
  assign alu_b         = alu_b_r;
  assign lj_out        = lj_out_r;
  assign lj_offset_out = lj_offset_out_r;
  assign mem_wr        = mem_wr_r;
  assign io_wr         = io_wr_r;
  assign io_rd         = io_rd_r;
  assign do_jmp        = do_jmp_r;
  assign do_ret        = do_ret_r;
endmodule
