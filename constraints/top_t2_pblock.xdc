# top_t2_pblock.xdc -- pblock_U_RP, verbatim from T1's top_dfx_pblock.xdc (T2_PLAN D8, sec. 6.7).
# Implementation-only (used_in_synthesis false) and the project's target constraints file.
# If a GUI save later appends dbg_hub lines here, keep them (same as T1).

create_pblock pblock_U_RP
add_cells_to_pblock [get_pblocks pblock_U_RP] [get_cells -quiet [list U_RP]]
resize_pblock [get_pblocks pblock_U_RP] -add {SLICE_X80Y50:SLICE_X103Y99}
resize_pblock [get_pblocks pblock_U_RP] -add {DSP48_X3Y20:DSP48_X4Y39}
resize_pblock [get_pblocks pblock_U_RP] -add {RAMB18_X4Y20:RAMB18_X4Y39}
resize_pblock [get_pblocks pblock_U_RP] -add {RAMB36_X4Y10:RAMB36_X4Y19}
set_property RESET_AFTER_RECONFIG true [get_pblocks pblock_U_RP]
set_property SNAPPING_MODE ON [get_pblocks pblock_U_RP]
