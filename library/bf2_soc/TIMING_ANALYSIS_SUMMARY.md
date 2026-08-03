===============================================================================
BF1/2 CPU PIPELINE TIMING ANALYSIS SUMMARY
Target: xc7z010clg400-1 (Artix-7 / Zynq-7000)
Tool: Vivado 2023.2
Date: 2026-08-01
===============================================================================

-------------------------------------------------------------------------------
1. COMBINATIONAL STAGE DELAYS (Pin-to-Pin Analysis)
-------------------------------------------------------------------------------
Measured by synthesizing each stage's combinational logic in isolation
(timing/bf2_*_comb.sv modules, no clock, report_timing -from [all_inputs] -to [all_outputs])

| Stage | Module                    | Max Delay | Logic Levels | Critical Path Components      |
|-------|---------------------------|-----------|--------------|-------------------------------|
| S1    | bf2_s1_fetch_comb         | 6.54 ns   | 5            | CARRY4×3 + IBUF + OBUF        |
| S2    | bf2_s2_decode_comb        | 5.94 ns   | 4            | LUT5×2 + IBUF + OBUF          |
| S3    | bf2_s3_execute_comb       | 7.80 ns   | 7-8          | CARRY4×3 + MUXF7 + LUT5/4     |
| S4    | bf2_s4_writeback_comb     | 4.43 ns   | 2            | IBUF + OBUF (pass-through)    |
| ALU   | bf2_alu_comb              | 6.66 ns   | 7            | CARRY4×4 + IBUF + LUT2 + OBUF  |
| LJ    | bf2_longjump_pipeline_comb| 7.79 ns   | 6            | CARRY4×2 + IBUF + LUT6×2 + OBUF|

KEY FINDING: Stage 3 (Execute) is the combinational bottleneck at 7.8 ns
due to 15-bit ALU adder chain (CARRY4×3) + stack data path (MUXF7).

-------------------------------------------------------------------------------
2. REGISTERED STAGE SYNTHESIS (Individual Stage Modules)
-------------------------------------------------------------------------------
Modules in bf2.sv with internal registers, synthesized standalone
with 100 MHz clock constraint (10 ns period).

| Stage | Module              | WNS @100MHz | Freq Limit | Notes                    |
|-------|---------------------|-------------|------------|--------------------------|
| S1    | bf2_s1_fetch        | +1.42 ns    | ~120 MHz   | 26 FFs, 2 LUTs           |
| S2    | bf2_s2_decode       | (no paths)  | -          | Pure combinational       |
| S3    | bf2_s3_execute      | (no paths)  | -          | Has unused clk/reset     |
| S4    | bf2_s4_writeback    | (no paths)  | -          | Many unconnected ports   |
| LJ    | bf2_longjump_pipeline| (no paths) | -          | 23 FFs, 2 CARRY4         |

Note: Timing analysis for registered stages needs proper input/output
delay constraints to see register-to-register paths.
SUPERSEDED by section 2b below: the R2R wrappers (input FF + stage logic +
output FF) are the correct way to measure internal stage delays.

-------------------------------------------------------------------------------
2b. REGISTER-TO-REGISTER STAGE DELAYS (FF_in -> comb -> FF_out, no IBUF/OBUF)
-------------------------------------------------------------------------------
Measured by wrapping each combinational stage core (timing/bf2_*_comb.sv) in input
and output flip-flops (timing/bf2_*_r2r.sv) -- simulating the pipeline registers
before/after the stage. The ports feed/tap ONLY FFs, so no IBUF/OBUF delay
appears on any measured path. Clock: 100 MHz (10 ns).

| Stage | Module                | R2R Path Delay | WNS @100MHz | Freq Limit | Logic Levels | Critical Path Components  |
|-------|-----------------------|----------------|-------------|------------|--------------|---------------------------|
| S1    | bf2_s1_fetch_r2r      | 2.61 ns        | +7.273 ns   | ~383 MHz   | 3            | CARRY4x3 (pc+1)           |
| S2    | bf2_s2_decode_r2r     | 2.32 ns        | +7.525 ns   | ~431 MHz   | 2            | LUT3+LUT6 (lj offset add) |
| S3    | bf2_s3_execute_r2r    | 3.86 ns        | +6.023 ns   | ~259 MHz   | 4            | CARRY4x2+LUT5+MUXF7       |
| S4    | bf2_s4_writeback_r2r  | 0.79 ns        | +8.795 ns   | --         | 0            | (pure pass-through)       |
| LJ    | bf2_longjump_r2r      | 2.32 ns        | +7.531 ns   | ~431 MHz   | 2            | LUT3+LUT6 (parallel adds) |
| ALU   | bf2_alu_r2r           | 2.36 ns        | +7.524 ns   | ~424 MHz   | 5            | CARRY4x4+LUT2             |
| STK2  | bf2_stack2_r2r        | 0.92 ns        | +8.299 ns   | --         | 0            | (head/tail shift)         |

