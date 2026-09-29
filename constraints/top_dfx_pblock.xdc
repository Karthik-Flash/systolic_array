# top_dfx_pblock.xdc -- pblock_U_RP (T1_PLAN §7.8). Implementation-only.
# Created by Tcl from the device database, then saved here by Vivado (Ctrl+S) as the Target Constraint File.
# The dbg_hub lines below are also written by Vivado on save; keep them.

create_pblock pblock_U_RP
add_cells_to_pblock [get_pblocks pblock_U_RP] [get_cells -quiet [list U_RP]]
resize_pblock [get_pblocks pblock_U_RP] -add {SLICE_X80Y50:SLICE_X103Y99}
resize_pblock [get_pblocks pblock_U_RP] -add {DSP48_X3Y20:DSP48_X4Y39}
resize_pblock [get_pblocks pblock_U_RP] -add {RAMB18_X4Y20:RAMB18_X4Y39}
resize_pblock [get_pblocks pblock_U_RP] -add {RAMB36_X4Y10:RAMB36_X4Y19}
set_property RESET_AFTER_RECONFIG true [get_pblocks pblock_U_RP]
set_property SNAPPING_MODE ON [get_pblocks pblock_U_RP]
set_property C_CLK_INPUT_FREQ_HZ 300000000 [get_debug_cores dbg_hub]
set_property C_ENABLE_CLK_DIVIDER false [get_debug_cores dbg_hub]
set_property C_USER_SCAN_CHAIN 1 [get_debug_cores dbg_hub]
connect_debug_port dbg_hub/clk [get_nets clk_IBUF_BUFG]
