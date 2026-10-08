# T1 Results — DFX Mechanism Proof on the ZedBoard

Board `xc7z020clg484-1`, Vivado 2022.2 project mode, PL-only, JTAG. Spec: [T1_PLAN.md](T1_PLAN.md). Explanation of everything below: [T1_Complete_Guide.md](T1_Complete_Guide.md).

**Status: T1 complete on silicon** (tags `t1-rtl` → `t1-built` → `t1-onboard`). Board session 2 (2026-10-08): 3 full programs and 15 partial swaps, all PASS. The static region kept running across every partial. Self-test CSV: [reports/hw_selftest_20261008_160232.csv](reports/hw_selftest_20261008_160232.csv).

T0 baseline (historical anchor, not re-measured): 16 DSP48E1, 1,335 LUT, 665 FF, 0 BRAM, WNS +0.378 ns @ 100 MHz (UART system); VIO system WNS +1.427 ns.

---

## T1 verdict

Dynamic Function eXchange works on this board with this toolchain, PL-only, over JTAG:
- One static design (`impl_1`, locked) served three configurations: `cfg_add`, `cfg_mul` and `cfg_grey`. All three meet timing at 100 MHz (worst WNS +3.501 ns) and pass `pr_verify`.
- On silicon, each 585,560 B partial bitstream swapped `U_RP` in **1,424 ± 27 ms** (N = 15). A full program takes **9,060 ± 73 ms** (N = 3).
- In all 15 partial swaps, `vio_uptime` kept counting (+2 s each). Every full program reset it to 0. That is the evidence that a partial is not a disguised full reconfiguration.
- After each swap, `rm_id` and every §6.1 vector matched the RM just loaded.
- Swap time is proportional to bitstream size and independent of the RM inside the Pblock. For T2 this means swap latency is set by the Pblock, not by the precision.

---

## Phase A — pre-Vivado checks

