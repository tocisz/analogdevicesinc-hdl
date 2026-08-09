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
// case_toggle — ASCII case toggle (uppercase ↔ lowercase)
// ==========================================================================
// A simple byte-stream processor used as a test stand-in for bf2_soc in
// the PS↔PL byte-bridge bring-up (doc/AXIS_FIFO_BRIDGE.md).  It presents
// the SAME io_* byte interface as bf2_soc, so the bridge connects to
// either without changes.
//
// Each accepted input byte is XORed with 0x20 (ASCII bit 5): 'A'..'Z'
// become 'a'..'z' and vice versa.  Non-letter characters also get bit 5
// flipped (unconditional 1-bit XOR — by design for a smoke test).
//
// Handshake (matches bf2_soc's io contract, mirror of uart_phy):
//   io_rx_ready — level; drains one byte per cycle while high
//   io_tx_valid — single-cycle strobe, fired only while io_tx_ready=1
//   io_tx_ready — level from the consumer (bridge tx_ready)
//
// Registered 2-cycle pipeline (accept → strobe); io_rx_ready drops while
// a byte is held, so upstream backpressure (M_AXIS TREADY) is loss-free.
// ==========================================================================

module case_toggle (
  input  wire       clk,
  input  wire       reset,        // active high

  // RX from bridge (byte in)
  input  wire [7:0] io_rx_data,
  input  wire       io_rx_valid,
  output wire       io_rx_ready,

  // TX to bridge (byte out)
  output wire [7:0] io_tx_data,
  output wire       io_tx_valid,
  input  wire       io_tx_ready
);

  localparam logic [7:0] XorMask = 8'h20;  // ASCII case bit (bit 5)

  logic       busy;        // holding a byte awaiting TX
  logic [7:0] tx_data_reg;
  logic       tx_valid;    // single-cycle strobe

  assign io_rx_ready = !busy;
  assign io_tx_data  = tx_data_reg;
  assign io_tx_valid = tx_valid;

  always_ff @(posedge clk) begin
    if (reset) begin
      busy        <= 1'b0;
      tx_data_reg <= 8'd0;
      tx_valid    <= 1'b0;
    end else begin
      tx_valid <= 1'b0;  // default: strobe off
      if (busy) begin
        if (io_tx_ready) begin
          tx_valid <= 1'b1;  // fire strobe; consumer captures this cycle
          busy     <= 1'b0;
        end
      end else if (io_rx_valid) begin
        tx_data_reg <= io_rx_data ^ XorMask;
        busy        <= 1'b1;
      end
    end
  end

endmodule
`default_nettype wire
// vim:ts=2 sw=2 tw=120 et
