###############################################################################
# Design Constraints File (SDC) for system_top
###############################################################################
# -----------------------------------------------------------------------------
# 1. Clock Definitions
# -----------------------------------------------------------------------------
set CLK_SYS_PERIOD   6.0
set CLK_ACCEL_PERIOD 3.0

create_clock -name clk_sys   -period $CLK_SYS_PERIOD   [get_ports clk_sys]
create_clock -name clk_accel -period $CLK_ACCEL_PERIOD [get_ports clk_accel]

set_ideal_network [get_ports {clk_sys clk_accel}]
set_ideal_network [get_nets -hierarchical *clk_sys*]
set_ideal_network [get_nets -hierarchical *clk_accel*]

set_clock_uncertainty -setup 0.10 [get_clocks clk_sys]
set_clock_uncertainty -hold  0.05 [get_clocks clk_sys]
set_clock_uncertainty -setup 0.10 [get_clocks clk_accel]
set_clock_uncertainty -hold  0.05 [get_clocks clk_accel]

# BUGFIX: was "0.15[get_clocks clk_sys]" (no space) -- in Tcl, [...] command
# substitution glues directly onto adjacent text, so that parsed as ONE
# malformed argument ("0.15" concatenated with the stringified clock
# collection) instead of the two arguments set_clock_transition expects
# (a value and a clock list). Space added below on both lines.
set_clock_transition 0.15 [get_clocks clk_sys]
set_clock_transition 0.15 [get_clocks clk_accel]

# -----------------------------------------------------------------------------
# 2. Input & Output Delay Constraints
# -----------------------------------------------------------------------------
set IN_DELAY  [expr {$CLK_SYS_PERIOD * 0.20}]
set OUT_DELAY [expr {$CLK_SYS_PERIOD * 0.20}]

set clk_ports         [get_ports {clk_sys clk_accel}]
set all_inputs_no_clk [remove_from_collection [all_inputs] $clk_ports]

set_input_delay -max $IN_DELAY -clock clk_sys $all_inputs_no_clk
set_input_delay -min 0.0       -clock clk_sys $all_inputs_no_clk

set_output_delay -max $OUT_DELAY -clock clk_sys [all_outputs]
set_output_delay -min -0.05      -clock clk_sys [all_outputs]

# -----------------------------------------------------------------------------
# 3. Global Design Rule Constraints (DRCs)
# -----------------------------------------------------------------------------
set_max_transition  0.20 [current_design]
set_max_capacitance 4.00 [current_design]
set_max_fanout       20  [current_design]

# -----------------------------------------------------------------------------
# 4. Boundary Environment Settings
# -----------------------------------------------------------------------------
set_driving_cell -lib_cell NBUFFX2_RVT $all_inputs_no_clk
set_load 0.004 [all_outputs]

# -----------------------------------------------------------------------------
# 5. Timing Exceptions
# -----------------------------------------------------------------------------
# Async resets - ignore setup/hold on the static reset assertion
foreach rst_port {rst_sys_n rst_accel_n} {
    if {[llength [get_ports -quiet $rst_port]] > 0} {
        set_false_path -from [get_ports $rst_port]
    }
}

# Cross-clock-domain paths (clk_sys <-> clk_accel) go through async_fifo's
# Gray-code synchronizers - these should NOT be timed as synchronous paths.
set_clock_groups -asynchronous -group [get_clocks clk_sys] -group [get_clocks clk_accel]
