###############################################################################
## Copyright (C) 2014-2024 Analog Devices, Inc. All rights reserved.
## Copyright (C) 2025 Mateusz Nalewajski. All rights reserved.
### SPDX short identifier: ADIBSD
###############################################################################

## This file is based on "pluto" project from Analog Devices
## reference HDL repository.

# default ports

create_bd_intf_port -mode Master -vlnv xilinx.com:interface:ddrx_rtl:1.0 ddr
create_bd_intf_port -mode Master -vlnv xilinx.com:display_processing_system7:fixedio_rtl:1.0 fixed_io

create_bd_intf_port -mode Master -vlnv xilinx.com:interface:mdio_rtl:1.0 MDIO_PHY
create_bd_intf_port -mode Master -vlnv xilinx.com:interface:gmii_rtl:1.0 GMII

create_bd_intf_port -mode Master -vlnv xilinx.com:interface:uart_rtl:1.0 UART_0

create_bd_port -dir I -from 12 -to 0 gpio_i
create_bd_port -dir O -from 12 -to 0 gpio_o
create_bd_port -dir O -from 12 -to 0 gpio_t

create_bd_port -dir O ttc0_wave0_out
create_bd_port -dir O ttc0_wave1_out

create_bd_port -dir O lcd_scl
create_bd_port -dir O lcd_sda

create_bd_port -dir O hdmi_clk
create_bd_port -dir O hdmi_d0
create_bd_port -dir O hdmi_d1
create_bd_port -dir O hdmi_d2

create_bd_port -dir I ext_clk_50m

# instance: sys_ps7

ad_ip_instance processing_system7 sys_ps7

# ps7 settings

ad_ip_parameter sys_ps7 CONFIG.PCW_PRESET_BANK0_VOLTAGE {LVCMOS 3.3V}
ad_ip_parameter sys_ps7 CONFIG.PCW_PRESET_BANK1_VOLTAGE {LVCMOS 3.3V}

ad_ip_parameter sys_ps7 CONFIG.PCW_PACKAGE_NAME {clg400}

ad_ip_parameter sys_ps7 CONFIG.PCW_GPIO_MIO_GPIO_ENABLE 1

ad_ip_parameter sys_ps7 CONFIG.PCW_GPIO_EMIO_GPIO_ENABLE 1
ad_ip_parameter sys_ps7 CONFIG.PCW_GPIO_EMIO_GPIO_IO 13

ad_ip_parameter sys_ps7 CONFIG.PCW_ENET0_PERIPHERAL_ENABLE 1
ad_ip_parameter sys_ps7 CONFIG.PCW_ENET0_ENET0_IO {EMIO}
ad_ip_parameter sys_ps7 CONFIG.PCW_ENET0_GRP_MDIO_ENABLE 1
ad_ip_parameter sys_ps7 CONFIG.PCW_ENET0_GRP_MDIO_IO {EMIO}
ad_ip_parameter sys_ps7 CONFIG.PCW_ENET0_PERIPHERAL_CLKSRC {External}
ad_ip_parameter sys_ps7 CONFIG.PCW_ENET0_PERIPHERAL_DIVISOR0 1
ad_ip_parameter sys_ps7 CONFIG.PCW_ENET0_PERIPHERAL_DIVISOR1 5
ad_ip_parameter sys_ps7 CONFIG.PCW_ENET0_PERIPHERAL_FREQMHZ {100 Mbps}
ad_ip_parameter sys_ps7 CONFIG.PCW_ENET0_RESET_ENABLE 0

ad_ip_parameter sys_ps7 CONFIG.PCW_ENET1_PERIPHERAL_ENABLE 0

ad_ip_parameter sys_ps7 CONFIG.PCW_EN_CLK0_PORT 1
ad_ip_parameter sys_ps7 CONFIG.PCW_EN_RST0_PORT 1

ad_ip_parameter sys_ps7 CONFIG.PCW_EN_CLK1_PORT 0
ad_ip_parameter sys_ps7 CONFIG.PCW_EN_RST1_PORT 0

ad_ip_parameter sys_ps7 CONFIG.PCW_EN_CLK2_PORT 0
ad_ip_parameter sys_ps7 CONFIG.PCW_EN_CLK3_PORT 0

ad_ip_parameter sys_ps7 CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ 100.0
ad_ip_parameter sys_ps7 CONFIG.PCW_FPGA1_PERIPHERAL_FREQMHZ 25.0

