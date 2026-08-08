`default_nettype none
`timescale 1 ns / 1 ps

// ==========================================================================
// Integration testbench: bf1_soc + uart_phy over a real serial link
// ==========================================================================
// Wires bf1_soc and uart_phy exactly as system_bd.tcl does and drives
// real 115200-baud serial frames into uart_rx_i.  Unlike tb_bf1_soc
// (which drives io_rx_valid directly), this exercises the FULL
// rx_accept_i / rx_valid holding-register handshake, the bf1_ce
// half-speed clock enable, and the TX strobe path — the classes of
// bugs the unit testbench cannot see:
//   1. RX deadlock: uart_phy presents data only while rx_accept_i=1,
//      so io_rx_ready must be high while the CPU waits at ','.
//   2. RX byte-drop: uart_phy consumes a presented byte at any posedge
//      where rx_valid && rx_accept_i, but the CPU captures io_din only
//      at cpu_active posedges (every other cycle, bf1_ce).
//   3. TX byte-drop: the io_tx_valid strobe must never fire while
//      uart_phy is busy (back-to-back '.' instructions).
// ==========================================================================

module tb_bf1_soc_uart;

  localparam CLK_FREQ   = 100000000;
  localparam BAUD       = 115200;
  localparam BIT_CYCLES = CLK_FREQ / BAUD;   // ~868
  localparam HALF_BIT   = BIT_CYCLES / 2;

  // ==================================================================
  // DUT signals
  // ==================================================================
  reg         clk_i;
  reg         resetq;
  reg         uart_rx_i;
  wire        uart_tx_o;
  wire [7:0]  rx_data;
  wire        rx_valid;
  wire        rx_accept;
  wire [7:0]  tx_data;
  wire        tx_start;
  wire        tx_ready;
  wire [12:0] debug_pc;
  wire [3:0]  debug_rsp;
  reg  [31:0] ctrl_gp0_out;
  reg  [31:0] ctrl_gp1_out;
  reg  [31:0] ctrl_gp2_out;
  wire [31:0] ctrl_gp0_in;
  wire [31:0] ctrl_gp1_in;
  wire [31:0] ctrl_gp2_in;

  // ==================================================================
  // DUT + PHY — connections mirror system_bd.tcl
  // ==================================================================
  bf1_soc dut (
    .clk_i(clk_i),
    .resetq(resetq),
    .io_rx_data(rx_data),
    .io_rx_valid(rx_valid),
    .io_rx_ready(rx_accept),
    .io_tx_data(tx_data),
    .io_tx_valid(tx_start),
    .io_tx_ready(tx_ready),
    .debug_pc(debug_pc),
    .debug_rsp(debug_rsp),
    .ctrl_gp0_out(ctrl_gp0_out),
    .ctrl_gp1_out(ctrl_gp1_out),
    .ctrl_gp2_out(ctrl_gp2_out),
    .ctrl_gp0_in(ctrl_gp0_in),
    .ctrl_gp1_in(ctrl_gp1_in),
    .ctrl_gp2_in(ctrl_gp2_in)
  );

  uart_phy #(
    .ClkFreq(CLK_FREQ),
    .Baud(BAUD)
  ) phy (
    .clk(clk_i),
    .reset(!resetq),
    .uart_rx_i(uart_rx_i),
    .uart_tx_o(uart_tx_o),
    .rx_data(rx_data),
    .rx_valid(rx_valid),
    .rx_ready(),
    .rx_accept_i(rx_accept),
    .tx_data(tx_data),
    .tx_start(tx_start),
    .tx_ready(tx_ready)
  );

  // ==================================================================
  // Clock — 100 MHz (10 ns period)
  // ==================================================================
  initial clk_i = 0;
  always #5 clk_i = ~clk_i;

  // ==================================================================
  // Test scoreboard (declared before tasks that reference it)
  // ==================================================================
  integer pass_count, fail_count;

  // ==================================================================
  // PS register tasks (identical to tb_bf1_soc)
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

  // ==================================================================
  // Serial stimulus — drive one UART frame (start, 8 data LSB-first, stop)
  // ==================================================================
  task serial_send(input [7:0] b);
    integer i;
    begin
      uart_rx_i <= 1'b0;                          // start bit
      repeat (BIT_CYCLES) @(posedge clk_i);
      for (i = 0; i < 8; i = i + 1) begin
        uart_rx_i <= b[i];
        repeat (BIT_CYCLES) @(posedge clk_i);
      end
      uart_rx_i <= 1'b1;                          // stop bit
      repeat (BIT_CYCLES) @(posedge clk_i);
    end
  endtask

  // ==================================================================
  // Serial monitor — receive one UART frame (with timeout)
  // Samples at bit centres; ±a few clk skew is harmless (868 clk cells).
  // ==================================================================
  task serial_recv(output [7:0] b, input integer timeout);
    integer i, t;
    begin
      b = 8'h00;
      t = 0;
      while (uart_tx_o === 1'b1 && t < timeout) begin
        @(posedge clk_i);
        t = t + 1;
      end
      if (t >= timeout) begin
        $display("  ERROR: serial_recv timed out after %0d cycles (PC=%0d halted=%0b)",
                 timeout, debug_pc, ctrl_gp0_in[0]);
        b = 8'hFF;
      end else begin
        // Move to the centre of data bit 0, then sample each bit
        repeat (HALF_BIT + BIT_CYCLES) @(posedge clk_i);
        for (i = 0; i < 8; i = i + 1) begin
          b[i] = uart_tx_o;
          if (i < 7) repeat (BIT_CYCLES) @(posedge clk_i);
        end
        // Let the stop bit finish before returning
        repeat (BIT_CYCLES) @(posedge clk_i);
      end
    end
  endtask

  // ==================================================================
  // echo_check — send one byte, expect it echoed back.
  // pre_gap (clk cycles) varies byte-arrival phase vs. bf1_ce.
  // ==================================================================
  task echo_check(input [7:0] b, input integer pre_gap);
    reg [7:0] e;
    begin
      fork
        begin
          repeat (pre_gap) @(posedge clk_i);
          serial_send(b);
        end
        begin
          serial_recv(e, 1000000);
        end
      join
      if (e == b) begin
        $display("  PASS: echoed 0x%0h (gap %0d)", b, pre_gap);
        pass_count = pass_count + 1;
      end else begin
        $display("  FAIL: sent 0x%0h, got 0x%0h (gap %0d)", b, e, pre_gap);
        fail_count = fail_count + 1;
      end
    end
  endtask

  // ==================================================================
  // Tests
  // ==================================================================
  reg [7:0] rb;

  initial begin
    pass_count = 0;
    fail_count = 0;

    resetq      = 0;
    uart_rx_i   = 1'b1;   // UART idle
    ctrl_gp0_out = 0;
    ctrl_gp1_out = 0;
    ctrl_gp2_out = 0;

    #200;
    resetq = 1;
    #200;

    // ==============================================================
    // Test 1: ",." — echo one byte over the real serial link
    // bf1 bytecode: , = 0xC0, . = 0xE0
    // ==============================================================
    $display("--- Test 1: ,. echo (real serial) ---");
    gp2_write(0, 8'hC0);  // ,
    gp2_write(1, 8'hE0);  // .
    gp0_cmd(4'h8);        // RUN

    // The CPU must stall at ',' waiting for input — uart_tx_o must
    // stay idle (no spurious TX strobes) the whole time.
    repeat (20000) @(posedge clk_i);
    if (uart_tx_o === 1'b1) begin
      $display("  PASS: no spurious TX while CPU waits for input");
      pass_count = pass_count + 1;
    end else begin
      $display("  FAIL: spurious TX activity while CPU waits for input");
      fail_count = fail_count + 1;
    end

    echo_check(8'h41, 0);   // 'A'

    gp0_cmd(4'h1);  // HALT
    #100;
    gp0_cmd(4'h2);  // RESET
    #100;

    // ==============================================================
    // Test 2: ",[.,]" — echo loop, phase-varying byte arrivals
    // bf1 bytecode: ,=0xC0 [=0x84 .=0xE0 ,=0xC0 ]=0x80
    // Odd/even gaps hit both bf1_ce phases; a dropped byte anywhere
    // breaks the echo and fails the test.
    // ==============================================================
    $display("--- Test 2: ,[.,] echo loop (phase sweep) ---");
    gp2_write(0, 8'hC0);  // ,
    gp2_write(1, 8'h84);  // [
    gp2_write(2, 8'hE0);  // .
    gp2_write(3, 8'hC0);  // ,
    gp2_write(4, 8'h80);  // ]
    gp0_cmd(4'h8);        // RUN

    echo_check(8'h41, 0);      // sent right after RUN (byte waits in FIFO)
    echo_check(8'h42, 217);    // odd gap
    echo_check(8'h43, 868);    // even gap
    echo_check(8'h44, 1);      // minimal odd gap

    // Send NUL to terminate the loop (cell==0 → '[' jumps past ']')
    serial_send(8'h00);
    #1000;
    gp0_cmd(4'h1);  // HALT
    #100;
    gp0_cmd(4'h2);  // RESET
    #100;

    // ==============================================================
    // Test 3: "+.." — back-to-back output bytes
    // The second '.' executes while uart_phy is still busy with the
    // first byte: the CPU must stall at '.' and transmit BOTH bytes.
    // bf1 bytecode: + = 0x41, . = 0xE0
    // ==============================================================
    $display("--- Test 3: +.. back-to-back output ---");
    gp2_write(0, 8'h41);  // +
    gp2_write(1, 8'hE0);  // .
    gp2_write(2, 8'hE0);  // .
    gp0_cmd(4'h8);        // RUN

    serial_recv(rb, 500000);
    if (rb == 8'h01) begin
      $display("  PASS: first byte = 0x01");
      pass_count = pass_count + 1;
    end else begin
      $display("  FAIL: first byte = 0x%0h (expected 0x01)", rb);
      fail_count = fail_count + 1;
    end

    serial_recv(rb, 500000);
    if (rb == 8'h01) begin
      $display("  PASS: second byte = 0x01 (TX-busy stall worked)");
      pass_count = pass_count + 1;
    end else begin
      $display("  FAIL: second byte = 0x%0h (expected 0x01 — dropped?)", rb);
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
`default_nettype wire
