`include "common.h"
`default_nettype wire

// ============================================================================
// BF2: Pipeline Stage Isolation for Timing Analysis
// ============================================================================
// This file contains each pipeline stage as a separate module with registered
// interfaces. Synthesize each module independently to measure:
//   - Critical path delay (report_timing)
//   - Resource utilization (LUTs, FFs, DSPs, BRAM)
//   - Max frequency per stage
//
// Usage:
//   vivado -mode batch -source synth_stage.tcl -tclargs <stage_name>
// ============================================================================

/* verilator lint_off DECLFILENAME */
/* verilator lint_off MULTITOP */
/* verilator lint_off UNUSEDSIGNAL */
/* verilator lint_off MULTIDRIVEN */
/* verilator lint_off WIDTHEXPAND */


// ---------------------------------------------------------------------------
// Stage 1: Instruction Fetch
// ---------------------------------------------------------------------------
// Inputs:  pc (current PC), cpu_active (stall)
// Outputs: code_addr (PC to instruction memory), pc_next (PC+1)
// ---------------------------------------------------------------------------
module bf2_s1_fetch #(
  parameter CADDR_WIDTH = 13
)(
  input  logic                    clk,
  input  logic                    resetq,
  input  logic                    cpu_active,
  input  logic [CADDR_WIDTH-1:0]  pc,
  output logic [CADDR_WIDTH-1:0]  code_addr,
  output logic [CADDR_WIDTH-1:0]  pc_next
);
  // Registered outputs for timing analysis
  logic [CADDR_WIDTH-1:0] code_addr_r;
  logic [CADDR_WIDTH-1:0] pc_next_r;
  always_ff @(posedge clk or negedge resetq) begin
    if (!resetq) begin
      code_addr_r <= '0;
      pc_next_r   <= '0;
    end else if (cpu_active) begin
      code_addr_r <= pc;
      pc_next_r   <= pc + 1'b1;
    end
  end
  assign code_addr = code_addr_r;
  assign pc_next   = pc_next_r;
endmodule


