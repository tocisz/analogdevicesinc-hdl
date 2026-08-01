# ============================================================================
# Synthesis Script for BF2 Register-to-Register Stage Timing
# ============================================================================
# Wraps each combinational stage core in input/output flip-flops (simulating
# the pipeline registers before and after the stage) and measures the true
# register-to-register path delay at 100 MHz (10 ns).
#
# The measured path is ONLY:
#     FF_in -> stage combinational logic -> FF_out
# Ports feed/tap only FFs, so no IBUF/OBUF delays appear on any path.
#
# Usage:
#   vivado -mode batch -source synth_r2r.tcl -tclargs <stage_name>
#   stage_name: s1_fetch | s2_decode | s3_execute | s4_writeback |
#               longjump | alu | stack2 | all
#
# Output: ./synth_<stage>_r2r/reports/timing_r2r_<stage>.rpt
# ============================================================================

set stage_name [lindex $argv 0]
if {$stage_name == ""} { set stage_name "all" }

set src_dir [file normalize [file dirname [info script]]]
set work_dir [file join $src_dir "synth_${stage_name}_r2r"]
file mkdir $work_dir
file mkdir [file join $work_dir "reports"]

set comb_v [file join $src_dir "bf2_comb.sv"]
set r2r_v  [file join $src_dir "bf2_r2r.sv"]

proc synth_r2r_stage {stage top_module} {
    global work_dir src_dir comb_v r2r_v
    set stage_dir [file join $work_dir $stage]
    file mkdir $stage_dir
    file mkdir [file join $stage_dir "reports"]

    cd $stage_dir

    # Create project
    create_project -force ${stage}_r2r_proj . -part xc7z010clg400-1

    # Add sources
    add_files -norecurse $comb_v
    add_files -norecurse $r2r_v

    # Set top module
    set_property top $top_module [current_fileset]

    # Synthesis settings
    set_property STEPS.SYNTH_DESIGN.ARGS.RETIMING false [get_runs synth_1]

    launch_runs synth_1 -jobs 4
    wait_on_run synth_1

    open_run synth_1 -name synth_1

    # 100 MHz clock (10 ns period) on the wrapper's clk port
    create_clock -period 10.0 -name clk [get_ports clk]

    # Register-to-register timing: FF_in -> comb -> FF_out (the measured path)
    report_timing -max_paths 20 -sort_by slack \
        -file [file join $work_dir "reports/timing_r2r_${stage}.rpt"]

    # Input setup / clock-to-out paths (should be trivially met)
    report_timing -max_paths 10 -sort_by slack \
        -from [all_inputs] \
        -to   [get_cells -hierarchical -filter {IS_SEQUENTIAL}] \
        -file [file join $work_dir "reports/timing_input_${stage}.rpt"]
    report_timing -max_paths 10 -sort_by slack \
        -from [get_cells -hierarchical -filter {IS_SEQUENTIAL}] \
        -to   [all_outputs] \
        -file [file join $work_dir "reports/timing_output_${stage}.rpt"]

    report_timing_summary -file [file join $work_dir "reports/timing_summary_r2r_${stage}.rpt"]

    # Resource utilization
    report_utilization -hierarchical -file [file join $work_dir "reports/util_r2r_${stage}.rpt"]

    # Print key result
    set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1]]
    set delay_ns [expr {10.0 - $wns}]
    puts "=== $stage: WNS = $wns ns (worst R2R path = [format %.3f $delay_ns] ns) ==="

    close_project
}

if {$stage_name == "all" || $stage_name == "s1_fetch"} {
    puts "=== R2R Stage 1: Fetch ==="
    synth_r2r_stage "s1_fetch" "bf2_s1_fetch_r2r"
}

if {$stage_name == "all" || $stage_name == "s2_decode"} {
    puts "=== R2R Stage 2: Decode ==="
    synth_r2r_stage "s2_decode" "bf2_s2_decode_r2r"
}

if {$stage_name == "all" || $stage_name == "s3_execute"} {
    puts "=== R2R Stage 3: Execute ==="
    synth_r2r_stage "s3_execute" "bf2_s3_execute_r2r"
}

if {$stage_name == "all" || $stage_name == "s4_writeback"} {
    puts "=== R2R Stage 4: Writeback ==="
    synth_r2r_stage "s4_writeback" "bf2_s4_writeback_r2r"
}

if {$stage_name == "all" || $stage_name == "longjump"} {
    puts "=== R2R Long Jump Pipeline ==="
    synth_r2r_stage "longjump" "bf2_longjump_r2r"
}

if {$stage_name == "all" || $stage_name == "alu"} {
    puts "=== R2R ALU ==="
    synth_r2r_stage "alu" "bf2_alu_r2r"
}

if {$stage_name == "all" || $stage_name == "stack2"} {
    puts "=== R2R Stack2 ==="
    synth_r2r_stage "stack2" "bf2_stack2_r2r"
}

puts "=== Done. Reports in $work_dir/reports/ ==="
