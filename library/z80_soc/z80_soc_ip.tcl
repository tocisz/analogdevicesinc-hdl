# ip
source ../../scripts/adi_env.tcl
source $ad_hdl_dir/library/scripts/adi_ip_xilinx.tcl

# Z80 SoC IP — tv80 core + Wishbone bridge + dual-port BRAMs + I/O bridge.
# External interface is compatible with bf2_soc (same io_*, ctrl_gp* ports).
adi_ip_create z80_soc
adi_ip_files z80_soc [list \
  "rtl/core/tv80s.v" \
  "rtl/core/tv80_core.v" \
  "rtl/core/tv80_alu.v" \
  "rtl/core/tv80_mcode.v" \
  "rtl/core/tv80_reg.v" \
  "rtl/wb_tv80/wb_tv80.v" \
  "z80_soc.sv" \
]

adi_ip_properties_lite z80_soc

set cc [ipx::current_core]

ipx::create_xgui_files $cc
ipx::save_core $cc