ad_ip_parameter sys_ps7 CONFIG.PCW_NAND_PERIPHERAL_ENABLE 1
ad_ip_parameter sys_ps7 CONFIG.PCW_NAND_GRP_D8_ENABLE 0
ad_ip_parameter sys_ps7 CONFIG.PCW_NAND_NAND_IO {MIO 0 2.. 14}

ad_ip_parameter sys_ps7 CONFIG.PCW_NOR_PERIPHERAL_ENABLE 0

ad_ip_parameter sys_ps7 CONFIG.PCW_QSPI_PERIPHERAL_ENABLE 0

ad_ip_parameter sys_ps7 CONFIG.PCW_SD0_PERIPHERAL_ENABLE 1
ad_ip_parameter sys_ps7 CONFIG.PCW_SD0_GRP_CD_ENABLE 0
ad_ip_parameter sys_ps7 CONFIG.PCW_SD0_GRP_POW_ENABLE 0
ad_ip_parameter sys_ps7 CONFIG.PCW_SD0_GRP_WP_ENABLE 0
ad_ip_parameter sys_ps7 CONFIG.PCW_SD0_SD0_IO {MIO 40 .. 45}

ad_ip_parameter sys_ps7 CONFIG.PCW_SDIO_PERIPHERAL_FREQMHZ 100.0
ad_ip_parameter sys_ps7 CONFIG.PCW_SDIO_PERIPHERAL_VALID 1

ad_ip_parameter sys_ps7 CONFIG.PCW_UART0_PERIPHERAL_ENABLE 1
ad_ip_parameter sys_ps7 CONFIG.PCW_UART0_GRP_FULL_ENABLE 0
ad_ip_parameter sys_ps7 CONFIG.PCW_UART0_UART0_IO {EMIO}

ad_ip_parameter sys_ps7 CONFIG.PCW_UART1_PERIPHERAL_ENABLE 1
ad_ip_parameter sys_ps7 CONFIG.PCW_UART1_GRP_FULL_ENABLE 0
ad_ip_parameter sys_ps7 CONFIG.PCW_UART1_UART1_IO {MIO 24 .. 25}

ad_ip_parameter sys_ps7 CONFIG.PCW_I2C_RESET_ENABLE 0

ad_ip_parameter sys_ps7 CONFIG.PCW_I2C0_PERIPHERAL_ENABLE 0
ad_ip_parameter sys_ps7 CONFIG.PCW_I2C0_RESET_ENABLE 0

ad_ip_parameter sys_ps7 CONFIG.PCW_I2C1_PERIPHERAL_ENABLE 0
ad_ip_parameter sys_ps7 CONFIG.PCW_I2C1_RESET_ENABLE 0

ad_ip_parameter sys_ps7 CONFIG.PCW_SPI0_PERIPHERAL_ENABLE 1
ad_ip_parameter sys_ps7 CONFIG.PCW_SPI0_SPI0_IO {EMIO}

ad_ip_parameter sys_ps7 CONFIG.PCW_SPI1_PERIPHERAL_ENABLE 0

ad_ip_parameter sys_ps7 CONFIG.PCW_TTC0_PERIPHERAL_ENABLE 1
ad_ip_parameter sys_ps7 CONFIG.PCW_TTC0_TTC0_IO {EMIO}

ad_ip_parameter sys_ps7 CONFIG.PCW_USB_RESET_ENABLE 0

ad_ip_parameter sys_ps7 CONFIG.PCW_USB0_PERIPHERAL_ENABLE 0
ad_ip_parameter sys_ps7 CONFIG.PCW_USB0_RESET_ENABLE 0

ad_ip_parameter sys_ps7 CONFIG.PCW_USB1_PERIPHERAL_ENABLE 0
ad_ip_parameter sys_ps7 CONFIG.PCW_USB1_RESET_ENABLE 0

ad_ip_parameter sys_ps7 CONFIG.PCW_USE_FABRIC_INTERRUPT 1
ad_ip_parameter sys_ps7 CONFIG.PCW_IRQ_F2P_INTR 1
ad_ip_parameter sys_ps7 CONFIG.PCW_IRQ_F2P_MODE REVERSE

