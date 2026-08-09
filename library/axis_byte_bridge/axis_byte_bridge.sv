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
// axis_byte_bridge — PS↔PL byte-stream bridge over a 32-bit AXI-Stream FIFO
// ==========================================================================
// v1 ("drop-24"): each 32-bit stream word carries ONE byte in bits [7:0];
// the upper 24 bits are dropped on the PS→PL path and driven to 0 on the
// PL→PS path.  No pack/unpack logic — the simplest correct adapter.
//
//   PS→PL (M_AXIS slave, from axi_fifo_mm_s):
//     Pure combinational pass-through of the low byte.  The transfer
//     completes only when m_axis_tvalid && m_axis_tready (== rx_accept)
//     coincide, so rx_accept dropping mid-word just defers the transfer —
//     loss-free, no FIFO, no state.
//
//   PL→PS (S_AXIS master, to axi_fifo_mm_s):
//     1-deep staging register.  io_tx_valid is a single-cycle strobe and
//     s_axis_tready may be low exactly when it fires (RX FIFO just filled),
//     so capture every strobe and hold it on S_AXIS until tready.  tx_ready
//     mirrors s_axis_tready; the byte source (bf2_soc / case_toggle) stalls
//     while io_wr_pending && !io_tx_ready, so while the stage is blocked no
//     new byte can arrive.  TLAST is asserted per word (one word = one
//     packet, RLR per byte).
//
// The byte-side contract mirrors uart_phy's parallel interface (and
// bf2_soc's io_rx_* / io_tx_* handshake):
//   rx_accept  — level; drains one byte per cycle while high
//   tx_valid   — single-cycle strobe
//
// See doc/AXIS_FIFO_BRIDGE.md for the full design (v2 byte-packer deferred).
// ==========================================================================

module axis_byte_bridge (
  input  wire        clk,          // sys_cpu_clk
  input  wire        reset,        // active high

  // M_AXIS slave (PS→PL, from axi_fifo_mm_s)
  /* verilator lint_off UNUSEDSIGNAL */ // upper 24 bits dropped / tlast ignored in v1
  input  wire        m_axis_tvalid,
  output wire        m_axis_tready,
  input  wire [31:0] m_axis_tdata,
  input  wire        m_axis_tlast,
  /* verilator lint_on UNUSEDSIGNAL */

  // S_AXIS master (PL→PS, to axi_fifo_mm_s)
  output wire        s_axis_tvalid,
  input  wire        s_axis_tready,
  output wire [31:0] s_axis_tdata,
  output wire        s_axis_tlast,

  // Byte side (bf2_soc io_rx_* / io_tx_* semantics)
  output wire [7:0]  rx_data,      // → io_rx_data
  output wire        rx_valid,     // → io_rx_valid
  input  wire        rx_accept,    // ← io_rx_ready (drain level)
  input  wire [7:0]  tx_data,      // ← io_tx_data
  input  wire        tx_valid,     // ← io_tx_valid (single-cycle strobe)
  output wire        tx_ready      // → io_tx_ready
);

  // ── PS→PL: pass-through of the low byte; upper 24 bits dropped. ──
  assign rx_data       = m_axis_tdata[7:0];
  assign rx_valid      = m_axis_tvalid;
  assign m_axis_tready = rx_accept;

  // ── PL→PS: 1-deep staging register. ──
  logic       tx_stage_valid;
  logic [7:0] tx_stage_data;

  assign s_axis_tdata  = {24'd0, tx_stage_data};
  assign s_axis_tvalid = tx_stage_valid;
  assign s_axis_tlast  = 1'b1;  // one word = one packet (RLR per byte)
  assign tx_ready      = s_axis_tready;

  always_ff @(posedge clk) begin
    if (reset) begin
      tx_stage_valid <= 1'b0;
    end else begin
      if (tx_valid) begin
        tx_stage_data  <= tx_data;
        tx_stage_valid <= 1'b1;  // overwrite: strobe always wins
      end else if (s_axis_tready) begin
        tx_stage_valid <= 1'b0;  // drained
      end
    end
  end

endmodule
`default_nettype wire
// vim:ts=2 sw=2 tw=120 et
