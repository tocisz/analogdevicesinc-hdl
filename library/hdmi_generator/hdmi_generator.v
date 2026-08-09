/*

Copyright (c) 2025 Mateusz Nalewajski

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

*/

`default_nettype none
`timescale 1 ns / 1 ps
module hdmi_generator #(
  // Defaults to 640x480 which should be supported by almost if not all HDMI sinks.
  parameter VIDEO_ID_CODE = 1
) (
  (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 reset_100m RST" *)
  (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_HIGH" *)
  input wire reset_100m,
  (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk_100m CLK" *)
  (* X_INTERFACE_PARAMETER = "ASSOCIATED_RESET reset_100m" *)
  input wire clk_100m,

  (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 pixel_reset RST" *)
  (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_HIGH" *)
  output wire pixel_reset,
  (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 pixel_clk CLK" *)
  (* X_INTERFACE_PARAMETER = "ASSOCIATED_RESET pixel_reset, FREQ_HZ 25250000, ASSOCIATED_BUSIF s_axis_rgb" *)
  output wire pixel_clk,
  (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 pixel_clk_5x CLK" *)
  (* X_INTERFACE_PARAMETER = "ASSOCIATED_RESET pixel_reset, FREQ_HZ 126250000" *)
  output wire pixel_x5_clk,

  input wire [63:0] s_axis_rgb_tdata,
  input wire s_axis_rgb_tvalid,
  input wire s_axis_rgb_tlast,
  output wire s_axis_rgb_tready,

  input wire [9:0] cx,
  input wire [9:0] cy,

  input wire [9:0] screen_width,
  input wire [9:0] screen_height,

  output wire [23:0] rgb
);

  localparam DIVCLK_DIVIDE =
    (VIDEO_ID_CODE == 1) ? 4 :
                           0;

  localparam CLKFBOUT_MULT_F =
    (VIDEO_ID_CODE == 1) ? 50.500 :
                           0;

  localparam CLKOUT0_DIVIDE_F =
    (VIDEO_ID_CODE == 1) ? 40.000 :
                           0;

  localparam CLKOUT1_DIVIDE = CLKOUT0_DIVIDE_F / 5;

generate
  if (DIVCLK_DIVIDE == 0)
    $error("Provided VIDEO_ID_CODE is not supported");
endgenerate

  wire clkfbout, clkfbout_o;

  wire pixel_clk_i;
  wire pixel_x5_clk_i;

  wire locked;

  MMCME2_ADV #(
    .BANDWIDTH("OPTIMIZED"),
    .COMPENSATION("ZHOLD"),
    .STARTUP_WAIT("FALSE"),
    .CLKIN1_PERIOD(12.500),
    .DIVCLK_DIVIDE(DIVCLK_DIVIDE),
    .CLKFBOUT_MULT_F(CLKFBOUT_MULT_F),
    .CLKOUT0_DIVIDE_F(CLKOUT0_DIVIDE_F),
    .CLKOUT1_DIVIDE(CLKOUT1_DIVIDE)
  ) mmcm_adv_inst (
    .PWRDWN(1'b0),
    .RST(reset_100m),
    .CLKIN1(clk_100m),
    .CLKINSEL(1'b1),
    .CLKFBOUT(clkfbout),
    .CLKFBIN(clkfbout_o),
    .CLKOUT0(pixel_clk_i),
    .CLKOUT1(pixel_x5_clk_i),
    .LOCKED(locked)
  );

  BUFG clkfbout_bufg(
    .I(clkfbout),
    .O(clkfbout_o)
  );

  BUFG pixel_clk_bufg (
    .I(pixel_clk_i),
    .O(pixel_clk)
  );

  BUFG pixel_x5_clk_bufg(
    .I(pixel_x5_clk_i),
    .O(pixel_x5_clk)
  );

  util_reset_sync util_reset_sync_0 (
    .rst(reset_100m || !locked),
    .clk(pixel_clk),
    .out(pixel_reset)
  );

  hdmi_adapter hdmi_adapter_0 (
    .areset(pixel_reset),
    .aclk(pixel_clk),
    .s_axis_rgb_tdata(s_axis_rgb_tdata),
    .s_axis_rgb_tvalid(s_axis_rgb_tvalid),
    .s_axis_rgb_tlast(s_axis_rgb_tlast),
    .s_axis_rgb_tready(s_axis_rgb_tready),
    .cx(cx),
    .cy(cy),
    .screen_width(screen_width),
    .screen_height(screen_height),
    .rgb(rgb)
  );
endmodule
`default_nettype wire
// vim:ts=2 sw=2 tw=120 et
