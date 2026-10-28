# reports_t2.tcl -- per-configuration reports + pr_verify (docs/t2/T2_PLAN.md §10.2)
#
# From PowerShell (G28), after collect_bitstreams.py passed:
#   cd D:\Projects\RC_Project\vivado\scratch_t2
#   C:\Xilinx\Vivado\2022.2\bin\vivado.bat -mode batch -nojournal -source ..\..\scripts\t2\reports_t2.tcl
# Writes docs/t2/reports/cfg_<x>_*.rpt, pr_verify.rpt, build_summary.csv. Read-only on the project.

set ROOT [file normalize [file join [file dirname [file normalize [info script]]] .. ..]]
set RUNS [file join $ROOT vivado t2_dfx t2_dfx.runs]
set REP  [file join $ROOT docs t2 reports]
file mkdir $REP
set CFGS {impl_1 int16 child_0_impl_1 int8 child_1_impl_1 int4 child_2_impl_1 grey}

proc util_num {txt label} {
    # first table row whose label starts with $label: | Slice LUTs* | 254 | ...
    foreach line [split $txt "\n"] {
        if {[regexp "^\\|\\s*${label}\\*?\\s*\\|\\s*(\[0-9.\]+)\\s*\\|" $line -> v]} { return $v }
    }
    return "?"
}
proc pct_num {txt label} {
    foreach line [split $txt "\n"] {
        set cols [split $line |]
        if {[llength $cols] >= 6 && [string match "${label}*" [string trim [lindex $cols 1]]]} {
            return [string trim [lindex $cols end-1]]
        }
    }
    return "?"
}

set rows {}
set dcps {}
foreach {run cfg} $CFGS {
    set dcp [file join $RUNS $run top_t2_routed.dcp]   ;# exact name, not a *_routed.dcp glob
    if {![file exists $dcp]} { puts "REPORT FAIL: $dcp missing"; continue }
    lappend dcps $dcp
    puts "=== cfg_$cfg ($run) ==="
    open_checkpoint $dcp
    set p [file join $REP cfg_$cfg]
    report_timing_summary -max_paths 10 -file ${p}_timing_summary.rpt
    report_utilization -file ${p}_utilization.rpt
    report_utilization -cells [get_cells U_RP] -file ${p}_utilization_U_RP.rpt
    catch {report_utilization -pblocks [get_pblocks pblock_U_RP] -file ${p}_utilization_pblock.rpt}
    report_utilization -hierarchical -file ${p}_utilization_hier.rpt
    report_drc -file ${p}_drc.rpt

    set wns [get_property SLACK [lindex [get_timing_paths -setup -max_paths 1 -nworst 1] 0]]
    set whs [get_property SLACK [lindex [get_timing_paths -hold  -max_paths 1 -nworst 1] 0]]
    set crit [lindex [get_timing_paths -setup -max_paths 1 -nworst 1] 0]
    set cp_from [get_property STARTPOINT_PIN $crit]
    set cp_to   [get_property ENDPOINT_PIN $crit]
    set cp_lvls [get_property LOGIC_LEVELS $crit]

    set ndrc_err 0
    foreach v [get_drc_violations -quiet] {
        if {[string match -nocase "error" [get_property SEVERITY $v]]} { incr ndrc_err }
    }
    set tot [report_utilization -return_string]
    set rp  [report_utilization -cells [get_cells U_RP] -return_string]
    set pb  ""
    catch {set pb [report_utilization -pblocks [get_pblocks pblock_U_RP] -return_string]}

    # partition pins: PPLOCs on U_RP's pins if the command exists, else non-clock U_RP pins
    set npp "?"; set ppm ""
    if {![catch {set npp [llength [get_pplocs -quiet -pins [get_pins U_RP/*]]]}] && $npp > 0} {
        set ppm get_pplocs
    } else {
        set npp [llength [get_pins -quiet U_RP/* -filter {NAME !~ "*/clk"}]]; set ppm non-clock-pins
    }
    set bufgs {}
    foreach c [get_cells -quiet -hierarchical -filter {REF_NAME =~ BUFG*}] { lappend bufgs $c }

    set row [list cfg_$cfg $run $wns $whs \
        [util_num $tot "Slice LUTs"] [util_num $tot "Slice Registers"] [util_num $tot "DSPs"] [util_num $tot "Block RAM Tile"] \
        [util_num $rp "Slice LUTs"] [util_num $rp "Slice Registers"] [util_num $rp "DSPs"] [util_num $rp "Block RAM Tile"] \
        [pct_num $pb "Slice LUTs"] [pct_num $pb "DSPs"] $npp $ppm $ndrc_err $cp_lvls $cp_from $cp_to]
    lappend rows $row
    puts "  WNS $wns  WHS $whs  U_RP LUT/FF/DSP [lindex $row 8]/[lindex $row 9]/[lindex $row 10]  DRC errors $ndrc_err  partition pins $npp ($ppm)"
    puts "  worst setup path: $cp_from -> $cp_to ($cp_lvls levels)"
    puts "  BUFGs: $bufgs"
    close_design
}

set f [open [file join $REP build_summary.csv] w]
puts $f "config,run,wns_ns,whs_ns,lut,ff,dsp,bram,urp_lut,urp_ff,urp_dsp,urp_bram,pblock_lut_pct,pblock_dsp_pct,partition_pins,pp_method,drc_errors,crit_levels,crit_from,crit_to"
foreach r $rows { puts $f [join $r ,] }
close $f
puts "wrote build_summary.csv ([llength $rows] configurations)"

if {[llength $dcps] == 4} {
    set rpt [file join $REP pr_verify.rpt]
    if {[catch {pr_verify -full_check -initial [lindex $dcps 0] -additional [lrange $dcps 1 end] -file $rpt} msg]} {
        puts "PR_VERIFY FAIL: $msg"
    } else {
        set f [open $rpt r]; set t [read $f]; close $f
        if {[regexp -nocase {incompatible} $t]} { puts "PR_VERIFY FAIL (see $rpt)" } else { puts "PR_VERIFY PASS (no incompatibility reported; read $rpt to confirm)" }
    }
} else {
    puts "PR_VERIFY SKIPPED: only [llength $dcps] routed checkpoints found"
}
