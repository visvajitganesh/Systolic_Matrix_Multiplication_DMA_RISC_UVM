check_design -checks pre_clock_tree_stage

synthesize_clock_tree

set_app_options -name cts.optimize.enable_local_skew -value true
set_app_options -name cts.compile.enable_local_skew -value true
set_app_options -name cts.compile.enable_global_route -value false
set_app_options -name clock_opt.flow.enable_ccd -value true

clock_opt -to build_clock

clock_opt -from route_clock -to route_clock
clock_opt

save_block -as systolic_cts_CCD
save_lib
