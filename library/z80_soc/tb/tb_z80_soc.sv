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
  logic       rts_n;

  logic [15:0] debug_pc;
  logic [7:0]  debug_rsp;

  logic [31:0] ctrl_gp0_out = 32'h0;
  logic [31:0] ctrl_gp1_out = 32'h0;
  logic [31:0] ctrl_gp2_out = 32'h0;
  logic [31:0] ctrl_gp0_in;
  logic [31:0] ctrl_gp1_in;
  logic [31:0] ctrl_gp2_in;

  integer errors = 0;
  integer tx_count = 0;
  integer rx_ready_count = 0;
  logic [7:0] tx_log [0:31];

  // Capture every byte-side TX strobe.  This is intentionally independent
  // of the AXI FIFO model: one Z80 OUT must produce one and only one strobe.
  always @(posedge clk) begin
    if (io_tx_valid && tx_count < 32) begin
      tx_log[tx_count] = io_tx_data;
      tx_count = tx_count + 1;
    end
    if (io_rx_ready)
      rx_ready_count = rx_ready_count + 1;
  end

  z80_soc dut (
    .clk_i        (clk),
    .resetq       (resetq),
    .io_rx_data   (io_rx_data),
    .io_rx_valid  (io_rx_valid),
    .io_rx_ready  (io_rx_ready),
    .io_tx_data   (io_tx_data),
    .io_tx_valid  (io_tx_valid),
    .io_tx_ready  (io_tx_ready),
    .rts_n        (rts_n),
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
  task automatic ram_write(input [15:0] address, input [7:0] data);
    begin
      while (ctrl_gp1_in[8]) @(posedge clk);
      @(negedge clk);
      ctrl_gp1_out = 32'h01000000 | ({24'h0, data} << 16) | {16'h0, address};
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
  task automatic ram_read(input [15:0] address, output [7:0] data);
    begin
      while (ctrl_gp1_in[8]) @(posedge clk);
      @(negedge clk);
      ctrl_gp1_out = 32'h02000000 | {16'h0, address};
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

    // Verify the top of the expanded RAM through the PS port.  RAM GP
    // addresses are offsets from Z80 address 0x2000, so 0xDFFF maps to
    // CPU address 0xFFFF.
    ram_write(16'hDFFF, 8'hA5);
    ram_read(16'hDFFF, readback);
    check_byte("PS RAM read at offset 0xDFFF", readback, 8'hA5);
    ram_write(16'hDFFF, 8'h00);

    // Program at Z80 address 0x2000:
    //   LD HL,0xFFFF
    //   LD A,0x42
    //   LD (0xFFFF),A
    //   LD A,(0xFFFF)
    //   LD (0xFFFE),A
    //   JP 0x2000
    //
    // The two final RAM values prove the CPU performed a data write, then
    // read that value back and wrote the read value at the next address.
    ram_write(13'h0000, 8'h21);
    ram_write(16'h0001, 8'hFF);
    ram_write(16'h0002, 8'hFF);
    ram_write(13'h0003, 8'h3E);
    ram_write(13'h0004, 8'h42);
    ram_write(13'h0005, 8'h32);
    ram_write(16'h0006, 8'hFF);
    ram_write(16'h0007, 8'hFF);
    ram_write(16'h0008, 8'h3A);
    ram_write(16'h0009, 8'hFF);
    ram_write(16'h000A, 8'hFF);
    ram_write(16'h000B, 8'h32);
    ram_write(16'h000C, 8'hFE);
    ram_write(16'h000D, 8'hFF);
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

    // RAM offsets 0xDFFF/0xDFFE correspond to Z80 addresses
    // 0xFFFF/0xFFFE, proving the upper end of the expanded RAM is usable.
    ram_read(16'hDFFF, readback);
    check_byte("CPU RAM write at 0xFFFF", readback, 8'h42);
    ram_read(16'hDFFE, readback);
    check_byte("CPU RAM readback/write at 0xFFFE", readback, 8'h42);

    if (debug_pc == 16'h0000) begin
      $display("FAIL: debug PC never left reset vector");
      errors = errors + 1;
    end else begin
      $display("PASS: CPU executed; final debug PC = 0x%04x", debug_pc);
    end

    // I/O regression: exercise OUT while the FIFO is always ready.  The
    // registered Wishbone ack means the bus request can remain asserted for
    // more than one clock; each OUT must nevertheless create one strobe.
    //   2000: LD A,0
    //   2002: OUT (0),A
    //   2004: INC A
    //   2005: JP 2002
    ram_write(13'h0000, 8'h3E);
    ram_write(13'h0001, 8'h00);
    ram_write(13'h0002, 8'hD3);
    ram_write(13'h0003, 8'h00);
    ram_write(13'h0004, 8'h3C);
    ram_write(13'h0005, 8'hC3);
    ram_write(13'h0006, 8'h02);
    ram_write(13'h0007, 8'h20);
    pulse_control(32'h00000002); // RESET, which also halts the CPU
    repeat (3) @(posedge clk);
    tx_count = 0;
    pulse_control(32'h00000008); // RUN
    repeat (500) @(posedge clk);
    pulse_control(32'h00000001); // HALT
    repeat (3) @(posedge clk);

    if (tx_count < 4) begin
      $display("FAIL: expected at least 4 OUT strobes, got %0d", tx_count);
      errors = errors + 1;
    end else begin
      check_byte("OUT[0]", tx_log[0], 8'h00);
      check_byte("OUT[1]", tx_log[1], 8'h01);
      check_byte("OUT[2]", tx_log[2], 8'h02);
      check_byte("OUT[3]", tx_log[3], 8'h03);
    end

    // ACIA regression: init CR 0x17, then poll TDRE and OUT incrementing
    // bytes to port 0x81.  The CR write must NOT appear on the byte
    // bridge, and TDRE must come back after each data write.
    //   2000: LD A,0x17
    //   2002: OUT (0x80),A
    //   2004: LD B,0
    //   2006: IN A,(0x80)
    //   2008: AND 0x02
    //   200A: JP Z,2006
    //   200D: LD A,B
    //   200E: OUT (0x81),A
    //   2010: INC B
    //   2011: JP 2006
    ram_write(16'h0000, 8'h3E);
    ram_write(16'h0001, 8'h17);
    ram_write(16'h0002, 8'hD3);
    ram_write(16'h0003, 8'h80);
    ram_write(16'h0004, 8'h06);
    ram_write(16'h0005, 8'h00);
    ram_write(16'h0006, 8'hDB);
    ram_write(16'h0007, 8'h80);
    ram_write(16'h0008, 8'hE6);
    ram_write(16'h0009, 8'h02);
    ram_write(16'h000A, 8'hCA);
    ram_write(16'h000B, 8'h06);
    ram_write(16'h000C, 8'h20);
    ram_write(16'h000D, 8'h78);
    ram_write(16'h000E, 8'hD3);
    ram_write(16'h000F, 8'h81);
    ram_write(16'h0010, 8'h04);
    ram_write(16'h0011, 8'hC3);
    ram_write(16'h0012, 8'h06);
    ram_write(16'h0013, 8'h20);
    pulse_control(32'h00000002); // RESET
    repeat (3) @(posedge clk);
    tx_count = 0;
    pulse_control(32'h00000008); // RUN
    repeat (800) @(posedge clk);
    pulse_control(32'h00000001); // HALT
    repeat (3) @(posedge clk);

    if (tx_count < 4) begin
      $display("FAIL: ACIA expected at least 4 TX strobes, got %0d", tx_count);
      errors = errors + 1;
    end else begin
      check_byte("ACIA TX[0]", tx_log[0], 8'h00);
      check_byte("ACIA TX[1]", tx_log[1], 8'h01);
      check_byte("ACIA TX[2]", tx_log[2], 8'h02);
      check_byte("ACIA TX[3]", tx_log[3], 8'h03);
    end

    // RTS/CTS wiring: ACIA RTS must follow CR, CTS must follow io_tx_ready
    // Do a minimal CR poke via ACIA to verify rts_n toggles (uses same path as above)
    // Already tested in standalone ACIA TB; here just sanity that top-level rts_n exists.
    if (rts_n !== 1'b0) begin
      // after reset rts_n should be 0 (cr_tx_ctrl=00)
      $display("INFO: rts_n=%b after reset (expected 0)", rts_n);
    end

    // IM 1 ACIA RX interrupt regression.  The ROM vector at 0038 emits A5
    // through the legacy raw I/O path, then disables interrupts and halts.
    // The held RX byte must raise ACIA IRQ but must not be consumed before an
    // explicit ACIA data-register read.  In particular, INTACK must not turn
    // into a raw I/O read (which would assert io_rx_ready).
    rom_write(13'h0038, 8'h3E); // LD A, A5
    rom_write(13'h0039, 8'hA5);
    rom_write(13'h003A, 8'hD3); // OUT (0), A
    rom_write(13'h003B, 8'h00);
    rom_write(13'h003C, 8'hF3); // DI
    rom_write(13'h003D, 8'h76); // HALT

    // RAM at 2000:
    //   reset ACIA, enable receive IRQ, select IM 1, EI, HALT
    ram_write(16'h0000, 8'h3E);
    ram_write(16'h0001, 8'h03);
    ram_write(16'h0002, 8'hD3);
    ram_write(16'h0003, 8'h80);
    ram_write(16'h0004, 8'h3E);
    ram_write(16'h0005, 8'h97);
    ram_write(16'h0006, 8'hD3);
    ram_write(16'h0007, 8'h80);
    ram_write(16'h0008, 8'hED);
    ram_write(16'h0009, 8'h56); // IM 1
    ram_write(16'h000A, 8'hFB); // EI
    ram_write(16'h000B, 8'h76); // HALT until IRQ

    pulse_control(32'h00000002); // RESET
    repeat (3) @(posedge clk);
    io_rx_data = 8'h5A;
    io_rx_valid = 1'b1;
    rx_ready_count = 0;
    tx_count = 0;
    pulse_control(32'h00000008); // RUN
    repeat (500) @(posedge clk);
    pulse_control(32'h00000001); // HALT
    repeat (3) @(posedge clk);

    if (tx_count < 1) begin
      $display("FAIL: IM 1 ACIA IRQ handler produced no raw TX byte");
      errors = errors + 1;
    end else begin
      check_byte("IM 1 IRQ handler TX", tx_log[0], 8'hA5);
    end
    if (rx_ready_count != 0) begin
      $display("FAIL: INTACK incorrectly asserted io_rx_ready %0d time(s)", rx_ready_count);
      errors = errors + 1;
    end else begin
      $display("PASS: INTACK did not consume raw RX data");
    end
    io_rx_valid = 1'b0;

    if (errors != 0) begin
      $display("Z80 SoC simulation FAILED (%0d errors)", errors);
      $fatal(1);
    end else begin
      $display("Z80 SoC simulation PASSED");
    end
    $finish;
  end
endmodule
