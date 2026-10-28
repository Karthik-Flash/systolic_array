# t2_filesets.tcl -- THE single list of T2 sources (T2_PLAN sec. 8.4, G21).
# Read by scripts/t2/run_sims.py (parsed as text), ooc_check.tcl and create_project_t2.tcl (sourced).
# Paths are relative to the repo root; ::T2_ROOT is the absolute repo root when sourced.
# Format rule (the Python parser relies on it): one `set ::NAME {...}` or
# `set ::NAME(key) {...}` per value, no nested braces inside a value.

set ::T2_ROOT [file normalize [file join [file dirname [info script]] ../..]]
set ::T2_PART xc7z020clg484-1
set ::T2_TOP  top_t2

# static region (sources_1); the VIO IP vio_t2 is added by create_project_t2.tcl
set ::T2_STATIC_FILES {rtl/t2/top_t2.v rtl/t1/rst_sync.v rtl/t1/uptime.v rtl/t1/dfx_decouple.v rtl/controller.v}

# reconfigurable modules: every RM declares module rp_t2
set ::T2_RMS {rm_int16 rm_int8 rm_int4}
set ::T2_RM_FILES(rm_int16) {rtl/t2/rm/rm_int16.v rtl/array.v rtl/pe.v rtl/t2/rm/rm_common.v}
set ::T2_RM_FILES(rm_int8)  {rtl/t2/rm/rm_int8.v rtl/t2/rm/array_lut.v rtl/t2/rm/pe_lut.v rtl/t2/rm/rm_common.v}
set ::T2_RM_FILES(rm_int4)  {rtl/t2/rm/rm_int4.v rtl/t2/rm/array_lut.v rtl/t2/rm/pe_lut.v rtl/t2/rm/rm_common.v}

# constraints: pins + clock (synth + impl), Pblock (impl only, target file)
set ::T2_XDC_PINS   constraints/top_t2.xdc
set ::T2_XDC_PBLOCK constraints/top_t2_pblock.xdc

# VIO vio_t2 probe widths, index order probe_in0..4 / probe_out0..5 (T2_PLAN sec. 4)
set ::T2_VIO_IN_WIDTHS  {32 8 32 4 16}
set ::T2_VIO_OUT_WIDTHS {1 1 1 4 256 256}

# configurations (cfg -> RM for U_RP; "greybox" = blank RP) and implementation run -> cfg
set ::T2_CFG_RM  {cfg_int16 rm_int16 cfg_int8 rm_int8 cfg_int4 rm_int4 cfg_grey greybox}
set ::T2_RUN_CFG {impl_1 cfg_int16 child_0_impl_1 cfg_int8 child_1_impl_1 cfg_int4 child_2_impl_1 cfg_grey}
