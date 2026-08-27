`default_nettype none
`timescale 1 ns / 1 ps

// axi_byte_fifo — byte-stream AXI-MM ↔ AXIS FIFO (DEPTH=1024 bytes)
// Replaces axi_fifo_lite / Xilinx axi_fifo_mm_s for the Z80 term path.
// See doc/AXI_BYTE_FIFO_PLAN.md. Byte = atomic value, no packets.
//
// Register map @ 0x7C450000 (same offsets as axi_fifo_lite for driver
// compat where they overlap). TDATA is now 8-bit, TLAST deleted.
// TLR(0x14)/RLR(0x24) return 0 (no packet), writes ignored.

module axi_byte_fifo (
  input  wire        s_axi_aclk,
  input  wire        s_axi_aresetn,
  output wire        interrupt,
  input  wire [31:0] s_axi_awaddr,
  input  wire        s_axi_awvalid,
  output logic       s_axi_awready,
  input  wire [31:0] s_axi_wdata,
  input  wire [3:0]  s_axi_wstrb,
  input  wire        s_axi_wvalid,
  output logic       s_axi_wready,
  output logic [1:0] s_axi_bresp,
  output logic       s_axi_bvalid,
  input  wire        s_axi_bready,
  input  wire [31:0] s_axi_araddr,
  input  wire        s_axi_arvalid,
  output logic       s_axi_arready,
  output logic [1:0] s_axi_rresp,
  output logic [31:0] s_axi_rdata,
  output logic       s_axi_rvalid,
  input  wire        s_axi_rready,
  output wire        mm2s_prmry_reset_out_n,
  output logic       axi_str_txd_tvalid,
  input  wire        axi_str_txd_tready,
  output logic [7:0] axi_str_txd_tdata,
  output wire        s2mm_prmry_reset_out_n,
  input  wire        axi_str_rxd_tvalid,
  output logic       axi_str_rxd_tready,
  input  wire [7:0]  axi_str_rxd_tdata
);
  localparam A_ISR=7'h00, A_IER=7'h04, A_TDFR=7'h08, A_TDFV=7'h0C,
             A_TDFD=7'h10, A_TLR=7'h14, A_RDFR=7'h18, A_RDFO=7'h1C,
             A_RDFD=7'h20, A_RLR=7'h24, A_SRR=7'h28;
  localparam DEPTH=1024;
  localparam logic [31:0] INT_RC = 32'h04000000;

  // The Linux driver waits in poll() on read_queue.  Keep RC latched until
  // the driver acknowledges it through ISR (W1C), rather than making the
  // interrupt a level derived directly from rx_cnt (which would retrigger
  // continuously while the host is draining the FIFO).
  assign mm2s_prmry_reset_out_n = s_axi_aresetn;
  assign s2mm_prmry_reset_out_n = s_axi_aresetn;

  logic [7:0] rx_mem[DEPTH];
  logic [7:0] tx_mem[DEPTH];

  int rx_wptr, rx_rptr, rx_cnt;
  int tx_wptr, tx_rptr, tx_cnt;
  logic [31:0] ier_r;
  logic [31:0] isr_r;

  assign interrupt = |(isr_r & ier_r);

  logic aw_done, w_done, ar_done;
  logic [6:0] awaddr_r, araddr_r;
  logic [31:0] wdata_r;
  logic bvalid_r, rvalid_r;
  logic [31:0] rdata_r;

  logic txd_valid_q;
  logic [7:0] txd_data_q;

  // A newly received byte must wake a blocked host poll.  Do not generate
  // another RC event when RDFD consumes the only byte in the same cycle:
  // there is then no queued data for the host to read.  These are wires so
  // the event can be applied after the AXI register case below, preserving
  // a simultaneous ISR W1C plus new-byte event.
  wire rx_read_request = ar_done && !rvalid_r && (araddr_r == A_RDFD);
  wire rx_ingest = axi_str_rxd_tvalid && (rx_cnt < DEPTH);
  wire rx_event = rx_ingest && (rx_cnt == 0) && !rx_read_request;
  wire fifo_reset_request = aw_done && w_done && !bvalid_r &&
                             ((awaddr_r == A_SRR) || (awaddr_r == A_RDFR)) &&
                             (wdata_r[7:0] == 8'hA5);
  wire isr_clear_request = aw_done && w_done && !bvalid_r &&
                           (awaddr_r == A_ISR);

  assign s_axi_awready = !aw_done;
  assign s_axi_wready  = !w_done;
  assign s_axi_bvalid  = bvalid_r;
  assign s_axi_bresp   = 2'b00;
  assign s_axi_arready = !ar_done;
  assign s_axi_rvalid  = rvalid_r;
  assign s_axi_rresp   = 2'b00;
  assign s_axi_rdata   = rdata_r;
  assign axi_str_txd_tvalid = txd_valid_q;
  assign axi_str_txd_tdata  = txd_data_q;
  assign axi_str_rxd_tready = (rx_cnt < DEPTH);

  // Single-driver: all state in one clocked process (Vivado DRC MDRV-1).
  // RX ingest (PL→PS) and RDFD pop (PS read) can coincide on the same
  // 80 MHz cycle; handled together so no byte is lost (net-zero count,
  // both pointers advance).
  always_ff @(posedge s_axi_aclk) begin
    if (!s_axi_aresetn) begin
      rx_wptr<=0; rx_rptr<=0; rx_cnt<=0;
      tx_wptr<=0; tx_rptr<=0; tx_cnt<=0;
      ier_r<=32'd0;
      isr_r<=32'h01D00000;
      aw_done<=1'b0; w_done<=1'b0; bvalid_r<=1'b0;
      awaddr_r<=7'd0; wdata_r<=32'd0;
      ar_done<=1'b0; rvalid_r<=1'b0; rdata_r<=32'd0; araddr_r<=7'd0;
      txd_valid_q<=1'b0; txd_data_q<=8'd0;
    end else begin
      if (s_axi_awvalid && !aw_done) begin awaddr_r<=s_axi_awaddr[6:0]; aw_done<=1'b1; end
      if (s_axi_wvalid  && !w_done)  begin wdata_r<=s_axi_wdata; w_done<=1'b1; end
      if (s_axi_arvalid && !ar_done) begin araddr_r<=s_axi_araddr[6:0]; ar_done<=1'b1; end

      // RX ingest + RDFD pop together — lossless
      begin
        logic do_ingest, is_rdfd, do_pop;
        do_ingest = axi_str_rxd_tvalid && (rx_cnt < DEPTH);
        is_rdfd   = ar_done && !rvalid_r && (araddr_r == A_RDFD);
        do_pop    = is_rdfd && ((rx_cnt > 0) || do_ingest);
        if (is_rdfd) begin
          if (do_ingest && do_pop) begin
            rx_mem[rx_wptr] <= axi_str_rxd_tdata;
            rdata_r <= {24'd0, rx_mem[rx_rptr]};
            rx_wptr <= (rx_wptr+1)%DEPTH;
            rx_rptr <= (rx_rptr+1)%DEPTH;
            rvalid_r <= 1'b1;
          end else if (do_pop) begin
            rdata_r <= {24'd0, rx_mem[rx_rptr]};
            rx_rptr <= (rx_rptr+1)%DEPTH;
            rx_cnt <= rx_cnt-1;
            rvalid_r <= 1'b1;
          end else begin
            rdata_r <= 32'd0;
            rvalid_r <= 1'b1;
          end
        end else if (do_ingest) begin
          rx_mem[rx_wptr] <= axi_str_rxd_tdata;
          rx_wptr <= (rx_wptr+1)%DEPTH;
          rx_cnt <= rx_cnt+1;
        end
      end

      if (txd_valid_q && axi_str_txd_tready) txd_valid_q <= 1'b0;
      if (!txd_valid_q && tx_cnt>0) begin
        txd_data_q <= tx_mem[tx_rptr];
        txd_valid_q <= 1'b1;
        tx_rptr <= (tx_rptr+1)%DEPTH;
        tx_cnt <= tx_cnt-1;
      end

      if (aw_done && w_done && !bvalid_r) begin
        case (awaddr_r)
          A_IER:  ier_r <= wdata_r;
          A_ISR:  isr_r <= isr_r & ~wdata_r;
          A_TDFR, A_RDFR, A_SRR: if (wdata_r[7:0]==8'hA5) begin
            if (awaddr_r==A_SRR) begin
              rx_wptr<=0; rx_rptr<=0; rx_cnt<=0;
              tx_wptr<=0; tx_rptr<=0; tx_cnt<=0; txd_valid_q<=1'b0;
              isr_r <= 32'h01D80000;
            end else if (awaddr_r==A_TDFR) begin
              tx_wptr<=0; tx_rptr<=0; tx_cnt<=0; txd_valid_q<=1'b0;
              isr_r <= isr_r | 32'h01000000;
            end else begin
              rx_wptr<=0; rx_rptr<=0; rx_cnt<=0;
              isr_r <= isr_r | 32'h00800000;
            end
          end
          A_TDFD: if (tx_cnt < DEPTH) begin
            tx_mem[tx_wptr] <= wdata_r[7:0];
            tx_wptr <= (tx_wptr+1)%DEPTH;
            tx_cnt <= tx_cnt+1;
          end
          A_TLR, A_RLR: ; // deleted: writes ignored, reads return 0
          default: ;
        endcase
        bvalid_r <= 1'b1;
      end
      if (bvalid_r && s_axi_bready) begin bvalid_r<=1'b0; aw_done<=1'b0; w_done<=1'b0; end

      // Remaining AXI reads (RDFD already handled above together with ingest)
      if (ar_done && !rvalid_r) begin
        if (araddr_r == A_RDFD) begin
          // already handled
        end else begin
          case (araddr_r)
            A_ISR:  rdata_r <= isr_r;
            A_IER:  rdata_r <= ier_r;
            A_TDFV: rdata_r <= DEPTH - tx_cnt;
            A_RDFO: rdata_r <= rx_cnt;
            A_TLR:  rdata_r <= 32'd0;
            A_RLR:  rdata_r <= 32'd0;
            default: rdata_r <= 32'd0;
          endcase
          rvalid_r <= 1'b1;
        end
      end
      if (rvalid_r && s_axi_rready) begin rvalid_r<=1'b0; ar_done<=1'b0; end

      // Apply this after the AXI register case.  If an ISR W1C and the
      // first RX byte coincide, preserve the clear while retaining the new
      // RC event; otherwise the blocked poll could miss that byte forever.
      if (rx_event && !fifo_reset_request) begin
        if (isr_clear_request)
          isr_r <= (isr_r & ~wdata_r) | INT_RC;
        else
          isr_r <= isr_r | INT_RC;
      end
    end
  end
endmodule
`default_nettype wire
