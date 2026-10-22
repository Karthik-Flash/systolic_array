# T1 project facts (read-only harvest from vivado/t1_dfx)

Source: `vivado/t1_dfx/t1_dfx.xpr` and `vivado/t1_dfx/t1_dfx.srcs/sources_1/ip/vio_dfx/vio_dfx.xci`,
extracted by script during T2 Phase A1 task 1b. A journal survives too: the T1 project was created in
`%APPDATA%/Xilinx/Vivado/vivado_19340.backup.jou` (see `t1_journal_excerpt.tcl`); this file cross-checks it.

## vio_dfx (.xci)

- component_reference `xilinx.com:ip:vio:3.0`, ip_revision `23`

### component_parameters set by the user (resolve_type = user), active probes only

| key | value |
|---|---|
| `C_EN_PROBE_IN_ACTIVITY` | `0` |
| `C_EN_SYNCHRONIZATION` | `1` |
| `C_NUM_PROBE_IN` | `3` |
| `C_NUM_PROBE_OUT` | `4` |
| `C_PROBE_IN0_WIDTH` | `32` |
| `C_PROBE_IN1_WIDTH` | `8` |
| `C_PROBE_IN2_WIDTH` | `32` |
| `C_PROBE_OUT0_WIDTH` | `1` |
| `C_PROBE_OUT1_WIDTH` | `1` |
| `C_PROBE_OUT2_WIDTH` | `16` |
| `C_PROBE_OUT3_WIDTH` | `16` |
| `Component_Name` | `vio_dfx` |

### All C_* component_parameters of the active probes (incl. defaults)

| key | value | resolve_type |
|---|---|---|
| `C_EN_PROBE_IN_ACTIVITY` | `0` | user |
| `C_EN_SYNCHRONIZATION` | `1` | user |
| `C_NUM_PROBE_IN` | `3` | user |
| `C_NUM_PROBE_OUT` | `4` | user |
| `C_PROBE_IN0_WIDTH` | `32` | user |
| `C_PROBE_IN1_WIDTH` | `8` | user |
| `C_PROBE_IN2_WIDTH` | `32` | user |
| `C_PROBE_OUT0_INIT_VAL` | `0x0` | user |
| `C_PROBE_OUT0_WIDTH` | `1` | user |
| `C_PROBE_OUT1_INIT_VAL` | `0x0` | user |
| `C_PROBE_OUT1_WIDTH` | `1` | user |
| `C_PROBE_OUT2_INIT_VAL` | `0x0` | user |
| `C_PROBE_OUT2_WIDTH` | `16` | user |
| `C_PROBE_OUT3_INIT_VAL` | `0x0` | user |
| `C_PROBE_OUT3_WIDTH` | `16` | user |

## t1_dfx.xpr

### Project options

- `Part` = `xc7z020clg484-1`
- `BoardPart` = `digilentinc.com:zedboard:part0:1.0`
- `DefaultLib` = `xil_defaultlib`
- `PRFlow` = `TRUE`

### FileSets (files are relative to $PPRDIR = vivado/t1_dfx)

- **sources_1** (Type `DesignSrcs`)
  - `$PPRDIR/../../rtl/t1/dfx_decouple.v` UsedIn=synthesis,implementation,simulation
  - `$PPRDIR/../../rtl/t1/rst_sync.v` UsedIn=synthesis,implementation,simulation
  - `$PPRDIR/../../rtl/t1/uptime.v` UsedIn=synthesis,implementation,simulation
  - `$PPRDIR/../../rtl/t1/top_dfx.v` UsedIn=synthesis,implementation,simulation
  - Config `DesignMode` = `RTL`
  - Config `TopModule` = `top_dfx`
  - Config `TopAutoSet` = `TRUE`
- **constrs_1** (Type `Constrs`)
  - `$PPRDIR/../../constraints/top_dfx.xdc` UsedIn=synthesis,implementation
  - `$PPRDIR/../../constraints/top_dfx_pblock.xdc` UsedIn=implementation
  - Config `TargetConstrsFile` = `$PPRDIR/../../constraints/top_dfx_pblock.xdc`
  - Config `ConstrsType` = `XDC`
- **vio_dfx** (Type `BlockSrcs`)
  - `$PSRCDIR/sources_1/ip/vio_dfx/vio_dfx.xci` UsedIn=synthesis,implementation,simulation
  - Config `TopModule` = `vio_dfx`
  - Config `UseBlackboxStub` = `1`
