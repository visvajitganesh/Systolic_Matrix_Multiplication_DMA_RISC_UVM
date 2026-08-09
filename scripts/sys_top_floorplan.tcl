# ==============================================================================
# 5. Check Library
# ==============================================================================
puts ""
puts "============================================================"
puts "Checking library"
puts "============================================================"

# Catch library check so script execution continues smoothly
if {[catch {
    redirect -file $PNR_REPORTS/check_library.rpt { check_library }
} err]} {
    puts "Note: check_library logged warnings to $PNR_REPORTS/check_library.rpt"
}

# ==============================================================================
# 6. Floorplan Initialization
# ==============================================================================
puts ""
puts "============================================================"
puts "Floorplan Initialization"
puts "============================================================"

# Find available site definition dynamically
set site_defs [get_site_defs -quiet *]
if {[sizeof_collection $site_defs] == 0} {
    puts "ERROR: No site definitions found. Check the technology library."
    exit 1
}

set SITE_NAME [get_attribute [index_collection $site_defs 0] name]
puts "Using site definition: $SITE_NAME"

# Initialize floorplan
initialize_floorplan \
    -control_type core \
    -core_utilization 0.65 \
    -side_ratio {1.0 1.0} \
    -core_offset {5 5 5 5} \
    -site_def $SITE_NAME

# Set explicit metal layer preferred routing directions
set_attribute [get_layers {M1 M3 M5 M7 M9}] routing_direction horizontal
set_attribute [get_layers {M2 M4 M6 M8 MRDL}] routing_direction vertical

puts ""
puts "============================================================"
puts "Floorplan initialization completed"
puts "============================================================"

# ==============================================================================
# 7. Generate Reports
# ==============================================================================
puts ""
puts "============================================================"
puts "Generating floorplan reports"
puts "============================================================"

# Safely redirect outputs in ICC2
catch { redirect -file $PNR_REPORTS/report_design.rpt { report_design } }
catch { redirect -file $PNR_REPORTS/check_design.rpt  { check_design } }