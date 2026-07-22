`default_nettype none
`timescale 1 ns / 1 ps

// ==========================================================================
// bf1_soc — Brainfuck CPU System-on-Chip Wrapper
// ==========================================================================
// Wraps the bf1 core with dual-port BRAMs for code (8K × 8) and data
// (32K × 8), an IO bridge for UART, and a register-driven control interface
// for the PS (via axi_gpreg).
//
// Ports:
//   clk_i          — System clock (100 MHz)
//   resetq         — CPU reset (active low, async)
//   io_rx_data     — Byte from UART RX (for ',')
//   io_rx_valid    — io_rx_data is valid (sticky — holds until accepted)
//   io_rx_ready    — CPU is executing ',' — drives uart_phy.rx_accept_i
//   io_tx_data     — Byte for UART TX (from '.')
//   io_tx_valid    — Strobe: io_tx_data is valid
//   io_tx_ready    — UART TX can accept (≡ !tx_busy)
//   debug_pc       — Current program counter
//   debug_rsp      — Current return stack pointer
//   ctrl_gp0_out   — Control register from axi_gpreg
//   ctrl_gp1_out   — Data RAM command
//   ctrl_gp2_out   — Code RAM command
//   ctrl_gp0_in    — Status to axi_gpreg
//   ctrl_gp1_in    — Data RAM result
//   ctrl_gp2_in    — Code RAM result
// ==========================================================================

