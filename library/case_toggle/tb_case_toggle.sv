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
// tb_case_toggle — focused testbench for the ASCII case-toggle module
// ==========================================================================
// Drives the bf2_soc-style io_* byte interface (rx valid/ready level,
// tx single-cycle strobe) exactly as the axis_byte_bridge would:
//   Test 1 — known letters toggle (A→a, a→A, Z→z, z→Z), digit bit-5 flip
//   Test 2 — back-to-back bytes, order preserved
//   Test 3 — TX blocked: io_rx_ready drops (backpressure), byte held,
//            delivered when io_tx_ready rises; strobe is single-cycle
// ==========================================================================

module tb_case_toggle;

  logic        clk;
  logic        reset;

  logic [7:0]  io_rx_data;
  logic        io_rx_valid;
  logic        io_rx_ready;
  logic [7:0]  io_tx_data;
  logic        io_tx_valid;
  logic        io_tx_ready;

  case_toggle dut (
      .clk         (clk),
      .reset       (reset),
      .io_rx_data  (io_rx_data),
      .io_rx_valid (io_rx_valid),
      .io_rx_ready (io_rx_ready),
      .io_tx_data  (io_tx_data),
      .io_tx_valid (io_tx_valid),
      .io_tx_ready (io_tx_ready)
  );

  always #5 clk = ~clk;

  int pass_count = 0;
  int fail_count = 0;

  // Present a byte until accepted (io_rx_valid && io_rx_ready posedge).
  task static rx_send(input logic [7:0] val);
    begin
      io_rx_valid = 1'b1;
      io_rx_data  = val;
      while (!io_rx_ready) @(posedge clk);
      @(posedge clk);  // accept posedge
      io_rx_valid = 1'b0;
    end
  endtask

  // Wait for the TX strobe, verify data, then check it is single-cycle.
  task static tx_expect(input logic [7:0] exp_byte);
    begin
      while (!(io_tx_valid && io_tx_ready)) @(posedge clk);
      @(negedge clk);
      if (io_tx_data !== exp_byte) begin
        $display("  ✗ FAIL: io_tx_data=0x%02h, expected 0x%02h", io_tx_data, exp_byte);
        fail_count = fail_count + 1;
      end else begin
        pass_count = pass_count + 1;
      end
      @(posedge clk);  // strobe cycle ends
      if (io_tx_valid !== 1'b0) begin
        $display("  ✗ FAIL: io_tx_valid not a single-cycle strobe");
        fail_count = fail_count + 1;
      end else begin
        pass_count = pass_count + 1;
      end
    end
  endtask

  initial begin
    $display("═══════════════════════════════════════════");
    $display("  case_toggle — ASCII case toggle TB");
    $display("═══════════════════════════════════════════");

    clk = 1'b0;
    reset = 1'b1;
    io_rx_valid = 1'b0;
    io_rx_data  = 8'd0;
    io_tx_ready = 1'b1;
    repeat (10) @(posedge clk);
    reset = 1'b0;
    repeat (5) @(posedge clk);

    // ── Test 1: known values ──
    $display("");
    $display("──────────────────────────────────────────");
    $display("TEST 1: known letters toggle, digit bit-5 flip");
    $display("──────────────────────────────────────────");
    rx_send(8'h41);  // 'A'
    tx_expect(8'h61);  // 'a'
    rx_send(8'h61);  // 'a'
    tx_expect(8'h41);  // 'A'
    rx_send(8'h5A);  // 'Z'
    tx_expect(8'h7A);  // 'z'
    rx_send(8'h7A);  // 'z'
    tx_expect(8'h5A);  // 'Z'
    rx_send(8'h30);  // '0' — non-letter: bit 5 flipped by design
    tx_expect(8'h10);

    // ── Test 2: back-to-back, order preserved ──
    $display("");
    $display("──────────────────────────────────────────");
    $display("TEST 2: back-to-back bytes");
    $display("──────────────────────────────────────────");
    for (int i = 0; i < 8; i = i + 1) begin
      rx_send(8'h41 + 8'(i));
      tx_expect(8'h61 + 8'(i));
    end

    // ── Test 3: TX blocked → RX backpressure ──
    $display("");
    $display("──────────────────────────────────────────");
    $display("TEST 3: TX blocked (io_tx_ready=0)");
    $display("──────────────────────────────────────────");
    io_tx_ready = 1'b0;
    rx_send(8'h42);  // accepted while idle, then busy
    @(negedge clk);
    if (io_rx_ready !== 1'b0) begin
      $display("  ✗ FAIL: io_rx_ready high while byte held");
      fail_count = fail_count + 1;
    end else begin
      pass_count = pass_count + 1;
    end
    if (io_tx_valid !== 1'b0) begin
      $display("  ✗ FAIL: strobe fired while io_tx_ready low");
      fail_count = fail_count + 1;
    end else begin
      pass_count = pass_count + 1;
    end
    repeat (3) @(posedge clk);  // byte held
    io_tx_ready = 1'b1;
    tx_expect(8'h62);  // 'B' → 'b'
    @(negedge clk);
    if (io_rx_ready !== 1'b1) begin
      $display("  ✗ FAIL: io_rx_ready not restored after drain");
      fail_count = fail_count + 1;
    end else begin
      pass_count = pass_count + 1;
    end
    io_tx_ready = 1'b1;

    // ── Summary ──
    repeat (20) @(posedge clk);
    $display("");
    if (fail_count == 0) $display("  ✓ ALL TESTS PASSED  (%0d checks)", pass_count);
    else $display("  ✗ FAILURES: %0d / %0d checks", fail_count, pass_count + fail_count);
    $finish;
  end

  // Watchdog — never let a deadlock hang the sim
  initial begin
    #100_000;
    $display("  ⚠ TIMEOUT: testbench stalled");
    $display("  ✗ FAILURES: %0d / %0d checks", fail_count, pass_count + fail_count);
    $finish;
  end

endmodule
`default_nettype wire
// vim:ts=2 sw=2 tw=120 et
