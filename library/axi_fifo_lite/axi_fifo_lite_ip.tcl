# ip
source ../../scripts/adi_env.tcl
source $ad_hdl_dir/library/scripts/adi_ip_xilinx.tcl

# axi_fifo_lite — behavioral replacement for Xilinx axi_fifo_mm_s
# for the Z80 term path. Same register map and AXIS ports, correct
# occupancy handling (fixes wedge/phantom described in
# doc/Z80_FIFO_WEDGE_INVESTIGATION.md §5b).
adi_ip_create axi_fifo_lite
adi_ip_files axi_fifo_lite [list \
  "axi_fifo_lite.sv" ]

adi_ip_properties_lite axi_fifo_lite

adi_add_bus "s_axi" "slave" \
  "xilinx.com:interface:aximm_rtl:1.0" \
  "xilinx.com:interface:aximm:1.0" \
  {
    {"s_axi_awaddr" "AWADDR"} \
    {"s_axi_awvalid" "AWVALID"} \
    {"s_axi_awready" "AWREADY"} \
    {"s_axi_wdata" "WDATA"} \
    {"s_axi_wstrb" "WSTRB"} \
    {"s_axi_wvalid" "WVALID"} \
    {"s_axi_wready" "WREADY"} \
    {"s_axi_bresp" "BRESP"} \
    {"s_axi_bvalid" "BVALID"} \
    {"s_axi_bready" "BREADY"} \
    {"s_axi_araddr" "ARADDR"} \
    {"s_axi_arvalid" "ARVALID"} \
    {"s_axi_arready" "ARREADY"} \
    {"s_axi_rdata" "RDATA"} \
    {"s_axi_rresp" "RRESP"} \
    {"s_axi_rvalid" "RVALID"} \
    {"s_axi_rready" "RREADY"} \
  }

adi_add_bus "axi_str_txd" "master" \
  "xilinx.com:interface:axis_rtl:1.0" \
  "xilinx.com:interface:axis:1.0" \
  {
    {"axi_str_txd_tvalid" "TVALID"} \
    {"axi_str_txd_tready" "TREADY"} \
    {"axi_str_txd_tdata" "TDATA"} \
    {"axi_str_txd_tlast" "TLAST"} \
  }

adi_add_bus "axi_str_rxd" "slave" \
  "xilinx.com:interface:axis_rtl:1.0" \
  "xilinx.com:interface:axis:1.0" \
  {
    {"axi_str_rxd_tvalid" "TVALID"} \
    {"axi_str_rxd_tready" "TREADY"} \
    {"axi_str_rxd_tdata" "TDATA"} \
    {"axi_str_rxd_tlast" "TLAST"} \
  }

adi_add_bus_clock "s_axi_aclk" "s_axi:axi_str_txd:axi_str_rxd" "s_axi_aresetn:mm2s_prmry_reset_out_n:s2mm_prmry_reset_out_n"

ipx::save_core [ipx::current_core]
