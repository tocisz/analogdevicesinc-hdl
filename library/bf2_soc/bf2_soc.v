`default_nettype none
`timescale 1 ns / 1 ps

// ==========================================================================
// bf2_soc — Brainfuck CPU System-on-Chip Wrapper (bf2_phase core)
// ==========================================================================
// Drop-in replacement for bf1_soc with the IDENTICAL external interface
// (clk_i, resetq, io_*, debug_*, ctrl_gp*), but the core is bf2_phase_full
// — the hazard-free 2-phase machine (phase A = fetch+decode+branch,
// phase B = execute+writeback; one instruction per A+B pair).
//
// What changed vs bf1_soc:
//   * Drive for 2 phases: the wrapper generates two alternating, mutually
//     exclusive clock enables (en_s12 = phase A, en_s34 = phase B) instead
//     of the single half-speed bf1_ce.  The cadence is the same — one
//     instruction per 2 clock cycles — but each phase now gets a full
//     10 ns period, and every register-to-register path is single-cycle,
//     so the bf1 2-cycle multicycle constraints are GONE (bf2_phase's
//     phase clouds are ~4 ns vs bf1's 12.5 ns ALU path).
//   * Simplified reset: bf2_phase_full uses a synchronous, active-high
//     reset; the wrapper derives it from the async active-low resetq and
//     the PS ctrl_reset pulse.  No separate core-level ctrl_reset_i.
//   * No explicit prefetch cycle: pc_r is cleared by reset, so code_addr
//     = 0 while stopped and the registered IMEM output latches code_ram[0]
//     before the CPU ever runs.  Code Port A reads every cycle (code_addr
//     has no combinational dependence on insn, so no stall-freeze needed).
//   * Async DMEM read model: bf2_phase reads mem_din combinationally in
//     phase A (branch decision and `-`/`+` ALU operand).  The data BRAM
//     registered output is aligned by construction — the phase-B read
//     address (s34_maddr_next) becomes the next phase-A read address
//     (maddr_r) — and the last-write bypass covers the same-edge
//     read-after-write, exactly like bf1_soc.
//   * IO stall: a stall is modelled by holding en_s34 low (nothing
//     commits).  The wrapper decides using the CPU's registered
//     io_rd_pending / io_wr_pending flags, so the ',' write and the '.'
//     strobe never fire with stale data.
// ==========================================================================

