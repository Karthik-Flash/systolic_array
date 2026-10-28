# video_t2.tcl -- one-step commands for the 30-45 s demo video (docs/t2/VIDEO_SHOT_LIST.md)
#
# Usage (Vivado 2022.2 Hardware Manager, Tcl console), after t2_connect and t2_program full int16:
#   source D:/Projects/RC_Project/scripts/t2/video_t2.tcl
#   vid_ready ; vid_1 ; vid_2 ; vid_3 ; vid_4      (then vid_1 again for the next take)
#
# Story: the same input (A all 200, B all 1) on int16 -> int8 -> int4 gives C[0][0] = 800 -> 508 -> 28,
# while the static region keeps running; vid_4 is a full reprogram that restarts the whole chip.
# Each vid_* proc does one step and prints one or two short lines. It calls the hardware wrappers
# of hw_t2.tcl directly (not t2_swap / t2_program) so their progress lines stay out of the shot.
# Tcl 8.5: no lmap; hex strings never go through expr; hex built with format.

if {[llength [info procs t2_hw_program]] == 0} {
    source [file join [file dirname [file normalize [info script]]] hw_t2.tcl]
}

set ::VID_A [lrepeat 16 200]
set ::VID_B [lrepeat 16 1]
array set ::VID_EXPECT {int16 800 int8 508 int4 28}
array set ::VID_NOTE   {int16 "" int8 "   (200 clamped to 127)" int4 "   (200 clamped to 7)"}
# Vivado messages printed by every program_hw_devices / refresh; hidden by vid_ready, restored by vid_verbose
set ::VID_MSG_IDS {{Labtools 27-3164} {Labtools 27-2302} {Labtools 27-1434} {Labtools 27-1435} {Labtools 27-1952}}

proc vid_verbose {} {
    if {$::T2_MOCK} { return }
    foreach id $::VID_MSG_IDS { catch {reset_msg_config -id $id -suppress} }
    puts "Vivado program messages shown again"
}

# decouple -> partial -> release, silently; returns program ms, or -1 if the module ID is wrong
proc vid__swap {prec} {
    t2_hw_write vio_decouple 1
    set ms [t2_hw_program [t2_bitfile partial $prec]]
    t2_hw_write vio_decouple 1
    t2_hw_write vio_decouple 0
    t2_wait 10
    if {[t2_rmid] ne $::T2_CODE($prec)} { return -1 }
    return $ms
}

# load A = 16 x 200, B = 16 x 1, run, return C[0][0] (or "" if the run failed)
proc vid__run {} {
    t2_load $::VID_A $::VID_B
    if {![t2_run]} { return "" }
    t2_hw_write vio_sel [format %X 0]
    return [t2_hex2s32 [lindex [t2_hw_read {vio_result}] 0]]
}

# run on the loaded module and print the result line; 1 = OK
proc vid__result {prec} {
    set c [vid__run]
    set e $::VID_EXPECT($prec)
    if {$c eq "" || $c != $e} {
        puts "MISMATCH got [expr {$c eq "" ? "no result (run failed)" : $c}] expected $e"
        return 0
    }
    puts [format "%-7s result %-5d expected %-4d OK%s" $prec $c $e $::VID_NOTE($prec)]
    return 1
}

proc vid__swap_step {prec} {
    set before [t2_uptime]
    set ms [vid__swap $prec]
    set after [t2_uptime]
    if {$ms < 0} { puts "MISMATCH got rm_id [t2_rmid] expected $::T2_CODE($prec)"; return 0 }
    if {$after < $before} { puts "MISMATCH got uptime $before -> $after s expected no reset"; return 0 }
    puts [format "swap to %s in %d ms | uptime %d -> %d s (not reset)" $prec $ms $before $after]
    return [vid__result $prec]
}

proc vid_ready {} {
    if {$::T2_DEV eq ""} { puts "NOT READY: run t2_connect, then t2_program full int16"; return 0 }
    if {[catch {t2_rmid} id]} { puts "NOT READY: no VIO core, run t2_program full int16"; return 0 }
    if {!$::T2_MOCK} {
        foreach mid $::VID_MSG_IDS { catch {set_msg_config -id $mid -suppress} }
    }
    if {$id ne "16"} {
        if {[vid__swap int16] < 0} { puts "MISMATCH got rm_id [t2_rmid] expected 16"; return 0 }
    }
    puts "READY: int16 loaded, uptime [t2_uptime] s"
    return 1
}

proc vid_1 {} {
    if {[t2_rmid] ne "16" && [vid__swap int16] < 0} { puts "MISMATCH got rm_id [t2_rmid] expected 16"; return 0 }
    return [vid__result int16]
}
proc vid_2 {} { return [vid__swap_step int8] }
proc vid_3 {} { return [vid__swap_step int4] }

proc vid_4 {} {
    for {set i 0} {$i < 10 && [t2_uptime] < 3} {incr i} { t2_wait 500 }
    set before [t2_uptime]
    set ms [t2_hw_program [t2_bitfile full int16]]
    t2__init_outputs
    set after [t2_uptime]
    if {$after >= $before} { puts "MISMATCH got uptime $before -> $after s expected a reset"; return 0 }
    if {[t2_rmid] ne "16"} { puts "MISMATCH got rm_id [t2_rmid] expected 16"; return 0 }
    puts [format "FULL reprogram in %d ms | uptime %d -> %d s (whole chip restarted)" $ms $before $after]
    return 1
}

puts "video_t2.tcl loaded: vid_ready vid_1 vid_2 vid_3 vid_4 (vid_verbose restores Vivado messages)"
