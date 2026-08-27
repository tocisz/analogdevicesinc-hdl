`default_nettype none
`timescale 1ns/1ps

// Verify the interrupt contract used by axi-byte-fifo.  RC is latched when
// RX changes empty -> non-empty, cleared by ISR W1C, and reasserted after the
// FIFO is drained and a later byte arrives.  This is the wakeup which makes
// a blocked userspace poll() reliable for sparse Z80 output.
module tb_axi_byte_fifo_irq;
  logic clk = 1'b0;
  logic resetn = 1'b0;
  always #5 clk = ~clk;

  logic [31:0] awaddr = 0, wdata = 0, araddr = 0;
  logic awvalid = 0, wvalid = 0, bready = 0;
  logic arvalid = 0, rready = 0;
  wire awready, wready, bvalid, arready, rvalid;
  wire [31:0] rdata;
  logic rxd_valid = 0;
  wire rxd_ready;
  logic [7:0] rxd_data = 0;
  wire txd_valid;
  logic txd_ready = 1'b1;
  wire [7:0] txd_data;
  wire interrupt;

  axi_byte_fifo dut (
      .s_axi_aclk(clk), .s_axi_aresetn(resetn), .interrupt(interrupt),
      .s_axi_awaddr(awaddr), .s_axi_awvalid(awvalid), .s_axi_awready(awready),
      .s_axi_wdata(wdata), .s_axi_wstrb(4'hf), .s_axi_wvalid(wvalid),
      .s_axi_wready(wready), .s_axi_bresp(), .s_axi_bvalid(bvalid),
      .s_axi_bready(bready), .s_axi_araddr(araddr), .s_axi_arvalid(arvalid),
      .s_axi_arready(arready), .s_axi_rresp(), .s_axi_rdata(rdata),
      .s_axi_rvalid(rvalid), .s_axi_rready(rready),
      .mm2s_prmry_reset_out_n(), .axi_str_txd_tvalid(txd_valid),
      .axi_str_txd_tready(txd_ready), .axi_str_txd_tdata(txd_data),
      .s2mm_prmry_reset_out_n(), .axi_str_rxd_tvalid(rxd_valid),
      .axi_str_rxd_tready(rxd_ready), .axi_str_rxd_tdata(rxd_data));

  task automatic axil_write(input logic [6:0] addr, input logic [31:0] value);
    begin
      @(negedge clk);
      awaddr = addr; wdata = value; awvalid = 1'b1; wvalid = 1'b1;
      @(posedge clk);
      @(negedge clk);
      awvalid = 1'b0; wvalid = 1'b0; bready = 1'b1;
      while (!bvalid) @(posedge clk);
      @(negedge clk); bready = 1'b0;
    end
  endtask

  task automatic axil_read(input logic [6:0] addr, output logic [31:0] value);
    begin
      @(negedge clk); araddr = addr; arvalid = 1'b1;
      @(posedge clk);
      @(negedge clk); arvalid = 1'b0; rready = 1'b1;
      while (!rvalid) @(posedge clk);
      value = rdata;
      @(negedge clk); rready = 1'b0;
    end
  endtask

  task automatic receive_byte(input logic [7:0] value);
    begin
      @(negedge clk); rxd_data = value; rxd_valid = 1'b1;
      while (!rxd_ready) @(posedge clk);
      @(posedge clk);
      @(negedge clk); rxd_valid = 1'b0;
    end
  endtask

  logic [31:0] value;
  initial begin
    repeat (3) @(posedge clk);
    resetn = 1'b1;
    repeat (2) @(posedge clk);

    // Enable RC (bit 26), then clear the reset status bits.
    axil_write(7'h04, 32'h04000000);
    axil_write(7'h00, 32'hFFFFFFFF);
    if (interrupt) $fatal(1, "interrupt asserted before RX data");

    receive_byte(8'h41);
    if (!interrupt) $fatal(1, "interrupt did not assert on first RX byte");

    axil_write(7'h00, 32'h04000000);
    if (interrupt) $fatal(1, "ISR W1C did not clear RC");
    axil_read(7'h1c, value);
    if (value != 1) $fatal(1, "RDFO=%0d, expected 1", value);
    axil_read(7'h20, value);
    if (value != 8'h41) $fatal(1, "RDFD=0x%02x, expected 0x41", value);

    receive_byte(8'h42);
    if (!interrupt) $fatal(1, "interrupt did not reassert after FIFO emptied");

    $display("axi_byte_fifo RX interrupt test PASSED");
    $finish;
  end

  initial begin
    #5000;
    $fatal(1, "timeout");
  end
endmodule
`default_nettype wire
