source [file join [file dirname [info script]] setup_ddr3_sim.tcl]
# A separate simulation set avoids overwriting logs of an open sim_1 session.
if {[get_filesets -quiet sim_duplex] eq ""} { create_fileset -simset sim_duplex }
foreach f [list $duplex_tb [file join $model_dir ddr3_model.sv] [file join $model_dir ddr3_model_parameters.vh]] {
    if {[get_files -quiet -of_objects [get_filesets sim_duplex] $f] eq ""} {
        add_files -fileset sim_duplex -norecurse $f
    }
}
set_property top testbench2 [get_filesets sim_duplex]
set_property top_auto_set false [get_filesets sim_duplex]
set_property verilog_define {x4Gb x16 sg125} [get_filesets sim_duplex]
set_property include_dirs [list $model_dir] [get_filesets sim_duplex]
set_property xsim.simulate.runtime 2ms [get_filesets sim_duplex]
set_property xsim.elaborate.debug_level typical [get_filesets sim_duplex]
current_fileset -simset [get_filesets sim_duplex]
update_compile_order -fileset sim_duplex
