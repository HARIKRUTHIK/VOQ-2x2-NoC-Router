# ==============================================================================
# Synopsys Design Constraints (SDC) for VOQ 2x2 NoC Router
# Target Clock: 100 MHz (10.000 ns Period)
# ==============================================================================

# Create Primary Clock
create_clock -name clk -period 10.000 [get_ports {clk}]

# Set Clock Uncertainty
set_clock_uncertainty -setup 0.200 [get_clocks {clk}]
set_clock_uncertainty -hold 0.100 [get_clocks {clk}]

# Input Constraints (2.0 ns setup, 1.0 ns hold budget)
set_input_delay -clock clk -max 2.000 [get_ports {rst_n inport0_* inport1_*}]
set_input_delay -clock clk -min 0.500 [get_ports {rst_n inport0_* inport1_*}]

# Output Constraints (2.5 ns output delay budget)
set_output_delay -clock clk -max 2.500 [get_ports {outport0_* outport1_* err_* throughput_* conflict_*}]
set_output_delay -clock clk -min 0.500 [get_ports {outport0_* outport1_* err_* throughput_* conflict_*}]
