###############################################################################
## bf1_soc multicycle path constraints
##
## The bf1 CPU uses a half-speed clock enable (bf1_ce, toggling every other
## cycle) to gate all register updates and BRAM reads. This gives the
## combinational ALU data path (BRAM output -> ALU -> BRAM input) ~20 ns to
## settle, though the physical clock period is only 10 ns (100 MHz).
##
## Without these constraints, Vivado reports ~294 timing violations on
## fpga_0_clk with WNS = -1.891 ns (critical path = ~11.9 ns vs 10 ns clock).
##
## Approach: Apply set_multicycle_path -setup 2 / -hold 1 to ALL paths
## between sequential cells within the bf1_soc_0 hierarchy. This is the same
## approach used in the original IP-level bf1_soc_constr.xdc, but scoped
## to the instance path in the project context.
##
## Note: PS-side control register paths (ctrl_gp*_out -> bf1_soc_0) are NOT
## gated by bf1_ce, but they start outside the bf1_soc_0 hierarchy and thus
## are not affected by this constraint.
###############################################################################

set_multicycle_path -setup 2 \
  -from [get_cells -hier -filter {IS_SEQUENTIAL && NAME =~ *bf1_soc_0/inst*}] \
  -to   [get_cells -hier -filter {IS_SEQUENTIAL && NAME =~ *bf1_soc_0/inst*}]

set_multicycle_path -hold 1 \
  -from [get_cells -hier -filter {IS_SEQUENTIAL && NAME =~ *bf1_soc_0/inst*}] \
  -to   [get_cells -hier -filter {IS_SEQUENTIAL && NAME =~ *bf1_soc_0/inst*}]
