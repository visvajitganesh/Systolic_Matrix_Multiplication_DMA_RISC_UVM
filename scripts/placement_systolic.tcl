set PDK_PATH /home/acts/Documents/References/ref
set LIB_DIR /home/DVLSI10/SYSTOLIC_LIB

open_lib $LIB_DIR
open_block SYSTOLIC_FP

set mode1 "func"
set corner1 "nom"
remove_modes -all; remove_corners -all; remove_scenarios -all

create_mode $mode1
create_corner $corner1
create_scenario -name func::nom -mode func -corner nom
current_mode func
current_scenario func::nom

read_sdc /home/DVLSI10/pd_group7/netlist/post_systolic_synth.sdc

set tluplus_filep1 "$PDK_PATH/tech/star_rcxt/saed32nm_1p9m_Cmax.tluplus"
set layer_map_filep1 "$PDK_PATH/tech/star_rcxt/saed32nm_tf_itf_tluplus.map"
set tluplus_filep2 "$PDK_PATH/tech/star_rcxt/saed32nm_1p9m_Cmin.tluplus"
set layer_map_filep2 "$PDK_PATH/tech/star_rcxt/saed32nm_tf_itf_tluplus.map"

read_parasitic_tech -tlup $tluplus_filep1 -layermap $layer_map_filep1 -name p1
read_parasitic_tech -tlup $tluplus_filep2 -layermap $layer_map_filep2 -name p2

set_parasitic_parameters -late_spec p1 -early_spec p2
set_app_options -name place.coarse.continue_on_missing_scandef -value true

place_pins -self
place_opt
legalize_placement

save_block -as systolic_placement
save_lib
