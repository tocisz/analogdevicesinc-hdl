# BF2 SoC Library — Pipeline Experiments and Timing Analysis

This directory contains the **BF2 pipeline variants** (2-phase, 4-stage, 2-stage) and comprehensive timing analysis for the Brainfuck CPU on Xilinx Artix-7 / Zynq-7000 (xc7z010clg400-1).

The **functionally verified 2-phase pipeline** (`bf2_phase`) is the production core, packaged as the `bf2_soc` IP (VLNV: `analog.com:user:bf2_soc:1.0`) — a drop-in replacement for `bf1_soc` with identical external interface.

---

## File Overview

### Core CPU Implementations

| File | Description |
|------|-------------|
| **`bf2_phase.sv`** | **Functionally verified 2-phase pipeline** (FD \| EX/WB) — drop-in replacement for BF1. Passes Verilator byte-comparison against `bf1.v` on `hello.bin`, `mandelbrot.bin`, `squares.bin`, `xmastree.bin`, `ghost.bin`. |
| **`bf2_soc.v`** | **Production SoC wrapper** — drop-in replacement for `bf1_soc.v` (identical external interface) wrapping `bf2_phase_full`: generates alternating `en_s12`/`en_s34` clock enables, derives synchronous active-high reset from `resetq` + PS `ctrl_reset`, adds IO-stall via core's `io_rd_pending`/`io_wr_pending`, presents async-read DMEM model (registered BRAM + last-write bypass). |
| **`bf2_pipeline.sv`** | **4-stage pipeline** (Fetch → Decode → Execute → Mem/WB) with BRAM models. Timing model only (not functionally verified). WNS +6.445 ns @ 100 MHz, max ~281 MHz. |
| **`bf2_2stage.sv`** | **2-stage pipeline** (FD \| EX/WB) with BRAM models. Alternative merged-boundary design. WNS +5.293 ns @ 100 MHz, max ~212 MHz, **half the FFs** of 4-stage (78 vs 137). |

### Combinational / Timing Analysis Modules

| File | Description |
|------|-------------|
| **`bf2_comb.sv`** | Pure combinational cores for each stage (`bf2_s1_fetch_comb`, `bf2_s2_decode_comb`, `bf2_s3_execute_comb`, `bf2_s4_writeback_comb`, `bf2_alu_comb`, `bf2_longjump_pipeline_comb`, `bf2_stack2_comb`). Used for pin-to-pin delay measurement. |
| **`bf2_r2r.sv`** | **Register-to-register (R2R) wrappers** — each combinational core wrapped in input/output FFs (`bf2_s1_fetch_r2r`, `bf2_s2_decode_r2r`, `bf2_s3_execute_r2r`, `bf2_s4_writeback_r2r`, `bf2_longjump_r2r`, `bf2_alu_r2r`, `bf2_stack2_r2r`). Measures **true internal stage delay** (no IBUF/OBUF). |
| **`bf2_stack2.sv`** | Shift-register LIFO stack (head + tail) replacing the original RAM-based `stack.v`. Registered read (`rd = head`) removes combinational read mux from critical path. **3× fewer LUTs**, slightly more FFs. |

### Testbench & Verification

| File | Description |
|------|-------------|
| **`bf2_verilator.cpp`** | C++ Verilator testbench for `bf2_phase` (2-phase pipeline). Alternates `en_s12` / `en_s34` enables; samples outputs only after Phase B. |

### Build & Timing Scripts

| File | Description |
|------|-------------|
| **`Makefile`** | Targets: `verilator2-build`, `verilator2-run`, `sim-verilator2`, `synth-comb`, `synth-r2r`, `synth-pipeline`, `synth-2stage`. |
| **`synth_comb.tcl`** | Vivado script: synthesize combinational cores from `bf2_comb.sv` (pin-to-pin delay). |
| **`synth_r2r.tcl`** | Vivado script: synthesize R2R wrappers from `bf2_r2r.sv` (true internal delay). |
| **`synth_pipeline_full.tcl`** | Vivado script: synthesize full 4-stage pipeline `bf2_pipeline_full`. |
| **`synth_stage.tcl`** | Vivado script: synthesize registered stage modules (from archive). |

### Documentation & Archive

| File | Description |
|------|-------------|
| **`TIMING_ANALYSIS_SUMMARY.md`** | Complete timing analysis: combinational delays, R2R measurements, full pipeline results, 2-stage comparison, stack2 impact, recommendations. |
| **`verilator.md`** | How to build/run Verilator simulations for BF2. |
| **`archive_4stage/`** | Snapshot of the first 4-stage pipeline iteration (before stack2 + S2/S3 partition fix). Preserved for historical comparison. |

---

## Quick Start

### Build & Run BF2 Phase (Functionally Verified Pipeline)

```bash
cd hdl/library/bf2_soc
make verilator2-build         # builds obj_dir/Vbf2_phase_full
make sim-verilator2 SIM_VER2_PROG=../../../demos/brainfuck_org/src/hello.bin
```

### Timing Analysis (Requires Vivado 2023.2)

```bash
# Individual stage R2R timing (most accurate internal delay)
make synth-r2r

# Full pipeline synthesis + timing
make synth-pipeline

# All combinational pin-to-pin delays
make synth-comb
```

