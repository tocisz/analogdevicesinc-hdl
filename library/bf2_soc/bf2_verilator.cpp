// Verilator testbench for the bf2_phase core (2-phase FD | EX/WB machine).
//
// Ported from bf1_verilator.cpp to drive the 2-phase bf2_phase_full module.
//
// Key differences from bf1:
//   * Alternates en_s12 / en_s34 enables (Phase A = fetch+decode+branch,
//     Phase B = execute+writeback).
//   * Outputs are only sampled/acted upon after a Phase B edge (en_s34).
//   * One instruction = two phases (A+B).  Per-cycle trace is printed at
//     phase boundaries.
//   * After reset deasserts, holds both enables low for ONE cycle to
//     perform the instruction prefetch (code_addr = pc_r = 0 -> IMEM latches
//     code_ram[0] for the first Phase A).
//   * Single synchronous active-high reset (reset), matching ARM ctrl_reset_i.
//
// Usage:
//   obj_dir/Vbf2_phase_full prog.bin [input.txt] [+verbose] [+trace] [+maxsteps=N]
//
// +maxsteps=N stops after N *instructions* (i.e. 2*N phases) — needed for
// programs that never fall off the end of the code (infinite loops).
// Diagnostics go to stderr, so stdout is the pure program output.

#include <iostream>
#include <fstream>
#include <bitset>
#include <queue>
#include <cstdlib>
#include <cstring>

#include "Vbf2_phase_full.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

#define CADDR_WIDTH 13
#define DADDR_WIDTH 15
#define DATA_WIDTH 8
#define DEPTH 4
#define MEMSIZE (1 << DADDR_WIDTH)   // 32K tape, matches SoC data RAM
#define CODESIZE (1 << CADDR_WIDTH)  // 8K code, matches SoC code RAM

using namespace std;

void print(Vbf2_phase_full& top, unsigned long phase, const char* phase_name) {
  cout << "phase=" << phase << " (" << phase_name << ")"
       << " insn=" << bitset<8>(top.insn)
       << " mem_din=" << bitset<DATA_WIDTH>(top.mem_din)
       << " io_din=" << bitset<DATA_WIDTH>(top.io_din)
       << endl;

  cout << "  code_addr=" << bitset<CADDR_WIDTH>(top.code_addr)
       << " pc=" << bitset<CADDR_WIDTH>(top.pc_debug)
       << " mem_addr=" << bitset<DADDR_WIDTH>(top.mem_addr)
       << " rsp=" << bitset<DEPTH>(top._rsp);

  if (top.mem_wr) {
    cout << " mem_wr=1 mem_dout=" << bitset<DATA_WIDTH>(top.mem_dout);
  } else {
    cout << " mem_wr=0";
  }
  cout << endl;

  cout << "  io_wr=" << bitset<1>(top.io_wr)
       << " io_rd=" << bitset<1>(top.io_rd);
  if (top.io_wr) {
    cout << " io_dout=" << bitset<DATA_WIDTH>(top.io_dout)
         << " (" << (char)top.io_dout << ")";
  }
  cout << endl;
}

char *code;
streampos prog_size;

unsigned char mem[MEMSIZE];
bool verbose = false;
unsigned long maxsteps = 0; // 0 = run until PC falls off the code

