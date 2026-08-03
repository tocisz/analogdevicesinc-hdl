`default_nettype none
`timescale 1 ns / 1 ps

// ==========================================================================
// bf2_soc — Brainfuck CPU System-on-Chip Wrapper (bf2_phase core)
// ==========================================================================
// Drop-in replacement for bf1_soc with the IDENTICAL external interface
// (clk_i, resetq, io_*, debug_*, ctrl_gp*), but the core is bf2_phase —
// an overlapped FD | EX machine (fetch+decode and execute in the same
// cycle on consecutive instructions; ~1 IPC steady state).
//
// What the wrapper does:
//   * Drives the core `enable` high when running, low on IO wait / halt.
//     Internal bubbles (pointer-move / stack) are handled inside the core
//     even while enable stays high.
//   * Synchronous active-high cpu_reset from async resetq + PS ctrl_reset.
//   * Registered IMEM: code_addr is the core's prefetch address; insn =
//     code_ra_dout (1-cycle BRAM latency) — matches the core contract.
//   * Simple dual-port DMEM for the CPU: Port A = read (mem_rd_addr),
//     Port B = write (mem_wr_addr) while the core stores, else PS access.
//     RAW bypass lives entirely in bf2_phase.
//   * IO stall: freeze both enables while io_rd_pending && !rx_valid or
//     io_wr_pending && !tx_ready.  Step mode completes on core `retiring`.
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
  localparam int CodeRamDepth = 8192;   // 8K × 8
  localparam int DataRamDepth = 32768;  // 32K × 8

  // ==================================================================
  // Internal signals — bf2_phase core connections
  // ==================================================================
  wire [14:0] mem_rd_addr;
  wire [14:0] mem_wr_addr;
  wire        mem_wr;
  wire [7:0]  mem_dout;
  wire        io_wr;
  /* verilator lint_off UNUSEDSIGNAL */
  wire        io_rd;   // 1-cycle ',' strobe; RX handshake uses io_rd_pending
  /* verilator lint_on UNUSEDSIGNAL */
  wire [7:0]  io_din;
  wire [7:0]  io_dout;
  wire [12:0] code_addr;
  wire [7:0]  insn;
  wire [12:0] pc;
  wire [3:0]  rsp;
  wire        io_rd_pending;
  wire        io_wr_pending;
  wire        retiring;

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
      end else if (step_pending && retiring) begin
        // one architectural instruction committed
        halted       <= 1;
        step_pending <= 0;
      end
    end
  end

  // ==================================================================
  // Pipe enable — high (nominal) when running, low on IO wait / halt.
  // ==================================================================
  wire running = !halted;

  // TX holdoff: io_tx_valid is registered (1-cycle late to uart_phy), and
  // uart_phy only drops tx_ready the cycle AFTER it samples tx_start.  At
  // ~1 IPC two consecutive '.' would both see tx_ready=1 and the second
  // byte would be lost.  Stall one extra cycle after any io_wr fire so the
  // busy flag is visible before the next '.' may retire.
  reg tx_holdoff;
  always @(posedge clk_i or negedge resetq) begin
    if (!resetq)
      tx_holdoff <= 1'b0;
    else
      tx_holdoff <= io_wr && !halted && !cpu_reset;
  end

  wire io_stall =
      (io_rd_pending && !io_rx_valid) ||
      (io_wr_pending && (!io_tx_ready || tx_holdoff));

  wire enable = running && !io_stall;

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
  (* ram_style = "block" *) reg [7:0] code_ram [CodeRamDepth];
  reg [7:0] code_ra_dout;  // Port A registered output (instruction)
  reg [7:0] code_rb_dout;  // Port B registered output (PS read)

  // ── Data RAM: 32K × 8, dual-port block RAM ──
  (* ram_style = "block" *) reg [7:0] data_ram [DataRamDepth];
  reg [7:0] data_ra_dout;  // Port A registered output (CPU mem_din)
  reg [7:0] data_rb_dout;  // Port B registered output (PS read / CPU write port)

  reg gp1_wr_d, gp1_rd_d;  // delayed ctrl_gp1_out[24:25]
  reg gp2_wr_d, gp2_rd_d;  // delayed ctrl_gp2_out[24:25]

  // ==================================================================
  // BRAM Port A/B accesses — one always block per port (BRAM inference)
  // ==================================================================

  // ── Code RAM Port A: instruction fetch (read-only) ──
  // code_addr is the core prefetch address (no comb dependence on insn).
  always @(posedge clk_i) begin
    code_ra_dout <= code_ram[code_addr];
  end

  // ── Code RAM Port B: PS access (read/write) ──
  always @(posedge clk_i) begin
    code_rb_dout <= code_ram[ctrl_gp2_out[12:0]];
    if (ctrl_gp2_out[24] && !gp2_wr_d)
      code_ram[ctrl_gp2_out[12:0]] <= ctrl_gp2_out[23:16];
  end

  // ── Data RAM Port A: CPU read (mem_rd_addr) ──
  always @(posedge clk_i) begin
    data_ra_dout <= data_ram[mem_rd_addr];
  end

  // ── Data RAM Port B: CPU write when storing, else PS access ──
  // Simple dual-port: CPU may read (A) and write (B) different addresses
  // in the same cycle.  CPU store wins over a simultaneous PS access.
  wire        cpu_dmem_wr = mem_wr && !cpu_reset;
  wire [14:0] data_b_addr = cpu_dmem_wr ? mem_wr_addr : ctrl_gp1_out[14:0];
  wire        data_b_we   = cpu_dmem_wr || (ctrl_gp1_out[24] && !gp1_wr_d);
  wire [7:0]  data_b_din  = cpu_dmem_wr ? mem_dout : ctrl_gp1_out[23:16];

  always @(posedge clk_i) begin
    data_rb_dout <= data_ram[data_b_addr];
    if (data_b_we)
      data_ram[data_b_addr] <= data_b_din;
  end

  // Zero-initialize memories for simulation (synthesis infers INIT=0)
  integer _init_i_;
  initial begin
    for (_init_i_ = 0; _init_i_ < CodeRamDepth; _init_i_ = _init_i_ + 1)
      code_ram[_init_i_] = 8'h00;
    for (_init_i_ = 0; _init_i_ < DataRamDepth; _init_i_ = _init_i_ + 1)
      data_ram[_init_i_] = 8'h00;
  end

  // ==================================================================
  // Instruction fetch — registered BRAM output feeds the core
  // ==================================================================
  assign insn = code_ra_dout;

  // ==================================================================
  // IO Bridge
  // ==================================================================
  assign io_din = io_rx_data;

  reg [7:0] io_tx_data_int;
  reg       io_tx_valid_int;

  // TX strobe: single-cycle pulse on io_wr.  en_pipe is held low while
  // io_wr_pending && !io_tx_ready, so the strobe always fires into idle TX.
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

  // RX accept: high while EX holds ',' so uart_phy can present/consume a byte.
  assign io_rx_ready = io_rd_pending && !halted && !cpu_reset;


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

      if (ctrl_gp1_out[24] && !gp1_wr_d)
        data_ram_done <= 1;

      if (ctrl_gp1_out[25] && !gp1_rd_d)
        data_ram_rd_pending <= 1;
      else if (data_ram_rd_pending) begin
        data_ram_rdata <= data_rb_dout;
        data_ram_done <= 1;
        data_ram_rd_pending <= 0;
      end

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

      if (ctrl_gp2_out[24] && !gp2_wr_d)
        code_ram_done <= 1;

      if (ctrl_gp2_out[25] && !gp2_rd_d)
        code_ram_rd_pending <= 1;
      else if (code_ram_rd_pending) begin
        code_ram_rdata <= code_rb_dout;
        code_ram_done <= 1;
        code_ram_rd_pending <= 0;
      end

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
  // bf2_phase core instantiation
  // ==================================================================
  bf2_phase #() bf2_inst (
    .clk(clk_i),
    .reset(cpu_reset),
    .enable(enable),
    .mem_rd_addr(mem_rd_addr),
    .mem_wr_addr(mem_wr_addr),
    .mem_wr(mem_wr),
    .mem_dout(mem_dout),
    .mem_din(data_ra_dout),
    .io_wr(io_wr),
    .io_rd(io_rd),
    .io_din(io_din),
    .io_dout(io_dout),
    .code_addr(code_addr),
    .insn(insn),
    ._rsp(rsp),
    .pc_debug(pc),
    .io_rd_pending(io_rd_pending),
    .io_wr_pending(io_wr_pending),
    .retiring(retiring)
  );

endmodule
