source [file join [file dirname [info script]] setup_testbench2.tcl]
# Batch measurement does not need internal wave instrumentation.
set_property xsim.elaborate.debug_level off [get_filesets sim_duplex]
launch_simulation -simset sim_duplex -mode behavioral
set sim_log [file join $root K325T_DDR3_AXI4.sim sim_duplex behav xsim simulate.log]
set handle [open $sim_log r]
set sim_text [read $handle]
close $handle
if {![string match "*PASS: testbench2 concurrent read/write and post-write verification*" $sim_text]} {
    error "testbench2 assertions did not all complete successfully"
}
close_sim
set_property xsim.elaborate.debug_level typical [get_filesets sim_duplex]
close_project
