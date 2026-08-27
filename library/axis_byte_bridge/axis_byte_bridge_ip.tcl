# ip
source ../../scripts/adi_env.tcl
source $ad_hdl_dir/library/scripts/adi_ip_xilinx.tcl

# axis_byte_bridge — byte-stream bridge for axi_byte_fifo (8-bit TDATA, no TLAST)
# See doc/AXI_BYTE_FIFO_PLAN.md. PS↔PL (axi_byte_fifo 8-bit) ↔ z80_soc io_*.
adi_ip_create axis_byte_bridge
adi_ip_files axis_byte_bridge [list \
  "axis_byte_bridge.sv" ]

adi_ip_properties_lite axis_byte_bridge

adi_add_bus "m_axis" "slave" \
	"xilinx.com:interface:axis_rtl:1.0" \
	"xilinx.com:interface:axis:1.0" \
	{
		{"m_axis_tvalid" "TVALID"} \
		{"m_axis_tready" "TREADY"} \
		{"m_axis_tdata" "TDATA"} \
	}

adi_add_bus "s_axis" "master" \
	"xilinx.com:interface:axis_rtl:1.0" \
	"xilinx.com:interface:axis:1.0" \
	{
		{"s_axis_tvalid" "TVALID"} \
		{"s_axis_tready" "TREADY"} \
		{"s_axis_tdata" "TDATA"} \
	}

adi_add_bus_clock "clk" "m_axis:s_axis" "reset"

ipx::save_core [ipx::current_core]
