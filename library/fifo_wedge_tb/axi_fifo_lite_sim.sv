`default_nettype none
`timescale 1 ns / 1 ps
// Wrapper so fifo_wedge_tb can instantiate axi_fifo_lite without
// renaming the module or temporarily overwriting axi_fifo_behav.sv.
// Usage: USE_LITE=1 make -C hdl/library/fifo_wedge_tb sim
module axi_fifo_mm_s_sim (
  input  wire        s_axi_aclk,
  input  wire        s_axi_aresetn,
  output wire        interrupt,
  input  wire [31:0] s_axi_awaddr,
  input  wire        s_axi_awvalid,
  output wire        s_axi_awready,
  input  wire [31:0] s_axi_wdata,
  input  wire [3:0]  s_axi_wstrb,
  input  wire        s_axi_wvalid,
  output wire        s_axi_wready,
  output wire [1:0]  s_axi_bresp,
  output wire        s_axi_bvalid,
  input  wire        s_axi_bready,
  input  wire [31:0] s_axi_araddr,
  input  wire        s_axi_arvalid,
  output wire        s_axi_arready,
  output wire [1:0]  s_axi_rresp,
  output wire [31:0] s_axi_rdata,
  output wire        s_axi_rvalid,
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
  axi_fifo_lite inst (
    .s_axi_aclk(s_axi_aclk), .s_axi_aresetn(s_axi_aresetn),
    .interrupt(interrupt),
    .s_axi_awaddr(s_axi_awaddr), .s_axi_awvalid(s_axi_awvalid), .s_axi_awready(s_axi_awready),
    .s_axi_wdata(s_axi_wdata), .s_axi_wstrb(s_axi_wstrb), .s_axi_wvalid(s_axi_wvalid), .s_axi_wready(s_axi_wready),
    .s_axi_bresp(s_axi_bresp), .s_axi_bvalid(s_axi_bvalid), .s_axi_bready(s_axi_bready),
    .s_axi_araddr(s_axi_araddr), .s_axi_arvalid(s_axi_arvalid), .s_axi_arready(s_axi_arready),
    .s_axi_rresp(s_axi_rresp), .s_axi_rdata(s_axi_rdata), .s_axi_rvalid(s_axi_rvalid), .s_axi_rready(s_axi_rready),
    .mm2s_prmry_reset_out_n(mm2s_prmry_reset_out_n),
    .axi_str_txd_tvalid(axi_str_txd_tvalid), .axi_str_txd_tready(axi_str_txd_tready),
    .axi_str_txd_tlast(axi_str_txd_tlast), .axi_str_txd_tdata(axi_str_txd_tdata),
    .s2mm_prmry_reset_out_n(s2mm_prmry_reset_out_n),
    .axi_str_rxd_tvalid(axi_str_rxd_tvalid), .axi_str_rxd_tready(axi_str_rxd_tready),
    .axi_str_rxd_tlast(axi_str_rxd_tlast), .axi_str_rxd_tdata(axi_str_rxd_tdata)
  );
endmodule
`default_nettype wire
