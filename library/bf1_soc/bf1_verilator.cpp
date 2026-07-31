// Verilator testbench for the bf1 core (SoC version).
//
// Ported from ~/repos/verilog/brainfuck_machine/verilog/bf1.cpp
// to the bf1.v used inside hdl/library/bf1_soc/bf1_soc.v.
//
// Changes vs. the original:
//   * drives the new inputs cpu_active (=1, run at full speed) and
//     ctrl_reset_i (=0)
//   * ',' can consume bytes from an optional input file (argv[2]);
//     without one io_din stays 0 (same as the original sim)
//   * io_rd / pc_debug are shown in verbose mode
//   * tape is 32K (DADDR_WIDTH) and code RAM 8K (CADDR_WIDTH) —
//     matching the sizes of the SoC BRAMs
//   * optional VCD trace with +trace
//
// Usage:
//   obj_dir/Vbf1 prog.bin [input.txt] [+verbose] [+trace] [+maxsteps=N]
//
// +maxsteps=N stops after N executed instructions — needed for programs
// that never fall off the end of the code (infinite loops; the board tool
// needs -n/--max-time for the same reason). Diagnostics go to stderr, so
// stdout is the pure program output.

#include <iostream>
#include <fstream>
#include <bitset>
#include <queue>
#include <cstdlib>
#include <cstring>

#include "Vbf1.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

#define CADDR_WIDTH 13
#define DADDR_WIDTH 15
#define DATA_WIDTH 8
#define STACK_DEPTH 4
#define MEMSIZE (1 << DADDR_WIDTH)   // 32K tape, matches SoC data RAM
#define CODESIZE (1 << CADDR_WIDTH)  // 8K code, matches SoC code RAM

using namespace std;

void print(Vbf1& top, int i) {
  if (top.clk) {
    // We set values before negative edge (we are so kind...)
    cout << "i=" << i
         << " insn=" << bitset<8>(top.insn)
         << " mem_din=" << bitset<DATA_WIDTH>(top.mem_din)
         << endl;
  } else {
    // CPU output is computed before positive edge
    cout << "    code_addr=" << bitset<CADDR_WIDTH>(top.code_addr)
         << " pc=" << bitset<CADDR_WIDTH>(top.pc_debug)
         << " mem_addr=" << bitset<DADDR_WIDTH>(top.mem_addr)
         << " rsp=" << bitset<STACK_DEPTH>(top._rsp)
         << " mem_wr=" << bitset<1>(top.mem_wr);
    if (top.mem_wr) {
      cout << " mem_dout=" << bitset<DATA_WIDTH>(top.mem_dout);
    }
    cout << endl;

    cout << "    io_wr=" << bitset<1>(top.io_wr)
         << " io_rd=" << bitset<1>(top.io_rd);
    if (top.io_wr) {
      cout << " io_dout=" << bitset<DATA_WIDTH>(top.io_dout)
           << " (" << (char)top.io_dout << ")";
    }
    cout << endl;
  }
}

char *code;
streampos prog_size;

unsigned char mem[MEMSIZE];
bool verbose = false;
unsigned long maxsteps = 0; // 0 = run until PC falls off the code

int main(int argc, char **argv, char **env) {
  int clk;
  if (argc <= 1) {
    cout << "Give me program name!" << endl;
    exit(1);
  }

  Verilated::commandArgs(argc, argv);
  const char *verboseParam = Verilated::commandArgsPlusMatch("verbose");
  verbose = verboseParam && verboseParam[0];
  if (verbose)
    cerr << "+verbose: per-cycle trace on stdout" << endl;

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
  // NB: commandArgsPlusMatch returns "" (never NULL) when there is no
  // match, so always check [0] — a bare pointer test is always truthy.
  const char* traceParam = Verilated::commandArgsPlusMatch("trace");
  if (traceParam && traceParam[0]) {
    tfp = new VerilatedVcdC;
  }

  // optional step limit for non-terminating programs
  // NB: commandArgsPlusMatch returns the matched arg including its leading
  // '+', so the value starts one past the prefix length.
  const char* maxstepsParam = Verilated::commandArgsPlusMatch("maxsteps=");
  if (maxstepsParam && maxstepsParam[0])
    maxsteps = strtoul(maxstepsParam + strlen("maxsteps=") + 1, NULL, 10);
  if (maxsteps)
    cerr << "+maxsteps: stopping after " << maxsteps << " instructions" << endl;

  // init top verilog instance
  Vbf1 top;
  if (tfp) {
    top.trace(tfp, 99);
    tfp->open("bf1.vcd");
    cerr << "+trace: writing waves to bf1.vcd (view with gtkwave bf1.vcd)" << endl;
  }

  ifstream prog;
  prog.open(argv[1], ios::in | ios::binary | ios::ate);
  if (prog.is_open()) {
    prog_size = prog.tellg();
    code = new char[prog_size];
    prog.seekg (0, ios::beg);
    prog.read (code, prog_size);
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
  top.resetq = 0;
  top.clk = 1;
  top.cpu_active = 1;    // run at full speed (no SoC stalls)
  top.ctrl_reset_i = 0;  // no PS-initiated resets
  top.eval();

  int code_addr = 0;
  int mem_addr = 0;
  vluint64_t t = 0;

  top.resetq = 1;
  unsigned long i = 0;
  do {
    // Write to CPU
    top.insn = code[code_addr];
    top.mem_din = mem[mem_addr];
    // present next input byte if the current instruction is ','
    top.io_din = ((top.insn >> 5) == 0x6) && !inq.empty() ? inq.front() : 0;
    if (verbose)
      print(top, i);
    // cout << " -- <NEGedge>" << endl;
    top.clk = 0;
    top.eval(); // negedge [here everything should be calculated]
    if (tfp) tfp->dump(t++);

    // Read from CPU
    // values need to be stable before posedge, so we read them here
    code_addr = top.code_addr;
    mem_addr = top.mem_addr;
    if (mem_addr < 0 || mem_addr >= MEMSIZE) {
      cerr << "i = " << i << endl;
      cerr << "Memory out of range " << mem_addr << endl;
      exit(2);
    }
    if (top.mem_wr)
      mem[mem_addr] = top.mem_dout;
    if (top.io_rd && !inq.empty())
      inq.pop(); // ',' consumed the presented byte
    if (top.io_wr)
      cout << (char)top.io_dout << flush;
    if (verbose)
      print(top, i);
    // cout << " -- <POSedge>" << endl;
    top.clk = 1;
    top.eval(); // posedge [outputs are available here]
    if (tfp) tfp->dump(t++);
    ++i;
    if (maxsteps && i >= maxsteps) {
      cerr << endl << "Max steps reached (" << maxsteps << ")." << endl;
      break;
    }
  } while (code_addr < prog_size && !Verilated::gotFinish());

  cerr << endl << "Executed " << i << " instructions." << endl;
  if (!inq.empty())
    cerr << "Unused input bytes: " << inq.size() << endl;

  if (tfp) {
    tfp->close();
    delete tfp;
  }

  delete[] code;
  exit(0);
}
