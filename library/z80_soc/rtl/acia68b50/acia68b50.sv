`default_nettype none
`timescale 1 ns / 1 ps

// ==========================================================================
// acia68b50 — Motorola MC68B50-compatible ACIA
// ==========================================================================
// Register map (RS = address bit 0):
//   RS=0  Control (write) / Status (read)
//   RS=1  Data (write/read)
//
// TX: a Z80 data-register write captures one byte.  tx_valid is a
// single-cycle strobe issued only while tx_ready is high (immediate or
// deferred).  TDRE is 0 while a byte is waiting, 1 once it has been
// handed to the bridge.
//
// RX: a Z80 data-register read consumes one byte from the bridge.
//
// cs stays asserted until ack is seen, so each access is handled on the
// rising edge of cs only (same reason the raw I/O path has io_tx_issued).
// ==========================================================================

module acia68b50 (
  input  wire       clk,
  input  wire       reset,         // active high, synchronous

  input  wire       cs,
  input  wire       rs,            // 0=CR/SR, 1=Data
  input  wire       r_nw,          // 1=read, 0=write
  input  wire [7:0] data_in,
  output reg  [7:0] data_out,
  output reg        ack,

  output wire       irq,

  input  wire [7:0] rx_byte,
  input  wire       rx_valid,
  output reg        rx_consume,
  output reg  [7:0] tx_byte,
  output reg        tx_valid,
  input  wire       tx_ready
);

  // Control register
  reg [1:0] cr_clock_div;
  /* verilator lint_off UNUSEDSIGNAL */
  reg [2:0] cr_word_sel;    // stored for compatibility; unused in FIFO mode
  /* verilator lint_on UNUSEDSIGNAL */
  reg [1:0] cr_tx_ctrl;
  reg       cr_rx_int_en;

  // Status bits
  reg sr_rdrf;
  reg sr_tdre;
  reg sr_dcd;
  reg sr_cts;
  reg sr_fe;
  reg sr_ovrn;
  reg sr_pe;

  // TX holding register (occupied while waiting for tx_ready)
  reg [7:0] tx_hold;
  reg       tx_hold_valid;

  // cs edge detect — process each bus cycle once
  reg cs_d;
  wire cs_rise = cs && !cs_d;

  wire irq_tx = (cr_tx_ctrl == 2'b01) && sr_tdre;
  wire irq_rx = cr_rx_int_en && sr_rdrf;
  assign irq = irq_tx || irq_rx;

  wire [7:0] status = {
    irq,
    sr_pe,
    sr_ovrn,
    sr_fe,
    sr_cts,
    sr_dcd,
    sr_tdre,
    (sr_rdrf || rx_valid)
  };

  wire wr_data = cs_rise && !r_nw && rs && sr_tdre && !tx_hold_valid;

  always_ff @(posedge clk) begin
    if (reset) begin
      cr_clock_div   <= 2'b00;
      cr_word_sel    <= 3'b000;
      cr_tx_ctrl     <= 2'b00;
      cr_rx_int_en   <= 1'b0;
      sr_rdrf        <= 1'b0;
      sr_tdre        <= 1'b1;
      sr_dcd         <= 1'b0;
      sr_cts         <= 1'b0;
      sr_fe          <= 1'b0;
      sr_ovrn        <= 1'b0;
      sr_pe          <= 1'b0;
      tx_hold        <= 8'h00;
      tx_hold_valid  <= 1'b0;
      cs_d           <= 1'b0;
      data_out       <= 8'h00;
      ack            <= 1'b0;
      tx_valid       <= 1'b0;
      tx_byte        <= 8'h00;
      rx_consume     <= 1'b0;
    end else begin
      cs_d       <= cs;
      tx_valid   <= 1'b0;
      rx_consume <= 1'b0;
      ack        <= cs;

      // Drain a previously deferred TX byte.
      if (tx_hold_valid && tx_ready) begin
        tx_byte       <= tx_hold;
        tx_valid      <= 1'b1;
        tx_hold_valid <= 1'b0;
        sr_tdre       <= 1'b1;
      end

      if (cs_rise) begin
        if (r_nw) begin
          if (rs) begin
            if (rx_valid) begin
              data_out   <= rx_byte;
              rx_consume <= 1'b1;
              sr_rdrf    <= 1'b0;
              sr_ovrn    <= 1'b0;
            end else begin
              data_out <= 8'h00;
              sr_rdrf  <= 1'b0;
            end
          end else begin
            data_out <= status;
          end
        end else if (rs) begin
          // Write data register
          if (wr_data) begin
            if (tx_ready) begin
              tx_byte       <= data_in;
              tx_valid      <= 1'b1;
              tx_hold_valid <= 1'b0;
              sr_tdre       <= 1'b1;
            end else begin
              tx_hold       <= data_in;
              tx_hold_valid <= 1'b1;
              sr_tdre       <= 1'b0;
            end
          end
        end else begin
          // Write control register
          cr_clock_div <= data_in[1:0];
          cr_word_sel  <= data_in[4:2];
          cr_tx_ctrl   <= data_in[6:5];
          cr_rx_int_en <= data_in[7];

          if (data_in[1:0] == 2'b00) begin
            sr_rdrf       <= 1'b0;
            sr_tdre       <= 1'b1;
            sr_ovrn       <= 1'b0;
            sr_fe         <= 1'b0;
            sr_pe         <= 1'b0;
            tx_hold_valid <= 1'b0;
          end
        end
      end

      if (rx_valid && sr_rdrf && !(cs_rise && r_nw && rs))
        sr_ovrn <= 1'b1;
    end
  end

endmodule
`default_nettype wire
