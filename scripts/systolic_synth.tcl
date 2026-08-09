# ---------- Library setup ----------
set LIB_DIR "/study/Testcase_C-DAC_july24/Testcase_C-DAC_july24/C-DAC_july24/ref/lib/stdcell_rvt"

set search_path ". $LIB_DIR"
set target_library "saed32rvt_ss0p7vn40c.db"
set link_library "* saed32rvt_ss0p7vn40c.db saed32rvt_tt0p78vn40c.db saed32rvt_ff1p16v125c.db"

# ---------- Design library ----------
define_design_lib WORK -path ./WORK

# ---------- Read RTL ----------
set RTL_DIR "/home/DVLSI10/pd_group7/rtl"

analyze -format sverilog [glob $RTL_DIR/systolic_array.sv]

elaborate systolic
current_design systolic
link

# ---------- Read constraints ----------
read_sdc /home/DVLSI10/pd_group7/sdc/systolic.sdc

# ---------- Checks ----------
check_design
check_timing

# ---------- Compile ----------
compile_ultra -timing_high_effort

# ---------- Write netlist ----------
set NET_DIR "/home/DVLSI10/pd_group7/netlist"

write_file -format verilog -hierarchy -output $NET_DIR/systolic_netlist.v
write_sdc  $NET_DIR/post_systolic_synth.sdc

# ---------- Reports ----------
report_timing -path full -delay max -max_paths 1 > $NET_DIR/systolic_timing.rpt
report_area   > $NET_DIR/systolic_area.rpt
report_power  > $NET_DIR/systolic_power.rpt
report_qor    > $NET_DIR/systolic_qor.rpt

quit