- **rm_add** (Type `BlockSrcs`)
  - `$PPRDIR/../../rtl/t1/rm/rm_add.v` UsedIn=synthesis,implementation,simulation
  - Config `TopModule` = `rp_t1`
  - Config `TopRTLFile` = `$PPRDIR/../../rtl/t1/rm/rm_add.v`
  - Config `UseBlackboxStub` = `1`
- **rm_mul** (Type `BlockSrcs`)
  - `$PPRDIR/../../rtl/t1/rm/rm_mul.v` UsedIn=synthesis,implementation,simulation
  - Config `TopModule` = `rp_t1`
  - Config `UseBlackboxStub` = `1`

### Partition definitions and reconfigurable modules

- PartitionDef `pd_t1` ModuleName=`rp_t1` DefaultRM=`rm_add` Library=`xil_defaultlib`
  - RM `rm_add` Top=`rp_t1` SrcSet=`rm_add` SynthRun=`rm_add_synth_1` ImplRun=`rm_add_impl_1`
  - RM `rm_mul` Top=`rp_t1` SrcSet=`rm_mul` SynthRun=`rm_mul_synth_1` ImplRun=`rm_mul_impl_1`

### PR configurations

- `cfg_add` Active=true map=['U_RP:rm_add'] greybox=[]
- `cfg_grey` Active=false map=[] greybox=['U_RP']
- `cfg_mul` Active=false map=['U_RP:rm_mul'] greybox=[]

### Runs

| Id | Type | SrcSet | SynthRun (parent for children) | PRConfiguration | Strategy | Flow |
|---|---|---|---|---|---|---|
| `synth_1` | Ft3:Synth | sources_1 |  |  | Vivado Synthesis Defaults | `Vivado Synthesis 2022` |
| `vio_dfx_synth_1` | Ft3:Synth | vio_dfx |  |  | Vivado Synthesis Defaults | `Vivado Synthesis 2022` |
| `rm_add_synth_1` | Ft3:Synth | rm_add |  |  | Vivado Synthesis Defaults | `Vivado Synthesis 2022` |
| `rm_mul_synth_1` | Ft3:Synth | rm_mul |  |  | Vivado Synthesis Defaults | `Vivado Synthesis 2022` |
| `impl_1` | Ft2:EntireDesign |  | synth_1 | cfg_add | Vivado Implementation Defaults | `Vivado Implementation 2022` |
| `vio_dfx_impl_1` | Ft2:EntireDesign |  | vio_dfx_synth_1 |  | Vivado Implementation Defaults | `Vivado Implementation 2022` |
| `rm_add_impl_1` | Ft2:EntireDesign |  | rm_add_synth_1 |  | Vivado Implementation Defaults | `Vivado Implementation 2022` |
| `rm_mul_impl_1` | Ft2:EntireDesign |  | rm_mul_synth_1 |  | Vivado Implementation Defaults | `Vivado Implementation 2022` |
| `child_0_impl_1` | Ft2:EntireDesign |  | impl_1 | cfg_mul | Vivado Implementation Defaults | `Vivado Implementation 2022` |
| `child_1_impl_1` | Ft2:EntireDesign |  | impl_1 | cfg_grey | Vivado Implementation Defaults | `Vivado Implementation 2022` |

## What T2 takes from this

- RM from existing sources: `create_reconfig_module -name rm_add -partition_def [get_partition_defs pd_t1] -define_from rp_t1`.
- Other RMs: `create_reconfig_module -name rm_mul -partition_def [get_partition_defs pd_t1] -top rp_t1`, then
  `add_files -norecurse <file> -of_objects [get_reconfig_modules rm_mul]`.
- Configurations: `create_pr_configuration -name cfg_add -partitions [list U_RP:rm_add]`;
  greybox: `create_pr_configuration -name cfg_grey -partitions { } -greyboxes [list U_RP]`.
- Parent: `set_property PR_CONFIGURATION cfg_add [get_runs impl_1]`; children:
  `create_run child_0_impl_1 -parent_run impl_1 -flow {Vivado Implementation 2022} -pr_config cfg_mul`.
- VIO: `create_ip -name vio -vendor xilinx.com -library ip -version 3.0 -module_name vio_dfx`, then
  `set_property -dict [list CONFIG.C_EN_PROBE_IN_ACTIVITY {0} CONFIG.C_NUM_PROBE_IN {3} ...] [get_ips vio_dfx]`.
- Pblock XDC: `set_property used_in_synthesis false [get_files ...]` and
  `set_property target_constrs_file ... [current_fileset -constrset]`.
- The T1 project also set `board_part digilentinc.com:zedboard:part0:1.0`.
