`default_nettype none
`timescale 1 ns / 1 ps

// ==========================================================================
// Testbench for bf1_soc
// ==========================================================================
// Tests the bf1_soc module through its register and UART interfaces.
// Programs are loaded into code RAM via the GP2 control interface,
// data RAM is accessed via GP1, and UART I/O is tested via the
// io_rx_data/io_tx_data ports.
// ==========================================================================

module tb_bf1_soc;

  // ==================================================================
  // DUT signals
  // ==================================================================
  reg        clk_i;
  reg        resetq;
  reg  [7:0] io_rx_data;
  reg        io_rx_valid;
  wire       io_rx_ready;
  wire [7:0] io_tx_data;
  wire       io_tx_valid;
  reg        io_tx_ready;
  wire [12:0] debug_pc;
  wire [3:0]  debug_rsp;
  reg  [31:0] ctrl_gp0_out;
  reg  [31:0] ctrl_gp1_out;
  reg  [31:0] ctrl_gp2_out;
  wire [31:0] ctrl_gp0_in;
  wire [31:0] ctrl_gp1_in;
  wire [31:0] ctrl_gp2_in;

  // ==================================================================
  // DUT
  // ==================================================================
  bf1_soc dut (
    .clk_i(clk_i),
    .resetq(resetq),
    .io_rx_data(io_rx_data),
    .io_rx_valid(io_rx_valid),
    .io_rx_ready(io_rx_ready),
    .io_tx_data(io_tx_data),
    .io_tx_valid(io_tx_valid),
    .io_tx_ready(io_tx_ready),
    .debug_pc(debug_pc),
    .debug_rsp(debug_rsp),
    .ctrl_gp0_out(ctrl_gp0_out),
    .ctrl_gp1_out(ctrl_gp1_out),
    .ctrl_gp2_out(ctrl_gp2_out),
    .ctrl_gp0_in(ctrl_gp0_in),
    .ctrl_gp1_in(ctrl_gp1_in),
    .ctrl_gp2_in(ctrl_gp2_in)
  );

  // ==================================================================
  // Clock — 100 MHz (10 ns period)
  // ==================================================================
  initial clk_i = 0;
  always #5 clk_i = ~clk_i;

  // ==================================================================
  // Helper tasks
  // ==================================================================

  task gp2_write(input [12:0] addr, input [7:0] data);
    begin
      @(posedge clk_i);
      ctrl_gp2_out <= {6'b0, 1'b0, 1'b1, data, 3'b0, addr};
      @(posedge clk_i);
      while (!ctrl_gp2_in[8]) @(posedge clk_i);
      ctrl_gp2_out <= 0;
      @(posedge clk_i);
      while (ctrl_gp2_in[8]) @(posedge clk_i);
    end
  endtask

  task gp1_write(input [14:0] addr, input [7:0] data);
    begin
      @(posedge clk_i);
      ctrl_gp1_out <= {6'b0, 1'b0, 1'b1, data, 1'b0, addr};
      @(posedge clk_i);
      while (!ctrl_gp1_in[8]) @(posedge clk_i);
      ctrl_gp1_out <= 0;
      @(posedge clk_i);
      while (ctrl_gp1_in[8]) @(posedge clk_i);
    end
  endtask

  task gp1_read(input [14:0] addr, output [7:0] rdata);
    begin
      @(posedge clk_i);
      ctrl_gp1_out <= {6'b0, 1'b1, 1'b0, 8'b0, 1'b0, addr};
      @(posedge clk_i);
      while (!ctrl_gp1_in[8]) @(posedge clk_i);
      rdata = ctrl_gp1_in[7:0];
      ctrl_gp1_out <= 0;
      @(posedge clk_i);
      while (ctrl_gp1_in[8]) @(posedge clk_i);
    end
  endtask

  task gp0_cmd(input [3:0] bits);
    begin
      @(posedge clk_i);
      ctrl_gp0_out <= {28'b0, bits};
      @(posedge clk_i);
      ctrl_gp0_out <= 0;
    end
  endtask

  task uart_send(input [7:0] data_byte);
    begin
      // Standard valid/ready source: assert valid, then wait for the
      // posedge at which io_rx_ready is high — that is the capture edge
      // (io_rx_ready is high only on the cycle the CPU actually consumes
      // the byte).  Then deassert valid.
      @(posedge clk_i);
      io_rx_data  <= data_byte;
      io_rx_valid <= 1;
      @(posedge clk_i);
      while (!io_rx_ready) @(posedge clk_i);
      // Byte captured at the last posedge — clear valid
      io_rx_valid <= 0;
      @(posedge clk_i);  // Let the clear propagate before returning
    end
  endtask

  task uart_recv(output [7:0] data_byte);
    begin
      while (!io_tx_valid) @(posedge clk_i);
      data_byte = io_tx_data;
      @(posedge clk_i);  // wait one cycle so DUT sees io_tx_ready=1 and clears io_tx_valid
    end
  endtask

  // ==================================================================
  // Tests
  // ==================================================================
  integer pass_count, fail_count;
  reg [7:0] rbyte;
  reg [7:0] captured_tx_data;
  reg       captured_tx_valid;

  // Capture TX output (io_tx_valid is a single-cycle strobe)
  // We accumulate received bytes in a simple queue for tests to check
  reg [7:0] tx_queue [0:15];
  reg [3:0] tx_wr_ptr;
  reg [3:0] tx_rd_ptr;

  always @(posedge clk_i or negedge resetq) begin
    if (!resetq) begin
      tx_wr_ptr <= 0;
      tx_rd_ptr <= 0;
    end else if (io_tx_valid) begin
      tx_queue[tx_wr_ptr[3:0]] <= io_tx_data;
      tx_wr_ptr <= tx_wr_ptr + 1;
    end
  end

  // Legacy capture for simple tests (still used by Test 1)
  always @(posedge clk_i) begin
    if (io_tx_valid) begin
      captured_tx_data  <= io_tx_data;
      captured_tx_valid <= 1;
    end else begin
      captured_tx_valid <= 0;
    end
  end

  task uart_recv_q(output [7:0] data_byte);
    begin
      while (tx_rd_ptr == tx_wr_ptr) @(posedge clk_i);
      data_byte = tx_queue[tx_rd_ptr[3:0]];
      tx_rd_ptr <= tx_rd_ptr + 1;
    end
  endtask

  initial begin
    pass_count = 0;
    fail_count = 0;

    // Initialize
    resetq = 0;
    io_rx_data = 0;
    io_rx_valid = 0;
    io_tx_ready = 1;
    ctrl_gp0_out = 0;
    ctrl_gp1_out = 0;
    ctrl_gp2_out = 0;

    #20;
    resetq = 1;
    #20;

    // ==============================================================
    // Test 1: "+." — increment and output
    // bf1 bytecode: + (count 1) = 0x41, . = 0xE0
    // ==============================================================
    $display("--- Test 1: +. program ---");
    gp2_write(0, 8'h41);  // +
    gp2_write(1, 8'hE0);  // .
    gp0_cmd(4'h8);        // RUN

    uart_recv_q(rbyte);
    if (rbyte == 8'h01) begin
      $display("  PASS: output = 0x01");
      pass_count = pass_count + 1;
    end else begin
      $display("  FAIL: output = 0x%0h", rbyte);
      fail_count = fail_count + 1;
    end
    gp0_cmd(4'h1);  // HALT
    #100;

    // Reset between tests to clear CPU state
    $display("--- Reset between tests ---");
    gp0_cmd(4'h2);  // RESET
    #50;

    // ==============================================================
    // Test 2: ",." — echo one byte
    // bf1 bytecode: , = 0xC0, . = 0xE0
    // ==============================================================
    $display("--- Test 2: ,. echo ---");
    gp2_write(0, 8'hC0);  // ,
    gp2_write(1, 8'hE0);  // .
    gp0_cmd(4'h8);        // RUN

    fork
      begin : sender
        #50;
        uart_send(8'h41);  // 'A'
      end
      begin : receiver
        uart_recv_q(rbyte);
        if (rbyte == 8'h41) begin
          $display("  PASS: echo = 0x41 ('A')");
          pass_count = pass_count + 1;
        end else begin
          $display("  FAIL: echo = 0x%0h", rbyte);
          fail_count = fail_count + 1;
        end
      end
    join
    gp0_cmd(4'h1);  // HALT
    #100;

    // Reset between tests to clear CPU state
    gp0_cmd(4'h2);  // RESET
    #50;

    // ==============================================================
    // Test 3: ",[.,]" — echo loop (exit on NUL)
    // bf1 bytecode: ,=0xC0, [=0x84 (jump offset 4), .=0xE0, ,=0xC0, ]=0x80
    // ==============================================================
    $display("--- Test 3: echo loop ,[.,] ---");
    gp2_write(0, 8'hC0);  // ,
    gp2_write(1, 8'h84);  // [ (jump forward 4 bytes if cell==0)
    gp2_write(2, 8'hE0);  // .
    gp2_write(3, 8'hC0);  // ,
    gp2_write(4, 8'h80);  // ]
    gp0_cmd(4'h8);        // RUN

    // Send 'H', wait for echo, send 'i', wait for echo, send NUL
    #100;
    uart_send(8'h48);  // 'H'

    uart_recv_q(rbyte);
    if (rbyte == 8'h48) begin
      $display("  PASS: recv 'H'");
      pass_count = pass_count + 1;
    end else begin
      $display("  FAIL: expected 'H' got 0x%0h", rbyte);
      fail_count = fail_count + 1;
    end

    #50;
    uart_send(8'h69);  // 'i'

    uart_recv_q(rbyte);
    if (rbyte == 8'h69) begin
      $display("  PASS: recv 'i'");
      pass_count = pass_count + 1;
    end else begin
      $display("  FAIL: expected 'i' got 0x%0h", rbyte);
      fail_count = fail_count + 1;
    end

    // Send NUL to terminate loop
    #50;
    uart_send(8'h00);
    gp0_cmd(4'h1);  // HALT
    #100;

    // Reset between tests to clear CPU state
    gp0_cmd(4'h2);  // RESET
    #50;

    // ==============================================================
    // Test 4: Data RAM access (peek/poke)
    // ==============================================================
    $display("--- Test 4: Data RAM access ---");
    gp1_write(16'h100, 8'hAB);
    gp1_read(16'h100, rbyte);
    if (rbyte == 8'hAB) begin
      $display("  PASS: RAM[0x100] = 0xAB");
      pass_count = pass_count + 1;
    end else begin
      $display("  FAIL: RAM[0x100] = 0x%0h", rbyte);
      fail_count = fail_count + 1;
    end

    // ==============================================================
    // Test 5: Status register
    // ==============================================================
    $display("--- Test 5: Status register ---");
    if (ctrl_gp0_in[0]) begin
      $display("  PASS: CPU halted flag set");
      pass_count = pass_count + 1;
    end else begin
      $display("  FAIL: CPU should be halted");
      fail_count = fail_count + 1;
    end

    // ==============================================================
    // Test 6: Long jump — conditional skip (cell = 0)
    // ==============================================================
    // New encoding: offset = {jump_insn[7:0], prefix_insn[4:0]}
    //   offset = +3  →  prefix_low = 3, jump_byte = 0
    //   prefix byte = 0b101_00011 = 0xA3, jump byte = 0x00
    //
    // After RESET, data.ptr=0, cell[0]=0.
    // Long jump `[` should check cell:
    //   cell == 0 → jump forward by offset (skip the loop body)
    //   cell != 0 → push return address, enter loop body
    //
    // Program (cell=0 → skip forward):
    //   0: prefix (0xA3)   long jump +3  → target = 3
    //   1: jump    (0x00)
    //   2: .  (0xE0)       [entered if no-skip: output 0]
    //   3: +  (0x41)       [skipped-to if cell==0: cell = 1]
    //   4: .  (0xE0)       output (1 if skip, 0 if no-skip)
    //
    // Expected: 0x01 (skip forward)
    // Fail (no-skip, falls through): 0x00
    // ==============================================================
    gp0_cmd(4'h2);  // RESET
    #50;
    $display("--- Test 6: Long jump conditional skip (cell=0) ---");
    gp2_write(0, 8'hA3);  // prefix (offset_low=3)
    gp2_write(1, 8'h00);  // jump_byte (offset_high=0)
    gp2_write(2, 8'hE0);  // .  (should be skipped if cell==0)
    gp2_write(3, 8'h41);  // +
    gp2_write(4, 8'hE0);  // .
    gp0_cmd(4'h8);        // RUN

    uart_recv_q(rbyte);
    if (rbyte == 8'h01) begin
      $display("  PASS: output = 0x01 (long jump skipped past '.' correctly)");
      pass_count = pass_count + 1;
    end else if (rbyte == 8'h00) begin
      $display("  FAIL: output = 0x00 (long jump did NOT skip past '.')");
      fail_count = fail_count + 1;
    end else begin
      $display("  FAIL: unexpected output = 0x%0h", rbyte);
      fail_count = fail_count + 1;
    end
    gp0_cmd(4'h1);  // HALT
    #100;

    // ==============================================================
    // Test 7: Long jump — conditional enter-loop (cell != 0)
    // ==============================================================
    // Same offset = +3.  Cell != 0 → push return address and
    // enter the loop body (execute `.` at address 4), not skip.
    //
    // NOTE: PS RESET (gp0_cmd 4'h2) clears CPU registers (pc, ptr, etc.)
    // but does NOT clear data RAM.  Cell[0] = 1 from Test 6's `+`.
    //
    // Program (cell=1 → + makes 2 → + makes 3 → enter loop body
    //          with output 3):
    //   0: +  (0x41)       cell = 2 (was 1 from Test 6)
    //   1: +  (0x41)       cell = 3
    //   2: prefix (0xA3)   long jump +3  → target = 5
    //   3: jump    (0x00)
    //   4: .  (0xE0)       [entered if cell!=0: output 3]
    //   5: +  (0x41)       [skipped-to if cell==0: cell = 4]
    //   6: .  (0xE0)       output (3 if entered, 4 if skipped)
    //
    // Expected: 0x03 (loop body entered at addr 4, cell=3)
    // Fail (skipped, jump taken): 0x04 (from addr 6 after +)
    // ==============================================================
    gp0_cmd(4'h2);  // RESET
    #50;
    $display("--- Test 7: Long jump conditional enter-loop (cell!=0) ---");
    gp2_write(0, 8'h41);  // +
    gp2_write(1, 8'h41);  // +
    gp2_write(2, 8'hA3);  // prefix (offset_low=3)
    gp2_write(3, 8'h00);  // jump_byte (offset_high=0)
    gp2_write(4, 8'hE0);  // .  (output 2 if entered)
    gp2_write(5, 8'h41);  // +  (cell=3 if skipped)
    gp2_write(6, 8'hE0);  // .  (output 3 if skipped)
    gp0_cmd(4'h8);        // RUN

    uart_recv_q(rbyte);
    if (rbyte == 8'h03) begin
      $display("  PASS: output = 0x03 (long jump entered loop body at addr 4)");
      pass_count = pass_count + 1;
    end else if (rbyte == 8'h04) begin
      $display("  FAIL: output = 0x04 (long jump skipped past loop body)");
      fail_count = fail_count + 1;
    end else begin
      $display("  FAIL: unexpected output = 0x%0h", rbyte);
      fail_count = fail_count + 1;
    end
    gp0_cmd(4'h1);  // HALT
    #100;

    // ==============================================================
    // Summary
    // ==============================================================
    $display("");
    $display("========================================");
    $display("  %0d passed, %0d failed", pass_count, fail_count);
    $display("========================================");

    if (fail_count > 0)
      $fatal(1, "Some tests failed");
    else
      $finish;
  end

endmodule
