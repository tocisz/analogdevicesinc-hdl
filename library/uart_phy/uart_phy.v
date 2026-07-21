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
// Extracted from echo_char.v: baud-rate generator, UART RX (8× oversampling
// FSM), 16-entry sync FIFO, and UART TX FSM — exposed as a clean parallel
// byte-stream interface with no transformation logic.
//
// RX path:  serial → RX FSM → FIFO → rx_data/rx_valid
// TX path:  tx_data + tx_start → TX FSM → serial
//
// Parameters:
//   CLK_FREQ   — System clock frequency (Hz)
//   BAUD       — UART baud rate
//   FIFO_DEPTH — Depth of RX FIFO (must be power of 2, default 16)
// ==========================================================================

module uart_phy #(
  parameter CLK_FREQ   = 100000000,
  parameter BAUD       = 115200,
  parameter FIFO_DEPTH = 16
) (
  input  wire       clk,
  input  wire       reset,

  // Serial interface
  input  wire       uart_rx_i,
  output wire       uart_tx_o,

  // RX parallel output (from FIFO)
  output reg  [7:0] rx_data,
  output reg        rx_valid,
  output wire       rx_ready,
  input  wire       rx_accept_i,

  // TX parallel input
  input  wire [7:0] tx_data,
  input  wire       tx_start,
  output wire       tx_busy
);

  // ------------------------------------------------------------------
  // Constants
  // ------------------------------------------------------------------
  // RX uses 8x oversampling: baud_tick_en strobes 8 times per bit
  localparam BAUD_TICK_CNT = (CLK_FREQ / (BAUD * 8)) - 1;
  // TX uses 1x baud rate
  localparam BAUD_DIV_CNT  = (CLK_FREQ / BAUD) - 1;

  // ------------------------------------------------------------------
  // Baud-rate tick generators
  // ------------------------------------------------------------------
  reg [15:0] baud_tick_cnt;
  reg        baud_tick_en;
  reg [15:0] baud_div_cnt;
  reg        baud_tx_en;

  always @(posedge clk) begin
    if (reset) begin
      baud_tick_cnt <= 0;
      baud_tick_en  <= 1'b0;
      baud_div_cnt  <= 0;
      baud_tx_en    <= 1'b0;
    end else begin
      // 8x oversampling tick (for RX)
      if (baud_tick_cnt >= BAUD_TICK_CNT) begin
        baud_tick_cnt <= 0;
        baud_tick_en  <= 1'b1;
      end else begin
        baud_tick_cnt <= baud_tick_cnt + 1'b1;
        baud_tick_en  <= 1'b0;
      end

      // 1x baud tick (for TX)
      // Reset counter on new transmission start so the start bit
      // always lasts a full baud period regardless of counter phase.
      if (tx_start) begin
        baud_div_cnt <= 0;
        baud_tx_en   <= 1'b0;
      end else if (baud_div_cnt >= BAUD_DIV_CNT) begin
        baud_div_cnt <= 0;
        baud_tx_en   <= 1'b1;
      end else begin
        baud_div_cnt <= baud_div_cnt + 1'b1;
        baud_tx_en   <= 1'b0;
      end
    end
  end

  // ------------------------------------------------------------------
  // Synchroniser for asynchronous uart_rx_i
  // ------------------------------------------------------------------
  reg uart_in_sync0, uart_in_sync1;
  always @(posedge clk) begin
    uart_in_sync0 <= uart_rx_i;
    uart_in_sync1 <= uart_in_sync0;
  end

  // ------------------------------------------------------------------
  // UART Receiver (8x oversampling)
  // ------------------------------------------------------------------
  localparam RX_IDLE  = 0;
  localparam RX_START = 1;
  localparam RX_DATA  = 2;
  localparam RX_STOP  = 3;

  reg [2:0] rx_state;
  reg [3:0] rx_sample_cnt;   // counts oversamples within a bit
  reg [3:0] rx_bit_cnt;      // which bit we are receiving (0-7)
  reg [7:0] rx_shift_reg;
  reg [7:0] rx_byte;
  reg       rx_byte_valid;

  always @(posedge clk) begin
    if (reset) begin
      rx_state      <= RX_IDLE;
      rx_sample_cnt <= 0;
      rx_bit_cnt    <= 0;
      rx_shift_reg  <= 0;
      rx_byte       <= 0;
      rx_byte_valid <= 1'b0;
    end else begin
      rx_byte_valid <= 1'b0;   // default: single-cycle strobe

      case (rx_state)
        RX_IDLE: begin
          rx_sample_cnt <= 0;
          rx_bit_cnt    <= 0;
          rx_shift_reg  <= 0;  // clear stale data between receptions
          // Wait for falling edge (start bit)
          if (baud_tick_en && !uart_in_sync1)
            rx_state <= RX_START;
        end

        RX_START: begin
          if (baud_tick_en) begin
            if (rx_sample_cnt == 4) begin
              // Sample at centre of start bit; confirm it is still low
              if (!uart_in_sync1) begin
                rx_sample_cnt <= 0;
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
              rx_shift_reg <= {uart_in_sync1, rx_shift_reg[7:1]};
              rx_sample_cnt <= 0;
              if (rx_bit_cnt == 7) begin
                rx_bit_cnt <= 0;
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
              rx_sample_cnt <= 0;
              rx_state      <= RX_IDLE;
            end else begin
              rx_sample_cnt <= rx_sample_cnt + 1'b1;
            end
          end
        end
      endcase
    end
  end

  // ------------------------------------------------------------------
  // FIFO buffer (16 × 8) — between RX and rx_data port
  // ------------------------------------------------------------------
  // Buffers received bytes so the consumer can drain them at its own
  // pace.  Without this, back-to-back bytes would be lost if the
  // consumer is busy when a new byte arrives.
  reg [7:0] fifo_mem [0:FIFO_DEPTH-1];
  reg [$clog2(FIFO_DEPTH):0] fifo_wr_ptr;  // MSB disambiguates empty vs full
  reg [$clog2(FIFO_DEPTH):0] fifo_rd_ptr;
  wire fifo_empty = (fifo_wr_ptr == fifo_rd_ptr);
  wire fifo_full  = (fifo_wr_ptr[$clog2(FIFO_DEPTH)-1:0] == fifo_rd_ptr[$clog2(FIFO_DEPTH)-1:0]) &&
                    (fifo_wr_ptr[$clog2(FIFO_DEPTH)]   != fifo_rd_ptr[$clog2(FIFO_DEPTH)]);

  // Write: on rx_byte_valid, drop silently if full
  always @(posedge clk) begin
    if (reset) begin
      fifo_wr_ptr <= 0;
    end else if (rx_byte_valid && !fifo_full) begin
      fifo_mem[fifo_wr_ptr[$clog2(FIFO_DEPTH)-1:0]] <= rx_byte;
      fifo_wr_ptr <= fifo_wr_ptr + 1'b1;
    end
  end

  // Read: pop only when consumer is ready (rx_accept_i high).
  // When the consumer is not ready, rx_valid holds its value
  // to prevent data loss (backpressure).
  always @(posedge clk) begin
    if (reset) begin
      fifo_rd_ptr <= 0;
      rx_data     <= 0;
      rx_valid    <= 1'b0;
    end else begin
      if (rx_valid && rx_accept_i) begin
        // Consumer accepted the current byte — advance or clear
        if (!fifo_empty) begin
          rx_data  <= fifo_mem[fifo_rd_ptr[$clog2(FIFO_DEPTH)-1:0]];
          rx_valid <= 1'b1;
          fifo_rd_ptr <= fifo_rd_ptr + 1'b1;
        end else begin
          rx_valid <= 1'b0;
        end
      end else if (!rx_valid && !fifo_empty && rx_accept_i) begin
        // No byte currently presented; pop the next one
        rx_data  <= fifo_mem[fifo_rd_ptr[$clog2(FIFO_DEPTH)-1:0]];
        rx_valid <= 1'b1;
        fifo_rd_ptr <= fifo_rd_ptr + 1'b1;
      end
      // else: rx_valid=1 and rx_accept_i=0 → stall, hold data
    end
  end

  assign rx_ready = !fifo_full;

  // ------------------------------------------------------------------
  // UART Transmitter
  // ------------------------------------------------------------------
  localparam TX_IDLE  = 0;
  localparam TX_START = 1;
  localparam TX_DATA  = 2;
  localparam TX_STOP  = 3;

  reg [2:0] tx_state;
  reg [3:0] tx_bit_cnt;
  reg [7:0] tx_shift_reg;
  reg       uart_tx_o_int;
  reg       tx_busy_int;
  reg       tx_baud_done;  // set when baud_tx_en seen, cleared on state change

  always @(posedge clk) begin
    if (reset) begin
      tx_state      <= TX_IDLE;
      tx_bit_cnt    <= 0;
      tx_shift_reg  <= 0;
      uart_tx_o_int <= 1'b1;  // idle = high
      tx_busy_int   <= 1'b0;
      tx_baud_done  <= 1'b0;
    end else begin
      tx_busy_int <= 1'b0;  // default unless actively sending

      // Latch baud_tx_en — cleared when state changes
      if (baud_tx_en)
        tx_baud_done <= 1'b1;

      case (tx_state)
        TX_IDLE: begin
          uart_tx_o_int <= 1'b1;
          tx_baud_done  <= 1'b0;
          if (tx_start) begin
            tx_shift_reg  <= tx_data;
            tx_bit_cnt    <= 0;
            tx_state      <= TX_START;
            tx_busy_int   <= 1'b1;
            tx_baud_done  <= 1'b0;  // start fresh in new state
          end
        end

        TX_START: begin
          uart_tx_o_int <= 1'b0;  // start bit (low)
          tx_busy_int   <= 1'b1;
          if (tx_baud_done) begin
            tx_state      <= TX_DATA;
            tx_baud_done  <= 1'b0;
          end
        end

        TX_DATA: begin
          uart_tx_o_int <= tx_shift_reg[0];  // LSB first
          tx_busy_int   <= 1'b1;
          if (tx_baud_done) begin
            tx_shift_reg <= {1'b0, tx_shift_reg[7:1]};
            if (tx_bit_cnt == 7) begin
              tx_bit_cnt   <= 0;
              tx_state     <= TX_STOP;
            end else begin
              tx_bit_cnt   <= tx_bit_cnt + 1'b1;
            end
            tx_baud_done  <= 1'b0;
          end
        end

        TX_STOP: begin
          uart_tx_o_int <= 1'b1;  // stop bit (high)
          tx_busy_int   <= 1'b1;
          if (tx_baud_done) begin
            tx_state      <= TX_IDLE;
            tx_baud_done  <= 1'b0;
          end
        end
      endcase
    end
  end

  assign uart_tx_o = uart_tx_o_int;
  assign tx_busy   = tx_busy_int;

endmodule
`default_nettype wire
// vim:ts=2 sw=2 tw=120 et
