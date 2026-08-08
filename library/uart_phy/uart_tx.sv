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
// uart_tx — UART transmitter (1× baud rate)
// ==========================================================================
// Submodule of uart_phy: baud-rate tick generator (1×) with phase reset
// on a new transmission, and the TX FSM.  tx_ready is high while idle;
// a tx_start strobe (asserted only while tx_ready) loads tx_data and
// transmits it LSB-first.
//
// Parallel: tx_data + tx_start (single-cycle strobe), tx_ready (idle)
// Serial:   uart_tx_o (idle = high)
//
// Parameters:
//   ClkFreq — System clock frequency (Hz)
//   Baud    — UART baud rate
// ==========================================================================

module uart_tx #(
    parameter int ClkFreq = 100000000,
    parameter int Baud    = 115200
) (
    input  wire clk,
    input  wire reset,

    // Parallel input
    input  wire [7:0] tx_data,
    input  wire       tx_start,
    output wire       tx_ready,  // high when idle; can accept a byte

    // Serial interface
    output wire uart_tx_o
);

  // ------------------------------------------------------------------
  // Constants
  // ------------------------------------------------------------------
  // TX uses 1x baud rate
  localparam int BaudDivCnt  = (ClkFreq / Baud) - 1;
  localparam int BaudDivCntW = $clog2(BaudDivCnt + 1);  // counter width

  // ------------------------------------------------------------------
  // Baud-rate tick generator (1× baud rate)
  // ------------------------------------------------------------------
  // Reset counter on new transmission start so the start bit
  // always lasts a full baud period regardless of counter phase.
  logic [BaudDivCntW-1:0] baud_div_cnt;
  logic                   baud_tx_en;

  always_ff @(posedge clk) begin
    if (reset) begin
      baud_div_cnt <= '0;
      baud_tx_en   <= 1'b0;
    end else if (tx_start) begin
      baud_div_cnt <= '0;
      baud_tx_en   <= 1'b0;
    end else if (baud_div_cnt >= BaudDivCnt[BaudDivCntW-1:0]) begin
      baud_div_cnt <= '0;
      baud_tx_en   <= 1'b1;
    end else begin
      baud_div_cnt <= baud_div_cnt + 1'b1;
      baud_tx_en   <= 1'b0;
    end
  end

  // ------------------------------------------------------------------
  // Transmitter FSM
  // ------------------------------------------------------------------
  typedef enum logic [1:0] {
    TX_IDLE  = 2'd0,
    TX_START = 2'd1,
    TX_DATA  = 2'd2,
    TX_STOP  = 2'd3
  } tx_state_t;

  tx_state_t tx_state;

  logic [3:0] tx_bit_cnt;
  logic [7:0] tx_shift_reg;
  logic       uart_tx_o_int;
  logic       tx_baud_done;  // set when baud_tx_en seen, cleared on state change

  always_ff @(posedge clk) begin
    if (reset) begin
      tx_state      <= TX_IDLE;
      tx_bit_cnt    <= '0;
      tx_shift_reg  <= '0;
      uart_tx_o_int <= 1'b1;  // idle = high
      tx_baud_done  <= 1'b0;
    end else begin
      // Latch baud_tx_en — cleared when state changes
      if (baud_tx_en) tx_baud_done <= 1'b1;

      unique case (tx_state)
        TX_IDLE: begin
          uart_tx_o_int <= 1'b1;
          tx_baud_done  <= 1'b0;
          if (tx_start) begin
            tx_shift_reg <= tx_data;
            tx_bit_cnt   <= '0;
            tx_state     <= TX_START;
            tx_baud_done <= 1'b0;  // start fresh in new state
          end
        end

        TX_START: begin
          uart_tx_o_int <= 1'b0;  // start bit (low)
          if (tx_baud_done) begin
            tx_state     <= TX_DATA;
            tx_baud_done <= 1'b0;
          end
        end

        TX_DATA: begin
          uart_tx_o_int <= tx_shift_reg[0];  // LSB first
          if (tx_baud_done) begin
            tx_shift_reg <= {1'b0, tx_shift_reg[7:1]};
            if (tx_bit_cnt == 7) begin
              tx_bit_cnt <= '0;
              tx_state   <= TX_STOP;
            end else begin
              tx_bit_cnt <= tx_bit_cnt + 1'b1;
            end
            tx_baud_done <= 1'b0;
          end
        end

        TX_STOP: begin
          uart_tx_o_int <= 1'b1;  // stop bit (high)
          if (tx_baud_done) begin
            tx_state     <= TX_IDLE;
            tx_baud_done <= 1'b0;
          end
        end
      endcase
    end
  end

  assign uart_tx_o = uart_tx_o_int;
  assign tx_ready  = (tx_state == TX_IDLE);

endmodule
`default_nettype wire
// vim:ts=2 sw=2 tw=120 et
