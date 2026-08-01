# ============================================================================
# Synthesis Script for BF2 Full 4-Stage Pipeline (bf2_pipeline_full)
# ============================================================================
# Full pipeline: Fetch(IMEM) -> Decode -> Execute -> Mem/WB(DMEM)
# with BRAM models and stack2 (LIFO return stack).
# Usage:
#   vivado -mode batch -source synth_pipeline_full.tcl
# ============================================================================

set src_dir [file normalize [file dirname [info script]]]

create_project -force bf2_pipeline_full_proj . -part xc7z010clg400-1
add_files -norecurse [file join $src_dir "common.h"]
add_files -norecurse [file join $src_dir "bf2_comb.sv"]
add_files -norecurse [file join $src_dir "bf2_stack2.sv"]
add_files -norecurse [file join $src_dir "bf2_pipeline.sv"]
set_property top bf2_pipeline_full [current_fileset]
set_property STEPS.SYNTH_DESIGN.ARGS.RETIMING false [get_runs synth_1]
launch_runs synth_1 -jobs 4
wait_on_run synth_1
open_run synth_1 -name synth_1
create_clock -period 10.0 -name clk [get_ports clk]
report_timing -max_paths 20 -sort_by slack -file bf2_pipeline_full_timing.rpt
report_timing_summary -file bf2_pipeline_full_timing_summary.rpt
report_utilization -hierarchical -file bf2_pipeline_full_util.rpt
close_project
