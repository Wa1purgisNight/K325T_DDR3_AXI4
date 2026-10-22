# Direct testbench2 -> MIG simulation. Also repairs an already-open GUI project.
set root [file normalize [file join [file dirname [info script]] ..]]
if {[current_project -quiet] eq ""} {
    open_project [file join $root K325T_DDR3_AXI4.xpr]
}
set model_dir [file join $root K325T_DDR3_AXI4.gen sources_1 ip mig_7series_0 mig_7series_0 example_design sim]
foreach name {ddr3_axi_wr.v ddr3_axi_rd.v ddr3_driver.v ddr3_top.v tb_ddr3_driver.sv tb_ddr3_top.v axi_ram_model.v tb_ddr3_top_behav.wcfg} {
    set old_files [get_files -quiet */$name]
    if {$old_files ne ""} { remove_files $old_files }
}
set duplex_tb [file join $root K325T_DDR3_AXI4.srcs sim_1 new testbench2.v]
foreach f [list $duplex_tb [file join $model_dir ddr3_model.sv] [file join $model_dir ddr3_model_parameters.vh]] {
    if {[get_files -quiet -of_objects [get_filesets sim_1] $f] eq ""} {
        add_files -fileset sim_1 -norecurse $f
    }
}
set_property top mig_7series_0 [get_filesets sources_1]
set_property top_auto_set false [get_filesets sources_1]
set_property top testbench2 [get_filesets sim_1]
set_property top_auto_set false [get_filesets sim_1]
set_property verilog_define {x4Gb x16 sg125} [get_filesets sim_1]
set_property include_dirs [list $model_dir] [get_filesets sim_1]
set_property xsim.simulate.runtime 2ms [get_filesets sim_1]
set_property xsim.view {} [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
