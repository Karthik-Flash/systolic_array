# hw_t2_mock.tcl -- run hw_t2.tcl against a simulated ZedBoard (docs/t2/T2_PLAN.md §11.2)
#
# Run from PowerShell (G28), in a scratch folder:
#   mkdir D:\Projects\RC_Project\vivado\scratch_t2 ; cd D:\Projects\RC_Project\vivado\scratch_t2
#   C:\Xilinx\Vivado\2022.2\bin\vivado.bat -mode batch -nojournal -nolog -source ..\..\scripts\t2\hw_t2_mock.tcl
# Expect the last two lines:  MOCK TESTS PASS  /  NEGATIVE MOCKS OK (5/5 failed as required)
#
# The device computes results with its OWN Tcl clamp + matmul + sat32 from the probe strings it
# receives, so a pass also proves that the Tcl packing/parsing agrees with Python's golden files.

set ::T2_MOCK 1
set ::MOCK_DIR [file normalize [file dirname [info script]]]
if {![info exists ::T2_REPORT_DIR]} { set ::T2_REPORT_DIR [file join [pwd] mock_reports] }
source [file join $::MOCK_DIR hw_t2.tcl]

# ------------------------------------------------------------ simulated device
array set ::MF {partial_resets_uptime 0 reverse_lanes 0 int8_no_clamp 0 start_ungated 0}
proc mock_reset_device {} {
    array set ::MD {loaded blank prec "" vclock 0 base 0 decouple 0 rm_rst 0 start 0 sel 0
                    runs 0 blocked 0 done 0}
    set ::MD(a) [string repeat 0 64]; set ::MD(b) [string repeat 0 64]
    set ::MD(C) [lrepeat 16 0]; set ::MD(O) [lrepeat 16 0]
}
mock_reset_device
proc mock_wait {ms}  { set ::MD(vclock) [expr {$::MD(vclock) + $ms}] }
proc mock_connect {} { set ::T2_DEV mock_xc7z020_1 }
proc mock_program {path} {
    set name [file tail $path]
    if {![regexp {^t2_(full|partial)_(int16|int8|int4|grey)\.bit$} $name -> kind prec]} {
        error "mock: unexpected bitstream $name"
    }
    array set sz [t2_manifest]
    if {[info exists sz($name)]} { set bytes $sz($name) } elseif {[file exists $path]} { set bytes [file size $path]
    } elseif {$kind eq "full"} { set bytes 4045667 } else { set bytes 585560 }
    if {$kind eq "partial" && $::MD(loaded) eq "blank"} {
        error "\[Xicom 50-103\] Static bitstream must first be programmed (mock)"
    }
    set ms [expr {130 + int(0.00221 * $bytes)}]
    mock_wait $ms
    set ::MD(prec) $prec
    set ::MD(C) [lrepeat 16 0]; set ::MD(O) [lrepeat 16 0]; set ::MD(done) 0
    if {$kind eq "full"} {
        set keep [list $::MD(vclock)]
        array set ::MD {decouple 0 rm_rst 0 start 0 sel 0 runs 0 blocked 0}
        set ::MD(a) [string repeat 0 64]; set ::MD(b) [string repeat 0 64]
        set ::MD(base) [lindex $keep 0]; set ::MD(loaded) full
    } else {
        if {$::MF(partial_resets_uptime)} { set ::MD(base) $::MD(vclock) }
    }
    return $ms
}
proc mock_clamp {v w} {
    set lo [expr {-(1 << ($w - 1))}]; set hi [expr {(1 << ($w - 1)) - 1}]
    if {$v < $lo} { return $lo }
    if {$v > $hi} { return $hi }
    return $v
}
proc mock_compute {} {
    set A [t2_unpack256 $::MD(a)]; set B [t2_unpack256 $::MD(b)]
    if {$::MF(reverse_lanes)} {
        set A [lreverse $A]; set B [lreverse $B]
    }
    array set W {int16 16 int8 8 int4 4}
    set C {}; set O {}
    for {set k 0} {$k < 16} {incr k} {
        set i [expr {$k / 4}]; set j [expr {$k % 4}]
        if {$::MD(prec) eq "grey"} { lappend C 0; lappend O 0; continue }
        set w $W($::MD(prec))
        if {$::MD(prec) eq "int8" && $::MF(int8_no_clamp)} { set w 16 }
        set s 0
        for {set q 0} {$q < 4} {incr q} {
            set s [expr {$s + [mock_clamp [lindex $A [expr {4*$i+$q}]] $w] * [mock_clamp [lindex $B [expr {4*$q+$j}]] $w]}]
        }
        set t [mock_clamp $s 32]
        lappend C $t; lappend O [expr {$t != $s}]
    }
    set ::MD(C) $C; set ::MD(O) $O
}
proc mock_rm_held {} { return [expr {$::MD(decouple) || $::MD(rm_rst)}] }
proc mock_write {name value} {
    if {$::MD(loaded) eq "blank"} { error "mock: no VIO core (blank device)" }
    mock_wait 20
    switch -- $name {
        vio_decouple - vio_rm_rst {
            set v [t2_hex2u $value]
            set key [expr {$name eq "vio_decouple" ? "decouple" : "rm_rst"}]
            set ::MD($key) $v
            if {$v} { set ::MD(done) 0; set ::MD(C) [lrepeat 16 0]; set ::MD(O) [lrepeat 16 0] }
        }
        vio_start {
            set v [t2_hex2u $value]
            if {$v && !$::MD(start)} {
                if {![mock_rm_held] || $::MF(start_ungated)} {
                    set ::MD(runs) [expr {($::MD(runs) + 1) & 0xFFFF}]
                    set ::MD(blocked) 0
                    if {[mock_rm_held]} { set ::MD(C) [lrepeat 16 0]; set ::MD(O) [lrepeat 16 0] } else { mock_compute }
                    set ::MD(done) [expr {![mock_rm_held]}]
                } else {
                    set ::MD(blocked) 1
                }
            }
            set ::MD(start) $v
        }
        vio_sel { set ::MD(sel) [t2_hex2u $value] }
        vio_a   { set ::MD(a) [string toupper $value] }
        vio_b   { set ::MD(b) [string toupper $value] }
        default { error "mock: unknown output probe $name" }
    }
}
proc mock_read {names} {
    if {$::MD(loaded) eq "blank"} { error "mock: no VIO core (blank device)" }
    mock_wait 20
    set out {}
    foreach n $names {
        switch -- $n {
            vio_result {
                # if/else, not expr ?: -- expr turns a hex string like 00007E45 into the float 7e+45 (G19)
                if {$::MD(decouple)} { lappend out 00000000 } else { lappend out [t2_hex8 [lindex $::MD(C) $::MD(sel)]] }
            }
            vio_rm_id {
                if {$::MD(decouple)} { lappend out FF } elseif {$::MD(rm_rst)} { lappend out 00 } else { lappend out $::T2_CODE($::MD(prec)) }
            }
            vio_uptime { lappend out [format %08X [expr {($::MD(vclock) - $::MD(base)) / 1000}]] }
            vio_flags {
                set ovf [expr {$::MD(decouple) ? 0 : [lindex $::MD(O) $::MD(sel)]}]
                lappend out [format %X [expr {($::MD(blocked) << 3) | ($ovf << 1) | $::MD(done)}]]
            }
            vio_runs { lappend out [format %04X $::MD(runs)] }
            default { error "mock: unknown input probe $n" }
        }
    }
    return $out
}

