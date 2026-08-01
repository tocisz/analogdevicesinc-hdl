LIBRARY_NAME := bf1_soc

GENERIC_DEPS += common.h
GENERIC_DEPS += stack.v
GENERIC_DEPS += bf1.v
GENERIC_DEPS += bf1_soc.v

XILINX_DEPS += bf1_soc_ip.tcl

include ../scripts/library.mk

# ------------------------------------------------------------------
# Simulation targets (Vivado xsim)
# ------------------------------------------------------------------
SIM_TOP    := tb_bf1_soc
SIM_SRC    := bf1_soc.v bf1.v stack.v tb_bf1_soc.sv
SIM_LOG    := $(SIM_TOP)_sim.log

.PHONY: sim
sim: $(SIM_LOG)
	@echo "=== Simulation log: $(SIM_LOG) ==="
	@tail -20 $(SIM_LOG)

$(SIM_LOG): $(SIM_SRC)
	xvlog --sv bf1_soc.v bf1.v stack.v
	xvlog --sv tb_bf1_soc.sv
	xelab $(SIM_TOP) -log xelab.log
	xsim $(SIM_TOP) -R | tee $(SIM_LOG)

# ------------------------------------------------------------------
# Integration simulation: bf1_soc + uart_phy over a real serial link
# (exercises the full RX/TX handshake the unit TB cannot see)
# ------------------------------------------------------------------
SIM_UART_TOP := tb_bf1_soc_uart
SIM_UART_LOG := $(SIM_UART_TOP)_sim.log

.PHONY: sim-uart
sim-uart: $(SIM_UART_LOG)
	@echo "=== Simulation log: $(SIM_UART_LOG) ==="
	@tail -30 $(SIM_UART_LOG)

$(SIM_UART_LOG): bf1_soc.v bf1.v stack.v ../uart_phy/uart_phy.v tb_bf1_soc_uart.sv
	xvlog --sv bf1_soc.v bf1.v stack.v ../uart_phy/uart_phy.v
	xvlog --sv tb_bf1_soc_uart.sv
	xelab $(SIM_UART_TOP) -log xelab_uart.log
	xsim $(SIM_UART_TOP) -R | tee $(SIM_UART_LOG)

.PHONY: wave
wave: $(SIM_TOP)_wave.wdb
	xsim --gui $(SIM_TOP)_wave.wdb &

$(SIM_TOP)_wave.wdb: $(SIM_SRC)
	xvlog --sv bf1_soc.v bf1.v stack.v
	xvlog --sv tb_bf1_soc.sv
	xelab $(SIM_TOP)
	xsim $(SIM_TOP) --tclbatch $(SIM_TOP)_wave.tcl

# ------------------------------------------------------------------
# Verilator simulation (fast C++ model of the bf1 core)
# Ported from the old standalone sim (~/repos/verilog/brainfuck_machine)
# to the current bf1.v (drives cpu_active/ctrl_reset_i, feeds ',' from
# an optional input file via io_rd).
#
# Any program compiled with the bf1 bytecode compiler can be simulated:
#   python3 demos/brainfuck_org/comp_bf.py prog.b -o prog.bin
#   make verilator-build
#   obj_dir/Vbf1 prog.bin            # program output on stdout
#   obj_dir/Vbf1 prog.bin in.txt     # feed ',' from a file (ghost.b, xmastree.b)
#   obj_dir/Vbf1 prog.bin +maxsteps=N    # cap for non-terminating programs
#   obj_dir/Vbf1 prog.bin +trace         # dump bf1.vcd
# All-in-one:   make sim-verilator SIM_VER_PROG=prog.bin SIM_VER_INPUT=input.txt
# ------------------------------------------------------------------
SIM_VER_TOP   := Vbf1
SIM_VER_SRC   := bf1.v stack.v
SIM_VER_CPP   := bf1_verilator.cpp
SIM_VER_BIN   := obj_dir/$(SIM_VER_TOP)
SIM_VER_PROG  ?= out.bin
SIM_VER_INPUT ?=
SIM_VER_ARGS  ?=  # opt-in: +verbose, +trace, +maxsteps=N

