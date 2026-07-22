 ###############################################################################
 ## bf1_soc multicycle path constraints
 ##
 ## The bf1 core advances only when cpu_active=1, which is gated by a
 ## half-speed clock enable (bf1_ce) that toggles every 2 clock cycles.
 ## This gives all paths from BRAM output registers (via ALU) to core
 ## registers or BRAM input pins 2 clock periods (20 ns effective) to
 ## settle. Without these constraints, Vivado assumes a 1-cycle (10 ns)
 ## requirement and reports violations (WNS = -2.373 ns, 302 paths).
 ##
 ## Approach: Pin-based multi-cycle path (MCP) constraints.
 ##   - Start points: All fpga_0_clk clock pins of BRAMs within bf1_soc_0
 ##     (code_ram_reg*, data_ram_reg*) AND all fpga_0_clk clock pins of
 ##     bf1_inst flip-flops (pc_reg, maddr_reg, rsp_reg, lj_reg, lj_offset_reg).
 ##     These are the only sequential elements that launch data that
 ##     must propagate within 2 cycles.
 ##   - End points: All sequential input pins within bf1_soc_0/inst:
 ##     register D pins, BRAM address/data/WE pins, distributed RAM
 ##     address/data/WE pins under bf1_inst/rstack.
 ##   - Excluded: PS-facing control registers (ctrl_gp*_in/out) run at
 ##     full 1-cycle speed; their paths are not constrained here.
 ##
 ## Verified: 0 setup violations, 0 hold violations on fpga_0_clk.
 ###############################################################################

 # ── Start points: BRAM clock pins (both Port A and Port B) ──
 # code_ram_reg_0, code_ram_reg_1 + data_ram_reg_0_0 through _0_7
 # Each BRAM has CLKARDCLK and CLKBWRCLK, both driven by fpga_0_clk.
 set bf1_bram_clk [get_pins -hier -filter \
   {NAME =~ *bf1_soc_0/inst/*ram_reg*/CLK*CLK && DIRECTION == IN}]

 # ── Start points: bf1_inst flip-flop clock pins ──
 # pc_reg[*], maddr_reg[*], rsp_reg[*], lj_reg, lj_offset_reg[*]
 set bf1_reg_clk [get_pins -hier -filter \
   {NAME =~ *bf1_soc_0/inst/bf1_inst/*_reg*/C && DIRECTION == IN}]

 # ── End points: bf1_inst flip-flop D pins ──
 set bf1_reg_d [get_pins -hier -filter \
   {NAME =~ *bf1_soc_0/inst/bf1_inst/*_reg*/D && DIRECTION == IN}]

 # ── End points: BRAM input pins (address, data, write-enable) ──
 set bf1_bram_addr [get_pins -hier -filter \
   {NAME =~ *bf1_soc_0/inst/*ram_reg*/ADDR* && DIRECTION == IN}]
 set bf1_bram_data [get_pins -hier -filter \
   {NAME =~ *bf1_soc_0/inst/*ram_reg*/DI* && DIRECTION == IN}]
 set bf1_bram_we [get_pins -hier -filter \
   {NAME =~ *bf1_soc_0/inst/*ram_reg*/WE* && DIRECTION == IN}]

 # ── End points: Distributed RAM input pins under bf1_inst/rstack ──
 # These are the return-stack RAM cells (RAM32M, RAM32X1D primitives)
 set bf1_dist_adr [get_pins -hier -filter \
   {NAME =~ *bf1_soc_0/inst/bf1_inst/*/*ADR* && DIRECTION == IN}]
 set bf1_dist_i [get_pins -hier -filter \
   {NAME =~ *bf1_soc_0/inst/bf1_inst/*/*/I && DIRECTION == IN}]
 set bf1_dist_di [get_pins -hier -filter \
   {NAME =~ *bf1_soc_0/inst/bf1_inst/*/*/DI* && DIRECTION == IN}]
 set bf1_dist_we [get_pins -hier -filter \
   {NAME =~ *bf1_soc_0/inst/bf1_inst/*/*/WE && DIRECTION == IN}]

 # ── Combine and apply ──
 set bf1_start_pins [concat $bf1_bram_clk $bf1_reg_clk]
 set bf1_end_pins [concat $bf1_reg_d $bf1_bram_addr $bf1_bram_data \
   $bf1_bram_we $bf1_dist_adr $bf1_dist_i $bf1_dist_di $bf1_dist_we]

 set_multicycle_path -setup 2 -quiet -from $bf1_start_pins -to $bf1_end_pins
 set_multicycle_path -hold 1 -quiet -from $bf1_start_pins -to $bf1_end_pins
