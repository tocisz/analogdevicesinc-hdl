# ip
source ../../scripts/adi_env.tcl
source $ad_hdl_dir/library/scripts/adi_ip_xilinx.tcl

adi_ip_create bf1_soc
adi_ip_files bf1_soc [list \
  "common.h" \
  "stack.v" \
  "bf1.v" \
  "bf1_soc.v" \
  "bf1_soc_constr.xdc" ]

adi_ip_properties_lite bf1_soc

set cc [ipx::current_core]

ipx::create_xgui_files $cc
ipx::save_core $cc
