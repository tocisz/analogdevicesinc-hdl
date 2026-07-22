# Check hold timing after applying multicycle constraints
open_checkpoint ebaz4205.runs/impl_1/system_top_routed.dcp

puts "=== Applying Multicycle Path Constraints ==="

# BRAM clock pins as start points (covers BRAM output reg -> everything)
set bram_clk_pins [get_pins -hier -filter {NAME =~ *bf1_soc_0/inst/*ram_reg*/CLK*CLK && DIRECTION == IN}]

# bf1_inst register clock pins (covers reg -> BRAM/rstack paths)
set reg_clk_pins [get_pins -hier -filter {NAME =~ *bf1_soc_0/inst/bf1_inst/*_reg*/C && DIRECTION == IN}]

# ALL endpoint pins within bf1_soc_0/inst
# 1. Register D pins
set reg_d_pins [get_pins -hier -filter {NAME =~ *bf1_soc_0/inst/*_reg*/D && DIRECTION == IN}]

# 2. BRAM input pins (address, data, write-enable)
set bram_addr_pins [get_pins -hier -filter {NAME =~ *bf1_soc_0/inst/*ram_reg*/ADDR* && DIRECTION == IN}]
set bram_data_pins [get_pins -hier -filter {NAME =~ *bf1_soc_0/inst/*ram_reg*/DI* && DIRECTION == IN}]
set bram_we_pins [get_pins -hier -filter {NAME =~ *bf1_soc_0/inst/*ram_reg*/WE* && DIRECTION == IN}]

# 3. Distributed RAM input pins under bf1_inst (rstack)
set dist_pins [get_pins -hier -filter {NAME =~ *bf1_soc_0/inst/bf1_inst/*/*ADR* && DIRECTION == IN}]
set dist_pins2 [get_pins -hier -filter {NAME =~ *bf1_soc_0/inst/bf1_inst/*/*/I && DIRECTION == IN}]
set dist_pins3 [get_pins -hier -filter {NAME =~ *bf1_soc_0/inst/bf1_inst/*/*/DI* && DIRECTION == IN}]
set dist_pins4 [get_pins -hier -filter {NAME =~ *bf1_soc_0/inst/bf1_inst/*/*/WE && DIRECTION == IN}]

set start_pins [concat $bram_clk_pins $reg_clk_pins]
set end_pins [concat $reg_d_pins $bram_addr_pins $bram_data_pins $bram_we_pins \
                   $dist_pins $dist_pins2 $dist_pins3 $dist_pins4]

# Apply MCP - setup
set_multicycle_path -setup 2 -quiet -from $start_pins -to $end_pins
# Apply MCP - hold
set_multicycle_path -hold 1 -quiet -from $start_pins -to $end_pins
puts "Constraints applied."

# --- Setup timing ---
puts "\n=== fpga_0_clk SETUP Timing AFTER MCP ==="
set viol [get_timing_paths -setup -from [get_clocks fpga_0_clk] -slack_lesser_than 0]
set nviol [llength $viol]
if {$nviol > 0} {
    set wns [get_property SLACK [lindex $viol 0]]
    puts "WNS = [format {%.3f} $wns] ns, Violations = $nviol"
    puts "\nWorst paths:"
    set worst_paths [get_timing_paths -setup -from [get_clocks fpga_0_clk] -max_paths 5 -nworst 1 -filter {SLACK < 0}]
    foreach path $worst_paths {
        set slack [get_property SLACK $path]
        set start [get_property STARTPOINT_PIN $path]
        set end [get_property ENDPOINT_PIN $path]
        set dly [get_property DATAPATH_DELAY $path]
        set levels [get_property LOGIC_LEVELS $path]
        puts "  Slack=[format {%.3f} $slack] Delay=[format {%.3f} $dly] Levels=$levels: $start -> $end"
    }
} else {
    puts "*** All fpga_0_clk setup paths MET (0 violations) ***"
}

# --- Hold timing ---
puts "\n=== fpga_0_clk HOLD Timing AFTER MCP ==="
set hold_viol [get_timing_paths -hold -from [get_clocks fpga_0_clk] -slack_lesser_than 0]
set nhold_viol [llength $hold_viol]
if {$nhold_viol > 0} {
    set whs [get_property SLACK [lindex $hold_viol 0]]
    puts "WHS = [format {%.3f} $whs] ns, Hold Violations = $nhold_viol"
    puts "\nWorst hold paths:"
    set worst_hold [get_timing_paths -hold -from [get_clocks fpga_0_clk] -max_paths 5 -nworst 1 -filter {SLACK < 0}]
    foreach path $worst_hold {
        set slack [get_property SLACK $path]
        set start [get_property STARTPOINT_PIN $path]
        set end [get_property ENDPOINT_PIN $path]
        puts "  Slack=[format {%.3f} $slack]: $start -> $end"
    }
} else {
    puts "*** All fpga_0_clk hold paths MET (0 violations) ***"
}

exit
