Verilator simulation of the bf1 core
====================================

Fast C++ model of the bf1 CPU (hdl/library/bf1_soc/bf1.v). Runs compiled
brainfuck bytecode on the PC — no Vivado, no FPGA needed. The model is
bit-exact with the core: the same bytecode behaves identically on the sim
and on the board.

1. Build the model (once, ~1 min)

   cd hdl/library/bf1_soc && make verilator-build

2. Compile a brainfuck program to bf1 bytecode (same compiler the board
   uses; the .bin lands next to the source)

   cd demos/brainfuck_org && python3 comp_bf.py src/hello.b -o bin/hello.bin

3. Run it

   cd hdl/library/bf1_soc && ./obj_dir/Vbf1 ../../../demos/brainfuck_org/bin/hello.bin

   Prints "Hello World!". stdout is the pure program output; diagnostics
   (program size, instruction count) go to stderr.

Options
-------

   cd hdl/library/bf1_soc && ./obj_dir/Vbf1 ../../../demos/brainfuck_org/bin/hello.bin in.txt
       feed ',' from a file (ghost.b, xmastree.b)
   cd hdl/library/bf1_soc && ./obj_dir/Vbf1 ../../../demos/brainfuck_org/bin/hello.bin +maxsteps=1000000
       stop after N instructions — for programs that never fall off the end
       of the code (equivalent of the board tool's -n / --max-time)
   cd hdl/library/bf1_soc && ./obj_dir/Vbf1 ../../../demos/brainfuck_org/bin/hello.bin +trace
       dump waves to bf1.vcd (view in gtkwave)
   cd hdl/library/bf1_soc && ./obj_dir/Vbf1 ../../../demos/brainfuck_org/bin/hello.bin +verbose
       per-cycle CPU trace

Makefile shortcut and cleanup
-----------------------------

   cd hdl/library/bf1_soc && make sim-verilator SIM_VER_PROG=../../../demos/brainfuck_org/src/hello.bin
       build (if needed) + run (stdout = pure program output; add +verbose
       in SIM_VER_ARGS for a per-cycle trace)
   cd hdl/library/bf1_soc && make verilator-clean
       remove obj_dir/ (also done by make sim-clean)

Notes
-----

- Tape is 32K cells, code RAM 8K — same sizes as the SoC BRAMs.
- The compiler (demos/brainfuck_org/comp_bf.py) is the same one used on the
  board, so .bin files from demos/brainfuck_org/bin/ run directly.
- Programs that never halt need +maxsteps, or pipe stdout through head -c
  (e.g. sierpinski.b output matched the board capture byte-for-byte).
