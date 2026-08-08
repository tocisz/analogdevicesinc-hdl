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
// echo_char — UART loopback with c → c+1 transform
// ==========================================================================
// Rebuilt from library modules: uart_phy + char_add_one.
// External ports and behavior unchanged from the original monolithic
// implementation.
//
// Path:  uart_phy (RX) → char_add_one → uart_phy (TX)
// ==========================================================================

module echo_char #(
  parameter CLK_FREQ = 100000000,
  parameter BAUD     = 115200
) (
  input  wire       clk,
  input  wire       reset,

  input  wire       uart_tx_i,
  output wire       uart_rx_o
);

  // Internal wires
  wire [7:0] rx_data;
  wire       rx_valid;
  wire       rx_ready;

  wire [7:0] add1_data;
  wire       add1_valid;

  wire       tx_ready;
  reg        tx_start;
  reg  [7:0] tx_data;

  // ------------------------------------------------------------------
  // uart_phy — serial ↔ parallel
  // ------------------------------------------------------------------
  // Backpressure: only accept a new byte from the FIFO when the
  // transmit path is free.  This prevents the FIFO from popping
  // data while the TX is busy (which would drop the byte).
  wire rx_accept = tx_ready;

  uart_phy #(
    .ClkFreq(CLK_FREQ),
    .Baud(BAUD)
  ) u_phy (
    .clk(clk),
    .reset(reset),
    .uart_rx_i(uart_tx_i),
    .uart_tx_o(uart_rx_o),
    .rx_data(rx_data),
    .rx_valid(rx_valid),
    .rx_ready(),
    .rx_accept_i(rx_accept),
    .tx_data(tx_data),
    .tx_start(tx_start),
    .tx_ready(tx_ready)
  );

  // ------------------------------------------------------------------
  // char_add_one — c → c+1 transform
  // ------------------------------------------------------------------
  char_add_one u_add1 (
    .clk(clk),
    .reset(reset),
    .data_in(rx_data),
    .data_in_valid(rx_valid),
    .data_out(add1_data),
    .data_out_valid(add1_valid)
  );

  // ------------------------------------------------------------------
  // TX control: start transmission when char_add_one has data and TX is idle
  // ------------------------------------------------------------------
  always @(posedge clk) begin
    if (reset) begin
      tx_start <= 1'b0;
    end else begin
      tx_start <= 1'b0;  // default: single-cycle strobe
      if (add1_valid && tx_ready) begin
        tx_data  <= add1_data;
        tx_start <= 1'b1;
      end
    end
  end

endmodule
`default_nettype wire
// vim:ts=2 sw=2 tw=120 et
