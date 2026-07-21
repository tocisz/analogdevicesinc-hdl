`default_nettype none
`timescale 1 ns / 1 ps

module tb_echo;
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

  always @(posedge clk_i) begin
    if (!ctrl_gp0_in[0])
      $display("[%0t] pc=%0d halted=%b io_rd=%b io_wr=%b rx_valid=%b rx_ready=%b mem_wr=%b mem_dout=0x%0h",
               $time, debug_pc, ctrl_gp0_in[0], dut.io_rd, dut.io_wr,
               io_rx_valid, io_rx_ready, dut.mem_wr, dut.mem_dout);
    if (io_tx_valid)
      $display("[%0t] >>> TX: 0x%0h ('%s')", $time, io_tx_data,
               (io_tx_data>=32 && io_tx_data<127) ? {io_tx_data[7:0]} : "?");
  end

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

  task gp0_cmd(input [3:0] bits);
    begin
      @(posedge clk_i);
      ctrl_gp0_out <= {28'b0, bits};
      @(posedge clk_i);
      ctrl_gp0_out <= 0;
    end
  endtask

  initial begin
    $display("[%0t] === Echo loop test ===", $time);
    resetq = 0;
    io_rx_data = 0; io_rx_valid = 0; io_tx_ready = 1;
    ctrl_gp0_out = 0; ctrl_gp1_out = 0; ctrl_gp2_out = 0;
    #100;
    resetq = 1;
    #50;

    // Load ,[.,] = {0xC0, 0x84, 0xE0, 0xC0, 0x80}
    gp2_write(0, 8'hC0);
    gp2_write(1, 8'h84);
    gp2_write(2, 8'hE0);
    gp2_write(3, 8'hC0);
    gp2_write(4, 8'h80);

    $display("[%0t] Code loaded, RUN", $time);
    gp0_cmd(4'h8);  // RUN

    // Send 'H' after a small delay
    #100;
    $display("[%0t] Sending 'H' (0x48)", $time);
    io_rx_data <= 8'h48;
    io_rx_valid <= 1;
    @(posedge clk_i);
    $display("[%0t] Waiting for rx_ready", $time);
    while (!io_rx_ready) @(posedge clk_i);
    $display("[%0t] CPU accepted, clearing rx_valid", $time);
    io_rx_valid <= 0;
    @(posedge clk_i);
    $display("[%0t] rx_valid now 0", $time);

    // Wait for TX of 'H', then send 'i'
    #100;
    $display("[%0t] Sending 'i' (0x69)", $time);
    io_rx_data <= 8'h69;
    io_rx_valid <= 1;
    @(posedge clk_i);
    while (!io_rx_ready) @(posedge clk_i);
    $display("[%0t] CPU accepted 'i', clearing", $time);
    io_rx_valid <= 0;
    @(posedge clk_i);

    // Send NUL to terminate
    #100;
    $display("[%0t] Sending NUL", $time);
    io_rx_data <= 8'h00;
    io_rx_valid <= 1;
    @(posedge clk_i);
    while (!io_rx_ready) @(posedge clk_i);
    io_rx_valid <= 0;
    @(posedge clk_i);

    #200;
    $display("[%0t] Done. halted=%b", $time, ctrl_gp0_in[0]);
    $finish;
  end
endmodule
