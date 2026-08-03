`include "common.h"

// ============================================================================
// BF2-PHASE: Overlapped FD | EX/WB Brainfuck core
// ============================================================================
// Same opcode semantics as bf1.v / the earlier mutually-exclusive 2-phase
// machine, but fetch+decode (S1+S2) and execute+writeback (S3+S4) run in
// the same cycle on consecutive instructions — target ~1 IPC at the board
// clock, with cheap hazard handling instead of a deep pipeline.
//
//   FD cloud (bf2_s12_comb): fetch + decode + BRANCH RESOLUTION.
//   EX cloud (bf2_s34_comb): ALU + tape pointer / mem_dout + stack depth.
//
// External enable:
//   enable = 1 advances the pipe, 0 freezes it (IO wait / halt).  There are
//   no longer mutually exclusive phase selects; pointer-move / stack bubbles
//   are handled inside the core while enable stays high.
//
// Hazards (kept minimal):
//   1. EX→FD cell forward: when EX stores and FD reads the same tape cell,
//      feed s34_mem_dout into the decode cloud (covers ± chains after RLE
//      splits, -], etc.).  last-write BRAM bypass still covers the registered
//      read latency after the store commits.
//   2. Pointer-move bubble: when EX is <> and FD needs the cell at the new
//      address (± [ ] . ), stall FD one cycle and insert an EX nop so
//      registered DMEM can re-read.  maddr is forwarded so ptr→ptr and
//      ptr→, do not stall.
//   3. Stack bubble: when EX push/pop and FD is a looping `]` (needs rst0),
//      stall FD one cycle so stack2's registered head reflects the EX update
//      (covers `]]` exit→outer and `[]`).
//   4. Long-jump flag/helpers commit at FD advance (not EX), so the jump
//      byte decoded next cycle already sees lj_r/pj_*/lj_offset_r.
//
// IMEM contract: registered-output code BRAM.  code_addr is the *prefetch*
// address (s12_pc_next when FD advances, else pc_r).  insn must be the value
// fetched from the previous code_addr (1-cycle latency).  The SoC already
// does this; the Verilator TB models the same latency.
//
// DMEM contract: simple dual-port.  mem_rd_addr is the tape pointer (with
// maddr forward); mem_wr_addr/mem_wr/mem_dout are the EX store.  mem_din is
// the raw registered read; bypass/forward live in this core.
// ============================================================================

module bf2_phase #(
  parameter int CodeAddressWidth = `CADDR_WIDTH,
  parameter int DataAddressWidth = `DADDR_WIDTH,
  parameter int DataWidth  = `DATA_WIDTH,
  parameter int Depth       = `DEPTH        // return-stack depth pointer width (bits)
)(
  input  logic                    clk,
  input  logic                    reset,      // synchronous, active high
  // Pipe enable: 1 = advance, 0 = freeze (IO wait / halt).  Internal
  // pointer-move and stack bubbles hold FD even while enable stays high.
  input  logic                    enable,

  // Data memory (simple dual-port: read addr may differ from write addr)
  output logic [DataAddressWidth-1:0]  mem_rd_addr,
  output logic [DataAddressWidth-1:0]  mem_wr_addr,
  output logic                    mem_wr,
  output logic [DataWidth-1:0]   mem_dout,
  input  logic [DataWidth-1:0]   mem_din,

  // IO
  output logic                    io_wr,
  output logic                    io_rd,
  input  logic [DataWidth-1:0]   io_din,
  output logic [DataWidth-1:0]   io_dout,

  // IO handshake observability for the SoC wrapper: registered EX flags.
  // Stable while the pipe is frozen, so the wrapper can drop enables until
  // RX data / TX space is available without decoding the instruction.
  output logic                    io_rd_pending,  // EX instruction is ','
  output logic                    io_wr_pending,  // EX instruction is '.'

  // Pulses high when a real EX instruction commits this cycle (for step mode)
  output logic                    retiring,

  // Code memory (registered output = insn; code_addr = prefetch address)
  output logic [CodeAddressWidth-1:0]  code_addr,
  input  logic [7:0]              insn,

  // Debug
  output logic [Depth-1:0]        _rsp,
  output logic [CodeAddressWidth-1:0]  pc_debug
);

  // stack2 capacity = 2^Depth entries (Depth = rsp pointer width in bits),
  // so it can hold every value representable by rsp_r [Depth-1:0].

  // enable high → pipe free to run; low → external freeze.
  wire pipe_en = enable;

  // ======================================================================
  // Architectural state
  // ======================================================================
  logic [CodeAddressWidth-1:0] pc_r;
  logic [DataAddressWidth-1:0] maddr_r;
  logic [Depth-1:0]            rsp_r;
  logic                        lj_r;
  logic [4:0]                  lj_offset_r;
  logic                        pj_carry5_r;
  logic [7:0]                  pj_pc_high_r;

  // ======================================================================
  // EX stage valid + FD/EX operand/control registers
  // ======================================================================
  logic                        ex_valid;
  logic signed [DataAddressWidth-1:0] ex_alu_a;
  logic signed [CodeAddressWidth-1:0] ex_alu_b;
  logic [2:0]                  ex_insn_op;
  logic                        ex_lj;
  logic                        ex_mem_wr, ex_io_wr, ex_io_rd;
  logic [CodeAddressWidth-1:0] ex_pc_next;
  logic                        ex_push, ex_pop;
  logic [DataWidth-1:0]        ex_io_dout;

  // ======================================================================
  // EX cloud (needs ex_* ; produces s34_* used by forward + commit)
  // ======================================================================
  logic [DataAddressWidth-1:0] s34_maddr_next;
  logic [DataWidth-1:0]        s34_mem_dout;
  logic [Depth-1:0]            s34_rsp_next;

  bf2_s34_comb #(.DataAddressWidth(DataAddressWidth), .CodeAddressWidth(CodeAddressWidth),
                  .DataWidth(DataWidth), .Depth(Depth)) s34_comb (
    .alu_a(ex_alu_a), .alu_b(ex_alu_b), .insn_op(ex_insn_op), .lj(ex_lj),
    .maddr(maddr_r), .io_din(io_din), .rsp(rsp_r),
    .push(ex_push), .pop(ex_pop),
    .maddr_next(s34_maddr_next),
    .mem_dout(s34_mem_dout), .rsp_next(s34_rsp_next)
  );

  // Pointer-move in EX?  opcode bits 7:6 == 00 and not a long-jump byte.
  wire ex_is_ptr = ex_valid && !ex_lj && (ex_insn_op[2:1] == 2'b00);

  // Best-known tape pointer for FD + DMEM read (forward from EX <>).
  wire [DataAddressWidth-1:0] fwd_maddr =
      ex_is_ptr ? s34_maddr_next : maddr_r;

  // ======================================================================
  // Last-write BRAM bypass + same-cycle EX store forward
  // ======================================================================
  logic [DataAddressWidth-1:0] last_w_addr;
  logic [DataWidth-1:0]        last_w_data;
  logic                        last_w_valid;
  logic [DataWidth-1:0]        mem_din_fwd;

  wire ex_store = ex_valid && ex_mem_wr;

  always_ff @(posedge clk) begin
    if (reset) begin
      last_w_addr  <= '0;
      last_w_data  <= '0;
      last_w_valid <= 1'b0;
    end else begin
      last_w_addr  <= mem_wr_addr;
      last_w_data  <= mem_dout;
      last_w_valid <= mem_wr;
    end
  end

  // Priority: live EX store → last committed store → raw BRAM read.
  assign mem_din_fwd =
      (ex_store && (s34_maddr_next == fwd_maddr)) ? s34_mem_dout :
      (last_w_valid && (last_w_addr == fwd_maddr)) ? last_w_data :
      mem_din;

  // ======================================================================
  // FD cloud
  // ======================================================================
  logic signed [DataAddressWidth-1:0] s12_alu_a;
  logic signed [CodeAddressWidth-1:0] s12_alu_b;
  logic                          s12_lj_next;
  logic [4:0]                    s12_lj_offset_next;
  logic                          s12_pj_carry5_next;
  logic [7:0]                    s12_pj_pc_high_next;
  logic                          s12_mem_wr, s12_io_wr, s12_io_rd;
  logic [CodeAddressWidth-1:0]   s12_pc_next;
  logic                          s12_push, s12_pop;

  // Forward-declared stack top (bf2_stack read is registered combinationally
  // as the head flop output).
  logic [CodeAddressWidth-1:0] rst0;

  bf2_s12_comb #(.DataAddressWidth(DataAddressWidth), .CodeAddressWidth(CodeAddressWidth),
                  .DataWidth(DataWidth)) s12_comb (
    .insn(insn), .pc(pc_r), .maddr(fwd_maddr), .mem_din(mem_din_fwd),
    .lj(lj_r), .lj_offset(lj_offset_r), .pj_carry5(pj_carry5_r),
    .pj_pc_high(pj_pc_high_r), .rst0(rst0),
    .alu_a(s12_alu_a), .alu_b(s12_alu_b),
    .lj_next(s12_lj_next), .lj_offset_next(s12_lj_offset_next),
    .pj_carry5_next(s12_pj_carry5_next), .pj_pc_high_next(s12_pj_pc_high_next),
    .mem_wr(s12_mem_wr), .io_wr(s12_io_wr), .io_rd(s12_io_rd),
    .pc_next(s12_pc_next), .push(s12_push), .pop(s12_pop)
  );

  // FD needs a fresh cell value at fwd_maddr (BRAM cannot supply it the
  // same cycle the pointer moves in EX).
  wire fd_uses_cell = lj_r
      || (!lj_r && (insn[7:6] == 2'b01))             // +/-
      || (!lj_r && (insn[7:5] == 3'b100))            // [ ]
      || (!lj_r && (insn[7:5] == 3'b111));           // .

  // Looping `]` reads rst0; EX push/pop changes the stack head this cycle.
  wire fd_is_ret = !lj_r && (insn[7:5] == 3'b100) && (insn[4:0] == 5'b0);
  wire fd_needs_rst0 = fd_is_ret && (mem_din_fwd != '0);
  wire ex_stack_op = ex_valid && (ex_push || ex_pop);

  wire ptr_stall   = pipe_en && ex_is_ptr && fd_uses_cell;
  wire stack_stall = pipe_en && ex_stack_op && fd_needs_rst0;
  wire fd_stall    = ptr_stall || stack_stall;

  wire advance_ex = pipe_en;
  wire advance_fd = pipe_en && !fd_stall;

  // ======================================================================
  // FD/EX + pc capture
  // ======================================================================
  always_ff @(posedge clk) begin
    if (reset) begin
      pc_r            <= '0;
      lj_r            <= 1'b0;
      lj_offset_r     <= '0;
      pj_carry5_r     <= 1'b0;
      pj_pc_high_r    <= '0;
      ex_valid        <= 1'b0;
      ex_alu_a        <= '0;
      ex_alu_b        <= '0;
      ex_insn_op      <= '0;
      ex_lj           <= 1'b0;
      ex_mem_wr       <= 1'b0;
      ex_io_wr        <= 1'b0;
      ex_io_rd        <= 1'b0;
      ex_pc_next      <= '0;
      ex_push         <= 1'b0;
      ex_pop          <= 1'b0;
      ex_io_dout      <= '0;
    end else if (advance_fd) begin
      pc_r            <= s12_pc_next;
      // Long-jump pending flag + helpers: commit at FD so the next cycle's
      // jump-byte decode already sees them (EX commit would be 1 cycle late).
      lj_r            <= s12_lj_next;
      lj_offset_r     <= s12_lj_offset_next;
      if (s12_lj_next) begin
        pj_carry5_r   <= s12_pj_carry5_next;
        pj_pc_high_r  <= s12_pj_pc_high_next;
      end
      ex_valid        <= 1'b1;
      ex_alu_a        <= s12_alu_a;
      ex_alu_b        <= s12_alu_b;
      ex_insn_op      <= insn[7:5];
      ex_lj           <= lj_r;
      ex_mem_wr       <= s12_mem_wr;
      ex_io_wr        <= s12_io_wr;
      ex_io_rd        <= s12_io_rd;
      ex_pc_next      <= s12_pc_next;
      ex_push         <= s12_push;
      ex_pop          <= s12_pop;
      ex_io_dout      <= mem_din_fwd;
    end else if (advance_ex) begin
      // EX drains (e.g. ptr/stack bubble): insert a nop into EX, hold FD.
      ex_valid        <= 1'b0;
      ex_mem_wr       <= 1'b0;
      ex_io_wr        <= 1'b0;
      ex_io_rd        <= 1'b0;
      ex_push         <= 1'b0;
      ex_pop          <= 1'b0;
    end
  end

  // ======================================================================
  // Return stack
  // ======================================================================
  wire stack_act = advance_ex && ex_valid;
  bf2_stack2 #(.Depth(Depth), .Width(CodeAddressWidth)) rstack (
    .clk(clk),
    .we(stack_act & ex_push),
    .delta({stack_act & ex_pop, stack_act & (ex_push | ex_pop)}),
    .rd(rst0),
    .wd(ex_pc_next)
  );

  // ======================================================================
  // Architectural register update (EX commit)
  // ======================================================================
  always_ff @(posedge clk) begin
    if (reset) begin
      maddr_r <= '0;
      rsp_r   <= '0;
      // lj_r / lj_offset_r / pj_* are reset with the FD/EX block (FD-tied).
    end else if (advance_ex && ex_valid) begin
      maddr_r <= s34_maddr_next;
      rsp_r   <= s34_rsp_next;
    end
  end

  // ======================================================================
  // Outputs
  // ======================================================================
  // Prefetch next insn when FD will advance; otherwise hold current pc so a
  // stalled/frozen cycle re-presents the same IMEM address to the BRAM.
  assign code_addr = advance_fd ? s12_pc_next : pc_r;

  assign mem_rd_addr = fwd_maddr;
  assign mem_wr_addr = s34_maddr_next;
  assign mem_wr      = advance_ex & ex_valid & ex_mem_wr;
  assign mem_dout    = s34_mem_dout;

  assign io_wr   = advance_ex & ex_valid & ex_io_wr;
  assign io_rd   = advance_ex & ex_valid & ex_io_rd;
  assign io_dout = ex_io_dout;

  assign io_rd_pending = ex_valid & ex_io_rd;
  assign io_wr_pending = ex_valid & ex_io_wr;
  assign retiring      = advance_ex & ex_valid;

  assign _rsp     = rsp_r;
  assign pc_debug = pc_r;

endmodule
