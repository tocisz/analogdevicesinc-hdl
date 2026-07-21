`default_nettype none
`timescale 1 ns / 1 ps

module tb_gp2;
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

  integer i;
  initial clk_i = 0;
  always #5 clk_i = ~clk_i;

  initial begin
    $display("[%0t] START", $time);
    resetq = 0;
    io_rx_data = 0; io_rx_valid = 0; io_tx_ready = 1;
    ctrl_gp0_out = 0; ctrl_gp1_out = 0; ctrl_gp2_out = 0;
    #100;
    resetq = 1;
    #50;

    // Write 0x41 (bf1 +) to code_ram[0]
    $display("[%0t] Writing 0x41 to code_ram[0]", $time);
    @(posedge clk_i);
    ctrl_gp2_out <= {6'b0, 1'b0, 1'b1, 8'h41, 9'b0, 13'd0};
    @(posedge clk_i);
    $display("[%0t] WR bit set, waiting for DONE", $time);
    for (i = 0; i < 20; i = i + 1) begin
      @(posedge clk_i);
      $display("[%0t]   ctrl_gp2_in[8]=%b", $time, ctrl_gp2_in[8]);
      if (ctrl_gp2_in[8]) begin
        $display("[%0t] DONE received!", $time);
        i = 20;
      end
    end
    ctrl_gp2_out <= 0;
    @(posedge clk_i);
    $display("[%0t] Cleared, waiting for DONE to clear", $time);
    for (i = 0; i < 20; i = i + 1) begin
      @(posedge clk_i);
      $display("[%0t]   ctrl_gp2_in[8]=%b", $time, ctrl_gp2_in[8]);
      if (!ctrl_gp2_in[8]) begin
        $display("[%0t] DONE cleared!", $time);
        i = 20;
      end
    end

    $display("[%0t] DONE. halted=%b", $time, ctrl_gp0_in[0]);
    $finish;
  end
endmodule