---

## Key Timing Results Summary

| Design | WNS @ 100 MHz | Max Freq | LUTs | FFs | BRAM | Notes |
|--------|---------------|----------|------|-----|------|-------|
| BF2 2-phase (verified) | SoC: **+2.522** ns (standalone) / **+1.066** ns (routed) @ 100 MHz | — | 296 | 411 | 10×RAMB36 | `bf2_soc` wrapper: 2-phase enables, no multicycle constraints needed |
| BF2 4-stage | **+6.445 ns** | **~281 MHz** | 53 | 137 | 9 (1×18K + 8×36K) | BRAM clock-to-out limited |
| BF2 2-stage | +5.293 ns | ~212 MHz | 54 | **78** | 9 | Half FFs; ALU→DMEM write-addr path |

**Critical bottleneck in all BRAM designs:** DMEM BRAM clock-to-out (2.454 ns). Adding output registers (`DOA_REG=1`) would cut this to ~0.5 ns, unlocking **>200 MHz**.

---

## Pipeline Architecture Notes

### BF2 Phase (2-Phase, Functionally Verified)
- Same logical split as 2-stage but driven by external `en_s12` / `en_s34`
- Alternating enables simulate 2-cycle-per-instruction execution
- No hazard logic needed (branch resolved in decode, async DMEM read)
- Verified byte-for-byte against BF1 on all test programs

### BF2 4-Stage (Fetch → Decode → Execute → Mem/WB)
- **S1 Fetch**: IMEM read (registered BRAM output) + pc+1
- **S2 Decode**: Opcode decode, ALU operand setup, branch resolution
- **S3 Execute**: ALU operation, long-jump target add, DMEM address
- **S4 Mem/WB**: DMEM read/write, register file writeback, stack push/pop
- IMEM BRAM registered output = fetch register
- DMEM BRAM 1-cycle read/write

### BF2 2-Stage (FD \| EX/WB)
- **FD** (Phase A): Fetch + Decode + PC commit (branch resolved here)
- **EX/WB** (Phase B): Execute + Mem/WB + architectural state update
- Eliminates IF/ID and EX/MEM register banks → **half the FFs**
- DMEM write uses combinational EX address → new critical path (ALU→BRAM write-addr)

### Long-Jump Helper (2-Cycle Prefix)
- **Prefix opcode** `0xA0-0xBF`: computes `pj_carry5 = pc[4:0] + insn[4:0]` carry, saves `pj_pc_high = pc[14:5]`
- **Jump opcode** `[` / `]`: target = `{pj_pc_high + insn[14:5] + carry, pj_carry5[4:0]}`
- **Key**: carry is REGISTERED between cycles → the two additions are **parallel from registers** (2.32 ns R2R), NOT chained (would be 3.99 ns)
- Feeds the SAME `pc_next` mux in Execute: `pc_next = lj ? pj_result : alu_c`

### Stack2: Shift-Register LIFO
- Replaces original `stack.v` (LUTRAM with combinational read mux)
- **Head + tail** shift register; `rd = head` is registered
- **Benefits**: removes stack-read mux from critical path, **3× fewer LUTs** (150 → 53 in full pipeline), eliminates multi-driven net warnings
- **Cost**: +27 FFs for shift register

---

## BF2 SoC (`bf2_soc.v`) — Board Integration

- **Drive for 2 phases**: the wrapper's phase controller toggles `phase_a_done` and asserts `en_s12` (phase A) / `en_s34` (phase B) on alternate cycles — one instruction per 2 clock cycles, the same cadence as the old `bf1_ce` half-speed clocking.
- **IO stall** = hold both enables low (nothing commits): the wrapper evaluates `io_rd_pending` / `io_wr_pending` (registered at the phase-A edge) against `io_rx_valid` / `io_tx_ready`, so `','` writes and `'.'` strobes never fire with stale data or a busy TX.
- **Simplified reset**: `reset` for the core is synchronous active-high, derived as `!resetq || ctrl_reset`.
- **Async DMEM read**: `bf2_phase` reads `mem_din` combinationally in phase A; the data-BRAM registered output is aligned by construction (phase-B read address = next phase-A address) and the last-write bypass covers read-after-write.
- **No multicycle timing constraints**: every register-to-register path is single-cycle (the phase clouds are ~4 ns), so `bf2_timing.xdc` is empty of exceptions — replacing `bf1_timing.xdc`'s blanket `-setup 2 / -hold 1` (which would be wrong for the 1-cycle phase-handoff paths).

---

## Related Directories

- **`../bf1_soc/`** — Original BF1 single-cycle golden reference implementation.
- **`demos/brainfuck_org/`** — Brainfuck source (`.b`), compiler (`comp_bf.py`), precompiled `.bin` files.
- **`hdl/projects/ebaz4205/`** — Vivado project for the EBAZ4205 board. The `bf2_soc` IP (BD instance `bf2_soc_0`) now wraps `bf2_soc.v` + `bf2_phase.sv`; `system_project.tcl` uses `bf2_timing.xdc`.
- **`u-boot-xlnx/`**, **`scripts/`**, **`build/`** — FPGA build flow for `make sdimg`

---

## License

Part of the EBAZ4205-HDMI-Demo project. See root `LICENSE` file.