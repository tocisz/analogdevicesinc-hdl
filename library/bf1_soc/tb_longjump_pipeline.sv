`default_nettype none
`timescale 1 ns / 1 ps

// ==========================================================================
// Testbench: Long Jump Pipelined Address Calculation
// ==========================================================================
// Verifies that the proposed two-step pipelined long jump address
// calculation gives the same result as a direct single-step reference,
// using the NEW bit encoding:
//
//   New encoding:  offset[12:0] = {jump_insn[7:0], prefix_insn[4:0]}
//   Old encoding:  offset[12:0] = {prefix_insn[4:0], jump_insn[7:0]}
//
// The two-step pipeline splits the 13-bit addition across two cycles:
//
//   Step 1 (prefix EXEC):
//     low_sum  = pc[4:0] + prefix_insn[4:0]    // 5-bit + 5-bit = 6-bit
//     pj_low   = low_sum[4:0]
//     carry5   = low_sum[5]                     // carry into bit 5
//     pc_high  = pc[12:5]                       // upper 8 bits of PC
//
//   Step 2 (jump EXEC):
//     mid_sum  = pc[12:5] + jump_insn + carry5
//     result   = {mid_sum[7:0], pj_low[4:0]}   // 13-bit
//
// Reference: result = pc + $signed({jump_insn, prefix_insn[4:0]})
//
// Additionally, this testbench models the ALU from bf1.v and verifies
// that reusing it for the prefix's low-5-bit computation (instead of a
// standalone adder) gives identical results via two approaches:
//
//   Style A  — [ ]-style ALU setup:   alu_b = sign-ext off6(insn[5:0])
//              carry5 = alu_c[5] ^ pc[5] ^ 1  (insn[5]=1 correction)
//
//   Style B  — zero-ext prefix ALU:  alu_b = {8'b0, insn[4:0]}
//              carry5 = alu_c[5] ^ pc[5]       (clean, same as [ ] for insn[5]=0)
// ==========================================================================

