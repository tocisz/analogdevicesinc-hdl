# ip
source ../../scripts/adi_env.tcl
source $ad_hdl_dir/library/scripts/adi_ip_xilinx.tcl

# axi_byte_fifo — byte-stream AXI-MM ↔ AXIS FIFO (DEPTH=1024 bytes)
# See doc/AXI_BYTE_FIFO_PLAN.md. Replaces axi_fifo_lite: 8-bit TDATA, no TLAST/TLR/RLR.
adi_ip_create axi_byte_fifo
adi_ip_files axi_byte_fifo [list \
  "axi_byte_fifo.sv" ]

adi_ip_properties_lite axi_byte_fifo

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
  }

adi_add_bus "axi_str_rxd" "slave" \
  "xilinx.com:interface:axis_rtl:1.0" \
  "xilinx.com:interface:axis:1.0" \
  {
    {"axi_str_rxd_tvalid" "TVALID"} \
    {"axi_str_rxd_tready" "TREADY"} \
    {"axi_str_rxd_tdata" "TDATA"} \
  }

adi_add_bus_clock "s_axi_aclk" "s_axi:axi_str_txd:axi_str_rxd" "s_axi_aresetn:mm2s_prmry_reset_out_n:s2mm_prmry_reset_out_n"

ipx::save_core [ipx::current_core]
