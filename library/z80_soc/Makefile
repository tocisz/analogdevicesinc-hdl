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
	verilator --lint-only -Wall --top-module z80_soc z80_soc.sv rtl/wb_tv80/wb_tv80.v rtl/core/tv80s.v rtl/core/tv80_core.v rtl/core/tv80_alu.v rtl/core/tv80_mcode.v rtl/core/tv80_reg.v

lint-verible:
	verible-verilog-lint z80_soc.sv

.PHONY: sim-clean
sim-clean:
	rm -rf xsim.dir obj_dir *.log *.wdb *.pb *.jou *.log webtalk* xelab* .Xil
