# Compile/elaborate real MIG integration without a long DDR calibration run.
source [file join [file dirname [info script]] setup_ddr3_sim.tcl]
if {[get_filesets -quiet sim_direct_check] eq ""} {
    create_fileset -simset sim_direct_check
}
foreach f [list $duplex_tb [file join $model_dir ddr3_model.sv] [file join $model_dir ddr3_model_parameters.vh]] {
    if {[get_files -quiet -of_objects [get_filesets sim_direct_check] $f] eq ""} {
        add_files -fileset sim_direct_check -norecurse $f
    }
}
set_property top testbench2 [get_filesets sim_direct_check]
set_property top_auto_set false [get_filesets sim_direct_check]
set_property verilog_define {x4Gb x16 sg125} [get_filesets sim_direct_check]
set_property include_dirs [list $model_dir] [get_filesets sim_direct_check]
set_property xsim.elaborate.debug_level off [get_filesets sim_direct_check]
update_compile_order -fileset sim_direct_check
current_fileset -simset [get_filesets sim_direct_check]
launch_simulation -simset sim_direct_check -mode behavioral -step compile
launch_simulation -simset sim_direct_check -mode behavioral -step elaborate
puts "PASS: testbench2 direct MIG elaboration"
close_project
