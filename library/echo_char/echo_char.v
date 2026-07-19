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

module echo_char #(
  parameter CLK_FREQ = 100000000,
  parameter BAUD     = 115200
) (
  input  wire       clk,
  input  wire       reset,

  input  wire       uart_tx_i,
  output wire       uart_rx_o
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

  // Forward declaration — used by baud generator to reset on new tx
  reg        tx_start;

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
  // Synchroniser for asynchronous uart_tx_i
  // ------------------------------------------------------------------
  reg uart_in_sync0, uart_in_sync1;
  always @(posedge clk) begin
    uart_in_sync0 <= uart_tx_i;
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
  reg [7:0] rx_data;
  reg       rx_data_valid;

  always @(posedge clk) begin
    if (reset) begin
      rx_state      <= RX_IDLE;
      rx_sample_cnt <= 0;
      rx_bit_cnt    <= 0;
      rx_shift_reg  <= 0;
      rx_data       <= 0;
      rx_data_valid <= 1'b0;
    end else begin
      rx_data_valid <= 1'b0;   // default: single-cycle strobe

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
                rx_data       <= rx_shift_reg;
                rx_data_valid <= 1'b1;
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
  // FIFO buffer (16 × 8) — between RX and TX
  // ------------------------------------------------------------------
  // Without a FIFO, back-to-back bytes cause drops because the TX is
  // still serializing the previous result when the next byte finishes
  // reception.  A single extra buffer slot solves this; 16 entries
  // matches the AXI UART Lite FIFO depth for symmetry.
  reg [7:0] fifo_mem [0:15];
  reg [4:0] fifo_wr_ptr;   // bit [4] disambiguates empty vs full
  reg [4:0] fifo_rd_ptr;
  wire      fifo_empty = (fifo_wr_ptr == fifo_rd_ptr);
  wire      fifo_full  = (fifo_wr_ptr[3:0] == fifo_rd_ptr[3:0]) &&
                         (fifo_wr_ptr[4]   != fifo_rd_ptr[4]);
  reg       tx_busy;   // set by TX FSM, read by FIFO pop logic

  // Write: byte+1 on rx_data_valid, drop silently if full
  always @(posedge clk) begin
    if (reset) begin
      fifo_wr_ptr <= 0;
    end else if (rx_data_valid && !fifo_full) begin
      fifo_mem[fifo_wr_ptr[3:0]] <= rx_data + 1'b1;
      fifo_wr_ptr <= fifo_wr_ptr + 1'b1;
    end
  end

  // Read: pop and start TX when idle and FIFO has data
  reg [7:0] tx_byte;

  always @(posedge clk) begin
    if (reset) begin
      fifo_rd_ptr <= 0;
      tx_byte     <= 0;
      tx_start    <= 1'b0;
    end else begin
      tx_start    <= 1'b0;   // single-cycle strobe
      if (!tx_busy && !fifo_empty) begin
        tx_byte     <= fifo_mem[fifo_rd_ptr[3:0]];
        tx_start    <= 1'b1;
        fifo_rd_ptr <= fifo_rd_ptr + 1'b1;
      end
    end
  end

  // ------------------------------------------------------------------
  // UART Transmitter
  // ------------------------------------------------------------------
  // The state machine avoids same-cycle baud_tx_en transitions by
  // using a level-sensitive approach: each state explicitly outputs its
  // bit and only advances when baud_tx_en is seen HIGH *and* we have
  // not already advanced on this pulse.
  localparam TX_IDLE  = 0;
  localparam TX_START = 1;
  localparam TX_DATA  = 2;
  localparam TX_STOP  = 3;

  reg [2:0] tx_state;
  reg [3:0] tx_bit_cnt;
  reg [7:0] tx_shift_reg;
  reg       uart_rx_o_int;
  reg       tx_baud_done;  // set when baud_tx_en seen, cleared on state change

  always @(posedge clk) begin
    if (reset) begin
      tx_state      <= TX_IDLE;
      tx_bit_cnt    <= 0;
      tx_shift_reg  <= 0;
      uart_rx_o_int <= 1'b1;  // idle = high
      tx_busy       <= 1'b0;
      tx_baud_done  <= 1'b0;
    end else begin
      tx_busy <= 1'b0;  // default unless actively sending

      // Latch baud_tx_en — cleared when state changes
      if (baud_tx_en)
        tx_baud_done <= 1'b1;

      case (tx_state)
        TX_IDLE: begin
          uart_rx_o_int <= 1'b1;
          tx_baud_done  <= 1'b0;
          if (tx_start) begin
            tx_shift_reg  <= tx_byte;
            tx_bit_cnt    <= 0;
            tx_state      <= TX_START;
            tx_busy       <= 1'b1;
            tx_baud_done  <= 1'b0;  // start fresh in new state
          end
        end

        TX_START: begin
          uart_rx_o_int <= 1'b0;  // start bit (low)
          tx_busy       <= 1'b1;
          if (tx_baud_done) begin
            tx_state      <= TX_DATA;
            tx_baud_done  <= 1'b0;
          end
        end

        TX_DATA: begin
          uart_rx_o_int <= tx_shift_reg[0];  // LSB first
          tx_busy       <= 1'b1;
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
          uart_rx_o_int <= 1'b1;  // stop bit (high)
          tx_busy       <= 1'b1;
          if (tx_baud_done) begin
            tx_state      <= TX_IDLE;
            tx_baud_done  <= 1'b0;
          end
        end
      endcase
    end
  end

  assign uart_rx_o = uart_rx_o_int;

endmodule
`default_nettype wire
// vim:ts=2 sw=2 tw=120 et
