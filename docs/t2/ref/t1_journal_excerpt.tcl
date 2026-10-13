# t1_journal_excerpt.tcl -- lines harvested from every surviving Vivado journal (T2_PLAN sec. 5.3, A1 task 1a).
# Reference only: NOT meant to be sourced. Filter regex:
#   create_ip|CONFIG\.C_|set_property -dict|PR_FLOW|create_partition_def|create_reconfig_module|-of_objects|create_pr_configuration|create_run|PR_CONFIGURATION|launch_runs|used_in_synthesis|target_constrs_file|create_pblock|resize_pblock
# Journals searched: %APPDATA%/Xilinx/Vivado/*.jou, repo root *.jou, vivado/**/*.jou
# A line ending in a backslash is kept together with its continuation lines (the set_property -dict block).
# The T1 project was created in vivado_19340.backup.jou (session of 2026-09-29); the others are T0 / board sessions.

# ---- source: C:/Users/karth/AppData/Roaming/Xilinx/Vivado/vivado.jou  (0 lines)
# (no matching lines)

# ---- source: C:/Users/karth/AppData/Roaming/Xilinx/Vivado/vivado_19340.backup.jou  (84 lines)
set_property used_in_synthesis false [get_files  D:/Projects/RC_Project/constraints/top_dfx_pblock.xdc]
set_property target_constrs_file D:/Projects/RC_Project/constraints/top_dfx_pblock.xdc [current_fileset -constrset]
create_ip -name vio -vendor xilinx.com -library ip -version 3.0 -module_name vio_dfx
set_property -dict [list \
  CONFIG.C_EN_PROBE_IN_ACTIVITY {0} \
  CONFIG.C_NUM_PROBE_IN {3} \
  CONFIG.C_NUM_PROBE_OUT {4} \
  CONFIG.C_PROBE_IN0_WIDTH {32} \
  CONFIG.C_PROBE_IN1_WIDTH {8} \
  CONFIG.C_PROBE_IN2_WIDTH {32} \
  CONFIG.C_PROBE_OUT2_WIDTH {16} \
  CONFIG.C_PROBE_OUT3_WIDTH {16} \
  CONFIG.Component_Name {vio_dfx} \
] [get_ips vio_dfx]
export_ip_user_files -of_objects [get_files d:/Projects/RC_Project/vivado/t1_dfx/t1_dfx.srcs/sources_1/ip/vio_dfx/vio_dfx.xci] -no_script -sync -force -quiet
create_ip_run [get_files -of_objects [get_fileset sources_1] d:/Projects/RC_Project/vivado/t1_dfx/t1_dfx.srcs/sources_1/ip/vio_dfx/vio_dfx.xci]
launch_runs vio_dfx_synth_1 -jobs 13
export_simulation -of_objects [get_files d:/Projects/RC_Project/vivado/t1_dfx/t1_dfx.srcs/sources_1/ip/vio_dfx/vio_dfx.xci] -directory D:/Projects/RC_Project/vivado/t1_dfx/t1_dfx.ip_user_files/sim_scripts -ip_user_files_dir D:/Projects/RC_Project/vivado/t1_dfx/t1_dfx.ip_user_files -ipstatic_source_dir D:/Projects/RC_Project/vivado/t1_dfx/t1_dfx.ip_user_files/ipstatic -lib_map_path [list {modelsim=D:/Projects/RC_Project/vivado/t1_dfx/t1_dfx.cache/compile_simlib/modelsim} {questa=D:/Projects/RC_Project/vivado/t1_dfx/t1_dfx.cache/compile_simlib/questa} {riviera=D:/Projects/RC_Project/vivado/t1_dfx/t1_dfx.cache/compile_simlib/riviera} {activehdl=D:/Projects/RC_Project/vivado/t1_dfx/t1_dfx.cache/compile_simlib/activehdl}] -use_ip_compiled_libs -force -quiet
set_property PR_FLOW 1 [current_project] 
create_partition_def -name pd_t1 -module rp_t1
create_reconfig_module -name rm_add -partition_def [get_partition_defs pd_t1 ]  -define_from rp_t1
create_reconfig_module -name rm_mul -partition_def [get_partition_defs pd_t1 ]  -top rp_t1
add_files -norecurse D:/Projects/RC_Project/rtl/t1/rm/rm_mul.v  -of_objects [get_reconfig_modules rm_mul]
create_pr_configuration -name cfg_add -partitions [list U_RP:rm_add ]
create_pr_configuration -name cfg_mul -partitions [list U_RP:rm_mul ]
create_pr_configuration -name cfg_grey -partitions { }  -greyboxes [list U_RP ]
set_property PR_CONFIGURATION cfg_add [get_runs impl_1]
create_run child_0_impl_1 -parent_run impl_1 -flow {Vivado Implementation 2022} -pr_config cfg_mul
create_run child_1_impl_1 -parent_run impl_1 -flow {Vivado Implementation 2022} -pr_config cfg_grey
launch_runs synth_1 -jobs 13
launch_runs impl_1 -to_step write_bitstream -jobs 13
set_property OUTPUT_VALUE 2 [get_hw_probes vio_sel -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
commit_hw_vio [get_hw_probes {vio_sel} -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
set_property OUTPUT_VALUE 1 [get_hw_probes vio_sel -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
commit_hw_vio [get_hw_probes {vio_sel} -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
set_property OUTPUT_VALUE 0 [get_hw_probes vio_sel -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
commit_hw_vio [get_hw_probes {vio_sel} -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
set_property OUTPUT_VALUE 1 [get_hw_probes vio_sel -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
commit_hw_vio [get_hw_probes {vio_sel} -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
set_property OUTPUT_VALUE 2 [get_hw_probes vio_sel -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
commit_hw_vio [get_hw_probes {vio_sel} -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
set_property OUTPUT_VALUE 0 [get_hw_probes vio_start -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
commit_hw_vio [get_hw_probes {vio_start} -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
set_property OUTPUT_VALUE 1 [get_hw_probes vio_start -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
commit_hw_vio [get_hw_probes {vio_start} -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
set_property OUTPUT_VALUE 3 [get_hw_probes vio_sel -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
commit_hw_vio [get_hw_probes {vio_sel} -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
set_property OUTPUT_VALUE 1 [get_hw_probes vio_sel -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
commit_hw_vio [get_hw_probes {vio_sel} -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
set_property OUTPUT_VALUE 2 [get_hw_probes vio_sel -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
commit_hw_vio [get_hw_probes {vio_sel} -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
create_pblock pblock_U_RP
resize_pblock [get_pblocks pblock_U_RP] -add {SLICE_X80Y50:SLICE_X103Y99}
resize_pblock [get_pblocks pblock_U_RP] -add {DSP48_X3Y20:DSP48_X4Y39}
resize_pblock [get_pblocks pblock_U_RP] -add {RAMB18_X4Y20:RAMB18_X4Y39}
resize_pblock [get_pblocks pblock_U_RP] -add {RAMB36_X4Y10:RAMB36_X4Y19}
puts "cells in pblock      : [get_cells -of_objects [get_pblocks pblock_U_RP]]"
launch_runs impl_1 child_0_impl_1 child_1_impl_1 -to_step write_bitstream -jobs 4
set_property OUTPUT_VALUE 0003 [get_hw_probes vio_a -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
commit_hw_vio [get_hw_probes {vio_a} -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
set_property OUTPUT_VALUE 0004 [get_hw_probes vio_b -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
commit_hw_vio [get_hw_probes {vio_b} -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
set_property OUTPUT_VALUE 0004 [get_hw_probes vio_b -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
commit_hw_vio [get_hw_probes {vio_b} -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
set_property OUTPUT_VALUE 0004 [get_hw_probes vio_b -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
commit_hw_vio [get_hw_probes {vio_b} -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
set_property OUTPUT_VALUE 1 [get_hw_probes vio_decouple -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
commit_hw_vio [get_hw_probes {vio_decouple} -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
set_property OUTPUT_VALUE 0 [get_hw_probes vio_decouple -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
commit_hw_vio [get_hw_probes {vio_decouple} -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
set_property OUTPUT_VALUE 1 [get_hw_probes vio_rm_rst -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
commit_hw_vio [get_hw_probes {vio_rm_rst} -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
set_property OUTPUT_VALUE 0 [get_hw_probes vio_rm_rst -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
commit_hw_vio [get_hw_probes {vio_rm_rst} -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
set_property OUTPUT_VALUE 1 [get_hw_probes vio_decouple -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
commit_hw_vio [get_hw_probes {vio_decouple} -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
set_property OUTPUT_VALUE 0 [get_hw_probes vio_decouple -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
commit_hw_vio [get_hw_probes {vio_decouple} -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
set_property OUTPUT_VALUE 1 [get_hw_probes vio_decouple -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
commit_hw_vio [get_hw_probes {vio_decouple} -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
set_property OUTPUT_VALUE 1 [get_hw_probes vio_rm_rst -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
commit_hw_vio [get_hw_probes {vio_rm_rst} -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
set_property OUTPUT_VALUE 0 [get_hw_probes vio_decouple -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
commit_hw_vio [get_hw_probes {vio_decouple} -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]

# ---- source: C:/Users/karth/AppData/Roaming/Xilinx/Vivado/vivado_27208.backup.jou  (0 lines)
# (no matching lines)

# ---- source: C:/Users/karth/AppData/Roaming/Xilinx/Vivado/vivado_33980.backup.jou  (3 lines)
launch_runs synth_1 -jobs 13
launch_runs impl_1 -jobs 13
launch_runs impl_1 child_0_impl_1 child_1_impl_1 -to_step write_bitstream -jobs 13

# ---- source: C:/Users/karth/AppData/Roaming/Xilinx/Vivado/vivado_37384.backup.jou  (0 lines)
# (no matching lines)

# ---- source: C:/Users/karth/AppData/Roaming/Xilinx/Vivado/vivado_8820.backup.jou  (58 lines)
create_ip -name vio -vendor xilinx.com -library ip -version 3.0 -module_name vio_0
set_property -dict [list \
  CONFIG.C_NUM_PROBE_IN {2} \
  CONFIG.C_NUM_PROBE_OUT {2} \
  CONFIG.C_PROBE_IN1_WIDTH {32} \
  CONFIG.C_PROBE_OUT1_WIDTH {4} \
] [get_ips vio_0]
export_ip_user_files -of_objects [get_files d:/Projects/RC_Project/vivado/systolic_t0/systolic_t0.srcs/sources_1/ip/vio_0/vio_0.xci] -no_script -sync -force -quiet
create_ip_run [get_files -of_objects [get_fileset sources_1] d:/Projects/RC_Project/vivado/systolic_t0/systolic_t0.srcs/sources_1/ip/vio_0/vio_0.xci]
launch_runs vio_0_synth_1 -jobs 13
export_simulation -of_objects [get_files d:/Projects/RC_Project/vivado/systolic_t0/systolic_t0.srcs/sources_1/ip/vio_0/vio_0.xci] -directory D:/Projects/RC_Project/vivado/systolic_t0/systolic_t0.ip_user_files/sim_scripts -ip_user_files_dir D:/Projects/RC_Project/vivado/systolic_t0/systolic_t0.ip_user_files -ipstatic_source_dir D:/Projects/RC_Project/vivado/systolic_t0/systolic_t0.ip_user_files/ipstatic -lib_map_path [list {modelsim=D:/Projects/RC_Project/vivado/systolic_t0/systolic_t0.cache/compile_simlib/modelsim} {questa=D:/Projects/RC_Project/vivado/systolic_t0/systolic_t0.cache/compile_simlib/questa} {riviera=D:/Projects/RC_Project/vivado/systolic_t0/systolic_t0.cache/compile_simlib/riviera} {activehdl=D:/Projects/RC_Project/vivado/systolic_t0/systolic_t0.cache/compile_simlib/activehdl}] -use_ip_compiled_libs -force -quiet
launch_runs impl_1 -jobs 13
launch_runs impl_1 -to_step write_bitstream -jobs 13
launch_runs impl_1 -to_step write_bitstream -jobs 13
set_property OUTPUT_VALUE 1 [get_hw_probes vio_start -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
commit_hw_vio [get_hw_probes {vio_start} -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
set_property OUTPUT_VALUE 0 [get_hw_probes vio_sel -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
commit_hw_vio [get_hw_probes {vio_sel} -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
set_property OUTPUT_VALUE 0 [get_hw_probes vio_start -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
commit_hw_vio [get_hw_probes {vio_start} -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
set_property OUTPUT_VALUE 1 [get_hw_probes vio_start -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
commit_hw_vio [get_hw_probes {vio_start} -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
launch_runs impl_1 -to_step write_bitstream -jobs 13
launch_runs impl_1 -to_step write_bitstream -jobs 13
set_property OUTPUT_VALUE 0 [get_hw_probes vio_start -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
commit_hw_vio [get_hw_probes {vio_start} -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
set_property OUTPUT_VALUE 1 [get_hw_probes vio_start -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
commit_hw_vio [get_hw_probes {vio_start} -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
set_property OUTPUT_VALUE 0 [get_hw_probes vio_sel -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
commit_hw_vio [get_hw_probes {vio_sel} -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
set_property OUTPUT_VALUE 0 [get_hw_probes vio_start -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
commit_hw_vio [get_hw_probes {vio_start} -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
set_property OUTPUT_VALUE 1 [get_hw_probes vio_start -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
commit_hw_vio [get_hw_probes {vio_start} -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
set_property OUTPUT_VALUE 0 [get_hw_probes vio_start -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
commit_hw_vio [get_hw_probes {vio_start} -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
set_property OUTPUT_VALUE 1 [get_hw_probes vio_start -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
commit_hw_vio [get_hw_probes {vio_start} -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
set_property OUTPUT_VALUE 0 [get_hw_probes vio_start -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
commit_hw_vio [get_hw_probes {vio_start} -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
set_property OUTPUT_VALUE 1 [get_hw_probes vio_start -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
commit_hw_vio [get_hw_probes {vio_start} -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
set_property OUTPUT_VALUE 0 [get_hw_probes vio_start -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
commit_hw_vio [get_hw_probes {vio_start} -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
set_property OUTPUT_VALUE 1 [get_hw_probes vio_start -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
commit_hw_vio [get_hw_probes {vio_start} -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
set_property OUTPUT_VALUE 0 [get_hw_probes vio_start -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
commit_hw_vio [get_hw_probes {vio_start} -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
set_property OUTPUT_VALUE 1 [get_hw_probes vio_start -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
commit_hw_vio [get_hw_probes {vio_start} -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
set_property OUTPUT_VALUE 0 [get_hw_probes vio_start -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
commit_hw_vio [get_hw_probes {vio_start} -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
set_property OUTPUT_VALUE 1 [get_hw_probes vio_start -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
commit_hw_vio [get_hw_probes {vio_start} -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
set_property OUTPUT_VALUE 1 [get_hw_probes vio_sel -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
commit_hw_vio [get_hw_probes {vio_sel} -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
set_property OUTPUT_VALUE 2 [get_hw_probes vio_sel -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]
commit_hw_vio [get_hw_probes {vio_sel} -of_objects [get_hw_vios -of_objects [get_hw_devices xc7z020_1] -filter {CELL_NAME=~"U_VIO"}]]

# ---- source: D:/Projects/RC_Project/vivado/systolic_t0/systolic_t0.runs/impl_1/vivado.jou  (0 lines)
# (no matching lines)

# ---- source: D:/Projects/RC_Project/vivado/systolic_t0/systolic_t0.runs/synth_1/vivado.jou  (0 lines)
# (no matching lines)

# ---- source: D:/Projects/RC_Project/vivado/systolic_t0/systolic_t0.runs/vio_0_synth_1/vivado.jou  (0 lines)
# (no matching lines)

# ---- source: D:/Projects/RC_Project/vivado/t1_dfx/t1_dfx.runs/child_0_impl_1/vivado.jou  (0 lines)
# (no matching lines)

# ---- source: D:/Projects/RC_Project/vivado/t1_dfx/t1_dfx.runs/child_1_impl_1/vivado.jou  (0 lines)
# (no matching lines)

# ---- source: D:/Projects/RC_Project/vivado/t1_dfx/t1_dfx.runs/impl_1/vivado.jou  (0 lines)
# (no matching lines)

# ---- source: D:/Projects/RC_Project/vivado/t1_dfx/t1_dfx.runs/rm_add_synth_1/vivado.jou  (0 lines)
# (no matching lines)

# ---- source: D:/Projects/RC_Project/vivado/t1_dfx/t1_dfx.runs/rm_mul_synth_1/vivado.jou  (0 lines)
# (no matching lines)

# ---- source: D:/Projects/RC_Project/vivado/t1_dfx/t1_dfx.runs/synth_1/vivado.jou  (0 lines)
# (no matching lines)

# ---- source: D:/Projects/RC_Project/vivado/t1_dfx/t1_dfx.runs/vio_dfx_synth_1/vivado.jou  (0 lines)
# (no matching lines)
