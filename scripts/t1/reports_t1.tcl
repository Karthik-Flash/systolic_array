# reports_t1.tcl -- T1_PLAN §9.2: per-config timing/utilization reports + pr_verify.
# Run from inside vivado/ (journals/logs stay in the gitignored folder):
#   cd vivado
#   C:/Xilinx/Vivado/2022.2/bin/vivado.bat -mode batch -source ../scripts/t1/reports_t1.tcl
# Writes docs/t1_reports/<cfg>_*.rpt and docs/t1_reports/pr_verify.rpt.

set root [file normalize [file join [file dirname [info script]] ../..]]
set runs $root/vivado/t1_dfx/t1_dfx.runs
set out  $root/docs/t1_reports
file mkdir $out

# run -> configuration (T1_PLAN §3)
set cfgs {impl_1 cfg_add child_0_impl_1 cfg_mul child_1_impl_1 cfg_grey}

# first number after "| <label>" in a report_utilization table, e.g. "| Slice LUTs* | 850 |"
proc util_num {rpt label} {
    if {[regexp -line "^\\|\\s*${label}\\*?\\s*\\|\\s*(\[0-9.\]+)" $rpt -> n]} { return $n }
    return "?"
}

set dcps {}
set summary {}
foreach {run cfg} $cfgs {
    # top_dfx_routed.dcp is the full design (static + RM); name it exactly so a
    # static-only or RM-only checkpoint in the same folder can never be picked up.
    set dcp $runs/$run/top_dfx_routed.dcp
    if {![file exists $dcp]} { error "missing $dcp -- implement $run first (T1_PLAN sec. 7.10)" }
    lappend dcps $dcp
    open_checkpoint $dcp

    report_timing_summary -file $out/${cfg}_timing_summary.rpt
    report_utilization -file $out/${cfg}_utilization.rpt
    report_utilization -hierarchical -file $out/${cfg}_utilization_hier.rpt
    report_utilization -pblocks [get_pblocks pblock_U_RP] -file $out/${cfg}_utilization_pblock.rpt
    report_utilization -cells [get_cells U_RP] -file $out/${cfg}_utilization_U_RP.rpt

    set wns [get_property SLACK [get_timing_paths -setup -max_paths 1 -nworst 1]]
    set whs [get_property SLACK [get_timing_paths -hold  -max_paths 1 -nworst 1]]
    set tot [report_utilization -return_string]
    set rp  [report_utilization -cells [get_cells U_RP] -return_string]
    lappend summary [format "%-9s WNS %7s  WHS %7s | total LUT %5s FF %5s DSP %3s | U_RP LUT %5s FF %5s DSP %3s" \
        $cfg $wns $whs \
        [util_num $tot "Slice LUTs"] [util_num $tot "Slice Registers"] [util_num $tot "DSPs"] \
        [util_num $rp  "Slice LUTs"] [util_num $rp  "Slice Registers"] [util_num $rp  "DSPs"]]
    close_design
}

set pr_rpt $out/pr_verify.rpt
set pr_ok [expr {![catch {
    pr_verify -full_check -initial [lindex $dcps 0] -additional [lrange $dcps 1 end] -file $pr_rpt
} pr_err]}]
if {$pr_ok && [file exists $pr_rpt]} {
    set fh [open $pr_rpt r]; set txt [read $fh]; close $fh
    set pr_ok [expr {[string match -nocase "*compatible*" $txt] && ![string match -nocase "*incompatible*" $txt]}]
}

puts "==== T1 build summary ===="
foreach line $summary { puts $line }
if {$pr_ok} {
    puts "pr_verify: PASS"
} else {
    puts "pr_verify: FAIL -- see $pr_rpt\n$pr_err"
}
