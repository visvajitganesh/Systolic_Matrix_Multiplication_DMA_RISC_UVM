set LIB_DIR /home/DVLSI10/SYSTOLIC_LIB

open_lib $LIB_DIR
open_block systolic_pdn

set_app_options -name route.global.timing_driven -value true
set_app_options -name route.global.crosstalk_driven -value false

set_app_options -name route.track.timing_driven -value true
set_app_options -name route.track.crosstalk_driven -value true

set_app_options -name route.detail.timing_driven -value true
set_app_options -name route.detail.force_max_number_iterations -value false
set_app_options -name route.detail.antenna -value true
set_app_options -name route.detail.antenna_fixing_preference -value use_diodes
set_app_options -name route.detail.diode_libcell_names -value */ANTENNA_RVT

route_global
route_track
route_detail
route_opt

write_verilog /home/DVLSI10/pd_group7/results/systolic.routed.v
write_sdc -output /home/DVLSI10/pd_group7/results/systolic.routed.sdc
write_parasitics -format spef -output /home/DVLSI10/pd_group7/results/systolic_func_nom.spef

save_block -as systolic_routed
save_lib