| Check | Result |
|---|---|
| §6.1 vector table re-derived in Python (two's complement, 32-bit) | all 14 expected values correct |
| `scripts/t1/run_sims.py` (tb_rp_t1 × {add, mul}, tb_top_dfx × {add, mul}) | ALL PASS, 0 iverilog warnings |
| Mutation check (mul bench against `rm_add`) | both benches FAIL as expected |
| OOC synth `rm_add` (`scripts/t1/ooc_check.tcl`) | 25 LUT, 53 FF, **0 DSP** |
| OOC synth `rm_mul` | 8 LUT, 36 FF, **1 DSP** (y absorbed into the DSP P register) |
| Mock-mode Tcl harness (`scripts/t1/hw_t1_mock.tcl`) | MOCK TESTS PASS; the negative run (a partial that resets uptime) FAILS 15/15 partial rows |

Deviations from the plan made in Phase A:
- `rm_mul`: `use_dsp = "yes"` moved from the module to the `prod` signal. On the module it also pushes adders into DSPs; the prescaler incrementer took a second DSP48E1 in OOC synthesis (2 DSP instead of 1).
- `top_dfx_pblock.xdc` header cites §7.8 (where the Pblock is made), not §7.6.
- `reports_t1.tcl` opens `top_dfx_routed.dcp` by exact name instead of globbing `*_routed.dcp`, so a static-only or RM-only checkpoint in a run folder can never be picked up.

---

## Pblock `pblock_U_RP`

| Item | Value |
|---|---|
| Ranges (from `constraints/top_dfx_pblock.xdc`) | `SLICE_X80Y50:SLICE_X103Y99`, `DSP48_X3Y20:DSP48_X4Y39`, `RAMB18_X4Y20:RAMB18_X4Y39`, `RAMB36_X4Y10:RAMB36_X4Y19` |
| Clock region(s) | right part of `X1Y1` (east of the configuration column), full clock-region height (Y50–Y99) |
| Capacity LUT / LUTRAM / FF / DSP / BRAM tile (`reports/cfg_*_utilization_pblock.rpt`) | 4,400 / 1,800 / 8,800 / 40 / 10 |
| RESET_AFTER_RECONFIG / SNAPPING_MODE | true / ON |
| Created by | Tcl from the device database, not drawn (see T1_PLAN §7.8) |
| DFX DRC after synthesis (`reports/drc_dfx_synth.rpt`) | 0 errors, 1 warning: ZPS7-1 (PS7 not used, expected for PL-only) |

## Table A — Build (per configuration)

All numbers are post-route, from `reports/`: WNS/WHS from `<cfg>_timing_summary.rpt`, totals from `<cfg>_utilization.rpt`, U_RP from `<cfg>_utilization_U_RP.rpt`, Pblock % from `<cfg>_utilization_pblock.rpt`.

| Config | WNS (ns) | WHS (ns) | Total LUT | Total FF | Total DSP | U_RP LUT | U_RP FF | U_RP DSP | Pblock util (LUT% / DSP%) |
|---|---|---|---|---|---|---|---|---|---|
| cfg_add | +4.304 | +0.039 | 676 | 1,465 | 0 | 40 | 53 | 0 | 0.91% / 0.00% |
| cfg_mul | +3.501 | +0.039 | 644 | 1,448 | 1 | 8 | 36 | 1 | 0.18% / 2.50% |
| cfg_grey | +4.304 | +0.039 | 713 | 1,413 | 0 | 77 | 1 | 0 | 1.75% / 0.00% |

TNS = THS = 0 in all three. Every configuration uses 0 BRAM, 10 bonded IOB and 2 BUFG (`reports/cfg_add_utilization.rpt`).

- **U_RP LUTs vs synthesis:** `rm_add` goes from 25 LUT (synth) to 40 (routed), and the routed RM has 20 LUT1s (`reports/cfg_add_utilization_U_RP.rpt`). Synthesis merged y[31:17] into one flop, since they are all sign copies of the same bit. Most likely Vivado then added LUT1 buffers so that each partition pin has its own driver.
- **Greybox:** 77 LUT1 = 44 output tie-offs (32 y + 8 rm_id + 4 led_pat) + 33 input loads (a 16 + b 16 + rst_n), plus one FDCE as the clock load (`reports/cfg_grey_utilization_U_RP.rpt`).
- **Static cost** (VIO + debug hub + static logic) = `cfg_grey` totals minus greybox = 713 − 77 = **636 LUT**, 1,413 − 1 = **1,412 FF**, 0 DSP.
- **BUFGs** (printed by `reports_t1.tcl`, identical in all three configs): `clk_IBUF_BUFG_inst` → `clk_IBUF_BUFG` (system clock, 979–1,031 loads); `dbg_hub/.../u_bufg_icon_tck` → `itck_i` (debug hub JTAG TCK, 482 loads).
- **Partition pins:** 78, reported as `Total PPLOCs 78` on `U_RP` in `reports/<cfg>_utilization_hier.rpt`. This matches the port list: inputs clk 1 + rst_n 1 + a 16 + b 16 = 34; outputs y 32 + rm_id 8 + led_pat 4 = 44.
- **Where the static cost goes** (`reports/cfg_grey_utilization_hier.rpt`): `dbg_hub` 447 LUT (24 as LUTRAM) / 741 FF and `U_VIO` 168 LUT / 559 FF, which is about 97% of the static LUTs and 92% of the static FFs. Our own static logic is tiny: `U_UP` 18 / 65, `U_DC` 1 / 44, `U_RST` 2 / 2, top-level `rm_rst_n` 1 / 1. (The hierarchy rows sum to 714 LUT against the 713 total; Table A uses the totals.)
- **Critical paths** (`reports/<cfg>_timing_summary.rpt`, sys_clk): in `cfg_add` and `cfg_grey` the worst path (+4.304 ns) is inside `dbg_hub`, 5 logic levels. In `cfg_mul` it is `U_VIO/.../Probe_out_reg[15]` → `U_RP/y_reg/A[20]` (+3.501 ns): a static VIO register driving the DSP's A input across a partition pin, with 0 logic levels and 2.692 ns data path (83% routing). That is the same unregistered-DSP-input situation the DPIP-1 warning describes.

**Implemented DRC** (`reports/<cfg>_drc.rpt`, 0 errors in all configs):

| Rule | Configs | Count | Where | Verdict |
|---|---|---|---|---|
| ZPS7-1 PS7 block required | all | 1 | top | Expected: PL-only design, configured over JTAG |
| PDCN-1569 LUT equation term check | all | 3 | `dbg_hub` (Xilinx debug IP) | Harmless: LUT pins tied inside Xilinx IP; not our RTL |
| RTSTAT-10 No routable loads | all | 1 (17 nets) | `dbg_hub` internals (unused FIFO flags, BSCAN TMS, ...) | Harmless: unused IP outputs |
| DPIP-1 Input pipelining | cfg_mul | 2 | `U_RP/y_reg` DSP A/B inputs | Harmless for T1 (WNS +3.5 ns). Relevant to T2's DSP-based PEs |
| DPOP-2 MREG output pipelining | cfg_mul | 1 | `U_RP/y_reg` (MREG=0) | Harmless for T1. Same T2 note |

No DFX-specific DRC violations. Nothing needs action for T1.

`pr_verify -full_check` (`reports/pr_verify.rpt`): **PASS**. impl_1 is compatible with child_0_impl_1, and impl_1 is compatible with child_1_impl_1.

## Table B — Bitstreams

Source: `bitstreams/t1/manifest.csv` (sizes, sha256, source run). Staleness guard passed: every child bitstream is newer than impl_1's routed checkpoint.

| File | Size (bytes) | vs full |
|---|---|---|
| t1_full_add.bit | 4,045,667 | 100% |
| t1_partial_add.bit | 585,560 | 14.5% |
| t1_partial_mul.bit | 585,560 | 14.5% |
| t1_partial_grey.bit | 585,560 | 14.5% |

All partials are the same size, because a partial rewrites every frame of the Pblock regardless of how much logic it holds. So partial size scales with Pblock area, not with RM content. The full bitstreams from the child runs (`t1_full_mul.bit`, `t1_full_grey.bit`) are also 4,045,667 bytes: a full bitstream covers the whole device, so its size doesn't depend on the design.

## Table C — JTAG programming time (host wall-clock, mean ± sd over N)

Source: [reports/hw_selftest_20261008_160232.csv](reports/hw_selftest_20261008_160232.csv), column `program_ms`. This is the wall-clock time of `program_hw_devices` alone; `refresh_hw_device` and the VIO accesses are not included.

| Operation | N | ms (mean ± sd) | min – max |
|---|---|---|---|
| Full program (`t1_full_add.bit`) | 3 | **9,060 ± 73** | 8,986 – 9,132 |
| Partial add | 5 | 1,422 ± 26 | 1,390 – 1,457 |
| Partial mul | 5 | 1,425 ± 34 | 1,391 – 1,472 |
| Partial grey | 5 | 1,424 ± 28 | 1,392 – 1,460 |
| All partials | 15 | **1,424 ± 27** | 1,390 – 1,472 |

Session 2 demo runs (console log, not in the CSV): full 9,146 ms; partial mul 1,460, grey 1,463, add 1,393 ms. Session 1 (manual, N = 1): full ≈ 9 s.

Over JTAG this is **cable/host-bound**: an upper bound on swap latency, not the fabric's intrinsic reconfiguration speed. Faster loaders (ICAP from fabric logic, PCAP from the PS, or a higher JTAG clock) are out of scope for a PL-only JTAG design.

### Size vs time

| | Full | Partial | Ratio |
|---|---|---|---|
| Size (B) | 4,045,667 | 585,560 | **14.5%** |
| Time (ms, mean) | 9,060 | 1,424 | **15.7%** |

Straight line `t = a + b·size` through the two means:
- b = (9,060.3 − 1,423.6) ms / (4,045,667 − 585,560) B = 7,636.7 ms / 3,460,107 B ≈ **2.21 µs/B**. That is ≈ 453 kB/s, or ≈ 3.6 Mbit/s effective.
- a = 9,060.3 − 2.207 µs/B × 4,045,667 B ≈ **0.13 s** fixed overhead per program.

So JTAG programming time is almost purely proportional to bitstream size. The time ratio (15.7%) is a little above the size ratio (14.5%) only because of the 0.13 s fixed overhead. With two operating points this is a two-point line, not a regression; it fits the data exactly by construction.

## Table D — Functional (on silicon)

**Session 1 (full only), 2026-09-29.** Only `t1_full_add.bit` + `t1_full_add.ltx` were programmed.

| Observation | Result |
|---|---|
| `vio_rm_id` after full program | **A1** |
| a = 0003, b = 0004 → `vio_y` | **0000_0007** (correct for `rm_add`) |
| `vio_uptime` | counting |
| decouple = 0, rm_rst = 0 | LD3..LD0 binary counting, LD7 heartbeat |
| decouple = 1 | LD5 + LD6 + LD7 on, LD3..LD0 dark: RM isolated and held in reset, static alive |
| rm_rst = 1, decouple = 0 | LD6 + LD7 on: the RM reset path works on its own |
| Full program over JTAG (N = 1) | ≈ 9 s |

**Before session 2:** loading a partial onto a freshly powered (blank) device was refused by Vivado: `[Xicom 50-103] Static bitstream must first be programmed ...`, with DONE = 0. This is the expected safety check (T1_PLAN gotcha #8). A partial only rewrites the Pblock, so the matching full bitstream must already be in the device.

**Session 2 (partial swaps), 2026-10-08.** `source scripts/t1/hw_t1.tcl`, then the runbook sequence.

| # | Command | Program ms | rm_id / y (a=3, b=4) | uptime before → after | Verdict |
|---|---|---|---|---|---|
| 1 | `t1_program full add` | 9,146 | A1 / 0000_0007 | — | "End of startup status: HIGH", 1 VIO core found |
| 2 | `t1_swap_demo mul` | 1,460 | A1 / 0000_0007 → decoupled FF / 0000_0000 → **B2 / 0000_000C** | 17 → 19 s (+2) | PASS |
| 3 | `t1_swap_demo grey` | 1,463 | B2 / 0000_000C → **00 / 0000_0000** | 43 → 45 s (+2) | PASS |
| 4 | `t1_swap_demo add` | 1,393 | 00 / 0000_0000 → **A1 / 0000_0007** | 67 → 69 s (+2) | PASS |
| 5 | `t1_full_contrast` | ≈ 9 s | A1 before | 88 s → (AFTER line cut off in the pasted log) | see note |
| 6 | `t1_selftest` | Table C | 18/18 rows PASS | partials +2 s each; fulls reset | **T1 SELFTEST PASS** |

Note on #5: the pasted console log ends before `t1_full_contrast` printed its AFTER line, so this run's uptime-after is not recorded. Self-test rows 2 and 3 show the same contrast independently: uptime 4 s before each full program, 0 s after (`reset=yes`).

Per-RM summary (self-test CSV, rows 4–18, plus the full-program rows 1–3 for `add`):

| Check | add | mul | grey |
|---|---|---|---|
| §6.1 vectors pass (`t1_check`, all 7 vectors) | 8/8 programs (3 full + 5 partial) | 5/5 partials | 5/5 partials (y = 0 for every vector) |
| `rm_id` | A1 | B2 | 00 |
| uptime continuous across every partial (`after − before ≥ floor(ms/1000)`) | 5/5, +2 s each | 5/5, +2 s each | 5/5, +2 s each |
| heartbeat never stopped during partial load (visual) | yes (see LED timeline) | yes, filmed during cmd 2 | yes |
| uptime reset on full program | 2/2 full programs with a "before" value (rows 2, 3) | — | — |

Every program printed `WARNING: [Labtools 27-1952] VIO hw_probe OUTPUT_VALUE properties differ ...`. This is harmless. Right after a (re)program, Vivado's cached copy of the VIO output-probe values no longer matches the core. The script then writes the values again (`t1_swap` and `t1_swap_demo` re-assert `decouple` 1 → 0 and re-write a, b), which brings the cache back in sync. The VIO readings above were all taken after those writes.

### LED timeline: expected (from RTL) vs observed (operator, from the video and memory)

The VIO readings are the authoritative evidence. The LED observations were recalled after the session and are approximate.

| Cmd | Expected (RTL) | Observed | Explanation |
|---|---|---|---|
| 1 full add | Whole chip reconfigured (~9 s, DONE low, LEDs not driven), then LD3..0 binary count, LD7 1 Hz | "LD3–0 blink at different rates (normal pattern)" | `rm_add` steps `pat <= pat + 1` every 2^24 cycles = 167.8 ms. LD0 toggles every step (≈ 3.0 Hz blink), LD1 ≈ 1.5 Hz, LD2 ≈ 0.75 Hz, LD3 ≈ 0.37 Hz |
| 2 swap → mul | During the swap (~2 s): LD5 + LD6 on, LD3..0 dark, LD7 keeps blinking. After release: walking one | "LD3–0 light up sequentially, faster"; heartbeat unchanged | `rm_mul` walking one: exactly one LED lit, moving every 167.8 ms; full sweep 4 × 167.8 = 671 ms. LD7 is static logic, untouched by the partial |
| 3 swap → grey | Swap as above; then LD3..0 dark, LD5 and LD6 off, only LD7 blinking | "Only LD7 blinking" | Greybox ties all RP outputs to 0, so `led_pat` = 0000. LD6 = ~rm_rst_n is off because the RM is released from reset after the swap |
| 4 swap → add | Swap as above; then binary count again | Operator thought "similar to cmd 2" | VIO read A1 and y = 0000_0007, so `rm_add` was loaded and the LEDs must have shown the binary count. The recollection is most likely mixed up with cmd 2. VIO is authoritative |
| 5 full contrast | ~9 s with the whole chip reconfiguring (LD7 stops), then binary count | "Took a while to program", then the same pattern again | A full bitstream rewrites the whole device, so static logic stops too and uptime restarts at 0 |
| 6 selftest | 3 full programs (three ~9 s gaps), then 15 swaps cycling mul → add → grey (walking one / count / dark) | "Repeated reprogramming" | As designed |

Why LD7 never pauses during a partial: a partial bitstream rewrites only the configuration frames inside `pblock_U_RP`. The static region's logic, its clock buffer and its routing sit outside those frames, so they keep running. Uptime advancing +2 s across every partial (≈ 1.4 s program + VIO round trips) is the measured form of the same fact.

### Predictions (written before session 2) vs measurements

| Prediction | Measured | Verdict |
|---|---|---|
| Partial = 585,560 B = 14.5% of full | 585,560 / 4,045,667 = 14.5% (Table B) | ✔ (this was already measured) |
| Swap time set by Pblock size, not RM contents: add, mul, grey equal within noise | 1,422 / 1,425 / 1,424 ms; sd 26–34 ms | ✔ |
| If JTAG transfer dominates: partial ≈ 1.5–2.5 s vs ≈ 9 s full | 1,424 ms vs 9,060 ms | Slightly pessimistic. Pure size scaling (9,060 × 0.145 ≈ 1.31 s) was closer; the fixed overhead is only ≈ 0.13 s |
| Uptime +1–3 s per partial, ≈ 0 after a full program | +2 s on all 15 partials; 0 after each full | ✔ |

---

## T2 decisions (T1_PLAN §13): facts from T1

1. **Pblock:** does the T2-sized `pblock_U_RP` (≥ 20 DSP, ~4k LUT, one clock-region tall) close timing and pass DRC?
   Yes. `pblock_U_RP` (4,400 LUT / 8,800 FF / 40 DSP / 10 BRAM, right part of X1Y1) meets timing in all three configs (worst WNS +3.501 ns), has 0 DRC errors, passes `pr_verify`, and swapped correctly 15/15 times on silicon. It can be reused unchanged. 40 DSP is 2.5× the 16 PEs.
2. **Partition boundary for T2:** whole 4×4 `array` as one RP. The raw `array` interface is ≈ 900 partition pins (`west_bus` 64 + `north_bus` 64 + `acc_bus` 768 + control); with result select + `sat32` inside the RM it is ≈ 150 (64 + 64 + `sel` 4 + `result` 32 + control).
   T1 fact: 78 partition pins routed with ≥ 3.5 ns slack. T1 has no data point anywhere near 900 pins, so it doesn't settle this question; it is open for T2 kickoff.
3. **Frozen interface convention:** RMs keep int16-wide ports even for int8/int4 variants.
   T1 fact: one frozen port list served two RMs and a greybox, and `pr_verify` passed. T1 did not test narrower internal datapaths behind wide ports.
4. **Decoupler:** `dfx_decouple` reused with a new `W`/`SAFE`; the controller must not start a run while decoupled.
   T1 fact: decouple + RM reset isolated the RP on all 15 swaps (`rm_id` FF, y 0 while decoupled). T1 has no controller, so the "no start while decoupled" rule is untested.
5. **Swap latency method:** T1's JTAG timing (Table C) is the method T3 reports, labelled JTAG-bound.
   T1 fact: 1,424 ± 27 ms per partial, ≈ 2.21 µs per bitstream byte plus ≈ 0.13 s fixed. Any RM in this Pblock has the same partial size, so the same swap time.

### Quantisation notes for the T2 precision RMs (pre-T2 research, not yet decided)

Existing scaffolding to reuse, not reinvent — `python/quant.py`: `LIMITS` {16, 8, 4}, `saturate` / `clip_to_width` (clip + overflow mask), `quantise` (symmetric per-tensor, scale = max|x| / qmax, round, clip, caller may pass an explicit scale), `to_hex`, `pack_lanes`. `gen_vectors.py` is already width-parametric through `data_w`, and `golden.matmul_out` saturates to `OUT_W`. An int8 golden is therefore `quantise(x, 8)` → `matmul_out`; no new model code is needed.

- **Data format:** symmetric signed, zero-point 0. The PE stays a pure multiply-accumulate (no zero-point correction terms). With its default max-abs scale, `quantise` never produces −128 (|round(x/scale)| ≤ 127), so the −128 × −128 corner never occurs in real data. Keep it in the RTL test vectors anyway.
- **Frozen int16 ports (§13.3):** the int8 RM receives `a[15:0]` and must **saturate** it to int8, not truncate it. Truncating an out-of-range int16 wraps (for example 200 becomes −56). Saturation matches `quant.clip_to_width`, so golden = clip then matmul.
- **Accumulator headroom:** int8 × int8 fits in 16 bits. K = 4 sums fit in 18 bits, so `sat32` never fires for int8. int16 × int16 is 32 bits and K = 4 sums need 34 bits, so the existing `sat32` stays necessary for int16. ACC_W = 48 costs nothing, because it is the DSP P register.
- **Scaling stays on the host:** the RM outputs integer C. The host dequantises with C · s_A · s_B. For an output-stationary array, per-row scales on A and per-column scales on B also work with no RTL change (C[i][j] · s_A[i] · s_B[j]). No requantisation logic goes in the PL, so the frozen interface stays simple.
- **Clipping vs rounding error:** max-abs calibration (the current `quantise` default) never clips, but outliers waste resolution. Percentile calibration (for example 99.9 %) gives better resolution for most values but clips outliers. `quantise(x, w, scale=...)` already accepts either scale, so this is a host-side choice for the MNIST stage.
- **Resource story for T3 (the reason for DFX):** an int8 RM mapped to DSPs uses the same 16 DSP as int16, so it shows no resource gain. Two options show a real difference: (a) int8 multipliers in LUTs (`use_dsp = "no"`, 0 DSP), the same contrast T1 rehearses with `rm_add` and `rm_mul`; (b) two int8 multiplies packed into one DSP48E1 with a shared operand (8 DSP), which needs correction logic.
