`default_nettype none
`timescale 1 ns / 1 ps

module tb_debug;
  reg clk_i, resetq;
  reg [31:0] ctrl_gp0_out, ctrl_gp1_out, ctrl_gp2_out;
  wire [31:0] ctrl_gp0_in, ctrl_gp1_in, ctrl_gp2_in;
  reg [7:0] io_rx_data;
  reg io_rx_valid;
  wire io_rx_ready;
  wire [7:0] io_tx_data;
  wire io_tx_valid;
  reg io_tx_ready;
  wire [12:0] debug_pc;
  wire [3:0] debug_rsp;

  reg tx_fired;
  reg [7:0] tx_captured;

  bf1_soc dut (
    .clk_i(clk_i), .resetq(resetq),
    .io_rx_data(io_rx_data), .io_rx_valid(io_rx_valid),
    .io_rx_ready(io_rx_ready),
    .io_tx_data(io_tx_data), .io_tx_valid(io_tx_valid),
    .io_tx_ready(io_tx_ready),
    .debug_pc(debug_pc), .debug_rsp(debug_rsp),
    .ctrl_gp0_out(ctrl_gp0_out), .ctrl_gp1_out(ctrl_gp1_out),
    .ctrl_gp2_out(ctrl_gp2_out),
    .ctrl_gp0_in(ctrl_gp0_in), .ctrl_gp1_in(ctrl_gp1_in),
    .ctrl_gp2_in(ctrl_gp2_in)
  );

  initial clk_i = 0;
  always #5 clk_i = ~clk_i;

  always @(posedge clk_i) begin
    if (io_tx_valid && !tx_fired) begin
      tx_fired <= 1;
      tx_captured <= io_tx_data;
      $display("[%0t] TX FIRED: data=0x%0h ('%s') pc=%0d",
               $time, io_tx_data,
               (io_tx_data >= 32 && io_tx_data < 127) ? {io_tx_data[7:0]} : "?",
               debug_pc);
    end
  end

  always @(posedge clk_i) begin
    if (ctrl_gp0_in[0] == 0)
      $display("[%0t] PC=%0d RSP=%0d halted=%b io_ready=%b io_valid=%b",
               $time, debug_pc, debug_rsp, ctrl_gp0_in[0], io_rx_ready, io_rx_valid);
  end

  task gp2_write(input [12:0] addr, input [7:0] data);
    begin
      @(posedge clk_i);
      ctrl_gp2_out <= {6'b0, 1'b0, 1'b1, data, 9'b0, addr};
      @(posedge clk_i);
      while (!ctrl_gp2_in[8]) @(posedge clk_i);
      ctrl_gp2_out <= 0;
      @(posedge clk_i);
      while (ctrl_gp2_in[8]) @(posedge clk_i);
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

  initial begin
    resetq = 0;
    io_rx_data = 0; io_rx_valid = 0; io_tx_ready = 1;
    ctrl_gp0_out = 0; ctrl_gp1_out = 0; ctrl_gp2_out = 0;
    tx_fired = 0; tx_captured = 0;

    #20;
    resetq = 1;
    #20;

    $display("[%0t] === Test: +. program ===", $time);
    gp2_write(0, 8'h41);  // +
    gp2_write(1, 8'hE0);  // .

    $display("[%0t] Status: halted=%b pc=%0d", $time, ctrl_gp0_in[0], debug_pc);

    gp0_cmd(4'h8);  // RUN

    $display("[%0t] After RUN: halted=%b pc=%0d", $time, ctrl_gp0_in[0], debug_pc);

    #200;

    if (tx_fired) begin
      $display("[%0t] PASS: TX captured 0x%0h", $time, tx_captured);
    end else begin
      $display("[%0t] FAIL: No TX output", $time);
    end

    $display("[%0t] Final: halted=%b pc=%0d rsp=%0d", $time, ctrl_gp0_in[0], debug_pc, debug_rsp);
    $finish;
  end
endmodule
