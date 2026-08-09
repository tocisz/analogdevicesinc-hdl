LIBRARY_NAME := axis_byte_bridge

GENERIC_DEPS += axis_byte_bridge.sv

XILINX_DEPS += axis_byte_bridge_ip.tcl

include ../scripts/library.mk

# ------------------------------------------------------------------
# Simulation targets (Vivado xsim)
# ------------------------------------------------------------------
SIM_TOP    := tb_axis_byte_bridge
SIM_SRC    := axis_byte_bridge.sv tb_axis_byte_bridge.sv
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
	verilator --lint-only -Wall axis_byte_bridge.sv

lint-verible:
	verible-verilog-lint axis_byte_bridge.sv

.PHONY: sim-clean
sim-clean:
	rm -rf xsim.dir $(SIM_LOG) *.wdb *.pb *.jou *.log webtalk* xelab* .Xil
