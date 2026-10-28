# ============================================================================
# T0 constraints for top.v on ZedBoard (xc7z020clg484-1)
# Pin numbers from Digilent Zedboard-Master.xdc
# ============================================================================

# ---- 100 MHz clock : bank 13, pin Y9 (fixed 3.3V bank) ----
set_property PACKAGE_PIN Y9 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
create_clock -period 10.000 -name sys_clk [get_ports clk]

# ---- reset : centre push button BTNC (bank 34) ----
# NOTE: bank 34 default IOSTANDARD is LVCMOS18 (see foot of file)
set_property PACKAGE_PIN P16 [get_ports rst_n]

# ---- UART on JA Pmod (bank 13, 3.3V) ----
# uart_rx = FPGA input  -> JA1 (Y11)
# uart_tx = FPGA output -> JA2 (AA11)
set_property PACKAGE_PIN Y11  [get_ports uart_rx]
set_property PACKAGE_PIN AA11 [get_ports uart_tx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_rx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_tx]

# ---- 8 user LEDs LD0..LD7 : bank 33 (fixed 3.3V) ----
set_property PACKAGE_PIN T22 [get_ports {led[0]}]
set_property PACKAGE_PIN T21 [get_ports {led[1]}]
set_property PACKAGE_PIN U22 [get_ports {led[2]}]
set_property PACKAGE_PIN U21 [get_ports {led[3]}]
set_property PACKAGE_PIN V22 [get_ports {led[4]}]
set_property PACKAGE_PIN W22 [get_ports {led[5]}]
set_property PACKAGE_PIN U19 [get_ports {led[6]}]
set_property PACKAGE_PIN U14 [get_ports {led[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[*]}]