###############################################################################
## bf1_soc timing constraints
##
## The bf1 CPU uses a half-speed clock enable (bf1_ce, toggling every other
## cycle) to gate all register updates and BRAM Port A reads.  This gives the
## combinational ALU ~20 ns to settle, though the physical clock period is
## only 10 ns (100 MHz).
##
## This constraint is evaluated in the context of the bf1_soc IP instance.
## It constrains ALL paths from any sequential cell to any other sequential
## cell within bf1_soc to 2 clock cycles (setup) / 1 clock cycle (hold).
##
## PS-side paths through Port B (register decoder -> BRAM read/write) are
## NOT gated by bf1_ce, but the start points (ctrl_gp*_out) are OUTSIDE
## this IP's hierarchy, so they are not affected.  Paths from internal
## registers to ctrl_gp*_in are covered but have ample margin.
###############################################################################

set_multicycle_path -setup 2 \
  -from [get_cells -hier -filter {IS_SEQUENTIAL}] \
  -to   [get_cells -hier -filter {IS_SEQUENTIAL}]

set_multicycle_path -hold 1 \
  -from [get_cells -hier -filter {IS_SEQUENTIAL}] \
  -to   [get_cells -hier -filter {IS_SEQUENTIAL}]
