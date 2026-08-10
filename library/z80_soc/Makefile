LIBRARY_NAME := z80_soc

GENERIC_DEPS += rtl/core/tv80s.v
GENERIC_DEPS += rtl/core/tv80_core.v
GENERIC_DEPS += rtl/core/tv80_alu.v
GENERIC_DEPS += rtl/core/tv80_mcode.v
GENERIC_DEPS += rtl/core/tv80_reg.v
GENERIC_DEPS += rtl/wb_tv80/wb_tv80.v
GENERIC_DEPS += z80_soc.sv

XILINX_DEPS += z80_soc_ip.tcl

include ../scripts/library.mk

# ------------------------------------------------------------------
# Lint targets
# ------------------------------------------------------------------
.PHONY: lint lint-verilator lint-verible

lint: lint-verilator lint-verible

lint-verilator:
	verilator --lint-only --no-timing -Wall --Wno-fatal --top-module z80_soc z80_soc.sv rtl/wb_tv80/wb_tv80.v rtl/core/tv80s.v rtl/core/tv80_core.v rtl/core/tv80_alu.v rtl/core/tv80_mcode.v rtl/core/tv80_reg.v

lint-verible:
	verible-verilog-lint z80_soc.sv

# ------------------------------------------------------------------
# Verilator functional simulation
# ------------------------------------------------------------------
# The testbench loads ROM/RAM through the ctrl_gp interfaces, runs a Z80
# program that performs a data write followed by a data read/write, and
# verifies the results through the PS-side memory readback path.
SIM_TOP := tb_z80_soc
SIM_BIN := obj_dir/V$(SIM_TOP)
SIM_SRCS := \
	tb/tb_z80_soc.sv \
	z80_soc.sv \
	rtl/wb_tv80/wb_tv80.v \
	rtl/core/tv80s.v \
	rtl/core/tv80_core.v \
	rtl/core/tv80_alu.v \
	rtl/core/tv80_mcode.v \
	rtl/core/tv80_reg.v

.PHONY: sim-verilator sim-verilator-clean

sim-verilator: $(SIM_BIN)
	./$(SIM_BIN)

$(SIM_BIN): $(SIM_SRCS)
	verilator --binary --timing --trace --Wno-fatal \
		--top-module $(SIM_TOP) --Mdir obj_dir $(SIM_SRCS)

sim-verilator-clean:
	rm -rf obj_dir z80_soc.vcd

.PHONY: sim-clean
sim-clean: sim-verilator-clean
	rm -rf xsim.dir *.log *.wdb *.pb *.jou webtalk* xelab* .Xil
