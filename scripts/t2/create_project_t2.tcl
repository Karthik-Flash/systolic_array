# create_project_t2.tcl -- T2_PLAN sec. 8.4 / 9.3: create the T2 DFX project t2_dfx.
#
# Real project (Vivado GUI Tcl console, Phase B):
#   cd D:/Projects/RC_Project/vivado
#   source D:/Projects/RC_Project/scripts/t2/create_project_t2.tcl
#   -> creates D:/Projects/RC_Project/vivado/t2_dfx
# Scratch validation (batch, Phase A1), from vivado/scratch_t2/:
#   vivado -mode batch -source ../../scripts/t2/create_project_t2.tcl -tclargs <dir> [synth]
#   <dir> may already exist only under vivado/scratch_t2/; `synth` is allowed only there.
#
# Command forms come from T1's own journal and project file (docs/t2/ref/t1_journal_excerpt.tcl,
# docs/t2/ref/t1_project_facts.md). Every source is added BY REFERENCE (never copied).
# Never launches implementation. Never touches vivado/t1_dfx.

source [file join [file dirname [info script]] t2_filesets.tcl]
set root $::T2_ROOT
set scratch [file normalize $root/vivado/scratch_t2]

proc t2_step {n msg} { puts "\[T2\] step $n $msg" }
proc t2_fail {msg}   { puts "\[T2\] ASSERT FAILED: $msg"; error "T2 project script stopped: $msg" }
proc t2_norm {paths} {
    set out {}
    foreach p $paths { lappend out [string tolower [file normalize $p]] }
    return [lsort $out]
}
proc t2_abs {rel} { return [file normalize $::T2_ROOT/$rel] }

# ---- arguments ----
set args_in [expr {[info exists ::argv] ? $::argv : {}}]
set proj_dir [file normalize $root/vivado/t2_dfx]
set do_synth 0
foreach a $args_in {
    # only an absolute path counts as <dir>, so a stray launcher argument can never redirect the project
    if {$a eq "synth"} { set do_synth 1 } elseif {[file pathtype $a] eq "absolute"} { set proj_dir [file normalize $a] }
}
set in_scratch [string match -nocase "$scratch/*" $proj_dir]
if {$do_synth && !$in_scratch} { t2_fail "`synth` is allowed only under $scratch" }
if {[file exists $proj_dir]} {
    if {!$in_scratch} { t2_fail "$proj_dir already exists; refusing (delete it yourself if that is intended)" }
    file delete -force $proj_dir
}

# ---- 1. project ----
t2_step 1 "create_project t2_dfx $proj_dir -part $::T2_PART"
create_project t2_dfx $proj_dir -part $::T2_PART
set_property target_language Verilog [current_project]

# ---- 2. static + rm_int16 sources, by reference ----
t2_step 2 "add static + rm_int16 sources to sources_1 (no copy)"
set static_abs {}
foreach f $::T2_STATIC_FILES { lappend static_abs [t2_abs $f] }
set int16_abs {}
foreach f $::T2_RM_FILES(rm_int16) { lappend int16_abs [t2_abs $f] }
add_files -norecurse -fileset sources_1 [concat $static_abs $int16_abs]
set_property top $::T2_TOP [get_filesets sources_1]
update_compile_order -fileset sources_1

# ---- 3. constraints ----
t2_step 3 "add constraints; Pblock XDC: implementation only, target file"
set xdc_pins [t2_abs $::T2_XDC_PINS]
set xdc_pb   [t2_abs $::T2_XDC_PBLOCK]
add_files -fileset constrs_1 -norecurse [list $xdc_pins $xdc_pb]
set_property used_in_synthesis false [get_files $xdc_pb]
set_property used_in_implementation true [get_files $xdc_pb]
set_property target_constrs_file $xdc_pb [get_filesets constrs_1]

# ---- 4. VIO IP ----
t2_step 4 "create_ip vio -module_name vio_t2 (in [join $::T2_VIO_IN_WIDTHS /], out [join $::T2_VIO_OUT_WIDTHS /])"
create_ip -name vio -vendor xilinx.com -library ip -version 3.0 -module_name vio_t2
set cfg [list CONFIG.C_EN_PROBE_IN_ACTIVITY {0} \
              CONFIG.C_NUM_PROBE_IN [llength $::T2_VIO_IN_WIDTHS] \
              CONFIG.C_NUM_PROBE_OUT [llength $::T2_VIO_OUT_WIDTHS] \
              CONFIG.Component_Name {vio_t2}]
