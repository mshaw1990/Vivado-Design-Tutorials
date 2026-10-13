#------------------------------------------------------------------------------
# Run the tutorial testbenches in the Vivado simulator from inside Vivado.
#
# From the Vivado Tcl console (GUI or "vivado -mode tcl"):
#   source <path>/Block_RAM_Fundamentals/scripts/run_sim.tcl
#
# or in batch mode:
#   vivado -mode batch -source scripts/run_sim.tcl
#
# Sourcing the script runs both testbenches and prints PASSED/FAILED for each.
# In the GUI, the last simulation stays open so you can look at the waveforms.
# Once sourced, you can rerun a single testbench with:
#   bram_sim tb_bram_tdp
#   bram_sim tb_bram_deep_buffer
#
# The script opens vivado_project/bram_7series.xpr, creating it with
# create_project.tcl first if it does not exist. Project mode adds the UNISIM
# library and glbl.v automatically.
#------------------------------------------------------------------------------
namespace eval ::bram_sim {
  variable script_dir [file dirname [file normalize [info script]]]
  variable root       [file dirname $script_dir]
  variable proj_name  bram_7series
  variable all_tests  {tb_bram_tdp tb_bram_deep_buffer}
}

# Make sure the tutorial project is the current project.
proc ::bram_sim::open_tutorial_project {} {
  variable script_dir
  variable root
  variable proj_name

  if {![catch {current_project} cur] && $cur eq $proj_name} {
    return
  }

  set xpr [file join $root vivado_project ${proj_name}.xpr]
  if {[file exists $xpr]} {
    puts "INFO: Opening $xpr"
    open_project $xpr
  } else {
    puts "INFO: Creating the tutorial project"
    source [file join $script_dir create_project.tcl]
  }
}

# Run one or more testbenches. Returns the number of failing testbenches.
#   tests      : list of testbench top modules (default: all)
#   keep_open  : 1 leaves the last simulation open for waveform viewing
proc bram_sim {{tests ""} {keep_open 1}} {
  if {$tests eq ""} {
    set tests $::bram_sim::all_tests
  }

  ::bram_sim::open_tutorial_project

  set simset  [get_filesets sim_1]
  set sim_dir [file join [get_property DIRECTORY [current_project]] \
                         "[current_project].sim" sim_1 behav xsim]
  set results [list]
  set failed  0

  # Run each testbench until it calls $finish.
  set_property -name xsim.simulate.runtime -value all -objects $simset

  foreach tb $tests {
    catch {close_sim -force -quiet}

    puts "=============================================================="
    puts " Simulating $tb"
    puts "=============================================================="
    set_property top     $tb            $simset
    set_property top_lib xil_defaultlib $simset
    update_compile_order -fileset sim_1

    set log [file join $sim_dir simulate.log]
    file delete -force $log

    if {[catch {launch_simulation -simset sim_1 -mode behavioral} err]} {
      puts "ERROR: launch_simulation failed for $tb:\n$err"
      lappend results [list $tb "FAILED (did not run)"]
      incr failed
      continue
    }

    # Each testbench sets test_passed = 1 just before $finish if every check
    # passed. Read it from the simulation; fall back to the log file.
    set status "FAILED (no result, see $log)"
    if {![catch {get_value -radix unsigned /$tb/test_passed} v]} {
      set status [expr {$v eq "1" ? "PASSED" : "FAILED (test_passed = $v)"}]
    } elseif {[file exists $log]} {
      set fh [open $log r]
      set text [read $fh]
      close $fh
      if {[string first "TEST PASSED" $text] >= 0} {
        set status "PASSED"
      } elseif {[string first "TEST FAILED" $text] >= 0} {
        set status "FAILED (see $log)"
      }
    }
    if {$status ne "PASSED"} {
      incr failed
    }
    lappend results [list $tb $status]

    if {!$keep_open || $tb ne [lindex $tests end]} {
      close_sim -force -quiet
    }
  }

  puts "=============================================================="
  puts " Simulation summary"
  puts "=============================================================="
  foreach r $results {
    puts [format "  %-22s %s" [lindex $r 0] [lindex $r 1]]
  }
  puts "=============================================================="
  return $failed
}

bram_sim
