# power_delay_t2.tcl -- power, delay and LUT usage per T2 configuration (read-only on the project)
#
# Why: the course report needs a table with LUT usage, delay and power consumption.
# Run from PowerShell (not Git Bash), from a scratch folder:
#   mkdir D:\Projects\RC_Project\vivado\scratch_t2 -Force ; cd D:\Projects\RC_Project\vivado\scratch_t2
#   C:\Xilinx\Vivado\2022.2\bin\vivado.bat -mode batch -nojournal -source ..\..\scripts\t2\power_delay_t2.tcl
# Writes docs/t2/reports/power_delay_summary.csv and cfg_<x>_power.rpt. Opens the routed checkpoints read-only.
#
# Power is Vivado's vectorless ESTIMATE (default switching activity). Quote it as an estimate with its confidence level.
# Delay = data-path delay of the worst setup path; period 10 ns, so Fmax estimate = 1000 / (10 - WNS) MHz (a computed estimate).

set ROOT [file normalize [file join [file dirname [file normalize [info script]]] .. ..]]
set RUNS [file join $ROOT vivado t2_dfx t2_dfx.runs]
set REP  [file join $ROOT docs t2 reports]
file mkdir $REP
set CFGS {impl_1 int16 child_0_impl_1 int8 child_1_impl_1 int4 child_2_impl_1 grey}

proc grab {txt label} {
    # first summary row "| label | value |"
    foreach line [split $txt "\n"] {
        if {[regexp "^\\|\\s*[string map {( \\( ) \\)} $label]\\*?\\s*\\|\\s*(\[^|\]+?)\\s*\\|" $line -> v]} { return [string trim $v] }
    }
    return "?"
}

set rows {}
foreach {run cfg} $CFGS {
    set dcp [file join $RUNS $run top_t2_routed.dcp]
    if {![file exists $dcp]} { puts "POWER FAIL: $dcp missing"; continue }
    puts "=== cfg_$cfg ($run) ==="
    open_checkpoint $dcp
    set pw [report_power -return_string]
    set f [open [file join $REP cfg_${cfg}_power.rpt] w]; puts $f $pw; close $f
    set total  [grab $pw "Total On-Chip Power (W)"]
    set dyn    [grab $pw "Dynamic (W)"]
    set stat   [grab $pw "Device Static (W)"]
    set conf   [grab $pw "Confidence Level"]
    set tj     [grab $pw "Junction Temperature (C)"]

    set util [report_utilization -return_string]
    set lut ?; set ff ?; set dsp ?
    foreach line [split $util "\n"] {
        if {$lut eq "?" && [regexp {^\|\s*Slice LUTs\*?\s*\|\s*(\d+)\s*\|} $line -> v]} { set lut $v }
        if {$ff  eq "?" && [regexp {^\|\s*Slice Registers\s*\|\s*(\d+)\s*\|} $line -> v]} { set ff $v }
        if {$dsp eq "?" && [regexp {^\|\s*DSPs\s*\|\s*(\d+)\s*\|} $line -> v]} { set dsp $v }
    }
    set rp [report_utilization -cells [get_cells U_RP] -return_string]
    set rlut ?
    foreach line [split $rp "\n"] {
        if {$rlut eq "?" && [regexp {^\|\s*Slice LUTs\*?\s*\|\s*(\d+)\s*\|} $line -> v]} { set rlut $v }
    }

    set path [lindex [get_timing_paths -setup -max_paths 1 -nworst 1] 0]
    set wns ?; set dpd ?; set lvl ?; set fmax ?
    catch {set wns [get_property SLACK $path]}
    catch {set dpd [get_property DATAPATH_DELAY $path]}
    catch {set lvl [get_property LOGIC_LEVELS $path]}
    if {$wns ne "?"} { set fmax [format %.1f [expr {1000.0 / (10.0 - $wns)}]] }

    lappend rows [list cfg_$cfg $lut $ff $dsp $rlut $wns $dpd $lvl $fmax $total $dyn $stat $tj $conf]
    puts "  LUT $lut (U_RP $rlut)  FF $ff  DSP $dsp  WNS $wns  datapath delay $dpd ns ($lvl levels)  est. Fmax $fmax MHz"
    puts "  power: total $total W  dynamic $dyn W  static $stat W  Tj $tj C  confidence $conf"
    close_design
}

set f [open [file join $REP power_delay_summary.csv] w]
puts $f "config,lut_total,ff_total,dsp,lut_region,wns_ns,datapath_delay_ns,logic_levels,fmax_est_mhz,power_total_w,power_dynamic_w,power_static_w,junction_c,power_confidence"
foreach r $rows { puts $f [join $r ,] }
close $f
puts "wrote power_delay_summary.csv ([llength $rows] configurations)"
