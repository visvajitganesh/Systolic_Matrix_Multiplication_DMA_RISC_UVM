###############################################################################
# ICC2 Placement Script - SAED 32nm Flow
###############################################################################

puts "======================================================================"
puts "  1. LOADING SAED 32nm PARASITIC TECH FILES (TLU+)"
puts "======================================================================"

set tlup_max "/home/DVLSI10/SYSTOLIC_LIB/attach/lib.tech.parasitic.tlup/p1.saed32nm_1p9m_Cmax.tluplus"
set tlup_min "/home/DVLSI10/SYSTOLIC_LIB/attach/lib.tech.parasitic.tlup/p2.saed32nm_1p9m_Cmin.tluplus"

# Read parasitic technology files.
# They may already be loaded, so catch the duplicate-read messages.

catch {
    read_parasitic_tech \
        -tlup $tlup_max \
        -name tlup_max
}

catch {
    read_parasitic_tech \
        -tlup $tlup_min \
        -name tlup_min
}

# Associate early/late parasitic models.
catch {
    set_parasitic_parameters \
        -early_spec tlup_min \
        -late_spec tlup_max
}

puts "======================================================================"
puts "  2. CONFIGURING PLACEMENT OPTIONS"
puts "======================================================================"

# Do NOT use:
#   place_opt.initial_place.congestion_driven
#   place.coarse.congestion_driven
#
# Those options are not valid in this ICC2 version.

# Optional congestion-aware setting supported by newer ICC2 releases.
# If your version rejects this, simply comment it out.
catch {
    set_app_options \
        -name place.coarse.congestion_layer_aware \
        -value true
}

puts "======================================================================"
puts "  3. INITIAL CELL PLACEMENT"
puts "======================================================================"

# Congestion-driven initial placement.
create_placement \
    -floorplan \
    -congestion \
    -effort high

puts "======================================================================"
puts "  4. LEGALIZATION"
puts "======================================================================"

legalize_placement

puts "======================================================================"
puts "  5. PLACEMENT OPTIMIZATION"
puts "======================================================================"

# Full timing/congestion-aware placement optimization.
place_opt

puts "======================================================================"
puts "  6. PLACEMENT VERIFICATION"
puts "======================================================================"

check_legality

puts "======================================================================"
puts "  7. CONGESTION REPORT"
puts "======================================================================"

catch {
    report_congestion
}

puts "======================================================================"
puts "  8. SAVING BLOCK"
puts "======================================================================"

save_block

puts "======================================================================"
puts "  --> PLACEMENT FLOW COMPLETED"
puts "======================================================================"