`timescale 1 ns / 1 ps
`default_nettype wire

// ============================================================================
// BF2 shared prelude
// ============================================================================
// Every BF2 source file starts with `include "common.h"` — this is where the
// timescale, default nettype, and the default parameter values live.
//
// Timescale: all modules use 1 ns / 1 ps.
// Nettype:   implicit nets default to `wire` (explicit declarations still
//            take precedence; bf2_soc.sv deliberately re-enables
//            `default_nettype none` for its strict port checking).
// ============================================================================

// Default parameter values shared by all BF2 modules.
`define CADDR_WIDTH 13   // CodeAddressWidth   (code / instruction address)
`define DADDR_WIDTH 15   // DataAddressWidth   (tape address)
`define DATA_WIDTH 8     // DataWidth          (byte width)
`define DEPTH 4          // Depth              (stack-pointer width in bits;
                        //                    capacity = 2^Depth entries)
