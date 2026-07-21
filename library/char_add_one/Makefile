LIBRARY_NAME := char_add_one

GENERIC_DEPS += char_add_one.v

XILINX_DEPS += char_add_one_ip.tcl

include ../scripts/library.mk

# ------------------------------------------------------------------
# Simulation targets (Vivado xsim)
# ------------------------------------------------------------------
SIM_TOP    := tb_char_add_one
SIM_SRC    := char_add_one.v tb_char_add_one.v
SIM_LOG    := $(SIM_TOP)_sim.log

.PHONY: sim
sim: $(SIM_LOG)
	@echo "=== Simulation log: $(SIM_LOG) ==="
	@tail -20 $(SIM_LOG)

$(SIM_LOG): $(SIM_SRC)
	xvlog --sv $(SIM_SRC)
	xelab $(SIM_TOP) -log xelab.log
	xsim $(SIM_TOP) -R | tee $(SIM_LOG)

.PHONY: wave
wave: $(SIM_TOP)_wave.wdb
	xsim --gui $(SIM_TOP)_wave.wdb &

$(SIM_TOP)_wave.wdb: $(SIM_SRC)
	xvlog --sv $(SIM_SRC)
	xelab $(SIM_TOP)
	xsim $(SIM_TOP) --tclbatch $(SIM_TOP)_wave.tcl

.PHONY: sim-clean
sim-clean:
	rm -rf xsim.dir $(SIM_LOG) *.wdb *.pb *.jou *.log webtalk* xelab* .Xil