# ------------------------------------------------------------ test driver
set ::FAILS {}
proc expect {what cond} {
    if {$cond} { puts "MOCK  ok   $what" } else { puts "MOCK  FAIL $what"; lappend ::FAILS $what }
}
proc fresh {} { mock_reset_device; t2_connect }

puts "\n================ positive suite ================"
# self-tests of the helpers
expect "hex2s32 FFFFFF20 = -224"        [expr {[t2_hex2s32 FFFFFF20] == -224}]
expect "hex2u 0000_006E = 110"          [expr {[t2_hex2u 0000_006E] == 110}]
expect "norm_id 08 stays 08 (octal trap)" [string equal [t2_norm_id 08] 08]
set M {1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 -1}
expect "pack/unpack round trip"         [string equal [t2_unpack256 [t2_pack256 $M]] $M]
expect "A\[0\]\[0\] is the last 4 digits" [string equal [string range [t2_pack256 $M] end-3 end] 0001]

fresh
t2_program full int16
set all {identity ones zeros counting asym_small random_inrange random_full extremes_neg extremes_mix}
foreach prec {int16 int8 int4} {
    if {$prec ne "int16"} { t2_swap $prec }
    set n 0
    foreach cs $all { incr n [t2_check $cs 0] }
    expect "$prec: all 9 golden cases bit-exact ($n/9)" [expr {$n == 9}]
}
t2_swap int16
expect "t2_block_test"            [t2_block_test]
foreach p {int8 int4 grey int16} { expect "t2_swap_demo $p" [t2_swap_demo $p] }
expect "t2_set_precision int4"    [t2_set_precision int4 counting]
expect "t2_demo"                  [t2_demo]
expect "t2_full_contrast"         [t2_full_contrast]
expect "t2_selftest 3"            [t2_selftest 3]
set pos_ok [expr {[llength $::FAILS] == 0}]

puts "\n================ negative mocks (each must FAIL) ================"
set neg 0
# NM1 partial resets uptime -> selftest continuity must fail
fresh; set ::MF(partial_resets_uptime) 1
set r [t2_selftest 1]; set ::MF(partial_resets_uptime) 0
puts "NM1 partial resets uptime        -> selftest [expr {$r ? "PASSED (BAD)" : "failed (good)"}]"; if {!$r} { incr neg }
# NM2 device reverses lanes -> asym check must fail
fresh; t2_program full int16; set ::MF(reverse_lanes) 1
set r [t2_check asym_small]; set ::MF(reverse_lanes) 0
puts "NM2 reversed probe lanes         -> check [expr {$r ? "PASSED (BAD)" : "failed (good)"}]"; if {!$r} { incr neg }
# NM3 int8 RM without clamp -> random_full / extremes must fail
fresh; t2_program full int16; t2_swap int8; set ::MF(int8_no_clamp) 1
set r [expr {[t2_check random_full] && [t2_check extremes_neg]}]; set ::MF(int8_no_clamp) 0
puts "NM3 int8 without input clamp     -> checks [expr {$r ? "PASSED (BAD)" : "failed (good)"}]"; if {!$r} { incr neg }
# NM4 start accepted while decoupled -> block test must fail
fresh; t2_program full int16; set ::MF(start_ungated) 1
set r [t2_block_test]; set ::MF(start_ungated) 0
puts "NM4 start accepted while decoupled -> block test [expr {$r ? "PASSED (BAD)" : "failed (good)"}]"; if {!$r} { incr neg }
# NM5 partial before any full -> must raise
fresh
set r [expr {![catch {t2_program partial int8} msg]}]
puts "NM5 partial on blank device      -> [expr {$r ? "accepted (BAD)" : "refused (good): $msg"}]"; if {!$r} { incr neg }

puts ""
if {$pos_ok} { puts "MOCK TESTS PASS" } else { puts "MOCK TESTS FAIL: $::FAILS" }
if {$neg == 5} { puts "NEGATIVE MOCKS OK (5/5 failed as required)" } else { puts "NEGATIVE MOCKS BAD ($neg/5 failed)" }