`include "common.h"

module bf1_soc (
  input  wire       clk_i,
  input  wire       resetq,          // active low, async

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
  // Internal signals — bf1 core connections
  // ==================================================================
  wire [14:0] mem_addr;
  wire        mem_wr;
  wire [7:0]  mem_dout;
  wire [7:0]  mem_din;
  wire        io_wr;
  wire        io_rd;
  wire [7:0]  io_din;
  wire [7:0]  io_dout;
  wire [12:0] code_addr;  // pc_next (combinational next-PC) — drives BRAM fetch
  wire [7:0]  insn;
  wire [12:0] pc;
  wire [3:0]  rsp;
  wire        cpu_active;

  // ==================================================================
  // Clock gating and IO stall
  //
  // io_stall_rx is COMBINATIONAL — when the CPU executes ',' and no
  // UART data is available, cpu_active must drop immediately (same cycle)
  // so the PC does NOT advance past the input instruction.
  //
  // io_stall_tx is COMBINATIONAL for the same reason: while TX is busy
  // the CPU must hold at '.' so the io_tx_valid strobe never fires into
  // a busy uart_phy (which would silently drop the byte).
  // ==================================================================
  reg halted;
  reg step_pending;

  // Edge detection on control bits
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
      end else if (step_pending && cpu_active) begin
        halted       <= 1;
        step_pending <= 0;
      end
    end
  end

  // IO stall (input — ',') — COMBINATIONAL: must block PC advance
  // in the SAME cycle io_rd goes high and data is unavailable.
  wire io_stall_rx;
  assign io_stall_rx = io_rd && !io_rx_valid;

  // IO stall (output — '.') — COMBINATIONAL: while TX is busy, the CPU
  // holds at '.' (PC frozen, no strobe).  When io_tx_ready goes high the
  // CPU executes '.' at the next cpu_active edge and the single-cycle
  // io_tx_valid strobe fires into an IDLE uart_phy.  This guarantees the
  // strobe can never fire while uart_phy is busy (which would drop the
  // byte), so back-to-back '.' instructions transmit correctly.
  wire io_stall_tx;
  assign io_stall_tx = io_wr && !io_tx_ready;

  wire cpu_active_raw = !halted && !io_stall_rx && !io_stall_tx;

  // Prefetch: hold cpu_active=0 for 1 cycle after reset or after a
  // PS-initiated reset so the BRAM can pre-fetch code_ram[0] before
  // the CPU starts executing.
  reg prefetch;

  always @(posedge clk_i or negedge resetq) begin
    if (!resetq)
      prefetch <= 1'b1;
    else if (ctrl_reset)
      prefetch <= 1'b1;
    else if (cpu_active_raw && prefetch)
      prefetch <= 1'b0;
  end

  // Half-speed clock enable: the bf1 core's combinational ALU requires
  // ~12.5 ns to settle, but clk_i=100 MHz gives only 10 ns.  Gating the
  // register updates every other cycle gives 20 ns for the ALU to
  // compute, which comfortably meets the requirement.
  reg bf1_ce;
  always @(posedge clk_i or negedge resetq) begin
    if (!resetq)
      bf1_ce <= 1'b0;
    else
      bf1_ce <= ~bf1_ce;
  end

  assign cpu_active = cpu_active_raw && !prefetch && bf1_ce;


  // ==================================================================
  // BRAM declarations and Port A/B access (no async resets)
  //
  // Each BRAM port gets its own `always @(posedge clk_i)` block with
  // no async reset — this is REQUIRED by Vivado for dual-port BRAM
  // inference (writes to different ports must be in separate processes).
  // Control logic (edge detection, done flags) lives in separate
  // always blocks with async reset.
  // ==================================================================

  // ── Code RAM: 8K × 8, dual-port block RAM ──
  (* ram_style = "block" *) reg [7:0] code_ram [0:CODE_RAM_DEPTH-1];
  reg [7:0] code_ra_dout;  // Port A registered output (instruction)
  reg [7:0] code_rb_dout;  // Port B registered output (PS read)

  // ── Data RAM: 32K × 8, dual-port block RAM ──
  (* ram_style = "block" *) reg [7:0] data_ram [0:DATA_RAM_DEPTH-1];
  reg [7:0] data_ra_dout;  // Port A registered output (CPU mem_din)
  reg [7:0] data_rb_dout;  // Port B registered output (PS read)

  // BRAM edge-detect signals for Port B (reset-domain)
  // These are registered in the control block (with reset), but read
  // combinationally here — fine for synthesis.
  reg gp1_wr_d, gp1_rd_d;  // delayed ctrl_gp1_out[24:25]
  reg gp2_wr_d, gp2_rd_d;  // delayed ctrl_gp2_out[24:25]

  // ==================================================================
  // BRAM Port A accesses — one always block per port is REQUIRED by
  // Vivado for dual-port BRAM inference.  Each port gets its own
  // `always @(posedge clk_i)` block with no async reset.
  // ==================================================================

  // ── Code RAM Port A: instruction fetch (read-only) ──
  // Freeze during stalls (cpu_active=0, prefetch=0) to prevent a
  // combinational loop: code_addr depends on insn (= code_ra_dout),
  // and updating code_ra_dout would change code_addr, causing the
  // BRAM to jump to a different address every cycle. By freezing,
  // insn stays stable during the entire stall.
  always @(posedge clk_i) begin
    if (prefetch || cpu_active)
      code_ra_dout <= code_ram[prefetch ? 13'd0 : code_addr];
  end

  // ── Code RAM Port B: PS access (read/write) ──
  always @(posedge clk_i) begin
    code_rb_dout <= code_ram[ctrl_gp2_out[12:0]];
    if (ctrl_gp2_out[24] && !gp2_wr_d)
      code_ram[ctrl_gp2_out[12:0]] <= ctrl_gp2_out[23:16];
  end

  // ── Data RAM Port A: CPU access (read/write, read-before-write) ──
  always @(posedge clk_i) begin
    data_ra_dout <= data_ram[mem_addr];
    if (mem_wr && cpu_active)
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
  // Uses code_addr (pcN) as the BRAM fetch address so code_ra_dout
  // always contains the NEXT instruction. During the 1-cycle prefetch
  // after reset, the BRAM reads address 0 so the first instruction is
  // ready when cpu_active goes high.
  //
  // We connect code_ra_dout directly to insn (no intermediate register)
  // because the BRAM output is already registered. An extra pipeline
  // stage (insn_reg) would delay everything by one cycle, causing the
  // bf1 core to execute each instruction with pc pointing one past the
  // correct address — breaking [ and ] which use pc for jumps.
  // ==================================================================
  assign insn = code_ra_dout;


  // ==================================================================
  // Data RAM bypass (read-after-write hazard)
  //
  // BRAM registered output is stale for one cycle after a write.
  // Forward the written data when the next read addresses the same
  // cell (e.g., '+' followed by '.' on the same tape cell).
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
      last_write_valid <= mem_wr && cpu_active;
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

  // TX strobe: single-cycle pulse on io_wr (like echo_char's tx_start).
  // uart_phy.tx_start expects a single-cycle strobe, not a level that
  // persists until acknowledged.  If io_tx_valid stayed high until
  // io_tx_ready (= !tx_busy), the TX FSM would re-enter TX_START on
  // the cycle after transmission completes, generating a spurious byte.
  always @(posedge clk_i or negedge resetq) begin
    if (!resetq) begin
      io_tx_data_int  <= 0;
      io_tx_valid_int <= 0;
    end else begin
      io_tx_valid_int <= 1'b0;  // default: single-cycle strobe
      if (io_wr && cpu_active) begin
        io_tx_data_int  <= io_dout;
        io_tx_valid_int <= 1;
      end
    end
  end

  assign io_tx_data  = io_tx_data_int;
  assign io_tx_valid = io_tx_valid_int;
  // RX accept handshake for uart_phy's holding-register FIFO.
  //
  // uart_phy only PRESENTS a byte (rx_valid<=1) while rx_accept_i=1, and
  // CONSUMES the presented byte at ANY posedge where rx_valid && rx_accept_i.
  // The CPU, however, only captures io_din at posedges where cpu_active=1
  // (every other cycle due to bf1_ce).  rx_accept_i must therefore be:
  //   - high while the CPU waits at ',' with no data yet (else deadlock:
  //     presentation waits for accept, accept would wait for cpu_active,
  //     and cpu_active waits for rx_valid),
  //   - low on bf1_ce=0 cycles once data IS presented (else uart_phy
  //     consumes the byte on a cycle the CPU does not capture it —
  //     byte lost and CPU stuck at ',' forever),
  //   - low while halted (byte must be held, not discarded).
  assign io_rx_ready = io_rd && !halted && (!io_rx_valid || cpu_active);


  // ==================================================================
  // Debug outputs
  // ==================================================================
  assign debug_pc = pc;
  assign debug_rsp = rsp;


  // ==================================================================
  // Register Decoder — PS control interface
  //
  // Edge detection + done flags — these have async reset.
  // BRAM Port B accesses are in the reset-free block above (they
  // read gp1_wr_d/gp1_rd_d from here combinationally).
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
  // bf1 core instantiation
  // ==================================================================
  bf1 #() bf1_inst (
    .clk(clk_i),
    .resetq(resetq),
    .cpu_active(cpu_active),
    .ctrl_reset_i(ctrl_reset),
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
    .pc_debug(pc)
  );

endmodule
