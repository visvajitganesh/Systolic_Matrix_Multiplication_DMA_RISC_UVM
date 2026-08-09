###############################################################################
# ICC2 Technology Library Setup (icc2_shell) -- ONE-TIME, run once and reuse
#
# Usage: icc2_shell -f pnr_00_build_tech_lib.tcl | tee pnr_00_build_tech_lib.log
#
# Why this script exists separately: saed32rvt_c.ndm's embedded technology
# data is corrupted (TECH-018 "Line contains nested comments", ~20 errors
# across a huge line range) and fails to load via -technology in create_lib.
# The standalone legacy Milkyway tech file at
#   ref/tech/milkyway/saed32nm_1p9m_mw.tf
# is the real source of truth for the layer stack / routing rules and does
# not have this corruption. ICC2 needs it compiled into a proper NDM
# technology library once -- this script does that. Every subsequent
# design script (pnr_01_setup_floorplan.tcl, etc.) should then reference
# the NDM this produces, not the .tf directly and not saed32rvt_c.ndm's
# own -technology.
#
# IMPORTANT: run this from your own writable project space, not from
# inside /home/acts/Documents/References/ref -- that path is shared and
# you should not write into it.
###############################################################################

set PD_ROOT     /home/DVLSI10/pd_group7
set TECH_TF     /home/acts/Documents/References/ref/tech/milkyway/saed32nm_1p9m_mw.tf
set TECH_LIB_NAME saed32nm_TECH

cd $PD_ROOT

# Verify the source .tf actually exists at this path before attempting
# the conversion -- fail fast with a clear message rather than a cryptic
# LIB-007 further down if the path is wrong.
if {![file exists $TECH_TF]} {
    error "Technology source file not found: $TECH_TF -- confirm this path before proceeding."
}

# Session-state check, same reasoning as the design library: if this
# script is re-sourced in an already-open session, don't try to recreate
# an NDM tech library that's already open in memory.
if {[sizeof_collection [get_libs -quiet $TECH_LIB_NAME]] > 0} {
    puts "Technology library $TECH_LIB_NAME is already open in this session -- reusing it."
} else {
    create_lib -technology $TECH_TF $TECH_LIB_NAME
    save_lib
}

puts "\n*** Technology library ready: $PD_ROOT/$TECH_LIB_NAME ***"
puts "*** Point \$TECH_LIB at this path (not the .tf, not saed32rvt_c.ndm) in design scripts. ***\n"

close_lib
