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
// tb_char_add_one — testbench for char_add_one byte transform
// ==========================================================================
// Tests:
//   Test 1 — Exhaustive 256-value sweep (includes wraparound 0xFF→0x00)
//   Test 2 — Back-to-back values (valid held high across cycles)
//
// Strategy: drive inputs via NBAs after posedge (settle before next
// posedge), check outputs on negedge (safe timing window).
// ==========================================================================

module tb_char_add_one;

  reg        clk;
  reg        reset;
  reg  [7:0] data_in;
  reg        data_in_valid;
  wire [7:0] data_out;
  wire       data_out_valid;

  char_add_one dut (
    .clk(clk), .reset(reset),
    .data_in(data_in), .data_in_valid(data_in_valid),
    .data_out(data_out), .data_out_valid(data_out_valid)
  );

  always #5 clk = ~clk;

  integer test_num, pass_count, fail_count, byte_idx;

  // Main
  initial begin
    $display("═══════════════════════════════════════════");
    $display("  char_add_one — full test suite");
    $display("═══════════════════════════════════════════");

    clk = 1'b0; reset = 1'b1; data_in = 8'd0; data_in_valid = 1'b0;
    pass_count = 0; fail_count = 0; test_num = 0;
    repeat (20) @(posedge clk); reset = 1'b0;
    repeat (5)  @(posedge clk);

    // ================================================================
    // TEST 1 — Exhaustive 256-value sweep (includes 0xFF→0x00 wrap)
    // ================================================================
    test_num = 1;
    $display("");
    $display("──────────────────────────────────────────");
    $display("TEST %0d: Exhaustive sweep (0x00 -> 0xFF)", test_num);
    $display("──────────────────────────────────────────");

    // Seed the first input before the loop so the DUT has valid data
    // at the first posedge we wait for.
    data_in       <= 8'd0;
    data_in_valid <= 1'b1;

    for (byte_idx = 0; byte_idx < 256; byte_idx = byte_idx + 1) begin
      @(posedge clk);          // DUT samples data_in = byte_idx, valid = 1
      // Queue the next input (NBA — takes effect after this timestep,
      // before the next posedge)
      if (byte_idx < 255) begin
        data_in       <= byte_idx[7:0] + 8'd1;
        data_in_valid <= 1'b1;
      end else begin
        data_in_valid <= 1'b0;
      end
      @(negedge clk);         // Safe check: DUT's output from byte_idx is stable
      if (data_out_valid !== 1'b1) begin
        $display("  ✗ FAIL: 0x%02h → data_out_valid=0 (expected 1)", byte_idx[7:0]);
        fail_count = fail_count + 1;
      end else if (data_out !== (byte_idx[7:0] + 8'd1)) begin
        $display("  ✗ FAIL: 0x%02h → got 0x%02h, expected 0x%02h",
                 byte_idx[7:0], data_out, byte_idx[7:0] + 8'd1);
        fail_count = fail_count + 1;
      end else begin
        pass_count = pass_count + 1;
      end
    end

    // ================================================================
    // TEST 2 — Back-to-back values (valid held high continuously)
    // ================================================================
    test_num = 2;
    $display("");
    $display("──────────────────────────────────────────");
    $display("TEST %0d: Back-to-back values (valid=1 throughout)", test_num);
    $display("──────────────────────────────────────────");

    // Seed first value
    data_in       <= 8'h41;
    data_in_valid <= 1'b1;

    // Byte 0x41
    @(posedge clk);
    data_in <= 8'h42;       // next value queued, valid stays 1
    @(negedge clk);
    if (data_out_valid !== 1'b1 || data_out !== 8'h42) begin
      $display("  ✗ FAIL: 0x41 → got 0x%02h (valid=%b), expected 0x42", data_out, data_out_valid);
      fail_count = fail_count + 1;
    end else pass_count = pass_count + 1;

    // Byte 0x42
    @(posedge clk);
    data_in <= 8'h43;
    @(negedge clk);
    if (data_out_valid !== 1'b1 || data_out !== 8'h43) begin
      $display("  ✗ FAIL: 0x42 → got 0x%02h (valid=%b), expected 0x43", data_out, data_out_valid);
      fail_count = fail_count + 1;
    end else pass_count = pass_count + 1;

    // Byte 0x43
    @(posedge clk);
    data_in_valid <= 1'b0;   // deassert after last byte
    @(negedge clk);
    if (data_out_valid !== 1'b1 || data_out !== 8'h44) begin
      $display("  ✗ FAIL: 0x43 → got 0x%02h (valid=%b), expected 0x44", data_out, data_out_valid);
      fail_count = fail_count + 1;
    end else pass_count = pass_count + 1;

    // ================================================================
    // Report
    // ================================================================
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
    $dumpfile("tb_char_add_one.vcd");
    $dumpvars(0, tb_char_add_one);
  end

endmodule
`default_nettype wire
