# hw_t2.tcl -- T2 board procedures (docs/t2/T2_PLAN.md §11.1)
#
# Usage (Vivado 2022.2 Hardware Manager, Tcl console):
#   source D:/Projects/RC_Project/scripts/t2/hw_t2.tcl
#   t2_connect ; t2_program full int16 ; t2_check counting ; t2_swap_demo int8 ; ...
#
# Tcl 8.5 rules (Vivado ships 8.5): no lmap/try; hex strings never go through expr;
# rm_id compared as normalised strings ("08" is an invalid octal number in 8.5).
# Only t2_hw_connect / t2_hw_program / t2_hw_write / t2_hw_read / t2_wait touch the
# hardware. With ::T2_MOCK 1 they call the simulated device in hw_t2_mock.tcl.

if {![info exists ::T2_MOCK]} { set ::T2_MOCK 0 }
set ::T2_ROOT   [file normalize [file join [file dirname [file normalize [info script]]] .. ..]]
if {![info exists ::T2_REPORT_DIR]} { set ::T2_REPORT_DIR [file join $::T2_ROOT docs t2 reports] }
set ::T2_BITDIR [file join $::T2_ROOT bitstreams t2]
set ::T2_VECDIR [file join $::T2_ROOT sim t2_vectors]
set ::T2_LTX    [file join $::T2_BITDIR t2_full_int16.ltx]
set ::T2_PRECS  {int16 int8 int4 grey}
array set ::T2_CODE {int16 16 int8 08 int4 04 grey 00}
array set ::T2_PREC_OF {16 int16 08 int8 04 int4 00 grey ff decoupled}
set ::T2_BOARD_CASES {counting asym_small random_full extremes_neg extremes_mix}
# locked VIO port of every probe (plan §4), used only if the .ltx renamed a net
array set ::T2_PORT {vio_decouple probe_out0 vio_rm_rst probe_out1 vio_start probe_out2
    vio_sel probe_out3 vio_a probe_out4 vio_b probe_out5 vio_result probe_in0
    vio_rm_id probe_in1 vio_uptime probe_in2 vio_flags probe_in3 vio_runs probe_in4}
set ::T2_LAST_CASE ""
if {![info exists ::T2_DEV]} { set ::T2_DEV "" }
set ::T2_VIO ""

# ---------------------------------------------------------------- hex helpers
proc t2_hex2u {h} {
    set h [string tolower [string map {_ "" " " "" "\t" "" "\r" ""} [string trim $h]]]
    if {[string match 0x* $h]} { set h [string range $h 2 end] }
    if {$h eq ""} { error "t2_hex2u: empty hex string" }
    set v 0
    foreach c [split $h ""] {
        set d [string first $c 0123456789abcdef]
        if {$d < 0} { error "t2_hex2u: bad hex '$h'" }
        set v [expr {$v * 16 + $d}]
    }
    return $v
}
proc t2_hex2s32 {h} {
    set v [t2_hex2u $h]
    if {$v >= 2147483648} { set v [expr {$v - 4294967296}] }
    return $v
}
proc t2_norm_id {h} { return [format %02x [t2_hex2u $h]] }
proc t2_hex8 {v}    { return [format %08X [expr {$v & 0xFFFFFFFF}]] }

# 16 signed ints, row-major -> 64-digit probe string, A[3][3] first ... A[0][0] last
proc t2_pack256 {M} {
    if {[llength $M] != 16} { error "t2_pack256: need 16 values, got [llength $M]" }
    set s ""
    for {set k 15} {$k >= 0} {incr k -1} {
        append s [format %04X [expr {[lindex $M $k] & 0xFFFF}]]
    }
    return $s
}
proc t2_unpack256 {s} {
    set s [string map {_ "" " " ""} [string trim $s]]
    if {[string length $s] != 64} { error "t2_unpack256: need 64 hex digits, got [string length $s]" }
    set M [lrepeat 16 0]
    for {set c 0} {$c < 16} {incr c} {
        set v [t2_hex2u [string range $s [expr {4*$c}] [expr {4*$c+3}]]]
        if {$v >= 32768} { set v [expr {$v - 65536}] }
        lset M [expr {15 - $c}] $v
    }
    return $M
}

