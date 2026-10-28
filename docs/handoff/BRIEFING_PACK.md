# Briefing Pack: every fact the report and deck need

This pack is for a chat that cannot see the repository. It collects the facts, tables and evidence of the whole project in one file. Every number below is copied from a report, CSV, log or source file in the repository; the "Source" lines name them, so a reader with the repository can check each one. Read `HANDOFF.md` first for the task order and the course rules.

**Project:** Dynamic Precision-Scalable Systolic Array using DFX
**Course:** Reconfigurable Computing (CS G553), BITS Pilani Hyderabad
**Board:** ZedBoard, Zynq-7000 `xc7z020clg484-1` · **Tools:** Vivado 2022.2, Python 3 with NumPy, XSim, Icarus Verilog 0.9.7 (compile checks only)
**Repository:** github.com/Karthik-Flash/systolic_array, branch `main`
**Status:** T0, T1 and T2 complete on silicon. T3 (accuracy on real data, measured power) not started.

---

## Contents

1. The project in one page
2. T0: the int16 array
3. T1: the swap mechanism
4. T2: design
5. T2: build data
6. T2: the board session
7. Report-ready results table
8. The demo script and LED legend (for the final lab)
9. Figure inventory
10. Document inventory
11. Glossary

---

## 1. The project in one page

Neural networks spend most of their time multiplying matrices. The project builds a 4×4 matrix multiplier (a **systolic array**: a grid of 16 small multiply-accumulate units) on an FPGA, and makes its **number precision** changeable at run time: 16-bit, 8-bit or 4-bit integers.

The change uses **Dynamic Function eXchange (DFX)**: one fenced region of the chip is rewritten with a small **partial bitstream** while the rest of the chip keeps running. Each precision is a separate module that fits the same region behind the same frozen set of boundary wires.

| Tier | What it proved | Where it ran | Key evidence |
|---|---|---|---|
| T0 | A 4×4 int16 systolic array is correct at 100 MHz | simulation, then silicon (tag `t0-onboard`, 2026-09-24) | C[0][2] = 110 read back over JTAG |
| T1 | DFX works on this board: swap a region in about 1.4 s without disturbing the rest | silicon (2026-10-08) | 15 of 15 swaps, static uptime never reset |
| T2 | The region holds the real array in int16, int8 and int4 and swaps between them | silicon (2026-10-22) | self-test 14/14 steps, demo 144/144 values |
| T3 | Accuracy on real data, power on the board | not started | — |

**Method used in every tier:** a written plan with decisions and predictions → RTL (Verilog) → simulation against a Python golden model → Vivado build → scripted bitstream collection with checksums → board scripts rehearsed on a software mock → board session → compare with predictions. The student ran every Vivado GUI step and every board step; AI coding assistants helped plan, write and review code, scripts and documents.

**Git tags (milestones):** `t0-datapath`, `t0-system` (2026-09-13), `t0-onboard` (2026-09-24), `t1-rtl` (2026-09-28), `t1-built` (2026-09-29), `t1-onboard` (2026-10-08), `t2-rtl` (2026-10-14), `t2-built`, `t2-lab-ready` (2026-10-16), `t2-onboard` (2026-10-22).

*Sources: README.md, docs/PROJECT_DETAIL.md, git tags*

---

## 2. T0: the int16 array

### 2.1 What was built

| Module | Job |
|---|---|
| `pe.v` | One processing element (PE): multiply two int16 inputs, add to a 48-bit running total, pass the inputs on. Maps to one DSP slice. |
| `array.v` | The 4×4 grid of 16 PEs, wired west-to-east and north-to-south |
| `controller.v` | Generates the staircase feed schedule and the clear signal |
| `loader.v` | Reads one result at a time and clamps it from 48 to 32 bits |
| `uart_rx.v`, `uart_tx.v`, `top.v` | Serial-port system: laptop sends A and B, gets C back (verified in simulation only) |
| `top_vio.v` | Board version: a VIO debug core sets start and reads results over the JTAG cable |

The ZedBoard's USB-serial connector is wired to the ARM processor side, not to the FPGA fabric, so the serial system was verified in simulation and the board used the VIO version.

### 2.2 Results

| What | Result |
|---|---|
| Architecture | 4×4 output-stationary systolic array |
| Arithmetic | int16 inputs, 48-bit accumulators, 32-bit saturated outputs |
| Multipliers | 16 DSP48E1, one per PE |
| Logic (serial system) | 1,335 LUTs, 665 flip-flops, 0 block RAM |
| Timing at 100 MHz | met: WNS +0.378 ns (serial system), +1.427 ns (VIO system, WHS +0.060 ns) |
| Critical path (serial system) | controller cycle counter → a DSP's A input: 5.959 ns data path, 6 logic levels, DSP setup 3.722 ns |
| Compute latency | 10 streaming cycles + 1 clear = 110 ns per 4×4 product |
| Peak throughput | 16 MACs × 100 MHz = 1.6 GMAC/s (3.2 GOPS) |
| Power (serial system) | 0.117 W total on-chip, 0.011 W dynamic, junction 26.4 °C: Vivado estimate, not measured |
| On silicon | `sel = 2` → `0x0000006E` = 110 = C[0][2] = 1×9 + 2×10 + 3×11 + 4×12 |
| Memory wall | 110 ns of compute vs about 11 ms to send 64 bytes in and 64 out at 115,200 baud: roughly 100,000× slower |

**Verification:** golden-model self-checks 14/14; benches `tb_pe`, `tb_array`, `tb_ctrl_array`, `tb_uart_loop`, `tb_system` all pass. Test cases: identity, ones, counting (symmetric), random (asymmetric), extremes (all −32,768, forces saturation), zeros.

### 2.3 Lessons

