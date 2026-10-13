#------------------------------------------------------------------------------
# Create a Vivado project with all the sources, for GUI simulation and browsing.
#
#   vivado -source scripts/create_project.tcl
#
# Then use Flow Navigator > Run Simulation. To switch testbench, right-click
# tb_bram_deep_buffer in the Simulation Sources and choose Set as Top.
#------------------------------------------------------------------------------
set script_dir [file dirname [file normalize [info script]]]
set root       [file dirname $script_dir]
set part       xc7v2000tflg1925-2

create_project bram_7series [file join $root vivado_project] -part $part -force

add_files -norecurse [glob [file join $root hdl *.v]]
add_files -fileset sim_1 -norecurse [glob [file join $root sim *.v]]

set_property top bram_deep_buffer [get_filesets sources_1]
set_property top tb_bram_tdp      [get_filesets sim_1]
set_property -name xsim.simulate.runtime -value all -objects [get_filesets sim_1]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "Project created in [file join $root vivado_project]"
