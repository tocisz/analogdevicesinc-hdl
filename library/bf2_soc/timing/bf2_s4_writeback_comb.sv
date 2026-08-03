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
// Stage 4: Memory / Writeback (combinational only)
// ---------------------------------------------------------------------------
module bf2_s4_writeback_comb #(
  parameter int DataAddressWidth = `DADDR_WIDTH,
  parameter int CodeAddressWidth = `CADDR_WIDTH,
  parameter int DataWidth  = `DATA_WIDTH,
  parameter int Depth       = `DEPTH
)(
  input  logic [DataAddressWidth-1:0]  alu_c,
  input  logic [CodeAddressWidth-1:0]  pc_next,
  input  logic [Depth-1:0]        rsp_next,
  input  logic                    rstk_write,
  input  logic [CodeAddressWidth-1:0]  rstk_data,
  input  logic [DataAddressWidth-1:0]  maddr_next,
  input  logic                    mem_wr,
  input  logic                    io_wr,
  input  logic                    io_rd,
  input  logic [DataWidth-1:0]   mem_dout,
  input  logic                    lj,
  input  logic [4:0]              lj_offset,
  input  logic                    pj_carry5,
  input  logic [7:0]              pj_pc_high,

  output logic [DataAddressWidth-1:0]  mem_addr,
  output logic                    mem_wr_out,
  output logic [DataWidth-1:0]   mem_dout_out,
  output logic                    io_wr_out,
  output logic                    io_rd_out,
  output logic [CodeAddressWidth-1:0]  pc_out,
  output logic [Depth-1:0]        rsp_out,
  output logic [DataAddressWidth-1:0]  maddr_out,
  output logic                    lj_out,
  output logic [4:0]              lj_offset_out,
  output logic                    pj_carry5_out,
  output logic [7:0]              pj_pc_high_out
);

  // Just pass through (combinational)
  assign mem_addr       = maddr_next;
  assign mem_wr_out     = mem_wr;
  assign mem_dout_out   = mem_dout;
  assign io_wr_out      = io_wr;
  assign io_rd_out      = io_rd;
  assign pc_out         = pc_next;
  assign rsp_out        = rsp_next;
  assign maddr_out      = maddr_next;
  assign lj_out         = lj;
  assign lj_offset_out  = lj_offset;
  assign pj_carry5_out  = pj_carry5;
  assign pj_pc_high_out = pj_pc_high;
endmodule
