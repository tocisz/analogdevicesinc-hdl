###############################################################################
## bf1_soc_synth.tcl
##
## Create a standalone Vivado project for the bf1_soc module, run synthesis,
## and report timing (setup slack, critical paths, propagation delays).
##
## Usage:
##   vivado -mode batch -source bf1_soc_synth.tcl
##
## Or from the bf1_soc Makefile:
##   make synth
###############################################################################

# Part used by the ebaz4205 target (XC7K70T)
set PART xc7k70tfbv676-1
set TOP bf1_soc
set SRCS [list \
  [file normalize "common.h"] \
  [file normalize "stack.v"] \
  [file normalize "bf1.v"] \
  [file normalize "bf1_soc.v"] \
]

# Create a fresh project
set proj_dir "./bf1_soc_synth"
file delete -force $proj_dir
create_project -force $TOP $proj_dir -part $PART

# Add sources
add_files -norecurse -scan_for_includes -fileset sources_1 $SRCS
set_property top $TOP [get_filesets sources_1]

puts "=== Launching synthesis ==="
synth_design -top $TOP -part $PART -flatten_hierarchy rebuilt

puts "=== Timing report (setup): ==="
report_timing -setup -max_paths 10 -nworst 5 -sort_by slack -name timing_1

puts "=== Timing report (delay paths, top 20): ==="
report_timing -setup -max_paths 20 -sort_by group -input_pins

puts "=== Summary: ==="
report_timing_summary -setup -max_paths 10

puts "=== Checking for propagation delays on long-jump paths ==="
report_timing -setup -max_paths 50 -through [get_nets -hier *pj_*] 2>/dev/null || \
  puts "(no paths through pj_* nets found)"
report_timing -setup -max_paths 50 -through [get_nets -hier *lj_*] 2>/dev/null || \
  puts "(no paths through lj_* nets found)"
report_timing -setup -max_paths 50 -through [get_nets -hier *alu_*] 2>/dev/null || \
  puts "(no paths through alu_* nets found)"

# Save the checkpoint for later inspection
write_checkpoint -force $TOP.post_synth.dcp

puts "=== Synthesis complete. Checkpoint saved to ${TOP}.post_synth.dcp ==="

close_project
