###############################################################################
## Copyright (C) 2014-2023 Analog Devices, Inc. All rights reserved.
### SPDX short identifier: ADIBSD
###############################################################################

source ../../scripts/adi_env.tcl
source $ad_hdl_dir/projects/scripts/adi_project_xilinx.tcl
source $ad_hdl_dir/projects/scripts/adi_board.tcl

adi_project_create ebaz4205 0 {} "xc7z010clg400-1"

adi_project_files ebaz4205 [list \
  "system_top.v" \
  "system_constr.xdc" \
  "system_constr_impl.xdc" \
  "bf2_timing.xdc" \
  "$ad_hdl_dir/library/common/ad_iobuf.v"]

set_property is_enabled false [get_files *system_sys_ps7_0.xdc]

adi_project_run ebaz4205
