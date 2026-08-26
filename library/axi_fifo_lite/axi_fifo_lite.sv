`default_nettype none
`timescale 1 ns / 1 ps

// axi_fifo_lite — drop-in replacement for Xilinx axi_fifo_mm_s (PG080)
// for the Z80 term path (doc/Z80_FIFO_WEDGE_INVESTIGATION.md §5b).
//
// Why: axi_fifo_mm_s corrupts data and register file after ~1.6–1.9k
// single-byte packets (TLAST per word, 1024-deep) — phantom NUL insertion,
// RDFO > depth, TDFV stuck at 0x3FC, ISR aliasing.  Reproduced in
// hdl/library/fifo_wedge_tb with the real IP; a trivial behavioral
// FIFO with the same register map passes 10k packets cleanly (USE_BEHAV=1).
//
// Interface: same as axi_fifo_mm_s as used in system_bd.tcl:
//  s_axi_*  : AXI4-Lite slave (32-bit, 7-bit address, byte offsets)
//  axi_str_txd_* : M_AXIS master  PS -> PL (keystrokes, 32b word per byte)
//  axi_str_rxd_* : S_AXIS slave   PL -> PS (guest output, 32b word per byte)
// Parameters: depth 1024 each direction, TLAST per word (one packet per word).
// Register map (offsets from base, same as axis_fifo.ko):
//  0x00 ISR  (RO/W1C) — we report 0x01D00000 idle (TRC|RRC|TFPE|RFPE|RFPE)
//  0x04 IER  (RW)     — stored, not used for interrupt generation
//  0x08 TDFR (WO)     — write 0xA5 : reset TX path
//  0x0C TDFV (RO)     — TX vacancy = DEPTH - tx_cnt
//  0x10 TDFD (WO)     — push word to TX pending
//  0x14 TLR  (WO)     — commit pending TX words as packets
//  0x18 RDFR (WO)     — write 0xA5 : reset RX path
//  0x1C RDFO (RO)     — RX occupancy (words)
//  0x20 RDFD (RO)     — pop word from RX (auto-decrements occupancy & length)
//  0x24 RLR  (RO)     — length of next RX packet (always 4)
//  0x28 SRR  (WO)     — write 0xA5 : reset both paths (like IP's local-link reset)

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

  // -- storage (inferred BRAM/LUTRAM; depth 1024 * 32b ~ 4KB each)
  logic [31:0] rx_mem[DEPTH];
  logic [31:0] rx_len_mem[DEPTH];
  int rx_wptr, rx_rptr, rx_cnt;
  int rx_len_wptr, rx_len_rptr, rx_len_cnt;

  logic [31:0] tx_mem[DEPTH];
  int tx_wptr, tx_rptr, tx_cnt, tx_len_cnt;
  int tx_pending_cnt; // staged words written via TDFD, not yet visible until TLR

  // status registers
  logic [31:0] ier_r = 32'h0;
  logic [31:0] isr_r = 32'h01D00000; // TRC|RRC|TFPE|RFPE|RFPE-like idle

  assign axi_str_rxd_tready = (rx_cnt < DEPTH);

  always_ff @(posedge s_axi_aclk) begin
    if (!s_axi_aresetn) begin
      rx_wptr<=0; rx_rptr<=0; rx_cnt<=0;
      rx_len_wptr<=0; rx_len_rptr<=0; rx_len_cnt<=0;
      isr_r <= 32'h01D00000;
    end else begin
      if (axi_str_rxd_tvalid && axi_str_rxd_tready) begin
        rx_mem[rx_wptr] <= axi_str_rxd_tdata;
        rx_wptr <= (rx_wptr+1)%DEPTH;
        rx_cnt <= rx_cnt+1;
        rx_len_mem[rx_len_wptr] <= 32'd4;
        rx_len_wptr <= (rx_len_wptr+1)%DEPTH;
        rx_len_cnt <= rx_len_cnt+1;
      end
    end
  end

  // TX streaming to PL (keystrokes) — simple store-and-forward
  always_ff @(posedge s_axi_aclk) begin
    if (!s_axi_aresetn) begin
      axi_str_txd_tvalid<=1'b0; tx_rptr<=0; tx_cnt<=0; tx_len_cnt<=0;
      axi_str_txd_tdata<=32'd0; axi_str_txd_tlast<=1'b1;
    end else begin
      if (axi_str_txd_tvalid && axi_str_txd_tready) axi_str_txd_tvalid<=1'b0;
      if (!axi_str_txd_tvalid && tx_cnt>0) begin
        axi_str_txd_tdata <= tx_mem[tx_rptr];
        axi_str_txd_tlast <= 1'b1;
        axi_str_txd_tvalid<=1'b1;
        tx_rptr <= (tx_rptr+1)%DEPTH;
        tx_cnt <= tx_cnt-1;
        if (tx_len_cnt>0) tx_len_cnt<=tx_len_cnt-1;
      end
    end
  end

  // -- AXI-Lite slave (single beat, no burst) --
  logic aw_done, w_done, ar_done;
  logic [6:0] awaddr_r, araddr_r;
  logic [31:0] wdata_r;
  logic bvalid_r, rvalid_r;
  logic [31:0] rdata_r;

  assign s_axi_awready = !aw_done;
  assign s_axi_wready  = !w_done;
  assign s_axi_bvalid  = bvalid_r;
  assign s_axi_bresp   = 2'b00;
  assign s_axi_arready = !ar_done;
  assign s_axi_rvalid  = rvalid_r;
  assign s_axi_rresp   = 2'b00;
  assign s_axi_rdata   = rdata_r;

  // write channel
  always_ff @(posedge s_axi_aclk) begin
    if (!s_axi_aresetn) begin
      aw_done<=1'b0; w_done<=1'b0; bvalid_r<=1'b0;
      awaddr_r<=7'd0; wdata_r<=32'd0; tx_pending_cnt<=0; ier_r<=32'd0;
      tx_wptr<=0; // keep TX reset state consistent
    end else begin
      if (s_axi_awvalid && !aw_done) begin awaddr_r<=s_axi_awaddr[6:0]; aw_done<=1'b1; end
      if (s_axi_wvalid  && !w_done)  begin wdata_r<=s_axi_wdata; w_done<=1'b1; end
      if (aw_done && w_done && !bvalid_r) begin
        case (awaddr_r)
          A_IER:  ier_r <= wdata_r;
          A_ISR:  isr_r <= isr_r & ~wdata_r; // W1C
          A_TDFR, A_RDFR, A_SRR: if (wdata_r[7:0]==8'hA5) begin
            if (awaddr_r==A_SRR) begin
              rx_wptr<=0; rx_rptr<=0; rx_cnt<=0; rx_len_wptr<=0; rx_len_rptr<=0; rx_len_cnt<=0;
              tx_wptr<=0; tx_rptr<=0; tx_cnt<=0; tx_len_cnt<=0; tx_pending_cnt<=0; axi_str_txd_tvalid<=1'b0;
              isr_r <= 32'h01D80000; // TRC|RRC set (like real IP after reset)
            end else if (awaddr_r==A_TDFR) begin
              tx_wptr<=0; tx_rptr<=0; tx_cnt<=0; tx_len_cnt<=0; tx_pending_cnt<=0; axi_str_txd_tvalid<=1'b0;
              isr_r <= isr_r | 32'h01000000; // TRC
            end else begin // RDFR
              rx_wptr<=0; rx_rptr<=0; rx_cnt<=0; rx_len_wptr<=0; rx_len_rptr<=0; rx_len_cnt<=0;
              isr_r <= isr_r | 32'h00800000; // RRC
            end
          end
          A_TDFD: if (tx_pending_cnt<128) begin
            // write directly into FIFO at the staged position — no second copy on TLR
            tx_mem[(tx_wptr + tx_pending_cnt) % DEPTH] <= wdata_r;
            tx_pending_cnt <= tx_pending_cnt + 1;
          end
          A_TLR: begin
            // commit staged words: just make them visible to the TX stream
            tx_wptr    <= (tx_wptr + tx_pending_cnt) % DEPTH;
            tx_cnt     <= tx_cnt + tx_pending_cnt;
            tx_len_cnt <= tx_len_cnt + tx_pending_cnt;
            tx_pending_cnt <= 0;
          end
          default: ;
        endcase
        bvalid_r<=1'b1;
      end
      if (bvalid_r && s_axi_bready) begin bvalid_r<=1'b0; aw_done<=1'b0; w_done<=1'b0; end
    end
  end

  // read channel
  always_ff @(posedge s_axi_aclk) begin
    if (!s_axi_aresetn) begin
      ar_done<=1'b0; rvalid_r<=1'b0; rdata_r<=32'd0;
    end else begin
      if (s_axi_arvalid && !ar_done) begin araddr_r<=s_axi_araddr[6:0]; ar_done<=1'b1; end
      if (ar_done && !rvalid_r) begin
        case (araddr_r)
          A_ISR:  rdata_r <= isr_r;
          A_IER:  rdata_r <= ier_r;
          A_TDFV: rdata_r <= DEPTH - tx_cnt - tx_pending_cnt;
          A_RDFO: rdata_r <= rx_cnt;
          A_RLR:  rdata_r <= (rx_len_cnt>0) ? rx_len_mem[rx_len_rptr] : 32'd0;
          A_RDFD: begin
            rdata_r <= (rx_cnt>0) ? rx_mem[rx_rptr] : 32'd0;
            if (rx_cnt>0) begin rx_rptr <= (rx_rptr+1)%DEPTH; rx_cnt <= rx_cnt-1; end
            if (rx_len_cnt>0) begin rx_len_rptr <= (rx_len_rptr+1)%DEPTH; rx_len_cnt <= rx_len_cnt-1; end
          end
          default: rdata_r <= 32'd0;
        endcase
        rvalid_r<=1'b1;
      end
      if (rvalid_r && s_axi_rready) begin rvalid_r<=1'b0; ar_done<=1'b0; end
    end
  end
endmodule
`default_nettype wire
