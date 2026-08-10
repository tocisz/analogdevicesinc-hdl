`default_nettype none
`timescale 1 ns / 1 ps

// ==========================================================================
// z80_soc — Z80 System-on-Chip Wrapper (tv80 core via Wishbone bridge)
// ==========================================================================
// DROP-IN REPLACEMENT for bf2_soc — identical external interface (clk_i,
// resetq, io_*, ctrl_gp*), but the core is a Z80-compatible CPU using the
// tv80 core (MIT license) wrapped by wb_tv80 (Wishbone master bridge).
//
// What the wrapper does:
//   * Instantiates wb_tv80 (tv80s + Wishbone master logic)
//   * Wishbone address decoder: ROM (0x0000–0x1FFF), RAM (0x2000–0xFFFF),
//     I/O space (any port → axis_byte_bridge byte handshake)
//   * Dual-port BRAMs: Port A = Z80 (Wishbone), Port B = PS (ctrl_gp1/2)
//   * I/O bridge: Z80 IN/OUT ↔ io_rx_* / io_tx_* handshake
//   * Control: halt / run / step / reset via ctrl_gp0 (same protocol)
//   * Step mode uses the tv80's m1_n signal to detect instruction boundaries
// ==========================================================================

module z80_soc (
  input  wire       clk_i,
  input  wire       resetq,          // active low, async (board/PS reset)

  // UART IO — same signals as bf2_soc
  input  wire [7:0] io_rx_data,
  input  wire       io_rx_valid,
  output wire       io_rx_ready,
  output wire [7:0] io_tx_data,
  output wire       io_tx_valid,
  input  wire       io_tx_ready,

  // Debug outputs
  output wire [15:0] debug_pc,
  output wire [7:0]  debug_rsp,

  // PS control interface (from axi_gpreg) — same protocol as bf2_soc
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
  localparam int RomDepth = 8192;  // 8K × 8 (2× BRAM36E1)
  localparam int RamDepth = 56 * 1024;  // 56K × 8 (0x2000–0xFFFF)

  // ==================================================================
  // wb_tv80 Wishbone signals
  // ==================================================================
  logic [15:0] wbm_adr_o;
  logic [1:0]  wbm_tga_o;
  logic [7:0]  wbm_dat_i;
  logic [7:0]  wbm_dat_o;
  logic        wbm_cyc_o;
  logic        wbm_stb_o;
  logic        wbm_we_o;
  logic        wbm_ack_i;
  logic        m1_n_o;              // exposed by modified wb_tv80

  // ==================================================================
  // wb_tv80 instantiation
  // ==================================================================
  wb_tv80 z80_cpu (
    .nrst_i    (cpu_nrst),
    .clk_i     (clk_i),
    .wbm_adr_o (wbm_adr_o),
    .wbm_tga_o (wbm_tga_o),
    .wbm_dat_i (wbm_dat_i),
    .wbm_dat_o (wbm_dat_o),
    .wbm_cyc_o (wbm_cyc_o),
    .wbm_stb_o (wbm_stb_o),
    .wbm_we_o  (wbm_we_o),
    .wbm_ack_i (wbm_ack_i),
    .nmi_req_i ('0),
    .int_req_i ('0),
    .busrq_i   ('0),
    .busak_o   (),
    .m1_n_o    (m1_n_o)
  );

  // ==================================================================
  // CPU reset generation
  // ==================================================================
  // cpu_nrst combines:
  //   - resetq: board-level async reset (active low)
  //   - ctrl_reset_pulse: PS-initiated reset (stretched to 8 cycles)
  //
  logic [2:0] ps_reset_stretch;
  logic       ctrl_reset_pulse;
  logic       ctrl_reset_d;

  always_ff @(posedge clk_i or negedge resetq) begin
    if (!resetq) begin
      ctrl_reset_d <= '0;
      ctrl_reset_pulse <= '0;
      ps_reset_stretch <= '0;
    end else begin
      ctrl_reset_d <= ctrl_gp0_out[1];
      ctrl_reset_pulse <= ctrl_gp0_out[1] && !ctrl_reset_d;

      if (ctrl_reset_pulse)
        ps_reset_stretch <= 3'b111;
      else if (ps_reset_stretch != 3'b000)
        ps_reset_stretch <= ps_reset_stretch - 1;
    end
  end

  wire cpu_nrst = resetq && (ps_reset_stretch == 3'b000);

  // ==================================================================
  // Control: halt / run / step / reset (same semantics as bf2_soc)
  // ==================================================================
  logic halted;
  logic step_pending;

  logic ctrl_halt_d, ctrl_halt_edge;
  logic ctrl_step_d, ctrl_step_edge;
  logic ctrl_run_d,  ctrl_run_edge;

  always_ff @(posedge clk_i or negedge resetq) begin
    if (!resetq) begin
      ctrl_halt_d  <= '0; ctrl_halt_edge  <= '0;
      ctrl_step_d  <= '0; ctrl_step_edge  <= '0;
      ctrl_run_d   <= '0; ctrl_run_edge   <= '0;
    end else begin
      ctrl_halt_d  <= ctrl_gp0_out[0];
      ctrl_halt_edge <= ctrl_gp0_out[0] && !ctrl_halt_d;
      ctrl_step_d  <= ctrl_gp0_out[2];
      ctrl_step_edge <= ctrl_gp0_out[2] && !ctrl_step_d;
      ctrl_run_d   <= ctrl_gp0_out[3];
      ctrl_run_edge  <= ctrl_gp0_out[3] && !ctrl_run_d;
    end
  end

  // ==================================================================
  // Step detection: track m1_n to count instruction boundaries
  // ==================================================================
  //
  // We use the tv80's m1_n signal (active-low M1 cycle indicator):
  //   m1_n=0 → CPU is in M1 cycle (opcode fetch)
  //   m1_n=1 → CPU is NOT in M1 (M2-M6 or between instructions)
  //
  // Step algorithm (after releasing halt):
  //   1. WAIT_M1_HIGH: wait until m1_n goes high (end any partially-stalled M1)
  //   2. WAIT_M1_LOW:  wait for m1_n to fall (start of next instruction M1)
  //   3. WAIT_M1_HIGH2: wait for m1_n to rise again (M1 done, rest of
  //                      instruction executes via M2-M6)
  //   4. WAIT_NEXT:     wait for m1_n to fall again (NEXT instruction M1)
  //                     → one complete instruction has executed → halt!
  //
  typedef enum logic [2:0] {
    STEP_IDLE,
    STEP_WAIT_M1_HIGH,
    STEP_WAIT_M1_LOW,
    STEP_WAIT_M1_HIGH2,
    STEP_WAIT_NEXT
  } step_state_t;

  step_state_t step_state;
  logic        m1_n_d;
  logic        m1_n_falling, m1_n_rising;
  logic        step_complete;

  always_ff @(posedge clk_i) begin
    m1_n_d <= m1_n_o;
  end

  assign m1_n_falling = m1_n_d && !m1_n_o;  // 1→0 transition
  assign m1_n_rising  = !m1_n_d && m1_n_o;  // 0→1 transition

  always_ff @(posedge clk_i or negedge resetq) begin
    if (!resetq) begin
      step_state    <= STEP_IDLE;
      step_complete <= '0;
    end else begin
      step_complete <= '0;

      if (step_pending) begin
        unique case (step_state)
          STEP_IDLE: begin
            // After releasing halt, check current m1_n state
            if (m1_n_o)
              step_state <= STEP_WAIT_M1_LOW;   // already high, go straight to waiting for M1 start
            else
              step_state <= STEP_WAIT_M1_HIGH;  // stalled in M1, wait for it to end
          end

          STEP_WAIT_M1_HIGH: begin
            if (m1_n_rising)
              step_state <= STEP_WAIT_M1_LOW;
          end

          STEP_WAIT_M1_LOW: begin
            if (m1_n_falling)
              step_state <= STEP_WAIT_M1_HIGH2;  // M1 of instruction started
          end

          STEP_WAIT_M1_HIGH2: begin
            if (m1_n_rising)
              step_state <= STEP_WAIT_NEXT;      // M1 done, rest of instruction runs
          end

          STEP_WAIT_NEXT: begin
            if (m1_n_falling) begin              // next instruction's M1 starting
              step_complete <= '1;
              step_state    <= STEP_IDLE;
            end
          end
        endcase
      end else begin
        step_state <= STEP_IDLE;
      end
    end
  end

  // ==================================================================
  // Halt / step / run state machine
  // ==================================================================
  always_ff @(posedge clk_i or negedge resetq) begin
    if (!resetq) begin
      halted       <= '1;
      step_pending <= '0;
    end else begin
      if (ctrl_reset_pulse)
        halted <= '1;
      else if (ctrl_halt_edge)
        halted <= '1;
      else if (ctrl_run_edge)
        halted <= '0;

      if (ctrl_step_edge && halted) begin
        halted       <= '0;
        step_pending <= '1;
      end else if (step_pending && step_complete) begin
        halted       <= '1;
        step_pending <= '0;
      end
    end
  end

  wire cpu_active = !halted;

  // ==================================================================
  // Wishbone Address Decoder
  // ==================================================================
  // wbm_tga_o[0] = 1 for I/O cycle (iorq_n active), 0 for memory
  wire is_io_cycle  = wbm_tga_o[0];
  wire is_mem_cycle = !wbm_tga_o[0];

  // Memory address decode:
  //   [15:13] == 000 → ROM (0x0000 - 0x1FFF)
  //   [15:13] != 000 → RAM (0x2000 - 0xFFFF)
  wire is_rom = is_mem_cycle && (wbm_adr_o[15:13] == 3'b000);
  wire is_ram = is_mem_cycle && (wbm_adr_o[15:13] != 3'b000);

  wire wb_valid = wbm_cyc_o && wbm_stb_o;

  // ==================================================================
  // BRAM declarations — dual-port block RAM
  // ==================================================================

  // ── ROM: 8K × 8 ──
  (* ram_style = "block" *) logic [7:0] rom [RomDepth];
  logic [7:0] rom_a_dout;  // Port A (Z80 read)
  logic [7:0] rom_b_dout;  // Port B (PS read)

  // ── RAM: 56K × 8 ──
  // The PS-side address is an offset from the Z80 RAM base (0x2000).
  (* ram_style = "block" *) logic [7:0] ram [RamDepth];
  logic [7:0] ram_a_dout;  // Port A (Z80 read/write)
  logic [7:0] ram_b_dout;  // Port B (PS read/write)

  // PS strobe edge detection
  logic gp1_wr_d, gp1_rd_d;
  logic gp2_wr_d, gp2_rd_d;

  // ==================================================================
  // Port A: Z80 Wishbone master access
  // ==================================================================
  // ROM Port A: read-only for the Z80
  always_ff @(posedge clk_i) begin
    rom_a_dout <= rom[wbm_adr_o[12:0]];
  end

  // RAM Port A: read/write via Wishbone.  The physical RAM starts at Z80
  // address 0x2000, so translate the CPU address to a zero-based RAM index.
  wire [15:0] ram_a_addr = wbm_adr_o - 16'h2000;
  always_ff @(posedge clk_i) begin
    if (is_ram)
      ram_a_dout <= ram[ram_a_addr];
    else
      ram_a_dout <= 8'h00;
    if (wb_valid && is_ram && wbm_we_o)
      ram[ram_a_addr] <= wbm_dat_o;
  end

  // ==================================================================
  // Port B: PS access via ctrl_gp1 (RAM) and ctrl_gp2 (ROM)
  // ==================================================================
  // ROM Port B: PS writes program bytes, reads for verification
  always_ff @(posedge clk_i) begin
    rom_b_dout <= rom[ctrl_gp2_out[12:0]];
    if (ctrl_gp2_out[24] && !gp2_wr_d)
      rom[ctrl_gp2_out[12:0]] <= ctrl_gp2_out[23:16];
  end

  // RAM Port B: PS writes/reads data.  GP1 addresses are zero-based RAM
  // offsets; reject offsets above 0xDFFF rather than indexing out of range.
  wire ram_b_valid = (ctrl_gp1_out[15:0] < RamDepth);
  always_ff @(posedge clk_i) begin
    if (ram_b_valid)
      ram_b_dout <= ram[ctrl_gp1_out[15:0]];
    else
      ram_b_dout <= 8'h00;
    if (ctrl_gp1_out[24] && !gp1_wr_d && ram_b_valid)
      ram[ctrl_gp1_out[15:0]] <= ctrl_gp1_out[23:16];
  end

  // ==================================================================
  // Wishbone ack generation
  // ==================================================================
  // All slaves have 1-cycle registered ack.
  // I/O ack is delayed until the byte bridge is ready (variable latency).
  logic rom_ack, ram_ack, io_ack;
  logic io_ack_ready;

  always_ff @(posedge clk_i) begin
    rom_ack <= cpu_active && wb_valid && is_rom;
    ram_ack <= cpu_active && wb_valid && is_ram;
    io_ack  <= cpu_active && wb_valid && is_io_cycle && io_ack_ready;
  end

  // I/O ack ready: for OUT (write) wait for tx_ready;
  // for IN (read) wait for rx_valid.
  assign io_ack_ready = wbm_we_o ? io_tx_ready : io_rx_valid;

  // Wishbone data input mux: Z80 reads from whichever slave is active
  always_comb begin
    unique case (1'b1)
      is_rom:      wbm_dat_i = rom_a_dout;
      is_ram:      wbm_dat_i = ram_a_dout;
      is_io_cycle: wbm_dat_i = io_rx_data;
      default:     wbm_dat_i = 8'h00;
    endcase
  end

  assign wbm_ack_i = rom_ack | ram_ack | io_ack;

  // ==================================================================
  // I/O Bridge — Z80 IN/OUT ↔ axis_byte_bridge byte handshake
  // ==================================================================
  //
  // TX: Z80 OUT → byte to axis_byte_bridge → AXI FIFO → Linux
  // RX: Z80 IN  ← byte from axis_byte_bridge ← AXI FIFO ← Linux
  //
  // io_tx_valid is a single-cycle strobe (matches bf2_soc convention).

  logic [7:0] io_tx_data_int;
  logic       io_tx_valid_int;
  // A Wishbone request remains asserted until the registered ack is seen by
  // tv80.  Remember that an OUT request has already been presented so it
  // cannot generate multiple byte-side strobes while waiting for that ack.
  logic       io_tx_issued;

  always_ff @(posedge clk_i or negedge resetq) begin
    if (!resetq) begin
      io_tx_data_int  <= '0;
      io_tx_valid_int <= '0;
      io_tx_issued    <= '0;
    end else begin
      io_tx_valid_int <= '0;  // default: single-cycle pulse

      // Every Z80 instruction has an M1 memory cycle between I/O cycles, so
      // leaving the I/O write request clears the per-request guard.  This
      // also clears it while halted, allowing a later OUT to be issued.
      if (!cpu_active || !wb_valid || !is_io_cycle || !wbm_we_o) begin
        io_tx_issued <= '0;
      end else if (!io_tx_issued && io_tx_ready) begin
        io_tx_data_int  <= wbm_dat_o;
        io_tx_valid_int <= '1;
        io_tx_issued    <= '1;
      end
    end
  end

  assign io_tx_data  = io_tx_data_int;
  assign io_tx_valid = io_tx_valid_int;

  // RX: Z80 reads from PS during an I/O read (IN) cycle
  assign io_rx_ready = wb_valid && is_io_cycle && !wbm_we_o && cpu_active;

  // ==================================================================
  // Debug outputs
  // ==================================================================
  assign debug_pc  = wbm_adr_o;
  assign debug_rsp = 8'h00;  // placeholder

  // ==================================================================
  // PS Register Decoder — read/write handshake
  // ==================================================================
  //
  // ctrl_gp1 — RAM access (same bits as bf2_soc data_ram):
  //   [15:0]   addr (zero-based offset within Z80 RAM at 0x2000)
  //   [23:16]  wdata
  //   [24]     wr_strobe (rising edge → write wdata to ram[addr])
  //   [25]     rd_strobe (rising edge → read ram[addr] → ctrl_gp1_in[7:0])
  //
  // ctrl_gp2 — ROM access (same bits as bf2_soc code_ram):
  //   Same layout as ctrl_gp1.

  logic [7:0] rom_rdata;
  logic       rom_done;
  logic       rom_rd_pending;

  logic [7:0] ram_rdata;
  logic       ram_done;
  logic       ram_rd_pending;

  always_ff @(posedge clk_i or negedge resetq) begin
    if (!resetq) begin
      gp2_wr_d <= '0;
      gp2_rd_d <= '0;
      rom_rdata <= '0;
      rom_done <= '0;
      rom_rd_pending <= '0;
    end else begin
      gp2_wr_d <= ctrl_gp2_out[24];
      gp2_rd_d <= ctrl_gp2_out[25];

      if (ctrl_gp2_out[24] && !gp2_wr_d)
        rom_done <= '1;

      if (ctrl_gp2_out[25] && !gp2_rd_d)
        rom_rd_pending <= '1;
      else if (rom_rd_pending) begin
        rom_rdata <= rom_b_dout;
        rom_done <= '1;
        rom_rd_pending <= '0;
      end

      if (!ctrl_gp2_out[24] && !ctrl_gp2_out[25]) begin
        rom_rd_pending <= '0;
        rom_done <= '0;
      end
    end
  end

  always_ff @(posedge clk_i or negedge resetq) begin
    if (!resetq) begin
      gp1_wr_d <= '0;
      gp1_rd_d <= '0;
      ram_rdata <= '0;
      ram_done <= '0;
      ram_rd_pending <= '0;
    end else begin
      gp1_wr_d <= ctrl_gp1_out[24];
      gp1_rd_d <= ctrl_gp1_out[25];

      if (ctrl_gp1_out[24] && !gp1_wr_d)
        ram_done <= '1;

      if (ctrl_gp1_out[25] && !gp1_rd_d)
        ram_rd_pending <= '1;
      else if (ram_rd_pending) begin
        ram_rdata <= ram_b_dout;
        ram_done <= '1;
        ram_rd_pending <= '0;
      end

      if (!ctrl_gp1_out[24] && !ctrl_gp1_out[25]) begin
        ram_rd_pending <= '0;
        ram_done <= '0;
      end
    end
  end

  // ==================================================================
  // Status output registers — PS reads back CPU state + BRAM data
  // ==================================================================
  always_ff @(posedge clk_i or negedge resetq) begin
    if (!resetq) begin
      ctrl_gp0_in <= '0;
      ctrl_gp1_in <= '0;
      ctrl_gp2_in <= '0;
    end else begin
      ctrl_gp0_in[0]    <= halted;
      ctrl_gp0_in[31:1] <= '0;

      ctrl_gp1_in[7:0]  <= ram_rdata;
      ctrl_gp1_in[8]    <= ram_done;
      ctrl_gp1_in[31:9] <= '0;

      ctrl_gp2_in[7:0]  <= rom_rdata;
      ctrl_gp2_in[8]    <= rom_done;
      ctrl_gp2_in[31:9] <= '0;
    end
  end

  // ==================================================================
  // Simulation initialization — zero-initialize BRAMs
  // ==================================================================
  initial begin
    for (int i = 0; i < RomDepth; i++)
      rom[i] = 8'h00;
    for (int i = 0; i < RamDepth; i++)
      ram[i] = 8'h00;
  end

endmodule
`default_nettype wire
