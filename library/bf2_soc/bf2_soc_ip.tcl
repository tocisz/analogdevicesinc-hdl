# ip
source ../../scripts/adi_env.tcl
source $ad_hdl_dir/library/scripts/adi_ip_xilinx.tcl

# BF2 SoC IP — hazard-free 2-phase machine (Verilator-verified against BF1).
# External interface is compatible with the original bf1_soc.
adi_ip_create bf2_soc
adi_ip_files bf2_soc [list \
  "common.h" \
  "bf2_s12_comb.sv" \
  "bf2_s34_comb.sv" \
  "bf2_phase.sv" \
  "bf2_stack2.sv" \
  "bf2_soc.sv" \
]

adi_ip_properties_lite bf2_soc

set cc [ipx::current_core]

ipx::create_xgui_files $cc
ipx::save_core $cc