ad_ip_parameter sys_ps7 CONFIG.PCW_MIO_0_PULLUP  {enabled}
ad_ip_parameter sys_ps7 CONFIG.PCW_MIO_9_PULLUP  {enabled}
ad_ip_parameter sys_ps7 CONFIG.PCW_MIO_10_PULLUP {enabled}
ad_ip_parameter sys_ps7 CONFIG.PCW_MIO_11_PULLUP {enabled}
ad_ip_parameter sys_ps7 CONFIG.PCW_MIO_12_PULLUP {enabled}
ad_ip_parameter sys_ps7 CONFIG.PCW_MIO_13_PULLUP {enabled}
ad_ip_parameter sys_ps7 CONFIG.PCW_MIO_14_PULLUP {enabled}
ad_ip_parameter sys_ps7 CONFIG.PCW_MIO_20_PULLUP {disabled}
ad_ip_parameter sys_ps7 CONFIG.PCW_MIO_40_PULLUP {enabled}
ad_ip_parameter sys_ps7 CONFIG.PCW_MIO_40_SLEW   {fast}
ad_ip_parameter sys_ps7 CONFIG.PCW_MIO_41_PULLUP {enabled}
ad_ip_parameter sys_ps7 CONFIG.PCW_MIO_42_PULLUP {enabled}
ad_ip_parameter sys_ps7 CONFIG.PCW_MIO_43_PULLUP {enabled}
ad_ip_parameter sys_ps7 CONFIG.PCW_MIO_44_PULLUP {enabled}
ad_ip_parameter sys_ps7 CONFIG.PCW_MIO_45_PULLUP {enabled}

# DDR MT41K128M16 JT-125

ad_ip_parameter sys_ps7 CONFIG.PCW_UIPARAM_DDR_PARTNO {MT41K128M16 JT-125}
ad_ip_parameter sys_ps7 CONFIG.PCW_UIPARAM_DDR_BUS_WIDTH {16 Bit}
ad_ip_parameter sys_ps7 CONFIG.PCW_UIPARAM_DDR_TRAIN_WRITE_LEVEL 1
ad_ip_parameter sys_ps7 CONFIG.PCW_UIPARAM_DDR_TRAIN_READ_GATE 1
ad_ip_parameter sys_ps7 CONFIG.PCW_UIPARAM_DDR_TRAIN_DATA_EYE 1

# interface connections

ad_connect sys_ps7/MDIO_ETHERNET_0 MDIO_PHY
ad_connect sys_ps7/GMII_ETHERNET_0 GMII

ad_connect ddr sys_ps7/DDR
ad_connect fixed_io sys_ps7/FIXED_IO

ad_connect UART_0 sys_ps7/UART_0

ad_connect gpio_i sys_ps7/GPIO_I
ad_connect gpio_o sys_ps7/GPIO_O
ad_connect gpio_t sys_ps7/GPIO_T

ad_connect ttc0_wave0_out sys_ps7/TTC0_WAVE0_OUT

ad_connect sys_cpu_clk sys_ps7/FCLK_CLK0


ad_ip_instance xlconcat sys_concat_intc
ad_ip_parameter sys_concat_intc CONFIG.NUM_PORTS 16

ad_ip_instance proc_sys_reset sys_rstgen
ad_ip_parameter sys_rstgen CONFIG.C_EXT_RST_WIDTH 1

# ps7 spi connections

ad_connect lcd_scl sys_ps7/SPI0_SCLK_O
ad_connect lcd_sda sys_ps7/SPI0_MOSI_O

# system reset/clock definitions

ad_connect sys_cpu_reset sys_rstgen/peripheral_reset
ad_connect sys_cpu_resetn sys_rstgen/peripheral_aresetn
ad_connect sys_cpu_clk sys_rstgen/slowest_sync_clk
ad_connect sys_rstgen/ext_reset_in sys_ps7/FCLK_RESET0_N

# interrupts

ad_connect sys_concat_intc/dout sys_ps7/IRQ_F2P
ad_connect sys_concat_intc/In15 GND
ad_connect sys_concat_intc/In14 GND
ad_connect sys_concat_intc/In13 GND
ad_connect sys_concat_intc/In12 GND
ad_connect sys_concat_intc/In11 GND
ad_connect sys_concat_intc/In10 GND
ad_connect sys_concat_intc/In9 GND
ad_connect sys_concat_intc/In8 GND
ad_connect sys_concat_intc/In7 GND
ad_connect sys_concat_intc/In6 GND
ad_connect sys_concat_intc/In5 GND
ad_connect sys_concat_intc/In4 GND
ad_connect sys_concat_intc/In3 GND
ad_connect sys_concat_intc/In2 GND
ad_connect sys_concat_intc/In1 GND
ad_connect sys_concat_intc/In0 GND

### hdmi

ad_ip_instance hdmi hdmi_0
ad_ip_instance hdmi_generator hdmi_generator_0

ad_connect hdmi_0/tmds_0 hdmi_d0
ad_connect hdmi_0/tmds_1 hdmi_d1
ad_connect hdmi_0/tmds_2 hdmi_d2
ad_connect hdmi_0/tmds_clock hdmi_clk