| Symptom | Cause | Lesson |
|---|---|---|
| PE wrong on negative results | an unsigned zero constant made a conditional expression unsigned | one unsigned operand silently changes a whole Verilog expression |
| A deliberate transpose bug passed `counting` | counting's result is symmetric | symmetric tests cannot see transposes; add an asymmetric case |
| Vivado `add_files` failed | spaces in the project path | never put spaces in EDA paths |
| Bitstream refused (DRC NSTD-1) | a port had no I/O standard | every port needs an I/O standard matching its bank voltage |
| Serial port unreachable on the board | the connector belongs to the processor side | know which side of a Zynq each connector is on |
| Design stayed in reset until the button was held | active-high button, active-low reset | check polarity at every board boundary |

*Sources: docs/t0/T0_Complete_Guide.md, docs/t0/img/T0_screen.png*

---

## 3. T1: the swap mechanism

### 3.1 Mechanism

- One reconfigurable partition `U_RP` with a frozen port list of 78 partition pins: inputs `clk`, `rst_n`, `a` 16 bits, `b` 16 bits; outputs `y` 32 bits, `rm_id` 8 bits, `led_pat` 4 bits.
- Three modules: `rm_add` (y = a + b, ID A1), `rm_mul` (y = a × b on one DSP, ID B2), and an empty greybox (ID 00).
- Static region: reset synchroniser, uptime counter in seconds (shows whether the static region was ever disturbed), decoupler (forces outputs to safe values during a swap; ID reads FF), VIO debug core.
- Vivado project mode with DFX: one parent run builds and locks the static region; child runs reuse it and implement only their module. `pr_verify` checks that all builds share an identical static region.

### 3.2 Where the fence sits (Pblock reasoning)

The Zynq-7020's programmable logic is divided into six clock regions. A column of configuration sites (BSCAN, ICAP; device grid position RPM_X 205, slices X68 to X79) runs through region X1Y1 and splits it. Both DSP columns of X1Y1 (`DSP48_X3`, `DSP48_X4`) lie to the right of it, so a fence in the left part could never hold a multiplier. The fence `pblock_U_RP` uses the right part:

| Item | Value |
|---|---|
| Ranges | `SLICE_X80Y50:SLICE_X103Y99`, `DSP48_X3Y20:DSP48_X4Y39`, `RAMB18_X4Y20:RAMB18_X4Y39`, `RAMB36_X4Y10:RAMB36_X4Y19` |
| Capacity | 4,400 LUT, 1,800 LUTRAM, 8,800 FF, 40 DSP, 10 block RAM |
| Properties | `RESET_AFTER_RECONFIG true`, `SNAPPING_MODE ON` |
| DRC after synthesis | 0 errors, 1 expected warning (ZPS7-1: processor block unused) |

It was sized for T2 from the start (40 DSPs = 2.5× the 16 PEs) and reused unchanged in T2.

### 3.3 Results

| Config | WNS (ns) | WHS (ns) | Total LUT | Total FF | Region LUT | Region FF | Region DSP |
|---|---:|---:|---:|---:|---:|---:|---:|
| cfg_add | +4.304 | +0.039 | 676 | 1,465 | 40 | 53 | 0 |
| cfg_mul | +3.501 | +0.039 | 644 | 1,448 | 8 | 36 | 1 |
| cfg_grey | +4.304 | +0.039 | 713 | 1,413 | 77 | 1 | 0 |

