LIBRARY_NAME := axi_byte_fifo

GENERIC_DEPS += axi_byte_fifo.sv

XILINX_DEPS += axi_byte_fifo_ip.tcl

include ../scripts/library.mk

# ------------------------------------------------------------------
# Simulation target for the host poll() wakeup contract
# ------------------------------------------------------------------
SIM_IRQ_TOP := tb_axi_byte_fifo_irq
SIM_IRQ_SRC := axi_byte_fifo.sv tb_axi_byte_fifo_irq.sv
SIM_IRQ_LOG := $(SIM_IRQ_TOP)_sim.log

.PHONY: sim-irq
sim-irq: $(SIM_IRQ_LOG)
	@cat $(SIM_IRQ_LOG)

$(SIM_IRQ_LOG): $(SIM_IRQ_SRC)
	xvlog --sv $(SIM_IRQ_SRC)
	xelab $(SIM_IRQ_TOP) -log xelab_irq.log
	xsim $(SIM_IRQ_TOP) -R | tee $(SIM_IRQ_LOG)

.PHONY: sim-irq-clean
sim-irq-clean:
	rm -rf xsim.dir $(SIM_IRQ_LOG) xelab_irq.log *.wdb *.pb *.jou *.log webtalk* .Xil
