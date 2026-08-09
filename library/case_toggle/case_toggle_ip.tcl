# ip
source ../../scripts/adi_env.tcl
source $ad_hdl_dir/library/scripts/adi_ip_xilinx.tcl

# case_toggle — ASCII case toggle (XOR 0x20), test stand-in for bf2_soc
# with the same io_rx_* / io_tx_* byte interface.
adi_ip_create case_toggle
adi_ip_files case_toggle [list \
  "case_toggle.sv" ]

adi_ip_properties_lite case_toggle

set cc [ipx::current_core]

ipx::create_xgui_files $cc
ipx::save_core $cc