.PHONY: sim-verilator verilator-build verilator-run verilator-clean

sim-verilator: verilator-build verilator-run

verilator-build: $(SIM_VER_BIN)

$(SIM_VER_BIN): $(SIM_VER_SRC) $(SIM_VER_CPP) common.h
	verilator -Wall --trace --cc bf1.v stack.v --exe $(SIM_VER_CPP)
	make -C obj_dir -j -f $(SIM_VER_TOP).mk $(SIM_VER_TOP)

verilator-run: $(SIM_VER_BIN)
	$(SIM_VER_BIN) $(SIM_VER_PROG) $(SIM_VER_INPUT) $(SIM_VER_ARGS)

verilator-clean:
	rm -rf obj_dir

# ------------------------------------------------------------------
# Verilator simulation for bf2_phase (2-phase FD | EX/WB machine)
# Alternates en_s12 / en_s34 enables; outputs sampled at Phase B edge.
# One instruction = two phases (A+B).
#
# Usage:
#   make verilator2-build
#   obj_dir/Vbf2_phase_full prog.bin [input.txt] [+verbose] [+trace] [+maxsteps=N]
# All-in-one: make sim-verilator2 SIM_VER2_PROG=prog.bin SIM_VER2_INPUT=input.txt
# ------------------------------------------------------------------
SIM_VER2_TOP   := Vbf2_phase_full
SIM_VER2_SRC   := bf2_phase.sv bf2_comb.sv bf2_stack2.sv common.h
SIM_VER2_CPP   := bf2_verilator.cpp
SIM_VER2_BIN   := obj_dir/$(SIM_VER2_TOP)
SIM_VER2_PROG  ?= out.bin
SIM_VER2_INPUT ?=
SIM_VER2_ARGS  ?=  # opt-in: +verbose, +trace, +maxsteps=N

.PHONY: sim-verilator2 verilator2-build verilator2-run verilator2-clean

sim-verilator2: verilator2-build verilator2-run

verilator2-build: $(SIM_VER2_BIN)

$(SIM_VER2_BIN): $(SIM_VER2_SRC) $(SIM_VER2_CPP)
	verilator -Wall --trace --top-module bf2_phase_full --cc bf2_phase.sv bf2_comb.sv bf2_stack2.sv --exe $(SIM_VER2_CPP)
	make -C obj_dir -j -f $(SIM_VER2_TOP).mk $(SIM_VER2_TOP)

verilator2-run: $(SIM_VER2_BIN)
	$(SIM_VER2_BIN) $(SIM_VER2_PROG) $(SIM_VER2_INPUT) $(SIM_VER2_ARGS)

verilator2-clean:
	rm -rf obj_dir

# ------------------------------------------------------------------
# Synthesis target (standalone, timing + propagation delay reports)
# ------------------------------------------------------------------
.PHONY: synth
synth: bf1_soc_synth.log
	@echo "=== Synthesis + timing report: bf1_soc_synth.log ==="
	@grep -A 100 "Timing report" bf1_soc_synth.log | head -120

bf1_soc_synth.log: bf1_soc_synth.tcl bf1_soc_synth.xdc common.h stack.v bf1.v bf1_soc.v
	vivado -mode batch -source bf1_soc_synth.tcl 2>&1 | tee bf1_soc_synth.log

.PHONY: sim-clean
sim-clean:
	rm -rf xsim.dir obj_dir $(SIM_LOG) $(SIM_UART_LOG) *.wdb *.pb *.jou *.log webtalk* xelab* .Xil

# ------------------------------------------------------------------
# Pipeline Stage Timing Analysis (bf2.v)
# ------------------------------------------------------------------
STAGES := s1_fetch s2_decode s3_execute s4_writeback longjump stack
COMB_STAGES := s1_fetch s2_decode s3_execute s4_writeback longjump alu stack stack2

.PHONY: synth-stages $(addprefix synth-stage-,$(STAGES))

synth-stages: $(addprefix synth-stage-,$(STAGES))

