`default_nettype none
`timescale 1 ns / 1 ps
// Behavioral stand-in for axi_fifo_mm_s_sim when USE_BEHAV=1.
// Shadows the Xilinx IP by providing the same module name.  Correct by
// construction: queues never corrupt, so wedge should disappear if the IP
// is the culprit.

module axi_fifo_mm_s_sim (
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
  output wire        axi_str_txd_tvalid,
  input  wire        axi_str_txd_tready,
  output wire        axi_str_txd_tlast,
  output wire [31:0] axi_str_txd_tdata,
  output wire        s2mm_prmry_reset_out_n,
  input  wire        axi_str_rxd_tvalid,
  output wire        axi_str_rxd_tready,
  input  wire        axi_str_rxd_tlast,
  input  wire [31:0] axi_str_rxd_tdata
);
  localparam A_ISR=32'h00, A_IER=32'h04, A_TDFR=32'h08, A_TDFV=32'h0c,
             A_TDFD=32'h10, A_TLR=32'h14, A_RDFR=32'h18, A_RDFO=32'h1c,
             A_RDFD=32'h20, A_RLR=32'h24, A_SRR=32'h28;

  assign interrupt = 1'b0;
  assign mm2s_prmry_reset_out_n = s_axi_aresetn;
  assign s2mm_prmry_reset_out_n = s_axi_aresetn;

  localparam DEPTH=1024;
  logic [31:0] rx_mem[DEPTH];
  logic [31:0] rx_len_mem[DEPTH];
  int rx_wptr=0, rx_rptr=0, rx_cnt=0;
  int rx_len_wptr=0, rx_len_rptr=0, rx_len_cnt=0;
  logic [31:0] tx_mem[DEPTH];
  int tx_wptr=0, tx_rptr=0, tx_cnt=0, tx_len_cnt=0;
  logic [31:0] tx_pending[128];
  int tx_pending_cnt=0;

  assign axi_str_rxd_tready = (rx_cnt < DEPTH);

  always_ff @(posedge s_axi_aclk) begin
    if (!s_axi_aresetn) begin
      rx_wptr<=0; rx_rptr<=0; rx_cnt<=0;
      rx_len_wptr<=0; rx_len_rptr<=0; rx_len_cnt<=0;
    end else if (axi_str_rxd_tvalid && axi_str_rxd_tready) begin
      rx_mem[rx_wptr] <= axi_str_rxd_tdata;
      rx_wptr <= (rx_wptr+1)%DEPTH;
      rx_cnt <= rx_cnt+1;
      rx_len_mem[rx_len_wptr] <= 32'd4;
      rx_len_wptr <= (rx_len_wptr+1)%DEPTH;
      rx_len_cnt <= rx_len_cnt+1;
    end
  end

  logic txd_valid_r=1'b0;
  logic [31:0] txd_data_r;
  logic txd_last_r=1'b1;
  assign axi_str_txd_tvalid = txd_valid_r;
  assign axi_str_txd_tdata  = txd_data_r;
  assign axi_str_txd_tlast  = txd_last_r;
  always_ff @(posedge s_axi_aclk) begin
    if (!s_axi_aresetn) begin
      txd_valid_r<=1'b0; tx_rptr<=0; tx_cnt<=0; tx_len_cnt<=0;
    end else begin
      if (txd_valid_r && axi_str_txd_tready) txd_valid_r<=1'b0;
      if (!txd_valid_r && tx_cnt>0) begin
        txd_data_r <= tx_mem[tx_rptr];
        txd_valid_r<=1'b1;
        tx_rptr <= (tx_rptr+1)%DEPTH;
        tx_cnt <= tx_cnt-1;
        if (tx_len_cnt>0) tx_len_cnt<=tx_len_cnt-1;
      end
    end
  end

  logic aw_done=1'b0, w_done=1'b0, ar_done=1'b0;
  logic [31:0] awaddr_r, araddr_r;
  logic [31:0] rdata_r;
  logic bvalid_r=1'b0, rvalid_r=1'b0;

  assign s_axi_awready = !aw_done;
  assign s_axi_wready  = !w_done;
  assign s_axi_bvalid  = bvalid_r;
  assign s_axi_bresp   = 2'b00;
  assign s_axi_arready = !ar_done;
  assign s_axi_rvalid  = rvalid_r;
  assign s_axi_rresp   = 2'b00;
  assign s_axi_rdata   = rdata_r;

  always_ff @(posedge s_axi_aclk) begin
    if (!s_axi_aresetn) begin
      aw_done<=1'b0; w_done<=1'b0; bvalid_r<=1'b0;
      awaddr_r<=0; tx_pending_cnt<=0;
    end else begin
      if (s_axi_awvalid && !aw_done) begin awaddr_r<=s_axi_awaddr; aw_done<=1'b1; end
      if (s_axi_wvalid  && !w_done)  begin w_done<=1'b1; end
      if (aw_done && w_done && !bvalid_r) begin
        case (awaddr_r)
          A_TDFR, A_SRR, A_RDFR: begin
            if (awaddr_r==A_SRR) begin
              rx_wptr<=0; rx_rptr<=0; rx_cnt<=0; rx_len_wptr<=0; rx_len_rptr<=0; rx_len_cnt<=0;
              tx_wptr<=0; tx_rptr<=0; tx_cnt<=0; tx_len_cnt<=0; tx_pending_cnt<=0; txd_valid_r<=1'b0;
            end else if (awaddr_r==A_TDFR) begin
              tx_wptr<=0; tx_rptr<=0; tx_cnt<=0; tx_len_cnt<=0; tx_pending_cnt<=0; txd_valid_r<=1'b0;
            end else begin
              rx_wptr<=0; rx_rptr<=0; rx_cnt<=0; rx_len_wptr<=0; rx_len_rptr<=0; rx_len_cnt<=0;
            end
          end
          A_TDFD: begin
            if (tx_pending_cnt<128) begin tx_pending[tx_pending_cnt]<=s_axi_wdata; tx_pending_cnt<=tx_pending_cnt+1; end
          end
          A_TLR: begin
            for (int i=0;i<tx_pending_cnt;i++) tx_mem[(tx_wptr+i)%DEPTH] <= tx_pending[i];
            tx_wptr <= (tx_wptr+tx_pending_cnt)%DEPTH;
            tx_cnt <= tx_cnt + tx_pending_cnt;
            tx_len_cnt <= tx_len_cnt + tx_pending_cnt;
            tx_pending_cnt<=0;
          end
          default: ;
        endcase
        bvalid_r<=1'b1;
      end
      if (bvalid_r && s_axi_bready) begin bvalid_r<=1'b0; aw_done<=1'b0; w_done<=1'b0; end
    end
  end

  always_ff @(posedge s_axi_aclk) begin
    if (!s_axi_aresetn) begin
      ar_done<=1'b0; rvalid_r<=1'b0; rdata_r<=0;
    end else begin
      if (s_axi_arvalid && !ar_done) begin araddr_r<=s_axi_araddr; ar_done<=1'b1; end
      if (ar_done && !rvalid_r) begin
        case (araddr_r)
          A_ISR:  rdata_r <= 32'h01D00000;
          A_TDFV: rdata_r <= DEPTH - tx_cnt;
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
