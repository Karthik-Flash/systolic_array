# hw_t1.tcl -- T1_PLAN §9.3: Hardware Manager procs for the on-board DFX swap test.
# In the Vivado Tcl console:
#   source D:/Projects/RC_Project/scripts/t1/hw_t1.tcl
#   t1_connect ; t1_program full add ; t1_swap_demo mul ; ... ; t1_selftest
# Procs: t1_connect, t1_program <full|partial> <rm> | <bitfile>, t1_swap <rm>, t1_check <rm>,
#        t1_swap_demo <rm>, t1_full_contrast, t1_set <probe> <hex>, t1_get <probe>, t1_probes,
#        t1_selftest.   <rm> = add | mul | grey
# Only the PL device xc7z020_1 is ever touched (never arm_dap_0 / the PS).
#
# MOCK mode (no hardware): `set ::T1_MOCK 1` before or after sourcing. Every hardware
# call goes through the t1_hw_* wrappers below; in mock mode they drive a small
# simulated device instead (see "mock device"). scripts/t1/hw_t1_mock.tcl runs it all.

set t1_root    [file normalize [file join [file dirname [info script]] ../..]]
set t1_bits    $t1_root/bitstreams/t1
set t1_ltx     $t1_bits/t1_full_add.ltx
set t1_reports $t1_root/docs/t1/reports
if {![info exists ::T1_MOCK]} { set ::T1_MOCK 0 }

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

# =============================================================================
# Hardware wrappers: the ONLY procs that touch Hardware Manager.
# =============================================================================
proc t1_dev {} { return [get_hw_devices xc7z020_1] }

proc t1_hw_connect {} {
    if {$::T1_MOCK} { return [t1_mock_connect] }
    catch {open_hw_manager}
    if {[llength [get_hw_servers -quiet]] == 0} { connect_hw_server }
    if {[catch {open_hw_target} err]} { puts "open_hw_target: $err (already open?)" }
    set dev [t1_dev]
    if {$dev eq ""} { error "xc7z020_1 not found in the JTAG chain" }
    current_hw_device $dev
    return $dev
}

