`include "common.h"
`default_nettype wire

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

/* verilator lint_off DECLFILENAME */
/* verilator lint_off MULTITOP */
/* verilator lint_off UNUSEDSIGNAL */
/* verilator lint_off MULTIDRIVEN */
/* verilator lint_off WIDTHEXPAND */

// ---------------------------------------------------------------------------
// Stage 1: Fetch
// ---------------------------------------------------------------------------
module bf2_s1_fetch_r2r #(
  parameter CADDR_WIDTH = 13
)(
  input  logic                         clk,
  input  logic [CADDR_WIDTH-1:0]       pc,
  output logic [CADDR_WIDTH-1:0]       code_addr,
  output logic [CADDR_WIDTH-1:0]       pc_next
);
  logic [CADDR_WIDTH-1:0] pc_r;
  logic [CADDR_WIDTH-1:0] code_addr_c, pc_next_c;

  always_ff @(posedge clk) pc_r <= pc;

  bf2_s1_fetch_comb #(.CADDR_WIDTH(CADDR_WIDTH)) u_comb (
    .pc       (pc_r),
    .code_addr(code_addr_c),
    .pc_next  (pc_next_c)
  );

  always_ff @(posedge clk) begin
    code_addr_r <= code_addr_c;
    pc_next_r   <= pc_next_c;
  end

  logic [CADDR_WIDTH-1:0] code_addr_r, pc_next_r;
  assign code_addr = code_addr_r;
  assign pc_next   = pc_next_r;
endmodule


// ---------------------------------------------------------------------------
// Stage 2: Decode / ALU Operand Setup
// ---------------------------------------------------------------------------
module bf2_s2_decode_r2r #(
  parameter DADDR_WIDTH = 15,
  parameter CADDR_WIDTH = 13,
  parameter DATA_WIDTH  = 8
)(
  input  logic                              clk,
  input  logic [7:0]                        insn,
  input  logic [DADDR_WIDTH-1:0]            maddr,
  input  logic [DATA_WIDTH-1:0]             mem_din,
  input  logic                              lj,
  input  logic [4:0]                        lj_offset,
  input  logic [CADDR_WIDTH-1:0]            pc,
  output logic signed [DADDR_WIDTH-1:0]     alu_a,
  output logic signed [CADDR_WIDTH-1:0]     alu_b,
  output logic                              lj_out,
  output logic [4:0]                        lj_offset_out,
  output logic                              mem_wr,
  output logic                              io_wr,
  output logic                              io_rd,
  output logic                              do_jmp,
  output logic                              do_ret
);
  logic [7:0]                   insn_r;
  logic [DADDR_WIDTH-1:0]       maddr_r;
  logic [DATA_WIDTH-1:0]        mem_din_r;
  logic                         lj_r;
  logic [4:0]                   lj_offset_r;
  logic [CADDR_WIDTH-1:0]       pc_r;

  logic signed [DADDR_WIDTH-1:0] alu_a_c, alu_a_r;
  logic signed [CADDR_WIDTH-1:0] alu_b_c, alu_b_r;
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
    .DADDR_WIDTH(DADDR_WIDTH),
    .CADDR_WIDTH(CADDR_WIDTH),
    .DATA_WIDTH (DATA_WIDTH)
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


// ---------------------------------------------------------------------------
// Stage 3: ALU Execute
// ---------------------------------------------------------------------------
module bf2_s3_execute_r2r #(
  parameter DADDR_WIDTH = 15,
  parameter CADDR_WIDTH = 13,
  parameter DATA_WIDTH  = 8,
  parameter DEPTH       = 4
)(
  input  logic                              clk,
  input  logic signed [DADDR_WIDTH-1:0]     alu_a,
  input  logic signed [CADDR_WIDTH-1:0]     alu_b,
  input  logic [7:0]                        insn,
  input  logic                              do_jmp,
  input  logic                              do_ret,
  input  logic                              lj,
  input  logic [CADDR_WIDTH-1:0]            pj_result,
  input  logic [CADDR_WIDTH-1:0]            pc,
  input  logic [DADDR_WIDTH-1:0]            maddr,
  input  logic [DATA_WIDTH-1:0]             mem_din,
  input  logic [DATA_WIDTH-1:0]             io_din,
  input  logic [DEPTH-1:0]                  rsp,
  input  logic [CADDR_WIDTH-1:0]            rst0,
  output logic [DADDR_WIDTH-1:0]            alu_c,
  output logic [CADDR_WIDTH-1:0]            pc_next,
  output logic [DEPTH-1:0]                  rsp_next,
  output logic                              rstk_push,
  output logic                              rstk_pop,
  output logic [CADDR_WIDTH-1:0]            rstk_data,
  output logic [DADDR_WIDTH-1:0]            maddr_next,
  output logic [DATA_WIDTH-1:0]             mem_dout
);
  logic signed [DADDR_WIDTH-1:0] alu_a_r;
  logic signed [CADDR_WIDTH-1:0] alu_b_r;
  logic [7:0]                    insn_r;
  logic                          do_jmp_r, do_ret_r, lj_r;
  logic [CADDR_WIDTH-1:0]        pj_result_r;
  logic [CADDR_WIDTH-1:0]        pc_r;
  logic [DADDR_WIDTH-1:0]        maddr_r;
  logic [DATA_WIDTH-1:0]         mem_din_r, io_din_r;
  logic [DEPTH-1:0]              rsp_r;
  logic [CADDR_WIDTH-1:0]        rst0_r;

  logic [DADDR_WIDTH-1:0] alu_c_c, alu_c_r;
  logic [CADDR_WIDTH-1:0] pc_next_c, pc_next_r;
  logic [DEPTH-1:0]       rsp_next_c, rsp_next_r;
  logic                   rstk_push_c, rstk_push_r;
  logic                   rstk_pop_c, rstk_pop_r;
  logic [CADDR_WIDTH-1:0] rstk_data_c, rstk_data_r;
  logic [DADDR_WIDTH-1:0] maddr_next_c, maddr_next_r;
  logic [DATA_WIDTH-1:0]  mem_dout_c, mem_dout_r;

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
    .DADDR_WIDTH(DADDR_WIDTH),
    .CADDR_WIDTH(CADDR_WIDTH),
    .DATA_WIDTH (DATA_WIDTH),
    .DEPTH      (DEPTH)
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