module bf2_soc (
  input  wire       clk_i,
  input  wire       resetq,          // active low, async (board/PS reset)

  // UART IO
  input  wire [7:0] io_rx_data,
  input  wire       io_rx_valid,
  output wire       io_rx_ready,
  output wire [7:0] io_tx_data,
  output wire       io_tx_valid,
  input  wire       io_tx_ready,

  // Debug outputs
  output wire [12:0] debug_pc,
  output wire [3:0]  debug_rsp,

  // PS control interface (from axi_gpreg)
  input  wire [31:0] ctrl_gp0_out,
  input  wire [31:0] ctrl_gp1_out,
  input  wire [31:0] ctrl_gp2_out,
  output reg  [31:0] ctrl_gp0_in,
  output reg  [31:0] ctrl_gp1_in,
  output reg  [31:0] ctrl_gp2_in
);

  // ==================================================================
  // Parameters
  // ==================================================================
  localparam CODE_RAM_DEPTH = 8192;   // 8K × 8
  localparam DATA_RAM_DEPTH = 32768;  // 32K × 8

  // ==================================================================
  // Internal signals — bf2_phase_full core connections
  // ==================================================================
  wire [14:0] mem_addr;
  wire        mem_wr;
  wire [7:0]  mem_dout;
  wire [7:0]  mem_din;
  wire        io_wr;
  wire        io_rd;
  wire [7:0]  io_din;
  wire [7:0]  io_dout;
  wire [12:0] code_addr;  // = pc_r (combinational) — drives BRAM fetch
  wire [7:0]  insn;
  wire [12:0] pc;
  wire [3:0]  rsp;
  wire        io_rd_pending;  // EX instruction is ',' (registered)
  wire        io_wr_pending;  // EX instruction is '.' (registered)

  // ==================================================================
  // Control: halt / run / step / reset (same semantics as bf1_soc)
  // ==================================================================
  reg halted;
  reg step_pending;

  reg ctrl_halt_d, ctrl_halt;
  reg ctrl_reset_d, ctrl_reset;
  reg ctrl_step_d, ctrl_step;
  reg ctrl_run_d, ctrl_run;

  always @(posedge clk_i or negedge resetq) begin
    if (!resetq) begin
      ctrl_halt_d  <= 0; ctrl_halt  <= 0;
      ctrl_reset_d <= 0; ctrl_reset <= 0;
      ctrl_step_d  <= 0; ctrl_step  <= 0;
      ctrl_run_d   <= 0; ctrl_run   <= 0;
    end else begin
      ctrl_halt_d  <= ctrl_gp0_out[0];
      ctrl_halt    <= ctrl_gp0_out[0] && !ctrl_halt_d;
      ctrl_reset_d <= ctrl_gp0_out[1];
      ctrl_reset   <= ctrl_gp0_out[1] && !ctrl_reset_d;
      ctrl_step_d  <= ctrl_gp0_out[2];
      ctrl_step    <= ctrl_gp0_out[2] && !ctrl_step_d;
      ctrl_run_d   <= ctrl_gp0_out[3];
      ctrl_run     <= ctrl_gp0_out[3] && !ctrl_run_d;
    end
  end

  always @(posedge clk_i or negedge resetq) begin
    if (!resetq) begin
      halted       <= 1;
      step_pending <= 0;
    end else begin
      if (ctrl_reset)
        halted <= 1;
      else if (ctrl_halt)
        halted <= 1;
      else if (ctrl_run)
        halted <= 0;

      if (ctrl_step && halted) begin
        halted       <= 0;
        step_pending <= 1;
      end else if (step_pending && en_s34) begin
        // an instruction completes at the phase-B edge
        halted       <= 1;
        step_pending <= 0;
      end
    end
  end

  // ==================================================================
  // Phase controller — generates the alternating en_s12 / en_s34
  // clock enables for bf2_phase_full.
  //
  //   phase_a_done: 0 → next cycle is phase A (fetch+decode)
  //                 1 → next cycle is phase B (execute+writeback)
  // A stall is modelled by holding both enables low for one or more
  // cycles (phase_a_done stays 1, nothing commits).  The stall condition
  // is evaluated from the REGISTERED io_rd_pending/io_wr_pending flags
  // (committed at the phase-A edge), so it is known one cycle before the
  // B-edge — the ',' write and '.' strobe therefore never fire with stale
  // RX data / a busy TX.
  // ==================================================================
  reg phase_a_done;

  always @(posedge clk_i or negedge resetq) begin
    if (!resetq)
      phase_a_done <= 1'b0;
    else if (ctrl_reset)
      phase_a_done <= 1'b0;
    else if (en_s12)
      phase_a_done <= 1'b1;   // A committed -> need B next
    else if (en_s34)
      phase_a_done <= 1'b0;   // B committed -> need A next
  end

  wire running = !halted;

  // B-stall: hold phase B until ',' has RX data and '.' has TX space.
  wire stall_b = phase_a_done &&
                 ((io_rd_pending && !io_rx_valid) ||
                  (io_wr_pending && !io_tx_ready));

  wire en_s12;
  wire en_s34;
  assign en_s12 = running && !phase_a_done;
  assign en_s34 = running &&  phase_a_done && !stall_b;

  // Simplified reset for the core: synchronous, active-high.
  wire cpu_reset = !resetq || ctrl_reset;

  // ==================================================================
  // BRAM declarations and Port A/B access (no async resets)
  //
  // Each BRAM port gets its own `always @(posedge clk_i)` block with no
  // async reset — REQUIRED by Vivado for dual-port BRAM inference.
  // Control logic lives in separate always blocks with async reset.
  // ==================================================================

  // ── Code RAM: 8K × 8, dual-port block RAM ──
  (* ram_style = "block" *) reg [7:0] code_ram [0:CODE_RAM_DEPTH-1];
  reg [7:0] code_ra_dout;  // Port A registered output (instruction)
  reg [7:0] code_rb_dout;  // Port B registered output (PS read)

  // ── Data RAM: 32K × 8, dual-port block RAM ──
  (* ram_style = "block" *) reg [7:0] data_ram [0:DATA_RAM_DEPTH-1];
  reg [7:0] data_ra_dout;  // Port A registered output (CPU mem_din)
  reg [7:0] data_rb_dout;  // Port B registered output (PS read)

  reg gp1_wr_d, gp1_rd_d;  // delayed ctrl_gp1_out[24:25]
  reg gp2_wr_d, gp2_rd_d;  // delayed ctrl_gp2_out[24:25]

  // ==================================================================
  // BRAM Port A accesses — one always block per port (BRAM inference)
  // ==================================================================

  // ── Code RAM Port A: instruction fetch (read-only) ──
  // Unconditional registered read: code_addr = pc_r has no combinational
  // dependence on insn, so there is no loop to freeze during stalls.
  always @(posedge clk_i) begin
    code_ra_dout <= code_ram[code_addr];
  end

  // ── Code RAM Port B: PS access (read/write) ──
  always @(posedge clk_i) begin
    code_rb_dout <= code_ram[ctrl_gp2_out[12:0]];
    if (ctrl_gp2_out[24] && !gp2_wr_d)
      code_ram[ctrl_gp2_out[12:0]] <= ctrl_gp2_out[23:16];
  end

  // ── Data RAM Port A: CPU access (read/write, read-before-write) ──
  // mem_wr is already gated by the CPU's phase (only asserted at phase-B
  // edges); the !cpu_reset guard suppresses any write on the same edge as
  // a PS-initiated reset (ex_mem_wr still holds its pre-reset value then).
  always @(posedge clk_i) begin
    data_ra_dout <= data_ram[mem_addr];
    if (mem_wr && !cpu_reset)
      data_ram[mem_addr] <= mem_dout;
  end

  // ── Data RAM Port B: PS access (read/write) ──
  always @(posedge clk_i) begin
    data_rb_dout <= data_ram[ctrl_gp1_out[14:0]];
    if (ctrl_gp1_out[24] && !gp1_wr_d)
      data_ram[ctrl_gp1_out[14:0]] <= ctrl_gp1_out[23:16];
  end

  // Zero-initialize memories for simulation (synthesis infers INIT=0)
  integer _init_i_;
  initial begin
    for (_init_i_ = 0; _init_i_ < CODE_RAM_DEPTH; _init_i_ = _init_i_ + 1)
      code_ram[_init_i_] = 8'h00;
    for (_init_i_ = 0; _init_i_ < DATA_RAM_DEPTH; _init_i_ = _init_i_ + 1)
      data_ram[_init_i_] = 8'h00;
  end

  // ==================================================================
  // Instruction fetch
  //
  // code_addr (= pc_r) drives the BRAM fetch address; code_ra_dout is the
  // registered output, so insn always holds the instruction that the NEXT
  // phase-A cycle decodes (the fetch happens during the previous phase-B
  // cycle).  No intermediate register — bf2_phase expects a registered
  // IMEM output (same alignment as bf1_soc).
  // ==================================================================
  assign insn = code_ra_dout;


  // ==================================================================
  // Data RAM bypass (read-after-write hazard)
  //
  // BRAM registered output is stale for one cycle after a write.  The
  // bypass forwards the written data when the phase-A read addresses the
  // same cell.  Because the write (phase B) is always immediately
  // followed by the read (phase A of the next instruction), the captured
  // last_write_addr is always the current maddr_r when a write happened.
  // ==================================================================
  reg [14:0] last_write_addr;
  reg [7:0]  last_write_data;
  reg        last_write_valid;

  always @(posedge clk_i or negedge resetq) begin
    if (!resetq) begin
      last_write_addr  <= 0;
      last_write_data  <= 0;
      last_write_valid <= 0;
    end else begin
      last_write_addr  <= mem_addr;
      last_write_data  <= mem_dout;
      last_write_valid <= mem_wr && !cpu_reset;
    end
  end

  assign mem_din = (last_write_valid && last_write_addr == mem_addr)
                   ? last_write_data
                   : data_ra_dout;


  // ==================================================================
  // IO Bridge
  // ==================================================================
  assign io_din = io_rx_data;

  reg [7:0] io_tx_data_int;
  reg       io_tx_valid_int;

  // TX strobe: single-cycle pulse on io_wr (like bf1_soc).  io_wr is only
  // asserted during a phase-B cycle (en_s34=1), and en_s34 is held low
  // while io_wr_pending && !io_tx_ready, so the strobe always fires into
  // an idle uart_phy.
  always @(posedge clk_i or negedge resetq) begin
    if (!resetq) begin
      io_tx_data_int  <= 0;
      io_tx_valid_int <= 0;
    end else begin
      io_tx_valid_int <= 1'b0;  // default: single-cycle strobe
      if (io_wr && !halted && !cpu_reset) begin
        io_tx_data_int  <= io_dout;
        io_tx_valid_int <= 1;
      end
    end
  end

  assign io_tx_data  = io_tx_data_int;
  assign io_tx_valid = io_tx_valid_int;

  // RX accept handshake for uart_phy's holding-register FIFO.
  //
  // Accept must be:
  //   - high while the CPU waits at ',' with no data yet (else deadlock:
  //     uart_phy only presents a byte while rx_accept_i=1),
  //   - high on the phase-B edge of ',' so the phy consumes the presented
  //     byte at the exact edge the CPU captures io_din (no double-read),
  //   - low otherwise (byte held, not discarded).
  // io_rd_pending is registered at the phase-A edge, so during the B-wait
  // it reliably indicates the instruction in EX is a ','.  The !cpu_reset
  // guard keeps the phy from consuming a byte on the same edge as a
  // PS-initiated reset (the CPU is not capturing then).
  assign io_rx_ready = io_rd_pending && !halted && phase_a_done && !cpu_reset;


  // ==================================================================
  // Debug outputs
  // ==================================================================
  assign debug_pc  = pc;
  assign debug_rsp = rsp;


  // ==================================================================
  // Register Decoder — PS control interface (identical to bf1_soc)
  // ==================================================================
  reg [7:0] data_ram_rdata;
  reg       data_ram_done;
  reg [7:0] code_ram_rdata;
  reg       code_ram_done;

  reg data_ram_rd_pending;

  always @(posedge clk_i or negedge resetq) begin
    if (!resetq) begin
      gp1_wr_d <= 0;
      gp1_rd_d <= 0;
      data_ram_rdata <= 0;
      data_ram_done <= 0;
      data_ram_rd_pending <= 0;
    end else begin
      gp1_wr_d <= ctrl_gp1_out[24];
      gp1_rd_d <= ctrl_gp1_out[25];

      // Write edge — BRAM write happens in the reset-free block
      if (ctrl_gp1_out[24] && !gp1_wr_d)
        data_ram_done <= 1;

      // Read edge — data_rb_dout has 1-cycle BRAM latency, so capture
      // the value on the NEXT cycle after RD goes high
      if (ctrl_gp1_out[25] && !gp1_rd_d)
        data_ram_rd_pending <= 1;
      else if (data_ram_rd_pending) begin
        data_ram_rdata <= data_rb_dout;
        data_ram_done <= 1;
        data_ram_rd_pending <= 0;
      end

      // Clear DONE when PS clears both WR and RD
      if (!ctrl_gp1_out[24] && !ctrl_gp1_out[25]) begin
        data_ram_done <= 0;
        data_ram_rd_pending <= 0;
      end
    end
  end

  reg code_ram_rd_pending;

  always @(posedge clk_i or negedge resetq) begin
    if (!resetq) begin
      gp2_wr_d <= 0;
      gp2_rd_d <= 0;
      code_ram_rdata <= 0;
      code_ram_done <= 0;
      code_ram_rd_pending <= 0;
    end else begin
      gp2_wr_d <= ctrl_gp2_out[24];
      gp2_rd_d <= ctrl_gp2_out[25];

      // Write edge — BRAM write happens in the reset-free block
      if (ctrl_gp2_out[24] && !gp2_wr_d)
        code_ram_done <= 1;

      // Read edge — code_rb_dout has 1-cycle BRAM latency, so capture
      // the value on the NEXT cycle after RD goes high
      if (ctrl_gp2_out[25] && !gp2_rd_d)
        code_ram_rd_pending <= 1;
      else if (code_ram_rd_pending) begin
        code_ram_rdata <= code_rb_dout;
        code_ram_done <= 1;
        code_ram_rd_pending <= 0;
      end

      // Clear DONE when PS clears both WR and RD
      if (!ctrl_gp2_out[24] && !ctrl_gp2_out[25]) begin
        code_ram_done <= 0;
        code_ram_rd_pending <= 0;
      end
    end
  end


  // ==================================================================
  // Status output
  // ==================================================================
  always @(posedge clk_i or negedge resetq) begin
    if (!resetq) begin
      ctrl_gp0_in <= 0;
      ctrl_gp1_in <= 0;
      ctrl_gp2_in <= 0;
    end else begin
      ctrl_gp0_in[0]       <= halted;
      ctrl_gp0_in[15:3]    <= pc;
      ctrl_gp0_in[19:16]   <= rsp;
      ctrl_gp0_in[31:20]   <= 0;
      ctrl_gp1_in[7:0]     <= data_ram_rdata;
      ctrl_gp1_in[8]       <= data_ram_done;
      ctrl_gp1_in[31:9]    <= 0;
      ctrl_gp2_in[7:0]     <= code_ram_rdata;
      ctrl_gp2_in[8]       <= code_ram_done;
      ctrl_gp2_in[31:9]    <= 0;
    end
  end


  // ==================================================================
  // bf2_phase_full core instantiation
  // ==================================================================
  bf2_phase_full #() bf2_inst (
    .clk(clk_i),
    .reset(cpu_reset),           // synchronous, active high (simplified)
    .en_s12(en_s12),             // phase A: fetch+decode commit
    .en_s34(en_s34),             // phase B: execute+writeback commit
    .mem_addr(mem_addr),
    .mem_wr(mem_wr),
    .mem_dout(mem_dout),
    .mem_din(mem_din),
    .io_wr(io_wr),
    .io_rd(io_rd),
    .io_din(io_din),
    .io_dout(io_dout),
    .code_addr(code_addr),
    .insn(insn),
    ._rsp(rsp),
    .pc_debug(pc),
    .io_rd_pending(io_rd_pending),
    .io_wr_pending(io_wr_pending)
  );

endmodule
