# Run from the Vivado GUI Tcl Console. Release the current simulation first.
# close_sim reports an error when no simulation is open, which is harmless here.
catch {close_sim}
source [file join [file dirname [info script]] setup_testbench2.tcl]
launch_simulation -simset sim_duplex -mode behavioral
