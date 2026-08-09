# ---------- Library setup ----------
set LIB_DIR "/study/Testcase_C-DAC_july24/Testcase_C-DAC_july24/C-DAC_july24/ref/lib/stdcell_rvt"
set search_path ". $LIB_DIR"
set target_library "saed32rvt_ss0p7vn40c.db"
set link_library "* saed32rvt_ss0p7vn40c.db saed32rvt_tt0p78vn40c.db saed32rvt_ff1p16v125c.db"

# ---------- Design library ----------
define_design_lib WORK -path ./WORK

# ---------- Read RTL ----------
set RTL_DIR "/home/DVLSI10/pd_group7/rtl"
analyze -format sverilog [glob $RTL_DIR/*.sv]
elaborate dma
current_design dma
link

# ---------- Read constraints ----------
read_sdc /home/DVLSI10/pd_group7/sdc/dma.sdc

# ---------- Datapath optimization hint (NEW) ----------
set_dp_smartgen_options -optimize_type1_datapath true

# ---------- Checks ----------
check_design
check_timing

# ---------- Compile ----------
compile_ultra -timing_high_effort

# ---------- Write netlist ----------
set NET_DIR "/home/DVLSI10/pd_group7/netlist"

write_file -format verilog -hierarchy -output $NET_DIR/dma_netlist.v
write_sdc  $NET_DIR/post_dma_synth.sdc

# ---------- Reports ----------
report_timing > $NET_DIR/timing.rpt
report_area   > $NET_DIR/area.rpt
report_power  > $NET_DIR/power.rpt
report_qor    > $NET_DIR/qor.rpt

quit
