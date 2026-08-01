# BF1 SoC Library — Brainfuck CPU and Pipeline Experiments

This directory contains the original **BF1 single-cycle Brainfuck CPU** and a series of pipeline experiments (**BF2** variants) for timing analysis and architectural exploration on the Xilinx Artix-7 / Zynq-7000 (xc7z010clg400-1).

---

## File Overview

### Core CPU Implementations

| File | Description |
|------|-------------|
| **`bf1.v`** | **Golden reference** — original single-cycle BF1 CPU (Verilog). Verified on hardware; all pipeline variants must match its byte-level output. |
| **`bf1_soc.v`** | Top-level SoC wrapper instantiating `bf1` + UART + external memory interface. Used for `make sdimg` FPGA builds. |
| **`bf2_phase.sv`** | **Functionally verified 2-phase pipeline** (FD \| EX/WB) — drop-in replacement for BF1. Passes Verilator byte-comparison against `bf1.v` on `hello.bin`, `mandelbrot.bin`, `squares.bin`, `xmastree.bin`. |
| **`bf2_pipeline.sv`** | **4-stage pipeline** (Fetch → Decode → Execute → Mem/WB) with BRAM models. Timing model only (not functionally verified). WNS +6.445 ns @ 100 MHz, max ~281 MHz. |
| **`bf2_2stage.sv`** | **2-stage pipeline** (FD \| EX/WB) with BRAM models. Alternative merged-boundary design. WNS +5.293 ns @ 100 MHz, max ~212 MHz, **half the FFs** of 4-stage (78 vs 137). |

### Combinational / Timing Analysis Modules

| File | Description |
|------|-------------|
| **`bf2_comb.sv`** | Pure combinational cores for each stage (`bf2_s1_fetch_comb`, `bf2_s2_decode_comb`, `bf2_s3_execute_comb`, `bf2_s4_writeback_comb`, `bf2_alu_comb`, `bf2_longjump_pipeline_comb`). Used for pin-to-pin delay measurement. |
| **`bf2_r2r.sv`** | **Register-to-register (R2R) wrappers** — each combinational core wrapped in input/output FFs (`bf2_s1_fetch_r2r`, `bf2_s2_decode_r2r`, `bf2_s3_execute_r2r`, `bf2_s4_writeback_r2r`, `bf2_longjump_r2r`, `bf2_alu_r2r`, `bf2_stack2_r2r`). Measures **true internal stage delay** (no IBUF/OBUF). |
| **`bf2_2stage_r2r.sv`** | R2R wrappers for the 2-stage merged clouds: `bf2_fd_r2r` (fetch+decode), `bf2_exwb_r2r` (execute+writeback). |
| **`bf2_stack2.sv`** | Shift-register LIFO stack (head + tail) replacing the original RAM-based `stack.v`. Registered read (`rd = head`) removes combinational read mux from critical path. **3× fewer LUTs**, slightly more FFs. |

### Testbench & Verification

| File | Description |
|------|-------------|
| **`bf1_verilator.cpp`** | C++ Verilator testbench for BF1 golden model. Runs compiled `.bin` bytecode, supports `+trace`, `+verbose`, `+maxsteps=N`. |
| **`bf2_verilator.cpp`** | C++ Verilator testbench for `bf2_phase` (2-phase pipeline). Alternates `en_s12` / `en_s34` enables; samples outputs only after Phase B. |
| **`tb_bf1_soc.sv`** | SystemVerilog testbench for `bf1_soc` (UART + external memory). |
| **`tb_bf1_soc_uart.sv`** | UART-focused testbench. |
| **`tb_longjump_pipeline.sv`** | Unit test for the 2-cycle long-jump helper. |
| **`tb_gp2.sv`** | Generic test harness. |

### Build & Timing Scripts

| File | Description |
|------|-------------|
| **`Makefile`** | Targets: `verilator-build`, `verilator-run`, `sim-verilator`, `verilator2-build`, `verilator2-run`, `sim-verilator2`, plus all `synth-*` targets for Vivado timing analysis. |
| **`synth_stage.tcl`** | Vivado script: synthesize registered stage modules from `bf2.sv` (archived). |
| **`synth_comb.tcl`** | Vivado script: synthesize combinational cores from `bf2_comb.sv` (pin-to-pin delay). |
| **`synth_r2r.tcl`** | Vivado script: synthesize R2R wrappers from `bf2_r2r.sv` (true internal delay). |
| **`synth_pipeline_full.tcl`** | Vivado script: synthesize full 4-stage pipeline `bf2_pipeline_full`. |
| **`synth_2stage_full.tcl`** | Vivado script: synthesize full 2-stage pipeline `bf2_2stage_full`. |
| **`synth_2stage_r2r.tcl`** | Vivado script: synthesize merged-cloud R2R wrappers `bf2_fd_r2r`, `bf2_exwb_r2r`. |

### Documentation & Archive

