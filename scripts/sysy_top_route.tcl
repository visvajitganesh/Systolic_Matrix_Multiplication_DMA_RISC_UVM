###############################################################################
# ICC2 ROUTING SCRIPT - SAED 32nm
# Design : system_top
# Stage  : Global/Detail Routing + Post-Route Optimization & DRC Fixing
# ICC2   : V-2023.12
###############################################################################

puts "======================================================================"
puts "              ICC2 ROUTING - SAED32"
puts "======================================================================"

set DESIGN_NAME system_top
set PD_ROOT     /home/DVLSI10/pd_group7
set LIB_PATH    "${PD_ROOT}/${DESIGN_NAME}_LIB"

###############################################################################
# 1. ROUTING SETUP & AUTOMATED BLOCK LOADING
###############################################################################

puts "======================================================================"
puts "1. ROUTE SETUP & DESIGN LOADING"
puts "======================================================================"

# Close open blocks safely
if {[sizeof_collection [get_blocks -quiet]] > 0} {
    close_blocks -force [get_blocks]
}

# Open library if necessary
if {[get_libs -quiet ${DESIGN_NAME}_LIB] eq ""} {
    open_lib $LIB_PATH
}

# Open the post-CTS block
if {[catch { open_block ${DESIGN_NAME}_LIB:${DESIGN_NAME}_CTS } err]} {
    return -code error "Could not open ${DESIGN_NAME}_CTS. Verify CTS completed and saved system_top_CTS!"
}

puts "===== CURRENT DESIGN ====="
current_design

puts "===== CLOCKS (Verifying propagated clocks 'p') ====="
report_clock

###############################################################################
# 2. PRE-ROUTE CHECKS
###############################################################################

puts "======================================================================"
puts "2. PRE-ROUTE LEGALITY & QoR CHECK"
puts "======================================================================"

check_legality
report_qor

###############################################################################
# 3. GLOBAL + DETAIL ROUTING (route_auto)
###############################################################################

puts "======================================================================"
puts "3. RUNNING ROUTE_AUTO (GLOBAL & DETAIL ROUTE)"
puts "======================================================================"

# Standard Routing Engine Call
route_auto

puts "route_auto completed successfully."

###############################################################################
# 4. INITIAL POST-ROUTE DRC CHECK
###############################################################################

puts "======================================================================"
puts "4. INITIAL POST-ROUTE DRC CHECK"
puts "======================================================================"

check_routes

###############################################################################
# 5. POST-ROUTE OPTIMIZATION (route_opt)
###############################################################################

puts "======================================================================"
puts "5. RUNNING POST-ROUTE ROUTE_OPT (TIMING, HOLD & DRC FIXING)"
puts "======================================================================"

# Optimizes timing, fixes hold violations, and resolves antenna/DRC issues
route_opt

puts "post-route route_opt completed successfully."

###############################################################################
# 6. POST-ROUTE TIMING & QoR
###############################################################################

puts "======================================================================"
puts "6. POST-ROUTE TIMING & QoR REPORTS"
puts "======================================================================"

report_timing -delay_type max -max_paths 20 -path_type full_clock_expanded
report_timing -delay_type min -max_paths 20 -path_type full_clock_expanded
report_qor

###############################################################################
# 7. FINAL LEGALITY & DRC VERIFICATION
###############################################################################

puts "======================================================================"
puts "7. FINAL DRC & LEGALITY CHECK"
puts "======================================================================"

check_legality
check_routes

###############################################################################
# 8. SAVE DESIGN
###############################################################################

puts "======================================================================"
puts "8. SAVING POST-ROUTE DESIGN"
puts "======================================================================"

save_block -as ${DESIGN_NAME}_ROUTE
save_lib

puts "======================================================================"
puts "              ROUTING FLOW COMPLETED SUCCESSFULLY"
puts "              DESIGN: system_top_ROUTE"
puts "======================================================================"