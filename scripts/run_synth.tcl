###############################################################################
# Synthesis script (dc_shell) for system_top
#
# Usage: dc_shell -f synth_system_top.tcl | tee synth_system_top.log
###############################################################################

# ==============================================================================
# 1. Setup
# ==============================================================================
remove_design -all

set RTL_DIR /home/DVLSI10/pd_group7/rtl
set SDC_DIR /home/DVLSI10/pd_group7/sdc

set search_path [list . $RTL_DIR $search_path]

set target_library "/home/acts/Documents/References/ref/lib/stdcell_rvt/saed32rvt_tt0p78vn40c.db"
set link_library   "* $target_library"

define_design_lib WORK -path ./WORK

# ==============================================================================
# 2. Analyze
# ==============================================================================
# Full file list, in dependency order (leaf modules first). The previous
# version of this list was missing input_fifo.sv and output_fifo.sv --
# accel_fifo.sv instantiates both directly (u_input_fifo / u_output_fifo),
# so without them `elaborate system_top` would fail to resolve those
# module references.
analyze -format sverilog -library WORK [list \
    $RTL_DIR/dff.sv \
    $RTL_DIR/d_ff_chain.sv \
    $RTL_DIR/processing_element.sv \
    $RTL_DIR/pe_array.sv \
    $RTL_DIR/systolic.sv \
    $RTL_DIR/async_fifo.sv \
    $RTL_DIR/input_fifo.sv \
    $RTL_DIR/output_fifo.sv \
    $RTL_DIR/accel_fifo.sv \
    $RTL_DIR/dma_bram.sv \
    $RTL_DIR/system_top.sv \
]

# ==============================================================================
# 3. Elaborate & Link
# ==============================================================================
elaborate system_top -library WORK
current_design system_top
link

# Catch unresolved references / multiply-driven nets / other structural
# problems before spending time applying constraints or compiling.
check_design

# ==============================================================================
# 4. Apply Constraints
# ==============================================================================
# Constraints MUST be sourced before any timing analysis (check_timing,
# report_timing) or compile -- an earlier version of this script ran
# check_timing and several report_timing calls BEFORE sourcing the SDC,
# meaning they executed against a design with no clocks/exceptions applied
# at all (meaningless/empty results). Fixed ordering below.
source $SDC_DIR/system_top.sdc

# Sanity-check that the constraints are well-formed now that they're
# applied (catches missing clocks, unconstrained paths, etc.) before
# burning compile time on an incompletely-constrained design.
check_timing

# ==============================================================================
# 5. Compile
# ==============================================================================
compile_ultra

# ==============================================================================
# 6. Post-Synthesis Reports
# ==============================================================================
# QoR snapshot (WNS/TNS/violating path count) first, then constraint
# violations, then detailed timing (worst path, then per-domain and
# per-path-group breakdowns), then min-delay (hold) checks.
report_qor
report_constraint -all_violators

# Worst setup path, full detail
report_timing -delay_type max -max_paths 1 -path_type full_clock

# Worst N setup paths within each clock's own domain, so you can see
# margin across many endpoints, not just the single worst
report_timing -delay_type max -max_paths 10 -from [get_clocks clk_sys]   -to [get_clocks clk_sys]   -sort_by slack
report_timing -delay_type max -max_paths 10 -from [get_clocks clk_accel] -to [get_clocks clk_accel] -sort_by slack

# Worst hold paths, same breakdown
report_timing -delay_type min -max_paths 10 -from [get_clocks clk_sys]   -to [get_clocks clk_sys]   -sort_by slack
report_timing -delay_type min -max_paths 10 -from [get_clocks clk_accel] -to [get_clocks clk_accel] -sort_by slack

report_area