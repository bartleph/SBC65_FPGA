# sbc65.sdc - timing constraints

create_clock -name clk50 -period 20.000 [get_ports clk50]

# CPU clock = clk50 / CPU_DIV, made by a register (default 1 MHz)
create_generated_clock -name cpu_clk -source [get_ports clk50] -divide_by 50 [get_registers {cpu_clk}]

derive_clock_uncertainty

# The bus is only sampled at fixed points in each CPU cycle (see sbc65_top),
# so transfers between the two clocks always get at least 2 clk50 periods.
set_multicycle_path -from [get_clocks clk50] -to [get_clocks cpu_clk] -setup 2
set_multicycle_path -from [get_clocks clk50] -to [get_clocks cpu_clk] -hold 1
set_multicycle_path -from [get_clocks cpu_clk] -to [get_clocks clk50] -setup 2
set_multicycle_path -from [get_clocks cpu_clk] -to [get_clocks clk50] -hold 1

# Asynchronous inputs / slow outputs
set_false_path -from [get_ports {uart_rxd ps2_clk ps2_data sd_miso sd_cd}]
set_false_path -to   [get_ports {uart_txd av_sync_n av_video ps2_clk ps2_data sd_cs sd_clk sd_mosi}]

# SRAM: address/data are set up many 50 MHz clocks before they are used
# (see the SRAM process in sbc65_top.vhd), so the pins need no I/O timing.
set_false_path -to   [get_ports {sram_a[*] sram_d[*] sram_ce_n sram_ce2 sram_oe_n sram_we_n}]
set_false_path -from [get_ports {sram_d[*]}]