| What | Result |
|---|---|
| Static region cost | 636 LUT, 1,412 FF, 0 DSP (about 97% of the LUTs are Xilinx debug cores) |
| Greybox | 77 one-input LUTs: 44 output tie-offs + 33 input loads |
| Bitstreams | partial 585,560 B (14.5% of the full 4,045,667 B), the same for every module |
| Partial swap over JTAG | 1,424 ± 27 ms (N = 15); per module add 1,422, mul 1,425, grey 1,424 ms |
| Full program | 9,060 ± 73 ms (N = 3) |
| Time vs size | two-point fit: 2.21 µs per byte + 0.13 s fixed; about 3.6 Mbit/s from the slope (about 3.3 Mbit/s from a partial's size ÷ time); JTAG clock not recorded |
| Static region during swaps | uptime +2 s across each of 15 swaps; reset to 0 only by full programs |
| `pr_verify` | pass |
| Board self-test | 18/18 rows PASS (3 full + 15 partial) |

### 3.4 Lessons

- A DSP attribute on a whole module also pushed a counter into a second DSP: apply attributes to the exact signal.
- Vivado's Tcl is version 8.5 (no `lmap`): test scripts in Vivado's own interpreter.
- A zero-padded hex string through Tcl `expr` reads as octal: avoid `expr` on hex strings.
- A partial bitstream cannot load onto a blank chip (`[Xicom 50-103]`): load the matching full bitstream first.
- The Hardware Manager's cached probe values go stale after programming (`[Labtools 27-1952]`, harmless); scripts rewrite values before reading.
- A weak negative test caught only 1 of 15 bad cases; this led to a stronger continuity check.
- T1's console log was lost to copy-paste truncation; T2 logged to a file from the start.

*Sources: docs/t1/T1_RESULTS.md, docs/t1/T1_Complete_Guide.md, bitstreams/t1/manifest.csv*

---

## 4. T2: design

### 4.1 Decisions D1 to D11

| # | Decision (one line) |
|---|---|
| D1 | The swappable region holds the input clamps, the 4×4 array and the result select: 180 boundary wires instead of about 900 |
| D2 | Every variant keeps 16-bit input lanes; each module saturates its own inputs at the array edge |
| D3 | int16 reuses T0's PE on 16 DSP slices; int8 and int4 use LUT multipliers (0 DSP); accumulators 48 / 18 / 10 bits |
| D4 | T0 controller reused unchanged, plus a registered feed stage and a start gate that refuses runs while decoupled, in reset or busy |
| D5 | A and B loaded through two 256-bit VIO probes; results read one at a time through a 4-bit selector |
| D6 | Registers on both sides of the boundary: every crossing path is register → wire → register; +2 cycles for every module |
| D7 | Cycle count identical for every precision by construction; measured in simulation |
| D8 | Reuse the T1 Pblock unchanged; out-of-context gate: at most 2,200 LUTs, DSP 16 / 0 / 0, no block RAM |
| D9 | Four configurations: int16 (parent), int8, int4, empty greybox |
| D10 | Vivado project created by a script, validated in a scratch copy; builds launched from the GUI |
| D11 | Module IDs 16 / 08 / 04, 00 empty, FF decoupled; LED badge: lit LEDs = bits ÷ 4 |

Correction recorded in the plan: the early estimate of 17 / 9 accumulator bits was wrong. The clamp allows −128 and −8, and 4 × (−128)² = 65,536 needs 18 signed bits; 4 × (−8)² = 256 needs 10.

### 4.2 Locked names

| Item | Name |
|---|---|
| Top module | `top_t2` (ports `clk` on Y9, `btn_rst` on P16, `led[7:0]`) |
| Static instances | `U_RST` rst_sync, `U_UP` uptime, `U_CT` controller, `U_DC` dfx_decouple, `U_VIO` vio_t2 |
| Swappable instance / module | `U_RP` / `rp_t2` |
| Partition definition | `pd_t2` |
| Modules | `rm_int16`, `rm_int8`, `rm_int4`, plus greybox |
| Configurations | `cfg_int16`, `cfg_int8`, `cfg_int4`, `cfg_grey` |
| Implementation runs | `impl_1` → cfg_int16 (parent), `child_0_impl_1` → cfg_int8, `child_1_impl_1` → cfg_int4, `child_2_impl_1` → cfg_grey |
| Synthesis runs | `synth_1` (static), `rm_int16_synth_1`, `rm_int8_synth_1`, `rm_int4_synth_1`, `vio_t2_synth_1` |
| Pblock | `pblock_U_RP` (the T1 ranges above) |
| Constraint files | `top_t2.xdc` (pins and clock), `top_t2_pblock.xdc` (Pblock) |
| Collected bitstreams | `t2_full_{int16,int8,int4,grey}.bit`, `t2_partial_{int16,int8,int4,grey}.bit`, `t2_full_int16.ltx`, `manifest.csv` |
| Board scripts | `hw_t2.tcl` (procedures `t2_*`), `hw_t2_mock.tcl` |

### 4.3 The frozen boundary (180 partition pins)

| Signal | Width | Direction | Meaning |
|---|---:|---|---|
| `clk` | 1 | in | 100 MHz clock |
| `rst_n` | 1 | in | module reset, held low while decoupled |
| `clr_acc` | 1 | in | clear accumulators at the start of a run |
| `west_bus` | 64 | in | four int16 A lanes from the static feed register |
| `north_bus` | 64 | in | four int16 B lanes |
| `sel` | 4 | in | result index 4i + j |
| `result` | 32 | out | C[sel] as int32 |
| `ovf` | 1 | out | the result was clamped (int16 only) |
| `rm_id` | 8 | out | module ID |
| `led_pat` | 4 | out | LED badge |

134 inputs + 45 outputs + clock = 180. The decoupler is 45 bits wide; safe values: result 0, ovf 0, ID FF, LEDs 0000.

### 4.4 The three modules

| | int16 | int8 | int4 | greybox |
|---|---|---|---|---|
| Input stage | pass-through | clamp to [−128, 127] | clamp to [−8, 7] | none |
| PE | T0 PE on a DSP slice | LUT multiplier | LUT multiplier | none |
| Accumulator | 48 bits | 18 bits | 10 bits | none |
| Output | clamp 48 → 32 bits, sets `ovf` | sign-extend | sign-extend | constants via one-input LUTs |
| DSP slices | 16 | 0 | 0 | 0 |
| ID / badge LD3..0 | 16 / 1111 | 08 / 0011 | 04 / 0001 | 00 / 0000 |

### 4.5 Timing of one run

Controller 12 cycles + 2 boundary registers + 1 done flag = **15 cycles = 150 ns** at 100 MHz, the same for all 27 (module, case) pairs in simulation.

### 4.6 Swap protocol

1. Write `vio_decouple = 1`: outputs forced safe, module held in reset, done flag cleared, starts refused.
2. Load the partial bitstream over JTAG; the static region keeps running.
3. Write `vio_decouple` 1 then 0: the new module leaves reset and reports its ID.
4. Load A and B, start, read results.

### 4.7 LED map

| LED | Meaning |
|---|---|
| LD7 | static heartbeat, 1 Hz |
| LD6 | module held in reset |
| LD5 | region decoupled |
| LD4 | done flag |
| LD3..LD0 | precision badge, blinking (toggles every 2²⁴ cycles ≈ 168 ms): int16 1111, int8 0011, int4 0001, empty or decoupled 0000 |

### 4.8 VIO probes (11)

| Probe | Net | Width | Direction | Meaning |
|---|---|---:|---|---|
| out0 | `vio_decouple` | 1 | laptop → chip | isolate the region and hold the module in reset |
| out1 | `vio_rm_rst` | 1 | laptop → chip | hold the module in reset without decoupling |
| out2 | `vio_start` | 1 | laptop → chip | run (rising edge, gated) |
| out3 | `vio_sel` | 4 | laptop → chip | result index 4i + j |
| out4 | `vio_a` | 256 | laptop → chip | matrix A, 16 × int16 |
| out5 | `vio_b` | 256 | laptop → chip | matrix B, same packing |
| in0 | `vio_result` | 32 | chip → laptop | C[sel] after the decoupler |
| in1 | `vio_rm_id` | 8 | chip → laptop | module ID after the decoupler |
| in2 | `vio_uptime` | 32 | chip → laptop | static seconds counter |
| in3 | `vio_flags` | 4 | chip → laptop | [0] done, [1] overflow, [2] busy, [3] blocked |
| in4 | `vio_runs` | 16 | chip → laptop | accepted runs since reset |

### 4.9 Gotchas new in T2 (G16 to G29)

| # | One line |
|---|---|
| G16 | int8 / int4 accumulators are 18 / 10 bits, not 17 / 9 |
| G17 | Small vectors give the same answer in every precision; tests need `random_full` and `extremes_*` |
| G18 | 256-bit probe order: first hex digit = top 4 bits of A[3][3]; last four digits = A[0][0] |
| G19 | `08` / `04` through Tcl `expr` is an invalid octal number; build hex with `format`; sign-convert 32-bit results explicitly |
| G20 | Constant outputs (int8/int4 `ovf`, sign bits) must come from `dont_touch` flops so every boundary wire is flop-driven |
| G21 | One authoritative module file list, in `t2_filesets.tcl` |
| G22 | RTL, constraints and filesets frozen between tags `t2-rtl` and `t2-built` |
| G23 | While the GUI builds, batch jobs run only in the scratch folder |
| G24 | The board script refuses any bitstream not in the T2 manifest |
| G25 | Decouple clears the done flag; always re-run before reading after a swap |
| G26 | XSim elaborates only the named bench; old Icarus cannot read 2-D net arrays |
| G27 | Probe names in the `.ltx` are the RTL net names; keep `vio_*` names exact |
| G28 | Vivado batch jobs fail from Git Bash (`couldn't read file`); use PowerShell or cmd |
| G29 | Opening the static synthesis checkpoint alone gives a VIO black-box warning; expected |

### 4.10 As-built deviations from the plan

| # | Deviation |
|---|---|
| 1 | All benches ran in Vivado XSim; Icarus 0.9.7 kept as a compile check only (it rejects T0's 2-D arrays) |
| 2 | The reused controller has an extra `running` output, wired to an unused net |
| 3 | Existing quantisation helpers reused (they equal the full-range clamp); hex width rounded up for 10- and 18-bit values |
| 4 | Lowercase hex in every vector file |
| 5 | Board script accepts both the locked VIO net names and known aliases |
| 6 | Constant outputs driven by internal `dont_touch` registers |
| 7 | The LUT array uses flat buses instead of 2-D arrays (passes the Icarus check) |
| 8 | Vivado batch jobs launched from PowerShell |
| 9 | Project script moves the shared module file after Vivado's `-define_from` |
| 10 | Project path accepted only as an absolute path |
| 11 | A cache folder under `scripts/t1/` kept (T1 files are read-only) |
| 12 | DFX command forms copied from T1's Vivado journal |

### 4.11 Predictions vs measured

| # | Prediction | Measured | Held? |
|---|---|---|---|
| P1 | Every partial 585,560 B | 585,559 B | within 1 byte: header names `top_t2`, one character shorter than T1's `top_dfx` |
| P2 | Every full 4,045,667 B | 4,045,666 B | within 1 byte, same reason |
| P3 | Swap about 1.42 s | 429.3 ms mean | not held: JTAG clock 15 MHz this session; T1's not recorded |
| P4 | DSP 16 / 0 / 0 / 0 | 16 / 0 / 0 / 0 | held |
| P5 | int8 LUTs > int4 LUTs | 1,451 > 693 | held |
| P6 | Same latency for every module | 12 / 15 cycles in all 27 pairs | held (simulation) |
| P7 | Static LUT/FF above T1's 636 / 1,412 | 1,300 / 2,659 | held |
| P8 | WNS ≥ 0; worst path in the controller or an int8 MAC | +1.481 to +2.981 ns; int8 worst path is a MAC | held |
| P9 | Board results bit-exact | int16 9/9, int8 9/9, int4 5 case types; demo 144/144 | held, with the int4 gap |

*Sources: docs/t2/T2_PLAN.md (sections 2, 3, 4, 12, 13, 16), rtl/t2/top_t2.v, rtl/t2/rm/*.v*

---

## 5. T2: build data

### 5.1 Build summary (post-route, 100 MHz)

| Config | Run | WNS (ns) | WHS (ns) | Total LUT | Total FF | DSP | Region LUT | Region FF | Region DSP | Pblock LUT % | Pblock DSP % | Partition pins | DRC errors | Logic levels (worst path) |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| cfg_int16 | impl_1 | 2.135 | 0.088 | 1,553 | 2,825 | 16 | 253 | 166 | 16 | 5.75 | 40.00 | 180 | 0 | 6 |
| cfg_int8 | child_0_impl_1 | 1.481 | 0.088 | 2,751 | 3,259 | 0 | 1,451 | 600 | 0 | 32.98 | 0.00 | 180 | 0 | 11 |
| cfg_int4 | child_1_impl_1 | 2.981 | 0.088 | 1,993 | 2,995 | 0 | 693 | 336 | 0 | 15.75 | 0.00 | 180 | 0 | 0 |
| cfg_grey | child_2_impl_1 | 2.981 | 0.088 | 1,479 | 2,660 | 0 | 179 | 1 | 0 | 4.07 | 0.00 | 180 | 0 | 0 |

No block RAM in any build. Static region (total minus region): 1,300 LUT and 2,659 FF in every build. The greybox's 179 LUTs are all one-input LUTs (LUT1), one per non-clock boundary wire.

### 5.2 Power and delay

| Config | LUT total | FF total | DSP | LUT region | WNS (ns) | Worst-path delay (ns) | Logic levels | Est. Fmax (MHz) | Total (W) | Dynamic (W) | Static (W) | Junction (°C) | Confidence |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| cfg_int16 | 1,553 | 2,825 | 16 | 253 | 2.135 | 7.732 | 6 | 127.1 | 0.135 | 0.032 | 0.103 | 26.6 | Medium |
| cfg_int8 | 2,751 | 3,259 | 0 | 1,451 | 1.481 | 8.538 | 11 | 117.4 | 0.127 | 0.021 | 0.106 | 26.5 | Medium |
| cfg_int4 | 1,993 | 2,995 | 0 | 693 | 2.981 | 6.532 | 0 | 142.5 | 0.124 | 0.017 | 0.106 | 26.4 | Medium |
| cfg_grey | 1,479 | 2,660 | 0 | 179 | 2.981 | 6.532 | 0 | 142.5 | 0.116 | 0.013 | 0.103 | 26.3 | Medium |

- Power: Vivado vectorless estimate on the routed design (default switching activity), confidence Medium; not measured on the board.
- Delay: data-path delay of the worst setup path. Fmax estimate = 1000 / (10 − WNS) MHz; it uses slack, which also counts clock skew and setup time, so it is not 1000 ÷ delay. Only 100 MHz was tested.
- int16 dynamic power by type (Vivado screenshot of `impl_1`): clocks 0.010 W, signals 0.007 W, logic 0.004 W, DSP 0.011 W, I/O < 0.001 W.

**Worst setup paths (from the timing reports):**

| Config | From → to | Logic levels | Where |
|---|---|---:|---|
| int16 | VIO `vio_sel` probe register → `U_RP` readout overflow register (`g_sat32.ovf_q`) | 6 | crosses into the region |
| int8 | `U_RP/north_r` input register → accumulator of PE row 0, column 2 | 11 | inside the region: int8 multiply-accumulate |
| int4, grey | VIO core `clear_int_reg` → VIO `probe_out_modified_reg` | 0 | static region, inside the VIO core |

### 5.3 Out-of-context synthesis (each module alone, before the project existed)

| Module | LUT | FF | DSP | BRAM | Est. WNS (ns) | Gates |
|---|---:|---:|---:|---:|---:|---|
| rm_int16 | 254 | 166 | 16 | 0 | 5.246 | DSP, LUT, BRAM, WNS all pass |
| rm_int8 | 1,442 | 600 | 0 | 0 | 2.631 | all pass |
| rm_int4 | 597 | 336 | 0 | 0 | 4.139 | all pass |

### 5.4 Simulation

| Build | Result |
|---|---|
| `tb_rp_t2` × int16 / int8 / int4 (9 cases each) | PASS ×3, 0 warnings |
| `tb_top_t2` × int16 / int8 / int4 (9 cases, cycle count, start gate) | PASS ×3, 0 warnings |
| N1: int16 module in the int8 bench | failed as expected (wrong ID, wrong results) |
| N2: int8 module in the int4 bench | failed as expected |
| N3: start gate removed | failed as expected (runs accepted while decoupled and in reset) |
| Port lists of the three modules | identical |
| Cycle counts, 27 (module, case) pairs | controller 12, start-to-done 15 in every pair |

Test cases (9): zeros, ones, identity, counting, asym_small, random_inrange, random_full, extremes_neg, extremes_mix.

Golden-model anchors: counting C[0][2] = 110 / 110 / 70 (int16 / int8 / int4); extremes_neg = 2,147,483,647 with overflow (exact 4,294,967,296) / 65,536 / 256; extremes_mix = −2,147,483,648 with overflow (exact −4,294,836,224) / −65,024 / −224.

### 5.5 Bitstreams (manifest)

| File | Bytes | SHA-256 (first 12) | Config | Source run |
|---|---:|---|---|---|
| t2_full_int16.bit | 4,045,666 | 9010177bda05 | cfg_int16 | impl_1 |
| t2_partial_int16.bit | 585,559 | 2e9028d808da | cfg_int16 | impl_1 |
| t2_full_int8.bit | 4,045,666 | b58781663a58 | cfg_int8 | child_0_impl_1 |
| t2_partial_int8.bit | 585,559 | 18817400607b | cfg_int8 | child_0_impl_1 |
| t2_full_int4.bit | 4,045,666 | 61eb40a33f1c | cfg_int4 | child_1_impl_1 |
| t2_partial_int4.bit | 585,559 | ed0868240fe5 | cfg_int4 | child_1_impl_1 |
| t2_full_grey.bit | 4,045,666 | e0ec22123bbb | cfg_grey | child_2_impl_1 |
| t2_partial_grey.bit | 585,559 | e9d7d049b0bd | cfg_grey | child_2_impl_1 |
| t2_full_int16.ltx | 110,316 | 0729f0ee9d8f | cfg_int16 | impl_1 |

Partial = 14.5% of full. The bundle check prints `BUNDLE OK` (re-run on 2026-10-28).

**Note for the record:** the Vivado run folders were re-generated on 2026-10-22 in the evening, after the board session. Their bitstreams differ from the collected ones only in the header's date and time fields; the configuration data is byte-identical. The committed, board-tested files match the manifest.

### 5.6 `pr_verify`

Three comparisons (`impl_1` against each child run), all **compatible**. Each compared 1 module, 180 partition pins, 1,734 static tiles, 708 static sites, 4,377 static cells, 43,282 static routed nodes and 39,717 static routed pips.

*Sources: docs/t2/reports/build_summary.csv, power_delay_summary.csv, cfg_*_timing_summary.rpt, cfg_*_power.rpt, cfg_grey_utilization_U_RP.rpt, ooc_summary.csv, sim_summary.txt, sim_cycles.csv, pr_verify.rpt; bitstreams/t2/manifest.csv; python/test_golden_t2.py output*

---

## 6. T2: the board session (2026-10-22)

**Setup:** ZedBoard, Vivado Hardware Manager, Digilent cable, JTAG clock **15,000,000 Hz**, script `hw_t2.tcl`, session logged to a file (855 lines).

### 6.1 Sequence and observations

| # | Command | Observed |
|---|---|---|
| 1 | `source …/hw_t2.tcl` | `hw_t2.tcl loaded (mock=0)` |
| 2 | `t2_connect` | `JTAG clock 15000000 Hz` |
| 3 | `t2_program full int16` | 2,537 ms; startup status HIGH; 1 VIO core |
| 4 | `t2_probes` | all 11 probes resolved |
| 5 | `t2_status` | `rm_id 16`, uptime 126 s, runs 0 |
| 6 | `t2_check ones` | PASS, C[0][2] = 4 |
| 7 | `t2_check_all` (int16) | 9/9; counting `0000006E`; extremes_neg `7FFFFFFF` |
| 8 | `t2_swap_demo int8` | ID ff during, 08 after; 431 ms; uptime 330 → 331 s |
| 9 | `t2_check_all` (int8) | 9/9; counting `0000006E`; extremes_neg `00010000`; extremes_mix `FFFF0200` |
| 10–11 | int4 swap and 9-case sweep | not run |
| 12 | `t2_block_test` | refused while decoupled (runs 21 → 21) and while in reset (21 → 21); accepted after release |
| 13 | `t2_demo` | PASS; 144 rows, 0 mismatches; swaps int8 417 ms, int4 416 ms |
| 14 | `t2_swap_demo grey` | ID 00; 418 ms; uptime 689 → 690 s |
| 15 | `t2_swap_demo int16` | ID 16; 423 ms; uptime 770 → 771 s |
| 16 | `t2_full_contrast` | 2,492 ms; uptime 1,006 → 0 s (reset, as expected) |
| 17 | `t2_selftest 3` | PASS; 14/14 steps; 58/58 case checks |

**Totals:** 23 programs (19 partial, 4 full), 0 failures. Only warnings: `[Labtools 27-1952]` after full programs (stale VIO cache; harmless).

### 6.2 Self-test (all 14 rows)

| Step | Operation | File | Bytes | ms | Uptime before → after | Check | ID | Cases | Verdict |
|---:|---|---|---:|---:|---|---|---|---:|---|
| 1 | full | t2_full_int16.bit | 4,045,666 | 2,504 | – → 2 | n/a | 16 | 5/5 | PASS |
| 2 | full | t2_full_int16.bit | 4,045,666 | 2,497 | 3 → 0 | reset = yes | 16 | 5/5 | PASS |
| 3 | partial int8 | t2_partial_int8.bit | 585,559 | 421 | 2 → 3 | continuity = yes | 08 | 5/5 | PASS |
| 4 | partial int4 | t2_partial_int4.bit | 585,559 | 436 | 5 → 6 | continuity = yes | 04 | 5/5 | PASS |
| 5 | partial grey | t2_partial_grey.bit | 585,559 | 415 | 7 → 8 | continuity = yes | 00 | 1/1 | PASS |
| 6 | partial int16 | t2_partial_int16.bit | 585,559 | 419 | 9 → 10 | continuity = yes | 16 | 5/5 | PASS |
| 7 | partial int8 | t2_partial_int8.bit | 585,559 | 418 | 12 → 12 | continuity = yes | 08 | 5/5 | PASS |
| 8 | partial int4 | t2_partial_int4.bit | 585,559 | 436 | 14 → 15 | continuity = yes | 04 | 5/5 | PASS |
| 9 | partial grey | t2_partial_grey.bit | 585,559 | 416 | 17 → 18 | continuity = yes | 00 | 1/1 | PASS |
| 10 | partial int16 | t2_partial_int16.bit | 585,559 | 414 | 18 → 19 | continuity = yes | 16 | 5/5 | PASS |
| 11 | partial int8 | t2_partial_int8.bit | 585,559 | 518 | 21 → 22 | continuity = yes | 08 | 5/5 | PASS |
| 12 | partial int4 | t2_partial_int4.bit | 585,559 | 427 | 24 → 25 | continuity = yes | 04 | 5/5 | PASS |
| 13 | partial grey | t2_partial_grey.bit | 585,559 | 421 | 27 → 28 | continuity = yes | 00 | 1/1 | PASS |
| 14 | partial int16 | t2_partial_int16.bit | 585,559 | 411 | 28 → 29 | continuity = yes | 16 | 5/5 | PASS |

Cases per module step: counting, asym_small, random_full, extremes_neg, extremes_mix. Greybox steps run `counting` against the empty module's expected output.

| Swap statistics | N | Mean (ms) | SD (ms) | Min – max (ms) |
|---|---:|---:|---:|---|
| All partials | 12 | 429.3 | 29.1 | 411 – 518 |
| int8 | 3 | 452.3 | – | 418 – 518 (one 518 ms outlier) |
| int4 | 3 | 433.0 | – | 427 – 436 |
| grey | 3 | 417.3 | – | 415 – 421 |
| int16 | 3 | 414.7 | – | 411 – 419 |
| Full programs | 2 | 2,500.5 | – | 2,497 – 2,504 |

Effective rate: 10.9 Mbit/s (partial), 12.9 Mbit/s (full), against a 15 Mbit/s JTAG clock. Two-point fit: 0.599 µs per byte + 0.079 s. One swap (0.43 s) equals about 2.9 million 4×4 products of 150 ns.

### 6.3 Demo summary (per case and precision)

| Case | Precision | Elements matched | C[0][2] | Overflow flags | Swap (ms) |
|---|---|---:|---:|---:|---:|
| counting | int16 | 16/16 | 110 | 0 | – |
| counting | int8 | 16/16 | 110 | 0 | 417 |
| counting | int4 | 16/16 | 70 | 0 | 416 |
| random_full | int16 | 16/16 | −184,541,856 | 0 | – |
| random_full | int8 | 16/16 | 256 | 0 | 417 |
| random_full | int4 | 16/16 | 16 | 0 | 416 |
| extremes_neg | int16 | 16/16 | 2,147,483,647 | 16 | – |
| extremes_neg | int8 | 16/16 | 65,536 | 0 | 417 |
| extremes_neg | int4 | 16/16 | 256 | 0 | 416 |

Total 144 rows, 0 mismatches. Elements equal to int16: counting int8 16/16, int4 1/16; random_full 0/16 for both; extremes_neg 0/16 for both. The demo ran int16 → int8 → int4 → int16.

### 6.4 The software mock

`hw_t2_mock.tcl` replaces the Hardware Manager with a model of the board. It runs 22 positive checks and 5 deliberate faults that must be caught: NM1 a partial that resets uptime, NM2 reversed probe lanes, NM3 int8 without its input clamp, NM4 a start accepted while decoupled, NM5 a partial on a blank chip. Re-run on 2026-10-28: `MOCK TESTS PASS` and `NEGATIVE MOCKS OK (5/5)`. Before the lab it caught two real script bugs (a hex string through `expr` became `00007E45` → a floating-point number; a bracket error in a format string).

### 6.5 Limits of the board evidence

- int4 never got the 9-case sweep on the board; not run on int4: identity, ones, zeros, random_inrange (all pass in simulation).
- LED behaviour is not in the log.
- Continuity: with programs under 1 s, the check reduces to "uptime did not go backwards"; the evidence is the monotonic 2 → 29 s sequence.
- One board, one JTAG clock, 12 timed swaps.

*Sources: docs/t2/reports/hw_session_20261022.log, hw_selftest_20261022_134926.csv, hw_demo_20261022_134038.csv; docs/t2/T2_BOARD_RUNBOOK.md (section F); scripts/t2/hw_t2_mock.tcl*

---

## 7. Report-ready results table

| Configuration | LUTs, whole design | LUTs, swappable region | DSPs | Worst-path delay (ns) | Estimated Fmax (MHz) | Total power (W) | Dynamic power (W) |
|---|---:|---:|---:|---:|---:|---:|---:|
| int16 | 1,553 | 253 | 16 | 7.732 | 127.1 | 0.135 | 0.032 |
| int8 | 2,751 | 1,451 | 0 | 8.538 | 117.4 | 0.127 | 0.021 |
| int4 | 1,993 | 693 | 0 | 6.532 | 142.5 | 0.124 | 0.017 |
| Empty (greybox) | 1,479 | 179 | 0 | 6.532 | 142.5 | 0.116 | 0.013 |

Notes to print under the table:
- Power is a Vivado vectorless estimate on the routed design, confidence Medium; not measured on the board.
- Estimated Fmax = 1000 / (10 − WNS); all designs were closed and tested at 100 MHz.
- Dynamic power rises with precision: int16 > int8 > int4 > empty.
- int4 and empty share the same worst path, inside the VIO debug core in the static region.
- Swap time 429.3 ms (N = 12) for every module; partial bitstream 585,559 B.

---

## 8. The demo script and LED legend (for the final lab)

This is what the student will run on 2026-10-29. Use it as the "expected" column when tabulating the uploaded results.

| # | Command | Expected |
|---|---|---|
| 1 | `source D:/Projects/RC_Project/scripts/t2/hw_t2.tcl` | `hw_t2.tcl loaded (mock=0)` |
| 2 | `t2_connect` | `connected (device xc7z020_1; JTAG clock 15000000 Hz)` |
| 3 | `t2_program full int16` | about 2.5 s; DONE LED on; LD7 blinks; LD3..0 blink together |
| 4 | `t2_status` | `rm_id 16 (int16)`, uptime counting, `runs 0` |
| 5 | `t2_set_precision int16 counting` | matrix with 110 at row 0, column 2; `matches golden: yes` |
| 6 | `t2_set_precision int8 counting` | `now int8 (swap about 430 ms)`; LD5/LD6 on and LD3..0 dark during the swap, then LD1 and LD0 blink; LD7 never stops; `matches golden: yes` |
| 7 | `t2_set_precision int4 counting` | only LD0 blinks; 70 at row 0, column 2; `matches golden: yes` |
| 8 | `show` helper, A all 100, B all 1 | int16 400, int8 400, int4 28 |
| 9 | `show` helper, A all 200, B all 1 | int16 800, int8 508, int4 28 |
| 10 | `t2_demo` | three tables (counting, random_full, extremes_neg); extremes_neg 2147483647 / 65536 / 256; `demo PASS`; writes `hw_demo_*.csv` |
| 11 | `t2_swap_demo grey` | ID ff during, 00 after; about 420 ms; LD3..0 dark, LD7 blinking; `VERDICT: PASS` |
| 12 | `t2_swap_demo int16` | ID 16; `VERDICT: PASS`; badge blinks again |
| 13 | `t2_block_test` | two `refused (PASS)`, one `accepted … PASS`; `block test PASS` |
| 14 | `t2_full_contrast` | about 2.5 s; all LEDs including LD7 stop, then restart; `uptime N -> 0`, `PASS` |
| opt. | `t2_selftest 1` | 2 full programs, 4 swaps; writes `hw_selftest_*.csv` |

Acts: Act 1 "it works" (steps 1–5), Act 2 "swap while it runs" (6–7), Act 3 "live saturation" (8–9), Act 4 "full comparison, then safety features" (10–13), Act 5 "the contrast" (14). Short version: steps 1–5, 7, 9, then 11 or 14.

Why steps 8 and 9 give those values: every result is four products summed. 100 fits int8 (limit 127), so int8 = int16 = 400; int4 clamps 100 to 7, so 4 × 7 = 28. 200 does not fit int8, so it clamps to 127: 4 × 127 = 508, not 800. Wrapping would have turned 200 into −56.

**LED legend (from the RTL; to be confirmed at the lab):**

| What you see | Meaning |
|---|---|
| Everything dark, DONE off | blank chip |
| LD7 blinking, LD3..0 blinking, LD5/LD6 off | a module is loaded and idle |
| plus LD4 on | a calculation finished |
| LD5 and LD6 on, LD3..0 dark, LD7 blinking | mid-swap: region isolated, static region alive |
| LD3..0 dark, LD7 blinking, LD5/LD6 off | empty module loaded |
| everything stops about 2.5 s, then restarts | full reprogramming (the contrast to a swap) |

*Sources: docs/DEMO.md*

---

## 9. Figure inventory

Viewed one by one. Screenshots may go in the deck; the report must not contain Vivado images.

| Path | Bytes | Pixels | What it shows |
|---|---:|---|---|
| `docs/t0/img/T0_screen.png` | 2,032,487 | 1200 × 1600 | Phone photo of the laptop: the T0 VIO dashboard with `vio_done` 1, `vio_sel` 2, `vio_result` 0000_006E (= 110) |
| `docs/t1/img/t1_dfx_cp1.png` | 163,989 | 1906 × 1120 | T1 project after adding sources: hierarchy (U_RST, U_UP, U_RP, U_DC, U_VIO), IP Catalog with the VIO core, VIO out-of-context run complete |
| `docs/t1/img/t1_dfx_synth_cp2.png` | 156,411 | 1915 × 1131 | T1 synthesised design (cfg_add): schematic of the static top and the Design Runs table (rm_add 25 LUT / 53 FF, rm_mul 8 / 36, VIO 170 / 559) |
| `docs/t1/img/t1_dfx_pblock_placement_cp2.png` | 136,579 | 1902 × 1122 | T1 Device view: `pblock_U_RP` drawn in the right part of clock region X1Y1; DRC with the single expected ZPS7-1 warning |
| `docs/t2/img/rtl_schematic.png` | 61,138 | 1541 × 1010 | Vivado elaborated schematic of `top_t2` (182 cells, 10 I/O ports, 968 nets) with U_RP, U_VIO and U_DC as blocks |
| `docs/t2/img/Child_runs_impl.png` | 101,873 | 1525 × 952 | T2 after implementation: Device view with `U_RP` in X1Y1, and the Design Runs table: impl_1 and three child runs with WNS 2.135 / 1.481 / 2.981 / 2.981, WHS 0.088, total power 0.135 / 0.127 / 0.124 / 0.116 W |
| `docs/t2/img/impl.png` | 125,809 | 1537 × 1027 | Implemented int16 design: utilisation bars (LUT 3%, DSP 7%), power 0.135 W (dynamic 0.032, static 0.103) with the dynamic breakdown, timing summary WNS 2.135 ns, WHS 0.088 ns, all constraints met |

Still to be made: the block diagram for the report (redraw; no Vivado image), any result charts, and the LED photos from the final lab.

---

## 10. Document inventory

| Document | One line |
|---|---|
| `README.md` | Project summary, status per tier, headline numbers, repo map, quick start |
| `docs/PROJECT_DETAIL.md` | The whole project for a reader with no FPGA background (T0 to T2, results, limits, applications, glossary) |
| `docs/DEMO.md` | Live demo script, LED legend, what to say, troubleshooting |
| `docs/t0/T0_Complete_Guide.md` | T0 from arithmetic to silicon |
| `docs/t1/T1_Complete_Guide.md` | T1 DFX mechanism, Pblock reasoning, flow, results, lessons |
| `docs/t1/T1_RESULTS.md` | T1 tables: build, bitstreams, swap times, functional results, predictions |
| `docs/t1/T1_PLAN.md`, `docs/t1/T1_BOARD_RUNBOOK.md` | T1 plan and board checklist |
| `docs/t2/T2_Complete_Guide.md` | T2 in plain language (Part I) and in technical depth (Part II) |
| `docs/t2/T2_PLAN.md` | T2 decisions, locked names, predictions, gotchas, as-built log |
| `docs/t2/T2_BOARD_RUNBOOK.md` | T2 lab playbook and the 2026-10-22 session record |
| `docs/t2/reports/` | Build, power, timing, simulation and board evidence (CSV, reports, log) |
| `docs/handoff/HANDOFF.md` | Task order, course rules, style, limits, Q&A seed, starter message |
| `docs/handoff/BRIEFING_PACK.md` | This file |
| `submission/note.txt` | Index of the source package: every file, its origin and meaning |

---

## 11. Glossary

| Term | Meaning |
|---|---|
| Accumulator | The running total inside a PE |
| Bitstream | The file that configures an FPGA: full (whole chip) or partial (one region) |
| Decoupler | Logic that forces the region's output wires to safe values during a swap |
| DFX | Dynamic Function eXchange: rewriting part of an FPGA while the rest runs |
| DRC | Design-rule check: Vivado's list of rule violations |
| DSP slice | A built-in multiplier-adder block; the chip has 220 |
| FPGA | A chip whose logic is rewired by loading a bitstream |
| Fmax | The fastest clock a design could run at; here an estimate from slack |
| Golden model | The trusted Python reference that computes the right answers |
| Greybox | An empty module that fills the region with tie-offs only |
| JTAG | The cable interface used to program and debug the chip |
| LUT | Lookup table: a small programmable logic cell |
| MAC | Multiply-accumulate: multiply two numbers and add to a running total |
| Output-stationary | Each PE keeps one output's running total; only inputs move |
| Partition pin | A wire crossing the region boundary (180 in T2) |
| Pblock | The fenced physical area that holds the swappable region |
| PE | Processing element: one tile of the array, one MAC per clock tick |
| `pr_verify` | Vivado check that all builds share an identical static region |
| RM / RP | Reconfigurable module (one variant) / reconfigurable partition (the region) |
| Saturation | Clamping a value to the largest or smallest allowed, instead of wrapping |
| Slack (WNS / WHS) | Spare time on the slowest path for setup / hold; positive means timing is met |
| Static region | The part of the chip that is never swapped |
| Systolic array | A grid of PEs passing data to neighbours each clock tick |
| Vectorless estimate | A power estimate that assumes default switching rates instead of recorded activity |
| VIO | Virtual input/output: a debug core giving on-screen switches and read-outs over JTAG |
