###############################################################################
## Copyright (C) 2014-2024 Analog Devices, Inc. All rights reserved.
## Copyright (C) 2025 Mateusz Nalewajski. All rights reserved.
### SPDX short identifier: ADIBSD
###############################################################################

## This file is based on "pluto" project from Analog Devices
## reference HDL repository.

## ports

# uart

set_property IOSTANDARD LVCMOS33 [get_ports UART_0_rxd]
set_property IOSTANDARD LVCMOS33 [get_ports UART_0_txd]
set_property PACKAGE_PIN H16 [get_ports UART_0_rxd]
set_property PACKAGE_PIN H17 [get_ports UART_0_txd]

# leds

set_property IOSTANDARD LVCMOS33 [get_ports gpio_led_green]
set_property IOSTANDARD LVCMOS33 [get_ports gpio_led_red]
set_property IOSTANDARD LVCMOS33 [get_ports gpio_led_aux_0]
set_property IOSTANDARD LVCMOS33 [get_ports gpio_led_aux_1]
set_property IOSTANDARD LVCMOS33 [get_ports gpio_led_aux_2]
set_property IOSTANDARD LVCMOS33 [get_ports buzzer]
set_property PACKAGE_PIN W13 [get_ports gpio_led_green]
set_property PACKAGE_PIN W14 [get_ports gpio_led_red]
set_property PACKAGE_PIN E19 [get_ports gpio_led_aux_0]
set_property PACKAGE_PIN K17 [get_ports gpio_led_aux_1]
set_property PACKAGE_PIN H18 [get_ports gpio_led_aux_2]
set_property PACKAGE_PIN D18 [get_ports buzzer]

# switches

set_property IOSTANDARD LVCMOS33 [get_ports gpio_switch_aux_0]
set_property IOSTANDARD LVCMOS33 [get_ports gpio_switch_aux_1]
set_property IOSTANDARD LVCMOS33 [get_ports gpio_switch_aux_2]
set_property IOSTANDARD LVCMOS33 [get_ports gpio_switch_aux_3]
set_property IOSTANDARD LVCMOS33 [get_ports gpio_switch_aux_4]
set_property PACKAGE_PIN T19 [get_ports gpio_switch_aux_0]
set_property PACKAGE_PIN P19 [get_ports gpio_switch_aux_1]
set_property PACKAGE_PIN U20 [get_ports gpio_switch_aux_2]
set_property PACKAGE_PIN U19 [get_ports gpio_switch_aux_3]
set_property PACKAGE_PIN V20 [get_ports gpio_switch_aux_4]

# hdmi

set_property PACKAGE_PIN F19 [get_ports {hdmi_clk_p}]
set_property PACKAGE_PIN F20 [get_ports {hdmi_clk_n}]
set_property IOSTANDARD TMDS_33 [get_ports {hdmi_clk_p}]
set_property IOSTANDARD TMDS_33 [get_ports {hdmi_clk_n}]

set_property PACKAGE_PIN D19 [get_ports {hdmi_d0_p}]
set_property PACKAGE_PIN D20 [get_ports {hdmi_d0_n}]
set_property IOSTANDARD TMDS_33 [get_ports {hdmi_d0_p}]
set_property IOSTANDARD TMDS_33 [get_ports {hdmi_d0_n}]

set_property PACKAGE_PIN C20 [get_ports {hdmi_d1_p}]
set_property PACKAGE_PIN B20 [get_ports {hdmi_d1_n}]
set_property IOSTANDARD TMDS_33 [get_ports {hdmi_d1_p}]
set_property IOSTANDARD TMDS_33 [get_ports {hdmi_d1_n}]

set_property PACKAGE_PIN B19 [get_ports {hdmi_d2_p}]
set_property PACKAGE_PIN A20 [get_ports {hdmi_d2_n}]
set_property IOSTANDARD TMDS_33 [get_ports {hdmi_d2_p}]
set_property IOSTANDARD TMDS_33 [get_ports {hdmi_d2_n}]

# gmii

set_property IOSTANDARD LVCMOS33 [get_ports GMII_rx_clk]
set_property IOSTANDARD LVCMOS33 [get_ports GMII_tx_clk]
set_property PACKAGE_PIN U14 [get_ports GMII_rx_clk]
set_property PACKAGE_PIN U15 [get_ports GMII_tx_clk]

