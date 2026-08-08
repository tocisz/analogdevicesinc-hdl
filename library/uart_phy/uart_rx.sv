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
// uart_rx — UART receiver (8× oversampling)
// ==========================================================================
// Submodule of uart_phy: baud-rate tick generator (8× oversampling),
// 2-FF synchronizer for the asynchronous serial input, and the RX FSM.
// Emits a byte with a single-cycle rx_byte_valid strobe; framing errors
// are silently discarded.
//
// Serial:  uart_rx_i (idle = high)
// Parallel: rx_byte + rx_byte_valid (single-cycle strobe)
//
// Parameters:
//   ClkFreq — System clock frequency (Hz)
//   Baud    — UART baud rate
// ==========================================================================

module uart_rx #(
    parameter int ClkFreq = 100000000,
    parameter int Baud    = 115200
) (
    input  wire clk,
    input  wire reset,

    // Serial interface
    input  wire uart_rx_i,

    // Parallel output
    output reg  [7:0] rx_byte,
    output reg        rx_byte_valid  // single-cycle strobe
);

  // ------------------------------------------------------------------
  // Constants
  // ------------------------------------------------------------------
  // 8x oversampling: baud_tick_en strobes 8 times per bit
  localparam int BaudTickCnt  = (ClkFreq / (Baud * 8)) - 1;
  localparam int BaudTickCntW = $clog2(BaudTickCnt + 1);  // counter width

  // ------------------------------------------------------------------
  // Baud-rate tick generator (8× oversampling)
  // ------------------------------------------------------------------
  logic [BaudTickCntW-1:0] baud_tick_cnt;
  logic                    baud_tick_en;

  always_ff @(posedge clk) begin
    if (reset) begin
      baud_tick_cnt <= '0;
      baud_tick_en  <= 1'b0;
    end else begin
      if (baud_tick_cnt >= BaudTickCnt[BaudTickCntW-1:0]) begin
        baud_tick_cnt <= '0;
        baud_tick_en  <= 1'b1;
      end else begin
        baud_tick_cnt <= baud_tick_cnt + 1'b1;
        baud_tick_en  <= 1'b0;
      end
    end
  end

  // ------------------------------------------------------------------
  // Synchroniser for asynchronous uart_rx_i
  // ------------------------------------------------------------------
  logic uart_in_sync0, uart_in_sync1;
  always_ff @(posedge clk) begin
    if (reset) begin
      uart_in_sync0 <= 1'b1;  // UART idle state = high
      uart_in_sync1 <= 1'b1;
    end else begin
      uart_in_sync0 <= uart_rx_i;
      uart_in_sync1 <= uart_in_sync0;
    end
  end

  // ------------------------------------------------------------------
  // Receiver FSM (8× oversampling)
  // ------------------------------------------------------------------
  typedef enum logic [1:0] {
    RX_IDLE  = 2'd0,
    RX_START = 2'd1,
    RX_DATA  = 2'd2,
    RX_STOP  = 2'd3
  } rx_state_t;

  rx_state_t rx_state;

  logic [3:0] rx_sample_cnt;  // counts oversamples within a bit
  logic [3:0] rx_bit_cnt;  // which bit we are receiving (0-7)
  logic [7:0] rx_shift_reg;

  always_ff @(posedge clk) begin
    if (reset) begin
      rx_state      <= RX_IDLE;
      rx_sample_cnt <= '0;
      rx_bit_cnt    <= '0;
      rx_shift_reg  <= '0;
      rx_byte       <= '0;
      rx_byte_valid <= 1'b0;
    end else begin
      rx_byte_valid <= 1'b0;  // default: single-cycle strobe

      unique case (rx_state)
        RX_IDLE: begin
          rx_sample_cnt <= '0;
          rx_bit_cnt    <= '0;
          rx_shift_reg  <= '0;  // clear stale data between receptions
          // Wait for falling edge (start bit)
          if (baud_tick_en && !uart_in_sync1) rx_state <= RX_START;
        end

        RX_START: begin
          if (baud_tick_en) begin
            if (rx_sample_cnt == 4) begin
              // Sample at centre of start bit; confirm it is still low
              if (!uart_in_sync1) begin
                rx_sample_cnt <= '0;
                rx_state      <= RX_DATA;
              end else begin
                // Glitch — return to idle
                rx_state <= RX_IDLE;
              end
            end else begin
              rx_sample_cnt <= rx_sample_cnt + 1'b1;
            end
          end
        end

        RX_DATA: begin
          if (baud_tick_en) begin
            if (rx_sample_cnt == 7) begin
              // Sample at centre of data bit
              rx_shift_reg  <= {uart_in_sync1, rx_shift_reg[7:1]};
              rx_sample_cnt <= '0;
              if (rx_bit_cnt == 7) begin
                rx_bit_cnt <= '0;
                rx_state   <= RX_STOP;
              end else begin
                rx_bit_cnt <= rx_bit_cnt + 1'b1;
              end
            end else begin
              rx_sample_cnt <= rx_sample_cnt + 1'b1;
            end
          end
        end

        RX_STOP: begin
          if (baud_tick_en) begin
            if (rx_sample_cnt == 7) begin
              // Sample stop bit (should be high)
              if (uart_in_sync1) begin
                rx_byte       <= rx_shift_reg;
                rx_byte_valid <= 1'b1;
              end
              // else: framing error — discard
              rx_sample_cnt <= '0;
              rx_state      <= RX_IDLE;
            end else begin
              rx_sample_cnt <= rx_sample_cnt + 1'b1;
            end
          end
        end
      endcase
    end
  end

endmodule
`default_nettype wire
// vim:ts=2 sw=2 tw=120 et