ad_connect sys_cpu_clk hdmi_generator_0/clk_100m
ad_connect sys_cpu_reset hdmi_generator_0/reset_100m

ad_connect hdmi_generator_0/pixel_reset hdmi_0/reset

ad_connect hdmi_generator_0/pixel_clk hdmi_0/clk_pixel
ad_connect hdmi_generator_0/pixel_x5_clk hdmi_0/clk_pixel_x5
ad_connect GND hdmi_0/clk_audio

ad_connect hdmi_0/cx hdmi_generator_0/cx
ad_connect hdmi_0/cy hdmi_generator_0/cy
ad_connect hdmi_0/screen_width hdmi_generator_0/screen_width
ad_connect hdmi_0/screen_height hdmi_generator_0/screen_height
ad_connect hdmi_generator_0/rgb hdmi_0/rgb

ad_ip_instance xlconstant audio_sample_word_GND
ad_ip_parameter audio_sample_word_GND CONFIG.CONST_VAL 0
ad_ip_parameter audio_sample_word_GND CONFIG.CONST_WIDTH 16

ad_connect audio_sample_word_GND/dout hdmi_0/audio_sample_word_0
ad_connect audio_sample_word_GND/dout hdmi_0/audio_sample_word_1

### dma

ad_ip_instance axi_dmac hdmi_sink_dma
ad_ip_parameter hdmi_sink_dma CONFIG.DMA_TYPE_SRC 0
ad_ip_parameter hdmi_sink_dma CONFIG.DMA_TYPE_DEST 1
ad_ip_parameter hdmi_sink_dma CONFIG.CYCLIC 1
ad_ip_parameter hdmi_sink_dma CONFIG.AXI_SLICE_SRC 0
ad_ip_parameter hdmi_sink_dma CONFIG.AXI_SLICE_DEST 0
ad_ip_parameter hdmi_sink_dma CONFIG.DMA_2D_TRANSFER 0
ad_ip_parameter hdmi_sink_dma CONFIG.DMA_DATA_WIDTH_DEST 64

ad_connect hdmi_generator_0/pixel_clk hdmi_sink_dma/m_axis_aclk

ad_connect sys_cpu_clk hdmi_sink_dma/m_src_axi_aclk
ad_connect sys_cpu_resetn hdmi_sink_dma/m_src_axi_aresetn

ad_connect hdmi_generator_0/s_axis_rgb hdmi_sink_dma/m_axis

### interconnects

ad_cpu_interconnect 0x7c420000 hdmi_sink_dma

ad_ip_parameter sys_ps7 CONFIG.PCW_USE_S_AXI_HP0 {1}
ad_connect sys_cpu_clk sys_ps7/S_AXI_HP0_ACLK
ad_connect hdmi_sink_dma/m_src_axi sys_ps7/S_AXI_HP0

create_bd_addr_seg -range 0x20000000 -offset 0x00000000 \
                    [get_bd_addr_spaces hdmi_sink_dma/m_src_axi] \
                    [get_bd_addr_segs sys_ps7/S_AXI_HP0/HP0_DDR_LOWOCM] \
                    SEG_sys_ps7_HP0_DDR_LOWOCM

### interrupts

ad_cpu_interrupt ps-12 mb-12 hdmi_sink_dma/irq

### PL TTY character device

ad_ip_instance axi_uartlite axi_uartlite_0
ad_ip_parameter axi_uartlite_0 CONFIG.C_BAUDRATE 115200
ad_ip_parameter axi_uartlite_0 CONFIG.C_DATA_BITS 8
ad_ip_parameter axi_uartlite_0 CONFIG.C_USE_PARITY 0
ad_ip_parameter axi_uartlite_0 CONFIG.C_ODD_PARITY 0

ad_cpu_interconnect 0x7C430000 axi_uartlite_0
ad_cpu_interrupt ps-13 mb-13 axi_uartlite_0/interrupt

# ── UART PHY ──
ad_ip_instance uart_phy uart_phy_0
ad_connect sys_cpu_clk uart_phy_0/clk
ad_connect sys_cpu_reset uart_phy_0/reset
ad_connect axi_uartlite_0/tx uart_phy_0/uart_rx_i
ad_connect axi_uartlite_0/rx uart_phy_0/uart_tx_o

