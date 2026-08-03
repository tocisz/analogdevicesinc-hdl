LIBRARY_NAME := bf2_soc

GENERIC_DEPS += common.h
GENERIC_DEPS += bf2_stack2.sv
GENERIC_DEPS += bf2_s12_comb.sv
GENERIC_DEPS += bf2_s34_comb.sv
GENERIC_DEPS += bf2_phase.sv
GENERIC_DEPS += bf2_soc.sv

XILINX_DEPS += bf2_soc_ip.tcl

include ../scripts/library.mk

# ------------------------------------------------------------------
# Verilator simulation for bf2_phase (overlapped FD | EX/WB machine)
# Drives the single `enable` (1 = run, 0 = IO freeze); pointer-move/stack
# bubbles are handled inside the core. ~1 IPC steady state.
#
# Usage:
#   make verilator2-build
#   obj_dir/Vbf2_phase_full prog.bin [input.txt] [+verbose] [+trace] [+maxsteps=N]
# All-in-one: make sim-verilator2 SIM_VER2_PROG=prog.bin SIM_VER2_INPUT=input.txt
# ------------------------------------------------------------------
SIM_VER2_TOP   := Vbf2_phase
SIM_VER2_SRC   := bf2_phase.sv bf2_s12_comb.sv bf2_s34_comb.sv bf2_stack2.sv common.h
SIM_VER2_CPP   := bf2_verilator.cpp
SIM_VER2_BIN   := obj_dir/$(SIM_VER2_TOP)
SIM_VER2_PROG  ?= out.bin
SIM_VER2_INPUT ?=
SIM_VER2_ARGS  ?=  # opt-in: +verbose, +trace, +maxsteps=N

.PHONY: sim-verilator2 verilator2-build verilator2-run verilator2-clean

sim-verilator2: verilator2-build verilator2-run

verilator2-build: $(SIM_VER2_BIN)

$(SIM_VER2_BIN): $(SIM_VER2_SRC) $(SIM_VER2_CPP)
	verilator -Wall --trace --top-module bf2_phase --cc bf2_phase.sv bf2_s12_comb.sv bf2_s34_comb.sv bf2_stack2.sv --exe $(SIM_VER2_CPP)
	make -C obj_dir -j -f $(SIM_VER2_TOP).mk $(SIM_VER2_TOP)

verilator2-run: $(SIM_VER2_BIN)
	$(SIM_VER2_BIN) $(SIM_VER2_PROG) $(SIM_VER2_INPUT) $(SIM_VER2_ARGS)

verilator2-clean:
	rm -rf obj_dir

# ------------------------------------------------------------------
# Pipeline Stage Timing Analysis (timing/synth_comb.tcl: combinational cores)
# ------------------------------------------------------------------
COMB_STAGES := s1_fetch s2_decode s3_execute s4_writeback longjump alu stack stack2

.PHONY: synth-comb $(addprefix synth-comb-,$(COMB_STAGES))

synth-comb: $(addprefix synth-comb-,$(COMB_STAGES))

$(addprefix synth-comb-,$(COMB_STAGES)): synth-comb-%:
	mkdir -p synth_${*}_comb
	vivado -mode batch -source timing/synth_comb.tcl -tclargs $* 2>&1 | tee synth_${*}_comb/build.log

.PHONY: synth-comb-clean
synth-comb-clean:
	rm -rf synth_*_comb/

# ------------------------------------------------------------------
# Register-to-Register stage timing (timing/synth_r2r.tcl: comb core wrapped in
# input/output FFs -- no IBUF/OBUF on the measured path)
# ------------------------------------------------------------------
R2R_STAGES := s1_fetch s2_decode s3_execute s4_writeback longjump alu stack2

.PHONY: synth-r2r $(addprefix synth-r2r-,$(R2R_STAGES))

synth-r2r: $(addprefix synth-r2r-,$(R2R_STAGES))

$(addprefix synth-r2r-,$(R2R_STAGES)): synth-r2r-%:
	mkdir -p synth_${*}_r2r
	vivado -mode batch -source timing/synth_r2r.tcl -tclargs $* 2>&1 | tee synth_${*}_r2r/build.log

.PHONY: synth-r2r-clean
synth-r2r-clean:
	rm -rf synth_*_r2r/

# ------------------------------------------------------------------
# Full pipeline synthesis (timing/bf2_pipeline_full.sv: 4 stages + BRAM + stack2)
# ------------------------------------------------------------------
.PHONY: synth-pipeline
synth-pipeline: bf2_pipeline_synth.log
	@echo "=== Full pipeline synthesis + timing: bf2_pipeline_synth.log ==="
	@grep -A 30 "WNS\|Worst Negative Slack" bf2_pipeline_synth.log | head -40

bf2_pipeline_synth.log: timing/synth_pipeline_full.tcl common.h bf2_stack2.sv \
	timing/bf2_pipeline_full.sv timing/bf2_s1_fetch_with_imem.sv \
	timing/bf2_bram_icode.sv timing/bf2_bram_data.sv \
	timing/bf2_s2_decode_comb.sv timing/bf2_s3_execute_comb.sv
	mkdir -p synth_pipeline_full
	cd synth_pipeline_full && vivado -mode batch -source ../timing/synth_pipeline_full.tcl 2>&1 | tee ../bf2_pipeline_synth.log

# ------------------------------------------------------------------
# 2-Stage pipeline (bf2_2stage.sv: FD | EX/WB) timing analysis
# Note: bf2_2stage.sv and related TCL scripts need to be created/moved from archive
# ------------------------------------------------------------------
# .PHONY: synth-2stage
# synth-2stage: bf2_2stage_synth.log
# 	@echo "=== 2-Stage pipeline synthesis + timing: bf2_2stage_synth.log ==="
# 	@grep -A 30 "WNS\|Worst Negative Slack" bf2_2stage_synth.log | head -40
#
# bf2_2stage_synth.log: synth 2stage common.h bf2_s12_comb.sv bf2_s34_comb.sv bf2_stack2.sv
# 	mkdir -p synth_2stage_full
# 	cd synth_2stage_full && vivado -mode batch -source ../synth_2stage_full.tcl 2>&1 | tee ../bf2_2stage_synth.log

.PHONY: sim-clean
sim-clean:
	rm -rf xsim.dir obj_dir *.log *.wdb *.pb *.jou *.log webtalk* xelab* .Xil