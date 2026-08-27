# axi_byte_fifo — byte-stream AXI-Lite ↔ AXIS FIFO (DEPTH=1024)

Replaces `axi_fifo_lite` / Xilinx `axi_fifo_mm_s` for the Z80 `term` path.
Byte = atomic value, no packets, no `TLAST/TLR/RLR` — see `doc/AXI_BYTE_FIFO_PLAN.md`
and `doc/Z80_FIFO_WEDGE_INVESTIGATION.md §5b`.

## When to use

* You need `PS (AXI-Lite @ 0x7C450000) ↔ PL (AXIS 8-bit per beat)` as
  `demos/z80_asm/z80_board/hw.py` + `axi_byte_fifo.ko` expect.
* `DEPTH=1024` bytes each direction, 80 MHz single clock.

Do **not** use for multi-word packets, `TDEST/TID/TUSER/TKEEP`, or PG080
thresholds/IRQs/ECC.

## Interface

Same as `axi_fifo_mm_s` as instantiated in `hdl/projects/ebaz4205/system_bd.tcl`,
but `TDATA` is **8-bit** per direction and `TLAST` is deleted:

* `s_axi_aclk`, `s_axi_aresetn`, `s_axi_awaddr/awvalid/awready/wdata/wstrb/wvalid/wready/bresp/bvalid/bready/araddr/arvalid/arready/rdata/rresp/rvalid/rready`
* `axi_str_txd_tvalid/tready/tdata[7:0]` (M_AXIS, PS→PL)
* `axi_str_rxd_tvalid/tready/tdata[7:0]` (S_AXIS, PL→PS)
* `mm2s/s2mm_prmry_reset_out_n`, `interrupt` (=0)

Base address stays `0x7C450000`; instance will become `axi_byte_fifo_0`,
DT `compatible="xlnx,axi-byte-fifo-1.0"`, device `/dev/axi_byte_fifo_0x7c450000`.

## Register map (offsets from base)

| Off | Name | Access | Notes |
|-----|------|--------|-------|
| 0x00 | ISR  | RO/W1C | Idle `0x01D00000`, after `SRR` `0x01D80000` (`TRC|RRC`). No real IRQ; `W1C` clears. |
| 0x04 | IER  | RW     | Stored, not decoded (`interrupt` stays 0). |
| 0x08 | TDFR | WO     | `0xA5` resets TX path. |
| 0x0C | TDFV | RO     | `1024 - tx_cnt` bytes free (correct `0x400` after reset). |
| 0x10 | TDFD | WO     | Push **one byte** `wdata[7:0]` → TX FIFO (no `TLR` commit). |
| 0x14 | TLR  | — | **Deleted** — reads `0`, writes ignored (kept for compat). |
| 0x18 | RDFR | WO     | `0xA5` resets RX path. |
| 0x1C | RDFO | RO     | `rx_cnt` bytes occupied. |
| 0x20 | RDFD | RO     | Pop **one byte** → `rdata[7:0]` (`rdata[31:8]=0`), `rx_cnt--`. |
| 0x24 | RLR  | — | **Deleted** — reads `0` (was `4`). |
| 0x28 | SRR  | WO     | `0xA5` resets both sides. |

All other PG080 offsets return `0`.

## Limitations vs PG080 `axi_fifo_mm_s v4.3`

| Feature | Xilinx | `axi_byte_fifo` | Impact |
|---------|--------|-----------------|--------|
| `C_TX/RX_FIFO_DEPTH` | 16..32768 | **Fixed 1024 bytes** | Change SV if needed. |
| `C_USE_TX_CTRL`, `C_DATA_INTERFACE_TYPE` | yes | **no** | Only byte-stream. |
| `C_USE_RX/TX_CUT_THROUGH` | 0/1 | **n/a** (always forward) | Wedge fixed. |
| `TDEST/TID/TUSER/TKEEP/TSR/TLAST/TLR/RLR` | yes | **no** | One byte = one beat. |
| Multi-word packets | yes | **no** | — |
| Prog thresholds `TFPF/TFPE/RFPF/RFPE` | cfg | **no** | — |
| Interrupts `RC/TC/...` | IRQ | **none** (`interrupt=0`) | Driver polls; `term` drains via `read_available`. |
| ECC / CDC | optional | **no** | Single `s_axi_aclk` 80 MHz. |
| `TDFV` reset | `0x3FC` (bug) | **`0x400`** | Correct. |

## History

* `axi_fifo_lite` (v1 drop-24) fixed the 1.9k-packet wedge (`use_behav BYTES=2300/10000 PASS`)
  but still wasted 75% BRAM (`32b×1024` with 24b dropped) and required Python `drop-24` shim.
* `axi_byte_fifo` (this) saves 75% BRAM (`8b×1024`) and deletes the shim.
