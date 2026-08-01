# ============================================================================
# Synthesis Script for BF2 Pipeline Stage Timing Analysis
# ============================================================================
# Usage:
#   vivado -mode batch -source synth_stage.tcl -tclargs <stage_name>
#   stage_name: s1_fetch | s2_decode | s3_execute | s4_writeback | longjump | all
#
# Output: ./synth_<stage>/reports/timing_<stage>.rpt
# ============================================================================

set stage_name [lindex $argv 0]
if {$stage_name == ""} { set stage_name "all" }

set src_dir [file normalize [file dirname [info script]]]
set work_dir [file join $src_dir "synth_${stage_name}"]
file mkdir $work_dir
file mkdir [file join $work_dir "reports"]

# Common sources
set common_h [file join $src_dir "common.h"]
set bf2_v    [file join $src_dir "bf2.sv"]

proc synth_stage {stage top_module} {
    global work_dir src_dir
    set stage_dir [file join $work_dir $stage]
    file mkdir $stage_dir
    file mkdir [file join $stage_dir "reports"]

    cd $stage_dir

    # Create project
    create_project -force ${stage}_proj . -part xc7z010clg400-1

    # Add sources
    add_files -norecurse $::common_h
    add_files -norecurse $::bf2_v

    # Set top module
    set_property top $top_module [current_fileset]

    # Synthesis settings for timing analysis
    set_property STEPS.SYNTH_DESIGN.ARGS.RETIMING false [get_runs synth_1]

    launch_runs synth_1 -jobs 4
    wait_on_run synth_1

    open_run synth_1 -name synth_1

    # Timing analysis
    # Create clock for register-to-register path analysis
    set clk_period 10.0  ;# 100 MHz target
    create_clock -period $clk_period -name clk [get_ports clk]

    # Report register-to-register timing (main paths in registered design)
    report_timing -max_paths 20 -sort_by slack \
        -from [get_cells -hierarchical *] \
        -to [get_cells -hierarchical *] \
        -file [file join $::work_dir "reports/timing_${stage}.rpt"]

    # Also report pin-to-pin for input-to-reg and reg-to-output paths
    report_timing -max_paths 10 -sort_by slack \
        -from [all_inputs] \
        -to [all_outputs] \
        -file [file join $::work_dir "reports/timing_pin2pin_${stage}.rpt"]

    report_timing_summary -file [file join $::work_dir "reports/timing_summary_${stage}.rpt"]

    # Resource utilization
    report_utilization -hierarchical -file [file join $::work_dir "reports/util_${stage}.rpt"]

    # Power (optional)
    # report_power -file [file join $::work_dir "reports/power_${stage}.rpt"]

    close_project
}

if {$stage_name == "all" || $stage_name == "s1_fetch"} {
    puts "=== Synthesizing Stage 1: Fetch ==="
    synth_stage "s1_fetch" "bf2_s1_fetch"
}

if {$stage_name == "all" || $stage_name == "s2_decode"} {
    puts "=== Synthesizing Stage 2: Decode ==="
    synth_stage "s2_decode" "bf2_s2_decode"
}

if {$stage_name == "all" || $stage_name == "s3_execute"} {
    puts "=== Synthesizing Stage 3: Execute ==="
    synth_stage "s3_execute" "bf2_s3_execute"
}

if {$stage_name == "all" || $stage_name == "s4_writeback"} {
    puts "=== Synthesizing Stage 4: Writeback ==="
    synth_stage "s4_writeback" "bf2_s4_writeback"
}

if {$stage_name == "all" || $stage_name == "longjump"} {
    puts "=== Synthesizing Long Jump Pipeline ==="
    synth_stage "longjump" "bf2_longjump_pipeline"
}

if {$stage_name == "all" || $stage_name == "stack"} {
    puts "=== Synthesizing Stack ==="
    synth_stage "stack" "bf2_stack"
}

puts "=== Done. Reports in $work_dir/reports/ ==="