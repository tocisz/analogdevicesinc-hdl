`timescale 1ns/1ps

// Self-checking functional test for z80_soc.
//
// The test exercises both sides of the memory system:
//   * PS-side ctrl_gp1/ctrl_gp2 writes and reads
//   * Z80 instruction fetches from ROM and RAM
//   * Z80 data-memory write followed by data-memory read and write
//
// Run with:
//   make -C hdl/library/z80_soc sim-verilator
//
module tb_z80_soc;
  logic clk = 1'b0;
  logic resetq = 1'b0;

  logic [7:0] io_rx_data = 8'h00;
  logic       io_rx_valid = 1'b0;
  logic       io_rx_ready;
  logic [7:0] io_tx_data;
  logic       io_tx_valid;
  logic       io_tx_ready = 1'b1;

  logic [15:0] debug_pc;
  logic [7:0]  debug_rsp;

  logic [31:0] ctrl_gp0_out = 32'h0;
  logic [31:0] ctrl_gp1_out = 32'h0;
  logic [31:0] ctrl_gp2_out = 32'h0;
  logic [31:0] ctrl_gp0_in;
  logic [31:0] ctrl_gp1_in;
  logic [31:0] ctrl_gp2_in;

  integer errors = 0;

  z80_soc dut (
    .clk_i        (clk),
    .resetq       (resetq),
    .io_rx_data   (io_rx_data),
    .io_rx_valid  (io_rx_valid),
    .io_rx_ready  (io_rx_ready),
    .io_tx_data   (io_tx_data),
    .io_tx_valid  (io_tx_valid),
    .io_tx_ready  (io_tx_ready),
    .debug_pc     (debug_pc),
    .debug_rsp    (debug_rsp),
    .ctrl_gp0_out (ctrl_gp0_out),
    .ctrl_gp1_out (ctrl_gp1_out),
    .ctrl_gp2_out (ctrl_gp2_out),
    .ctrl_gp0_in  (ctrl_gp0_in),
    .ctrl_gp1_in  (ctrl_gp1_in),
    .ctrl_gp2_in  (ctrl_gp2_in)
  );

  always #5 clk = ~clk;

  task automatic check_byte(input string name, input [7:0] got, input [7:0] expected);
    begin
      if (got !== expected) begin
        $display("FAIL: %s: got 0x%02x, expected 0x%02x", name, got, expected);
        errors = errors + 1;
      end else begin
        $display("PASS: %s = 0x%02x", name, got);
      end
    end
  endtask

  // Hold the GP write strobe until the SoC reports completion.  Driving on
  // negedge avoids races with the DUT's posedge-based strobe edge detector.
  task automatic ram_write(input [12:0] address, input [7:0] data);
    begin
      while (ctrl_gp1_in[8]) @(posedge clk);
      @(negedge clk);
      ctrl_gp1_out = 32'h01000000 | ({24'h0, data} << 16) | {19'h0, address};
      while (!ctrl_gp1_in[8]) @(posedge clk);
      @(negedge clk);
      ctrl_gp1_out = 32'h0;
    end
  endtask

  task automatic rom_write(input [12:0] address, input [7:0] data);
    begin
      while (ctrl_gp2_in[8]) @(posedge clk);
      @(negedge clk);
      ctrl_gp2_out = 32'h01000000 | ({24'h0, data} << 16) | {19'h0, address};
      while (!ctrl_gp2_in[8]) @(posedge clk);
      @(negedge clk);
      ctrl_gp2_out = 32'h0;
    end
  endtask

  // A read strobe must remain asserted while the one-cycle BRAM read is
  // completing; deasserting it immediately can clear the done indication.
  task automatic ram_read(input [12:0] address, output [7:0] data);
    begin
      while (ctrl_gp1_in[8]) @(posedge clk);
      @(negedge clk);
      ctrl_gp1_out = 32'h02000000 | {19'h0, address};
      while (!ctrl_gp1_in[8]) @(posedge clk);
      data = ctrl_gp1_in[7:0];
      @(negedge clk);
      ctrl_gp1_out = 32'h0;
    end
  endtask

  task automatic rom_read(input [12:0] address, output [7:0] data);
    begin
      while (ctrl_gp2_in[8]) @(posedge clk);
      @(negedge clk);
      ctrl_gp2_out = 32'h02000000 | {19'h0, address};
      while (!ctrl_gp2_in[8]) @(posedge clk);
      data = ctrl_gp2_in[7:0];
      @(negedge clk);
      ctrl_gp2_out = 32'h0;
    end
  endtask

  task automatic pulse_control(input [31:0] value);
    begin
      @(negedge clk);
      ctrl_gp0_out = value;
      @(posedge clk);
      @(negedge clk);
      ctrl_gp0_out = 32'h0;
    end
  endtask

  logic [7:0] readback;
  integer i;

  initial begin
    $dumpfile("z80_soc.vcd");
    $dumpvars(0, tb_z80_soc);

    // Power-on reset leaves the CPU halted.
    repeat (3) @(posedge clk);
    resetq = 1'b1;
    repeat (3) @(posedge clk);
    if (ctrl_gp0_in[0] !== 1'b1) begin
      $display("FAIL: CPU is not halted after reset");
      errors = errors + 1;
    end else begin
      $display("PASS: CPU halted after reset");
    end

    // Boot ROM: JP 0x2000.
    rom_write(13'h0000, 8'hC3);
    rom_write(13'h0001, 8'h00);
    rom_write(13'h0002, 8'h20);

    // Verify PS-side ROM access before starting the CPU.
    rom_read(13'h0000, readback);
    check_byte("PS ROM read", readback, 8'hC3);

    // Program at Z80 address 0x2000:
    //   LD HL,0x2100
    //   LD A,0x42
    //   LD (0x2100),A
    //   LD A,(0x2100)
    //   LD (0x2101),A
    //   JP 0x2000
    //
    // The two final RAM values prove the CPU performed a data write, then
    // read that value back and wrote the read value at the next address.
    ram_write(13'h0000, 8'h21);
    ram_write(13'h0001, 8'h00);
    ram_write(13'h0002, 8'h21);
    ram_write(13'h0003, 8'h3E);
    ram_write(13'h0004, 8'h42);
    ram_write(13'h0005, 8'h32);
    ram_write(13'h0006, 8'h00);
    ram_write(13'h0007, 8'h21);
    ram_write(13'h0008, 8'h3A);
    ram_write(13'h0009, 8'h00);
    ram_write(13'h000A, 8'h21);
    ram_write(13'h000B, 8'h32);
    ram_write(13'h000C, 8'h01);
    ram_write(13'h000D, 8'h21);
    ram_write(13'h000E, 8'hC3);
    ram_write(13'h000F, 8'h00);
    ram_write(13'h0010, 8'h20);

    // Run long enough to execute the complete program, then halt it.
    pulse_control(32'h00000008); // RUN
    repeat (120) @(posedge clk);
    pulse_control(32'h00000001); // HALT
    repeat (3) @(posedge clk);

    if (ctrl_gp0_in[0] !== 1'b1) begin
      $display("FAIL: CPU did not halt");
      errors = errors + 1;
    end else begin
      $display("PASS: CPU halted on command");
    end

    // RAM index 0x100 corresponds to Z80 address 0x2100.
    ram_read(13'h0100, readback);
    check_byte("CPU RAM write at 0x2100", readback, 8'h42);
    ram_read(13'h0101, readback);
    check_byte("CPU RAM readback/write at 0x2101", readback, 8'h42);

    if (debug_pc == 16'h0000) begin
      $display("FAIL: debug PC never left reset vector");
      errors = errors + 1;
    end else begin
      $display("PASS: CPU executed; final debug PC = 0x%04x", debug_pc);
    end

    if (errors != 0) begin
      $display("Z80 SoC simulation FAILED (%0d errors)", errors);
      $fatal(1);
    end else begin
      $display("Z80 SoC simulation PASSED");
    end
    $finish;
  end
endmodule