KEY FINDINGS:
- True internal stage delays are 2-3x SMALLER than the pin-to-pin comb
  numbers (which were dominated by IBUF/OBUF + IOB routing):
  S3 7.80 ns -> 3.86 ns, S1 6.54 -> 2.61, S2 5.94 -> 2.32, S4 4.43 -> 0.79.
- Longjump is NOT a separate stage: it is a 2-cycle helper (prefix opcode
  0xA0-0xBF + the jump instruction) that computes the jump target for loops
  whose offset exceeds the 5-bit immediate.  Its pj_result feeds the SAME
  pc_next mux in S3 (pc_next = lj ? pj_result : alu_c).  The prefix-cycle
  carry is REGISTERED (pj_carry5_r), so the two additions are PARALLEL from
  registers -- 2.32 ns, NOT chained (a chained model overestimates at 3.99 ns).
- WORST R2R STAGE = S3 Execute (3.86 ns): ALU CARRY4 chain + MUXF7.
- At 100 MHz every stage has >= 5.9 ns slack; the full pipeline's real
  bottleneck is NOT stage logic but BRAM clock-to-out (2.454 ns, see sec. 3).
- The pipeline can comfortably run 250+ MHz on internal logic alone;
  BRAM output registration (DOA_REG=1) is the path to >200 MHz end-to-end.

-------------------------------------------------------------------------------
3. FULL 4-STAGE PIPELINE WITH BRAM (bf2_pipeline_full)
-------------------------------------------------------------------------------
Complete pipeline: Fetch(IMEM) → Decode → Execute → Mem/WB(DMEM)
with Block RAM models for instruction and data memory.

SYNTHESIS RESULTS (rev 2: stack2 + corrected S2/S3 partition):
------------------
- WNS (Worst Negative Slack):     +6.445 ns  @ 100 MHz (10 ns period)
- MAX FREQUENCY:                  ~281 MHz   (3.555 ns period)
- TNS (Total Negative Slack):     0.000 ns   (no violations)
- WHS (Worst Hold Slack):         +0.143 ns  (clean)
- Critical warnings:              NONE (multi-driven nets fixed in rev 2)
- LUTs: 53, FFs: 137 (stack2 shift-register stack; consolidated WB regs)

CRITICAL PATH (Setup) - unchanged, BRAM clock-to-out dominated:
----------------------
Source:      dmem/mem_reg_0_1/CLKARDCLK  (BRAM clock)
Destination: mem_din_r_reg[1]/D           (pipeline register)
Path Delay:  3.404 ns (logic 2.604 ns + route 0.800 ns)
  - BRAM clock-to-out:  2.454 ns   <-- the real bottleneck

NON-MEMORY CRITICAL PATH (rev 2, corrected S3):
-----------------------------------------------
Source:      s2_alu_a_r_reg[1]/C
Destination: s3_maddr_next_r_reg[11]/D   (maddr_next = alu_c for '< >')
Path Delay:  3.150 ns  (ALU CARRY4 chain, registered in EX/MEM)

RESOURCE UTILIZATION (current run, bf2_pipeline_full_util.rpt):
---------------------
| Resource      | Used  | Available | Utilization |
|---------------|-------|-----------|-------------|
| LUTs          | 53    | 17,600    | <1%         |   (top: 53; s3_comb: 23)
| FFs           | 137   | 35,200    | <1%         |
| BRAM36 (36Kb) | 8     | 20        | 40%         |   (DMEM: 32K×8 = 256Kb → 8 BRAM36)
| BRAM18 (18Kb) | 1     | 40        | 2.5%        |   (IMEM: 8K×8 = 64Kb → 1 BRAM18)

(Note: an earlier run with the RAM-based bf2_stack showed ~150 LUTs / 110 FFs;
rev 2 with stack2 + corrected S2/S3 partition is the numbers above.)

-------------------------------------------------------------------------------
3b. 2-STAGE PIPELINE (FD | EX/WB) -- bf2_2stage_full
-------------------------------------------------------------------------------
Merges the 4-stage boundary: FD = S1 Fetch + S2 Decode (pc_r -> IMEM -> insn
-> decode -> FD/EX regs), EX/WB = S3 Execute + S4 Mem/WB (ALU + post-ALU +
long-jump + DMEM + stack2 -> architectural regs).  Reuses the same comb
modules (bf2_s2_decode_comb / bf2_s3_execute_comb / bf2_stack2).

