`include "common.h"
`default_nettype wire

// ============================================================================
// BF2-PHASE: Functionally correct 2-phase machine (FD | EX/WB)
// ============================================================================
// A hazard-free replacement for bf1.v.  Instead of overlapping pipeline
// stages (which would need forwarding + stalls), the machine runs each
// instruction in two alternating phases:
//
//   Phase A (en_s12): S1+S2 combinational cloud — fetch + decode + BRANCH
//                     RESOLUTION.  Commits pc_r and the FD/EX registers
//                     (operands, control flags, branch result, stack action,
//                     long-jump prefix capture).
//   Phase B (en_s34): S3+S4 combinational cloud — ALU + post-ALU datapath
//                     (maddr_next, mem_dout), return-stack push/pop, DMEM
//                     write.  Commits the architectural state (maddr_r,
//                     rsp_r, lj_r, lj_offset_r, pj_carry5_r, pj_pc_high_r).
//
// Why this has NO hazards:
//   - S1+S2 and S3+S4 are never active in the same cycle, so no two
//     instructions overlap: there is nothing to forward or stall (RAW, WAR
//     and WAW all collapse into "the previous phase B already committed").
//   - The branch (pc) is resolved in phase A, one full phase before the next
//     fetch uses it, so there is no branch-fetch hazard either.
//   - DMEM is read at phase A (branch + `-`/`+` operand) and written at
//     phase B, so a write can never collide with the read of the same
//     instruction.
// The only ordering requirement is that the FD/EX registers written at the
// phase-A edge are read by the S3+S4 cloud during phase B — that is the
// "S2 -> S3" handoff, and it is built into the phase schedule itself.
//
// Phase timing contract (driven by the wrapper/testbench):
//   - en_s12 and en_s34 are mutually exclusive clock enables.
//   - Internally tracked by an enum: PHASE_IDLE -> PHASE_A -> PHASE_B ->
//     PHASE_A -> ... (advances on the respective enable assertion).
//   - The machine starts executing with en_s12 after reset.  Holding both
//     enables low for one cycle after reset deasserts performs the
//     instruction prefetch: code_addr = pc_r = 0 then, so the registered
//     IMEM output latches code_ram[0] for the first phase A.
//   - A stall is modelled by holding both enables low (nothing commits).
//
// Memory model: the decode cloud treats mem_din as an ASYNC read of
// mem_addr.  During phase A, mem_addr = maddr_r, so the cloud reads the
// tape cell combinationally (branch decision for [ ] and the `-`/`+` ALU
// operand).  The real DMEM is a registered-output BRAM whose read is stale
// for one cycle after a write, so the core owns the read-after-write
// bypass: mem_din is the raw BRAM read, and the internal last-write
// forward presents the value written here to the decode cloud. The
// wrapper only feeds the raw read; it needs no knowledge of the bypass.
//
// Functionally identical to bf1.v (same memory/IO/code interface, same
// opcode semantics including the 2-cycle long-jump helper); one instruction
// per (phase A + phase B) pair, i.e. half the single-cycle rate — matching
// the board's half-speed bf1_ce clocking.
// ============================================================================

/* verilator lint_off DECLFILENAME */
/* verilator lint_off MULTITOP */
/* verilator lint_off UNUSEDSIGNAL */
/* verilator lint_off MULTIDRIVEN */
/* verilator lint_off WIDTHEXPAND */

