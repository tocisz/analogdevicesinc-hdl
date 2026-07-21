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
// char_add_one — Reusable byte-stream transform: c → c+1
// ==========================================================================
// A simple registered pipeline stage that adds 1 to each input byte.
// Not part of the final bf1 data path — used only for testing the
// uart_phy integration and as a smoke-test stand-in for any byte-stream
// processor.
//
// Registered (1-cycle latency) to avoid adding combinational paths
// between modules.
// ==========================================================================

module char_add_one (
  input  wire       clk,
  input  wire       reset,

  input  wire [7:0] data_in,
  input  wire       data_in_valid,

  output reg  [7:0] data_out,
  output reg        data_out_valid
);

  always @(posedge clk) begin
    if (reset) begin
      data_out       <= 8'd0;
      data_out_valid <= 1'b0;
    end else begin
      data_out       <= data_in + 1'b1;
      data_out_valid <= data_in_valid;
    end
  end

endmodule
`default_nettype wire
// vim:ts=2 sw=2 tw=120 et