MERGED-CLOUD R2R DELAYS (bf2_2stage_r2r.sv, 100 MHz):
| Cloud | Module          | R2R Path | WNS @100MHz | Notes                        |
|-------|-----------------|----------|-------------|------------------------------|
| FD    | bf2_fd_r2r      | 2.734 ns | +7.266 ns   | ~max(S1 2.61, S2 2.32), NOT  |
|       |                 |          |             | the sum 4.93 (paths disjoint)|
| EX/WB | bf2_exwb_r2r    | 4.102 ns | +5.898 ns   | S3 3.86 + LJ add + pc_next   |
|       |                 |          |             | mux merged into one cloud    |

FULL PIPELINE SYNTHESIS (rev 1):
------------------
- WNS: +5.293 ns @ 100 MHz (worst path 3.961 ns)  ->  MAX FREQ ~212 MHz
- WHS: +0.139 ns (clean); TNS 0
- LUTs: 54, FFs: 78  (vs 4-stage 53 LUTs / 137 FFs -- FFs HALVED: the
  IF/ID and EX/MEM register banks are gone; only FD/EX + arch regs remain)
- BRAM: same 8x RAMB36 + 1x RAMB18

CRITICAL PATH (Setup) -- NEW, ALU -> DMEM WRITE ADDR:
----------------------
Source:      ex_alu_a_reg[1]/C
Destination: dmem/mem_reg_0_0/ADDRARDADDR[11]  (BRAM write address input)
Path Delay:  3.961 ns (logic 2.051 + route 1.910);  CARRY4x3 + LUT2 + LUT3
  Cause: DMEM write uses the COMBINATIONAL EX address (ex_maddr_next); the
  BRAM write-addr input sits directly behind the ALU CARRY4 chain.  In the
  4-stage this address was registered (EX/MEM boundary), so this path did
  not exist there.

OTHER PATHS (from -max_paths 200):
  - 3.404 ns  dmem CLK -> mem_din_r            (BRAM ck->out, same as 4-stage)
  - 3.254 ns  imem dout_reg -> ex_insn_r       (IMEM ck->out + decode comb)
  - 3.498 ns  ex_pc -> pc_r                    (pc_next = pc+1 + jump muxes,
                                               includes the lj?pj_result mux)

LONG-JUMP PLACEMENT IN 2-STAGE (confirmed):
  - prefix-cycle decode (lj flag, lj_offset = pc[4:0]+insn[4:0]) in FD
  - lj / lj_offset / insn / pc cross FD/EX
  - pj_carry5_r / pj_pc_high_r update in EX/WB when ex_lj
  - jump-cycle target add (parallel from pj regs, 2.32 ns R2R) + the
    pc_next mux (pc_next = lj ? pj_result : alu_c) in EX/WB
  - its worst path (ex_pc -> pc_r via pj_result mux) is 3.498 ns -- off
    the critical path; the 2-cycle nature is orthogonal to pipeline depth

VERDICT for 100 MHz target: YES.  Both merged stages fit with >= 5.3 ns
slack; even 150 MHz (6.67 ns period) closes with ~2.7 ns margin.  Practical
ceiling ~150-160 MHz (vs ~281 MHz for the 4-stage).  Trade-off: -70 MHz
headroom for HALF the FFs (78 vs 137) and a single pipeline boundary
(simpler hazard handling: only one register bank between stages).

-------------------------------------------------------------------------------
4. COMPARISON: ORIGINAL BF1 (Single-Cycle) vs PIPELINED BF2
-------------------------------------------------------------------------------
| Metric                | BF1 (Original) | BF2 (Pipelined)  |
|-----------------------|----------------|------------------|
| Architecture          | Single-cycle   | 4-stage pipeline |
| Max Frequency (est.)  | ~100-120 MHz   | ~280 MHz         |
| CPI (ideal)           | 1              | 1 (steady state) |
| Branch penalty        | 2 cycles (LJ)  | 2 cycles (LJ)    |
| Memory                | Async (sim)    | BRAM (1-cycle)   |
| BRAM usage            | 0              | 9 (1×18K + 8×36K)|
| LUTs / FFs            | ~50            | 53 / 137         |

-------------------------------------------------------------------------------
5b. STACK2 COMPARISON (bf2_pipeline: bf2_stack RAM vs bf2_stack2 shift-register)
-------------------------------------------------------------------------------
| Metric                  | bf2_stack (RAM)     | bf2_stack2 (shift reg)  |
|-------------------------|---------------------|--------------------------|
| Storage                 | 2^DEPTH x WIDTH LUTRAM | DEPTH x WIDTH FFs     |
| Stack read path         | comb. RAM read mux  | registered (rd = head)   |
| "Stack -> PC next" path | 2.622 ns (in top 20) | GONE from top 20        |
| LUTs (full pipeline)    | ~150                | 53 (3x fewer)            |
| FFs  (full pipeline)    | 110                 | 137 (+27 shift reg)      |
| WNS @ 100 MHz           | +6.445 ns           | +6.445 ns (unchanged)    |
| Critical warnings       | multi-driven nets   | 0                        |