// ---------------------------------------------------------------------------
// Stage 4: Memory / Writeback
// ---------------------------------------------------------------------------
module bf2_s4_writeback_r2r #(
  parameter DADDR_WIDTH = 15,
  parameter CADDR_WIDTH = 13,
  parameter DATA_WIDTH  = 8,
  parameter DEPTH       = 4
)(
  input  logic                              clk,
  input  logic [DADDR_WIDTH-1:0]            alu_c,
  input  logic [CADDR_WIDTH-1:0]            pc_next,
  input  logic [DEPTH-1:0]                  rsp_next,
  input  logic                              rstk_write,
  input  logic [CADDR_WIDTH-1:0]            rstk_data,
  input  logic [DADDR_WIDTH-1:0]            maddr_next,
  input  logic                              mem_wr,
  input  logic                              io_wr,
  input  logic                              io_rd,
  input  logic [DATA_WIDTH-1:0]             mem_dout,
  input  logic                              lj,
  input  logic [4:0]                        lj_offset,
  input  logic                              pj_carry5,
  input  logic [7:0]                        pj_pc_high,
  output logic [DADDR_WIDTH-1:0]            mem_addr,
  output logic                              mem_wr_out,
  output logic [DATA_WIDTH-1:0]             mem_dout_out,
  output logic                              io_wr_out,
  output logic                              io_rd_out,
  output logic [CADDR_WIDTH-1:0]            pc_out,
  output logic [DEPTH-1:0]                  rsp_out,
  output logic [DADDR_WIDTH-1:0]            maddr_out,
  output logic                              lj_out,
  output logic [4:0]                        lj_offset_out,
  output logic                              pj_carry5_out,
  output logic [7:0]                        pj_pc_high_out
);
  logic [DADDR_WIDTH-1:0] alu_c_r;
  logic [CADDR_WIDTH-1:0] pc_next_r;
  logic [DEPTH-1:0]       rsp_next_r;
  logic                   rstk_write_r;
  logic [CADDR_WIDTH-1:0] rstk_data_r;
  logic [DADDR_WIDTH-1:0] maddr_next_r;
  logic                   mem_wr_r, io_wr_r, io_rd_r;
  logic [DATA_WIDTH-1:0]  mem_dout_r;
  logic                   lj_r;
  logic [4:0]             lj_offset_r;
  logic                   pj_carry5_r;
  logic [7:0]             pj_pc_high_r;

  logic [DADDR_WIDTH-1:0] mem_addr_c, mem_addr_r;
  logic                   mem_wr_out_c, mem_wr_out_r;
  logic [DATA_WIDTH-1:0]  mem_dout_out_c, mem_dout_out_r;
  logic                   io_wr_out_c, io_wr_out_r;
  logic                   io_rd_out_c, io_rd_out_r;
  logic [CADDR_WIDTH-1:0] pc_out_c, pc_out_r;
  logic [DEPTH-1:0]       rsp_out_c, rsp_out_r;
  logic [DADDR_WIDTH-1:0] maddr_out_c, maddr_out_r;
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
    .DADDR_WIDTH(DADDR_WIDTH),
    .CADDR_WIDTH(CADDR_WIDTH),
    .DATA_WIDTH (DATA_WIDTH),
    .DEPTH      (DEPTH)
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


