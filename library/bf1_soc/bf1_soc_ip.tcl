# ip
source ../../scripts/adi_env.tcl
source $ad_hdl_dir/library/scripts/adi_ip_xilinx.tcl

# NOTE: the IP keeps its historical name "bf1_soc" (the block design and
# the PS driver refer to it), but its top module is now bf2_soc.v wrapping
# the bf2_phase_full core (hazard-free 2-phase machine, Verilator-verified
# against bf1).  The external interface is identical to the old bf1_soc.
#
# The old bf1 reference implementation (stack.v / bf1.v / bf1_soc.v) is
# preserved in this directory and is still used by the standalone sim
# targets (make sim / make sim-uart) and the timing models.
adi_ip_create bf1_soc
adi_ip_files bf1_soc [list \
  "common.h" \
  "bf2_phase.sv" \
  "bf2_stack2.sv" \
  "bf2_soc.v" \
]

adi_ip_properties_lite bf1_soc

set cc [ipx::current_core]

ipx::create_xgui_files $cc
ipx::save_core $cc