| File | Description |
|------|-------------|
| **`TIMING_ANALYSIS_SUMMARY.md`** | Complete timing analysis: combinational delays, R2R measurements, full pipeline results, 2-stage comparison, stack2 impact, recommendations. |
| **`verilator.md`** | How to build/run Verilator simulations for BF1 and BF2. |
| **`archive_4stage/`** | Snapshot of the first 4-stage pipeline iteration (before stack2 + S2/S3 partition fix). Preserved for historical comparison. |

---

## Quick Start

### Build & Run BF1 (Golden Model)

```bash
cd hdl/library/bf1_soc
make verilator-build          # builds obj_dir/Vbf1 (~1 min)
make sim-verilator SIM_VER_PROG=../../../demos/brainfuck_org/src/hello.bin
```

### Build & Run BF2 Phase (Functionally Verified Pipeline)

```bash
cd hdl/library/bf1_soc
make verilator2-build         # builds obj_dir/Vbf2_phase_full
make sim-verilator2 SIM_VER2_PROG=../../../demos/brainfuck_org/src/hello.bin
```

### Timing Analysis (Requires Vivado 2023.2)

```bash
# Individual stage R2R timing (most accurate internal delay)
make synth-r2r

# Full pipeline synthesis + timing
make synth-pipeline

# 2-stage pipeline synthesis + timing
make synth-2stage

# All combinational pin-to-pin delays
make synth-comb
```

---

## Key Timing Results Summary

| Design | WNS @ 100 MHz | Max Freq | LUTs | FFs | BRAM | Notes |
|--------|---------------|----------|------|-----|------|-------|
| BF1 (single-cycle) | — | ~100-120 MHz | ~50 | — | 0 | Golden model |
| BF2 4-stage | **+6.445 ns** | **~281 MHz** | 53 | 137 | 9 (1×18K + 8×36K) | BRAM clock-to-out limited |
| BF2 2-stage | +5.293 ns | ~212 MHz | 54 | **78** | 9 | Half FFs; ALU→DMEM write-addr path |
| BF2 Phase (verified) | N/A (Verilator only) | N/A | — | — | — | Byte-identical to BF1 |

**Critical bottleneck in all BRAM designs:** DMEM BRAM clock-to-out (2.454 ns). Adding output registers (`DOA_REG=1`) would cut this to ~0.5 ns, unlocking **>200 MHz**.

---

## Pipeline Architecture Notes

### BF1 (Single-Cycle)
- All operations in one clock: fetch → decode → ALU → memory → writeback
- 2-cycle long-jump prefix (`0xA0-0xBF`) already partially pipelined
- Asynchronous memory model (simulation only)

### BF2 4-Stage (Fetch → Decode → Execute → Mem/WB)
- **S1 Fetch**: IMEM read (registered BRAM output) + pc+1
- **S2 Decode**: Opcode decode, ALU operand setup, branch resolution
- **S3 Execute**: ALU operation, long-jump target add, DMEM address
- **S4 Mem/WB**: DMEM read/write, register file writeback, stack push/pop
- IMEM BRAM registered output = fetch register
- DMEM BRAM 1-cycle read/write

### BF2 2-Stage (FD | EX/WB)
- **FD** (Phase A): Fetch + Decode + PC commit (branch resolved here)
- **EX/WB** (Phase B): Execute + Mem/WB + architectural state update
- Eliminates IF/ID and EX/MEM register banks → **half the FFs**
- DMEM write uses combinational EX address → new critical path (ALU→BRAM write-addr)

### BF2 Phase (2-Phase, Functionally Verified)
- Same logical split as 2-stage but driven by external `en_s12` / `en_s34`
- Alternating enables simulate 2-cycle-per-instruction execution
- No hazard logic needed (branch resolved in decode, async DMEM read)
- Verified byte-for-byte against BF1 on all test programs

---

## Long-Jump Helper (2-Cycle Prefix)

- **Prefix opcode** `0xA0-0xBF`: computes `pj_carry5 = pc[4:0] + insn[4:0]` carry, saves `pj_pc_high = pc[14:5]`
- **Jump opcode** `[` / `]`: target = `{pj_pc_high + insn[14:5] + carry, pj_carry5[4:0]}`
- **Key**: carry is REGISTERED between cycles → the two additions are **parallel from registers** (2.32 ns R2R), NOT chained (would be 3.99 ns)
- Feeds the SAME `pc_next` mux in Execute: `pc_next = lj ? pj_result : alu_c`

---

## Stack2: Shift-Register LIFO

- Replaces original `stack.v` (LUTRAM with combinational read mux)
- **Head + tail** shift register; `rd = head` is registered
- **Benefits**: removes stack-read mux from critical path, **3× fewer LUTs** (150 → 53 in full pipeline), eliminates multi-driven net warnings
- **Cost**: +27 FFs for shift register

---

## Related Directories

- **`demos/brainfuck_org/`** — Brainfuck source (`.b`), compiler (`comp_bf.py`), precompiled `.bin` files
- **`hdl/projects/ebaz4205/`** — Vivado project for the EBAZ4205 board (uses `bf1_soc.v`)
- **`u-boot-xlnx/`**, **`scripts/`**, **`build/`** — FPGA build flow for `make sdimg`

---

## License

Part of the EBAZ4205-HDMI-Demo project. See root `LICENSE` file.