set i 0
foreach w $::T2_VIO_IN_WIDTHS  { lappend cfg CONFIG.C_PROBE_IN${i}_WIDTH $w;  incr i }
set i 0
foreach w $::T2_VIO_OUT_WIDTHS { lappend cfg CONFIG.C_PROBE_OUT${i}_WIDTH $w; incr i }
set_property -dict $cfg [get_ips vio_t2]
set xci [get_files -of_objects [get_filesets sources_1] vio_t2.xci]
generate_target all $xci
create_ip_run $xci
update_compile_order -fileset sources_1

# ---- 5. DFX: partition definition + rm_int16 from the existing sources ----
t2_step 5 "PR_FLOW 1; create_partition_def pd_t2 -module rp_t2; rm_int16 -define_from rp_t2"
set_property PR_FLOW 1 [current_project]
create_partition_def -name pd_t2 -module rp_t2
create_reconfig_module -name rm_int16 -partition_def [get_partition_defs pd_t2] -define_from rp_t2

# ---- 6. rm_int8, rm_int4 ----
foreach rm {rm_int8 rm_int4} {
    t2_step 6 "create_reconfig_module $rm -top rp_t2 + add_files -of_objects ($::T2_RM_FILES($rm))"
    create_reconfig_module -name $rm -partition_def [get_partition_defs pd_t2] -top rp_t2
    set fl {}
    foreach f $::T2_RM_FILES($rm) { lappend fl [t2_abs $f] }
    if {[catch {add_files -norecurse $fl -of_objects [get_reconfig_modules $rm]} err]} {
        t2_fail "add_files to $rm refused (shared RM file?): $err"
    }
}

# ---- 7. assert filesets ----
t2_step 7 "assert filesets"
proc t2_rm_files {rm} { return [get_files -norecurse -of_objects [get_reconfig_modules $rm]] }
# rm_int16's submodules must not stay in sources_1; move them if -define_from left them there
set src1 [get_files -norecurse -of_objects [get_filesets sources_1]]
set moved {}
foreach f $int16_abs {
    if {[lsearch -exact [t2_norm $src1] [string tolower $f]] >= 0} { lappend moved $f }
}
if {[llength $moved]} {
    puts "\[T2\] note: moving from sources_1 into rm_int16: $moved"
    remove_files -fileset sources_1 $moved
    add_files -norecurse $moved -of_objects [get_reconfig_modules rm_int16]
}
set src1 [get_files -norecurse -of_objects [get_filesets sources_1]]
set src1_rtl {}
foreach f $src1 { if {[file extension $f] ne ".xci"} { lappend src1_rtl $f } }
if {[t2_norm $src1_rtl] ne [t2_norm $static_abs]} { t2_fail "sources_1 = $src1_rtl, expected $static_abs" }
if {[llength [get_ips vio_t2]] != 1} { t2_fail "vio_t2 IP missing" }
foreach rm $::T2_RMS {
    set want {}
    foreach f $::T2_RM_FILES($rm) { lappend want [t2_abs $f] }
    set have [t2_rm_files $rm]
    if {[t2_norm $have] ne [t2_norm $want]} { t2_fail "$rm fileset = $have, expected $want" }
}

# ---- 8. configurations + runs ----
t2_step 8 "configurations + implementation runs"
foreach {cfgname rm} $::T2_CFG_RM {
    if {$rm eq "greybox"} {
        create_pr_configuration -name $cfgname -partitions { } -greyboxes [list U_RP]
    } else {
        create_pr_configuration -name $cfgname -partitions [list U_RP:$rm]
    }
}
set flow [get_property FLOW [get_runs impl_1]]
foreach {run cfgname} $::T2_RUN_CFG {
    if {$run eq "impl_1"} {
        set_property PR_CONFIGURATION $cfgname [get_runs impl_1]
    } else {
        create_run $run -parent_run impl_1 -flow $flow -pr_config $cfgname
    }
}

