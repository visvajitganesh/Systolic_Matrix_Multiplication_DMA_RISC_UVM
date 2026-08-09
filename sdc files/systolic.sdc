#######################################################################
# SDC Constraints for systolic (systolic array / PE grid, MAC-based)
# Target: SAED32nm, saed32rvt_ss0p7vn40c (worst-case setup corner)
#######################################################################

#############################
# 1. Clock Definition
#############################
# NOTE: This design does multiply-accumulate (psum_in + weight*in) per
# PE, which is far more timing-critical than a simple counter/adder.
# Start conservative and tighten after seeing a clean STA report.
set CLK_PERIOD  8.500
set CLK_NAME    clk

create_clock -name $CLK_NAME -period $CLK_PERIOD [get_ports clk]

set_clock_uncertainty -setup 0.060 [get_clocks $CLK_NAME]
set_clock_uncertainty -hold  0.030 [get_clocks $CLK_NAME]
set_clock_transition  0.020 [get_clocks $CLK_NAME]

#############################
# 2. Asynchronous Reset
#############################
# rst is ACTIVE-HIGH here (posedge rst in always_ff), unlike dma's
# active-low rst_n. Still async -> exclude from setup/hold timing.
set_false_path -from [get_ports rst]

#############################
# 3. Input Delays
#############################
set IN_DELAY_MAX  [expr {$CLK_PERIOD * 0.20}]
set IN_DELAY_MIN  [expr {$CLK_PERIOD * 0.05}]

# Explicit port list (avoids remove_from_collection issue seen in dma.sdc —
# get_ports with a name list is plain SDC, works fine under read_sdc)
set all_in_ports [get_ports {
    start
    input_data
}]

set_input_delay -clock $CLK_NAME -max $IN_DELAY_MAX $all_in_ports
set_input_delay -clock $CLK_NAME -min $IN_DELAY_MIN $all_in_ports

#############################
# 4. Output Delays
#############################
set OUT_DELAY_MAX [expr {$CLK_PERIOD * 0.20}]
set OUT_DELAY_MIN [expr {$CLK_PERIOD * 0.05}]

set all_out_ports [get_ports {
    output_data
    valid
}]

set_output_delay -clock $CLK_NAME -max $OUT_DELAY_MAX $all_out_ports
set_output_delay -clock $CLK_NAME -min $OUT_DELAY_MIN $all_out_ports

#############################
# 5. Driving Cell / Load
#############################
set_driving_cell -lib_cell BUFX2 -pin Z $all_in_ports
set_load 0.002 [all_outputs]

#############################
# 6. Max Transition / Max Fanout
#############################
set_max_transition 0.150 [current_design]
set_max_fanout      16   [current_design]

#############################
# 7. Exceptions
#############################
# No CDC — single clock domain. No false/multicycle paths identified
# yet. If the MAC critical path proves too slow at target frequency,
# consider a multicycle path on psum accumulation before relaxing clk.
