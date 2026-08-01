`include "common.h"
`default_nettype wire

// ============================================================================
// BF2: Pipeline Stage Combinational Logic for Timing Analysis
// ============================================================================
// This version has ONLY combinational logic (no output registers) so we can
// measure the critical path delay through each stage's combinational logic.
// ============================================================================

/* verilator lint_off DECLFILENAME */
/* verilator lint_off MULTITOP */
/* verilator lint_off UNUSEDSIGNAL */
/* verilator lint_off MULTIDRIVEN */
/* verilator lint_off WIDTHEXPAND */

// ---------------------------------------------------------------------------
// Stage 1: Instruction Fetch (combinational only)
// ---------------------------------------------------------------------------
module bf2_s1_fetch_comb #(
  parameter CADDR_WIDTH = 13
)(
  input  logic [CADDR_WIDTH-1:0]  pc,
  output logic [CADDR_WIDTH-1:0]  code_addr,
  output logic [CADDR_WIDTH-1:0]  pc_next
);
  assign code_addr = pc;
  assign pc_next   = pc + 1'b1;
endmodule


// ---------------------------------------------------------------------------
// Stage 2: Decode / ALU Operand Setup (combinational only)
// ---------------------------------------------------------------------------
// Corrected pipeline partition:
//   S2 does ONLY pre-ALU operand setup + pure control decode (flags that do NOT
//   consume alu_c).  Signals that depend on alu_c (mem_dout, maddr_next, and the
//   skip pc_next) live in S3 Execute AFTER the ALU -- see bf2_s3_execute_comb.
//   (In BF1 these were all written in the "after ALU" block, but the flags are
//   pure opcode decode and can be produced one stage early.)
// ---------------------------------------------------------------------------
module bf2_s2_decode_comb #(
  parameter DADDR_WIDTH = 15,
  parameter CADDR_WIDTH = 13,
  parameter DATA_WIDTH  = 8
)(
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

  // 6-bit low sum with carry (shared between pipeline step 1 and lj_offset update)
  logic [5:0] pj_low_sum;
  assign pj_low_sum = pc[4:0] + insn[4:0];
  assign lj_offset_out = pj_low_sum[4:0];

  // Suppress unused warning
  logic _unused;
  assign _unused = ^lj_offset;

  // --- Before ALU (decode operands) ---
  always_comb begin
    alu_a = 'x;
    alu_b = 'x;
    casez ({lj, insn[7:6]})
      3'b0_00: begin alu_a = maddr;                    alu_b = $signed({insn[5:0], 7'b0}) >>> 7; end // < >
      3'b0_01: begin alu_a = {7'b0, mem_din};          alu_b = $signed({insn[5:0], 7'b0}) >>> 7; end // - +
      3'b0_10: begin alu_a = {2'b0, pc};               alu_b = $signed({insn[5:0], 7'b0}) >>> 7; end // [
      3'b1_??: ; // long jump - result from pipeline registers
      3'b0_11: ; // ALU not used
    endcase
  end

  // --- Control decode: pure instruction decode, independent of alu_c ---
  always_comb begin
    mem_wr   = 1'b0;
    io_wr    = 1'b0;
    io_rd    = 1'b0;
    lj_out   = 1'b0;
    do_jmp   = 1'b0;
    do_ret   = 1'b0;

    casez ({lj, insn[7:5]})
      4'b0_00?: ; // < or >: maddr_next = alu_c computed in S3
      4'b0_01?: mem_wr = 1'b1; // - or +: mem_dout = alu_c[7:0] computed in S3
      4'b0_100: begin do_jmp = |insn[4:0]; do_ret = ~do_jmp; end // [ or ]
      4'b1_???: ; // long jump - handled by lj in pc logic
      4'b0_101: begin lj_out = 1'b1; end // begin long jump
      4'b0_110: begin mem_wr = 1'b1; io_rd = 1'b1; end // ,
      4'b0_111: begin io_wr = 1'b1; end // .
    endcase
  end
endmodule


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
  parameter DADDR_WIDTH = 15,
  parameter CADDR_WIDTH = 13,
  parameter DATA_WIDTH  = 8,
  parameter DEPTH       = 4
)(
  input  logic signed [DADDR_WIDTH-1:0] alu_a,
  input  logic signed [CADDR_WIDTH-1:0] alu_b,
  input  logic [7:0]                    insn,
  input  logic                          do_jmp,
  input  logic                          do_ret,
  input  logic                          lj,
  input  logic [CADDR_WIDTH-1:0]        pj_result,
  input  logic [CADDR_WIDTH-1:0]        pc,
  input  logic [DADDR_WIDTH-1:0]        maddr,
  input  logic [DATA_WIDTH-1:0]         mem_din,
  input  logic [DATA_WIDTH-1:0]         io_din,
  input  logic [DEPTH-1:0]              rsp,
  input  logic [CADDR_WIDTH-1:0]        rst0,

  output logic [DADDR_WIDTH-1:0]        alu_c,
  output logic [CADDR_WIDTH-1:0]        pc_next,
  output logic [DEPTH-1:0]              rsp_next,
  output logic                          rstk_push,
  output logic                          rstk_pop,
  output logic [CADDR_WIDTH-1:0]        rstk_data,
  output logic [DADDR_WIDTH-1:0]        maddr_next,
  output logic [DATA_WIDTH-1:0]         mem_dout
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
        pc_next = lj ? pj_result : alu_c[CADDR_WIDTH-1:0];
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


// ---------------------------------------------------------------------------
// Stage 4: Memory / Writeback (combinational only)
// ---------------------------------------------------------------------------
module bf2_s4_writeback_comb #(
  parameter DADDR_WIDTH = 15,
  parameter CADDR_WIDTH = 13,
  parameter DATA_WIDTH  = 8,
  parameter DEPTH       = 4
)(
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
  input  logic [7:0]              pj_pc_high,

  output logic [DADDR_WIDTH-1:0]  mem_addr,
  output logic                    mem_wr_out,
  output logic [DATA_WIDTH-1:0]   mem_dout_out,
  output logic                    io_wr_out,
  output logic                    io_rd_out,
  output logic [CADDR_WIDTH-1:0]  pc_out,
  output logic [DEPTH-1:0]        rsp_out,
  output logic [DADDR_WIDTH-1:0]  maddr_out,
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


// ---------------------------------------------------------------------------
// Long Jump Pipeline Helper (2-cycle: prefix + jump) - Combinational Core
// ---------------------------------------------------------------------------
module bf2_longjump_pipeline_comb #(
  parameter CADDR_WIDTH = 13
)(
  input  logic [7:0]              prefix_insn,
  input  logic [7:0]              jump_insn,
  input  logic [CADDR_WIDTH-1:0]  pc,

  output logic [CADDR_WIDTH-1:0]  jump_target
);

  // Stage 1: Prefix cycle - compute low 5 bits + carry
  logic [5:0] low_sum;
  logic [4:0] pj_low;
  logic       carry5;
  logic [7:0] pc_high;

  always_comb begin
    low_sum = pc[4:0] + prefix_insn[4:0];
    pj_low  = low_sum[4:0];
    carry5  = low_sum[5];
    pc_high = pc[12:5];
  end

  // Stage 2: Jump cycle - mid addition with carry
  logic [7:0] mid_sum;
  always_comb begin
    mid_sum = pc_high + jump_insn + {7'b0, carry5};
  end

  assign jump_target = {mid_sum, pj_low};
endmodule


// ---------------------------------------------------------------------------
// ALU Module (standalone for timing measurement)
// ---------------------------------------------------------------------------
module bf2_alu_comb #(
  parameter DADDR_WIDTH = 15,
  parameter CADDR_WIDTH = 13
)(
  input  logic signed [DADDR_WIDTH-1:0] alu_a,
  input  logic signed [CADDR_WIDTH-1:0] alu_b,
  output logic [DADDR_WIDTH-1:0]        alu_c
);
  always_comb begin
    alu_c = alu_a + ($signed({alu_b, 2'b0}) >>> 2);
  end
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


// ---------------------------------------------------------------------------
// Stack2 (LIFO push/pop/top) - combinational core for timing measurement
// head register: top of stack (registered output -> zero read-path delay)
// tail register: remaining DEPTH-1 entries as a shift register
// ---------------------------------------------------------------------------
module bf2_stack2_comb #(
  parameter DEPTH = 16,
  parameter WIDTH = 13
)(
  input  logic              we,       // push (write enable)
  input  logic [1:0]        delta,    // {dir, move}: 00=hold, 01=push, 11=pop
  input  logic [WIDTH-1:0]  wd,       // push data
  output logic [WIDTH-1:0]  rd,       // top of stack
  input  logic [WIDTH-1:0]  head,     // current head register value
  input  logic [((WIDTH*DEPTH)-1):0] tail, // current tail register value
  output logic [WIDTH-1:0]  headN,    // next head
  output logic [((WIDTH*DEPTH)-1):0] tailN // next tail
);
  localparam BITS = (WIDTH * DEPTH) - 1;

  assign headN = we ? wd : tail[WIDTH-1:0];
  assign tailN = delta[1] ? {{WIDTH{1'b0}}, tail[BITS:WIDTH]} : {tail[BITS-WIDTH:0], head};
  assign rd = head;
endmodule