# program a bitstream; returns program_hw_devices wall-clock ms
proc t1_hw_program {bit} {
    if {$::T1_MOCK} { return [t1_mock_program $bit] }
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

proc t1_hw_write {key hex} {
    if {$::T1_MOCK} { return [t1_mock_write $key $hex] }
    set p [t1_probe $key]
    set_property OUTPUT_VALUE_RADIX HEX $p
    set_property OUTPUT_VALUE $hex $p
    commit_hw_vio $p
}

proc t1_hw_read {key} {
    if {$::T1_MOCK} { return [t1_mock_read $key] }
    set p [t1_probe $key]
    refresh_hw_vio [get_hw_vios -of_objects [t1_dev]]
    set_property INPUT_VALUE_RADIX HEX $p
    return [string toupper [get_property INPUT_VALUE $p]]
}

proc t1_hw_probe_names {} {
    if {$::T1_MOCK} { return {mock/vio_y mock/vio_rm_id mock/vio_uptime mock/vio_decouple mock/vio_rm_rst mock/vio_a mock/vio_b} }
    return [get_hw_probes -of_objects [get_hw_vios -of_objects [t1_dev]]]
}

proc t1_wait {ms} {
    if {$::T1_MOCK} { set ::t1_mock(skew) [expr {$::t1_mock(skew) + $ms}]; return }
    after $ms
}

# =============================================================================
# Mock device: loaded config, VIO outputs, uptime from a virtual clock
# ([clock milliseconds] + skew; programming advances skew by the fake time, no sleep).
# Fake program time is proportional to bitstream size: full (4,045,667 B) = 9,000 ms,
# as measured in board session 1.
# ::T1_MOCK_BAD_PARTIAL 1 = negative test: a partial also resets uptime (static NOT kept).
# =============================================================================
if {![info exists ::T1_MOCK_BAD_PARTIAL]} { set ::T1_MOCK_BAD_PARTIAL 0 }

proc t1_mock_reset {} {
    array set ::t1_mock {rm none boot 0 skew 0 decouple 0 rm_rst 0 a 0 b 0}
}
t1_mock_reset

proc t1_mock_now {} { return [expr {[clock milliseconds] + $::t1_mock(skew)}] }

proc t1_mock_connect {} { return mock/xc7z020_1 }

proc t1_mock_program {bit} {
    set ms [expr {int([file size $bit] * 9000.0 / 4045667)}]
    set ::t1_mock(skew) [expr {$::t1_mock(skew) + $ms}]
    set name [file tail $bit]
    if {[regexp {^t1_full_(\w+)\.bit$} $name -> rm]} {
        # full program: whole chip reconfigured -> static restarts, VIO outputs back to 0
        array set ::t1_mock [list rm $rm boot [t1_mock_now] decouple 0 rm_rst 0 a 0 b 0]
    } elseif {[regexp {^t1_partial_(\w+)\.bit$} $name -> rm]} {
        if {$::t1_mock(rm) eq "none"} { error "mock: partial $name loaded onto an unconfigured device" }
        set ::t1_mock(rm) $rm
        if {$::T1_MOCK_BAD_PARTIAL} { set ::t1_mock(boot) [t1_mock_now] }
    } else {
        error "mock: unknown bitstream $name"
    }
    return $ms
}

proc t1_mock_write {key hex} { set ::t1_mock($key) [scan $hex %x] }

proc t1_s16 {x} { return [expr {$x >= 0x8000 ? $x - 0x10000 : $x}] }

proc t1_mock_read {key} {
    set held [expr {$::t1_mock(decouple) || $::t1_mock(rm_rst)}]
    switch -- $key {
        uptime { return [format %08X [expr {$::t1_mock(rm) eq "none" ? 0 : ([t1_mock_now] - $::t1_mock(boot)) / 1000}]] }
        rm_id {
            if {$::t1_mock(decouple)} { return FF }
            if {$held || $::t1_mock(rm) eq "none"} { return 00 }
            return [dict get $::t1_rm_id $::t1_mock(rm)]
        }
        y {
            if {$held} { return 00000000 }
            set a [t1_s16 $::t1_mock(a)]
            set b [t1_s16 $::t1_mock(b)]
            switch -- $::t1_mock(rm) {
                add     { set y [expr {$a + $b}] }
                mul     { set y [expr {$a * $b}] }
                default { set y 0 }
            }
            return [format %08X [expr {$y & 0xFFFFFFFF}]]
        }
        default { return [format %X $::t1_mock($key)] }
    }
}

# =============================================================================
# Everything below uses only the wrappers above.
# =============================================================================
proc t1_connect {} { return [t1_hw_connect] }

# t1_program full add | t1_program partial mul | t1_program <bitfile>; returns ms
proc t1_program {args} {
    if {[llength $args] == 2} {
        lassign $args kind rm
        set bit $::t1_bits/t1_${kind}_$rm.bit
    } else {
        set bit [lindex $args 0]
    }
    if {![file exists $bit]} { error "missing $bit -- run scripts/t1/collect_bitstreams.py" }
    return [t1_hw_program $bit]
}

proc t1_probes {} { foreach p [t1_hw_probe_names] { puts $p } }

proc t1_probe {key} {
    set all [t1_hw_probe_names]
    foreach pat [dict get $::t1_probe_pat $key] {
        set hit [lsearch -all -inline -glob $all $pat]
        if {[llength $hit] == 1} { return $hit }
    }
    error "VIO probe '$key' not found (patterns: [dict get $::t1_probe_pat $key]). Probes: $all"
}

proc t1_set {key hex} { t1_hw_write $key $hex }
proc t1_get {key}     { return [t1_hw_read $key] }

proc t1_eq {x y} { return [expr {[scan $x %x] == [scan $y %x]}] }

# decouple -> program partial (timed) -> release; returns ms
proc t1_swap {rm} {
    t1_set decouple 1
    set ms [t1_program partial $rm]
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

# ---- demo helpers: readable values ----
proc t1_y_fmt {hex} {
    set h [format %08X [scan $hex %x]]
    return "[string range $h 0 3]_[string range $h 4 7]"
}
proc t1_commas {n} {
    while {[regsub {^(\d+)(\d{3})} $n {\1,\2} n]} {}
    return $n
}
proc t1_uptime_s {} { return [scan [t1_get uptime] %x] }

# Static kept running across a program that took ms? At least ms of wall time passes
# between the two uptime reads, and floor(t + E) - floor(t) >= floor(E), so a
# continuous seconds counter must advance by >= floor(ms/1000). Stronger than
# "non-decreasing", which misses a reset when uptime was already ~0.
proc t1_uptime_kept {before after ms} { return [expr {$after - $before >= $ms / 1000}] }

# One readable swap block for a live demo (a, b held at 3, 4). Returns 1 = PASS.
proc t1_swap_demo {rm} {
    set bit $::t1_bits/t1_partial_$rm.bit
    set exp_id [dict get $::t1_rm_id $rm]
    set exp_y  [dict get {add 00000007 mul 0000000C grey 00000000} $rm]
    t1_set a 0003
    t1_set b 0004
    set up0 [t1_uptime_s]
    puts [format "BEFORE  : rm_id %s  y %s  uptime %d s" [t1_get rm_id] [t1_y_fmt [t1_get y]] $up0]

    t1_set decouple 1
    set dc_id [t1_get rm_id]
    set dc_y  [t1_get y]
    puts [format "DECOUPLE -> rm_id %s  y %s" $dc_id [t1_y_fmt $dc_y]]

    set ms [t1_program $bit]
    puts [format "PROGRAM  %s (%s B) ... %d ms" [file tail $bit] [t1_commas [file size $bit]] $ms]

    # force a real 1 -> 0 write (tool cache may be stale after refresh), re-assert a, b
    t1_set decouple 1
    t1_set decouple 0
    t1_set a 0003
    t1_set b 0004
    set id [t1_get rm_id]
    set y  [t1_get y]
    puts [format "RELEASE  -> rm_id %s  y %s" $id [t1_y_fmt $y]]

    set up1 [t1_uptime_s]
    set d [expr {$up1 - $up0}]
    set kept [t1_uptime_kept $up0 $up1 $ms]
    set ok [expr {[t1_eq $dc_id FF] && [t1_eq $dc_y 0] && [t1_eq $id $exp_id] && [t1_eq $y $exp_y] && $kept}]
    set note [expr {$kept ? "static NOT reset" : "static WAS RESET"}]
    puts [format "AFTER   : uptime %d s   (%+d s across the swap; %s)   VERDICT: %s" \
        $up1 $d $note [expr {$ok ? "PASS" : "FAIL"}]]
    return $ok
}

# Contrast: a FULL program restarts the static region -> uptime drops. Returns 1 = PASS.
proc t1_full_contrast {} {
    set bit $::t1_bits/t1_full_add.bit
    set up0 [t1_uptime_s]
    puts [format "BEFORE  : rm_id %s  uptime %d s" [t1_get rm_id] $up0]
    set ms [t1_program $bit]
    puts [format "PROGRAM  %s (%s B) ... %d ms" [file tail $bit] [t1_commas [file size $bit]] $ms]
    set up1 [t1_uptime_s]
    set ok [expr {$up1 < $up0}]
    puts [format "AFTER   : rm_id %s  uptime %d s   (%s)   VERDICT: %s" [t1_get rm_id] $up1 \
        [expr {$ok ? "uptime reset: expected for a full program" : "uptime NOT reset: unexpected"}] \
        [expr {$ok ? "PASS" : "FAIL"}]]
    return $ok
}

# full program x3, then partial swaps (mul add grey) x5 = mul->add->grey->mul->add->...
# Returns 1 = PASS.
proc t1_selftest {} {
    t1_connect
    set rows {}
    set ms_of [dict create full {} add {} mul {} grey {}]
    set step 0

    # ---- full program x3: uptime must restart (expected) ----
    for {set i 0} {$i < 3} {incr i} {
        # if/else, not expr ?: -- expr would parse the hex string as a (octal!) number
        if {$i == 0} { set before "" } else { set before [t1_get uptime] }
        set ms [t1_program full add]
        set after [t1_get uptime]
        set reset [expr {$before eq "" ? "n/a" : ([scan $after %x] < [scan $before %x] ? "yes" : "NO")}]
        set fails [t1_check add]
        dict lappend ms_of full $ms
        lappend rows [list [incr step] full t1_full_add.bit $ms $before $after reset=$reset [t1_get rm_id] [expr {[llength $fails] ? "FAIL" : "PASS"}] [join $fails {; }]]
        t1_wait 3000   ;# let uptime climb so the next full program visibly resets it
    }

    # ---- partial swaps: static (uptime) must keep counting across the swap ----
    for {set i 0} {$i < 5} {incr i} {
        foreach rm {mul add grey} {
            set before [t1_get uptime]
            set ms [t1_swap $rm]
            set after [t1_get uptime]
            set cont [expr {[t1_uptime_kept [scan $before %x] [scan $after %x] $ms] ? "yes" : "NO"}]
            set fails [t1_check $rm]
            if {$cont ne "yes"} { lappend fails "uptime not continuous across ${ms} ms program: $before -> $after" }
            dict lappend ms_of $rm $ms
            lappend rows [list [incr step] partial_$rm t1_partial_$rm.bit $ms $before $after continuity=$cont [t1_get rm_id] [expr {[llength $fails] ? "FAIL" : "PASS"}] [join $fails {; }]]
        }
    }
    # leave the board in the reference configuration
    t1_swap add

    # ---- CSV (mock runs go to the gitignored sim/t1_build/mock/, never docs/) ----
    set ts [clock format [clock seconds] -format %Y%m%d_%H%M%S]
    if {$::T1_MOCK} {
        set dir $::t1_root/sim/t1_build/mock
        set csv $dir/hw_selftest_MOCK_${ts}_[clock clicks].csv
    } else {
        set dir $::t1_reports
        set csv $dir/hw_selftest_$ts.csv
    }
    file mkdir $dir
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
    return $all_ok
}
