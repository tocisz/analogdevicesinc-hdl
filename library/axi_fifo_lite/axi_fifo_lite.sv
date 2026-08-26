`default_nettype none
`timescale 1 ns / 1 ps

// axi_fifo_lite — drop-in replacement for Xilinx axi_fifo_mm_s (PG080)
// for the Z80 term path (doc/Z80_FIFO_WEDGE_INVESTIGATION.md §5b).

module axi_fifo_lite (
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
  output logic       axi_str_txd_tlast,
  output logic [31:0] axi_str_txd_tdata,
  output wire        s2mm_prmry_reset_out_n,
  input  wire        axi_str_rxd_tvalid,
  output logic       axi_str_rxd_tready,
  input  wire        axi_str_rxd_tlast,
  input  wire [31:0] axi_str_rxd_tdata
);
  localparam A_ISR=7'h00, A_IER=7'h04, A_TDFR=7'h08, A_TDFV=7'h0C,
             A_TDFD=7'h10, A_TLR=7'h14, A_RDFR=7'h18, A_RDFO=7'h1C,
             A_RDFD=7'h20, A_RLR=7'h24, A_SRR=7'h28;
  localparam DEPTH=1024;

  assign interrupt = 1'b0;
  assign mm2s_prmry_reset_out_n = s_axi_aresetn;
  assign s2mm_prmry_reset_out_n = s_axi_aresetn;

  logic [31:0] rx_mem[DEPTH];
  logic [31:0] rx_len_mem[DEPTH];
  logic [31:0] tx_mem[DEPTH];

  int rx_wptr, rx_rptr, rx_cnt;
  int rx_len_wptr, rx_len_rptr, rx_len_cnt;
  int tx_wptr, tx_rptr, tx_cnt, tx_len_cnt;
  int tx_pending_cnt;
  logic [31:0] ier_r;
  logic [31:0] isr_r;

  logic aw_done, w_done, ar_done;
  logic [6:0] awaddr_r, araddr_r;
  logic [31:0] wdata_r;
  logic bvalid_r, rvalid_r;
  logic [31:0] rdata_r;

  logic txd_valid_q;
  logic [31:0] txd_data_q;

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
  assign axi_str_txd_tlast  = 1'b1;
  assign axi_str_rxd_tready = (rx_cnt < DEPTH);

  // Single-driver: all state in one clocked process (fixes Vivado DRC MDRV-1).
  // Previously rx_cnt/tx_cnt etc were driven from 4 separate always_ff
  // blocks — legal in xsim (last assignment wins) but DRC flags as
  // multiple-driver nets and aborts opt_design.  Merged here.
  // RX ingest (PL→PS burst) and RDFD pop (PS read) can coincide on the
  // same 80 MHz cycle; they are handled together so no packet is lost
  // (net-zero count, both pointers advance) — small 1-cycle latency is OK.
  always_ff @(posedge s_axi_aclk) begin
    if (!s_axi_aresetn) begin
      rx_wptr<=0; rx_rptr<=0; rx_cnt<=0;
      rx_len_wptr<=0; rx_len_rptr<=0; rx_len_cnt<=0;
      tx_wptr<=0; tx_rptr<=0; tx_cnt<=0; tx_len_cnt<=0;
      tx_pending_cnt<=0;
      ier_r<=32'd0;
      isr_r<=32'h01D00000;
      aw_done<=1'b0; w_done<=1'b0; bvalid_r<=1'b0;
      awaddr_r<=7'd0; wdata_r<=32'd0;
      ar_done<=1'b0; rvalid_r<=1'b0; rdata_r<=32'd0; araddr_r<=7'd0;
      txd_valid_q<=1'b0; txd_data_q<=32'd0;
    end else begin
      if (s_axi_awvalid && !aw_done) begin awaddr_r<=s_axi_awaddr[6:0]; aw_done<=1'b1; end
      if (s_axi_wvalid  && !w_done)  begin wdata_r<=s_axi_wdata; w_done<=1'b1; end
      if (s_axi_arvalid && !ar_done) begin araddr_r<=s_axi_araddr[6:0]; ar_done<=1'b1; end

      // RX ingest + RDFD pop together — lossless (no last-wins clobber).
      // ar_done is registered one cycle after AR, so a PS read and a PL
      // push can land on the same s_axi_aclk edge during bursts.
      begin
        logic do_ingest, is_rdfd, do_pop;
        do_ingest = axi_str_rxd_tvalid && (rx_cnt < DEPTH);
        is_rdfd   = ar_done && !rvalid_r && (araddr_r == A_RDFD);
        do_pop    = is_rdfd && ((rx_cnt > 0) || do_ingest);
        if (is_rdfd) begin
          if (do_ingest && do_pop) begin
            rx_mem[rx_wptr] <= axi_str_rxd_tdata;
            rx_len_mem[rx_len_wptr] <= 32'd4;
            rdata_r <= rx_mem[rx_rptr];
            rx_wptr <= (rx_wptr+1)%DEPTH;
            rx_len_wptr <= (rx_len_wptr+1)%DEPTH;
            rx_rptr <= (rx_rptr+1)%DEPTH;
            rx_len_rptr <= (rx_len_rptr+1)%DEPTH;
            // net 0
            rvalid_r <= 1'b1;
          end else if (do_pop) begin
            rdata_r <= rx_mem[rx_rptr];
            rx_rptr <= (rx_rptr+1)%DEPTH;
            rx_cnt <= rx_cnt-1;
            rx_len_rptr <= (rx_len_rptr+1)%DEPTH;
            rx_len_cnt <= rx_len_cnt-1;
            rvalid_r <= 1'b1;
          end else begin
            rdata_r <= 32'd0;
            rvalid_r <= 1'b1;
          end
        end else if (do_ingest) begin
          rx_mem[rx_wptr] <= axi_str_rxd_tdata;
          rx_len_mem[rx_len_wptr] <= 32'd4;
          rx_wptr <= (rx_wptr+1)%DEPTH;
          rx_len_wptr <= (rx_len_wptr+1)%DEPTH;
          rx_cnt <= rx_cnt+1;
          rx_len_cnt <= rx_len_cnt+1;
        end
      end

      if (txd_valid_q && axi_str_txd_tready) txd_valid_q <= 1'b0;
      if (!txd_valid_q && tx_cnt>0) begin
        txd_data_q <= tx_mem[tx_rptr];
        txd_valid_q <= 1'b1;
        tx_rptr <= (tx_rptr+1)%DEPTH;
        tx_cnt <= tx_cnt-1;
        if (tx_len_cnt>0) tx_len_cnt <= tx_len_cnt-1;
      end

      if (aw_done && w_done && !bvalid_r) begin
        case (awaddr_r)
          A_IER:  ier_r <= wdata_r;
          A_ISR:  isr_r <= isr_r & ~wdata_r;
          A_TDFR, A_RDFR, A_SRR: if (wdata_r[7:0]==8'hA5) begin
            if (awaddr_r==A_SRR) begin
              rx_wptr<=0; rx_rptr<=0; rx_cnt<=0; rx_len_wptr<=0; rx_len_rptr<=0; rx_len_cnt<=0;
              tx_wptr<=0; tx_rptr<=0; tx_cnt<=0; tx_len_cnt<=0; tx_pending_cnt<=0; txd_valid_q<=1'b0;
              isr_r <= 32'h01D80000;
            end else if (awaddr_r==A_TDFR) begin
              tx_wptr<=0; tx_rptr<=0; tx_cnt<=0; tx_len_cnt<=0; tx_pending_cnt<=0; txd_valid_q<=1'b0;
              isr_r <= isr_r | 32'h01000000;
            end else begin
              rx_wptr<=0; rx_rptr<=0; rx_cnt<=0; rx_len_wptr<=0; rx_len_rptr<=0; rx_len_cnt<=0;
              isr_r <= isr_r | 32'h00800000;
            end
          end
          A_TDFD: if (tx_pending_cnt<128) begin
            tx_mem[(tx_wptr + tx_pending_cnt) % DEPTH] <= wdata_r;
            tx_pending_cnt <= tx_pending_cnt + 1;
          end
          A_TLR: begin
            tx_wptr    <= (tx_wptr + tx_pending_cnt) % DEPTH;
            tx_cnt     <= tx_cnt + tx_pending_cnt;
            tx_len_cnt <= tx_len_cnt + tx_pending_cnt;
            tx_pending_cnt <= 0;
          end
          default: ;
        endcase
        bvalid_r <= 1'b1;
      end
      if (bvalid_r && s_axi_bready) begin bvalid_r<=1'b0; aw_done<=1'b0; w_done<=1'b0; end

      // Remaining AXI reads (RDFD already handled above together with ingest)
      if (ar_done && !rvalid_r) begin
        // skip if RDFD was already completed in the combined RX block
        if (araddr_r == A_RDFD) begin
          // already handled — do nothing (rvalid already set if needed)
        end else begin
          case (araddr_r)
            A_ISR:  rdata_r <= isr_r;
            A_IER:  rdata_r <= ier_r;
            A_TDFV: rdata_r <= DEPTH - tx_cnt - tx_pending_cnt;
            A_RDFO: rdata_r <= rx_cnt;
            A_RLR:  rdata_r <= (rx_len_cnt>0) ? rx_len_mem[rx_len_rptr] : 32'd0;
            default: rdata_r <= 32'd0;
          endcase
          rvalid_r <= 1'b1;
        end
      end
      if (rvalid_r && s_axi_rready) begin rvalid_r<=1'b0; ar_done<=1'b0; end
    end
  end
endmodule
`default_nettype wire