// ---------------------------------------------------------------------------
// Phase A cloud: fetch + decode + branch resolution (S1+S2)
// ---------------------------------------------------------------------------
// Combinational only.  Inputs are the committed architectural state
// (pc_r, maddr_r, lj_r, lj_offset_r, pj_*, rst0) plus the fetched insn and
// the async DMEM read.  Outputs are captured at the phase-A edge into pc_r
// and the FD/EX registers.
//
// Branch resolution lives HERE (not in S3): pc_next is a pure function of
// the committed state, so committing it at the phase-A edge kills the
// branch-fetch hazard.  The small pc+len adder replaces the ALU for the
// short-`[` skip target (BF1 computes it via alu_a={0,pc}, alu_b=signext).
// ---------------------------------------------------------------------------
module bf2_s12_comb #(
  parameter DADDR_WIDTH = 15,
  parameter CADDR_WIDTH = 13,
  parameter DATA_WIDTH  = 8
)(
  input  logic [7:0]              insn,
  input  logic [CADDR_WIDTH-1:0]  pc,
  input  logic [DADDR_WIDTH-1:0]  maddr,
  input  logic [DATA_WIDTH-1:0]   mem_din,
  input  logic                    lj,          // long-jump pending (jump byte)
  input  logic [4:0]              lj_offset,   // arch lj_offset (prefix value)
  input  logic                    pj_carry5,   // arch long-jump helper regs
  input  logic [7:0]              pj_pc_high,
  input  logic [CADDR_WIDTH-1:0]  rst0,        // return stack top

  output logic signed [DADDR_WIDTH-1:0] alu_a,
  output logic signed [CADDR_WIDTH-1:0] alu_b,
  output logic                          lj_next,        // prefix seen this instr
  output logic [4:0]                    lj_offset_next, // pc[4:0] + insn[4:0]
  output logic                          pj_carry5_next, // carry of that add
  output logic [7:0]                    pj_pc_high_next,// pc[12:5] of the prefix
  output logic                          mem_wr,         // '-' '+' ','
  output logic                          io_wr,          // '.'
  output logic                          io_rd,          // ','
  output logic [CADDR_WIDTH-1:0]        pc_next,        // branch-resolved pc
  output logic                          push,           // enter loop: push pc+1
  output logic                          pop             // leave loop: pop
);

  // ---- Long-jump step 1 (prefix cycle, computed for every insn like BF1):
  // low 5 bits of pc + insn and the carry out.  Used as lj_offset for the
  // jump byte two phases later and captured into pj_carry5/pj_pc_high when
  // this instruction IS a prefix.
  logic [5:0] pj_low_sum;
  assign pj_low_sum = pc[4:0] + insn[4:0];
  assign lj_offset_next = pj_low_sum[4:0];
  assign pj_carry5_next = pj_low_sum[5];
  assign pj_pc_high_next = pc[12:5];

  // ---- Long-jump step 2 (jump cycle): target = {high8, low5}
  // parallel adds from the committed pj registers + the current (jump byte)
  // insn; only used when lj=1.
  logic [8:0] pj_mid_sum;
  assign pj_mid_sum = {1'b0, pj_pc_high} + {1'b0, insn} + {8'b0, pj_carry5};
  logic [CADDR_WIDTH-1:0] pj_result;
  assign pj_result = {pj_mid_sum[7:0], lj_offset[4:0]};

  // ---- Short-`[` skip target: pc + sign-extended insn[5:0] (BF1's ALU
  // for the [ opcode: alu_a = {0,pc}, alu_b = signext(insn[5:0]))
  logic [CADDR_WIDTH-1:0] skip_target;
  assign skip_target = pc + {{(CADDR_WIDTH-6){insn[5]}}, insn[5:0]};

  // ---- Pre-ALU operand setup (identical to BF1 "before ALU" block)
  always_comb begin
    alu_a = 'x;
    alu_b = 'x;
    casez ({lj, insn[7:6]})
      3'b0_00: begin alu_a = maddr;                alu_b = $signed({insn[5:0], 7'b0}) >>> 7; end // < >
      3'b0_01: begin alu_a = {7'b0, mem_din};      alu_b = $signed({insn[5:0], 7'b0}) >>> 7; end // - +
      3'b0_10: begin alu_a = {2'b0, pc};           alu_b = $signed({insn[5:0], 7'b0}) >>> 7; end // [
      3'b1_??: ; // long jump - result from the pj registers
      3'b0_11: ; // ALU not used
    endcase
  end

  // ---- Pure control decode (identical to BF1 "after ALU" block flags)
  always_comb begin
    mem_wr  = 1'b0;
    io_wr   = 1'b0;
    io_rd   = 1'b0;
    lj_next = 1'b0;
    casez ({lj, insn[7:5]})
      4'b0_00?: ;                          // < >: maddr_next = alu_c (phase B)
      4'b0_01?: mem_wr = 1'b1;             // - +: mem_dout = alu_c[7:0] (phase B)
      4'b0_100: ;                          // [ or ]: handled by branch below
      4'b1_???: ;                          // long jump - unconditional branch
      4'b0_101: lj_next = 1'b1;            // begin long jump (prefix byte)
      4'b0_110: begin mem_wr = 1'b1; io_rd = 1'b1; end // ,
      4'b0_111: io_wr = 1'b1;              // .
    endcase
  end

  // ---- Branch resolution: pc_next + return-stack action
  // BF1 semantics: default pc+1; [ / jump-byte enters the loop (push pc+1)
  // when the cell is non-zero, otherwise skips; ] loops to rst0 while the
  // cell is non-zero, otherwise falls through and pops.
  logic do_jmp;
  logic do_ret;
  always_comb begin
    do_jmp = 1'b0;
    do_ret = 1'b0;
    if (!lj && insn[7:5] == 3'b100) begin
      do_jmp = |insn[4:0];      // [ (length != 0)
      do_ret = ~do_jmp;         // ] (0x80)
    end
  end

  always_comb begin
    pc_next = pc + 1'b1;
    push    = 1'b0;
    pop     = 1'b0;

    if (do_jmp || lj) begin
      if (mem_din != 8'b0) begin
        push = 1'b1;            // enter the loop: push the return address
      end else begin
        pc_next = lj ? pj_result : skip_target;  // skip the loop
      end
    end else if (do_ret) begin
      if (mem_din != 8'b0) begin
        pc_next = rst0;         // loop again
      end else begin
        pop = 1'b1;             // leave the loop
      end
    end
  end
endmodule


// ---------------------------------------------------------------------------
// Phase B cloud: execute + writeback (S3+S4)
// ---------------------------------------------------------------------------
// Combinational only.  Inputs are the FD/EX registers (registered at the
// phase-A edge) plus the committed architectural state.  Outputs are
// committed at the phase-B edge.  pc_next / push / pop are NOT recomputed
// here — they were resolved in phase A and ride in the FD/EX registers.
// ---------------------------------------------------------------------------
module bf2_s34_comb #(
  parameter DADDR_WIDTH = 15,
  parameter CADDR_WIDTH = 13,
  parameter DATA_WIDTH  = 8,
  parameter DEPTH       = 4
)(
  input  logic signed [DADDR_WIDTH-1:0] alu_a,   // FD/EX operands
  input  logic signed [CADDR_WIDTH-1:0] alu_b,
  input  logic [7:0]                    insn,    // FD/EX instruction
  input  logic                          lj,      // FD/EX: lj flag of this insn
  input  logic [DADDR_WIDTH-1:0]        maddr,   // committed tape pointer
  input  logic [DATA_WIDTH-1:0]         io_din,  // ',' write data (async)
  input  logic [DEPTH-1:0]              rsp,     // committed stack depth
  input  logic                          push,    // from phase A (enter loop)
  input  logic                          pop,     // from phase A (leave loop)

  output logic [DADDR_WIDTH-1:0]        alu_c,
  output logic [DADDR_WIDTH-1:0]        maddr_next,
  output logic [DATA_WIDTH-1:0]         mem_dout,
  output logic [DEPTH-1:0]              rsp_next
);

  // ---- ALU (identical formula to BF1: a + signext(b))
  always_comb begin
    alu_c = alu_a + ($signed({alu_b, 2'b0}) >>> 2);
  end

  // ---- Post-ALU datapath: the two alu_c consumers
  always_comb begin
    maddr_next = maddr;
    mem_dout   = io_din; // default; ',' writes IO data to memory
    casez ({lj, insn[7:5]})
      4'b0_00?: maddr_next = alu_c;      // < or >
      4'b0_01?: mem_dout   = alu_c[7:0]; // - or +
      default:  ;                        // [ ] , . prefix : defaults
    endcase
  end

  // ---- Return-stack depth
  always_comb begin
    rsp_next = rsp + {{(DEPTH-1){1'b0}}, push} - {{(DEPTH-1){1'b0}}, pop};
  end
endmodule


// ============================================================================
// BF2-PHASE top: 2-phase machine, drop-in for bf1.v
// ============================================================================
module bf2_phase_full #(
  parameter CADDR_WIDTH = 13,
  parameter DADDR_WIDTH = 15,
  parameter DATA_WIDTH  = 8,
  parameter DEPTH       = 4        // return-stack depth pointer width (bits)
)(
  input  logic                    clk,
  input  logic                    reset,      // synchronous, active high
  input  logic                    en_s12,     // phase A: fetch+decode commit
  input  logic                    en_s34,     // phase B: execute+writeback commit

  // Data memory.  mem_din is the raw BRAM read; the core presents
  // async decode semantics via the internal last-write bypass.
  output logic [DADDR_WIDTH-1:0]  mem_addr,
  output logic                    mem_wr,
  output logic [DATA_WIDTH-1:0]   mem_dout,
  input  logic [DATA_WIDTH-1:0]   mem_din,

  // IO
  output logic                    io_wr,
  output logic                    io_rd,
  input  logic [DATA_WIDTH-1:0]   io_din,
  output logic [DATA_WIDTH-1:0]   io_dout,

  // IO handshake observability (for the SoC wrapper's phase controller):
  // registered FD/EX flags of the instruction currently in EX.  They are
  // stable for the whole phase-B region (including the B-wait stall), so
  // the wrapper can hold en_s34 low until RX data / TX space is available
  // without decoding the instruction itself.
  output logic                    io_rd_pending,  // EX instruction is ','
  output logic                    io_wr_pending,  // EX instruction is '.'

  // Code memory (registered output = insn; code_addr = prefetch address)
  output logic [CADDR_WIDTH-1:0]  code_addr,
  input  logic [7:0]              insn,

  // Debug
  output logic [DEPTH-1:0]        _rsp,
  output logic [CADDR_WIDTH-1:0]  pc_debug
);

  // ---------------------------------------------------------------------
  // Phase state — combinational from the external enables (no register).
  // en_s12 and en_s34 are mutually exclusive, so exactly one is active at
  // any time.  A stall is both low (PHASE_IDLE).
  // ---------------------------------------------------------------------
  typedef enum logic [1:0] {
    PHASE_IDLE  = 2'b00,
    PHASE_A     = 2'b01,
    PHASE_B     = 2'b10
  } phase_e;

  phase_e phase;
  assign phase = en_s12 ? PHASE_A : (en_s34 ? PHASE_B : PHASE_IDLE);

  localparam STACK_ENTRIES = (1 << DEPTH) - 1; // stack2 = head + tail entries

  // ======================================================================
  // Architectural state (committed at phase-B edges, read by both clouds)
  // ======================================================================
  logic [CADDR_WIDTH-1:0] pc_r;        // committed at phase-A edge (see below)
  logic [DADDR_WIDTH-1:0] maddr_r;     // tape pointer
  logic [DEPTH-1:0]       rsp_r;       // return-stack depth
  logic                   lj_r;        // long-jump pending (jump byte)
  logic [4:0]             lj_offset_r; // low 5 bits of the jump target
  logic                   pj_carry5_r; // long-jump helper regs
  // ======================================================================
  // Last-write bypass (read-after-write memory hazard)
  // ======================================================================
  // A registered-output BRAM returns stale data for one cycle after a
  // write.  Because a write (phase B) is immediately followed by the read
  // (phase A) and the write address becomes the next read address, the
  // last written cell/data is exactly what the decode cloud needs when a
  // store and the next instruction target the same tape cell.  This forward
  // lives in the core (it schedules the read and the write), so the wrapper
  // only has to feed the raw registered read.
  logic [DADDR_WIDTH-1:0]  last_w_addr;
  logic [DATA_WIDTH-1:0]  last_w_data;
  logic                   last_w_valid;
  logic [DATA_WIDTH-1:0]  mem_din_fwd;

  always_ff @(posedge clk) begin
    if (reset) begin
      last_w_addr  <= '0;
      last_w_data  <= '0;
      last_w_valid <= 1'b0;
    end else begin
      last_w_addr  <= mem_addr;
      last_w_data  <= mem_dout;
      last_w_valid <= mem_wr && !reset;
    end
  end

  assign mem_din_fwd = (last_w_valid && last_w_addr == mem_addr)
                       ? last_w_data
                       : mem_din;

  logic [7:0]             pj_pc_high_r;

  // ======================================================================
  // Phase A cloud (S1+S2): fetch+decode+branch resolution
  // ======================================================================
  logic signed [DADDR_WIDTH-1:0] s12_alu_a;
  logic signed [CADDR_WIDTH-1:0] s12_alu_b;
  logic                          s12_lj_next;
  logic [4:0]                    s12_lj_offset_next;
  logic                          s12_pj_carry5_next;
  logic [7:0]                    s12_pj_pc_high_next;
  logic                          s12_mem_wr, s12_io_wr, s12_io_rd;
  logic [CADDR_WIDTH-1:0]        s12_pc_next;
  logic                          s12_push, s12_pop;

  bf2_s12_comb #(.DADDR_WIDTH(DADDR_WIDTH), .CADDR_WIDTH(CADDR_WIDTH),
                  .DATA_WIDTH(DATA_WIDTH)) s12_comb (
    .insn(insn), .pc(pc_r), .maddr(maddr_r), .mem_din(mem_din_fwd),
    .lj(lj_r), .lj_offset(lj_offset_r), .pj_carry5(pj_carry5_r),
    .pj_pc_high(pj_pc_high_r), .rst0(rst0),
    .alu_a(s12_alu_a), .alu_b(s12_alu_b),
    .lj_next(s12_lj_next), .lj_offset_next(s12_lj_offset_next),
    .pj_carry5_next(s12_pj_carry5_next), .pj_pc_high_next(s12_pj_pc_high_next),
    .mem_wr(s12_mem_wr), .io_wr(s12_io_wr), .io_rd(s12_io_rd),
    .pc_next(s12_pc_next), .push(s12_push), .pop(s12_pop)
  );

  // ======================================================================
  // FD/EX registers (committed at the phase-A edge)
  // ======================================================================
  logic signed [DADDR_WIDTH-1:0] ex_alu_a;
  logic signed [CADDR_WIDTH-1:0] ex_alu_b;
  logic [7:0]                    ex_insn;    // for phase-B post-ALU decode
  logic                          ex_lj;      // lj flag ACTIVE for this insn
  logic                          ex_lj_next; // prefix seen (-> arch lj at B)
  logic [4:0]                    ex_lj_offset;
  logic                          ex_pj_carry5;
  logic [7:0]                    ex_pj_pc_high;
  logic                          ex_mem_wr, ex_io_wr, ex_io_rd;
  logic [CADDR_WIDTH-1:0]        ex_pc_next; // branch-resolved pc (push data)
  logic                          ex_push, ex_pop;
  logic [DATA_WIDTH-1:0]         ex_io_dout; // mem_din for '.' (stable in B)

  always_ff @(posedge clk) begin
    if (reset) begin
      pc_r            <= '0;
      ex_alu_a        <= '0;
      ex_alu_b        <= '0;
      ex_insn         <= '0;
      ex_lj           <= 1'b0;
      ex_lj_next      <= 1'b0;
      ex_lj_offset    <= '0;
      ex_pj_carry5    <= 1'b0;
      ex_pj_pc_high   <= '0;
      ex_mem_wr       <= 1'b0;
      ex_io_wr        <= 1'b0;
      ex_io_rd        <= 1'b0;
      ex_pc_next      <= '0;
      ex_push         <= 1'b0;
      ex_pop          <= 1'b0;
      ex_io_dout      <= '0;
    end else if (phase == PHASE_A) begin
      pc_r            <= s12_pc_next;  // branch resolved in phase A
      ex_alu_a        <= s12_alu_a;
      ex_alu_b        <= s12_alu_b;
      ex_insn         <= insn;
      ex_lj           <= lj_r;         // this instruction's lj flag
      ex_lj_next      <= s12_lj_next;
      ex_lj_offset    <= s12_lj_offset_next;
      ex_pj_carry5    <= s12_pj_carry5_next;
      ex_pj_pc_high   <= s12_pj_pc_high_next;
      ex_mem_wr       <= s12_mem_wr;
      ex_io_wr        <= s12_io_wr;
      ex_io_rd        <= s12_io_rd;
      ex_pc_next      <= s12_pc_next;
      ex_push         <= s12_push;
      ex_pop          <= s12_pop;
      ex_io_dout      <= mem_din_fwd;  // the cell value for '.'
    end
  end

  // ======================================================================
  // Phase B cloud (S3+S4): ALU + post-ALU + stack
  // ======================================================================
  logic [DADDR_WIDTH-1:0] s34_alu_c;
  logic [DADDR_WIDTH-1:0] s34_maddr_next;
  logic [DATA_WIDTH-1:0]  s34_mem_dout;
  logic [DEPTH-1:0]       s34_rsp_next;

  bf2_s34_comb #(.DADDR_WIDTH(DADDR_WIDTH), .CADDR_WIDTH(CADDR_WIDTH),
                  .DATA_WIDTH(DATA_WIDTH), .DEPTH(DEPTH)) s34_comb (
    .alu_a(ex_alu_a), .alu_b(ex_alu_b), .insn(ex_insn), .lj(ex_lj),
    .maddr(maddr_r), .io_din(io_din), .rsp(rsp_r),
    .push(ex_push), .pop(ex_pop),
    .alu_c(s34_alu_c), .maddr_next(s34_maddr_next),
    .mem_dout(s34_mem_dout), .rsp_next(s34_rsp_next)
  );

  // ======================================================================
  // Return stack: stack2 (head + tail shift register, registered read).
  // push: we=1 delta=01 ; pop: we=0 delta=11 ; hold: delta=00.
  // Write enable is gated by phase == PHASE_B so the stack only ever
  // changes at a phase-B edge (ex_push/ex_pop are ID/EX regs, stable).
  // ======================================================================
  logic [CADDR_WIDTH-1:0] rst0;
  bf2_stack2 #(.DEPTH(STACK_ENTRIES), .WIDTH(CADDR_WIDTH)) rstack (
    .clk(clk),
    .we((phase == PHASE_B) & ex_push),
    .delta({(phase == PHASE_B) & ex_pop, (phase == PHASE_B) & (ex_push | ex_pop)}),
    .rd(rst0),
    .wd(ex_pc_next)   // return address = pc+1 resolved in phase A
  );

  // ======================================================================
  // Architectural register update (committed at the phase-B edge)
  // ======================================================================
  always_ff @(posedge clk) begin
    if (reset) begin
      maddr_r      <= '0;
      rsp_r        <= '0;
      lj_r         <= 1'b0;
      lj_offset_r  <= '0;
      pj_carry5_r  <= 1'b0;
      pj_pc_high_r <= '0;
    end else if (phase == PHASE_B) begin
      maddr_r     <= s34_maddr_next;
      rsp_r       <= s34_rsp_next;
      lj_r        <= ex_lj_next;        // clear after the jump byte
      lj_offset_r <= ex_lj_offset;      // every cycle, like BF1
      if (ex_lj_next) begin             // prefix cycle: capture pc high + carry
        pj_carry5_r  <= ex_pj_carry5;
        pj_pc_high_r <= ex_pj_pc_high;
      end
    end
  end

  // ======================================================================
  // Outputs
  // ======================================================================
  // code_addr: current PC being decoded (combinational IMEM model).
  // In hardware with registered IMEM, this would be the prefetch address.
  // For simulation with combinational IMEM (testbench), we use pc_r.
  assign code_addr = pc_r;

  // mem_addr: phase A = committed tape pointer (async read for branch +
  // `-`/`+` operand); phase B = write address (maddr_next).
  assign mem_addr = (phase == PHASE_B) ? s34_maddr_next : maddr_r;

  assign mem_wr   = (phase == PHASE_B) & ex_mem_wr;     // '-' '+' ',' store at B edge
  assign mem_dout = (phase == PHASE_B) ? s34_mem_dout : io_din;

  assign io_wr    = (phase == PHASE_B) & ex_io_wr;      // '.' strobe at B edge
  assign io_rd    = (phase == PHASE_B) & ex_io_rd;      // ',' strobe at B edge
  assign io_dout  = ex_io_dout;             // '.' data (cell value, phase A)

  assign io_rd_pending = ex_io_rd;          // registered at the phase-A edge
  assign io_wr_pending = ex_io_wr;          // registered at the phase-A edge

  assign _rsp     = rsp_r;
  assign pc_debug = pc_r;

endmodule
