###############################################################################
# ICC2 CHIP FINISHING & SIGNOFF PREP SCRIPT - SAED 32nm
# Design : system_top
# Stage  : Metal Fill + Final DRC/Connectivity Signoff + GDS/OASIS Streamout
# ICC2   : V-2023.12
###############################################################################
#
# PREREQUISITE - READ BEFORE SOURCING:
# This script assumes the currently open block is the POST-ROUTE design
# (e.g. system_top_ROUTE saved at the end of the routing script), with a
# clean check_routes / check_legality result already confirmed.
#
# To open the correct block first:
#   open_block <libname>:<libname>/system_top_ROUTE
#
###############################################################################
#
# CONFIDENCE NOTE: steps 1-2 and 6-8 use commands already confirmed working
# earlier in this flow (current_design, check_legality, report_qor,
# report_timing, save_block). Steps 3 (metal fill) and 5 (final GDS/OASIS
# streamout) use commands whose exact flags have NOT been verified against
# this specific ICC2 V-2023.12 install in this session - given how often
# guessed flags have been wrong so far, each is preceded by a '-help' call
# and wrapped so it reports rather than blindly assumes success.
#
###############################################################################

puts "======================================================================"
puts "              ICC2 CHIP FINISHING & SIGNOFF PREP - SAED32"
puts "======================================================================"

###############################################################################
# 1. SETUP
###############################################################################

puts "======================================================================"
puts "1. CHIP FINISHING SETUP"
puts "======================================================================"

current_design system_top

puts "===== CURRENT DESIGN ====="
current_design

###############################################################################
# 2. PRE-FINISHING SANITY CHECK
###############################################################################

puts "======================================================================"
puts "2. PRE-FINISHING LEGALITY + DRC CHECK"
puts "======================================================================"

check_legality
check_routes

###############################################################################
# 3. METAL FILL
###############################################################################

puts "======================================================================"
puts "3. METAL FILL"
puts "======================================================================"

# UNVERIFIED COMMAND NAME/FLAGS - run the -help line first and read its
# output before uncommenting the actual fill call below. Common ICC2
# candidates across versions: add_metal_fill, route_zrt_add_fill,
# insert_metal_fill. Do not assume any one of these is correct here.

puts "Checking available metal fill command syntax - run manually:"
puts "  add_metal_fill -help"
puts "  (or) route_zrt_add_fill -help"
puts "then replace the block below with the confirmed command/flags."

# Example guarded pattern once you know the real command name:
# if {[catch {add_metal_fill -help} err]} {
#     puts "add_metal_fill not available: $err"
# } else {
#     add_metal_fill
# }

###############################################################################
# 4. POST-FILL DRC CHECK
###############################################################################

puts "======================================================================"
puts "4. POST-FILL DRC + LEGALITY CHECK"
puts "======================================================================"

# Metal fill can introduce new spacing/DRC violations - re-check after
# step 3 is actually enabled and run.
check_routes
check_legality

###############################################################################
# 5. FINAL CONNECTIVITY / GDS-OASIS STREAMOUT
###############################################################################

puts "======================================================================"
puts "5. STREAMOUT"
puts "======================================================================"

# UNVERIFIED COMMAND NAME/FLAGS - confirm before running. Likely candidates
# in ICC2 V-2023.12: write_stream (GDSII/OASIS), possibly with -format,
# -library, -cell_map options. Run write_stream -help first.

puts "Checking available streamout command syntax - run manually:"
puts "  write_stream -help"
puts "then replace the block below with the confirmed command/flags."

# Example guarded pattern once you know the real command name:
# if {[catch {write_stream -help} err]} {
#     puts "write_stream not available: $err"
# } else {
#     write_stream -format gds -output system_top_final.gds
# }

###############################################################################
# 6. FINAL TIMING SIGNOFF REPORTS
###############################################################################

puts "======================================================================"
puts "6. FINAL MAX TIMING"
puts "======================================================================"

report_timing \
    -delay_type max \
    -max_paths 20 \
    -path_type full_clock_expanded

puts "======================================================================"
puts "6B. FINAL MIN TIMING"
puts "======================================================================"

report_timing \
    -delay_type min \
    -max_paths 20 \
    -path_type full_clock_expanded

###############################################################################
# 7. FINAL QoR
###############################################################################

puts "======================================================================"
puts "7. FINAL QoR"
puts "======================================================================"

report_qor

###############################################################################
# 8. SAVE FINAL DESIGN
###############################################################################

puts "======================================================================"
puts "8. SAVING FINAL SIGNED-OFF DESIGN"
puts "======================================================================"

save_block -as system_top_FINAL

###############################################################################
# COMPLETE
###############################################################################

puts "======================================================================"
puts "              CHIP FINISHING FLOW COMPLETED"
puts "              DESIGN: system_top_FINAL"
puts "======================================================================"
