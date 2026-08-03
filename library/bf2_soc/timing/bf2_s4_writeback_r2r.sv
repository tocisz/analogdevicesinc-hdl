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
// Stage 4: Memory / Writeback
// ---------------------------------------------------------------------------
module bf2_s4_writeback_r2r #(
  parameter int DataAddressWidth = `DADDR_WIDTH,
  parameter int CodeAddressWidth = `CADDR_WIDTH,
  parameter int DataWidth  = `DATA_WIDTH,
  parameter int Depth       = `DEPTH
)(
  input  logic                              clk,
  input  logic [DataAddressWidth-1:0]            alu_c,
  input  logic [CodeAddressWidth-1:0]            pc_next,
  input  logic [Depth-1:0]                  rsp_next,
  input  logic                              rstk_write,
  input  logic [CodeAddressWidth-1:0]            rstk_data,
  input  logic [DataAddressWidth-1:0]            maddr_next,
  input  logic                              mem_wr,
  input  logic                              io_wr,
  input  logic                              io_rd,
  input  logic [DataWidth-1:0]             mem_dout,
  input  logic                              lj,
  input  logic [4:0]                        lj_offset,
  input  logic                              pj_carry5,
  input  logic [7:0]                        pj_pc_high,
  output logic [DataAddressWidth-1:0]            mem_addr,
  output logic                              mem_wr_out,
  output logic [DataWidth-1:0]             mem_dout_out,
  output logic                              io_wr_out,
  output logic                              io_rd_out,
  output logic [CodeAddressWidth-1:0]            pc_out,
  output logic [Depth-1:0]                  rsp_out,
  output logic [DataAddressWidth-1:0]            maddr_out,
  output logic                              lj_out,
  output logic [4:0]                        lj_offset_out,
  output logic                              pj_carry5_out,
  output logic [7:0]                        pj_pc_high_out
);
  logic [DataAddressWidth-1:0] alu_c_r;
  logic [CodeAddressWidth-1:0] pc_next_r;
  logic [Depth-1:0]       rsp_next_r;
  logic                   rstk_write_r;
  logic [CodeAddressWidth-1:0] rstk_data_r;
  logic [DataAddressWidth-1:0] maddr_next_r;
  logic                   mem_wr_r, io_wr_r, io_rd_r;
  logic [DataWidth-1:0]  mem_dout_r;
  logic                   lj_r;
  logic [4:0]             lj_offset_r;
  logic                   pj_carry5_r;
  logic [7:0]             pj_pc_high_r;

  logic [DataAddressWidth-1:0] mem_addr_c, mem_addr_r;
  logic                   mem_wr_out_c, mem_wr_out_r;
  logic [DataWidth-1:0]  mem_dout_out_c, mem_dout_out_r;
  logic                   io_wr_out_c, io_wr_out_r;
  logic                   io_rd_out_c, io_rd_out_r;
  logic [CodeAddressWidth-1:0] pc_out_c, pc_out_r;
  logic [Depth-1:0]       rsp_out_c, rsp_out_r;
  logic [DataAddressWidth-1:0] maddr_out_c, maddr_out_r;
  logic                   lj_out_c, lj_out_r;
  logic [4:0]             lj_offset_out_c, lj_offset_out_r;
  logic                   pj_carry5_out_c, pj_carry5_out_r;
  logic [7:0]             pj_pc_high_out_c, pj_pc_high_out_r;

  always_ff @(posedge clk) begin
    alu_c_r     <= alu_c;
    pc_next_r   <= pc_next;
    rsp_next_r  <= rsp_next;
    rstk_write_r<= rstk_write;
    rstk_data_r <= rstk_data;
    maddr_next_r<= maddr_next;
    mem_wr_r    <= mem_wr;
    io_wr_r     <= io_wr;
    io_rd_r     <= io_rd;
    mem_dout_r  <= mem_dout;
    lj_r        <= lj;
    lj_offset_r <= lj_offset;
    pj_carry5_r <= pj_carry5;
    pj_pc_high_r<= pj_pc_high;
  end

  bf2_s4_writeback_comb #(
    .DataAddressWidth(DataAddressWidth),
    .CodeAddressWidth(CodeAddressWidth),
    .DataWidth (DataWidth),
    .Depth      (Depth)
  ) u_comb (
    .alu_c         (alu_c_r),
    .pc_next       (pc_next_r),
    .rsp_next      (rsp_next_r),
    .rstk_write    (rstk_write_r),
    .rstk_data     (rstk_data_r),
    .maddr_next    (maddr_next_r),
    .mem_wr        (mem_wr_r),
    .io_wr         (io_wr_r),
    .io_rd         (io_rd_r),
    .mem_dout      (mem_dout_r),
    .lj            (lj_r),
    .lj_offset     (lj_offset_r),
    .pj_carry5     (pj_carry5_r),
    .pj_pc_high    (pj_pc_high_r),
    .mem_addr      (mem_addr_c),
    .mem_wr_out    (mem_wr_out_c),
    .mem_dout_out  (mem_dout_out_c),
    .io_wr_out     (io_wr_out_c),
    .io_rd_out     (io_rd_out_c),
    .pc_out        (pc_out_c),
    .rsp_out       (rsp_out_c),
    .maddr_out     (maddr_out_c),
    .lj_out        (lj_out_c),
    .lj_offset_out (lj_offset_out_c),
    .pj_carry5_out (pj_carry5_out_c),
    .pj_pc_high_out(pj_pc_high_out_c)
  );

  always_ff @(posedge clk) begin
    mem_addr_r     <= mem_addr_c;
    mem_wr_out_r   <= mem_wr_out_c;
    mem_dout_out_r <= mem_dout_out_c;
    io_wr_out_r    <= io_wr_out_c;
    io_rd_out_r    <= io_rd_out_c;
    pc_out_r       <= pc_out_c;
    rsp_out_r      <= rsp_out_c;
    maddr_out_r    <= maddr_out_c;
    lj_out_r       <= lj_out_c;
    lj_offset_out_r<= lj_offset_out_c;
    pj_carry5_out_r<= pj_carry5_out_c;
    pj_pc_high_out_r<= pj_pc_high_out_c;
  end

  assign mem_addr      = mem_addr_r;
  assign mem_wr_out    = mem_wr_out_r;
  assign mem_dout_out  = mem_dout_out_r;
  assign io_wr_out     = io_wr_out_r;
  assign io_rd_out     = io_rd_out_r;
  assign pc_out        = pc_out_r;
  assign rsp_out       = rsp_out_r;
  assign maddr_out     = maddr_out_r;
  assign lj_out        = lj_out_r;
  assign lj_offset_out = lj_offset_out_r;
  assign pj_carry5_out = pj_carry5_out_r;
  assign pj_pc_high_out= pj_pc_high_out_r;
endmodule