// ---------------------------------------------------------------------------
// Long Jump Target Computation (2-cycle helper, faithful to bf2_pipeline.sv)
// ---------------------------------------------------------------------------
// NOT an alternative S3: this is the separate 2-cycle jump-target state
// machine that feeds the pc_next mux in S3 (pc_next = lj ? pj_result : alu_c).
//   prefix cycle: pj_low_sum = pc_r[4:0] + insn[4:0]; capture pj_carry5,
//                 pj_pc_high = pc_r[12:5]            (REGISTERED between cycles)
//   jump cycle:   pj_result  = {pj_pc_high_r + insn + {7'b0, pj_carry5_r},
//                                pj_low_sum[4:0]}    (parallel adds from regs)
// The two additions are NOT chained in the pipeline -- the carry is registered
// -- so the measured path is max(5-bit add, 8-bit add) + output register.
// ---------------------------------------------------------------------------
module bf2_longjump_r2r #(
  parameter CADDR_WIDTH = 13
)(
  input  logic                       clk,
  input  logic [7:0]                 insn,          // jump instruction ([ or ])
  input  logic [CADDR_WIDTH-1:0]     pc,            // architectural PC
  input  logic                       pj_carry5,     // prefix-cycle carry (saved)
  input  logic [7:0]                 pj_pc_high,    // prefix-cycle pc[12:5] (saved)
  output logic [CADDR_WIDTH-1:0]     jump_target
);
  logic [7:0]             insn_r;
  logic [CADDR_WIDTH-1:0] pc_r;
  logic                   pj_carry5_r;
  logic [7:0]             pj_pc_high_r;
  logic [CADDR_WIDTH-1:0] jump_target_c, jump_target_r;
  logic [5:0]             pj_low_sum_c;

  always_ff @(posedge clk) begin
    insn_r      <= insn;
    pc_r        <= pc;
    pj_carry5_r <= pj_carry5;
    pj_pc_high_r<= pj_pc_high;
  end

  // Same combinational cloud as bf2_pipeline.sv (parallel, not chained):
  assign pj_low_sum_c  = pc_r[4:0] + insn_r[4:0];
  assign jump_target_c = {pj_pc_high_r + insn_r + {7'b0, pj_carry5_r},
                          pj_low_sum_c[4:0]};

  always_ff @(posedge clk) jump_target_r <= jump_target_c;
  assign jump_target = jump_target_r;
endmodule


// ---------------------------------------------------------------------------
// ALU (standalone)
// ---------------------------------------------------------------------------
module bf2_alu_r2r #(
  parameter DADDR_WIDTH = 15,
  parameter CADDR_WIDTH = 13
)(
  input  logic                              clk,
  input  logic signed [DADDR_WIDTH-1:0]     alu_a,
  input  logic signed [CADDR_WIDTH-1:0]     alu_b,
  output logic [DADDR_WIDTH-1:0]            alu_c
);
  logic signed [DADDR_WIDTH-1:0] alu_a_r;
  logic signed [CADDR_WIDTH-1:0] alu_b_r;
  logic [DADDR_WIDTH-1:0]        alu_c_c, alu_c_r;

  always_ff @(posedge clk) begin
    alu_a_r <= alu_a;
    alu_b_r <= alu_b;
  end

  bf2_alu_comb #(.DADDR_WIDTH(DADDR_WIDTH), .CADDR_WIDTH(CADDR_WIDTH)) u_comb (
    .alu_a(alu_a_r),
    .alu_b(alu_b_r),
    .alu_c(alu_c_c)
  );

  always_ff @(posedge clk) alu_c_r <= alu_c_c;
  assign alu_c = alu_c_r;
endmodule


// ---------------------------------------------------------------------------
// Stack2 (LIFO push/pop/top shift-register stack)
// ---------------------------------------------------------------------------
module bf2_stack2_r2r #(
  parameter DEPTH = 16,
  parameter WIDTH = 13
)(
  input  logic                        clk,
  input  logic                        we,
  input  logic [1:0]                  delta,
  input  logic [WIDTH-1:0]            wd,
  input  logic [WIDTH-1:0]            head,
  input  logic [((WIDTH*DEPTH)-1):0]  tail,
  output logic [WIDTH-1:0]            rd,
  output logic [WIDTH-1:0]            headN,
  output logic [((WIDTH*DEPTH)-1):0]  tailN
);
  logic                   we_r;
  logic [1:0]             delta_r;
  logic [WIDTH-1:0]       wd_r;
  logic [WIDTH-1:0]       head_r;
  logic [((WIDTH*DEPTH)-1):0] tail_r;
  logic [WIDTH-1:0]       rd_c, rd_r;
  logic [WIDTH-1:0]       headN_c, headN_r;
  logic [((WIDTH*DEPTH)-1):0] tailN_c, tailN_r;

  always_ff @(posedge clk) begin
    we_r    <= we;
    delta_r <= delta;
    wd_r    <= wd;
    head_r  <= head;
    tail_r  <= tail;
  end

  bf2_stack2_comb #(.DEPTH(DEPTH), .WIDTH(WIDTH)) u_comb (
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
