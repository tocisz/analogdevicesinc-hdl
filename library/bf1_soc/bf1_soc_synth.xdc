# 50 MHz effective clock for standalone bf1_soc synthesis
# The bf1 core advances only every 2 clock cycles via bf1_ce,
# giving the ALU data path ~20 ns to settle.  This matches the
# set_multicycle_path -setup 2 constraint used in the full project.
create_clock -name clk_i -period 20.000 [get_ports clk_i]