# ---- 9. summary (everything read back from the project) ----
t2_step 9 "summary"
puts "\[T2\] project      : [get_property DIRECTORY [current_project]]  part [get_property PART [current_project]]  PR_FLOW [get_property PR_FLOW [current_project]]"
puts "\[T2\] top          : [get_property TOP [get_filesets sources_1]]"
puts "\[T2\] sources_1    : [lsort [get_files -norecurse -of_objects [get_filesets sources_1]]]"
foreach rm $::T2_RMS {
    puts "\[T2\] $rm fileset: [lsort [t2_rm_files $rm]]"
}
puts "\[T2\] partition def: [get_partition_defs]  RMs: [lsort [get_reconfig_modules]]"
foreach c [lsort [get_pr_configurations]] {
    puts "\[T2\] configuration $c : PARTITION_CELL_RMS={[get_property PARTITION_CELL_RMS [get_pr_configurations $c]]} GREYBOX_CELLS={[get_property GREYBOX_CELLS [get_pr_configurations $c]]}"
}
foreach {run cfgname} $::T2_RUN_CFG {
    set r [get_runs $run]
    set got [get_property PR_CONFIGURATION $r]
    puts "\[T2\] run $run -> $got  parent={[get_property PARENT $r]}  flow={[get_property FLOW $r]}"
    if {$got ne $cfgname} { t2_fail "$run has PR_CONFIGURATION $got, expected $cfgname" }
}
foreach x [list $xdc_pins $xdc_pb] {
    set fo [get_files $x]
    puts "\[T2\] xdc [file tail $x]: used_in_synthesis [get_property USED_IN_SYNTHESIS $fo] used_in_implementation [get_property USED_IN_IMPLEMENTATION $fo]"
}
set tgt [get_property TARGET_CONSTRS_FILE [get_filesets constrs_1]]
puts "\[T2\] target constraints file: $tgt"
if {[string tolower [file normalize $tgt]] ne [string tolower $xdc_pb]} { t2_fail "target constraints file is $tgt" }
if {[get_property USED_IN_SYNTHESIS [get_files $xdc_pb]]} { t2_fail "Pblock XDC is used in synthesis" }
set ip [get_ips vio_t2]
set win {}; set wout {}
for {set i 0} {$i < [get_property CONFIG.C_NUM_PROBE_IN $ip]} {incr i}  { lappend win  [get_property CONFIG.C_PROBE_IN${i}_WIDTH $ip] }
for {set i 0} {$i < [get_property CONFIG.C_NUM_PROBE_OUT $ip]} {incr i} { lappend wout [get_property CONFIG.C_PROBE_OUT${i}_WIDTH $ip] }
puts "\[T2\] vio_t2 widths in {$win} out {$wout} activity [get_property CONFIG.C_EN_PROBE_IN_ACTIVITY $ip]"
if {$win ne $::T2_VIO_IN_WIDTHS || $wout ne $::T2_VIO_OUT_WIDTHS} { t2_fail "VIO widths read back as in {$win} out {$wout}" }
puts "T2 PROJECT READY"

# ---- scratch only: synthesise static + 3 RMs, check, report ----
if {$do_synth} {
    set sruns {synth_1 rm_int16_synth_1 rm_int8_synth_1 rm_int4_synth_1}
    puts "\[T2\] launch_runs $sruns -jobs 4"
    launch_runs {*}$sruns -jobs 4
    foreach r $sruns { wait_on_run $r }
    set ok 1
    foreach r [concat vio_t2_synth_1 $sruns] {
        set st [get_property STATUS [get_runs $r]]
        set rpt [glob -nocomplain [get_property DIRECTORY [get_runs $r]]/*_utilization_synth.rpt]
        set lut ?; set ff ?; set dsp ?
        if {[llength $rpt] == 1} {
            set fh [open [lindex $rpt 0] r]; set u [read $fh]; close $fh
            regexp -line {^\|\s*Slice LUTs\*?\s*\|\s*([0-9]+)} $u -> lut
            regexp -line {^\|\s*Slice Registers\s*\|\s*([0-9]+)} $u -> ff
            regexp -line {^\|\s*DSPs\s*\|\s*([0-9]+)} $u -> dsp
        }
        puts [format "\[T2\] %-18s %-28s LUT %5s  FF %5s  DSP %3s" $r $st $lut $ff $dsp]
        if {![string match "*Complete*" $st]} { set ok 0 }
    }
    set dcp [get_property DIRECTORY [get_runs synth_1]]/${::T2_TOP}.dcp
    open_checkpoint $dcp
    set bb [get_property IS_BLACKBOX [get_cells U_RP]]
    puts "\[T2\] synth_1 U_RP: REF_NAME [get_property REF_NAME [get_cells U_RP]]  IS_BLACKBOX $bb  leaf cells inside [llength [get_cells -quiet -hier -filter {NAME =~ U_RP/* && IS_PRIMITIVE}]]"
    if {!$bb} { set ok 0 }
    close_design
    puts [expr {$ok ? "SCRATCH OK" : "SCRATCH FAIL"}]
}