Stack2 verdict: YES, it helps.  The registered head output removes the
combinational stack-read mux from the critical path entirely and cuts LUT
usage ~3x (RAM stack -> FF shift register).  Overall max frequency is
UNCHANGED because the DMEM BRAM clock-to-out (2.454 ns) still dominates.

The pipeline restructure also fixed the decode/execute partition mistake
(mem_dout = alu_c[7:0] and maddr_next = alu_c for '< >' now computed in
S3 AFTER the ALU, not in S2) and eliminated the multi-driven net warnings.
The corrected S3 now shows a real ALU path: s2_alu_a_r -> s3_maddr_next_r
3.150 ns -- the next bottleneck after BRAM clock-to-out.

NEXT BOTTLENECK: BRAM output registration (DOA_REG=1) would cut the
2.454 ns clock-to-out to ~0.5 ns, unlocking >200 MHz.

-------------------------------------------------------------------------------
5. RECOMMENDATIONS FOR PRODUCTION PIPELINE
-------------------------------------------------------------------------------
1. FIX MULTI-DRIVEN NETS:
   - Add proper pipeline register isolation between stages
   - Use distinct signal names per stage (s1_insn, s2_insn, etc.)
   - Drive outputs only from final stage registers

2. IMPROVE BRAM TIMING:
   - Add output registers to BRAM (Vivado suggested this)
   - Use BRAM primitives with DOA_REG=1 for registered outputs
   - This reduces clock-to-out from 2.45 ns to ~0.5 ns

3. HAZARD HANDLING:
   - Data forwarding for ALU results (EX→EX, MEM→EX)
   - Load-use stall for DMEM reads (1 cycle)
   - Branch prediction or stall for long jumps (already 2-cycle)

4. TIMING CLOSURE AT 200+ MHz:
   - Current WNS 6.4 ns @ 100 MHz → can target 150-200 MHz easily
   - For >200 MHz: register BRAM outputs, retime CARRY4 chains
   - Consider splitting Stage 3 ALU into two cycles for >250 MHz

5. VERIFICATION:
   - Create testbench for full pipeline with BRAM
   - Verify hazard handling with directed tests
   - Compare BF2 output with BF1 golden model

-------------------------------------------------------------------------------
FILES GENERATED:
-------------------------------------------------------------------------------
- bf2.sv              : Registered stage modules (s1-s4, LJ, stack)  [archive_4stage/]
- timing/bf2_*_comb.sv: Combinational-only cores, one file per module
- timing/bf2_*_r2r.sv : R2R wrappers (comb core + input/output FFs)
- timing/bf2_pipeline_full.sv : Full 4-stage pipeline with BRAM models
- timing/bf2_bram_*.sv, timing/bf2_s1_fetch_with_imem.sv : pipeline BRAM/prefetch submodules
- bf2_2stage.sv       : Full 2-stage pipeline (FD | EX/WB) with BRAM models  [archive_4stage/]
- bf2_2stage_r2r.sv   : R2R wrappers for the merged FD / EX/WB clouds       [archive_4stage/]
- timing/synth_stage.tcl     : TCL script for registered stage synthesis
- timing/synth_comb.tcl      : TCL script for combinational stage synthesis
- timing/synth_r2r.tcl       : TCL script for register-to-register stage timing
- timing/synth_pipeline_full.tcl : TCL script for full pipeline synthesis
- synth_2stage_full.tcl   : TCL script for 2-stage pipeline synthesis         [archive_4stage/]
- synth_2stage_r2r.tcl    : TCL script for merged-cloud R2R timing            [archive_4stage/]

Timing reports in:
- synth_s*_comb/reports/timing_s*.rpt          (combinational)
- synth_s*_r2r/reports/timing_r2r_s*.rpt       (register-to-register)
- synth_s*/reports/timing_s*.rpt               (registered, needs fix; see 2b)
- bf2_pipeline_full_timing.rpt                 (full pipeline setup)
- bf2_pipeline_full_timing_summary.rpt         (full pipeline summary)
- bf2_pipeline_full_util.rpt                   (resource utilization)
- bf2_2stage_full_timing.rpt                    (2-stage pipeline setup)
- bf2_2stage_full_timing_summary.rpt            (2-stage pipeline summary)
- bf2_2stage_full_util.rpt                      (2-stage resource utilization)
- synth_2stage_r2r/reports/timing_r2r_*.rpt     (merged-cloud R2R: fd, exwb)

===============================================================================
END OF SUMMARY
===============================================================================