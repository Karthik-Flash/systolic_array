# hw_t1_mock.tcl -- run hw_t1.tcl end to end against the mock device (no hardware).
# From inside vivado/ (Vivado ships Tcl 8.5, the same interpreter the board run uses):
#   C:/Xilinx/Vivado/2022.2/bin/vivado.bat -mode batch -nojournal -nolog -source ../scripts/t1/hw_t1_mock.tcl
# Positive run: every demo + t1_selftest must PASS.
# Negative run: a partial that resets uptime must make t1_swap_demo and t1_selftest FAIL.
# Mock CSVs go to sim/t1_build/mock/ (gitignored); real runs write docs/t1/reports/.

set ::T1_MOCK 1
source [file join [file dirname [info script]] hw_t1.tcl]

set results {}
proc expect {name got want} {
    lappend ::results [format "%-34s %s" $name [expr {$got == $want ? "ok" : "WRONG (got $got, want $want)"}]]
}

puts "\n######## POSITIVE: good partials ########"
t1_mock_reset
t1_connect
t1_program full add
t1_wait 5000
foreach rm {mul grey add} {
    puts "\n---- t1_swap_demo $rm ----"
    expect "swap_demo $rm" [t1_swap_demo $rm] 1
}
t1_wait 5000
puts "\n---- t1_full_contrast ----"
expect "full_contrast" [t1_full_contrast] 1
puts "\n---- t1_selftest ----"
expect "selftest" [t1_selftest] 1

puts "\n######## NEGATIVE: partial resets uptime (static NOT kept) ########"
set ::T1_MOCK_BAD_PARTIAL 1
t1_mock_reset
t1_program full add
t1_wait 5000
puts "\n---- t1_swap_demo mul (must FAIL) ----"
expect "neg swap_demo mul" [t1_swap_demo mul] 0
puts "\n---- t1_selftest (must FAIL) ----"
expect "neg selftest" [t1_selftest] 0
set ::T1_MOCK_BAD_PARTIAL 0

puts "\nreal-run CSV dir: $::t1_reports"
expect "real-run CSV dir exists" [file isdirectory $::t1_reports] 1
expect "bitstream dir exists" [file isdirectory $::t1_bits] 1

puts "\n######## MOCK SUMMARY ########"
foreach r $results { puts $r }
puts [expr {[llength [lsearch -all $results *WRONG*]] ? "MOCK TESTS FAIL" : "MOCK TESTS PASS"}]