int main(int argc, char **argv, char **env) {
  if (argc <= 1) {
    cout << "Give me program name!" << endl;
    exit(1);
  }

  Verilated::commandArgs(argc, argv);
  const char *verboseParam = Verilated::commandArgsPlusMatch("verbose");
  verbose = verboseParam && verboseParam[0];
  if (verbose)
    cerr << "+verbose: per-phase trace on stdout" << endl;

  // Optional input bytes for ',' — argv[2] unless it's a plusarg
  queue<unsigned char> inq;
  if (argc > 2 && argv[2][0] != '+') {
    ifstream in(argv[2], ios::in | ios::binary | ios::ate);
    if (in.is_open()) {
      streampos sz = in.tellg();
      in.seekg(0, ios::beg);
      for (int n = 0; n < sz; n++)
        inq.push((unsigned char)in.get());
      in.close();
      cerr << "Input file \"" << argv[2] << "\" has " << sz << " bytes." << endl;
    } else {
      cerr << "Cannot open input file \"" << argv[2] << "\"" << endl;
      return 1;
    }
  }

  Verilated::traceEverOn(true);
  VerilatedVcdC* tfp = NULL;
  const char* traceParam = Verilated::commandArgsPlusMatch("trace");
  if (traceParam && traceParam[0]) {
    tfp = new VerilatedVcdC;
  }

  // optional step limit for non-terminating programs (counted in instructions)
  const char* maxstepsParam = Verilated::commandArgsPlusMatch("maxsteps=");
  if (maxstepsParam && maxstepsParam[0])
    maxsteps = strtoul(maxstepsParam + strlen("maxsteps=") + 1, NULL, 10);
  if (maxsteps)
    cerr << "+maxsteps: stopping after " << maxsteps << " instructions" << endl;

  // init top verilog instance (Vbf2_phase_full)
  Vbf2_phase_full top;
  if (tfp) {
    top.trace(tfp, 99);
    tfp->open("bf2_phase.vcd");
    cerr << "+trace: writing waves to bf2_phase.vcd (view with gtkwave bf2_phase.vcd)" << endl;
  }

  ifstream prog;
  prog.open(argv[1], ios::in | ios::binary | ios::ate);
  if (prog.is_open()) {
    prog_size = prog.tellg();
    code = new char[prog_size];
    prog.seekg(0, ios::beg);
    prog.read(code, prog_size);
    prog.close();
  } else {
    return 1;
  }

  cerr << "Program size is " << prog_size << endl;
  if (prog_size > CODESIZE) {
    cerr << "Program too large for the 8K code RAM!" << endl;
    return 1;
  }

  // initialize simulation inputs
  top.reset = 1;
  top.clk = 0;
  top.en_s12 = 0;
  top.en_s34 = 0;
  top.eval();

  int code_addr = 0;
  int mem_addr = 0;
  vluint64_t t = 0;

  // Assert reset for ONE cycle, then release.  Hold both enables low for
  // ONE cycle after reset releases to perform the instruction prefetch
  // (code_addr = pc_r = 0 -> registered IMEM output latches code_ram[0]
  // for the first Phase A).
  top.reset = 1;
  top.clk = 1;
  top.eval();
  if (tfp) tfp->dump(t++);
  top.clk = 0;
  top.eval();
  if (tfp) tfp->dump(t++);

  top.reset = 0;
  top.clk = 1;
  top.eval();
  if (tfp) tfp->dump(t++);
  top.clk = 0;
  top.eval();
  if (tfp) tfp->dump(t++);

  unsigned long phase = 0;        // phase count (A=even, B=odd)
  unsigned long instr_count = 0;  // instruction count (A+B pair = 1 instruction)
  bool en_s12 = true;             // start with Phase A (fetch+decode)

  do {
    // Alternate enables: even phases = A (en_s12), odd phases = B (en_s34)
    en_s12 = (phase % 2 == 0);
    bool en_s34 = !en_s12;

    top.en_s12 = en_s12 ? 1 : 0;
    top.en_s34 = en_s34 ? 1 : 0;

    // Write to CPU
    top.insn = code[code_addr];
    top.mem_din = mem[mem_addr];
    // present next input byte if the current instruction is ','
    top.io_din = ((top.insn >> 5) == 0x6) && !inq.empty() ? inq.front() : 0;

    if (verbose)
      print(top, phase, en_s12 ? "A(en_s12)" : "B(en_s34)");

    // Negative edge
    top.clk = 0;
    top.eval();
    if (tfp) tfp->dump(t++);

    // Read from CPU
    code_addr = top.code_addr;
    mem_addr = top.mem_addr;
    if (mem_addr < 0 || mem_addr >= MEMSIZE) {
      cerr << "phase = " << phase << endl;
      cerr << "Memory out of range " << mem_addr << endl;
      exit(2);
    }

    // Only act on outputs at Phase B edge (en_s34 == 1 during this phase)
    if (en_s34) {
      if (top.mem_wr)
        mem[mem_addr] = top.mem_dout;
      if (top.io_rd && !inq.empty())
        inq.pop(); // ',' consumed the presented byte
      if (top.io_wr)
        cout << (char)top.io_dout << flush;
    }

    if (verbose)
      print(top, phase, en_s12 ? "A(en_s12)" : "B(en_s34)");

    // Positive edge
    top.clk = 1;
    top.eval();
    if (tfp) tfp->dump(t++);

    // Instruction completes at the end of Phase B
    if (en_s34) {
      ++instr_count;
      if (maxsteps && instr_count >= maxsteps) {
        cerr << endl << "Max steps reached (" << maxsteps << ")." << endl;
        break;
      }
    }

    ++phase;
  } while (code_addr < prog_size && !Verilated::gotFinish());

  cerr << endl << "Executed " << instr_count << " instructions (" << phase << " phases)." << endl;
  if (!inq.empty())
    cerr << "Unused input bytes: " << inq.size() << endl;

  if (tfp) {
    tfp->close();
    delete tfp;
  }

  delete[] code;
  exit(0);
}