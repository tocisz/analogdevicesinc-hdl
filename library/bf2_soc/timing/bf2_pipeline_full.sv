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

// ============================================================================
// Full Pipeline (4-stage) with Memory for End-to-End Timing
// ============================================================================
module bf2_pipeline_full #(
  parameter int CodeAddressWidth = `CADDR_WIDTH,
  parameter int DataAddressWidth = `DADDR_WIDTH,
  parameter int DataWidth  = `DATA_WIDTH,
  parameter int Depth       = `DEPTH
)(
  input  logic                    clk,
  input  logic                    resetq,
  input  logic                    cpu_active,
  input  logic                    ctrl_reset_i,
  output logic [CodeAddressWidth-1:0]  pc_debug,
  output logic [DataAddressWidth-1:0]  mem_addr,
  output logic                    mem_wr,
  output logic [DataWidth-1:0]   mem_dout,
  output logic                    io_wr,
  output logic                    io_rd,
  input  logic [DataWidth-1:0]   io_din,
  output logic [DataWidth-1:0]   io_dout,
  output logic [Depth-1:0]        _rsp
);

  // ======================================================================
  // S1: Fetch (PC -> IMEM -> insn)
  // ======================================================================
  logic [CodeAddressWidth-1:0] s1_code_addr;
  logic [7:0]             s1_insn;

  bf2_s1_fetch_with_imem #(.CodeAddressWidth(CodeAddressWidth)) s1 (
    .clk(clk), .resetq(resetq), .cpu_active(cpu_active),
    .code_addr(s1_code_addr), .insn(s1_insn)
  );

  // ---- IF/ID: pair the fetched instruction with its own PC ----
  logic [CodeAddressWidth-1:0] id_pc;
  logic [7:0]             id_insn;
  always_ff @(posedge clk or negedge resetq) begin
    if (!resetq) begin
      id_pc   <= '0;
      id_insn <= '0;
    end else if (cpu_active) begin
      id_pc   <= s1_code_addr; // pc whose insn just emerged from IMEM
      id_insn <= s1_insn;
    end
  end

  // ======================================================================
  // S2: Decode (pre-ALU operand setup + pure control decode)
  // ======================================================================
  logic signed [DataAddressWidth-1:0] s2_alu_a;
  logic signed [CodeAddressWidth-1:0] s2_alu_b;
  logic                          s2_lj, s2_mem_wr, s2_io_wr, s2_io_rd;
  logic                          s2_do_jmp, s2_do_ret;
  logic [4:0]                    s2_lj_offset;

  bf2_s2_decode_comb #(.DataAddressWidth(DataAddressWidth), .CodeAddressWidth(CodeAddressWidth),
                        .DataWidth(DataWidth)) s2_comb (
    .insn(id_insn), .maddr(maddr_r), .mem_din(mem_din_r),
    .lj(lj_r), .lj_offset(lj_offset_r), .pc(id_pc),
    .alu_a(s2_alu_a), .alu_b(s2_alu_b),
    .lj_out(s2_lj), .lj_offset_out(s2_lj_offset),
    .mem_wr(s2_mem_wr), .io_wr(s2_io_wr), .io_rd(s2_io_rd),
    .do_jmp(s2_do_jmp), .do_ret(s2_do_ret)
  );

  // ---- ID/EX registers ----
  logic signed [DataAddressWidth-1:0] s2_alu_a_r;
  logic signed [CodeAddressWidth-1:0] s2_alu_b_r;
  logic                          s2_lj_r, s2_mem_wr_r, s2_io_wr_r, s2_io_rd_r;
  logic                          s2_do_jmp_r, s2_do_ret_r;
  logic [4:0]                    s2_lj_offset_r;
  logic [CodeAddressWidth-1:0]        s2_pc_r;     // this instruction's pc
  logic [7:0]                    s2_insn_r;   // for S3 post-ALU decode
  logic [DataWidth-1:0]         s2_io_din_r; // ',' writes IO data to DMEM

  always_ff @(posedge clk or negedge resetq) begin
    if (!resetq) begin
      s2_alu_a_r     <= '0;
      s2_alu_b_r     <= '0;
      s2_lj_r        <= 1'b0;
      s2_lj_offset_r <= '0;
      s2_mem_wr_r    <= 1'b0;
      s2_io_wr_r     <= 1'b0;
      s2_io_rd_r     <= 1'b0;
      s2_do_jmp_r    <= 1'b0;
      s2_do_ret_r    <= 1'b0;
      s2_pc_r        <= '0;
      s2_insn_r      <= '0;
      s2_io_din_r    <= '0;
    end else if (cpu_active) begin
      s2_alu_a_r     <= s2_alu_a;
      s2_alu_b_r     <= s2_alu_b;
      s2_lj_r        <= s2_lj;
      s2_lj_offset_r <= s2_lj_offset;
      s2_mem_wr_r    <= s2_mem_wr;
      s2_io_wr_r     <= s2_io_wr;
      s2_io_rd_r     <= s2_io_rd;
      s2_do_jmp_r    <= s2_do_jmp;
      s2_do_ret_r    <= s2_do_ret;
      s2_pc_r        <= id_pc;
      s2_insn_r      <= id_insn;
      s2_io_din_r    <= io_din;
    end
  end

  // ======================================================================
  // S3: Execute (ALU + post-ALU datapath that consumes alu_c)
  // ======================================================================
  logic [DataAddressWidth-1:0] s3_alu_c;
  logic [CodeAddressWidth-1:0] s3_pc_next;
  logic [Depth-1:0]       s3_rsp_next;
  logic                   s3_rstk_push, s3_rstk_pop;
  logic [CodeAddressWidth-1:0] s3_rstk_data;
  logic [DataAddressWidth-1:0] s3_maddr_next;
  logic [DataWidth-1:0]  s3_mem_dout;

  bf2_s3_execute_comb #(.DataAddressWidth(DataAddressWidth), .CodeAddressWidth(CodeAddressWidth),
                         .DataWidth(DataWidth), .Depth(Depth)) s3_comb (
    .alu_a(s2_alu_a_r), .alu_b(s2_alu_b_r), .insn(s2_insn_r),
    .do_jmp(s2_do_jmp_r), .do_ret(s2_do_ret_r), .lj(s2_lj_r),
    .pj_result(pj_result), .pc(s2_pc_r), .maddr(maddr_r), .mem_din(mem_din_r),
    .io_din(s2_io_din_r), .rsp(rsp_r), .rst0(rst0),
    .alu_c(s3_alu_c), .pc_next(s3_pc_next), .rsp_next(s3_rsp_next),
    .rstk_push(s3_rstk_push), .rstk_pop(s3_rstk_pop), .rstk_data(s3_rstk_data),
    .maddr_next(s3_maddr_next), .mem_dout(s3_mem_dout)
  );

  // ---- EX/MEM registers ----
  logic [DataAddressWidth-1:0] s3_alu_c_r;
  logic [CodeAddressWidth-1:0] s3_pc_next_r;
  logic [Depth-1:0]       s3_rsp_next_r;
  logic                   s3_rstk_push_r, s3_rstk_pop_r;
  logic [CodeAddressWidth-1:0] s3_rstk_data_r;
  logic [DataAddressWidth-1:0] s3_maddr_next_r;
  logic [DataWidth-1:0]  s3_mem_dout_r;
  logic                   s3_mem_wr_r, s3_io_wr_r, s3_io_rd_r;
  logic                   s3_lj_r;
  logic [4:0]             s3_lj_offset_r;

  always_ff @(posedge clk or negedge resetq) begin
    if (!resetq) begin
      s3_alu_c_r      <= '0;
      s3_pc_next_r    <= '0;
      s3_rsp_next_r   <= '0;
      s3_rstk_push_r  <= 1'b0;
      s3_rstk_pop_r   <= 1'b0;
      s3_rstk_data_r  <= '0;
      s3_maddr_next_r <= '0;
      s3_mem_dout_r   <= '0;
      s3_mem_wr_r     <= 1'b0;
      s3_io_wr_r      <= 1'b0;
      s3_io_rd_r      <= 1'b0;
      s3_lj_r         <= 1'b0;
      s3_lj_offset_r  <= '0;
    end else if (cpu_active) begin
      s3_alu_c_r      <= s3_alu_c;
      s3_pc_next_r    <= s3_pc_next;
      s3_rsp_next_r   <= s3_rsp_next;
      s3_rstk_push_r  <= s3_rstk_push;
      s3_rstk_pop_r   <= s3_rstk_pop;
      s3_rstk_data_r  <= s3_rstk_data;
      s3_maddr_next_r <= s3_maddr_next;
      s3_mem_dout_r   <= s3_mem_dout;
      s3_mem_wr_r     <= s2_mem_wr_r;
      s3_io_wr_r      <= s2_io_wr_r;
      s3_io_rd_r      <= s2_io_rd_r;
      s3_lj_r         <= s2_lj_r;
      s3_lj_offset_r  <= s2_lj_offset_r;
    end
  end

  // ======================================================================
  // S4: Memory access + architectural register update
  // ======================================================================
  logic [DataWidth-1:0] s4_mem_din;

  bf2_bram_data #(.DataAddressWidth(DataAddressWidth), .DataWidth(DataWidth)) dmem (
    .clk(clk), .we(s3_mem_wr_r), .addr(s3_maddr_next_r),
    .din(s3_mem_dout_r), .dout(s4_mem_din)
  );

  // Return stack: stack2 (head + tail shift register, registered read).
  // push: we=1 delta=01 (wd into head, old head shifts into tail)
  // pop : we=0 delta=11 (tail top becomes head, tail shifts up)
  logic [CodeAddressWidth-1:0] rst0;
  bf2_stack2 #(.Depth(Depth), .Width(CodeAddressWidth)) rstack (
    .clk(clk),
    .we(s3_rstk_push_r),
    .delta({s3_rstk_pop_r, s3_rstk_push_r | s3_rstk_pop_r}),
    .rd(rst0),
    .wd(s3_rstk_data_r)
  );

  // ---- Architectural state registers ----
  logic [CodeAddressWidth-1:0] pc_r;
  logic [DataAddressWidth-1:0] maddr_r;
  logic [DataWidth-1:0]  mem_din_r;
  logic [Depth-1:0]       rsp_r;
  logic                   lj_r;
  logic [4:0]             lj_offset_r;
  logic                   pj_carry5_r;
  logic [7:0]             pj_pc_high_r;

  // Long-jump 2-cycle pipeline (timing model; state-machine alignment TODO)
  logic [5:0]             pj_low_sum;
  logic [CodeAddressWidth-1:0] pj_result;
  assign pj_low_sum = pc_r[4:0] + id_insn[4:0];
  assign pj_result  = {pj_pc_high_r + id_insn + {7'b0, pj_carry5_r}, pj_low_sum[4:0]};

  always_ff @(negedge resetq or posedge clk) begin
    if (!resetq || ctrl_reset_i) begin
      pc_r         <= '0;
      rsp_r        <= '0;
      maddr_r      <= '0;
      mem_din_r    <= '0;
      lj_r         <= 1'b0;
      lj_offset_r  <= '0;
      pj_carry5_r  <= 1'b0;
      pj_pc_high_r <= '0;
    end else if (cpu_active) begin
      pc_r        <= s3_pc_next_r;
      rsp_r       <= s3_rsp_next_r;
      maddr_r     <= s3_maddr_next_r;
      mem_din_r   <= s4_mem_din;
      lj_r        <= s3_lj_r;
      lj_offset_r <= s3_lj_offset_r;
      if (s3_lj_r) begin
        pj_carry5_r  <= pj_low_sum[5];
        pj_pc_high_r <= pc_r[12:5];
      end
    end
  end

  // ---- Outputs ----
  assign pc_debug = pc_r;
  assign _rsp     = rsp_r;
  assign mem_addr = s3_maddr_next_r;
  assign mem_wr   = s3_mem_wr_r;
  assign mem_dout = s3_mem_dout_r;
  assign io_wr    = s3_io_wr_r;
  assign io_rd    = s3_io_rd_r;
  assign io_dout  = mem_din_r;

endmodule
