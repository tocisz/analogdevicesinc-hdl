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