// ---------------------------------------------------------------------------
// Stage 2: Decode / ALU Operand Setup
// ---------------------------------------------------------------------------
// Inputs:  insn, maddr, mem_din, io_din, lj, lj_offset, pc, rsp, rst0
// Outputs: alu_a, alu_b, control signals for S3/S4
// ---------------------------------------------------------------------------
module bf2_s2_decode #(
  parameter DADDR_WIDTH = 15,
  parameter CADDR_WIDTH = 13,
  parameter DATA_WIDTH  = 8
)(
  input  logic                    clk,
  input  logic                    resetq,
  input  logic                    cpu_active,
  input  logic [7:0]              insn,
  input  logic [DADDR_WIDTH-1:0]  maddr,
  input  logic [DATA_WIDTH-1:0]   mem_din,
  input  logic                    lj,
  input  logic [4:0]              lj_offset,
  input  logic [CADDR_WIDTH-1:0]  pc,

  output logic signed [DADDR_WIDTH-1:0] alu_a,
  output logic signed [CADDR_WIDTH-1:0] alu_b,
  output logic                          lj_out,
  output logic [4:0]                    lj_offset_out,
  output logic                          mem_wr,
  output logic                          io_wr,
  output logic                          io_rd,
  output logic                          do_jmp,
  output logic                          do_ret
);

  // Combinational decode (from bf1.v "before ALU" block + pure control decode)
  // NOTE: signals that consume alu_c (mem_dout, maddr_next, skip pc_next)
  // live in S3 Execute AFTER the ALU -- not here.
  logic signed [DADDR_WIDTH-1:0] alu_a_c;
  logic signed [CADDR_WIDTH-1:0] alu_b_c;
  logic                          lj_c, mem_wr_c, io_wr_c, io_rd_c, do_jmp_c, do_ret_c;
  logic [4:0]                    lj_offset_c;

  // 6-bit low sum with carry (shared between pipeline step 1 and lj_offset update)
  logic [5:0] pj_low_sum;
  assign pj_low_sum = pc[4:0] + insn[4:0];
  assign lj_offset_c = pj_low_sum[4:0];

  // Suppress unused warning for lj_offset (used in lj_offset_c)
  logic _unused_lj_offset;
  assign _unused_lj_offset = ^lj_offset;

  // --- Before ALU (decode operands) ---
  always_comb begin
    alu_a_c = 'x;
    alu_b_c = 'x;
    casez ({lj, insn[7:6]})
      3'b0_00: begin alu_a_c = maddr;                    alu_b_c = $signed({insn[5:0], 7'b0}) >>> 7; end // < >
      3'b0_01: begin alu_a_c = {7'b0, mem_din};          alu_b_c = $signed({insn[5:0], 7'b0}) >>> 7; end // - +
      3'b0_10: begin alu_a_c = {2'b0, pc};               alu_b_c = $signed({insn[5:0], 7'b0}) >>> 7; end // [
      3'b1_??: ; // long jump - result from pipeline registers
      3'b0_11: ; // ALU not used
    endcase
  end

  // --- Control decode: pure instruction decode, independent of alu_c ---
  always_comb begin
    mem_wr_c  = 1'b0;
    io_wr_c   = 1'b0;
    io_rd_c   = 1'b0;
    lj_c      = 1'b0;
    do_jmp_c  = 1'b0;
    do_ret_c  = 1'b0;

    casez ({lj, insn[7:5]})
      4'b0_00?: ; // < or >: maddr_next = alu_c computed in S3
      4'b0_01?: mem_wr_c = 1'b1; // - or +: mem_dout = alu_c[7:0] computed in S3
      4'b0_100: begin do_jmp_c = |insn[4:0]; do_ret_c = ~do_jmp_c; end // [ or ]
      4'b1_???: ; // long jump - handled by lj in pc logic
      4'b0_101: begin lj_c = 1'b1; end // begin long jump
      4'b0_110: begin mem_wr_c = 1'b1; io_rd_c = 1'b1; end // ,
      4'b0_111: begin io_wr_c = 1'b1; end // .
    endcase
  end

  // Registered outputs
  always_ff @(posedge clk or negedge resetq) begin
    if (!resetq) begin
      alu_a          <= '0;
      alu_b          <= '0;
      lj_out         <= 1'b0;
      lj_offset_out  <= '0;
      mem_wr         <= 1'b0;
      io_wr          <= 1'b0;
      io_rd          <= 1'b0;
      do_jmp         <= 1'b0;
      do_ret         <= 1'b0;
    end else if (cpu_active) begin
      alu_a         <= alu_a_c;
      alu_b         <= alu_b_c;
      lj_out        <= lj_c;
      lj_offset_out <= lj_offset_c;
      mem_wr        <= mem_wr_c;
      io_wr         <= io_wr_c;
      io_rd         <= io_rd_c;
      do_jmp        <= do_jmp_c;
      do_ret        <= do_ret_c;
    end
  end
endmodule


// ---------------------------------------------------------------------------
// Stage 3: ALU Execute
// ---------------------------------------------------------------------------
// Inputs:  alu_a, alu_b, do_jmp, do_ret, lj, pj_result, pc, maddr, mem_din, rsp, rst0
// Outputs: alu_c, pc_next, rsp_next, rstk_write, rstk_data, maddr_next
// ---------------------------------------------------------------------------
module bf2_s3_execute #(
  parameter DADDR_WIDTH = 15,
  parameter CADDR_WIDTH = 13,
  parameter DATA_WIDTH  = 8,
  parameter DEPTH       = 4
)(
  input  logic                       clk,
  input  logic                       resetq,
  input  logic                       cpu_active,
  input  logic signed [DADDR_WIDTH-1:0] alu_a,
  input  logic signed [CADDR_WIDTH-1:0] alu_b,
  input  logic [7:0]                    insn,
  input  logic                       do_jmp,
  input  logic                       do_ret,
  input  logic                       lj,
  input  logic [CADDR_WIDTH-1:0]     pj_result,
  input  logic [CADDR_WIDTH-1:0]     pc,
  input  logic [DADDR_WIDTH-1:0]     maddr,
  input  logic [DATA_WIDTH-1:0]      mem_din,
  input  logic [DATA_WIDTH-1:0]      io_din,
  input  logic [DEPTH-1:0]           rsp,
  input  logic [CADDR_WIDTH-1:0]     rst0,

  output logic [DADDR_WIDTH-1:0]     alu_c,
  output logic [CADDR_WIDTH-1:0]     pc_next,
  output logic [DEPTH-1:0]           rsp_next,
  output logic                       rstk_push,
  output logic                       rstk_pop,
  output logic [CADDR_WIDTH-1:0]     rstk_data,
  output logic [DADDR_WIDTH-1:0]     maddr_next,
  output logic [DATA_WIDTH-1:0]      mem_dout
);

  // ALU computation
  logic [DADDR_WIDTH-1:0] alu_c_c;
  always_comb begin
    alu_c_c = alu_a + ($signed({alu_b, 2'b0}) >>> 2);
  end

  // Post-ALU datapath: signals that consume alu_c
  // (BF1's "after ALU" block mixed these with pure control decode; the
  //  latter is done in S2, these MUST be after the ALU, i.e. in S3.)
  logic [DADDR_WIDTH-1:0] maddr_next_c;
  logic [DATA_WIDTH-1:0]  mem_dout_c;
  always_comb begin
    maddr_next_c = maddr;
    mem_dout_c   = io_din; // default; ',' writes IO data to memory
    casez ({lj, insn[7:5]})
      4'b0_00?: maddr_next_c = alu_c_c;      // < or >
      4'b0_01?: mem_dout_c   = alu_c_c[7:0]; // - or +
      default:  ;                            // [ ] , . : defaults
    endcase
  end

  // PC / Register logic (from bf1.v sequential block, made combinational)
  logic [CADDR_WIDTH-1:0] pc_next_c;
  logic [DEPTH-1:0]       rsp_next_c;
  logic                   rstk_push_c, rstk_pop_c;
  logic [CADDR_WIDTH-1:0] rstk_data_c;

  always_comb begin
    pc_next_c    = pc + 1'b1;
    rsp_next_c   = rsp;
    rstk_push_c  = 1'b0;
    rstk_pop_c   = 1'b0;
    rstk_data_c  = pc_next_c;

    if (do_jmp || lj) begin
      if (mem_din != 0) begin
        rsp_next_c   = rsp + 1'b1;
        rstk_push_c  = 1'b1;
      end else begin
        pc_next_c = lj ? pj_result : alu_c_c[CADDR_WIDTH-1:0];
      end
    end else if (do_ret) begin
      if (mem_din != 0) pc_next_c = rst0;
      else begin
        rsp_next_c = rsp - 1'b1;
        rstk_pop_c = 1'b1;
      end
    end
  end

  // Registered outputs
  always_ff @(posedge clk or negedge resetq) begin
    if (!resetq) begin
      alu_c       <= '0;
      pc_next     <= '0;
      rsp_next    <= '0;
      rstk_push   <= 1'b0;
      rstk_pop    <= 1'b0;
      rstk_data   <= '0;
      maddr_next  <= '0;
      mem_dout    <= '0;
    end else if (cpu_active) begin
      alu_c       <= alu_c_c;
      pc_next     <= pc_next_c;
      rsp_next    <= rsp_next_c;
      rstk_push   <= rstk_push_c;
      rstk_pop    <= rstk_pop_c;
      rstk_data   <= rstk_data_c;
      maddr_next  <= maddr_next_c;
      mem_dout    <= mem_dout_c;
    end
  end
endmodule


// ---------------------------------------------------------------------------
// Stage 4: Memory / Writeback / Register Update
// ---------------------------------------------------------------------------
// Inputs:  alu_c, pc_next, rsp_next, rstk_write, rstk_data, maddr_next,
//          mem_wr, io_wr, io_rd, mem_dout, lj, lj_offset, pj_carry5, pj_pc_high
// Outputs: mem_addr, mem_dout_reg, io_wr_reg, io_rd_reg, pc_reg, rsp_reg, maddr_reg,
//          lj_reg, lj_offset_reg, pj_carry5_reg, pj_pc_high_reg
// ---------------------------------------------------------------------------
module bf2_s4_writeback #(
  parameter DADDR_WIDTH = 15,
  parameter CADDR_WIDTH = 13,
  parameter DATA_WIDTH  = 8,
  parameter DEPTH       = 4
)(
  input  logic                    clk,
  input  logic                    resetq,
  input  logic                    cpu_active,
  input  logic                    ctrl_reset_i,
  input  logic [DADDR_WIDTH-1:0]  alu_c,
  input  logic [CADDR_WIDTH-1:0]  pc_next,
  input  logic [DEPTH-1:0]        rsp_next,
  input  logic                    rstk_write,
  input  logic [CADDR_WIDTH-1:0]  rstk_data,
  input  logic [DADDR_WIDTH-1:0]  maddr_next,
  input  logic                    mem_wr,
  input  logic                    io_wr,
  input  logic                    io_rd,
  input  logic [DATA_WIDTH-1:0]   mem_dout,
  input  logic                    lj,
  input  logic [4:0]              lj_offset,
  input  logic                    pj_carry5,
  logic [7:0]                     pj_pc_high,

  output logic [DADDR_WIDTH-1:0]  mem_addr,
  output logic                    mem_wr_reg,
  output logic [DATA_WIDTH-1:0]   mem_dout_reg,
  output logic                    io_wr_reg,
  output logic                    io_rd_reg,
  output logic [CADDR_WIDTH-1:0]  pc_reg,
  output logic [DEPTH-1:0]        rsp_reg,
  output logic [DADDR_WIDTH-1:0]  maddr_reg,
  output logic                    lj_reg,
  output logic [4:0]              lj_offset_reg,
  output logic                    pj_carry5_reg,
  output logic [7:0]              pj_pc_high_reg
);

  // Long jump pipeline step 1 (prefix cycle) - from bf1.v
  logic [5:0] pj_low_sum;
  // Note: pc here is pc_reg (current PC), insn comes from instruction memory
  // For isolated timing, we just register the inputs

  // Registered outputs
  always_ff @(negedge resetq or posedge clk) begin
    if (!resetq || ctrl_reset_i) begin
      pc_reg           <= '0;
      rsp_reg          <= '0;
      maddr_reg        <= '0;
      lj_reg           <= 1'b0;
      lj_offset_reg    <= '0;
      pj_carry5_reg    <= 1'b0;
      pj_pc_high_reg   <= '0;
      mem_wr_reg       <= 1'b0;
      mem_dout_reg     <= '0;
      io_wr_reg        <= 1'b0;
      io_rd_reg        <= 1'b0;
    end else if (cpu_active) begin
      pc_reg        <= pc_next;
      rsp_reg       <= rsp_next;
      maddr_reg     <= maddr_next;
      lj_reg        <= lj;
      lj_offset_reg <= lj_offset;
      mem_wr_reg    <= mem_wr;
      mem_dout_reg  <= mem_dout;
      io_wr_reg     <= io_wr;
      io_rd_reg     <= io_rd;

      if (lj) begin
        // Long jump pipeline step 1 (prefix cycle)
        pj_carry5_reg  <= pj_carry5;
        pj_pc_high_reg <= pj_pc_high;
      end
    end
  end

  assign mem_addr = maddr_reg;
endmodule


// ---------------------------------------------------------------------------
// Long Jump Pipeline Helper (2-cycle: prefix + jump)
// ---------------------------------------------------------------------------
// Can be synthesized separately to measure the long-jump adder chain timing
// ---------------------------------------------------------------------------
module bf2_longjump_pipeline #(
  parameter CADDR_WIDTH = 13
)(
  input  logic                    clk,
  input  logic                    resetq,
  input  logic                    cpu_active,
  input  logic                    lj_prefix,    // Asserted during prefix instruction (0xA0-0xBF)
  input  logic [7:0]              prefix_insn,  // Prefix instruction (insn[4:0] = offset[4:0])
  input  logic [7:0]              jump_insn,    // Jump instruction (insn[7:0] = offset[12:5])
  input  logic [CADDR_WIDTH-1:0]  pc,           // PC at prefix instruction
  output logic [CADDR_WIDTH-1:0]  jump_target,  // Calculated jump target
  output logic                    target_valid  // High when jump_target is valid
);

  // Stage 1: Prefix cycle - compute low 5 bits + carry
  logic [5:0] low_sum_s1;
  logic [4:0] pj_low_s1;
  logic       carry5_s1;
  logic [7:0] pc_high_s1;

  always_comb begin
    low_sum_s1  = pc[4:0] + prefix_insn[4:0];
    pj_low_s1   = low_sum_s1[4:0];
    carry5_s1   = low_sum_s1[5];
    pc_high_s1  = pc[12:5];
  end

  // Stage 1 registers
  logic [4:0]  pj_low_s2;
  logic        carry5_s2;
  logic [7:0]  pc_high_s2;
  logic [7:0]  jump_insn_s2;

  always_ff @(posedge clk or negedge resetq) begin
    if (!resetq) begin
      pj_low_s2     <= '0;
      carry5_s2     <= 1'b0;
      pc_high_s2    <= '0;
      jump_insn_s2  <= '0;
    end else if (cpu_active && lj_prefix) begin
      pj_low_s2     <= pj_low_s1;
      carry5_s2     <= carry5_s1;
      pc_high_s2    <= pc_high_s1;
      jump_insn_s2  <= jump_insn;
    end
  end

  // Stage 2: Jump cycle - mid addition with carry
  logic [7:0] mid_sum_s2;
  always_comb begin
    mid_sum_s2 = pc_high_s2 + jump_insn_s2 + {7'b0, carry5_s2};
  end

  // Output
  assign jump_target = {mid_sum_s2, pj_low_s2};

  // Valid signal (asserted one cycle after jump_insn)
  logic target_valid_s2;
  always_ff @(posedge clk or negedge resetq) begin
    if (!resetq) target_valid_s2 <= 1'b0;
    else if (cpu_active) target_valid_s2 <= lj_prefix;
  end
  assign target_valid = target_valid_s2;

endmodule


// ---------------------------------------------------------------------------
// Stack Module (for reference - same as stack.v)
// ---------------------------------------------------------------------------
module bf2_stack #(
  parameter DEPTH = 4,
  parameter WIDTH = 16
)(
  input  logic              clk,
  input  logic [DEPTH-1:0]  ra,
  output logic [WIDTH-1:0]  rd,
  input  logic              we,
  input  logic [DEPTH-1:0]  wa,
  input  logic [WIDTH-1:0]  wd
);
  logic [WIDTH-1:0] store [0:(2**DEPTH)-1];

  initial begin
    integer k;
    for (k = 0; k < (2**DEPTH); k++) store[k] = '0;
  end

  always_ff @(posedge clk) if (we) store[wa] <= wd;
  assign rd = store[ra];
endmodule