$(addprefix synth-stage-,$(STAGES)): synth-stage-%:
	mkdir -p synth_$*
	vivado -mode batch -source synth_stage.tcl -tclargs $* 2>&1 | tee synth_$*/build.log

.PHONY: synth-comb $(addprefix synth-comb-,$(COMB_STAGES))

synth-comb: $(addprefix synth-comb-,$(COMB_STAGES))

$(addprefix synth-comb-,$(COMB_STAGES)): synth-comb-%:
	mkdir -p synth_${*}_comb
	vivado -mode batch -source synth_comb.tcl -tclargs $* 2>&1 | tee synth_${*}_comb/build.log

# ------------------------------------------------------------------
# Register-to-Register stage timing (bf2_r2r.sv: comb core wrapped in
# input/output FFs -- no IBUF/OBUF on the measured path)
# ------------------------------------------------------------------
R2R_STAGES := s1_fetch s2_decode s3_execute s4_writeback longjump alu stack2

.PHONY: synth-r2r $(addprefix synth-r2r-,$(R2R_STAGES))

synth-r2r: $(addprefix synth-r2r-,$(R2R_STAGES))

$(addprefix synth-r2r-,$(R2R_STAGES)): synth-r2r-%:
	mkdir -p synth_${*}_r2r
	vivado -mode batch -source synth_r2r.tcl -tclargs $* 2>&1 | tee synth_${*}_r2r/build.log

.PHONY: synth-r2r-clean
synth-r2r-clean:
	rm -rf synth_*_r2r/

.PHONY: synth-stages-clean synth-comb-clean
synth-stages-clean:
	rm -rf synth_*/
synth-comb-clean:
	rm -rf synth_*_comb/

# ------------------------------------------------------------------
# Full pipeline synthesis (bf2_pipeline.sv: 4 stages + BRAM + stack2)
# ------------------------------------------------------------------
.PHONY: synth-pipeline
synth-pipeline: bf2_pipeline_synth.log
	@echo "=== Full pipeline synthesis + timing: bf2_pipeline_synth.log ==="
	@grep -A 30 "WNS\|Worst Negative Slack" bf2_pipeline_synth.log | head -40

bf2_pipeline_synth.log: synth_pipeline_full.tcl common.h bf2_comb.sv bf2_stack2.sv bf2_pipeline.sv
	mkdir -p synth_pipeline_full
	cd synth_pipeline_full && vivado -mode batch -source ../synth_pipeline_full.tcl 2>&1 | tee ../bf2_pipeline_synth.log

# ------------------------------------------------------------------
# 2-Stage pipeline (bf2_2stage.sv: FD | EX/WB) timing analysis
# ------------------------------------------------------------------
2S_R2R_CLOUDS := fd exwb

.PHONY: synth-2stage-r2r $(addprefix synth-2stage-r2r-,$(2S_R2R_CLOUDS))

synth-2stage-r2r: $(addprefix synth-2stage-r2r-,$(2S_R2R_CLOUDS))

$(addprefix synth-2stage-r2r-,$(2S_R2R_CLOUDS)): synth-2stage-r2r-%:
	mkdir -p synth_2stage_r2r
	vivado -mode batch -source synth_2stage_r2r.tcl -tclargs $* 2>&1 | tee synth_2stage_r2r/build_$*.log

.PHONY: synth-2stage
synth-2stage: bf2_2stage_synth.log
	@echo "=== 2-Stage pipeline synthesis + timing: bf2_2stage_synth.log ==="
	@grep -A 30 "WNS\|Worst Negative Slack" bf2_2stage_synth.log | head -40

bf2_2stage_synth.log: synth_2stage_full.tcl common.h bf2_comb.sv bf2_stack2.sv bf2_2stage.sv
	mkdir -p synth_2stage_full
	cd synth_2stage_full && vivado -mode batch -source ../synth_2stage_full.tcl 2>&1 | tee ../bf2_2stage_synth.log

.PHONY: synth-2stage-clean
synth-2stage-clean:
	rm -rf synth_2stage_full synth_2stage_r2r bf2_2stage_synth.log
