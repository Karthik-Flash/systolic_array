# hw_t1.tcl -- T1_PLAN §9.3: Hardware Manager procs for the on-board DFX swap test.
# In the Vivado Tcl console:
#   source D:/Projects/RC_Project/scripts/t1/hw_t1.tcl
#   t1_selftest
# Procs: t1_connect, t1_program <bit>, t1_swap <add|mul|grey>, t1_check <add|mul|grey>,
#        t1_set <probe> <hex>, t1_get <probe>, t1_probes, t1_selftest.
# Only the PL device xc7z020_1 is ever touched (never arm_dap_0 / the PS).

set t1_root    [file normalize [file join [file dirname [info script]] ../..]]
set t1_bits    $t1_root/bitstreams/t1
set t1_ltx     $t1_bits/t1_full_add.ltx
set t1_reports $t1_root/docs/t1_reports

# VIO probe name patterns, tried in order (robust to hierarchy prefixes).
# Calibration knob: if a lookup fails, run t1_probes and add the real name here.
set t1_probe_pat {
    y        {*vio_y*}
    rm_id    {*vio_rm_id*}
    uptime   {*vio_uptime* *uptime_s*}
    decouple {*vio_decouple*}
    rm_rst   {*vio_rm_rst*}
    a        {*vio_a*}
    b        {*vio_b*}
}

# T1_PLAN §6.1 -- keep identical to tb_rp_t1.v / tb_top_dfx.v. {a b add_y mul_y}
set t1_vectors {
    {0003 0004 00000007 0000000C}
    {FFFD 0004 00000001 FFFFFFF4}
    {0007 FFFA 00000001 FFFFFFD6}
    {7FFF 7FFF 0000FFFE 3FFF0001}
    {8000 8000 FFFF0000 40000000}
    {8000 7FFF FFFFFFFF C0008000}
    {0000 0000 00000000 00000000}
}
set t1_rm_id {add A1 mul B2 grey 00}

proc t1_dev {} { return [get_hw_devices xc7z020_1] }

proc t1_connect {} {
    catch {open_hw_manager}
    if {[llength [get_hw_servers -quiet]] == 0} { connect_hw_server }
    if {[catch {open_hw_target} err]} { puts "open_hw_target: $err (already open?)" }
    set dev [t1_dev]
    if {$dev eq ""} { error "xc7z020_1 not found in the JTAG chain" }
    current_hw_device $dev
    return $dev
}

# program a full or partial bitstream; returns program_hw_devices wall-clock ms
proc t1_program {bit} {
    if {![file exists $bit]} { error "missing $bit -- run scripts/t1/collect_bitstreams.py" }
    set dev [t1_dev]
    set_property PROBES.FILE      $::t1_ltx $dev
    set_property FULL_PROBES.FILE $::t1_ltx $dev
    set_property PROGRAM.FILE     $bit      $dev
    set t0 [clock milliseconds]
    program_hw_devices $dev
    set ms [expr {[clock milliseconds] - $t0}]
    refresh_hw_device $dev
    return $ms
}

proc t1_probes {} {
    foreach p [get_hw_probes -of_objects [get_hw_vios -of_objects [t1_dev]]] { puts $p }
}

proc t1_probe {key} {
    set all [get_hw_probes -of_objects [get_hw_vios -of_objects [t1_dev]]]
    foreach pat [dict get $::t1_probe_pat $key] {
        set hit [lsearch -all -inline -glob $all $pat]
        if {[llength $hit] == 1} { return $hit }
    }
    error "VIO probe '$key' not found (patterns: [dict get $::t1_probe_pat $key]). Probes: $all"
}

proc t1_set {key hex} {
    set p [t1_probe $key]
    set_property OUTPUT_VALUE_RADIX HEX $p
    set_property OUTPUT_VALUE $hex $p
    commit_hw_vio $p
}

proc t1_get {key} {
    set p [t1_probe $key]
    refresh_hw_vio [get_hw_vios -of_objects [t1_dev]]
    set_property INPUT_VALUE_RADIX HEX $p
    return [string toupper [get_property INPUT_VALUE $p]]
}

proc t1_eq {x y} { return [expr {[scan $x %x] == [scan $y %x]}] }

# decouple -> program partial (timed) -> release; returns ms
proc t1_swap {rm} {
    t1_set decouple 1
    set ms [t1_program $::t1_bits/t1_partial_$rm.bit]
    # re-assert then release: after refresh_hw_device the tool's cached
    # OUTPUT_VALUE may not match the core, so force a real 1 -> 0 write.
    t1_set decouple 1
    t1_set decouple 0
    return $ms
}