set_property IOSTANDARD LVCMOS33 [get_ports {GMII_rxd[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {GMII_rxd[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {GMII_rxd[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {GMII_rxd[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports GMII_tx_en]
set_property IOSTANDARD LVCMOS33 [get_ports {GMII_txd[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {GMII_txd[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {GMII_txd[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {GMII_txd[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports GMII_rx_dv]
set_property IOSTANDARD LVCMOS33 [get_ports MDIO_PHY_mdc]
set_property IOSTANDARD LVCMOS33 [get_ports MDIO_PHY_mdio_io]
set_property PACKAGE_PIN Y17 [get_ports {GMII_rxd[3]}]
set_property PACKAGE_PIN V17 [get_ports {GMII_rxd[2]}]
set_property PACKAGE_PIN V16 [get_ports {GMII_rxd[1]}]
set_property PACKAGE_PIN Y16 [get_ports {GMII_rxd[0]}]
set_property PACKAGE_PIN W19 [get_ports GMII_tx_en]
set_property PACKAGE_PIN W18 [get_ports {GMII_txd[0]}]
set_property PACKAGE_PIN Y18 [get_ports {GMII_txd[1]}]
set_property PACKAGE_PIN V18 [get_ports {GMII_txd[2]}]
set_property PACKAGE_PIN Y19 [get_ports {GMII_txd[3]}]
set_property PACKAGE_PIN W15 [get_ports MDIO_PHY_mdc]
set_property PACKAGE_PIN Y14 [get_ports MDIO_PHY_mdio_io]
set_property PACKAGE_PIN W16 [get_ports GMII_rx_dv]

# ext_clk_50m

set_property IOSTANDARD LVCMOS33 [get_ports ext_clk_50m]
set_property PACKAGE_PIN N18 [get_ports ext_clk_50m]


# ddr

set_property IOSTANDARD SSTL15_T_DCI [get_ports *fixed_io_ddr_vr*]
set_property IOSTANDARD DIFF_SSTL15 [get_ports *ddr_ck*]
set_property IOSTANDARD SSTL15 [get_ports *ddr_addr*]
set_property IOSTANDARD SSTL15 [get_ports *ddr_ba*]
set_property IOSTANDARD SSTL15 [get_ports ddr_reset_n]
set_property IOSTANDARD SSTL15 [get_ports ddr_cs_n]
set_property IOSTANDARD SSTL15 [get_ports ddr_ras_n]
set_property IOSTANDARD SSTL15 [get_ports ddr_cas_n]
set_property IOSTANDARD SSTL15 [get_ports ddr_we_n]
set_property IOSTANDARD SSTL15 [get_ports ddr_cke]
set_property IOSTANDARD SSTL15 [get_ports ddr_odt]
set_property IOSTANDARD SSTL15_T_DCI [get_ports *ddr_dq[*]]
set_property IOSTANDARD SSTL15_T_DCI [get_ports *ddr_dm[*]]
set_property IOSTANDARD DIFF_SSTL15_T_DCI [get_ports *ddr_dqs*]
set_property PACKAGE_PIN H5 [get_ports fixed_io_ddr_vrp]
set_property PACKAGE_PIN G5 [get_ports fixed_io_ddr_vrn]
set_property PACKAGE_PIN L2 [get_ports ddr_ck_p]
set_property PACKAGE_PIN M2 [get_ports ddr_ck_n]
set_property PACKAGE_PIN F4 [get_ports ddr_addr[14]]
set_property PACKAGE_PIN D4 [get_ports ddr_addr[13]]
set_property PACKAGE_PIN E4 [get_ports ddr_addr[12]]
set_property PACKAGE_PIN G4 [get_ports ddr_addr[11]]
set_property PACKAGE_PIN F5 [get_ports ddr_addr[10]]
set_property PACKAGE_PIN J4 [get_ports ddr_addr[9]]
set_property PACKAGE_PIN K1 [get_ports ddr_addr[8]]
set_property PACKAGE_PIN K4 [get_ports ddr_addr[7]]
set_property PACKAGE_PIN L4 [get_ports ddr_addr[6]]
set_property PACKAGE_PIN L1 [get_ports ddr_addr[5]]
set_property PACKAGE_PIN M4 [get_ports ddr_addr[4]]
set_property PACKAGE_PIN K3 [get_ports ddr_addr[3]]
set_property PACKAGE_PIN M3 [get_ports ddr_addr[2]]
set_property PACKAGE_PIN K2 [get_ports ddr_addr[1]]
set_property PACKAGE_PIN N2 [get_ports ddr_addr[0]]
set_property PACKAGE_PIN J5 [get_ports ddr_ba[2]]
set_property PACKAGE_PIN R4 [get_ports ddr_ba[1]]
set_property PACKAGE_PIN L5 [get_ports ddr_ba[0]]
set_property PACKAGE_PIN B4 [get_ports ddr_reset_n]
set_property PACKAGE_PIN N1 [get_ports ddr_cs_n]
set_property PACKAGE_PIN P4 [get_ports ddr_ras_n]
set_property PACKAGE_PIN P5 [get_ports ddr_cas_n]
set_property PACKAGE_PIN M5 [get_ports ddr_we_n]
set_property PACKAGE_PIN N3 [get_ports ddr_cke]
set_property PACKAGE_PIN N5 [get_ports ddr_odt]
set_property PACKAGE_PIN V3 [get_ports ddr_dq[31]]
set_property PACKAGE_PIN V2 [get_ports ddr_dq[30]]
set_property PACKAGE_PIN W3 [get_ports ddr_dq[29]]
set_property PACKAGE_PIN Y2 [get_ports ddr_dq[28]]
set_property PACKAGE_PIN Y4 [get_ports ddr_dq[27]]
set_property PACKAGE_PIN W1 [get_ports ddr_dq[26]]
set_property PACKAGE_PIN Y3 [get_ports ddr_dq[25]]
set_property PACKAGE_PIN V1 [get_ports ddr_dq[24]]
set_property PACKAGE_PIN U3 [get_ports ddr_dq[23]]
set_property PACKAGE_PIN U2 [get_ports ddr_dq[22]]
set_property PACKAGE_PIN U4 [get_ports ddr_dq[21]]
set_property PACKAGE_PIN T4 [get_ports ddr_dq[20]]
set_property PACKAGE_PIN R1 [get_ports ddr_dq[19]]
set_property PACKAGE_PIN R3 [get_ports ddr_dq[18]]
set_property PACKAGE_PIN P3 [get_ports ddr_dq[17]]
set_property PACKAGE_PIN P1 [get_ports ddr_dq[16]]
set_property PACKAGE_PIN J1 [get_ports ddr_dq[15]]
set_property PACKAGE_PIN H1 [get_ports ddr_dq[14]]
set_property PACKAGE_PIN H2 [get_ports ddr_dq[13]]
set_property PACKAGE_PIN J3 [get_ports ddr_dq[12]]
set_property PACKAGE_PIN H3 [get_ports ddr_dq[11]]
set_property PACKAGE_PIN G3 [get_ports ddr_dq[10]]
set_property PACKAGE_PIN E3 [get_ports ddr_dq[9]]
set_property PACKAGE_PIN E2 [get_ports ddr_dq[8]]
set_property PACKAGE_PIN E1 [get_ports ddr_dq[7]]
set_property PACKAGE_PIN C1 [get_ports ddr_dq[6]]
set_property PACKAGE_PIN D1 [get_ports ddr_dq[5]]
set_property PACKAGE_PIN D3 [get_ports ddr_dq[4]]
set_property PACKAGE_PIN A4 [get_ports ddr_dq[3]]
set_property PACKAGE_PIN A2 [get_ports ddr_dq[2]]
set_property PACKAGE_PIN B3 [get_ports ddr_dq[1]]
set_property PACKAGE_PIN C3 [get_ports ddr_dq[0]]
set_property PACKAGE_PIN Y1 [get_ports ddr_dm[3]]
set_property PACKAGE_PIN T1 [get_ports ddr_dm[2]]
set_property PACKAGE_PIN F1 [get_ports ddr_dm[1]]
set_property PACKAGE_PIN A1 [get_ports ddr_dm[0]]
set_property PACKAGE_PIN W5 [get_ports ddr_dqs_p[3]]
set_property PACKAGE_PIN R2 [get_ports ddr_dqs_p[2]]
set_property PACKAGE_PIN G2 [get_ports ddr_dqs_p[1]]
set_property PACKAGE_PIN C2 [get_ports ddr_dqs_p[0]]
set_property PACKAGE_PIN W4 [get_ports ddr_dqs_n[3]]
set_property PACKAGE_PIN T2 [get_ports ddr_dqs_n[2]]
set_property PACKAGE_PIN F2 [get_ports ddr_dqs_n[1]]
set_property PACKAGE_PIN B2 [get_ports ddr_dqs_n[0]]

# spi display

set_property IOSTANDARD LVCMOS33 [get_ports lcd_backlight]
set_property IOSTANDARD LVCMOS33 [get_ports lcd_dc]
set_property IOSTANDARD LVCMOS33 [get_ports lcd_scl]
set_property IOSTANDARD LVCMOS33 [get_ports lcd_sda]
set_property IOSTANDARD LVCMOS33 [get_ports lcd_res]
set_property PACKAGE_PIN T20 [get_ports lcd_backlight]
set_property PACKAGE_PIN R18 [get_ports lcd_dc]
set_property PACKAGE_PIN R19 [get_ports lcd_scl]
set_property PACKAGE_PIN P20 [get_ports lcd_sda]
set_property PACKAGE_PIN N17 [get_ports lcd_res]

## clocks

# ethernet PHY

create_clock -name GMII_rx_clk \
    -period 40.000 \
    -waveform {0.000 20.000} \
    [get_ports GMII_rx_clk]

create_clock -name GMII_tx_clk \
    -period 40.000 \
    -waveform {0.000 20.000} \
    [get_ports GMII_tx_clk]

# ext_clk

create_clock -name ext_clk_50m \
    -period 20.000 \
    [get_ports ext_clk_50m]

# fpga_x_clk

create_clock -name fpga_0_clk \
    -period 12.500 \
    [get_pins {i_system_wrapper/system_i/sys_ps7/inst/PS7_i/FCLKCLK[0]}]

set_input_jitter fpga_0_clk 0.3

create_clock -name fpga_1_clk \
    -period 40.000 \
    [get_pins {i_system_wrapper/system_i/sys_ps7/inst/PS7_i/FCLKCLK[1]}]

set_input_jitter fpga_1_clk 0.3

# pixel_clk

create_generated_clock -name pixel_clk \
    [get_pins {i_system_wrapper/system_i/hdmi_generator_0/inst/mmcm_adv_inst/CLKOUT0}]

create_generated_clock -name pixel_x5_clk \
    [get_pins {i_system_wrapper/system_i/hdmi_generator_0/inst/mmcm_adv_inst/CLKOUT1}]
