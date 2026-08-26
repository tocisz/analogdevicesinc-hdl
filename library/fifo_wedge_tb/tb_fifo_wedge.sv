`default_nettype none
`timescale 1 ns / 1 ps

// ==========================================================================
// tb_fifo_wedge — reproduction harness for the z80_soc term-output wedge
// ==========================================================================
// Recreates the full data path around the suspect IP with REAL RTL:
//
//   host BFM (mirrors linux/drivers/staging/axis-fifo/axis-fifo.ko)
//        |  AXI4-Lite register accesses (RDFO -> RLR -> RDFD*N reads,
//        |  TDFV check -> TDFD word -> TLR commit writes)
//        v
//   axi_fifo_mm_s (real Vivado IP, same config as system_bd.tcl)
//        | AXI_STR_TXD (PS->PL)      AXI_STR_RXD (PL->PS)
//        v                                 ^
//   axis_byte_bridge (real RTL, 1-deep staging, TLAST per word)
//        | rx_*/tx_* byte handshake
//        v
//   acia68b50 (real RTL) <-- ACIA bus driven by a "guest" model that
//                             mimics the int32k polled-TX loop:
//                             poll SR until TDRE=1, write DR, repeat.
//
// Checks performed continuously:
//   * stream integrity: guest-emitted bytes must reach the host in order.
//     Payload pattern is (i%255)+1 so a phantom NUL can never be a legit
//     byte, and insertions/drops are diagnosed explicitly.
//   * packet framing: every RX packet must be 4-byte aligned (RLR%4==0),
//     upper 24 bits zero (drop-24 contract).
//   * wedge detector: no forward progress (no s_axis handshake, no guest
//     emission, no host packet read) for WEDGE_CYCLES while bytes are
//     still outstanding => declare WEDGE, dump snapshot, exit non-zero.
//
// Plusargs:
//   BYTES=<n>        guest emits this many bytes          (default 2300)
//   GAP_POLL=<n>     guest idle cycles between SR polls   (default 2)
//   GAP_BYTE=<n>     guest idle cycles between bytes      (default 8)
//   PACING=<n>       host idle cycles when FIFO is empty  (default 0=tight)
//   KEYS=<n>         host sends n keystroke packets first (default 0)
//   SEED=<n>         rng seed for jittered gaps           (default 0=off)
//   WEDGE_CYCLES=<n> stall-detection threshold in clocks  (default 200000)
//   RESET_MODE=<m>   soft reset flavor: none | srr | driver | settle
//                    (default: driver = exact axis_fifo.ko probe sequence)
//                    settle = driver + wait for TRC|RRC latched in ISR
//
// Exit status: 0 = clean transfer, 1 = wedge/anomalies/timeout.
// ==========================================================================

