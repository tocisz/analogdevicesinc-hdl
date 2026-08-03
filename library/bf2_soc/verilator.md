Verilator simulation of the bf2 core
====================================

Fast C++ model of the `bf2_phase` CPU (hdl/library/bf2_soc/bf2_phase.sv, with
bf2_stack2.sv). Runs compiled brainfuck bytecode on the PC — no Vivado, no
FPGA needed. The model matches the core memory contract (registered IMEM /
DMEM), so identical bytecode behaves the same on the sim and on the board.

> History: this file was moved here from `bf1_soc/` (where it documented the
> bf1 core) when the BF2 pipeline experiments got their own directory. The
> content below now reflects the **bf2_phase** target. For the older bf1 core
> see `hdl/library/bf1_soc/Makefile` (`make verilator-build` / `Vbf1`).

1. Build the model (once, ~1 min)

   cd hdl/library/bf2_soc && make verilator2-build

   Top-level model binary: `obj_dir/Vbf2_phase`.

2. Compile a brainfuck program to bytecode (same compiler the board uses;
   the .bin lands where `-o` says)

   cd demos/brainfuck_org && python3 comp_bf.py src/hello.b -o bin/hello.bin

3. Run it

   cd hdl/library/bf2_soc && ./obj_dir/Vbf2_phase ../../../demos/brainfuck_org/bin/hello.bin

   Prints "Hello World!". stdout is the pure program output; diagnostics
   (program size, instruction count, cycle count) go to stderr.

Options
-------

   ./obj_dir/Vbf2_phase prog.bin in.txt
       feed ',' from a file (ghost.b needs interactive-style input;
       empty ',' → 0 in this TB, matching bf_interpret.py with /dev/null)
   ./obj_dir/Vbf2_phase prog.bin +maxsteps=1000000
       stop after N *retired instructions* — for programs that never fall
       off the end of the code (mandelbrot, ghost)
   ./obj_dir/Vbf2_phase prog.bin +verbose
       per-cycle CPU trace
   ./obj_dir/Vbf2_phase prog.bin +trace
       dump waves to bf2_phase.vcd (view in gtkwave)

Makefile shortcut and cleanup
-----------------------------

   make sim-verilator2 SIM_VER2_PROG=../../../demos/brainfuck_org/bin/hello.bin
       build (if needed) + run; add SIM_VER2_ARGS='+verbose' for a per-cycle
       trace, SIM_VER2_INPUT=in.txt for ',' programs
   make verilator2-clean
       remove obj_dir/ (also done by make sim-clean)

Notes
-----

- `bf2_phase` is an **overlapped FD | EX** machine: fetch+decode and execute
  run in the same cycle on consecutive instructions. A single `enable` port
  drives the pipe (1 = run, 0 = freeze for IO wait on the SoC).
  Internal bubbles: 1 cycle after `<>` when the next insn needs the new cell,
  and 1 cycle when EX push/pop races a looping `]`.
- Steady-state CPI is ~1.2–1.5 (was 2.0 with the old A/B mutex) → about
  1.35–1.7× throughput at the same clock. Byte-identical vs the old 2-phase
  on the demo suite.
- DMEM ports: `mem_rd_addr` / `mem_wr_addr` (simple dual-port). RAW bypass
  and EX→FD cell forward live in the core.
- Tape is 32K cells, code RAM 8K — same sizes as the SoC BRAMs.
- The compiler (demos/brainfuck_org/comp_bf.py) is the same one used on the
  board, so .bin files from demos/brainfuck_org/bin/ run directly.
- For timing/area analysis of the same source, the Makefile also has
  `synth-comb`, `synth-r2r`, and `synth-pipeline` targets (Vivado).
  The bf1 core's corresponding sim is in `hdl/library/bf1_soc/`.