module tb_longjump_pipeline;

  // ==================================================================
  // Parameters
  // ==================================================================
  localparam CADDR_WIDTH = 13;  // same as common.h
  localparam ALU_A_W = 15;      // alu_a width in bf1.v
  localparam ALU_B_W = 13;      // alu_b width in bf1.v

  // ==================================================================
  // Test control
  // ==================================================================
  integer pass_count, fail_count;
  integer pc_val, prefix_val, jump_val;
  integer iter, n_total;
  reg [4:0]  prefix_low;        // prefix_insn[4:0] — lower 5 bits of offset in new encoding
  reg [7:0]  jump_insn;         // jump byte — upper 8 bits of offset in new encoding
  reg [12:0] pc;                // program counter (at time of prefix EXEC)

  // ==================================================================
  // Original two-step calculation (standalone 5-bit adder)
  // ==================================================================

  // Step 1: prefix EXEC — compute low 5 bits + carry
  wire [5:0] low_sum;
  assign low_sum = pc[4:0] + prefix_low[4:0];

  // Step 2: jump EXEC — mid addition with known carry-in
  //   offset_high = jump_insn[7:0] = offset[12:5] in new encoding
  //   pc_high     = pc[12:5]
  //   mid_sum = pc_high + jump_insn + low_sum[5]
  wire [7:0] mid_sum;
  assign mid_sum = pc[12:5] + jump_insn + low_sum[5];

  // Assemble full 13-bit result
  wire [12:0] result_pl;
  assign result_pl = {mid_sum[7:0], low_sum[4:0]};

  // ==================================================================
  // ALU model (matches bf1.v exactly)
  // ==================================================================
  //   alu_c = alu_a + ($signed({alu_b, 2'b0}) >>> 2)
  //
  // where $signed({alu_b, 2'b0}) >>> 2  ==  sign_extend(alu_b) to 15 bits
  // (multiply by 4 then arithmetic divide by 4 = identity + sign-ext)

  reg [ALU_A_W-1:0] alu_a;
  reg [ALU_B_W-1:0] alu_b;
  wire [ALU_A_W-1:0] alu_c;
  assign alu_c = alu_a + ($signed({alu_b, 2'b0}) >>> 2);

  // ==================================================================
  // Style A: [ ]-style ALU setup for the prefix
  // ==================================================================
  //   Same as bf1.v's existing "before ALU" case for `[`:
  //     alu_a = {2'b0, pc}
  //     alu_b = $signed({insn[5:0], 7'b0}) >>> 7
  //   For the prefix, insn[7:5]=101, so insn[5]=1 and insn[4:0]=prefix_low.
  //
  //   This means: alu_b = sign-extend({1'b1, prefix_low[4:0]})  → negative!
  //   But alu_c[4:0] still gives pc[4:0] + prefix_low (carry flows LSB→MSB).
  //   At bit 5: alu_c[5] = pc[5] + 1 + carry5  → carry5 = alu_c[5] ^ pc[5] ^ 1

  wire [ALU_B_W-1:0] alu_b_styleA;
  assign alu_b_styleA = $signed({{1{1'b1}}, prefix_low[4:0], 7'b0}) >>> 7;

  wire [ALU_A_W-1:0] alu_a_styleA;
  assign alu_a_styleA = {2'b0, pc};

  wire [ALU_A_W-1:0] alu_c_styleA;
  assign alu_c_styleA = alu_a_styleA + ($signed({alu_b_styleA, 2'b0}) >>> 2);

  // Extraction
  wire [4:0] pj_low_A;
  wire       carry5_A;
  assign pj_low_A  = alu_c_styleA[4:0];
  assign carry5_A  = alu_c_styleA[5] ^ pc[5] ^ 1'b1;

  // Full pipeline result using Style A extraction
  wire [7:0] mid_sum_A;
  wire [12:0] result_A;
  assign mid_sum_A = pc[12:5] + jump_insn + carry5_A;
  assign result_A  = {mid_sum_A[7:0], pj_low_A[4:0]};

  // ==================================================================
  // Style B: zero-ext prefix ALU setup (dedicated prefix mode)
  // ==================================================================
  //   alu_a = {2'b0, pc}
  //   alu_b = {8'b0, insn[4:0]}  — zero-ext prefix_low to 13 bits
  //
  //   alu_b[5] = 0, so at bit 5: alu_c[5] = pc[5] + 0 + carry5
  //   carry5 = alu_c[5] ^ pc[5]   (same formula as [ ] for insn[5]=0)

  wire [ALU_B_W-1:0] alu_b_styleB;
  assign alu_b_styleB = {8'b0, prefix_low[4:0]};

  wire [ALU_A_W-1:0] alu_c_styleB;
  assign alu_c_styleB = alu_a_styleA + ($signed({alu_b_styleB, 2'b0}) >>> 2);

  // Extraction
  wire [4:0] pj_low_B;
  wire       carry5_B;
  assign pj_low_B  = alu_c_styleB[4:0];
  assign carry5_B  = alu_c_styleB[5] ^ pc[5];

  // Full pipeline result using Style B extraction
  wire [7:0] mid_sum_B;
  wire [12:0] result_B;
  assign mid_sum_B = pc[12:5] + jump_insn + carry5_B;
  assign result_B  = {mid_sum_B[7:0], pj_low_B[4:0]};

  // ==================================================================
  // Direct single-step reference
  // ==================================================================
  wire [12:0] result_ref;
  assign result_ref = pc[12:0] + $signed({jump_insn[7:0], prefix_low[4:0]});

  // ==================================================================
  // Test runner
  // ==================================================================
  initial begin
    pass_count = 0;
    fail_count = 0;
    n_total = 0;

    $display("");
    $display("===========================================================");
    $display("  Long Jump Pipeline — Arithmetic Verification");
    $display("===========================================================");
    $display("");
    $display("  Encoding: offset = {jump_insn[7:0], prefix_insn[4:0]}");
    $display("  PC width: %0d bits", CADDR_WIDTH);
    $display("");
    $display("  Comparing 4 calculations:");
    $display("    result_ref   = pc + $signed(offset)         (reference)");
    $display("    result_pl    = independent 5-bit + 8-bit    (original pipeline)");
    $display("    result_A     = ALU [ ]-style prefix reuse   (carry5 = alu_c[5]^pc[5]^1)");
    $display("    result_B     = ALU zero-ext prefix reuse    (carry5 = alu_c[5]^pc[5])");
    $display("");

    // ─── Initial smoke test: pick one case and show all signals ───
    $display("--- Smoke test (detailed signal dump) ---");
    pc = 13'b000_0001_1111_1;  prefix_low = 1;  jump_insn = 8'hFF;
    #0;  // settle combinational logic
    $display("  pc=%5d (0x%03h)  prefix_low=%2d  jump=0x%02h  offset=0x%04h (%4d)",
             pc, pc, prefix_low, jump_insn,
             {jump_insn, prefix_low}, $signed({jump_insn, prefix_low}));
    $display("  result_ref    = %5d (0x%03h)", result_ref, result_ref);
    $display("  result_pl     = %5d (0x%03h)  low_sum=%2d  carry5=%1d  mid_sum=%3d",
             result_pl, result_pl, low_sum, low_sum[5], mid_sum);
    $display("  --- Style A ---");
    $display("  alu_a_styleA  = %15b (%d)", alu_a_styleA, $signed(alu_a_styleA));
    $display("  alu_b_styleA  = %13b (%d)", alu_b_styleA, $signed(alu_b_styleA));
    $display("  alu_c_styleA  = %15b (%d)", alu_c_styleA, $signed(alu_c_styleA));
    $display("  pj_low_A=%2d  alu_c[5]=%1d  pc[5]=%1d  carry5_A=%1d  mid_sum_A=%3d",
             pj_low_A, alu_c_styleA[5], pc[5], carry5_A, mid_sum_A);
    $display("  result_A      = %5d (0x%03h)", result_A, result_A);
    $display("  --- Style B ---");
    $display("  alu_b_styleB  = %13b (%d)", alu_b_styleB, $signed(alu_b_styleB));
    $display("  alu_c_styleB  = %15b (%d)", alu_c_styleB, $signed(alu_c_styleB));
    $display("  pj_low_B=%2d  alu_c[5]=%1d  pc[5]=%1d  carry5_B=%1d  mid_sum_B=%3d",
             pj_low_B, alu_c_styleB[5], pc[5], carry5_B, mid_sum_B);
    $display("  result_B      = %5d (0x%03h)", result_B, result_B);
    $display("");

    // ─── Random tests with full-range pc (0..8191) ───
    $display("--- Random: pc[0:%0d] × prefix[0:31] × jump[0:255] ---",
             (1 << CADDR_WIDTH) - 1);
    for (iter = 0; iter < 1000; iter = iter + 1) begin
      pc        = $urandom_range(0, (1 << CADDR_WIDTH) - 1);
      prefix_low = $urandom_range(0, 31);
      jump_insn = $urandom_range(0, 255);
      run_one_test();
      n_total = n_total + 1;
    end

    // ─── Corner cases ───
    $display("--- Corner cases ---");

    // pc=0, offset=0
    pc = 0;  prefix_low = 0;  jump_insn = 0;  run_one_test(); n_total++;
    // pc=max, offset=0
    pc = (1<<CADDR_WIDTH)-1;  prefix_low = 0;  jump_insn = 0;  run_one_test(); n_total++;
    // pc=0, max positive offset (jump_insn[7]=0, prefix_low=31)
    pc = 0;  prefix_low = 31;  jump_insn = 8'h7F;  run_one_test(); n_total++;
    // pc=0, max negative offset (jump_insn[7]=1, all lower bits 1)
    pc = 0;  prefix_low = 31;  jump_insn = 8'hFF;  run_one_test(); n_total++;
    // pc=max, max negative offset (wraparound)
    pc = (1<<CADDR_WIDTH)-1;  prefix_low = 31;  jump_insn = 8'hFF;  run_one_test(); n_total++;
    // Sequential carries: low 5 bits produce carry, mid addition produces carry too
    pc = 13'b000_0001_1111_1;  prefix_low = 1;   jump_insn = 8'hFF;  run_one_test(); n_total++;
    // Low bits all 1s + low bits all 1s → maximum low carry
    pc = 13'b111_1111_1111_1;  prefix_low = 31;  jump_insn = 8'h80;  run_one_test(); n_total++;
    // Sign extension test: negative offset (jump_insn[7]=1) with small magnitude
    pc = 100;  prefix_low = 1;   jump_insn = 8'hFF;  run_one_test(); n_total++;
    // Sign extension test: positive offset (jump_insn[7]=0)
    pc = 100;  prefix_low = 1;   jump_insn = 8'h00;  run_one_test(); n_total++;
    // Zero prefix_low, nonzero jump_insn
    pc = 42;   prefix_low = 0;   jump_insn = 8'hA5;  run_one_test(); n_total++;
    // Zero jump_insn, nonzero prefix_low
    pc = 42;   prefix_low = 17;  jump_insn = 0;      run_one_test(); n_total++;
    // Both zero
    pc = 0;    prefix_low = 0;   jump_insn = 0;      run_one_test(); n_total++;
    // Negative offset with zero low bits
    pc = 500;  prefix_low = 0;   jump_insn = 8'h80;  run_one_test(); n_total++;
    // Offset that changes sign of high part only
    pc = 2048; prefix_low = 0;   jump_insn = 8'hFF;  run_one_test(); n_total++;
    // All ones in pc low bits, carry from low clears high result bit
    pc = 13'b111_1111_1000_0;  prefix_low = 8;  jump_insn = 8'h00; run_one_test(); n_total++;
    // Mid addition overflow: pc_high=255 + offset_high=127 + carry=1 = 383 (>255)
    pc = 13'b111_1111_0000_0;  prefix_low = 31;  jump_insn = 8'h7F; run_one_test(); n_total++;
    // Mid addition underflow: pc_high=0 + offset_high=-128 + carry=0 = -128
    pc = 0;  prefix_low = 0;  jump_insn = 8'h80;  run_one_test(); n_total++;

    // ─── Summary ───
    $display("");
    $display("===========================================================");
    $display("  %0d tests: %0d passed, %0d failed", n_total, pass_count, fail_count);
    $display("===========================================================");

    if (fail_count > 0)
      $fatal(1, "Some tests failed — pipeline arithmetic does NOT match reference");
    else begin
      $display("  *** ALL PASSED ***");
      $finish;
    end
  end

  // ==================================================================
  // Single test execution
  // ==================================================================
  task run_one_test();
    begin
      // ── Check original pipeline (standalone 5-bit adder) ──
      if (result_ref !== result_pl) begin
        $display("  FAIL (pipeline): pc=%5d (0x%03h)  prefix_low=%2d  jump=0x%02h",
                 pc, pc, prefix_low, jump_insn);
        $display("        offset=0x%04h  ref=%5d  pl=%5d",
                 {jump_insn, prefix_low}, result_ref, result_pl);
        $display("        low_sum=%2d (carry=%1d)  mid_sum=%3d",
                 low_sum, low_sum[5], mid_sum);
        fail_count = fail_count + 1;
        return;
      end

      // ── Check Style A (ALU [ ]-style) ──
      if (result_ref !== result_A) begin
        $display("  FAIL (style A):  pc=%5d  prefix_low=%2d  jump=0x%02h",
                 pc, prefix_low, jump_insn);
        $display("        ref=%5d  A=%5d  carry5_A=%1d (alu_c[5]=%1d, pc[5]=%1d)",
                 result_ref, result_A, carry5_A, alu_c_styleA[5], pc[5]);
        $display("        alu_a_styleA=%15b  alu_b_styleA=%13b  alu_c_styleA=%15b",
                 alu_a_styleA, alu_b_styleA, alu_c_styleA);
        fail_count = fail_count + 1;
        return;
      end

      // ── Check Style B (ALU zero-ext) ──
      if (result_ref !== result_B) begin
        $display("  FAIL (style B):  pc=%5d  prefix_low=%2d  jump=0x%02h",
                 pc, prefix_low, jump_insn);
        $display("        ref=%5d  B=%5d  carry5_B=%1d (alu_c[5]=%1d, pc[5]=%1d)",
                 result_ref, result_B, carry5_B, alu_c_styleB[5], pc[5]);
        $display("        alu_b_styleB=%13b  alu_c_styleB=%15b",
                 alu_b_styleB, alu_c_styleB);
        fail_count = fail_count + 1;
        return;
      end

      pass_count = pass_count + 1;
    end
  endtask

endmodule
