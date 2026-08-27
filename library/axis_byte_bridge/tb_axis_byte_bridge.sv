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
// tb_axis_byte_bridge — focused testbench for the byte-stream bridge
// ==========================================================================
// Updated for axi_byte_fifo: 8-bit TDATA, no TLAST/TLR/RLR.
// Tests:
//   Test 1 — PS→PL: byte pass-through, rx_accept backpressure holds M_AXIS
//   Test 2 — PL→PS: tx_valid strobe captured into 1-deep stage even while
//            S_AXIS blocked (tready=0); drained when tready rises
//   Test 3 — back-to-back bytes both directions (order + zero loss)
//   Test 4 — RTS stalls PS→PL but not PL→PS (separate FIFOs)
// ==========================================================================

module tb_axis_byte_bridge;

  logic        clk;
  logic        reset;

  // M_AXIS (PS→PL) — 8-bit
  logic        m_axis_tvalid;
  logic        m_axis_tready;
  logic [7:0]  m_axis_tdata;

  // S_AXIS (PL→PS) — 8-bit
  logic        s_axis_tvalid;
  logic        s_axis_tready;
  logic [7:0]  s_axis_tdata;

  // Byte side
  logic [7:0]  rx_data;
  logic        rx_valid;
  logic        rx_accept;
  logic [7:0]  tx_data;
  logic        tx_valid;
  logic        tx_ready;
  logic        rx_rts_n = 1'b0;

  axis_byte_bridge dut (
      .clk          (clk),
      .reset        (reset),
      .m_axis_tvalid(m_axis_tvalid),
      .m_axis_tready(m_axis_tready),
      .m_axis_tdata (m_axis_tdata),
      .s_axis_tvalid(s_axis_tvalid),
      .s_axis_tready(s_axis_tready),
      .s_axis_tdata (s_axis_tdata),
      .rx_data      (rx_data),
      .rx_valid     (rx_valid),
      .rx_accept    (rx_accept),
      .tx_data      (tx_data),
      .tx_valid     (tx_valid),
      .tx_ready     (tx_ready),
      .rx_rts_n     (rx_rts_n)
  );

  always #5 clk = ~clk;

  int pass_count = 0;
  int fail_count = 0;

  task static m_axis_send(input logic [7:0] exp_val);
    begin
      m_axis_tvalid = 1'b1;
      m_axis_tdata  = exp_val;
      while (!m_axis_tready) @(posedge clk);
      @(negedge clk);
      if (rx_valid !== 1'b1 || rx_data !== exp_val) begin
        $display("  ✗ FAIL: rx_valid=%0b rx_data=0x%02h, expected 0x%02h",
                 rx_valid, rx_data, exp_val);
        fail_count = fail_count + 1;
      end else begin
        pass_count = pass_count + 1;
      end
      @(posedge clk);  // transfer completes
      m_axis_tvalid = 1'b0;
      @(posedge clk);
    end
  endtask

  task static tx_strobe(input logic [7:0] val);
    begin
      @(negedge clk);
      tx_valid = 1'b1;
      tx_data  = val;
      @(posedge clk);
      @(negedge clk);
      tx_valid = 1'b0;
    end
  endtask

  task static s_axis_expect(input logic [7:0] val);
    begin
      while (!(s_axis_tvalid && s_axis_tready)) @(posedge clk);
      @(negedge clk);
      if (s_axis_tdata !== val) begin
        $display("  ✗ FAIL: S_AXIS tdata=0x%02h, expected 0x%02h",
                 s_axis_tdata, val);
        fail_count = fail_count + 1;
      end else begin
        pass_count = pass_count + 1;
      end
      @(posedge clk);  // pop
    end
  endtask

  initial begin
    $display("═══════════════════════════════════════════");
    $display("  axis_byte_bridge (8-bit, no TLAST) — TB");
    $display("═══════════════════════════════════════════");

    clk = 1'b0;
    reset = 1'b1;
    m_axis_tvalid = 1'b0;
    m_axis_tdata  = 8'd0;
    s_axis_tready = 1'b1;
    rx_accept     = 1'b1;
    tx_valid      = 1'b0;
    tx_data       = 8'd0;
    repeat (10) @(posedge clk);
    reset = 1'b0;
    repeat (5) @(posedge clk);

    // ── Test 1: PS→PL pass-through ──
    $display("");
    $display("──────────────────────────────────────────");
    $display("TEST 1: PS→PL pass-through");
    $display("──────────────────────────────────────────");
    rx_accept = 1'b1;
    m_axis_send(8'h41);
    m_axis_send(8'h7A);

    // rx_accept low must deassert tready and hold the byte, not drop it
    rx_accept = 1'b0;
    m_axis_tvalid = 1'b1;
    m_axis_tdata  = 8'h61;
    @(posedge clk);
    if (m_axis_tready !== 1'b0) begin
      $display("  ✗ FAIL: m_axis_tready high while rx_accept low");
      fail_count = fail_count + 1;
    end else begin
      pass_count = pass_count + 1;
    end
    repeat (3) @(posedge clk);  // byte held
    @(negedge clk);
    if (rx_valid !== 1'b1 || rx_data !== 8'h61) begin
      $display("  ✗ FAIL: held byte corrupted (rx=0x%02h)", rx_data);
      fail_count = fail_count + 1;
    end else begin
      pass_count = pass_count + 1;
    end
    rx_accept = 1'b1;           // drain
    @(posedge clk);
    if (!(m_axis_tvalid && m_axis_tready)) begin
      $display("  ✗ FAIL: byte not drained on rx_accept rise");
      fail_count = fail_count + 1;
    end else begin
      pass_count = pass_count + 1;
    end
    m_axis_tvalid = 1'b0;
    @(posedge clk);

    // ── Test 2: PL→PS strobe captured while S_AXIS blocked ──
    $display("");
    $display("──────────────────────────────────────────");
    $display("TEST 2: tx_valid strobe onto blocked S_AXIS");
    $display("──────────────────────────────────────────");
    s_axis_tready = 1'b0;        // RX FIFO "full"
    tx_strobe(8'h42);            // strobe lands while blocked
    if (s_axis_tvalid !== 1'b1) begin
      $display("  ✗ FAIL: strobe not captured (s_axis_tvalid low)");
      fail_count = fail_count + 1;
    end else begin
      pass_count = pass_count + 1;
    end
    repeat (3) @(posedge clk);  // stage holds the byte
    @(negedge clk);
    if (s_axis_tdata !== 8'h42) begin
      $display("  ✗ FAIL: held stage byte wrong (tdata=0x%02h)", s_axis_tdata);
      fail_count = fail_count + 1;
    end else begin
      pass_count = pass_count + 1;
    end
    s_axis_tready = 1'b1;
    s_axis_expect(8'h42);

    // Normal strobe (ready high) still works
    tx_strobe(8'h5A);
    s_axis_expect(8'h5A);

    // ── Test 3: back-to-back both directions, no loss ──
    $display("");
    $display("──────────────────────────────────────────");
    $display("TEST 3: back-to-back bytes both directions");
    $display("──────────────────────────────────────────");
    rx_accept = 1'b1;
    for (int i = 0; i < 8; i = i + 1) begin
      m_axis_send(8'(i + 1));
      tx_strobe(8'hA0 + 8'(i));
      s_axis_expect(8'hA0 + 8'(i));
    end

    // ── Test 4: RTS flow-control stalls PS→PL but not PL→PS (separate FIFOs) ──
    $display("");
    $display("──────────────────────────────────────────");
    $display("TEST 4: RTS stalls PS→PL, PL→PS still flows (separate buffers)");
    $display("──────────────────────────────────────────");
    rx_rts_n = 1'b1; // assert RTS (Z80 serBuf full) - should hide data and stall
    rx_accept = 1'b1;
    m_axis_tvalid = 1'b1;
    m_axis_tdata  = 8'hAA;
    repeat (2) @(posedge clk);
    @(negedge clk);
    if (m_axis_tready !== 1'b0) begin
      $display("  ✗ FAIL: RTS=1 but tready=%b (expected 0)", m_axis_tready);
      fail_count = fail_count + 1;
    end else begin pass_count = pass_count + 1; end
    if (rx_valid !== 1'b0) begin
      $display("  ✗ FAIL: RTS=1 but rx_valid=%b (expected 0, masked RDRF)", rx_valid);
      fail_count = fail_count + 1;
    end else begin pass_count = pass_count + 1; end
    // PL->PS must still flow while RTS stalls PS->PL (separate RX FIFO)
    s_axis_tready = 1'b1;
    tx_strobe(8'hCC);
    s_axis_expect(8'hCC);
    // Deassert RTS: stalled byte must appear exactly once
    rx_rts_n = 1'b0;
    @(posedge clk);
    @(negedge clk);
    if (rx_valid !== 1'b1 || rx_data !== 8'hAA) begin
      $display("  ✗ FAIL: after RTS clear rx_valid=%b rx_data=0x%02h exp AA", rx_valid, rx_data);
      fail_count = fail_count + 1;
    end else begin pass_count = pass_count + 1; $display("  PASS: RTS clear exposes stalled byte"); end
    if (m_axis_tready !== 1'b1) begin
      $display("  ✗ FAIL: after RTS clear tready=%b (expected 1)", m_axis_tready);
      fail_count = fail_count + 1;
    end else begin pass_count = pass_count + 1; end
    @(posedge clk); // handshake completes
    m_axis_tvalid = 1'b0;
    @(posedge clk);
    if (rx_valid !== 1'b0) begin
      $display("  NOTE: rx_valid after pop=%b (expected 0)", rx_valid);
    end

    // ── Summary ──
    repeat (20) @(posedge clk);
    $display("");
    if (fail_count == 0) $display("  ✓ ALL TESTS PASSED  (%0d checks)", pass_count);
    else $display("  ✗ FAILURES: %0d / %0d checks", fail_count, pass_count + fail_count);
    $finish;
  end

  initial begin
    #100_000;
    $display("  ⚠ TIMEOUT: testbench stalled");
    $display("  ✗ FAILURES: %0d / %0d checks", fail_count, pass_count + fail_count);
    $finish;
  end

endmodule
`default_nettype wire
// vim:ts=2 sw=2 tw=120 et
