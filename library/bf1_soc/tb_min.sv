`default_nettype none
`timescale 1 ns / 1 ps

module tb_min;
  reg clk_i, resetq;
  reg [31:0] ctrl_gp0_out, ctrl_gp1_out, ctrl_gp2_out;
  wire [31:0] ctrl_gp0_in, ctrl_gp1_in, ctrl_gp2_in;
  reg [7:0] io_rx_data;
  reg io_rx_valid, io_tx_ready;
  wire io_rx_ready;
  wire [7:0] io_tx_data;
  wire io_tx_valid;
  wire [12:0] debug_pc;
  wire [3:0] debug_rsp;

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

  initial begin
    $display("[%0t] START", $time);
    resetq = 0;
    io_rx_data = 0; io_rx_valid = 0; io_tx_ready = 1;
    ctrl_gp0_out = 0; ctrl_gp1_out = 0; ctrl_gp2_out = 0;
    $display("[%0t] Reset low", $time);
    #100;
    $display("[%0t] Releasing reset", $time);
    resetq = 1;
    #100;
    $display("[%0t] After reset release, halted=%b", $time, ctrl_gp0_in[0]);
    #100;
    $display("[%0t] DONE", $time);
    $finish;
  end
endmodule