# ---------------------------------------------------------------- vectors
proc t2_read_lines {path} {
    if {![file exists $path]} { error "missing vector file $path" }
    set f [open $path r]; set data [read $f]; close $f
    set out {}
    foreach line [split $data "\n"] {
        set line [string trim $line]
        if {$line eq "" || [string match //* $line] || [string match #* $line]} { continue }
        lappend out [lindex [split $line] 0]
    }
    return $out
}
proc t2_case_dir {prec case} {
    if {$prec eq "grey"} { set prec int16 }
    return [file join $::T2_VECDIR $prec $case]
}
proc t2_case_probes {prec case} {
    set d [t2_case_dir $prec $case]
    return [list [string toupper [lindex [t2_read_lines [file join $d a_probe.hex]] 0]] \
                 [string toupper [lindex [t2_read_lines [file join $d b_probe.hex]] 0]]]
}
proc t2_case_golden {prec case} {
    if {$prec eq "grey"} { return [list [lrepeat 16 0] [lrepeat 16 0]] }
    set d [t2_case_dir $prec $case]
    set c {}; set o {}
    foreach h [t2_read_lines [file join $d c_out.hex]] { lappend c [t2_hex2s32 $h] }
    foreach h [t2_read_lines [file join $d ovf.hex]]   { lappend o [t2_hex2u $h] }
    if {[llength $c] != 16 || [llength $o] != 16} { error "bad golden files in $d" }
    return [list $c $o]
}

# ---------------------------------------------------------------- manifest / files
proc t2_manifest {} {
    set m [file join $::T2_BITDIR manifest.csv]
    array set sz {}
    if {![file exists $m]} { return [array get sz] }
    set f [open $m r]; set lines [split [read $f] "\n"]; close $f
    set hdr [split [string trim [lindex $lines 0]] ,]
    set fi [lsearch $hdr file]; set bi [lsearch $hdr bytes]
    foreach l [lrange $lines 1 end] {
        set l [string trim $l]; if {$l eq ""} continue
        set r [split $l ,]
        set sz([lindex $r $fi]) [lindex $r $bi]
    }
    return [array get sz]
}
proc t2_bitfile {kind prec} {
    if {[lsearch {full partial} $kind] < 0} { error "kind must be full or partial" }
    if {[lsearch $::T2_PRECS $prec] < 0}    { error "prec must be one of $::T2_PRECS" }
    set name "t2_${kind}_${prec}.bit"
    set path [file join $::T2_BITDIR $name]
    array set sz [t2_manifest]
    if {[array size sz] == 0} {
        if {$::T2_MOCK} { return $path }
        error "bitstreams/t2/manifest.csv missing: run scripts/t2/collect_bitstreams.py first"
    }
    if {![info exists sz($name)]} { error "$name is not in bitstreams/t2/manifest.csv: refusing (G24)" }
    if {[file exists $path]} {
        if {[file size $path] != $sz($name)} { error "$name size [file size $path] != manifest $sz($name)" }
    } elseif {!$::T2_MOCK} { error "$path does not exist" }
    return $path
}

# ---------------------------------------------------------------- hardware wrappers
proc t2_wait {ms} {
    if {$::T2_MOCK} { mock_wait $ms; return }
    after $ms
}
proc t2_hw_connect {} {
    if {$::T2_MOCK} { mock_connect; return }
    catch {open_hw_manager}
    if {[llength [get_hw_servers -quiet]] == 0} { connect_hw_server -allow_non_jtag }
    if {[catch {open_hw_target} msg]} { puts "  (open_hw_target: target probably already open)" }
    set devs [get_hw_devices -quiet xc7z020*]
    if {[llength $devs] == 0} { error "no xc7z020 device on the JTAG chain (cable in J17? board on?)" }
    set ::T2_DEV [lindex $devs 0]
    current_hw_device $::T2_DEV
    if {[file exists $::T2_LTX]} {
        set_property PROBES.FILE $::T2_LTX $::T2_DEV
        catch {set_property FULL_PROBES.FILE $::T2_LTX $::T2_DEV}
    }
    refresh_hw_device $::T2_DEV
    set ::T2_VIO ""; catch {array unset ::T2_PCACHE}
}
proc t2_hw_program {path} {
    if {$::T2_MOCK} { return [mock_program $path] }
    set dev $::T2_DEV
    set_property PROBES.FILE $::T2_LTX $dev
    catch {set_property FULL_PROBES.FILE $::T2_LTX $dev}
    catch {set_property PARTIAL_PROBES.FILES {} $dev}
    set_property PROGRAM.FILE $path $dev
    set t0 [clock milliseconds]
    program_hw_devices $dev
    set ms [expr {[clock milliseconds] - $t0}]
    refresh_hw_device $dev
    set ::T2_VIO ""; catch {array unset ::T2_PCACHE}
    return $ms
}
proc t2__vio {} {
    if {$::T2_VIO eq ""} {
        set vios [get_hw_vios -quiet -of_objects $::T2_DEV]
        if {[llength $vios] == 0} { error "no VIO core: is a T2 full bitstream loaded? (t2_program full int16)" }
        set ::T2_VIO [lindex $vios 0]
    }
    return $::T2_VIO
}
proc t2__probe {name} {
    if {[info exists ::T2_PCACHE($name)]} { return $::T2_PCACHE($name) }
    set all [get_hw_probes -quiet -of_objects [t2__vio]]
    set want $name
    if {[info exists ::T2_ALIAS($name)]} { set want $::T2_ALIAS($name) }   ;# manual override, survives reprogramming
    set hit {}
    foreach p $all { if {[get_property NAME $p] eq $want} { lappend hit $p } }
    if {[llength $hit] == 0} {
        foreach p $all {
            set tail [lindex [split [get_property NAME $p] /] end]
            regsub {\[.*$} $tail {} tail
            if {$tail eq $name} { lappend hit $p }
        }
    }
    if {[llength $hit] == 0 && [info exists ::T2_PORT($name)]} {
        foreach p $all {
            set port ""
            catch {set port [get_property PROBE_PORT $p]}
            if {$port eq $::T2_PORT($name)} { lappend hit $p }
        }
    }
    if {[llength $hit] != 1} {
        set names {}
        foreach p $all { lappend names [get_property NAME $p] }
        error "probe '$name': [llength $hit] matches. Probes on the core: $names"
    }
    set p [lindex $hit 0]
    catch {set_property OUTPUT_VALUE_RADIX HEX $p}
    catch {set_property INPUT_VALUE_RADIX HEX $p}
    set ::T2_PCACHE($name) $p
    return $p
}
proc t2_hw_write {name value} {
    if {$::T2_MOCK} { mock_write $name $value; return }
    set p [t2__probe $name]
    set_property OUTPUT_VALUE $value $p
    commit_hw_vio $p
}
proc t2_hw_read {names} {
    if {$::T2_MOCK} { return [mock_read $names] }
    refresh_hw_vio [t2__vio]
    set out {}
    foreach n $names { lappend out [get_property INPUT_VALUE [t2__probe $n]] }
    return $out
}

# ---------------------------------------------------------------- basic operations
proc t2_hw_info {} {
    if {$::T2_MOCK} { return "mock device, no JTAG" }
    set f "?"
    catch {set f [get_property PARAM.FREQUENCY [current_hw_target]]}
    return "JTAG clock $f Hz"
}
proc t2_connect {} {
    t2_hw_connect
    puts "T2: connected (device $::T2_DEV; [t2_hw_info]). Next: t2_program full int16"
}
proc t2__init_outputs {} {
    # after a full program every VIO output is 0 in hardware; writing 0 resyncs the cache (G11)
    foreach n {vio_decouple vio_rm_rst vio_start vio_sel} { t2_hw_write $n 0 }
    t2_hw_write vio_a [string repeat 0 64]
    t2_hw_write vio_b [string repeat 0 64]
}
proc t2_program {kind prec} {
    set path [t2_bitfile $kind $prec]
    puts "T2: program $kind $prec  ([file tail $path]) ..."
    set ms [t2_hw_program $path]
    if {$kind eq "full"} { t2__init_outputs }
    puts [format "T2:   done in %d ms" $ms]
    return $ms
}
proc t2_status {} {
    lassign [t2_hw_read {vio_rm_id vio_uptime vio_flags vio_runs vio_result}] id up fl rn rs
    set f [t2_hex2u $fl]
    set s [format "rm_id %s (%s)  uptime %d s  done %d ovf %d busy %d blocked %d  runs %d  result %s" \
        [t2_norm_id $id] [t2_prec_of [t2_norm_id $id]] [t2_hex2u $up] \
        [expr {$f & 1}] [expr {($f>>1)&1}] [expr {($f>>2)&1}] [expr {($f>>3)&1}] [t2_hex2u $rn] [t2_hex8 [t2_hex2s32 $rs]]]
    puts "T2: $s"
    return $s
}
# list the probes on the VIO core and check that all 11 locked names resolve (run once after the first full program)
proc t2_probes {} {
    set names {vio_decouple vio_rm_rst vio_start vio_sel vio_a vio_b vio_result vio_rm_id vio_uptime vio_flags vio_runs}
    if {$::T2_MOCK} { puts "T2: probes: all 11 resolved (mock)"; return 1 }
    foreach p [get_hw_probes -quiet -of_objects [t2__vio]] {
        set w "?"; catch {set w [get_property WIDTH $p]}
        puts [format "  %-24s width %s" [get_property NAME $p] $w]
    }
    set bad 0
    foreach n $names { if {[catch {t2__probe $n} m]} { puts "  MISSING $n : $m"; incr bad } }
    if {$bad == 0} { puts "T2: probes: all 11 resolved" } else { puts "T2: probes: $bad MISSING (see T2_ALIAS in the runbook)" }
    return [expr {$bad == 0}]
}
proc t2_rmid {}   { return [t2_norm_id [lindex [t2_hw_read {vio_rm_id}] 0]] }
proc t2_prec_of {id} {
    if {[info exists ::T2_PREC_OF($id)]} { return $::T2_PREC_OF($id) }
    return "unknown"
}
proc t2_uptime {} { return [t2_hex2u [lindex [t2_hw_read {vio_uptime}] 0]] }
proc t2_flags {}  {
    set f [t2_hex2u [lindex [t2_hw_read {vio_flags}] 0]]
    return [list [expr {$f & 1}] [expr {($f>>1)&1}] [expr {($f>>2)&1}] [expr {($f>>3)&1}]]
}
proc t2_load_probes {a b} {
    t2_hw_write vio_a $a
    t2_hw_write vio_b $b
}
proc t2_load {A B} { t2_load_probes [t2_pack256 $A] [t2_pack256 $B]; set ::T2_LAST_CASE "" }
proc t2_load_case {case {prec ""}} {
    if {$prec eq ""} { set prec [t2_prec_of [t2_rmid]] }
    if {$prec eq "decoupled"} { error "RP is decoupled" }
    lassign [t2_case_probes $prec $case] a b
    if {[t2_pack256 [t2_unpack256 $a]] ne $a} { error "probe string round-trip failed for $case" }
    t2_load_probes $a $b
    set ::T2_LAST_CASE $case
}
# pulse start; returns 1 if the run was accepted and completed
proc t2_run {} {
    set r0 [t2_hex2u [lindex [t2_hw_read {vio_runs}] 0]]
    t2_hw_write vio_start 0
    t2_hw_write vio_start 1
    t2_hw_write vio_start 0
    set done 0; set rn $r0
    for {set i 0} {$i < 20} {incr i} {
        lassign [t2_hw_read {vio_flags vio_runs}] fl rh
        set rn [t2_hex2u $rh]
        if {[t2_hex2u $fl] & 1} { set done 1; break }
        t2_wait 5
    }
    if {$rn != (($r0 + 1) & 0xFFFF)} { puts "T2:   run NOT accepted (runs $r0 -> $rn)"; return 0 }
    if {!$done} { puts "T2:   run accepted but done never set"; return 0 }
    return 1
}
# returns {C ovf}, 16 signed int32 and 16 bits
proc t2_read_c {} {
    set c {}; set o {}
    for {set k 0} {$k < 16} {incr k} {
        t2_hw_write vio_sel [format %X $k]
        lassign [t2_hw_read {vio_result vio_flags}] rs fl
        lappend c [t2_hex2s32 $rs]
        lappend o [expr {([t2_hex2u $fl] >> 1) & 1}]
    }
    return [list $c $o]
}
proc t2_print_c {C {title ""}} {
    if {$title ne ""} { puts "    $title" }
    for {set i 0} {$i < 4} {incr i} {
        set row "     "
        for {set j 0} {$j < 4} {incr j} { append row [format " %12d" [lindex $C [expr {4*$i+$j}]]] }
        puts $row
    }
}

# ---------------------------------------------------------------- checks
# run one golden case on whatever RM is loaded; returns 1 = PASS, 0 = FAIL
proc t2_check {case {verbose 1}} {
    set id [t2_rmid]
    set prec [t2_prec_of $id]
    if {$prec eq "unknown"} { puts "T2: unknown rm_id $id"; return 0 }
    if {$prec eq "decoupled"} { puts "T2: RP is decoupled (rm_id ff)"; return 0 }
    t2_load_case $case $prec
    if {![t2_run]} { return 0 }
    lassign [t2_read_c] c o
    lassign [t2_case_golden $prec $case] gc go
    set bad 0
    for {set k 0} {$k < 16} {incr k} {
        if {[lindex $c $k] != [lindex $gc $k] || [lindex $o $k] != [lindex $go $k]} {
            if {$bad < 4} {
                puts [format "T2:   %s/%s \[%d\]: got %s ovf %d, expected %s ovf %d" $prec $case $k \
                    [t2_hex8 [lindex $c $k]] [lindex $o $k] [t2_hex8 [lindex $gc $k]] [lindex $go $k]]
            }
            incr bad
        }
    }
    set ok [expr {$bad == 0}]
    if {$verbose} {
        puts [format "T2: check %-14s on %-5s : %s  (C\[0\]\[2\] = %s)" $case $prec \
            [expr {$ok ? "PASS" : "FAIL ($bad/16 wrong)"}] [t2_hex8 [lindex $c 2]]]
    }
    return $ok
}
proc t2_check_set {{cases ""}} {
    if {$cases eq ""} { set cases $::T2_BOARD_CASES }
    set n 0
    foreach cs $cases { incr n [t2_check $cs 0] }
    return [list $n [llength $cases]]
}

# all 9 golden cases on whatever RM is loaded (about a minute); 1 = all pass
proc t2_check_all {} {
    set cases {identity ones zeros counting asym_small random_inrange random_full extremes_neg extremes_mix}
    set prec [t2_prec_of [t2_rmid]]
    set n 0
    foreach cs $cases { incr n [t2_check $cs 1] }
    set ok [expr {$n == [llength $cases]}]
    puts "T2: ALL CASES on $prec: $n/[llength $cases] [expr {$ok ? "PASS" : "FAIL"}]"
    return $ok
}

# decouple -> partial -> release; returns program ms
proc t2_swap {prec} {
    t2_hw_write vio_decouple 1
    set ms [t2_program partial $prec]
    t2_hw_write vio_decouple 1
    t2_hw_write vio_decouple 0
    t2_wait 10
    set id [t2_rmid]
    if {$id ne $::T2_CODE($prec)} { puts "T2:   WARNING rm_id $id after swap, expected $::T2_CODE($prec)" }
    return $ms
}
proc t2__continuity {before after ms} {
    return [expr {$after - $before >= $ms / 1000}]
}
proc t2_swap_demo {prec} {
    lassign [t2_hw_read {vio_rm_id vio_result vio_uptime}] id rs up
    set before [t2_hex2u $up]
    puts [format "BEFORE   : rm_id %s  result %s  uptime %d s" [t2_norm_id $id] [t2_hex8 [t2_hex2s32 $rs]] $before]
    t2_hw_write vio_decouple 1
    lassign [t2_hw_read {vio_rm_id vio_result}] id rs
    set dec_ok [expr {[t2_norm_id $id] eq "ff" && [t2_hex2s32 $rs] == 0}]
    puts [format "DECOUPLE -> rm_id %s  result %s" [t2_norm_id $id] [t2_hex8 [t2_hex2s32 $rs]]]
    set path [t2_bitfile partial $prec]
    set ms [t2_hw_program $path]
    puts [format "PROGRAM  %s ... %d ms" [file tail $path] $ms]
    t2_hw_write vio_decouple 1
    t2_hw_write vio_decouple 0
    t2_wait 10
    lassign [t2_hw_read {vio_rm_id vio_uptime}] id up
    set after [t2_hex2u $up]
    set id [t2_norm_id $id]
    set id_ok [string equal $id $::T2_CODE($prec)]
    set cont [t2__continuity $before $after $ms]
    puts [format "RELEASE  -> rm_id %s (expected %s)" $id $::T2_CODE($prec)]
    puts [format "AFTER    : uptime %d s (%+d s; static %s)" $after [expr {$after - $before}] \
        [expr {$cont ? "NOT reset" : "RESET?!"}]]
    set chk 1
    foreach cs {counting extremes_neg} { set chk [expr {[t2_check $cs] && $chk}] }
    set ok [expr {$dec_ok && $id_ok && $cont && $chk}]
    puts "VERDICT  : [expr {$ok ? "PASS" : "FAIL"}]"
    return $ok
}
proc t2_block_test {} {
    set ok 1
    foreach {how n} {decouple vio_decouple rm_rst vio_rm_rst} {
        t2_hw_write $n 1
        set r0 [t2_hex2u [lindex [t2_hw_read {vio_runs}] 0]]
        t2_hw_write vio_start 0; t2_hw_write vio_start 1; t2_hw_write vio_start 0
        lassign [t2_hw_read {vio_runs vio_flags}] rh fl
        set r1 [t2_hex2u $rh]; set blocked [expr {([t2_hex2u $fl] >> 3) & 1}]
        set pass [expr {$r1 == $r0 && $blocked == 1}]
        puts [format "T2: start while %-8s: runs %d -> %d, blocked %d : %s" $how $r0 $r1 $blocked \
            [expr {$pass ? "refused (PASS)" : "ACCEPTED (FAIL)"}]]
        set ok [expr {$ok && $pass}]
        t2_hw_write $n 0
    }
    set r0 [t2_hex2u [lindex [t2_hw_read {vio_runs}] 0]]
    set acc [t2_run]
    lassign [t2_flags] d o b bl
    set pass [expr {$acc && $bl == 0}]
    puts [format "T2: start after release : accepted %d, blocked %d : %s" $acc $bl [expr {$pass ? "PASS" : "FAIL"}]]
    set ok [expr {$ok && $pass}]
    puts "T2: block test [expr {$ok ? "PASS" : "FAIL"}]"
    return $ok
}
proc t2_full_contrast {} {
    for {set i 0} {$i < 10 && [t2_uptime] < 3} {incr i} { t2_wait 500 }
    set before [t2_uptime]
    set ms [t2_program full int16]
    set after [t2_uptime]
    set ok [expr {$after < $before}]
    puts [format "T2: full program %d ms, uptime %d -> %d : %s" $ms $before $after \
        [expr {$ok ? "static reset as expected (PASS)" : "NOT reset (FAIL)"}]]
    return $ok
}
# swap to prec, re-run the last case (or the given one), print C
proc t2_set_precision {prec {case ""}} {
    if {$case eq ""} { set case $::T2_LAST_CASE }
    if {$case eq ""} { set case counting }
    if {[t2_prec_of [t2_rmid]] ne $prec} {
        set ms [t2_swap $prec]
        puts "T2: now $prec (swap $ms ms)"
    }
    t2_load_case $case $prec
    if {![t2_run]} { return 0 }
    lassign [t2_read_c] c o
    t2_print_c $c "$case on $prec:"
    lassign [t2_case_golden $prec $case] gc go
    set ok [expr {$c eq $gc}]
    puts "T2: matches golden: [expr {$ok ? "yes" : "NO"}]"
    return $ok
}

# ---------------------------------------------------------------- CSV
proc t2__csv {prefix header rows} {
    file mkdir $::T2_REPORT_DIR
    set path [file join $::T2_REPORT_DIR "${prefix}_[clock format [clock seconds] -format %Y%m%d_%H%M%S].csv"]
    set f [open $path w]
    puts $f $header
    foreach r $rows { puts $f [join $r ,] }
    close $f
    return $path
}

# ---------------------------------------------------------------- demo
proc t2_demo {{cases {counting random_full extremes_neg}}} {
    if {[t2_prec_of [t2_rmid]] ne "int16"} { t2_swap int16 }
    set rows {}; set ok 1
    foreach prec {int16 int8 int4} {
        set ms "-"
        if {$prec ne "int16"} { set ms [t2_swap $prec] }
        puts [format "T2: --- %s loaded (swap %s ms) ---" $prec $ms]
        foreach cs $cases {
            t2_load_case $cs $prec
            if {![t2_run]} { set ok 0; set R($prec,$cs) [lrepeat 16 0]; continue }
            lassign [t2_read_c] c o
            lassign [t2_case_golden $prec $cs] gc go
            set R($prec,$cs) $c
            for {set k 0} {$k < 16} {incr k} {
                set m [expr {[lindex $c $k] == [lindex $gc $k]}]
                if {!$m} { set ok 0 }
                lappend rows [list $cs $prec $k [lindex $c $k] [lindex $gc $k] $m [lindex $o $k] $ms]
            }
        }
    }
    foreach cs $cases {
        puts "T2: $cs  (element: int16 | int8 | int4, * = differs from int16)"
        for {set k 0} {$k < 16} {incr k} {
            set line [format "      C\[%d\]\[%d\] %12s" [expr {$k/4}] [expr {$k%4}] [lindex $R(int16,$cs) $k]]
            foreach p {int8 int4} {
                set v [lindex $R($p,$cs) $k]
                append line [format " | %12s%s" $v [expr {$v == [lindex $R(int16,$cs) $k] ? " " : "*"}]]
            }
            puts $line
        }
    }
    t2_swap int16
    set path [t2__csv hw_demo "case,prec,idx,c_hw,c_golden,match,ovf,swap_ms" $rows]
    puts "T2: demo [expr {$ok ? "PASS (every element matches its precision's golden)" : "FAIL"}]  -> $path"
    return $ok
}

# ---------------------------------------------------------------- self-test
proc t2_selftest {{rounds 3}} {
    set rows {}; set step 0; set nfail 0
    # step 1: full int16
    set ms [t2_program full int16]
    lassign [t2_check_set] np nt
    set id [t2_rmid]
    set v [expr {$id eq "16" && $np == $nt}]
    lappend rows [list [incr step] full t2_full_int16.bit - $ms - [t2_uptime] n/a $id $np $nt [expr {$v?"PASS":"FAIL"}]]
    if {!$v} { incr nfail }
    # step 2: full int16 again, must reset uptime
    for {set i 0} {$i < 10 && [t2_uptime] < 3} {incr i} { t2_wait 500 }
    set before [t2_uptime]
    set ms [t2_program full int16]
    set after [t2_uptime]
    lassign [t2_check_set] np nt
    set id [t2_rmid]
    set reset [expr {$after < $before}]
    set v [expr {$reset && $id eq "16" && $np == $nt}]
    lappend rows [list [incr step] full t2_full_int16.bit - $ms $before $after [expr {$reset?"reset=yes":"reset=NO"}] $id $np $nt [expr {$v?"PASS":"FAIL"}]]
    if {!$v} { incr nfail }
    # partial rounds
    for {set r 1} {$r <= $rounds} {incr r} {
        foreach prec {int8 int4 grey int16} {
            set before [t2_uptime]
            set ms [t2_swap $prec]
            set after [t2_uptime]
            set cont [t2__continuity $before $after $ms]
            set id [t2_rmid]
            if {$prec eq "grey"} { set cs counting } else { set cs "" }
            lassign [t2_check_set $cs] np nt
            set v [expr {$cont && $id eq $::T2_CODE($prec) && $np == $nt}]
            lappend rows [list [incr step] partial_$prec t2_partial_$prec.bit - $ms $before $after \
                [expr {$cont?"continuity=yes":"continuity=NO"}] $id $np $nt [expr {$v?"PASS":"FAIL"}]]
            if {!$v} { incr nfail }
            puts [format "T2: step %2d partial %-5s %5d ms  uptime %d -> %d  rm_id %s  cases %d/%d  %s" \
                $step $prec $ms $before $after $id $np $nt [expr {$v?"PASS":"FAIL"}]]
        }
    }
    # fill byte sizes from the manifest
    array set sz [t2_manifest]
    set out {}
    foreach row $rows {
        set fn [lindex $row 2]
        if {[info exists sz($fn)]} { lset row 3 $sz($fn) }
        lappend out $row
    }
    set path [t2__csv hw_selftest "step,op,file,bytes,ms,uptime_before,uptime_after,check,rm_id,cases_pass,cases_total,verdict" $out]
    set ok [expr {$nfail == 0}]
    puts "T2 SELFTEST [expr {$ok ? "PASS" : "FAIL ($nfail/$step steps failed)"}]  -> $path"
    return $ok
}

puts "hw_t2.tcl loaded (mock=$::T2_MOCK). Procs: t2_connect t2_program t2_status t2_check t2_swap t2_swap_demo"
puts "  t2_probes t2_check_all t2_block_test t2_demo t2_set_precision t2_full_contrast t2_selftest t2_load t2_load_case t2_run t2_read_c"
