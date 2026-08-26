# axi_fifo_lite — light AXI-Lite ↔ AXIS byte-stream FIFO

Drop-in replacement for Xilinx `axi_fifo_mm_s` for the Z80 `term` path.
Fixes the 1.9k-packet wedge/phantom described in
`doc/Z80_FIFO_WEDGE_INVESTIGATION.md` §5b (TLAST=1 per word, 1024 depth).

## When to use

* You need `PS (AXI-Lite at 0x7C450000) ↔ PL (AXIS 32b word per byte, TLAST=1 per word)` as `demos/z80_asm/z80_board/hw.py` + `axis_fifo.ko` expect.
* Packets are **single-word** (`TLR=4*N`, `RLR=4`). `axis_byte_bridge` v1 does this.
* Depth 1024 each direction is enough; 80 MHz, single clock.

Do **not** use for multi-word packets, `TDEST/TID/TUSER/TKEEP`, bursts without `TLR`, or where you need Xilinx PG080 thresholds/IRQs/ECC.

## Interface

Same as `axi_fifo_mm_s` as instantiated in `hdl/projects/ebaz4205/system_bd.tcl`:

* `s_axi_aclk`, `s_axi_aresetn`, `s_axi_awaddr/awvalid/awready/wdata/wstrb/wvalid/wready/bresp/bvalid/bready/araddr/arvalid/arready/rdata/rresp/rvalid/rready` (32-bit, 7-bit addr)
* `axi_str_txd_tvalid/tready/tdata/tlast` (M_AXIS, PS→PL keystrokes)
* `axi_str_rxd_tvalid/tready/tdata/tlast` (S_AXIS, PL→PS guest output)
* `mm2s/s2mm_prmry_reset_out_n`, `interrupt` (=0)

Base address and instance name stay `0x7C450000` / `axi_fifo_mm_s_0` so the DT `compatible="xlnx,axi-fifo-mm-s-4.1"` and the `axis_fifo` staging driver need no change.

## Register map (offsets from base)

| Off | Name | Access | Notes |
|-----|------|--------|-------|
| 0x00 | ISR  | RO/W1C | Idle `0x01D00000`, after `SRR` `0x01D80000` (`TRC|RRC`). No real IRQ sources; `W1C` clears bits. |
| 0x04 | IER  | RW     | Stored, not decoded (`interrupt` stays 0). |
| 0x08 | TDFR | WO     | `0xA5` resets TX path (clears `tx_cnt`, `tx_pending`). |
| 0x0C | TDFV | RO     | `1024 - tx_cnt` (vacancy). Correct `0x400` after reset (Xilinx IP stuck at `0x3FC`). |
| 0x10 | TDFD | WO     | Push word to TX pending (128-deep coalesce). |
| 0x14 | TLR  | WO     | Commit pending: `tx_cnt += N`, `N = pending`. Expects `4*N`. |
| 0x18 | RDFR | WO     | `0xA5` resets RX path. |
| 0x1C | RDFO | RO     | `rx_cnt` (occupancy). |
| 0x20 | RDFD | RO     | Pop word: `rx_cnt--`, `rx_len_cnt--`. Returns 0 if empty. |
| 0x24 | RLR  | RO     | `4` if `rx_len_cnt>0` else `0`. |
| 0x28 | SRR  | WO     | `0xA5` resets both sides. |

All other PG080 registers/offsets return `0`.

## Limitations vs PG080 `axi_fifo_mm_s v4.3`

| Feature | Xilinx | Lite | Impact |
|---------|--------|------|--------|
| Depths `C_TX/RX_FIFO_DEPTH` | 16..32768 | **Fixed 1024** | Change SV if needed. |
| `C_USE_TX_CTRL`, `C_DATA_INTERFACE_TYPE` | yes | **no** | Only byte-stream tested. |
| `C_USE_RX/TX_CUT_THROUGH` | 0/1 | **n/a** (always forward) | No store-and-forward commit; wedge fixed. |
| `TDEST/TID/TUSER/TKEEP/TSR` | yes | **no** | Bridge drops upper 24b, `TLAST=1` always. |
| Multi-word packets | yes | **1 word = 1 packet** | `TLR` must be `4*N`, `RLR==4`. |
| Pending coalesce | FWFT | **128-word** pending before `TLR` | Host writes `1+TLR=4` per keystroke, safe. |
| Prog thresholds `TFPF/TFPE/RFPF/RFPE` | cfg | **no** | `ISR` threshold bits not generated. |
| Interrupts `RC/TC/RPURE/...` | IRQ | **none** (`interrupt=0`, `ISR` idle) | Driver polling still works; blocking `RC/TC` wakeups become 1s timeout. Non-blocking `term` unaffected. |
| ECC | optional | **no** | — |
| CDC (2 clocks) | optional | **single** `s_axi_aclk` | System uses one 80 MHz clock. |
| AXI burst / `WSTRB` | yes | **single-beat, `4'hF` only** | Host driver always `4'hF`. |
| `TDFV` reset value | `0x3FC` (observed, bug) | **`0x400`** | Correct. |

If you need any of the right-hand “no” features, keep the Xilinx IP or extend this file. For the Z80 term path it is a faithful subset and is **proven** in xsim: `USE_BEHAV=1` `BYTES=2300/10000 PASS` where the Xilinx IP wedges at 1917.

## Revert

In `system_bd.tcl` comment the `ad_ip_instance axi_fifo_lite` line and restore:

```tcl
ad_ip_instance axi_fifo_mm_s axi_fifo_mm_s_0
ad_ip_parameter axi_fifo_mm_s_0 CONFIG.C_TX_FIFO_DEPTH 1024 ...
```

No driver or `hw.py` change needed.
