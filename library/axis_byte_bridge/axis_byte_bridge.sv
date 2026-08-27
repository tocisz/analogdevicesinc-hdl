/*

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

*/

`default_nettype none
`timescale 1 ns / 1 ps

// ==========================================================================
// axis_byte_bridge — PS↔PL byte-stream bridge for axi_byte_fifo
// ==========================================================================
// Byte-stream bridge over an 8-bit AXIS FIFO (axi_byte_fifo, DEPTH=1024).
// Replaces v1 drop-24 (32-bit word with 24 bits dropped) — now true 8-bit
// TDATA per beat, no TLAST. See doc/AXI_BYTE_FIFO_PLAN.md.
//
//   PS→PL (M_AXIS slave, from axi_byte_fifo):
//     Pure combinational pass-through of the byte. Transfer completes
//     only when m_axis_tvalid && m_axis_tready (== rx_accept) coincide,
//     so rx_accept dropping mid-beat just defers the transfer — loss-free,
//     no FIFO, no state.
//
//   PL→PS (S_AXIS master, to axi_byte_fifo):
//     1-deep staging register. io_tx_valid is a single-cycle strobe and
//     s_axis_tready may be low exactly when it fires (RX FIFO just filled),
//     so capture every strobe and hold it on S_AXIS until tready. tx_ready
//     mirrors s_axis_tready; the byte source stalls while the stage is
//     blocked, so no new byte can arrive while held.
//
// The byte-side contract mirrors uart_phy's parallel interface:
//   rx_accept  — level; drains one byte per cycle while high
//   tx_valid   — single-cycle strobe
//
// RTS/CTS (z80_soc serBuf flow control):
//   rx_rts_n = 1 (Z80 serBuf ≥48) masks PS→PL (rdrf). PL→PS uses the
//   independent RX FIFO, so its backpressure (tx_ready=s_axis_tready) is CTS.
// ==========================================================================

module axis_byte_bridge (
  input  wire        clk,          // sys_cpu_clk
  input  wire        reset,        // active high

  // M_AXIS slave (PS→PL, from axi_byte_fifo)
  input  wire        m_axis_tvalid,
  output wire        m_axis_tready,
  input  wire [7:0]  m_axis_tdata,

  // S_AXIS master (PL→PS, to axi_byte_fifo)
  output wire        s_axis_tvalid,
  input  wire        s_axis_tready,
  output wire [7:0]  s_axis_tdata,

  // Byte side (z80_soc io_rx_* / io_tx_* semantics)
  output wire [7:0]  rx_data,      // → io_rx_data
  output wire        rx_valid,     // → io_rx_valid
  input  wire        rx_accept,    // ← io_rx_ready (drain level)
  input  wire [7:0]  tx_data,      // ← io_tx_data
  input  wire        tx_valid,     // ← io_tx_valid (single-cycle strobe)
  output wire        tx_ready,     // → io_tx_ready
  input  wire        rx_rts_n      // ← ACIA RTS (1=Z80 serBuf full, stall PS→PL)
);

  // ── PS→PL: pass-through byte; RTS gating both sides.
  // When Z80 firmware asserts RTS (serBuf ≥48), mask RDRF (rx_valid) and
  // stall AXIS handshake. Both gated — gating only tready would leave
  // rx_valid=1 with held byte → spurious RDRF IRQ and duplicate IN.
  assign rx_data       = m_axis_tdata;
  assign rx_valid      = m_axis_tvalid && !rx_rts_n;
  assign m_axis_tready = rx_accept && !rx_rts_n;

  // ── PL→PS: 1-deep staging register. ──
  logic       tx_stage_valid;
  logic [7:0] tx_stage_data;

  assign s_axis_tdata  = tx_stage_data;
  assign s_axis_tvalid = tx_stage_valid;
  assign tx_ready      = s_axis_tready;

  always_ff @(posedge clk) begin
    if (reset) begin
      tx_stage_valid <= 1'b0;
    end else begin
      if (tx_valid) begin
        tx_stage_data  <= tx_data;
        tx_stage_valid <= 1'b1;  // strobe always wins
      end else if (s_axis_tready) begin
        tx_stage_valid <= 1'b0;  // drained
      end
    end
  end

endmodule
`default_nettype wire
// vim:ts=2 sw=2 tw=120 et
