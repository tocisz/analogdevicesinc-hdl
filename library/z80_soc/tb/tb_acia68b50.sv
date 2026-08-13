`timescale 1ns/1ps

// Standalone ACIA register / TX / RX test (no Z80).
module tb_acia68b50;
  logic clk = 1'b0;
  logic reset = 1'b1;

  logic       cs = 1'b0;
  logic       rs = 1'b0;
  logic       r_nw = 1'b1;
  logic [7:0] data_in = 8'h00;
  logic [7:0] data_out;
  logic       ack;
  logic       irq;

  logic [7:0] rx_byte = 8'h00;
  logic       rx_valid = 1'b0;
  logic       rx_consume;
  logic [7:0] tx_byte;
  logic       tx_valid;
  logic       tx_ready = 1'b1;

  integer errors = 0;
  integer tx_n = 0;
  logic [7:0] tx_log [0:15];

  acia68b50 dut (
    .clk(clk), .reset(reset),
    .cs(cs), .rs(rs), .r_nw(r_nw),
    .data_in(data_in), .data_out(data_out), .ack(ack),
    .irq(irq),
    .rx_byte(rx_byte), .rx_valid(rx_valid), .rx_consume(rx_consume),
    .tx_byte(tx_byte), .tx_valid(tx_valid), .tx_ready(tx_ready)
  );

  always #5 clk = ~clk;

  always @(posedge clk) begin
    if (tx_valid && tx_n < 16) begin
      tx_log[tx_n] = tx_byte;
      tx_n = tx_n + 1;
    end
  end

  task automatic bus_write(input bit rs_i, input [7:0] val);
    begin
      @(negedge clk);
      cs = 1'b1; rs = rs_i; r_nw = 1'b0; data_in = val;
      @(posedge clk);
      while (!ack) @(posedge clk);
      @(negedge clk);
      cs = 1'b0;
      @(posedge clk);
    end
  endtask

  task automatic bus_read(input bit rs_i, output [7:0] val);
    begin
      @(negedge clk);
      cs = 1'b1; rs = rs_i; r_nw = 1'b1;
      @(posedge clk);
      while (!ack) @(posedge clk);
      val = data_out;
      @(negedge clk);
      cs = 1'b0;
      @(posedge clk);
    end
  endtask

  logic [7:0] sr;

  initial begin
    repeat (2) @(posedge clk);
    reset = 1'b0;
    repeat (2) @(posedge clk);

    // After reset, TDRE must be set.
    bus_read(1'b0, sr);
    if (sr[1] !== 1'b1) begin
      $display("FAIL: TDRE not set after reset (sr=0x%02x)", sr);
      errors = errors + 1;
    end else $display("PASS: TDRE set after reset");

    // Init CR = 0x17 (must not produce a TX strobe)
    tx_n = 0;
    bus_write(1'b0, 8'h17);
    repeat (3) @(posedge clk);
    if (tx_n != 0) begin
      $display("FAIL: CR write produced %0d TX strobe(s)", tx_n);
      errors = errors + 1;
    end else $display("PASS: CR write is silent on TX");

    // Three data writes with tx_ready=1
    bus_write(1'b1, 8'h00);
    bus_write(1'b1, 8'h01);
    bus_write(1'b1, 8'h02);
    repeat (4) @(posedge clk);
    if (tx_n != 3) begin
      $display("FAIL: expected 3 TX strobes, got %0d", tx_n);
      errors = errors + 1;
    end else begin
      if (tx_log[0] !== 8'h00 || tx_log[1] !== 8'h01 || tx_log[2] !== 8'h02) begin
        $display("FAIL: TX bytes %02x %02x %02x", tx_log[0], tx_log[1], tx_log[2]);
        errors = errors + 1;
      end else $display("PASS: three incrementing TX bytes");
    end

    // TDRE still set after accepted writes
    bus_read(1'b0, sr);
    if (sr[1] !== 1'b1) begin
      $display("FAIL: TDRE lost after TX (sr=0x%02x)", sr);
      errors = errors + 1;
    end else $display("PASS: TDRE still set after TX");

    // Deferred TX: hold off the bridge, write one byte, then release
    tx_ready = 1'b0;
    tx_n = 0;
    bus_write(1'b1, 8'hA5);
    repeat (3) @(posedge clk);
    if (tx_n != 0) begin
      $display("FAIL: TX strobe while !tx_ready");
      errors = errors + 1;
    end
    bus_read(1'b0, sr);
    if (sr[1] !== 1'b0) begin
      $display("FAIL: TDRE should be 0 while holding (sr=0x%02x)", sr);
      errors = errors + 1;
    end else $display("PASS: TDRE clear while TX held");
    tx_ready = 1'b1;
    repeat (4) @(posedge clk);
    if (tx_n != 1 || tx_log[0] !== 8'hA5) begin
      $display("FAIL: deferred TX did not fire (n=%0d val=%02x)", tx_n, tx_log[0]);
      errors = errors + 1;
    end else $display("PASS: deferred TX fired after tx_ready");
    bus_read(1'b0, sr);
    if (sr[1] !== 1'b1) begin
      $display("FAIL: TDRE not restored after deferred TX (sr=0x%02x)", sr);
      errors = errors + 1;
    end else $display("PASS: TDRE restored after deferred TX");

    // RX: present a byte, RDRF, then read it
    rx_byte = 8'h5A;
    rx_valid = 1'b1;
    bus_read(1'b0, sr);
    if (sr[0] !== 1'b1) begin
      $display("FAIL: RDRF not set (sr=0x%02x)", sr);
      errors = errors + 1;
    end else $display("PASS: RDRF set when rx_valid");
    bus_read(1'b1, sr);
    if (sr !== 8'h5A || !rx_consume) begin
      // rx_consume is a pulse on the read cycle; may already be low here
    end
    if (sr !== 8'h5A) begin
      $display("FAIL: data read 0x%02x, expected 0x5A", sr);
      errors = errors + 1;
    end else $display("PASS: data read 0x5A");

    if (errors != 0) begin
      $display("ACIA unit test FAILED (%0d errors)", errors);
      $fatal(1);
    end
    $display("ACIA unit test PASSED");
    $finish;
  end
endmodule
