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
// fifo_sync — Synchronous FIFO (single clock domain)
// ==========================================================================
// Simple power-of-2-depth FIFO with registered read output.  A write
// (wr_en) is dropped silently when full; a read (rd_en) is a no-op when
// empty.  rd_data holds the popped word after rd_en, like uart_phy's
// holding-register presentation (the consumer interface lives in the
// parent module).
//
// Parameters:
//   DataWidth — Word width in bits (default 8)
//   Depth     — Number of entries, must be a power of 2 (default 16)
// ==========================================================================

module fifo_sync #(
    parameter int DataWidth = 8,
    parameter int Depth     = 16
) (
    input  wire                clk,
    input  wire                reset,

    // Write side
    input  wire                wr_en,
    input  wire [DataWidth-1:0] wr_data,

    // Read side
    input  wire                rd_en,
    output reg  [DataWidth-1:0] rd_data,
    output wire                empty,
    output wire                full
);

  localparam int AddrBits = $clog2(Depth);

  logic [DataWidth-1:0] fifo_mem[Depth];
  logic [AddrBits:0]    wr_ptr;  // MSB disambiguates empty vs full
  logic [AddrBits:0]    rd_ptr;

  assign empty = (wr_ptr == rd_ptr);
  assign full = (wr_ptr[AddrBits-1:0] == rd_ptr[AddrBits-1:0]) &&
                (wr_ptr[AddrBits] != rd_ptr[AddrBits]);

  // Write: on wr_en, drop silently if full
  always_ff @(posedge clk) begin
    if (reset) begin
      wr_ptr <= '0;
    end else if (wr_en && !full) begin
      fifo_mem[wr_ptr[AddrBits-1:0]] <= wr_data;
      wr_ptr <= wr_ptr + 1'b1;
    end
  end

  // Read: pop on rd_en; no-op when empty
  always_ff @(posedge clk) begin
    if (reset) begin
      rd_ptr  <= '0;
      rd_data <= '0;
    end else if (rd_en && !empty) begin
      rd_data <= fifo_mem[rd_ptr[AddrBits-1:0]];
      rd_ptr  <= rd_ptr + 1'b1;
    end
  end

endmodule
`default_nettype wire
// vim:ts=2 sw=2 tw=120 et
