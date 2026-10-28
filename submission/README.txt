SOURCE PACKAGE - Dynamic Precision-Scalable Systolic Array using DFX
Board: ZedBoard, Zynq-7000 xc7z020clg484-1. Tool: Vivado 2022.2 (project mode, Dynamic Function eXchange).
T2_final/ is the final project: a 4x4 matrix multiplier whose precision (int16, int8, int4) is swapped at run time
by loading a partial bitstream into one fenced region while the rest of the chip keeps running. It holds all
Verilog, constraints, the VIO IP, the bitstreams, the test vectors, the scripts and the Python reference model.
How to run: in Vivado Hardware Manager, program T2_final/bitstreams/t2_full_int16.bit with probes file
T2_final/bitstreams/t2_full_int16.ltx first; then load any T2_final/bitstreams/t2_partial_*.bit (same probes file).
A partial bitstream cannot load onto a blank chip: always load a full bitstream first.
No .coe files are used: the design has no memory initialisation; matrices are loaded at run time through the VIO.
earlier_tiers/ holds T0 and T1, the earlier steps kept as supporting evidence.

------------------------------------------------------------------------------------------------------------------
T2_final - every file
------------------------------------------------------------------------------------------------------------------
File                                What it is                                                  Origin (repository path)
rtl/top_t2.v                        Static top: controller, feed registers, start gate,         rtl/t2/top_t2.v
                                    done flag, decoupler, uptime, LEDs, VIO, region U_RP
rtl/controller.v                    Control state machine and staircase feed generator          reused unchanged from T0 (rtl/controller.v)
rtl/array.v                         4x4 systolic array of pe cells (int16 module only)          reused unchanged from T0 (rtl/array.v)
rtl/pe.v                            Processing element on one DSP slice (int16 module only)     reused unchanged from T0 (rtl/pe.v)
rtl/rst_sync.v                      Two-flop reset synchroniser for the push button             reused unchanged from T1 (rtl/t1/rst_sync.v)
rtl/uptime.v                        Seconds counter and 1 Hz heartbeat of the static region     reused unchanged from T1 (rtl/t1/uptime.v)
rtl/dfx_decouple.v                  Forces the region's 45 output wires to safe values          reused unchanged from T1 (rtl/t1/dfx_decouple.v)
                                    during a swap
rtl/rm/rm_int16.v                   int16 module: T0 array on 16 DSP slices, 48-bit             rtl/t2/rm/rm_int16.v
                                    accumulators, result clamped to 32 bits, ID 16
rtl/rm/rm_int8.v                    int8 module: inputs clamped to 8 bits, LUT array,           rtl/t2/rm/rm_int8.v
                                    18-bit accumulators, 0 DSP, ID 08
rtl/rm/rm_int4.v                    int4 module: inputs clamped to 4 bits, LUT array,           rtl/t2/rm/rm_int4.v
                                    10-bit accumulators, 0 DSP, ID 04
rtl/rm/rm_common.v                  Shared parts of the modules: input clamp, result select     rtl/t2/rm/rm_common.v
                                    and conversion, ID and LED badge
rtl/rm/array_lut.v                  4x4 array of pe_lut cells (int8 and int4)                   rtl/t2/rm/array_lut.v
rtl/rm/pe_lut.v                     Processing element built from LUTs (int8 and int4)          rtl/t2/rm/pe_lut.v
tb/tb_rp_t2.v                       Bench for one module on its own, 9 test cases               tb/t2/tb_rp_t2.v
tb/tb_top_t2.v                      Bench for the static top plus one module: 9 cases,          tb/t2/tb_top_t2.v
                                    cycle count, start gate
tb/vio_t2_stub.v                    Simulation-only stand-in for the VIO core                   tb/t2/vio_t2_stub.v
constraints/top_t2.xdc              Pins, I/O standards and the 100 MHz clock                   constraints/top_t2.xdc
constraints/top_t2_pblock.xdc       The fenced region pblock_U_RP (right part of clock          constraints/top_t2_pblock.xdc
                                    region X1Y1; implementation only)
ip/vio_t2.xci                       VIO debug core configuration: 5 inputs, 6 outputs           vivado/t2_dfx/t2_dfx.srcs/sources_1/ip/vio_t2/
                                    including two 256-bit matrix probes                         vio_t2.xci (not in git; generated project)
