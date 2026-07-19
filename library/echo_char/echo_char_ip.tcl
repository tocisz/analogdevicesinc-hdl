# ip
source ../../scripts/adi_env.tcl
source $ad_hdl_dir/library/scripts/adi_ip_xilinx.tcl

adi_ip_create echo_char
adi_ip_files echo_char [list \
  "echo_char.v" ]

adi_ip_properties_lite echo_char

set cc [ipx::current_core]

ipx::create_xgui_files $cc
ipx::save_core $cc
