# ============================================================================
# Synthesis Script for BF2 Combinational Stage Timing Analysis
# ============================================================================
# Measures the critical path through combinational logic of each stage.
# The combinational stage cores live here (timing/), one module per file.
# Usage:
#   vivado -mode batch -source timing/synth_comb.tcl -tclargs <stage_name>
#   stage_name: s1_fetch | s2_decode | s3_execute | s4_writeback | longjump | alu | stack | all
# ============================================================================

set stage_name [lindex $argv 0]
if {$stage_name == ""} { set stage_name "all" }

set src_dir [file normalize [file dirname [info script]]]   ;# .../bf2_soc/timing
set top_dir [file dirname $src_dir]                          ;# .../bf2_soc
set work_dir [file join $top_dir "synth_${stage_name}_comb"]
file mkdir $work_dir
file mkdir [file join $work_dir "reports"]

# Combinational stage cores (one module per file) + the shared header.
set comb_src [list \
  [file join $src_dir "bf2_s1_fetch_comb.sv"] \
  [file join $src_dir "bf2_s2_decode_comb.sv"] \
  [file join $src_dir "bf2_s3_execute_comb.sv"] \
  [file join $src_dir "bf2_s4_writeback_comb.sv"] \
  [file join $src_dir "bf2_longjump_pipeline_comb.sv"] \
  [file join $src_dir "bf2_alu_comb.sv"] \
  [file join $src_dir "bf2_stack.sv"] \
  [file join $src_dir "bf2_stack2_comb.sv"] \
  [file join $top_dir "common.h"] \
]

proc synth_comb_stage {stage top_module} {
    global work_dir comb_src
    set stage_dir [file join $work_dir $stage]
    file mkdir $stage_dir
    file mkdir [file join $stage_dir "reports"]

    cd $stage_dir

    # Create project
    create_project -force ${stage}_proj . -part xc7z010clg400-1

    # Add sources (all comb cores; the project top selects the stage)
    add_files -norecurse $comb_src

    # Set top module
    set_property top $top_module [current_fileset]

    # Synthesis settings
    set_property STEPS.SYNTH_DESIGN.ARGS.RETIMING false [get_runs synth_1]

    launch_runs synth_1 -jobs 4
    wait_on_run synth_1

    open_run synth_1 -name synth_1

    # Timing analysis - NO clock for purely combinational modules
    # Just measure pin-to-pin combinational delay
    report_timing -max_paths 10 -sort_by slack \
        -from [all_inputs] \
        -to [all_outputs] \
        -file [file join $work_dir "reports/timing_${stage}.rpt"]

    report_timing_summary -file [file join $work_dir "reports/timing_summary_${stage}.rpt"]

    # Resource utilization
    report_utilization -hierarchical -file [file join $work_dir "reports/util_${stage}.rpt"]

    close_project
}

if {$stage_name == "all" || $stage_name == "s1_fetch"} {
    puts "=== Synthesizing Stage 1: Fetch (combinational) ==="
    synth_comb_stage "s1_fetch" "bf2_s1_fetch_comb"
}

if {$stage_name == "all" || $stage_name == "s2_decode"} {
    puts "=== Synthesizing Stage 2: Decode (combinational) ==="
    synth_comb_stage "s2_decode" "bf2_s2_decode_comb"
}

if {$stage_name == "all" || $stage_name == "s3_execute"} {
    puts "=== Synthesizing Stage 3: Execute (combinational) ==="
    synth_comb_stage "s3_execute" "bf2_s3_execute_comb"
}

if {$stage_name == "all" || $stage_name == "s4_writeback"} {
    puts "=== Synthesizing Stage 4: Writeback (combinational) ==="
    synth_comb_stage "s4_writeback" "bf2_s4_writeback_comb"
}

if {$stage_name == "all" || $stage_name == "longjump"} {
    puts "=== Synthesizing Long Jump Pipeline (combinational) ==="
    synth_comb_stage "longjump" "bf2_longjump_pipeline_comb"
}

if {$stage_name == "all" || $stage_name == "alu"} {
    puts "=== Synthesizing ALU (combinational) ==="
    synth_comb_stage "alu" "bf2_alu_comb"
}

if {$stage_name == "all" || $stage_name == "stack"} {
    puts "=== Synthesizing Stack ==="
    synth_comb_stage "stack" "bf2_stack"
}

if {$stage_name == "all" || $stage_name == "stack2"} {
    puts "=== Synthesizing Stack2 (push/pop shift-register stack) ==="
    synth_comb_stage "stack2" "bf2_stack2_comb"
}

puts "=== Done. Reports in $work_dir/reports/ ==="