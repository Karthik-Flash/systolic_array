# ooc_check.tcl -- T2_PLAN sec. 8.3: out-of-context synthesis of each RM + resource/timing gates.
# Run from vivado/scratch_t2/ so journals, logs and .Xil/ stay in the scratch folder:
#   cd D:/Projects/RC_Project/vivado/scratch_t2
#   C:/Xilinx/Vivado/2022.2/bin/vivado.bat -mode batch -source ../../scripts/t2/ooc_check.tcl
# Writes docs/t2/reports/ooc_<rm>_utilization.rpt, ooc_<rm>_timing.rpt, ooc_summary.csv.
# Gates: DSP 16/0/0, LUT <= 2200, BRAM 0, est. WNS > 0 (warn < +1.5 ns for int16/int8).
# Counts are read from report_utilization text, never from PRIMITIVE_GROUP filters (T1 bug #3).

source [file join [file dirname [info script]] t2_filesets.tcl]
set root $::T2_ROOT
set out  $root/docs/t2/reports
file mkdir $out

set exp_dsp {rm_int16 16 rm_int8 0 rm_int4 0}
set lut_max 2200
set warn_wns {rm_int16 1.5 rm_int8 1.5 rm_int4 0.0}

# first number after "| <label>" in a report_utilization table, e.g. "| Slice LUTs* | 850 |"
proc util_num {rpt label} {
    if {[regexp -line "^\\|\\s*${label}\\*?\\s*\\|\\s*(\[0-9.\]+)" $rpt -> n]} { return $n }
    error "no '$label' row in report_utilization"
}

set rows {}
set ok 1
foreach rm $::T2_RMS {
    create_project -in_memory -part $::T2_PART
    foreach f $::T2_RM_FILES($rm) { read_verilog $root/$f }
    synth_design -mode out_of_context -top rp_t2 -part $::T2_PART
    create_clock -period 10.000 -name clk [get_ports clk]

    report_utilization -file $out/ooc_${rm}_utilization.rpt
    report_timing_summary -file $out/ooc_${rm}_timing.rpt
    set u [report_utilization -return_string]
    set lut  [util_num $u "Slice LUTs"]
    set ff   [util_num $u "Slice Registers"]
    set dsp  [util_num $u "DSPs"]
    set bram [util_num $u "Block RAM Tile"]
    set wns  [get_property SLACK [get_timing_paths -setup -max_paths 1 -nworst 1]]

    set v {}
    set g_dsp  [expr {$dsp == [dict get $exp_dsp $rm]}]
    set g_lut  [expr {$lut <= $lut_max}]
    set g_bram [expr {$bram == 0}]
    set g_wns  [expr {$wns ne "" && $wns > 0}]
    foreach {name g} [list DSP $g_dsp LUT $g_lut BRAM $g_bram WNS $g_wns] {
        lappend v "$name:[expr {$g ? {PASS} : {FAIL}}]"
        if {!$g} { set ok 0 }
    }
    set warn [expr {$g_wns && $wns < [dict get $warn_wns $rm] ? "WNS<[dict get $warn_wns $rm]ns" : ""}]
    lappend rows [list $rm $lut $ff $dsp $bram $wns [join $v " "] $warn]
    close_project
}

set fh [open $out/ooc_summary.csv w]
puts $fh "rm,lut,ff,dsp,bram,wns_est_ns,gates,warn"
foreach r $rows { puts $fh [join $r ","] }
close $fh

puts "==== T2 OOC check ===="
foreach r $rows {
    puts [format "%-9s LUT %5s  FF %5s  DSP %3s  BRAM %3s  WNS %7s  %s %s" {*}$r]
}
puts [expr {$ok ? "OOC PASS" : "OOC FAIL"}]