module tb_fifo_wedge;

  // ── PG080 register offsets (from axis-fifo.c) ──
  localparam logic [31:0] A_ISR  = 32'h00, A_IER  = 32'h04,
                          A_TDFR = 32'h08, A_TDFV = 32'h0c,
                          A_TDFD = 32'h10, A_TLR  = 32'h14,
                          A_RDFR = 32'h18, A_RDFO = 32'h1c,
                          A_RDFD = 32'h20, A_RLR  = 32'h24,
                          A_SRR  = 32'h28;

  // ── knobs ──
  int  nbytes       = 2300;
  int  gap_poll     = 2;
  int  gap_byte     = 8;
  int  pacing       = 0;
  int  keys         = 0;
  int  seed         = 0;
  int  wedge_cycles = 200000;
  string reset_mode = "driver";

  // ── clock / reset (sys_cpu_clk = 80 MHz) ──
  logic clk = 1'b0;
  logic rst = 1'b1;
  always #6.25 clk = ~clk;

  // ── AXI4-Lite (host BFM side) ──
  logic [31:0] awaddr, wdata, araddr;
  logic awvalid = 1'b0, wvalid = 1'b0, arvalid = 1'b0;
  logic bready  = 1'b0, rready = 1'b0;
  logic awready, wready, bvalid, arready, rvalid;
  logic [31:0] rdata;

  // ── streams ──
  wire        txd_tvalid, txd_tready;   // FIFO -> bridge (keystrokes)
  wire [31:0] txd_tdata;
  wire        txd_tlast;
  wire        rxd_tvalid, rxd_tready;   // bridge -> FIFO (guest output)
  wire [31:0] rxd_tdata;
  wire        rxd_tlast;

  // ── ACIA bus (guest side) ──
  logic       acia_cs = 1'b0, acia_rs = 1'b0, acia_r_nw = 1'b1;
  logic [7:0] acia_din = 8'h00;
  wire [7:0]  acia_dout;
  wire        acia_ack, acia_irq;

  // ── DUTs ──
  wire [7:0] wire_rx_data;
  wire       wire_rx_valid;
  wire       acia_rx_consume;
  wire [7:0] bridge_tx_data;
  wire       bridge_tx_valid;
  wire       bridge_tx_ready;    // mirror of rxd_tready

  axis_byte_bridge u_bridge (
      .clk(clk), .reset(rst),
      .m_axis_tvalid(txd_tvalid), .m_axis_tready(txd_tready),
      .m_axis_tdata (txd_tdata),  .m_axis_tlast (txd_tlast),
      .s_axis_tvalid(rxd_tvalid), .s_axis_tready(rxd_tready),
      .s_axis_tdata (rxd_tdata),  .s_axis_tlast (rxd_tlast),
      .rx_data      (wire_rx_data),
      .rx_valid     (wire_rx_valid),
      .rx_accept    (acia_rx_consume),  // no raw-I/O path in this TB
      .tx_data      (bridge_tx_data),
      .tx_valid     (bridge_tx_valid),
      .tx_ready     (bridge_tx_ready)
  );

  acia68b50 u_acia (
      .clk(clk), .reset(rst),
      .cs(acia_cs), .rs(acia_rs), .r_nw(acia_r_nw),
      .data_in(acia_din), .data_out(acia_dout), .ack(acia_ack),
      .irq(acia_irq),
      .rx_byte(wire_rx_data), .rx_valid(wire_rx_valid),
      .rx_consume(acia_rx_consume),
      .tx_byte(bridge_tx_data), .tx_valid(bridge_tx_valid),
      .tx_ready(bridge_tx_ready)
  );

  axi_fifo_mm_s_sim u_fifo (
      .s_axi_aclk        (clk),
      .s_axi_aresetn     (!rst),
      .interrupt         (),
      .s_axi_awaddr      (awaddr),
      .s_axi_awvalid     (awvalid),
      .s_axi_awready     (awready),
      .s_axi_wdata       (wdata),
      .s_axi_wstrb       (4'hf),
      .s_axi_wvalid      (wvalid),
      .s_axi_wready      (wready),
      .s_axi_bresp       (),
      .s_axi_bvalid      (bvalid),
      .s_axi_bready      (bready),
      .s_axi_araddr      (araddr),
      .s_axi_arvalid     (arvalid),
      .s_axi_arready     (arready),
      .s_axi_rresp       (),
      .s_axi_rdata       (rdata),
      .s_axi_rvalid      (rvalid),
      .s_axi_rready      (rready),
      .mm2s_prmry_reset_out_n (),
      .axi_str_txd_tvalid(txd_tvalid),
      .axi_str_txd_tready(txd_tready),
      .axi_str_txd_tlast (txd_tlast),
      .axi_str_txd_tdata (txd_tdata),
      .s2mm_prmry_reset_out_n (),
      .axi_str_rxd_tvalid(rxd_tvalid),
      .axi_str_rxd_tready(rxd_tready),
      .axi_str_rxd_tlast (rxd_tlast),
      .axi_str_rxd_tdata (rxd_tdata)
  );

  // ── scoreboard state ──
  int      sent_count   = 0;   // guest DR writes completed
  int      axis_accepts = 0;   // s_axis handshake transfers observed
  int      recv_count   = 0;   // payload bytes delivered to host BFM
  int      anomalies    = 0;
  int      max_occ      = 0;
  realtime last_progress = 0;
  bit      guest_done   = 1'b0;
  bit      wedged       = 1'b0;
  bit      desynced     = 1'b0;

  logic [7:0] recv_log [int];  // full received stream for post-mortem

  function automatic logic [7:0] exp_byte(input int i);
    return ((i % 255) + 1);
  endfunction

  task automatic note_progress();
    last_progress = $realtime;
  endtask

  // ── register peeks (safe reads only: never touch RDFD/TDFD here) ──
  task automatic peek_state(input string tag);
    logic [31:0] tdfv, rdfo, isr;
    begin
      axi_read(A_TDFV, tdfv);
      axi_read(A_RDFO, rdfo);
      axi_read(A_ISR, isr);
      $display("[peek %0t] %-14s TDFV=0x%03X RDFO=0x%08X ISR=0x%08X",
               $time, tag, tdfv[11:0], rdfo, isr);
    end
  endtask

  // exact reset_ip_core() from axis-fifo.c
  task automatic reset_ip_core_driver();
    begin
      axi_write(A_SRR,  32'hA5);
      axi_write(A_TDFR, 32'hA5);
      axi_write(A_RDFR, 32'hA5);
    end
  endtask

  // wait until both reset-complete bits latch (PG080 handshake)
  task automatic wait_reset_complete();
    logic [31:0] isr;
    int guard;
    begin
      axi_write(A_ISR, 32'hFFFFFFFF);  // clear latched status first
      guard = 0;
      forever begin
        axi_read(A_ISR, isr);
        if ((isr & 32'h01800000) == 32'h01800000) break; // TRC|RRC
        if (++guard > 1000) begin
          $display("[%0t] TIMEOUT waiting for TRC|RRC (ISR=0x%08X)", $time, isr);
          anomalies++;
          break;
        end
      end
    end
  endtask

  // ── AXI4-Lite BFM ──
  task automatic axi_write(input logic [31:0] addr, input logic [31:0] d);
    begin
      @(negedge clk);
      awaddr <= addr; awvalid <= 1'b1;
      wdata  <= d;    wvalid  <= 1'b1;
      @(posedge clk);
      while (awready !== 1'b1) @(posedge clk);
      awvalid <= 1'b0;
      while (wready !== 1'b1) @(posedge clk);
      wvalid <= 1'b0;
      bready <= 1'b1;
      while (bvalid !== 1'b1) @(posedge clk);
      @(negedge clk);
      bready <= 1'b0;
    end
  endtask

  task automatic axi_read(input logic [31:0] addr, output logic [31:0] d);
    begin
      @(negedge clk);
      araddr <= addr; arvalid <= 1'b1;
      @(posedge clk);
      while (arready !== 1'b1) @(posedge clk);
      arvalid <= 1'b0;
      rready  <= 1'b1;
      while (rvalid !== 1'b1) @(posedge clk);
      d = rdata;
      @(negedge clk);
      rready <= 1'b0;
    end
  endtask

  bit host_packet_busy = 1'b0;
  // ── driver-faithful packet read: RDFO -> RLR -> RDFD*N ──
  task automatic host_read_packet(output bit got);
    logic [31:0] occ, rlr, w;
    int nw;
    begin
      got = 1'b0;
      host_packet_busy = 1'b1;
      axi_read(A_RDFO, occ);
      if (occ == 0) begin host_packet_busy = 1'b0; return; end
      if (occ > max_occ) max_occ = occ;
      axi_read(A_RLR, rlr);
      if (rlr == 0) begin
        $display("[%0t] ANOMALY: RDFO=%0d but RLR=0 (zero-length packet?) recv=%0d", $time, occ, recv_count);
        anomalies++;
        host_packet_busy = 1'b0;
        return;
      end
      if (rlr % 4 != 0) begin
        $display("[%0t] ANOMALY: RLR=%0d not word-aligned! recv=%0d", $time, rlr, recv_count);
        anomalies++;
        host_packet_busy = 1'b0;
        return;
      end
      nw = rlr >> 2;
      for (int i = 0; i < nw; i++) begin
        axi_read(A_RDFD, w);
        if (w[31:8] != 24'd0) begin
          $display("[%0t] ANOMALY: RX word upper bits nonzero: 0x%08h recv=%0d", $time, w, recv_count);
          anomalies++;
        end
        deliver_byte(w[7:0]);
      end
      note_progress();
      got = 1'b1;
      host_packet_busy = 1'b0;
    end
  endtask

  // Stream integrity check with insertion/drop diagnosis.
  // After a desync we stop strict checking (context already logged) so the
  // run still measures whether the FIFO recovers mechanically.
  task automatic deliver_byte(input logic [7:0] b);
    logic [7:0] expd;
    begin
      recv_log[recv_count] = b;
      expd = exp_byte(recv_count);
      if (b !== expd) begin
        if (b === 8'h00) begin
          $display("[%0t] PHANTOM-NUL inserted at offset %0d (expected 0x%02h)",
                   $time, recv_count, expd);
          desynced = 1'b1;   // treat NUL as extra payload: stay at this index
          anomalies++;
          return;            // don't advance; real byte should follow
        end else if ((recv_count + 1 < nbytes) && b === exp_byte(recv_count + 1)) begin
          $display("[%0t] BYTE DROPPED: expected 0x%02h never arrived (offset %0d)",
                   $time, expd, recv_count);
          anomalies++;
          recv_count += 2;   // skip the missing expected byte too
          return;
        end else begin
          $display("[%0t] MISMATCH at offset %0d: got 0x%02h expected 0x%02h",
                   $time, recv_count, b, expd);
          anomalies++;
          desynced = 1'b1;
          recv_count++;
          return;
        end
      end
      recv_count++;
    end
  endtask

  // ── driver-faithful packet write (one keystroke = one 4-byte packet) ──
  task automatic host_send_keystroke(input logic [7:0] b);
    logic [31:0] vac;
    begin
      axi_read(A_TDFV, vac);
      if (vac < 1) begin
        $display("[%0t] ANOMALY: TX FIFO full before keystroke", $time);
        anomalies++;
        return;
      end
      axi_write(A_TDFD, {24'd0, b});
      axi_write(A_TLR, 32'd4);
    end
  endtask

  // ── ACIA bus-cycle models (mirror Z80 bus timing: ack follows cs) ──
  task automatic acia_reg_write(input logic rs, input logic [7:0] v);
    begin
      @(negedge clk);
      acia_cs = 1'b1; acia_rs = rs; acia_r_nw = 1'b0; acia_din = v;
      @(posedge clk);
      while (acia_ack !== 1'b1) @(posedge clk);
      @(negedge clk);
      acia_cs = 1'b0;
    end
  endtask

  task automatic acia_reg_read(output logic [7:0] v);
    begin
      @(negedge clk);
      acia_cs = 1'b1; acia_rs = 1'b0; acia_r_nw = 1'b1;
      @(posedge clk);
      while (acia_ack !== 1'b1) @(posedge clk);
      v = acia_dout;
      @(negedge clk);
      acia_cs = 1'b0;
    end
  endtask

  int seed_val = 1;

  function automatic int rand_next();
    // xorshift32 — deterministic, avoids $random/$urandom portability issues
    seed_val ^= seed_val << 13;
    seed_val ^= seed_val >> 17;
    seed_val ^= seed_val << 5;
    return seed_val;
  endfunction

  function automatic int jitter(input int base);
    if (seed == 0) return base;
    return base / 2 + ((rand_next() >>> 1) % (base / 2 + 1));
  endfunction

  // ── guest model: int32k-style polled-TX emitter ──
  task automatic guest_run();
    logic [7:0] sr;
    begin
      acia_reg_write(1'b0, 8'h03);
      acia_reg_write(1'b0, 8'h12);
      for (int i = 0; i < nbytes; i++) begin
        forever begin
          acia_reg_read(sr);
          if (sr[1]) break;
          repeat (jitter(gap_poll)) @(posedge clk);
        end
        acia_reg_write(1'b1, exp_byte(i));
        sent_count++;
        note_progress();
        repeat (jitter(gap_byte)) @(posedge clk);
      end
      guest_done = 1'b1;
      $display("[%0t] guest finished emitting %0d bytes", $time, sent_count);
    end
  endtask

  // ── monitor: s_axis handshakes are progress ──
  always @(posedge clk) begin
    if (!rst && rxd_tvalid && rxd_tready) begin
      axis_accepts++;
      note_progress();
    end
  end

  // ── host drain loop (runs until wedged or everything received) ──
  task automatic drain_forever();
    bit got;
    forever begin
      host_read_packet(got);
      if (!got) begin
        if (pacing > 0) repeat (pacing) @(posedge clk);
        else #1;  // tight loop: yield delta cycle, retry immediately
      end
      if (wedged || recv_count >= nbytes) return;
    end
  endtask

  // final opportunistic drain for tail bytes committed but not yet read
  task automatic drain_flush(input int max_cycles);
    bit got;
    begin
      for (int c = 0; recv_count < nbytes && c < max_cycles; c++) begin
        host_read_packet(got);
        @(posedge clk);
      end
    end
  endtask

  // ── main sequence ──
  initial begin
    void'($value$plusargs("BYTES=%d", nbytes));
    void'($value$plusargs("GAP_POLL=%d", gap_poll));
    void'($value$plusargs("GAP_BYTE=%d", gap_byte));
    void'($value$plusargs("PACING=%d", pacing));
    void'($value$plusargs("KEYS=%d", keys));
    void'($value$plusargs("SEED=%d", seed));
    void'($value$plusargs("WEDGE_CYCLES=%d", wedge_cycles));
    begin
      string m;
      if ($value$plusargs("RESET_MODE=%s", m)) reset_mode = m;
    end
    if (seed != 0)
      seed_val = seed;

    $display("═══ fifo_wedge_tb: BYTES=%0d GAP_POLL=%0d GAP_BYTE=%0d PACING=%0d KEYS=%0d SEED=%0d ═══",
             nbytes, gap_poll, gap_byte, pacing, keys, seed);

    // hard reset (PL load equivalent)
    repeat (20) @(posedge clk);
    rst = 1'b0;
    repeat (20) @(posedge clk);
    note_progress();

    peek_state("post-hard-rst");

    if (reset_mode != "none") begin
      if (reset_mode == "srr") axi_write(A_SRR, 32'hA5);
      else reset_ip_core_driver();
      repeat (10) @(posedge clk);
      if (reset_mode == "settle") wait_reset_complete();
      peek_state("post-soft-rst");
    end else begin
      repeat (10) @(posedge clk);
    end

    // H5 check: TX vacancy must be full (0x400) after reset settles
    begin
      logic [31:0] tdfv;
      axi_read(A_TDFV, tdfv);
      if (tdfv[11:0] != 12'h400) begin
        $display("  *** H5 anomaly: TDFV=0x%03X after %s reset (expect 0x400)",
                 tdfv[11:0], reset_mode);
        anomalies++;
      end
    end

    // optional pre-burst keystrokes
    for (int k = 0; k < keys; k++) begin
      host_send_keystroke(exp_byte(200 + k));  // junk keys, guest ignores them
      repeat (100) @(posedge clk);
    end

    fork
      begin : guest_thread
        guest_run();
      end
      begin : drain_thread
        drain_forever();
      end
    join_any
    disable fork;

    wait (wedged || recv_count >= nbytes || guest_done);
    drain_flush(100000);

    // verdict
    $display("═══════════════════════════════════════════");
    $display("  sent=%0d axis_accepts=%0d recv=%0d anomalies=%0d max_occ=%0d",
             sent_count, axis_accepts, recv_count, anomalies, max_occ);
    if (wedged)
      $display("  RESULT: WEDGED (reproduction succeeded)");
    else if (anomalies == 0 && recv_count == nbytes && sent_count == nbytes)
      $display("  RESULT: PASS — clean transfer");
    else
      $display("  RESULT: FAIL — incomplete transfer or anomalies");
    $display("═══════════════════════════════════════════");

    if (anomalies > 0 || wedged || recv_count != nbytes) begin
      dump_tail();
      $finish(1);
    end
    $finish;
  end

  // ── wedge watchdog ──
  initial begin
    forever begin
      #(1us);
      if (rst || wedged) continue;
      // done condition: guest finished and host received everything emitted
      if (guest_done && recv_count >= sent_count) continue;
      if (($realtime - last_progress) > (wedge_cycles * 12.5ns)) begin
        logic [31:0] tdfv, rdfo, isr;
        // don't interleave with an in-flight packet read (breaks atomicity)
        wait (host_packet_busy == 1'b0);
        axi_read(A_TDFV, tdfv);
        axi_read(A_RDFO, rdfo);
        axi_read(A_ISR, isr);
        wedged = 1'b1;
        $display("[%0t] ═══ WEDGE DETECTED ═══", $time);
        $display("  sent=%0d axis_accepts=%0d recv=%0d",
                 sent_count, axis_accepts, recv_count);
        $display("  TDFV=0x%03X RDFO=%0d ISR=0x%08X", tdfv[11:0], rdfo, isr);
        $display("  stall duration: %0t", $realtime - last_progress);
        dump_tail();
        $finish(1);
      end
    end
  end

  task automatic dump_tail();
    int lo;
    begin
      lo = recv_count > 64 ? recv_count - 64 : 0;
      $write("  tail[%0d..%0d]:", lo, recv_count - 1);
      for (int i = lo; i < recv_count; i++)
        $write(" %02h", recv_log[i]);
      $write("\n");
    end
  endtask

  // global timeout safety net (5 ms sim time ≈ far beyond any legit run)
  initial begin
    #5ms;
    $display("GLOBAL TIMEOUT: sent=%0d recv=%0d anomalies=%0d",
             sent_count, recv_count, anomalies);
    $finish(1);
  end

endmodule

`default_nettype wire
