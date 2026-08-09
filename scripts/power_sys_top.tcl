# ==============================================================================
# 3. Create Power Ring (Top Metal: M8 & M9)
# ==============================================================================
puts "============================================================"
puts "Creating Power Rings"
puts "============================================================"

# Remove pre-existing PG strategies and patterns
remove_pg_strategies -all
remove_pg_patterns -all

create_pg_ring_pattern ring_pattern \
    -horizontal_layer M9 -horizontal_width {2.0} -horizontal_spacing {1.0} \
    -vertical_layer   M8 -vertical_width   {2.0} -vertical_spacing   {1.0}

set_pg_strategy ring_strategy \
    -pattern {{name: ring_pattern} {nets: {VDD VSS}}} \
    -core

compile_pg -strategies ring_strategy
# ==============================================================================
# 4. Create Power Mesh (Middle Metal: M5 & M6)
# ==============================================================================
puts "============================================================"
puts "Creating Power Mesh Straps"
puts "============================================================"

create_pg_mesh_pattern mesh_pattern \
    -layers { \
        { {horizontal_layer: M6} {width: 0.8} {spacing: 0.8} {pitch: 20.0} {offset: 5.0} } \
        { {vertical_layer:   M5} {width: 0.8} {spacing: 0.8} {pitch: 20.0} {offset: 5.0} } \
    }

set_pg_strategy mesh_strategy \
    -pattern {{name: mesh_pattern} {nets: {VDD VSS}}} \
    -core

compile_pg -strategies mesh_strategy

# ==============================================================================
# 5. Connect Standard-Cell M1 Rails
# ==============================================================================
puts "============================================================"
puts "Connecting Standard-Cell Rails"
puts "============================================================"

create_pg_std_cell_conn_pattern rail_pattern -layers {M1}

set_pg_strategy rail_strategy \
    -pattern {{name: rail_pattern} {nets: {VDD VSS}}} \
    -core

compile_pg -strategies rail_strategy