bitstreams/t2_full_int16.bit        Full bitstream, static region + int16 module; load first    bitstreams/t2/
bitstreams/t2_full_int8.bit         Full bitstream with the int8 module                         bitstreams/t2/
bitstreams/t2_full_int4.bit         Full bitstream with the int4 module                         bitstreams/t2/
bitstreams/t2_full_grey.bit         Full bitstream with the empty (greybox) region              bitstreams/t2/
bitstreams/t2_partial_int16.bit     Partial bitstream: swap the region to int16 (585,559 B)     bitstreams/t2/
bitstreams/t2_partial_int8.bit      Partial bitstream: swap to int8                             bitstreams/t2/
bitstreams/t2_partial_int4.bit      Partial bitstream: swap to int4                             bitstreams/t2/
bitstreams/t2_partial_grey.bit      Partial bitstream: empty the region                         bitstreams/t2/
bitstreams/t2_full_int16.ltx        VIO probes file for every T2 full and partial bitstream     bitstreams/t2/
bitstreams/manifest.csv             Size, SHA-256 and source run of each file above             bitstreams/t2/
sim_vectors/t2_vectors/<prec>/<case>/{a_probe,b_probe,feed_west,feed_north,c_out,ovf}.hex
                                    The 162 golden vector files the two benches read            sim/t2_vectors/
                                    (3 precisions x 9 cases x 6 files)
python/golden_t2.py                 Golden reference model for int16 / int8 / int4              python/golden_t2.py
python/gen_vectors_t2.py            Writes the T2 test vectors from the golden model            python/gen_vectors_t2.py
python/test_golden_t2.py            Self-checks of the T2 golden model                          python/test_golden_t2.py
python/golden.py                    T0 golden model, imported by golden_t2.py                   reused unchanged from T0 (python/golden.py)
python/quant.py                     Clamp and hex helpers, imported by golden_t2.py             reused unchanged from T0 (python/quant.py)
scripts/t2_filesets.tcl             The single list of T2 source files                          scripts/t2/
scripts/create_project_t2.tcl       Creates the Vivado DFX project (partition, modules,         scripts/t2/
                                    configurations, runs)
scripts/run_sims.py                 Runs all benches in XSim, including 3 negative builds       scripts/t2/
scripts/ooc_check.tcl               Out-of-context synthesis check of each module               scripts/t2/
scripts/reports_t2.tcl              Writes timing, utilisation, DRC and pr_verify reports       scripts/t2/
scripts/power_delay_t2.tcl          Writes the power estimate, worst-path delay and Fmax table  scripts/t2/
scripts/collect_bitstreams.py       Copies bitstreams from the run folders, writes manifest     scripts/t2/
scripts/verify_bundle.py            Checks the bitstreams against the manifest                  scripts/t2/
scripts/hw_t2.tcl                   Board script for Vivado Hardware Manager (t2_* commands)    scripts/t2/
scripts/hw_t2_mock.tcl              Software mock of the board for rehearsing hw_t2.tcl         scripts/t2/

Notes
- The scripts expect the repository layout (rtl/t2, sim/t2_vectors, bitstreams/t2, ...) and were not edited.
  To use them, run them from a clone of the repository (github.com/Karthik-Flash/systolic_array).
- The benches read vectors from ../../t2_vectors/ relative to the simulator's working folder. Run XSim from a
  folder two levels below sim_vectors/, for example sim_vectors/build/<name>/. Checked: xvlog, xelab and xsim
  of tb_top_t2 for int16, int8 and int4 all PASS using only a copy of T2_final outside the repository.
- rm_int16.v, rm_int8.v and rm_int4.v all declare the same Verilog module, rp_t2: compile one of them at a time.
- The greybox (empty region) has no source file; Vivado creates it.

------------------------------------------------------------------------------------------------------------------
earlier_tiers
------------------------------------------------------------------------------------------------------------------
T0_int16_array/     Proved a 4x4 int16 systolic array is correct at 100 MHz on silicon (C[0][2] = 110 read back).
                    rtl (8), tb (5), constraints (2), ip (vio_0.xci), bitstreams (t0_top_vio.bit + .ltx),
                    sim_vectors (54 .hex), python (T0 golden model, vector generator, UART host).
                    The T0 bitstream is a rebuild (2026-09-29) of the VIO system from sources unchanged since
                    the t0-onboard tag; it is not proven byte-identical to the file loaded on 24 Sep.
                    No bitstream of the T0 serial (UART) system exists; that system was verified in simulation only.
                    The T0 benches name their vector folder with an absolute path (D:/Projects/RC_Project/sim/vectors/).
T1_dfx_mechanism/   Proved DFX works on this board: a region swapped between adder, multiplier and empty in
                    about 1.4 s, 15 of 15 swaps, without disturbing the static region.
                    rtl (6), tb (3), constraints (2), ip (vio_dfx.xci), bitstreams (6 .bit, .ltx, manifest.csv),
                    scripts (6). Load t1_full_add.bit with t1_full_add.ltx before any t1_partial_*.bit.
