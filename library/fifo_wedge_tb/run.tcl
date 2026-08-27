# fifo_wedge_tb — standalone xsim project for doc/Z80_FIFO_WEDGE_INVESTIGATION.md
# open question 2: observe the bridge<->FIFO AXIS handshake under a wedge.
#
# Env knobs:
#   RX_CUT=0|1     axi_fifo_mm_s C_USE_RX_CUT_THROUGH (default 1, current repo)
#   PLUSARGS="..." passed through to xsim as -testplusarg items

set part    xc7z010clg400-1
set rx_cut  1
if {[info exists env(RX_CUT)]} { set rx_cut $env(RX_CUT) }
set plusargs "-testplusarg WEDGE_PROBE=1"
if {[info exists env(PLUSARGS)]} {
    foreach p $env(PLUSARGS) { append plusargs " -testplusarg $p" }
}

create_project -force fifo_wedge_sim . -part $part

set use_behav 0
if {[info exists env(USE_BEHAV)]} { set use_behav $env(USE_BEHAV) }
set use_lite 0
if {[info exists env(USE_LITE)]} { set use_lite $env(USE_LITE) }
# USE_LITE and USE_BEHAV are mutually exclusive; USE_LITE wins if both set
if {$use_lite} { set use_behav 0 }
if {!$use_behav && !$use_lite} {
  create_ip -name axi_fifo_mm_s -vendor xilinx.com -library ip \
      -module_name axi_fifo_mm_s_sim
  set ip [get_ips axi_fifo_mm_s_sim]
  set_property CONFIG.C_DATA_INTERFACE_TYPE 0 $ip
  set_property CONFIG.C_USE_TX_DATA 1        $ip
  set_property CONFIG.C_USE_RX_DATA 1        $ip
  set_property CONFIG.C_USE_TX_CTRL 0        $ip
  set_property CONFIG.C_TX_FIFO_DEPTH 1024   $ip
  set_property CONFIG.C_RX_FIFO_DEPTH 1024   $ip
  set_property CONFIG.C_USE_TX_CUT_THROUGH 0 $ip
  set_property CONFIG.C_USE_RX_CUT_THROUGH $rx_cut $ip
}

add_files -fileset sources_1 [list \
    ../axis_byte_bridge/axis_byte_bridge.sv]
if {$use_lite} {
  add_files -fileset sim_1 [list \
      ../axis_byte_bridge/axis_byte_bridge.sv \
      ../axi_byte_fifo/axi_byte_fifo.sv \
      ../z80_soc/rtl/acia68b50/acia68b50.sv \
      axi_fifo_lite_sim.sv \
      tb_fifo_wedge.sv]
} elseif {$use_behav} {
  add_files -fileset sim_1 [list \
      ../axis_byte_bridge/axis_byte_bridge.sv \
      ../z80_soc/rtl/acia68b50/acia68b50.sv \
      axi_fifo_behav.sv \
      tb_fifo_wedge.sv]
} else {
  add_files -fileset sim_1 [list \
      ../axis_byte_bridge/axis_byte_bridge.sv \
      ../z80_soc/rtl/acia68b50/acia68b50.sv \
      tb_fifo_wedge.sv]
}

update_compile_order -fileset sim_1
set_property top tb_fifo_wedge [get_filesets sim_1]
set_property -name {xsim.simulate.runtime} -value {-all} -objects [get_filesets sim_1]
set_property -name {xsim.simulate.xsim.more_options} -value $plusargs -objects [get_filesets sim_1]

launch_simulation
close_sim -force
close_project
exit
