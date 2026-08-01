###############################################################################
## bf2_soc timing — no multicycle constraints needed
###############################################################################
##
## The bf2_phase core (inside bf2_soc_0, via bf2_phase_full) executes one
## instruction per (phase A + phase B) pair, driven by two alternating,
## mutually exclusive clock enables (en_s12 / en_s34):
##   - Phase A (en_s12): fetch + decode + branch-resolution cloud
##   - Phase B (en_s34): ALU + post-ALU + return-stack cloud
##
## Each phase gets a FULL 10 ns clock period (100 MHz), and every
## register-to-register path is single-cycle — including the phase-handoff
## paths (arch state -> phase A regs, phase A regs -> arch state).  The
## phase clouds are ~4 ns, so there is comfortable margin.
##
## Contrast with bf1: its single-cycle ALU datapath (~12.5 ns) exceeded the
## 10 ns period, and the old bf1_timing.xdc applied -setup 2 / -hold 1
## multicycle exceptions on all paths inside bf1_soc_0/inst*.  That blanket
## exception would be WRONG for bf2_phase because the phase-handoff paths
## above are genuinely single-cycle.  Removing it lets Vivado verify every
## path at the true 10 ns budget.
##
## The PS-side control paths (ctrl_gp*_out -> bf2_soc_0) and the UART PHY
## paths are all relaxed register-to-register paths and need no exceptions.
###############################################################################
