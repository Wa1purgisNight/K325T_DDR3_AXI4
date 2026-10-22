# Source in simulation Tcl Console; then restart; run all.
foreach name {ui_clk ui_clk_sync_rst axi_aresetn init_calib_complete test_phase wr_busy rd_busy test_done test_pass} {
    add_wave /testbench2/$name
}
# Five channel groups are declared next to their driving tasks in testbench2.v.
add_wave /testbench2/axi_aw*
add_wave /testbench2/axi_w*
add_wave /testbench2/axi_b*
add_wave /testbench2/axi_ar*
add_wave /testbench2/axi_r*
