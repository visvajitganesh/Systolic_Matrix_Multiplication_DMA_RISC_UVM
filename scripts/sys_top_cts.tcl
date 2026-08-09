###############################################################################
# ICC2 CLOCK TREE SYNTHESIS (CTS) SCRIPT
# Design: system_top
###############################################################################

puts "======================================================================"
puts "              ICC2 CLOCK TREE SYNTHESIS - SAED32"
puts "======================================================================"

set DESIGN_NAME system_top
set PD_ROOT     /home/DVLSI10/pd_group7
set LIB_PATH    "${PD_ROOT}/${DESIGN_NAME}_LIB"

puts "======================================================================"
puts "1. CTS SETUP & DESIGN LOADING"
puts "======================================================================"

# Safe block closing without trigger errors
if {[sizeof_collection [get_blocks -quiet]] > 0} {
    close_blocks -force [get_blocks]
}

# Ensure library is open
if {[get_libs -quiet ${DESIGN_NAME}_LIB] eq ""} {
    open_lib $LIB_PATH
}

# Open the placed design block
if {[catch { open_block ${DESIGN_NAME}_LIB:${DESIGN_NAME}_placed } err]} {
    return -code error "Could not open ${DESIGN_NAME}_placed. Make sure placement is saved as system_top_placed!"
}

puts "===== CURRENT DESIGN ====="
current_design

puts "===== CLOCKS ====="
report_clock

###############################################################################
# 2. CTS CELL PURPOSE CONFIGURATION
###############################################################################

puts "======================================================================"
puts "2. CONFIGURING CTS CELLS"
puts "======================================================================"

# Clock buffers
set_lib_cell_purpose -include cts [get_lib_cells */NBUFFX2_RVT]
set_lib_cell_purpose -include cts [get_lib_cells */NBUFFX4_RVT]
set_lib_cell_purpose -include cts [get_lib_cells */NBUFFX8_RVT]
set_lib_cell_purpose -include cts [get_lib_cells */NBUFFX16_RVT]

# Clock inverters
set_lib_cell_purpose -include cts [get_lib_cells */INVX1_RVT]
set_lib_cell_purpose -include cts [get_lib_cells */INVX2_RVT]
set_lib_cell_purpose -include cts [get_lib_cells */INVX4_RVT]
set_lib_cell_purpose -include cts [get_lib_cells */INVX8_RVT]

###############################################################################
# 3. RUN CLOCK_OPT
###############################################################################

puts "======================================================================"
puts "3. RUNNING CLOCK_OPT"
puts "======================================================================"

catch { set_app_options -name clock_opt.flow.enable_power -value false }

clock_opt

###############################################################################
# 4. REPORT & SAVE
###############################################################################

puts "======================================================================"
puts "4. POST-CTS REPORTS AND SAVE"
puts "======================================================================"

report_clock -skew
report_timing -delay_type max -max_paths 10
report_timing -delay_type min -max_paths 10

save_block -as ${DESIGN_NAME}_CTS
save_lib

puts "======================================================================"
puts "              CTS FLOW COMPLETED SUCCESSFULLY"
puts "======================================================================"