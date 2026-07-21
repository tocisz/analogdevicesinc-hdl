# ip
source ../../scripts/adi_env.tcl
source $ad_hdl_dir/library/scripts/adi_ip_xilinx.tcl

adi_ip_create uart_phy
adi_ip_files uart_phy [list \
  "uart_phy.v" ]

adi_ip_properties_lite uart_phy

set cc [ipx::current_core]

ipx::create_xgui_files $cc
ipx::save_core $cc
