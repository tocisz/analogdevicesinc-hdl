LIBRARY_NAME := case_toggle

GENERIC_DEPS += case_toggle.sv

XILINX_DEPS += case_toggle_ip.tcl

include ../scripts/library.mk

# ------------------------------------------------------------------
# Simulation targets (Vivado xsim)
# ------------------------------------------------------------------
SIM_TOP    := tb_case_toggle
SIM_SRC    := case_toggle.sv tb_case_toggle.sv
SIM_LOG    := $(SIM_TOP)_sim.log

.PHONY: sim
sim: $(SIM_LOG)
	@echo "=== Simulation log: $(SIM_LOG) ==="
	@tail -20 $(SIM_LOG)

$(SIM_LOG): $(SIM_SRC)
	xvlog --sv $(SIM_SRC)
	xelab $(SIM_TOP) -log xelab.log
	xsim $(SIM_TOP) -R | tee $(SIM_LOG)

# ------------------------------------------------------------------
# Lint targets
# ------------------------------------------------------------------
.PHONY: lint lint-verilator lint-verible

lint: lint-verilator lint-verible

lint-verilator:
	verilator --lint-only -Wall case_toggle.sv

lint-verible:
	verible-verilog-lint case_toggle.sv

.PHONY: sim-clean
sim-clean:
	rm -rf xsim.dir $(SIM_LOG) *.wdb *.pb *.jou *.log webtalk* xelab* .Xil
