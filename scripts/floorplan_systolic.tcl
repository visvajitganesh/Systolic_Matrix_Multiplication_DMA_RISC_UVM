set PDK_PATH /home/acts/Documents/References/ref
set LIB_DIR /home/DVLSI10/SYSTOLIC_LIB

if {[file exists $LIB_DIR]} {
    open_lib $LIB_DIR
} else {
    create_lib -ref_lib $PDK_PATH/lib/ndm/saed32rvt_c.ndm SYSTOLIC_LIB
}

read_verilog /home/DVLSI10/pd_group7/netlist/systolic_netlist.v -library SYSTOLIC_LIB -design systolic -top systolic

initialize_floorplan -core_utilization 0.55 -core_offset {2 2}
place_pins -self
create_placement -floorplan

save_block -as SYSTOLIC_FP
save_lib
