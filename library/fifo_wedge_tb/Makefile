LIB_ROOT := ..
BRIDGE_SV := $(LIB_ROOT)/axis_byte_bridge/axis_byte_bridge.sv
ACIA_SV   := $(LIB_ROOT)/z80_soc/rtl/acia68b50/acia68b50.sv

# Scenario knobs (see tb_fifo_wedge.sv header for the full list)
RX_CUT   ?= 1
PLUSARGS ?=

.PHONY: sim sim-gui sim-clean

sim: sim.log
	@echo "=== tail of sim.log ==="
	@tail -25 sim.log

sim.log: tb_fifo_wedge.sv $(BRIDGE_SV) $(ACIA_SV) run.tcl
	RX_CUT=$(RX_CUT) PLUSARGS="$(PLUSARGS)" \
		vivado -mode batch -source run.tcl -journal vivado.jou -log vivado.log | tee sim.log

# GUI wave viewer for a finished run
sim-gui:
	cd fifo_wedge_sim && xsim tb_fifo_wedge --gui &

sim-clean:
	rm -rf fifo_wedge_sim sim.log vivado.jou vivado.log webtalk* .Xil
