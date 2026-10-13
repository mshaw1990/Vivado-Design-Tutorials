#------------------------------------------------------------------------------
# Create a Vivado project with all the sources, for GUI simulation and browsing.
#
#   vivado -source scripts/create_project.tcl
#
# Then use Flow Navigator > Run Simulation. To switch testbench, right-click
# tb_bram_deep_buffer in the Simulation Sources and choose Set as Top.
#
# The project goes in vivado_project/ next to the sources. On Windows, deep
# paths can exceed the 260-character limit inside the simulation directories.
# To put the project somewhere shorter, set this before sourcing:
#   set ::bram_project_dir D:/vp
#------------------------------------------------------------------------------
set script_dir [file dirname [file normalize [info script]]]
set root       [file dirname $script_dir]
set part       xc7v2000tflg1925-2

if {[info exists ::bram_project_dir]} {
  set proj_dir [file normalize $::bram_project_dir]
} else {
  set proj_dir [file join $root vivado_project]
}

create_project bram_7series $proj_dir -part $part -force

add_files -norecurse [glob [file join $root hdl *.v]]
add_files -fileset sim_1 -norecurse [glob [file join $root sim *.v]]

set_property top bram_deep_buffer [get_filesets sources_1]
set_property top tb_bram_tdp      [get_filesets sim_1]
set_property -name xsim.simulate.runtime -value all -objects [get_filesets sim_1]

# Vivado keeps the compile order up to date by itself, so a failure here is
# not fatal. On Windows it can fail with "Spawn failed: No error".
foreach fs {sources_1 sim_1} {
  if {[catch {update_compile_order -fileset $fs} err]} {
    puts "WARNING: update_compile_order -fileset $fs failed, continuing:\n$err"
  }
}

puts "Project created in $proj_dir"
