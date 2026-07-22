# Check timing after applying multicycle constraints
open_checkpoint ebaz4205.runs/impl_1/system_top_routed.dcp

puts "=== Applying Multicycle Path Constraints ==="

# BRAM clock pins as start points (covers BRAM output reg -> everything)
set bram_clk_pins [get_pins -hier -filter {NAME =~ *bf1_soc_0/inst/*ram_reg*/CLK*CLK && DIRECTION == IN}]

# Also: bf1_inst register clock pins as start points (covers reg -> BRAM/rstack paths)
# These registers only update every 2 cycles due to cpu_active gating
set reg_clk_pins [get_pins -hier -filter {NAME =~ *bf1_soc_0/inst/bf1_inst/*_reg*/C && DIRECTION == IN}]
puts "Start points: [expr [llength $bram_clk_pins] + [llength $reg_clk_pins]] BRAM+REG clock pins"

# ALL endpoint pins within bf1_soc_0/inst
# 1. Register D pins
set reg_d_pins [get_pins -hier -filter {NAME =~ *bf1_soc_0/inst/*_reg*/D && DIRECTION == IN}]
puts "  Register D pins: [llength $reg_d_pins]"

# 2. BRAM input pins (address, data, write-enable)
set bram_addr_pins [get_pins -hier -filter {NAME =~ *bf1_soc_0/inst/*ram_reg*/ADDR* && DIRECTION == IN}]
set bram_data_pins [get_pins -hier -filter {NAME =~ *bf1_soc_0/inst/*ram_reg*/DI* && DIRECTION == IN}]
set bram_we_pins [get_pins -hier -filter {NAME =~ *bf1_soc_0/inst/*ram_reg*/WE* && DIRECTION == IN}]
puts "  BRAM input pins: [expr [llength $bram_addr_pins] + [llength $bram_data_pins] + [llength $bram_we_pins]]"

# 3. Distributed RAM input pins under bf1_inst (rstack, store_reg*)
set dist_pins [get_pins -hier -filter {NAME =~ *bf1_soc_0/inst/bf1_inst/*/*ADR* && DIRECTION == IN}]
set dist_pins2 [get_pins -hier -filter {NAME =~ *bf1_soc_0/inst/bf1_inst/*/*/I && DIRECTION == IN}]
set dist_pins3 [get_pins -hier -filter {NAME =~ *bf1_soc_0/inst/bf1_inst/*/*/DI* && DIRECTION == IN}]
set dist_pins4 [get_pins -hier -filter {NAME =~ *bf1_soc_0/inst/bf1_inst/*/*/WE && DIRECTION == IN}]
puts "  Distributed RAM pins: [expr [llength $dist_pins] + [llength $dist_pins2] + [llength $dist_pins3] + [llength $dist_pins4]]"

# Combine start points
set start_pins [concat $bram_clk_pins $reg_clk_pins]

# Combine end points
set end_pins [concat $reg_d_pins $bram_addr_pins $bram_data_pins $bram_we_pins \
                   $dist_pins $dist_pins2 $dist_pins3 $dist_pins4]
puts "Total start points: [llength $start_pins]"
puts "Total end points: [llength $end_pins]"

# Apply MCP
set_multicycle_path -setup 2 -quiet -from $start_pins -to $end_pins
set_multicycle_path -hold 1 -quiet -from $start_pins -to $end_pins
puts "Constraints applied."

# --- Results ---
puts "\n=== fpga_0_clk Timing AFTER MCP ==="
set wns_fpga [get_property SLACK [lindex [get_timing_paths -setup -from [get_clocks fpga_0_clk] -max_paths 1] 0]]
set viol_fpga [llength [get_timing_paths -setup -from [get_clocks fpga_0_clk] -slack_lesser_than 0]]
puts "fpga_0_clk: WNS = [format {%.3f} $wns_fpga] ns, Violations = $viol_fpga"

if {$viol_fpga > 0} {
    puts "\nRemaining violations:"
    set worst_paths [get_timing_paths -setup -from [get_clocks fpga_0_clk] -max_paths 10 -nworst 1 -filter {SLACK < 0}]
    foreach path $worst_paths {
        set slack [get_property SLACK $path]
        set start [get_property STARTPOINT_PIN $path]
        set end [get_property ENDPOINT_PIN $path]
        set dly [get_property DATAPATH_DELAY $path]
        set levels [get_property LOGIC_LEVELS $path]
        puts "  Slack=$slack Delay=$dly Levels=$levels: $start -> $end"
    }
} else {
    puts "\n*** TIMING CLOSED! All fpga_0_clk violations fixed. ***"
}

exit
