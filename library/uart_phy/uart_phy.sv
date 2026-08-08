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
// uart_phy — Reusable UART PHY with parallel byte-stream interface
// ==========================================================================
// Composed from uart_rx (8× oversampling receiver), fifo_sync (RX buffer),
// and uart_tx (1× transmitter) — exposed as a clean parallel byte-stream
// interface with no transformation logic.
//
// RX path:  serial → uart_rx → fifo_sync → rx_data/rx_valid
// TX path:  tx_data + tx_start → uart_tx → serial
//
// The FIFO's holding-register presentation lives here: a byte is popped
// only while the consumer is ready (rx_accept_i), rx_valid stays high
// while a byte is presented but not yet accepted, and rx_ready reflects
// free FIFO space.
//
// Parameters:
//   ClkFreq   — System clock frequency (Hz)
//   Baud      — UART baud rate
//   FifoDepth — Depth of RX FIFO (must be power of 2, default 16)
// ==========================================================================

module uart_phy #(
    parameter int ClkFreq   = 100000000,
    parameter int Baud      = 115200,
    parameter int FifoDepth = 16
) (
    input  wire clk,
    input  wire reset,

    // Serial interface
    input  wire uart_rx_i,
    output wire uart_tx_o,

    // RX parallel output (from FIFO)
    output wire [7:0] rx_data,
    output reg        rx_valid,
    output wire       rx_ready,
    input  wire       rx_accept_i,

    // TX parallel input
    input  wire [7:0] tx_data,
    input  wire       tx_start,
    output wire       tx_ready   // high when idle; can accept a byte
);

  // ------------------------------------------------------------------
  // UART receiver
  // ------------------------------------------------------------------
  logic [7:0] rx_byte;
  logic       rx_byte_valid;

  uart_rx #(
      .ClkFreq(ClkFreq),
      .Baud(Baud)
  ) u_rx (
      .clk           (clk),
      .reset         (reset),
      .uart_rx_i     (uart_rx_i),
      .rx_byte       (rx_byte),
      .rx_byte_valid (rx_byte_valid)
  );

  // ------------------------------------------------------------------
  // RX FIFO (FifoDepth × 8) — buffers received bytes so the consumer
  // can drain them at its own pace.  Without this, back-to-back bytes
  // would be lost if the consumer is busy when a new byte arrives.
  // ------------------------------------------------------------------
  logic [7:0] fifo_dout;
  logic       fifo_empty;
  logic       fifo_full;
  logic       fifo_rd_en;

  fifo_sync #(
      .DataWidth(8),
      .Depth(FifoDepth)
  ) u_fifo (
      .clk     (clk),
      .reset   (reset),
      .wr_en   (rx_byte_valid),
      .wr_data (rx_byte),
      .rd_en   (fifo_rd_en),
      .rd_data (fifo_dout),
      .empty   (fifo_empty),
      .full    (fifo_full)
  );

  // Consumer handshake: pop only when the consumer is ready; while a byte
  // is presented (rx_valid=1) and rx_accept_i is low, hold it (backpressure
  // at FIFO-full, not at the presented byte).
  assign fifo_rd_en = rx_accept_i && !fifo_empty;
  assign rx_data    = fifo_dout;
  assign rx_ready   = !fifo_full;

  always_ff @(posedge clk) begin
    if (reset) begin
      rx_valid <= 1'b0;
    end else if (fifo_rd_en) begin
      rx_valid <= 1'b1;
    end else begin
      // Hold while not accepted; clear once accepted with nothing to pop
      rx_valid <= rx_valid && !rx_accept_i;
    end
  end

  // ------------------------------------------------------------------
  // UART transmitter
  // ------------------------------------------------------------------
  uart_tx #(
      .ClkFreq(ClkFreq),
      .Baud(Baud)
  ) u_tx (
      .clk      (clk),
      .reset    (reset),
      .tx_data  (tx_data),
      .tx_start (tx_start),
      .tx_ready (tx_ready),
      .uart_tx_o(uart_tx_o)
  );

endmodule
`default_nettype wire
// vim:ts=2 sw=2 tw=120 et
