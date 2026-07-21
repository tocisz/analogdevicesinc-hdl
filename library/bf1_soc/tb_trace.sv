`default_nettype none
`timescale 1 ns / 1 ps

module tb_trace;
  reg        clk_i;
  reg        resetq;
  reg  [7:0] io_rx_data;
  reg        io_rx_valid;
  wire       io_rx_ready;
  wire [7:0] io_tx_data;
  wire       io_tx_valid;
  reg        io_tx_ready;
  reg  [31:0] ctrl_gp0_out;
  reg  [31:0] ctrl_gp1_out;
  reg  [31:0] ctrl_gp2_out;
  wire [31:0] ctrl_gp0_in;
  wire [31:0] ctrl_gp1_in;
  wire [31:0] ctrl_gp2_in;

  bf1_soc dut (.*);

  initial clk_i = 0;
  always #5 clk_i = ~clk_i;

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

  task gp0_cmd(input [3:0] bits);
    begin
      @(posedge clk_i);
      ctrl_gp0_out <= {28'b0, bits};
      @(posedge clk_i);
      ctrl_gp0_out <= 0;
    end
  endtask

  initial begin
    $display("Cycle,pc,pcN,code_addr,insn_reg,code_ra_dout,insn,mem_din,data_ra_dout,mem_addr,io_tx_valid,io_tx_data");
    $monitor("%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%b,%0d",
      $time/10, dut.pc, dut.bf1_inst.pcN, dut.code_addr,
      dut.insn_reg, dut.code_ra_dout, dut.insn,
      dut.mem_din, dut.data_ra_dout, dut.mem_addr,
      dut.io_tx_valid, dut.io_tx_data);
  end

  initial begin
    resetq = 0; io_rx_data = 0; io_rx_valid = 0; io_tx_ready = 1;
    ctrl_gp0_out = 0; ctrl_gp1_out = 0; ctrl_gp2_out = 0;
    #20; resetq = 1;
    #30;
    
    $display("--- Loading +. program ---");
    gp2_write(0, 8'h41);  // +
    gp2_write(1, 8'hE0);  // .
    #20;
    
    $display("--- Running ---");
    gp0_cmd(4'h8);  // RUN
    #200;
    
    $display("--- Halting ---");
    gp0_cmd(4'h1);  // HALT
    #100;
    $finish;
  end
endmodule
