# Signoff-style STA on the post-route / final design (sky130hd).
#
# Methodology mirrors ORFS final_report.tcl: read LEF/LIB, the routed DEF and
# its propagated-clock SDC, then use the OpenRCX-extracted SPEF for parasitics
# (identical RC to ORFS signoff). If finish hasn't run yet, fall back to
# global-route parasitic estimation so `make sta` still works post-route.
#
# Env in:  RESULTS_DIR  PLATFORM_DIR
# Out:     worst-5 setup paths, worst-5 hold paths, clock skew, WNS/TNS, area, power

set res  $::env(RESULTS_DIR)
set pdir $::env(PLATFORM_DIR)

read_lef     $pdir/lef/sky130_fd_sc_hd.tlef
read_lef     $pdir/lef/sky130_fd_sc_hd_merged.lef
read_liberty $pdir/lib/sky130_fd_sc_hd__tt_025C_1v80.lib

# Use the most-final stage available: signoff (SPEF) > routed > post-CTS.
if {[file exists $res/6_final.def]} {
  set stage 6_final
} elseif {[file exists $res/5_route.def]} {
  set stage 5_route
} else {
  set stage 4_cts
}
read_def $res/$stage.def
read_sdc $res/$stage.sdc
set_propagated_clock [all_clocks]

if {[file exists $pdir/setRC.tcl]} { source $pdir/setRC.tcl }
if {$stage eq "6_final" && [file exists $res/6_final.spef]} {
  read_spef $res/6_final.spef
  puts "## design=$stage  parasitics=extracted-SPEF"
} elseif {$stage eq "4_cts"} {
  estimate_parasitics -placement
  puts "## design=$stage  parasitics=estimate(placement, pre-route)"
} else {
  estimate_parasitics -global_routing
  puts "## design=$stage  parasitics=estimate(global_routing)"
}

puts "\n===================== SETUP (max) : worst 5 endpoints ====================="
report_checks -path_delay max -group_count 5 -slack_max 1e30 \
  -fields {slew capacitance input_pins nets fanout} -format full_clock_expanded

puts "\n===================== HOLD (min) : worst 5 endpoints ======================"
report_checks -path_delay min -group_count 5 -slack_min -1e30 \
  -fields {slew capacitance input_pins nets fanout} -format full_clock_expanded

puts "\n===================== CLOCK SKEW (propagated) ====================="
report_clock_skew

puts "\n===================== WNS / TNS ====================="
puts "setup worst slack: [sta::worst_slack -max]"
puts "hold  worst slack: [sta::worst_slack -min]"
report_tns

puts "\n===================== AREA / POWER ====================="
report_design_area
report_power