# all §6.1 vectors + rm_id for the loaded RM; returns list of failures (empty = pass)
proc t1_check {rm} {
    set fails {}
    set exp_id [dict get $::t1_rm_id $rm]
    set id [t1_get rm_id]
    if {![t1_eq $id $exp_id]} { lappend fails "rm_id $id != $exp_id" }
    foreach v $::t1_vectors {
        lassign $v a b yadd ymul
        t1_set a $a
        t1_set b $b
        set exp [dict get [list add $yadd mul $ymul grey 00000000] $rm]
        set y [t1_get y]
        if {![t1_eq $y $exp]} { lappend fails "$rm $a,$b: y $y != $exp" }
    }
    return $fails
}

proc t1_stats {xs} {
    set n [llength $xs]
    set mean [expr {double([tcl::mathop::+ {*}$xs]) / $n}]
    set ss 0.0
    foreach x $xs { set ss [expr {$ss + ($x - $mean) ** 2}] }
    set sd [expr {$n > 1 ? sqrt($ss / ($n - 1)) : 0.0}]
    return [format "%.0f +- %.0f" $mean $sd]
}

# full program x3, then partial swaps (mul add grey) x5 = mul->add->grey->mul->add->...
proc t1_selftest {} {
    t1_connect
    set rows {}
    set ms_of [dict create full {} add {} mul {} grey {}]
    set step 0

    # ---- full program x3: uptime must restart (expected) ----
    for {set i 0} {$i < 3} {incr i} {
        set before [expr {$i == 0 ? "" : [t1_get uptime]}]
        set ms [t1_program $::t1_bits/t1_full_add.bit]
        set after [t1_get uptime]
        set reset [expr {$before eq "" ? "n/a" : ([scan $after %x] < [scan $before %x] ? "yes" : "NO")}]
        set fails [t1_check add]
        dict lappend ms_of full $ms
        lappend rows [list [incr step] full t1_full_add.bit $ms $before $after reset=$reset [t1_get rm_id] [expr {[llength $fails] ? "FAIL" : "PASS"}] [join $fails {; }]]
        after 3000   ;# let uptime climb so the next full program visibly resets it
    }

    # ---- partial swaps: static (uptime) must never go backwards ----
    for {set i 0} {$i < 5} {incr i} {
        foreach rm {mul add grey} {
            set before [t1_get uptime]
            set ms [t1_swap $rm]
            set after [t1_get uptime]
            set cont [expr {[scan $after %x] >= [scan $before %x] ? "yes" : "NO"}]
            set fails [t1_check $rm]
            if {$cont ne "yes"} { lappend fails "uptime went backwards $before -> $after" }
            dict lappend ms_of $rm $ms
            lappend rows [list [incr step] partial_$rm t1_partial_$rm.bit $ms $before $after continuity=$cont [t1_get rm_id] [expr {[llength $fails] ? "FAIL" : "PASS"}] [join $fails {; }]]
        }
    }
    # leave the board in the reference configuration
    t1_swap add

    # ---- CSV ----
    file mkdir $::t1_reports
    set csv $::t1_reports/hw_selftest_[clock format [clock seconds] -format %Y%m%d_%H%M%S].csv
    set fh [open $csv w]
    puts $fh "step,op,bitfile,program_ms,uptime_before,uptime_after,uptime_check,rm_id,result,details"
    foreach r $rows {
        set cells {}
        foreach f $r { lappend cells [string map {, ;} $f] }   ;# no lmap: Vivado ships Tcl 8.5
        puts $fh [join $cells ,]
    }
    close $fh

    # ---- console table ----
    set all_ok 1
    puts [format "%-4s %-13s %8s %10s %10s %-16s %-5s %s" step op ms up_before up_after uptime rm_id result]
    foreach r $rows {
        lassign $r s op bit ms before after chk id res det
        puts [format "%-4s %-13s %8s %10s %10s %-16s %-5s %s %s" $s $op $ms $before $after $chk $id $res $det]
        if {$res ne "PASS" || [string match "*NO" $chk]} { set all_ok 0 }
    }
    puts "---- JTAG program time (ms, mean +- sd) ----"
    dict for {op xs} $ms_of { puts [format "%-5s N=%d  %s" $op [llength $xs] [t1_stats $xs]] }
    puts "CSV: $csv"
    puts [expr {$all_ok ? "T1 SELFTEST PASS" : "T1 SELFTEST FAIL"}]
}