# ── bf2_soc ──
ad_ip_instance bf2_soc bf2_soc_0
ad_connect sys_cpu_clk bf2_soc_0/clk_i
ad_connect sys_cpu_resetn bf2_soc_0/resetq
ad_connect uart_phy_0/rx_data   bf2_soc_0/io_rx_data
ad_connect uart_phy_0/rx_valid  bf2_soc_0/io_rx_valid
ad_connect bf2_soc_0/io_rx_ready  uart_phy_0/rx_accept_i
ad_connect bf2_soc_0/io_tx_data   uart_phy_0/tx_data
ad_connect bf2_soc_0/io_tx_valid  uart_phy_0/tx_start
ad_connect uart_phy_0/tx_ready    bf2_soc_0/io_tx_ready

# ── bf2 control via axi_gpreg ──
ad_ip_instance axi_gpreg bf2_ctrl
ad_ip_parameter bf2_ctrl CONFIG.NUM_OF_IO 3
ad_ip_parameter bf2_ctrl CONFIG.NUM_OF_CLK_MONS 0
ad_ip_parameter bf2_ctrl CONFIG.ID 48912
ad_cpu_interconnect 0x7C440000 bf2_ctrl

ad_connect bf2_ctrl/up_gp_out_0  bf2_soc_0/ctrl_gp0_out
ad_connect bf2_ctrl/up_gp_out_1  bf2_soc_0/ctrl_gp1_out
ad_connect bf2_ctrl/up_gp_out_2  bf2_soc_0/ctrl_gp2_out
ad_connect bf2_soc_0/ctrl_gp0_in  bf2_ctrl/up_gp_in_0
ad_connect bf2_soc_0/ctrl_gp1_in  bf2_ctrl/up_gp_in_1
ad_connect bf2_soc_0/ctrl_gp2_in  bf2_ctrl/up_gp_in_2

### PS↔PL byte-stream bridge test path (AXI-Stream FIFO + byte adapter + case_toggle)
# bf2_soc stays on the uartlite path above; this fifo path is the bring-up
# testbed for the bridge with case_toggle standing in for bf2_soc.

ad_ip_instance axi_fifo_mm_s axi_fifo_mm_s_0
ad_ip_parameter axi_fifo_mm_s_0 CONFIG.C_DATA_INTERFACE_TYPE 0
ad_ip_parameter axi_fifo_mm_s_0 CONFIG.C_USE_TX_DATA 1
ad_ip_parameter axi_fifo_mm_s_0 CONFIG.C_USE_RX_DATA 1
ad_ip_parameter axi_fifo_mm_s_0 CONFIG.C_USE_TX_CTRL 0
ad_ip_parameter axi_fifo_mm_s_0 CONFIG.C_TX_FIFO_DEPTH 1024
ad_ip_parameter axi_fifo_mm_s_0 CONFIG.C_RX_FIFO_DEPTH 1024
ad_ip_parameter axi_fifo_mm_s_0 CONFIG.C_USE_TX_CUT_THROUGH 0
ad_ip_parameter axi_fifo_mm_s_0 CONFIG.C_USE_RX_CUT_THROUGH 0
ad_connect sys_cpu_clk axi_fifo_mm_s_0/s_axi_aclk
ad_connect sys_cpu_resetn axi_fifo_mm_s_0/s_axi_aresetn

ad_cpu_interconnect 0x7C450000 axi_fifo_mm_s_0
ad_cpu_interrupt ps-14 mb-14 axi_fifo_mm_s_0/interrupt

# axis_byte_bridge v1 (drop-24): 32-bit stream words ↔ 8-bit byte handshake
ad_ip_instance axis_byte_bridge axis_byte_bridge_0
ad_connect sys_cpu_clk axis_byte_bridge_0/clk
ad_connect sys_cpu_reset axis_byte_bridge_0/reset

ad_connect axi_fifo_mm_s_0/AXI_STR_TXD axis_byte_bridge_0/m_axis
ad_connect axis_byte_bridge_0/s_axis axi_fifo_mm_s_0/AXI_STR_RXD

# case_toggle (test stand-in for bf2_soc): toggles ASCII case (XOR 0x20)
ad_ip_instance case_toggle case_toggle_0
ad_connect sys_cpu_clk case_toggle_0/clk
ad_connect sys_cpu_reset case_toggle_0/reset

ad_connect axis_byte_bridge_0/rx_data   case_toggle_0/io_rx_data
ad_connect axis_byte_bridge_0/rx_valid  case_toggle_0/io_rx_valid
ad_connect case_toggle_0/io_rx_ready    axis_byte_bridge_0/rx_accept
ad_connect case_toggle_0/io_tx_data     axis_byte_bridge_0/tx_data
ad_connect case_toggle_0/io_tx_valid    axis_byte_bridge_0/tx_valid
ad_connect axis_byte_bridge_0/tx_ready  case_toggle_0/io_tx_ready
