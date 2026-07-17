/*

Copyright (C) 2014-2023 Analog Devices, Inc. All rights reserved.
Copyright (C) 2025 Mateusz Nalewajski. All rights reserved.

In this HDL repository, there are many different and unique modules, consisting
of various HDL (Verilog or VHDL) components. The individual modules are
developed independently, and may be accompanied by separate and unique license
terms.

The user should read each of these license terms, and understand the
freedoms and responsibilities that he or she has by using this source/core.

This core is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
A PARTICULAR PURPOSE.

Redistribution and use of source or resulting binaries, with or without modification
of this file, are permitted under one of the following two license terms:

  1. The GNU General Public License version 2 as published by the
     Free Software Foundation, which can be found in the top level directory
     of this repository (LICENSE_GPL2), and also online at:
     <https://www.gnu.org/licenses/old-licenses/gpl-2.0.html>

OR

  2. An ADI specific BSD license, which can be found in the top level directory
     of this repository (LICENSE_ADIBSD), and also on-line at:
     https://github.com/analogdevicesinc/hdl/blob/main/LICENSE_ADIBSD
     This will allow to generate bit files and not release the source code,
     as long as it attaches to an ADI device.

/*

/*

This file is based on "pluto" project from Analog Devices
reference HDL repository.

*/

