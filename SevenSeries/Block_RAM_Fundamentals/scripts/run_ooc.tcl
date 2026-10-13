#------------------------------------------------------------------------------
# Out-of-context synthesis + implementation for one module, targeting
# xc7v2000tflg1925-2. Reports utilization (with the per-SLR table), timing,
# estimated Fmax and the number of BRAMs placed in each SLR.
#
# Usage (from the tutorial directory):
#   vivado -mode batch -source scripts/run_ooc.tcl -tclargs \
#          <top> [period_ns] [SLR0|SLR1|SLR2|SLR3|none] [GENERIC=VALUE ...]
#
# Examples:
#   # BRAM output register off vs on
#   ... -tclargs bram_fmax_harness 2.0 none DO_REG=0
#   ... -tclargs bram_fmax_harness 2.0 none DO_REG=1
#   # Same, using the instantiated primitive
#   ... -tclargs bram_fmax_harness 2.0 none DO_REG=1 USE_PRIM=1
#   # 64-bank (64K x 32) buffer, free placement, then locked to one SLR
#   ... -tclargs bram_deep_buffer 2.0 none
#   ... -tclargs bram_deep_buffer 2.0 SLR1
#   # 256 banks (256K x 32): most of one SLR's BRAM
#   ... -tclargs bram_deep_buffer 2.0 none AW=18
#
# Results are written to ooc_runs/<top>_<generics>_<slr>/.
#------------------------------------------------------------------------------
set script_dir [file dirname [file normalize [info script]]]
set root       [file dirname $script_dir]
set part       xc7v2000tflg1925-2

set top      [expr {[llength $argv] > 0 ? [lindex $argv 0] : "bram_deep_buffer"}]
set period   [expr {[llength $argv] > 1 ? [lindex $argv 1] : 2.0}]
set slr      [expr {[llength $argv] > 2 ? [lindex $argv 2] : "none"}]
set generics [lrange $argv 3 end]

set tag     [join [concat $top $generics $slr] _]
set run_dir [file join $root ooc_runs $tag]
file mkdir $run_dir

puts "=== OOC run: top=$top period=${period}ns slr=$slr generics=$generics"

# The clock constraint is written into the run directory so the period can be
# chosen on the command line.
set xdc [file join $run_dir clock.xdc]
set fh [open $xdc w]
puts $fh "create_clock -period $period -name clk \[get_ports clk\]"
close $fh

read_verilog [glob [file join $root hdl *.v]]
read_xdc -mode out_of_context $xdc

set synth_args [list -top $top -part $part -mode out_of_context]
foreach g $generics {
  lappend synth_args -generic $g
}
synth_design {*}$synth_args
write_checkpoint -force [file join $run_dir post_synth.dcp]
report_utilization -file [file join $run_dir post_synth_util.rpt]

#------------------------------------------------------------------------------
# Optional: lock the whole module into one SLR with a pblock that covers all
# of that SLR's clock regions.
#------------------------------------------------------------------------------
if {$slr ne "none"} {
  set xs {}
  set ys {}
  foreach cr [get_clock_regions -of_objects [get_slrs $slr]] {
    regexp {X(\d+)Y(\d+)} [get_property NAME $cr] -> x y
    lappend xs $x
    lappend ys $y
  }
  set xs [lsort -integer $xs]
  set ys [lsort -integer $ys]
  set range "CLOCKREGION_X[lindex $xs 0]Y[lindex $ys 0]:CLOCKREGION_X[lindex $xs end]Y[lindex $ys end]"
  puts "=== Constraining $top to $slr ($range)"
  create_pblock pb_slr
  resize_pblock pb_slr -add $range
  add_cells_to_pblock pb_slr -top
}

opt_design
place_design
phys_opt_design
route_design
write_checkpoint -force [file join $run_dir post_route.dcp]

report_utilization       -file [file join $run_dir post_route_util.rpt]
report_timing_summary    -max_paths 10 -file [file join $run_dir post_route_timing.rpt]
report_pulse_width       -file [file join $run_dir post_route_pulse_width.rpt]
catch {report_ram_utilization -file [file join $run_dir post_route_ram_util.rpt]}

#------------------------------------------------------------------------------
# Summary
#------------------------------------------------------------------------------
set n36 [llength [get_cells -quiet -hier -filter {REF_NAME == RAMB36E1}]]
set n18 [llength [get_cells -quiet -hier -filter {REF_NAME == RAMB18E1}]]

set per_slr [dict create]
foreach r [get_cells -quiet -hier -filter {REF_NAME =~ RAMB*}] {
  if {[catch {set s [get_slrs -of_objects [get_sites -of_objects $r]]}]} {
    set s "unknown"
  }
  set w [expr {[get_property REF_NAME $r] eq "RAMB36E1" ? 1.0 : 0.5}]
  if {![dict exists $per_slr $s]} {
    dict set per_slr $s 0.0
  }
  dict set per_slr $s [expr {[dict get $per_slr $s] + $w}]
}

set wns ""
set path [get_timing_paths -quiet -setup -max_paths 1]
if {[llength $path]} {
  set wns [get_property SLACK $path]
}

set fh [open [file join $run_dir summary.txt] w]
foreach chan [list stdout $fh] {
  puts $chan "================================================================"
  puts $chan " Summary: $tag"
  puts $chan "================================================================"
  puts $chan " Part              : $part"
  puts $chan " Target period     : $period ns ([format %.1f [expr {1000.0 / $period}]] MHz)"
  puts $chan " RAMB36E1 / 18E1   : $n36 / $n18  ([expr {$n36 + $n18 / 2.0}] RAMB36 equivalents)"
  dict for {s c} $per_slr {
    puts $chan "   BRAM in $s : $c RAMB36 equivalents"
  }
  if {$wns ne ""} {
    puts $chan " Setup WNS         : $wns ns"
    puts $chan " Estimated Fmax    : [format %.1f [expr {1000.0 / ($period - $wns)}]] MHz (setup only)"
  } else {
    puts $chan " Setup WNS         : no constrained paths"
  }
  puts $chan " Also check post_route_pulse_width.rpt: the BRAM minimum period"
  puts $chan " can limit Fmax even when the setup slack is positive."
  puts $chan "================================================================"
}
close $fh
