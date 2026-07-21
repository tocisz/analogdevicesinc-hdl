# ip
source ../../scripts/adi_env.tcl
source $ad_hdl_dir/library/scripts/adi_ip_xilinx.tcl

adi_ip_create char_add_one
adi_ip_files char_add_one [list \
  "char_add_one.v" ]

adi_ip_properties_lite char_add_one

set cc [ipx::current_core]

ipx::create_xgui_files $cc
ipx::save_core $cc
