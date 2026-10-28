# ooc_check.tcl -- T1_PLAN §6.5: out-of-context synth of each RM -> LUT/FF/DSP sanity.
# Run from inside vivado/ so journals/logs land in the gitignored folder:
#   cd vivado
#   C:/Xilinx/Vivado/2022.2/bin/vivado.bat -mode batch -source ../scripts/t1/ooc_check.tcl
# Expect: rm_add 0 DSP, rm_mul 1 DSP.

set root [file normalize [file join [file dirname [info script]] ../..]]
set part xc7z020clg484-1
set expect_dsp [dict create add 0 mul 1]
set summary {}
set ok 1

foreach rm {add mul} {
    create_project -in_memory -part $part
    read_verilog $root/rtl/t1/rm/rm_$rm.v
    synth_design -mode out_of_context -top rp_t1 -part $part
    report_utilization
    set lut [llength [get_cells -hier -filter {PRIMITIVE_GROUP == LUT}]]
    set ff  [llength [get_cells -hier -filter {PRIMITIVE_GROUP == FLOP_LATCH}]]
    set dsp [llength [get_cells -hier -filter {REF_NAME == DSP48E1}]]
    set exp [dict get $expect_dsp $rm]
    set verdict [expr {$dsp == $exp ? "OK" : "UNEXPECTED (expected $exp DSP)"}]
    if {$dsp != $exp} { set ok 0 }
    lappend summary [format "rm_%-4s LUT %4d  FF %4d  DSP %d  %s" $rm $lut $ff $dsp $verdict]
    close_project
}

puts "==== T1 OOC check ===="
foreach line $summary { puts $line }
puts [expr {$ok ? "OOC PASS" : "OOC FAIL"}]
