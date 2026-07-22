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

.PHONY: sim-clean
sim-clean:
	rm -rf xsim.dir $(SIM_LOG) $(SIM_UART_LOG) *.wdb *.pb *.jou *.log webtalk* xelab* .Xil
