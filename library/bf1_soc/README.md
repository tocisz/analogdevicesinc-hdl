# BF1 SoC Library — Original Single-Cycle Brainfuck CPU

This directory contains the **BF1 single-cycle Brainfuck CPU** — the golden reference implementation verified on hardware.

---

## File Overview

### Core CPU Implementation

| File | Description |
|------|-------------|
| **`bf1.v`** | **Golden reference** — original single-cycle BF1 CPU (Verilog). Verified on hardware; all pipeline variants must match its byte-level output. |
| **`bf1_soc.v`** | SoC wrapper instantiating `bf1` + UART + external memory interface (dual-port BRAMs for code/data, register-driven PS control via `axi_gpreg`). |
| **`stack.v`** | Original LUTRAM-based return stack (combinational read, registered write). |

### Testbench & Verification

| File | Description |
|------|-------------|
| **`bf1_verilator.cpp`** | C++ Verilator testbench for BF1 golden model. Runs compiled `.bin` bytecode, supports `+trace`, `+verbose`, `+maxsteps=N`. |
| **`tb_bf1_soc.sv`** | SystemVerilog testbench for `bf1_soc` (UART + external memory). |
| **`tb_bf1_soc_uart.sv`** | UART-focused testbench. |
| **`tb_longjump_pipeline.sv`** | Unit test for the 2-cycle long-jump helper. |
| **`tb_gp2.sv`** | Generic test harness. |

### Build & Timing Scripts

| File | Description |
|------|-------------|
| **`Makefile`** | Targets: `verilator-build`, `verilator-run`, `sim-verilator`, `sim`, `sim-uart`, `synth`. |
| **`bf1_soc_synth.tcl`** | Vivado script: synthesize `bf1_soc` for timing analysis. |
| **`bf1_soc_synth.xdc`** | Timing constraints for BF1 (multicycle -setup 2 / -hold 1 on ALU path). |

### IP Packaging

| File | Description |
|------|-------------|
| **`bf1_soc_ip.tcl`** | Creates the `bf1_soc` IP (VLNV: `analog.com:user:bf1_soc:1.0`). |

### Documentation

| File | Description |
|------|-------------|
| **`verilator.md`** | How to build/run Verilator simulations for BF1. |

---

## Quick Start

### Build & Run BF1 (Golden Model)

```bash
cd hdl/library/bf1_soc
make verilator-build          # builds obj_dir/Vbf1 (~1 min)
make sim-verilator SIM_VER_PROG=../../../demos/brainfuck_org/src/hello.bin
```

### Vivado Simulation

```bash
cd hdl/library/bf1_soc
make sim          # xsim with tb_bf1_soc
make sim-uart     # xsim with tb_bf1_soc_uart (full UART handshake)
```

### Timing Analysis (Requires Vivado 2023.2)

```bash
cd hdl/library/bf1_soc
make synth
```

---

## Key Timing Results Summary

| Design | WNS @ 100 MHz | Max Freq | Notes |
|--------|---------------|----------|-------|
| BF1 (single-cycle) | ~-2.5 ns | ~100-120 MHz | ALU path ~12.5 ns exceeds 10 ns period; requires multicycle constraints |

The BF1 ALU datapath exceeds the 10 ns clock period at 100 MHz. The `bf1_timing.xdc` applies blanket `-setup 2 / -hold 1` multicycle exceptions to meet timing, limiting max frequency.

---

## Pipeline Architecture Notes

### BF1 (Single-Cycle)
- All operations in one clock: fetch → decode → ALU → memory → writeback
- 2-cycle long-jump prefix (`0xA0-0xBF`) already partially pipelined
- Asynchronous memory model (simulation only)
- Return stack: LUTRAM with combinational read mux

---

## Related Directories

- **`../bf2_soc/`** — BF2 pipeline experiments (2-phase, 4-stage, 2-stage) and timing analysis.
- **`demos/brainfuck_org/`** — Brainfuck source (`.b`), compiler (`comp_bf.py`), precompiled `.bin` files.
- **`hdl/projects/ebaz4205/`** — Vivado project for the EBAZ4205 board. Uses `bf2_soc` IP (BD instance `bf2_soc_0`) wrapping the verified 2-phase pipeline; `system_project.tcl` uses `bf2_timing.xdc`.
- **`u-boot-xlnx/`**, **`scripts/`**, **`build/`** — FPGA build flow for `make sdimg`

---

## License

Part of the EBAZ4205-HDMI-Demo project. See root `LICENSE` file.