Verilator simulation of the bf2 core
====================================

Fast C++ model of the `bf2_phase` CPU (hdl/library/bf2_soc/bf2_phase.sv, with
bf2_comb.sv and bf2_stack2.sv). Runs compiled brainfuck bytecode on the PC —
no Vivado, no FPGA needed. The model matches the core, so identical bytecode
behaves the same on the sim and on the board.

> History: this file was moved here from `bf1_soc/` (where it documented the
> bf1 core) when the BF2 pipeline experiments got their own directory. The
> content below now reflects the **bf2_phase** target. For the older bf1 core
> see `hdl/library/bf1_soc/Makefile` (`make verilator-build` / `Vbf1`).

1. Build the model (once, ~1 min)

   cd hdl/library/bf2_soc && make verilator2-build

   Top-level model binary: `obj_dir/Vbf2_phase_full`.

2. Compile a brainfuck program to bytecode (same compiler the board uses;
   the .bin lands where `-o` says)

   cd demos/brainfuck_org && python3 comp_bf.py src/hello.b -o bin/hello.bin

3. Run it

   cd hdl/library/bf2_soc && ./obj_dir/Vbf2_phase_full ../../../demos/brainfuck_org/bin/hello.bin

   Prints "Hello World!". stdout is the pure program output; diagnostics
   (program size, instruction count) go to stderr.

Options
-------

   cd hdl/library/bf2_soc && ./obj_dir/Vbf2_phase_full ../../../demos/brainfuck_org/bin/hello.bin in.txt
       feed ',' from a file (ghost.b, xmastree.b)
   cd hdl/library/bf2_soc && ./obj_dir/Vbf2_phase_full ../../../demos/brainfuck_org/bin/hello.bin +maxsteps=1000000
       stop after N *instructions* (1 instruction = 2 phases) — for programs
       that never fall off the end of the code (equivalent of -n / --max-time)
   cd hdl/library/bf2_soc && ./obj_dir/Vbf2_phase_full ../../../demos/brainfuck_org/bin/hello.bin +verbose
       per-phase CPU trace
   cd hdl/library/bf2_soc && ./obj_dir/Vbf2_phase_full ../../../demos/brainfuck_org/bin/hello.bin +trace
       dump waves to bf2_phase.vcd (view in gtkwave)

Makefile shortcut and cleanup
-----------------------------

   cd hdl/library/bf2_soc && make sim-verilator2 SIM_VER2_PROG=../../../demos/brainfuck_org/bin/hello.bin
       build (if needed) + run; add SIM_VER2_ARGS='+verbose' for a per-phase trace,
       SIM_VER2_INPUT=in.txt for ',' programs
   cd hdl/library/bf2_soc && make verilator2-clean
       remove obj_dir/ (also done by make sim-clean)

Notes
-----

- `bf2_phase` is a 2-phase machine: it alternates `en_s12` / `en_s34`.
  Phase A (en_s12) = fetch + decode + branch; Phase B (en_s34) = execute +
  writeback. One instruction = one A+B pair (2 phases).
- Tape is 32K cells, code RAM 8K — same sizes as the SoC BRAMs.
- The compiler (demos/brainfuck_org/comp_bf.py) is the same one used on the
  board, so .bin files from demos/brainfuck_org/bin/ run directly.
- Programs that never halt need +maxsteps (N counts instructions = 2*N phases),
  or pipe stdout through head -c.
- For timing/area analysis of the same source, the Makefile also has
  `synth-comb`, `synth-r2r`, and `synth-pipeline` targets (Vivado).
  The bf1 core's corresponding sim is in `hdl/library/bf1_soc/`.
