# Vivado xsim waveform TCL script for tb_echo_char

open_wave_database tb_echo_char_wave.wdb

# DUT internals
add_wave /tb_echo_char/dut/clk
add_wave /tb_echo_char/dut/reset
add_wave /tb_echo_char/dut/uart_tx_i
add_wave /tb_echo_char/dut/uart_rx_o
add_wave /tb_echo_char/dut/rx_state
add_wave /tb_echo_char/dut/rx_data
add_wave /tb_echo_char/dut/rx_data_valid
add_wave /tb_echo_char/dut/fifo_wr_ptr
add_wave /tb_echo_char/dut/fifo_rd_ptr
add_wave /tb_echo_char/dut/fifo_empty
add_wave /tb_echo_char/dut/fifo_full
add_wave /tb_echo_char/dut/tx_byte
add_wave /tb_echo_char/dut/tx_start
add_wave /tb_echo_char/dut/tx_busy
add_wave /tb_echo_char/dut/tx_state
add_wave /tb_echo_char/dut/tx_shift_reg

# Testbench control
add_wave /tb_echo_char/clk
add_wave /tb_echo_char/reset
add_wave /tb_echo_char/test_num
add_wave /tb_echo_char/pass_count
add_wave /tb_echo_char/fail_count
add_wave /tb_echo_char/rx_queue_wr_ptr
add_wave /tb_echo_char/rx_queue_rd_ptr

run all