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
// tb_echo_char — comprehensive testbench for echo_char UART loopback
// ==========================================================================
// Tests the echo_char module: UART RX → byte+1 → UART TX.
//
// Test structure:
//   Test 1 — Known values (hardware corruption candidates)
//   Test 2 — Wraparound (0xFF→0x00, 0x00→0x01)
//   Test 3 — Back-to-back bytes
//   Test 4 — Byte after long idle
//   Test 5 — Exhaustive sweep (0x00 → 0xFF)
//   Test 6 — Repeated 0x41 × 100 (timing drift stress)
// ==========================================================================

module tb_echo_char;

  localparam CLK_FREQ = 100000000;
  localparam BAUD     = 115200;

  reg        clk;
  reg        reset;
  wire       uart_tx_o;
  wire       uart_rx_o;

  echo_char #(.CLK_FREQ(CLK_FREQ), .BAUD(BAUD)) dut (
    .clk(clk), .reset(reset), .uart_tx_i(uart_tx_o), .uart_rx_o(uart_rx_o)
  );

  always #5 clk = ~clk;

  // TB TX
  reg        tb_tx_start;
  reg  [7:0] tb_tx_byte;
  wire       tb_tx_busy, tb_tx_done;

  uart_tx_model #(.CLK_FREQ(CLK_FREQ), .BAUD(BAUD)) tx_model (
    .clk(clk), .reset(reset), .tx_start(tb_tx_start), .tx_byte(tb_tx_byte),
    .tx_line(uart_tx_o), .tx_busy(tb_tx_busy), .tx_done(tb_tx_done)
  );

  // TB RX
  wire       tb_rx_valid;
  wire [7:0] tb_rx_byte;

  uart_rx_model #(.CLK_FREQ(CLK_FREQ), .BAUD(BAUD)) rx_model (
    .clk(clk), .reset(reset), .rx_line(uart_rx_o),
    .rx_valid(tb_rx_valid), .rx_byte(tb_rx_byte)
  );

  // TB-side RX queue: captures bytes while we're busy sending bursts.
  // Without this, single-cycle tb_rx_valid pulses during a multi-byte
  // burst are lost before wait_rx_byte() gets called.
  reg [7:0]  rx_queue [0:255];
  reg [7:0]  rx_queue_wr_ptr;
  reg [7:0]  rx_queue_rd_ptr;
  wire       rx_queue_empty = (rx_queue_wr_ptr == rx_queue_rd_ptr);
  wire       rx_queue_full  = (rx_queue_wr_ptr - rx_queue_rd_ptr == 256);

  always @(posedge clk) begin
    if (reset) begin
      rx_queue_wr_ptr <= 0;
    end else if (tb_rx_valid && !rx_queue_full) begin
      rx_queue[rx_queue_wr_ptr] <= tb_rx_byte;
      rx_queue_wr_ptr <= rx_queue_wr_ptr + 1'd1;
    end
  end

  // Test state
  integer test_num, pass_count, fail_count, byte_idx;
  reg  [7:0] expected;
  reg  [7:0] test_bytes [0:255];
  integer   test_bytes_len;
  reg        rx_timeout;
  reg  [7:0] rx_got;
  reg  [7:0] tx_sent;
  reg  [7:0] rx_expected;
  reg [31:0] watchdog;

  always @(posedge clk) begin
    if (reset) watchdog <= 0;
    else       watchdog <= watchdog + 1'b1;
  end

  // Tasks
  task send_byte;
    input [7:0] val;
    begin
      tb_tx_byte = val; tb_tx_start = 1'b1;
      @(posedge clk); tb_tx_start = 1'b0;
      @(posedge clk); while (tb_tx_busy) @(posedge clk);
    end
  endtask

  task wait_rx_byte;
    output [7:0] val;
    output       timeout;
    begin
      timeout = 1'b0; watchdog = 0;
      while (!tb_rx_valid) begin
        @(posedge clk);
        if (watchdog > 500_000) begin
          timeout = 1'b1; val = 8'hXX;
          $display("  ⚠ TIMEOUT");
          disable wait_rx_byte;
        end
      end
      val = tb_rx_byte; @(posedge clk);
    end
  endtask

  task wait_rx_queued;
    output [7:0] val;
    output       timeout;
    begin
      timeout = 1'b0; watchdog = 0;
      while (rx_queue_empty) begin
        @(posedge clk);
        if (watchdog > 1_000_000) begin
          timeout = 1'b1; val = 8'hXX;
          $display("  ⚠ QUEUE TIMEOUT");
          disable wait_rx_queued;
        end
      end
      val = rx_queue[rx_queue_rd_ptr];
      rx_queue_rd_ptr <= rx_queue_rd_ptr + 1'd1;
      @(posedge clk);
    end
  endtask

  task reset_rx_queue;
    begin
      rx_queue_rd_ptr <= 0;
      rx_queue_wr_ptr <= 0;
      @(posedge clk);
    end
  endtask

  task check_byte;
    input [7:0] sent;
    input [7:0] received;
    input [7:0] exp;
    begin
      if (received === 8'hXX) begin
        $display("  ✗ SKIP: no data received");
        fail_count = fail_count + 1;
      end else if (received === exp) begin
        pass_count = pass_count + 1;
      end else begin
        $display("  ✗ FAIL: sent 0x%02h (%3d) → got 0x%02h (%3d), expected 0x%02h (%3d)",
                 sent, sent, received, received, exp, exp);
        $display("         sent:     %08b", sent);
        $display("         received: %08b", received);
        $display("         expected: %08b", exp);
        fail_count = fail_count + 1;
      end
    end
  endtask

  task test_banner;
    input [8*30:0] desc;
    begin
      $display("");
      $display("──────────────────────────────────────────");
      $display("TEST %0d: %0s", test_num, desc);
      $display("──────────────────────────────────────────");
    end
  endtask

  // Main
  initial begin
    $display("═══════════════════════════════════════════");
    $display("  echo_char UART loopback — full test suite");
    $display("  CLK = %0d Hz, BAUD = %0d", CLK_FREQ, BAUD);
    $display("═══════════════════════════════════════════");

    clk = 1'b0; reset = 1'b1; tb_tx_start = 1'b0; tb_tx_byte = 8'd0;
    pass_count = 0; fail_count = 0; test_num = 0;
    repeat (20) @(posedge clk); reset = 1'b0;
    repeat (5) @(posedge clk);

    // TEST 1
    test_num = 1;
    test_banner("Known values (hardware corruption candidates)");
    test_bytes[0] = 8'h41; test_bytes[1] = 8'h7A; test_bytes[2] = 8'h30;
    test_bytes[3] = 8'h21; test_bytes[4] = 8'h0A; test_bytes[5] = 8'h42;
    test_bytes_len = 6;
    for (byte_idx = 0; byte_idx < test_bytes_len; byte_idx = byte_idx + 1) begin
      tx_sent = test_bytes[byte_idx]; send_byte(tx_sent);
      rx_expected = tx_sent + 8'd1; wait_rx_byte(rx_got, rx_timeout);
      if (!rx_timeout) check_byte(tx_sent, rx_got, rx_expected);
    end

    // TEST 2
    test_num = 2; test_banner("Wraparound (0xFF=>0x00, 0x00=>0x01)");
    repeat (200) @(posedge clk);
    send_byte(8'hFF); wait_rx_byte(rx_got, rx_timeout);
    if (!rx_timeout) check_byte(8'hFF, rx_got, 8'h00);
    send_byte(8'h00); wait_rx_byte(rx_got, rx_timeout);
    if (!rx_timeout) check_byte(8'h00, rx_got, 8'h01);

    // TEST 3
    test_num = 3; test_banner("Back-to-back bytes");
    repeat (200) @(posedge clk);
    send_byte(8'h10); wait_rx_byte(rx_got, rx_timeout); if (!rx_timeout) check_byte(8'h10, rx_got, 8'h11);
    send_byte(8'h20); wait_rx_byte(rx_got, rx_timeout); if (!rx_timeout) check_byte(8'h20, rx_got, 8'h21);
    send_byte(8'h40); wait_rx_byte(rx_got, rx_timeout); if (!rx_timeout) check_byte(8'h40, rx_got, 8'h41);
    send_byte(8'h80); wait_rx_byte(rx_got, rx_timeout); if (!rx_timeout) check_byte(8'h80, rx_got, 8'h81);

    // TEST 4
    test_num = 4; test_banner("Byte after long idle period");
    repeat (10_000) @(posedge clk);
    send_byte(8'h55); wait_rx_byte(rx_got, rx_timeout);
    if (!rx_timeout) check_byte(8'h55, rx_got, 8'h56);

    // TEST 5
    test_num = 5; test_banner("Exhaustive sweep (0x00 -> 0xFF)");
    for (byte_idx = 0; byte_idx < 256; byte_idx = byte_idx + 1) begin
      tx_sent = byte_idx[7:0]; send_byte(tx_sent);
      rx_expected = tx_sent + 8'd1; wait_rx_byte(rx_got, rx_timeout);
      if (!rx_timeout) check_byte(tx_sent, rx_got, rx_expected);
    end

    // TEST 6
    test_num = 6; test_banner("Repeated 0x41 x 100 (timing drift stress)");
    for (byte_idx = 0; byte_idx < 100; byte_idx = byte_idx + 1) begin
      send_byte(8'h41); wait_rx_byte(rx_got, rx_timeout);
      if (!rx_timeout) check_byte(8'h41, rx_got, 8'h42);
    end

    // TEST 7 — Burst of 8 back-to-back bytes (FIFO exercise)
    test_num = 7; test_banner("Burst 8 back-to-back (FIFO)");
    repeat (500) @(posedge clk); reset_rx_queue;
    for (byte_idx = 0; byte_idx < 8; byte_idx = byte_idx + 1) begin
      tx_sent = byte_idx[7:0] + 8'h40;
      send_byte(tx_sent);
      rx_expected = tx_sent + 8'd1;
      wait_rx_queued(rx_got, rx_timeout);
      if (!rx_timeout) check_byte(tx_sent, rx_got, rx_expected);
    end

    // TEST 8 — Burst of 32 bytes send-all-then-read-all
    test_num = 8; test_banner("Burst 32 send-then-read-all");
    repeat (500) @(posedge clk); reset_rx_queue;
    for (byte_idx = 0; byte_idx < 32; byte_idx = byte_idx + 1) begin
      send_byte(byte_idx[7:0]);
    end
    for (byte_idx = 0; byte_idx < 32; byte_idx = byte_idx + 1) begin
      wait_rx_queued(rx_got, rx_timeout);
      rx_expected = byte_idx[7:0] + 8'd1;
      if (!rx_timeout) check_byte(byte_idx[7:0], rx_got, rx_expected);
    end

    // TEST 9 — Burst of 64 bytes send-all-then-read-all
    test_num = 9; test_banner("Burst 64 send-then-read-all");
    repeat (500) @(posedge clk); reset_rx_queue;
    for (byte_idx = 0; byte_idx < 64; byte_idx = byte_idx + 1) begin
      send_byte(byte_idx[7:0]);
    end
    for (byte_idx = 0; byte_idx < 64; byte_idx = byte_idx + 1) begin
      wait_rx_queued(rx_got, rx_timeout);
      rx_expected = byte_idx[7:0] + 8'd1;
      if (!rx_timeout) check_byte(byte_idx[7:0], rx_got, rx_expected);
    end

    // TEST 10 — Burst of 17 bytes (one more than FIFO depth)
    test_num = 10; test_banner("Burst 17 (FIFO depth + 1)");
    repeat (500) @(posedge clk); reset_rx_queue;
    for (byte_idx = 0; byte_idx < 17; byte_idx = byte_idx + 1) begin
      tx_sent = byte_idx[7:0] + 8'hA0;
      send_byte(tx_sent);
    end
    for (byte_idx = 0; byte_idx < 17; byte_idx = byte_idx + 1) begin
      wait_rx_queued(rx_got, rx_timeout);
      rx_expected = (byte_idx[7:0] + 8'hA0) + 8'd1;
      if (!rx_timeout) check_byte(byte_idx[7:0] + 8'hA0, rx_got, rx_expected);
    end

    // Report
    $display("");
    $display("═══════════════════════════════════════════");
    if (fail_count == 0)
      $display("  ✓ ALL TESTS PASSED  (%0d checks)", pass_count);
    else
      $display("  ✗ FAILURES: %0d / %0d checks", fail_count, pass_count + fail_count);
    $display("═══════════════════════════════════════════");
    $finish;
  end

  // VCD dump
  initial begin
    $dumpfile("tb_echo_char.vcd");
    $dumpvars(0, tb_echo_char);
  end

endmodule


// ==========================================================================
// uart_tx_model — UART transmitter with baud counter reset on new tx
// ==========================================================================
module uart_tx_model #(
  parameter CLK_FREQ = 100000000,
  parameter BAUD     = 115200
) (
  input  wire       clk, reset, tx_start,
  input  wire [7:0] tx_byte,
  output reg        tx_line, tx_busy, tx_done
);

  localparam BAUD_CNT = CLK_FREQ / BAUD - 1;
  localparam ST_IDLE = 0, ST_START = 1, ST_DATA = 2, ST_STOP = 3;

  reg [1:0]  state;
  reg [3:0]  bit_idx;
  reg [7:0]  shift_reg;
  reg [15:0] baud_cnt;
  reg        baud_en;

  always @(posedge clk) begin
    if (reset) begin
      state <= ST_IDLE; bit_idx <= 0; shift_reg <= 0;
      baud_cnt <= 0; baud_en <= 1'b0;
      tx_line <= 1'b1; tx_busy <= 1'b0; tx_done <= 1'b0;
    end else begin
      tx_done <= 1'b0;
      if (tx_start) begin
        baud_cnt <= 0; baud_en <= 1'b0;
      end else if (baud_cnt >= BAUD_CNT) begin
        baud_cnt <= 0; baud_en <= 1'b1;
      end else begin
        baud_cnt <= baud_cnt + 1'd1; baud_en <= 1'b0;
      end
      case (state)
        ST_IDLE: begin
          tx_line <= 1'b1; tx_busy <= 1'b0;
          if (tx_start) begin
            shift_reg <= tx_byte; bit_idx <= 0;
            state <= ST_START; tx_busy <= 1'b1;
          end
        end
        ST_START: begin
          tx_line <= 1'b0; tx_busy <= 1'b1;
          if (baud_en) state <= ST_DATA;
        end
        ST_DATA: begin
          tx_line <= shift_reg[0]; tx_busy <= 1'b1;
          if (baud_en) begin
            shift_reg <= {1'b0, shift_reg[7:1]};
            if (bit_idx == 7) begin bit_idx <= 0; state <= ST_STOP; end
            else bit_idx <= bit_idx + 1'd1;
          end
        end
        ST_STOP: begin
          tx_line <= 1'b1; tx_busy <= 1'b1;
          if (baud_en) begin state <= ST_IDLE; tx_busy <= 1'b0; tx_done <= 1'b1; end
        end
      endcase
    end
  end

endmodule


// ==========================================================================
// uart_rx_model — UART receiver (8x oversampling)
// ==========================================================================
module uart_rx_model #(
  parameter CLK_FREQ = 100000000,
  parameter BAUD     = 115200
) (
  input  wire       clk, reset, rx_line,
  output reg        rx_valid,
  output reg  [7:0] rx_byte
);

  localparam BAUD_TICK_CNT = CLK_FREQ / (BAUD * 8) - 1;
  localparam RX_IDLE = 0, RX_START = 1, RX_DATA = 2, RX_STOP = 3;

  reg [2:0]  state;
  reg [3:0]  sample_cnt, bit_cnt;
  reg [7:0]  shift_reg;
  reg [15:0] tick_cnt;
  reg        tick_en;
  reg        rx_sync0, rx_sync1;

  always @(posedge clk) begin rx_sync0 <= rx_line; rx_sync1 <= rx_sync0; end

  always @(posedge clk) begin
    if (reset) begin tick_cnt <= 0; tick_en <= 1'b0; end
    else begin
      if (tick_cnt >= BAUD_TICK_CNT) begin tick_cnt <= 0; tick_en <= 1'b1; end
      else begin tick_cnt <= tick_cnt + 1'd1; tick_en <= 1'b0; end
    end
  end

  always @(posedge clk) begin
    if (reset) begin
      state <= RX_IDLE; sample_cnt <= 0; bit_cnt <= 0;
      shift_reg <= 0; rx_byte <= 0; rx_valid <= 1'b0;
    end else begin
      rx_valid <= 1'b0;
      case (state)
        RX_IDLE: begin
          sample_cnt <= 0; bit_cnt <= 0; shift_reg <= 0;
          if (tick_en && !rx_sync1) state <= RX_START;
        end
        RX_START: begin
          if (tick_en) begin
            if (sample_cnt == 4) begin
              if (!rx_sync1) begin sample_cnt <= 0; state <= RX_DATA; end
              else state <= RX_IDLE;
            end else sample_cnt <= sample_cnt + 1'd1;
          end
        end
        RX_DATA: begin
          if (tick_en) begin
            if (sample_cnt == 7) begin
              shift_reg <= {rx_sync1, shift_reg[7:1]}; sample_cnt <= 0;
              if (bit_cnt == 7) begin bit_cnt <= 0; state <= RX_STOP; end
              else bit_cnt <= bit_cnt + 1'd1;
            end else sample_cnt <= sample_cnt + 1'd1;
          end
        end
        RX_STOP: begin
          if (tick_en) begin
            if (sample_cnt == 7) begin
              if (rx_sync1) begin rx_byte <= shift_reg; rx_valid <= 1'b1; end
              sample_cnt <= 0; state <= RX_IDLE;
            end else sample_cnt <= sample_cnt + 1'd1;
          end
        end
      endcase
    end
  end

endmodule

`default_nettype wire