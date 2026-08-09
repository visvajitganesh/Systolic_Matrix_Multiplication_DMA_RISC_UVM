#######################################################################
# SDC Constraints for dma_top
# Target Technology : SAED32nm Educational Standard Cell Library
#                      (e.g. saed32nm_typ.db / saed32rvt_tt0p85v25c)
#
# Single clock domain design:
#   - clk    : system clock, drives all AXI-Lite / AXI4 / AXI-Stream I/O
#   - rst_n  : asynchronous, active-low reset
#
# NOTE: target_library / link_library setup (saed32nm_typ.db, wireload
# model, operating conditions such as tt0p85v25c) belongs in your
# dc_shell / Design Compiler synthesis script, not in this SDC. This
# file assumes that library is already loaded and its cell names
# (INVX*, BUFX*) are resolvable.
#######################################################################

#############################
# 1. Clock Definition
#############################
# SAED32nm control-plane logic like this DMA (simple FSMs, 32-bit
# compares/adders, no deep combinational chains) typically closes
# comfortably in the 500MHz - 1GHz range at the tt0p85v25c corner.
# 1.5 ns (~667 MHz) is a reasonable, safe starting target; tighten
# once you've seen a clean STA report.
set CLK_PERIOD  8.500
set CLK_NAME    clk

create_clock -name $CLK_NAME -period $CLK_PERIOD [get_ports clk]

# Jitter/margin budget scaled for 32nm (much smaller absolute numbers
# than a board-level 10ns/100MHz constraint would use)
set_clock_uncertainty -setup 0.060 [get_clocks $CLK_NAME]
set_clock_uncertainty -hold  0.030 [get_clocks $CLK_NAME]
set_clock_transition  0.020 [get_clocks $CLK_NAME]

#############################
# 2. Asynchronous Reset
#############################
# rst_n only feeds the async negedge-sensitive reset input of every
# always_ff block -> not a data path, exclude from setup/hold timing.
set_false_path -from [get_ports rst_n]

#############################
# 3. Input Delays
#############################
# External AXI master/slave assumed synchronous to the same clk.
# 20% of period budget for max (setup), 5% for min (hold) is a
# standard starting ratio; tighten once the real interconnect timing
# is known.
set IN_DELAY_MAX  [expr {$CLK_PERIOD * 0.20}]
set IN_DELAY_MIN  [expr {$CLK_PERIOD * 0.05}]

set all_in_ports [get_ports {
    s_axi_lite_awaddr   s_axi_lite_awvalid
    s_axi_lite_wdata    s_axi_lite_wvalid
    s_axi_lite_bready
    s_axi_lite_araddr   s_axi_lite_arvalid
    s_axi_lite_rready
    m_axi_arready
    m_axi_rdata         m_axi_rvalid
    m_axi_awready
    m_axi_wready
    m_axi_bvalid
    m_axis_mm2s_tready
    s_axis_s2mm_tdata   s_axis_s2mm_tvalid
}]

set_input_delay -clock $CLK_NAME -max $IN_DELAY_MAX $all_in_ports
set_input_delay -clock $CLK_NAME -min $IN_DELAY_MIN $all_in_ports

#   Interfaces covered by the wildcard above:
#     AXI4-Lite slave  : s_axi_lite_awaddr/awvalid, s_axi_lite_wdata/wvalid,
#                         s_axi_lite_bready, s_axi_lite_araddr/arvalid,
#                         s_axi_lite_rready
#     AXI4 master      : m_axi_arready, m_axi_rdata/rvalid,
#                         m_axi_awready, m_axi_wready, m_axi_bvalid
#     AXI4-Stream MM2S : m_axis_mm2s_tready
#     AXI4-Stream S2MM : s_axis_s2mm_tdata/tvalid

#############################
# 4. Output Delays
#############################
set OUT_DELAY_MAX [expr {$CLK_PERIOD * 0.20}]
set OUT_DELAY_MIN [expr {$CLK_PERIOD * 0.05}]

set_output_delay -clock $CLK_NAME -max $OUT_DELAY_MAX [all_outputs]
set_output_delay -clock $CLK_NAME -min $OUT_DELAY_MIN [all_outputs]

#   Interfaces covered:
#     AXI4-Lite slave  : s_axi_lite_awready/wready/bresp/bvalid,
#                         s_axi_lite_arready/rdata/rresp/rvalid
#     AXI4 master      : m_axi_araddr/arlen/arvalid, m_axi_rready,
#                         m_axi_awaddr/awlen/awvalid,
#                         m_axi_wdata/wvalid/wlast, m_axi_bready
#     AXI4-Stream MM2S : m_axis_mm2s_tdata/tvalid
#     AXI4-Stream S2MM : s_axis_s2mm_tready

#############################
# 5. Driving Cell / Load (SAED32nm cell names)
#############################
# BUFX2 is a standard, moderate-strength driver in the SAED32nm kit;
# used here to model a realistic input transition instead of an ideal
# zero-impedance driver. Swap for whatever actually drives these pins
# upstream (e.g. another block's output stage) once known.
set_driving_cell -lib_cell BUFX2 -pin Z $all_in_ports

# Output load modeled as ~2 INVX1 input pins (SAED32nm INVX1 input cap
# is ~0.9 fF per pin in the typical corner) -> ~0.002 pF. Replace with
# set_load [load_of <lib>/INVX1/IN] * <fanout> once the library is
# loaded in your session, or with the real downstream receiver load.
set_load 0.002 [all_outputs]

#############################
# 6. Max Transition / Max Fanout (design-wide defaults)
#############################
# SAED32nm typical guidance: keep transitions well under ~10-15% of
# the clock period, and fanout under the library's default max (~20
# for standard drive-strength cells).
set_max_transition 0.150 [current_design]
set_max_fanout      16   [current_design]

#############################
# 7. Exceptions
#############################
# No additional multicycle or false paths identified. reg_ctrl/
# reg_src_addr/reg_dest_addr/reg_xfer_len are single-clock-domain
# registers written by the AXI-Lite slave logic and read by the
# MM2S/S2MM engines within the same clk domain -> normal single-cycle
# timing applies, no CDC exceptions needed.