`timescale 1ns / 100ps
module system_top (
  output       MDIO_PHY_mdc,
  inout        MDIO_PHY_mdio_io,

  input        GMII_rx_clk,
  input        GMII_tx_clk,
  input        GMII_rx_dv,
  input  [3:0] GMII_rxd,
  output [3:0] GMII_txd,
  output       GMII_tx_en,

  input        UART_0_rxd,
  output       UART_0_txd,

  inout [14:0] ddr_addr,
  inout [ 2:0] ddr_ba,
  inout        ddr_cas_n,
  inout        ddr_ck_n,
  inout        ddr_ck_p,
  inout        ddr_cke,
  inout        ddr_cs_n,
  inout [ 3:0] ddr_dm,
  inout [31:0] ddr_dq,
  inout [ 3:0] ddr_dqs_n,
  inout [ 3:0] ddr_dqs_p,
  inout        ddr_odt,
  inout        ddr_ras_n,
  inout        ddr_reset_n,
  inout        ddr_we_n,

  inout        fixed_io_ddr_vrn,
  inout        fixed_io_ddr_vrp,
  inout [53:0] fixed_io_mio,
  inout        fixed_io_ps_clk,
  inout        fixed_io_ps_porb,
  inout        fixed_io_ps_srstb,

  inout        gpio_led_red,
  inout        gpio_led_green,
  inout        gpio_led_aux_0,
  inout        gpio_led_aux_1,
  inout        gpio_led_aux_2,
  inout        gpio_switch_aux_0,
  inout        gpio_switch_aux_1,
  inout        gpio_switch_aux_2,
  inout        gpio_switch_aux_3,
  inout        gpio_switch_aux_4,

  output       buzzer,

  output       lcd_backlight,
  output       lcd_dc,
  output       lcd_scl,
  output       lcd_sda,
  output       lcd_res,

  output       hdmi_clk_p, hdmi_clk_n,
  output       hdmi_d0_p,  hdmi_d0_n,
  output       hdmi_d1_p,  hdmi_d1_n,
  output       hdmi_d2_p,  hdmi_d2_n,

  input        ext_clk_50m
);
  // internal signals

  wire [12:0] gpio_i;
  wire [12:0] gpio_o;
  wire [12:0] gpio_t;

  wire hdmi_clk;
  wire hdmi_d0;
  wire hdmi_d1;
  wire hdmi_d2;

  wire [7:0] GMII_txd_0;

  wire ext_clk_50m_i;
  wire ext_clk_50m_o;

  // instantiations

  ad_iobuf #(
    .DATA_WIDTH(13)
  ) i_iobuf (
    .dio_t(gpio_t[12:0]),
    .dio_i(gpio_o[12:0]),
    .dio_o(gpio_i[12:0]),
    .dio_p({ lcd_backlight,      // 12:12
             lcd_dc,             // 11:11
             lcd_res,            // 10:10
             gpio_switch_aux_4,  //  9: 9
             gpio_switch_aux_3,  //  8: 8
             gpio_switch_aux_2,  //  7: 7
             gpio_switch_aux_1,  //  6: 6
             gpio_switch_aux_0,  //  5: 5
             gpio_led_aux_2,     //  4: 4
             gpio_led_aux_1,     //  3: 3
             gpio_led_aux_0,     //  2: 2
             gpio_led_red,       //  1: 1
             gpio_led_green })); //  0: 0

  assign GMII_txd = GMII_txd_0[3:0];

  // hdmi buffers

  OBUFDS #(
    .IOSTANDARD("TMDS_33")
  ) obufds_clk (
    .I(hdmi_clk),
    .O(hdmi_clk_p),
    .OB(hdmi_clk_n)
  );

  OBUFDS #(
    .IOSTANDARD("TMDS_33")
  ) obufds_d0 (
    .I(hdmi_d0),
    .O(hdmi_d0_p),
    .OB(hdmi_d0_n)
  );

  OBUFDS #(
    .IOSTANDARD("TMDS_33")
  ) obufds_d1 (
    .I(hdmi_d1),
    .O(hdmi_d1_p),
    .OB(hdmi_d1_n)
  );

  OBUFDS #(
    .IOSTANDARD("TMDS_33")
  ) obufds_d2 (
    .I(hdmi_d2),
    .O(hdmi_d2_p),
    .OB(hdmi_d2_n)
  );

  // clocks

  IBUF ext_clk_50m_ibufg (
    .I(ext_clk_50m),
    .O(ext_clk_50m_i)
  );

  BUFG ext_clk_50m_bufg (
    .I(ext_clk_50m_i),
    .O(ext_clk_50m_o)
  );

  // system wrapper

  system_wrapper i_system_wrapper (
    .MDIO_PHY_mdc(MDIO_PHY_mdc),
    .MDIO_PHY_mdio_io(MDIO_PHY_mdio_io),

    .GMII_col(1'b0),
    .GMII_crs(1'b0),
    .GMII_rx_clk(GMII_rx_clk),
    .GMII_tx_clk(GMII_tx_clk),
    .GMII_rx_dv(GMII_rx_dv),
    .GMII_rx_er(1'b0),
    .GMII_rxd({4'b0, GMII_rxd}),
    .GMII_txd(GMII_txd_0),
    .GMII_tx_en(GMII_tx_en),
    .GMII_tx_er(),

    .UART_0_rxd(UART_0_rxd),
    .UART_0_txd(UART_0_txd),

    .ddr_addr(ddr_addr),
    .ddr_ba(ddr_ba),
    .ddr_cas_n(ddr_cas_n),
    .ddr_ck_n(ddr_ck_n),
    .ddr_ck_p(ddr_ck_p),
    .ddr_cke(ddr_cke),
    .ddr_cs_n(ddr_cs_n),
    .ddr_dm(ddr_dm),
    .ddr_dq(ddr_dq),
    .ddr_dqs_n(ddr_dqs_n),
    .ddr_dqs_p(ddr_dqs_p),
    .ddr_odt(ddr_odt),
    .ddr_ras_n(ddr_ras_n),
    .ddr_reset_n(ddr_reset_n),
    .ddr_we_n(ddr_we_n),

    .fixed_io_ddr_vrn(fixed_io_ddr_vrn),
    .fixed_io_ddr_vrp(fixed_io_ddr_vrp),
    .fixed_io_mio(fixed_io_mio),
    .fixed_io_ps_clk(fixed_io_ps_clk),
    .fixed_io_ps_porb(fixed_io_ps_porb),
    .fixed_io_ps_srstb(fixed_io_ps_srstb),

    .gpio_i(gpio_i),
    .gpio_o(gpio_o),
    .gpio_t(gpio_t),

    .ttc0_wave0_out(buzzer),

    .lcd_scl(lcd_scl),
    .lcd_sda(lcd_sda),

    .hdmi_clk(hdmi_clk),
    .hdmi_d0(hdmi_d0),
    .hdmi_d1(hdmi_d1),
    .hdmi_d2(hdmi_d2),

    .ext_clk_50m(ext_clk_50m_o)
  );
endmodule
