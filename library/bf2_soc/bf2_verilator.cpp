// Verilator testbench for the bf2_phase core (overlapped FD | EX machine).
//
// Models the SoC memory contract:
//   * Registered IMEM: insn presented this cycle is code[code_addr] latched
//     at the previous posedge (1-cycle latency).
//   * Registered DMEM read on a read-only port (read-first vs a same-cycle
//     store on the write port). RAW bypass lives inside the core.
//   * `enable` high to run, low to freeze (the SoC drops it on IO wait).
//
// Usage:
//   obj_dir/Vbf2_phase prog.bin [input.txt] [+verbose] [+trace] [+maxsteps=N]
//
// +maxsteps=N stops after N *retired instructions*.
// Diagnostics go to stderr; stdout is pure program output.

#include <iostream>
#include <fstream>
#include <bitset>
#include <queue>
#include <cstdlib>
#include <cstring>

#include "Vbf2_phase.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

#define CADDR_WIDTH 13
#define DADDR_WIDTH 15
#define DATA_WIDTH 8
#define DEPTH 4
#define MEMSIZE (1 << DADDR_WIDTH)
#define CODESIZE (1 << CADDR_WIDTH)

using namespace std;

void print(Vbf2_phase& top, unsigned long cycle) {
  cout << "cycle=" << cycle
       << " insn=" << bitset<8>(top.insn)
       << " mem_din=" << bitset<DATA_WIDTH>(top.mem_din)
       << " io_din=" << bitset<DATA_WIDTH>(top.io_din)
       << endl;

  cout << "  code_addr=" << bitset<CADDR_WIDTH>(top.code_addr)
       << " pc=" << bitset<CADDR_WIDTH>(top.pc_debug)
       << " mem_rd=" << bitset<DADDR_WIDTH>(top.mem_rd_addr)
       << " mem_wr_addr=" << bitset<DADDR_WIDTH>(top.mem_wr_addr)
       << " rsp=" << bitset<DEPTH>(top._rsp);

  if (top.mem_wr)
    cout << " mem_wr=1 mem_dout=" << bitset<DATA_WIDTH>(top.mem_dout);
  else
    cout << " mem_wr=0";
  cout << endl;

  cout << "  io_wr=" << bitset<1>(top.io_wr)
       << " io_rd=" << bitset<1>(top.io_rd)
       << " retiring=" << bitset<1>(top.retiring)
       << " rd_pend=" << bitset<1>(top.io_rd_pending)
       << " wr_pend=" << bitset<1>(top.io_wr_pending);
  if (top.io_wr)
    cout << " io_dout=" << bitset<DATA_WIDTH>(top.io_dout)
         << " (" << (char)top.io_dout << ")";
  cout << endl;
}

char *code;
streampos prog_size;
unsigned char mem[MEMSIZE];
bool verbose = false;
unsigned long maxsteps = 0;

static unsigned char code_at(int addr) {
  if (addr < 0 || addr >= (int)prog_size)
    return 0;
  return (unsigned char)code[addr];
}

int main(int argc, char **argv, char **env) {
  if (argc <= 1) {
    cout << "Give me program name!" << endl;
    exit(1);
  }

  Verilated::commandArgs(argc, argv);
  const char *verboseParam = Verilated::commandArgsPlusMatch("verbose");
  verbose = verboseParam && verboseParam[0];
  if (verbose)
    cerr << "+verbose: per-cycle trace on stdout" << endl;

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

  const char* maxstepsParam = Verilated::commandArgsPlusMatch("maxsteps=");
  if (maxstepsParam && maxstepsParam[0])
    maxsteps = strtoul(maxstepsParam + strlen("maxsteps=") + 1, NULL, 10);
  if (maxsteps)
    cerr << "+maxsteps: stopping after " << maxsteps << " instructions" << endl;

  Vbf2_phase top;
  if (tfp) {
    top.trace(tfp, 99);
    tfp->open("bf2_phase.vcd");
    cerr << "+trace: writing waves to bf2_phase.vcd" << endl;
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

  memset(mem, 0, sizeof(mem));

  top.reset = 1;
  top.clk = 0;
  top.enable = 0;
  top.insn = 0;
  top.mem_din = 0;
  top.io_din = 0;
  top.eval();

  vluint64_t t = 0;
  auto half = [&](int clk) {
    top.clk = clk;
    top.eval();
    if (tfp) tfp->dump(t++);
  };

  // Reset pulse (posedge while reset=1)
  half(1);
  half(0);

  // Release reset; idle one cycle with enable low so IMEM latches code[0]
  top.reset = 0;
  top.enable = 0;
  top.insn = 0;
  top.mem_din = 0;
  half(1);
  // Registered memories sample at this posedge: code_addr should be 0
  unsigned char insn_r = code_at((int)top.code_addr);
  unsigned char mem_din_r = 0; // mem all zeros
  half(0);

  unsigned long cycle = 0;
  unsigned long instr_count = 0;
  int drain = 0;
  const int drain_limit = 4;

  do {
    // In a standalone TB without a UART feeding bytes, a `,` with an empty
    // input queue gets 0 (same as bf_interpret.py with /dev/null stdin).
    // Do NOT freeze; the SoC-only IO-stall is for the actual hardware where
    // the PS must feed data before the CPU can proceed.
    bool io_stall = false;
    top.enable = 1;

    top.insn = insn_r;
    top.mem_din = mem_din_r;
    top.io_din = (top.io_rd_pending && !inq.empty()) ? inq.front() : 0;
    top.eval(); // settle comb with new enables/inputs

    if (verbose)
      print(top, cycle);

    int code_addr = (int)top.code_addr;
    int mem_rd = (int)top.mem_rd_addr;
    int mem_wa = (int)top.mem_wr_addr;

    if (mem_rd < 0 || mem_rd >= MEMSIZE || mem_wa < 0 || mem_wa >= MEMSIZE) {
      cerr << "cycle = " << cycle << " Memory out of range rd=" << mem_rd
           << " wr=" << mem_wa << endl;
      exit(2);
    }

    // Read-first sample for the read port (before applying the store).
    unsigned char rd_sample = mem[mem_rd];

    if (top.mem_wr)
      mem[mem_wa] = (unsigned char)top.mem_dout;
    if (top.io_rd && !inq.empty())
      inq.pop();
    if (top.io_wr)
      cout << (char)top.io_dout << flush;

    if (top.retiring) {
      ++instr_count;
      if (maxsteps && instr_count >= maxsteps) {
        cerr << endl << "Max steps reached (" << maxsteps << ")." << endl;
        // still finish the clock so state is consistent
      }
    }

    // Posedge: core registers + BRAM output registers
    half(1);
    insn_r = code_at(code_addr);
    mem_din_r = rd_sample;
    half(0);

    ++cycle;

    if (maxsteps && instr_count >= maxsteps)
      break;

    if ((int)top.pc_debug >= (int)prog_size)
      ++drain;
    else
      drain = 0;

  } while (drain < drain_limit && !Verilated::gotFinish());

  cerr << endl << "Executed " << instr_count << " instructions ("
       << cycle << " cycles)." << endl;
  if (!inq.empty())
    cerr << "Unused input bytes: " << inq.size() << endl;

  if (tfp) {
    tfp->close();
    delete tfp;
  }

  delete[] code;
  exit(0);
}
