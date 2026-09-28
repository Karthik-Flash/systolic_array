# T1 Results — DFX Mechanism Proof on the ZedBoard

Spec: [T1_PLAN.md](T1_PLAN.md). Board `xc7z020clg484-1`, Vivado 2022.2 project mode, PL-only, JTAG.
Status: **Phase A done** (RTL + sims + scripts, tag `t1-rtl`). Phases B–D pending.

T0 baseline (historical anchor, not re-measured): 16 DSP48E1, 1,335 LUT, 665 FF, 0 BRAM, WNS +0.378 ns @ 100 MHz (UART system); VIO system WNS +1.427 ns.

---

## Phase A — pre-Vivado checks

| Check | Result |
|---|---|
| §6.1 vector table re-derived in Python (two's complement, 32-bit) | all 14 expected values correct |
| `scripts/t1/run_sims.py` (tb_rp_t1 × {add, mul}, tb_top_dfx × {add, mul}) | ALL PASS, 0 iverilog warnings |
| Mutation check (mul bench against `rm_add`) | both benches FAIL as expected |
| OOC synth `rm_add` (`scripts/t1/ooc_check.tcl`) | 25 LUT, 53 FF, **0 DSP** |
| OOC synth `rm_mul` | 8 LUT, 36 FF, **1 DSP** (y absorbed into the DSP P register) |

Deviations from the plan made in Phase A:
- `rm_mul`: `use_dsp = "yes"` moved from the module to the `prod` signal. On the module it also pushes adders into DSPs; the prescaler incrementer took a second DSP48E1 in OOC synthesis (2 DSP instead of 1).
- `top_dfx_pblock.xdc` header cites §7.8 (where the Pblock is drawn), not §7.6.
- `reports_t1.tcl` opens `top_dfx_routed.dcp` by exact name instead of globbing `*_routed.dcp`, so a static-only or RM-only checkpoint in a run folder can never be picked up.

---

## Pblock `pblock_U_RP`

| Item | Value |
|---|---|
| Ranges (from `constraints/top_dfx_pblock.xdc`) | |
| Clock region(s) | |
| Capacity LUT / FF / DSP / BRAM (Statistics tab) | |
| RESET_AFTER_RECONFIG / SNAPPING_MODE | |
| DFX DRC after synthesis (`docs/t1_reports/drc_dfx_synth.rpt`) | |

## Table A — Build (per configuration)

| Config | WNS (ns) | WHS (ns) | Total LUT | Total FF | Total DSP | U_RP LUT | U_RP FF | U_RP DSP | Pblock util (LUT% / DSP%) |
|---|---|---|---|---|---|---|---|---|---|
| cfg_add | | | | | | | | 0 | |
| cfg_mul | | | | | | | | 1 | |
| cfg_grey | | | | | | | | 0 | |

Static cost (VIO + debug hub + static logic) = `cfg_grey` totals minus greybox tie-offs: 

`pr_verify` (`docs/t1_reports/pr_verify.rpt`): 

## Table B — Bitstreams

| File | Size (bytes) | vs full |
|---|---|---|
| t1_full_add.bit | | 100% |
| t1_partial_add.bit | | |
| t1_partial_mul.bit | | |
| t1_partial_grey.bit | | |

## Table C — JTAG programming time (host wall-clock, mean ± sd over N)

| Operation | N | ms |
|---|---|---|
| Full program | 3 | |
| Partial add | 5 | |
| Partial mul | 5 | |
| Partial grey | 5 | |

Over JTAG this is **cable-bound**: time scales with bitstream size. It is an upper bound on swap latency, not the fabric's intrinsic reconfiguration time (an ICAP-based loader would be far faster; out of scope, PL-only via JTAG).

## Table D — Functional (on silicon)

| Check | add | mul | grey |
|---|---|---|---|
| §6.1 vectors pass | | | n/a (y = 0) |
| `rm_id` | | | |
| uptime continuous across every partial | | | |
| heartbeat never stopped during partial load (visual) | | | |

Uptime reset on full program (expected yes): 

Self-test CSV: `docs/t1_reports/hw_selftest_<timestamp>.csv`

---

## T2 decisions (T1_PLAN §13 — answer from T1 build + board evidence)

1. **Pblock:** does the T2-sized `pblock_U_RP` (≥ 20 DSP, ~4k LUT, one clock-region tall) close timing and pass DRC? If yes, T2 reuses it unchanged.
   Answer: 
2. **Partition boundary for T2:** whole 4×4 `array` as one RP. Raw `array` interface ≈ 900 partition pins (`west_bus` 64 + `north_bus` 64 + `acc_bus` 768 + control); moving result select + `sat32` inside the RM shrinks it to ≈ 150 (64 + 64 + `sel` 4 + `result` 32 + control). What do T1's partition-pin count and routing results say?
   Answer: 
3. **Frozen interface convention:** RMs keep int16-wide ports even for int8/int4 variants; quantisation happens inside the RM so the static side never changes.
   Answer: 
4. **Decoupler:** `dfx_decouple` reused with a new `W`/`SAFE`; the controller must also be blocked from starting a run while decoupled.
   Answer: 
5. **Swap latency method:** T1's JTAG timing method (Table C) is the one T3 reports, labelled JTAG-bound.
   Answer: 

### Quantisation notes for the T2 precision RMs (pre-T2 research, not yet decided)

Existing scaffolding to reuse, not reinvent — `python/quant.py`: `LIMITS` {16, 8, 4}, `saturate` / `clip_to_width` (clip + overflow mask), `quantise` (symmetric per-tensor, scale = max|x| / qmax, round, clip, caller may pass an explicit scale), `to_hex`, `pack_lanes`. `gen_vectors.py` is already width-parametric through `data_w`, and `golden.matmul_out` saturates to `OUT_W`. An int8 golden is therefore `quantise(x, 8)` → `matmul_out`; no new model code is needed.

- **Data format:** symmetric signed, zero-point 0. The PE stays a pure multiply-accumulate (no zero-point correction terms). With its default max-abs scale, `quantise` never produces −128 (|round(x/scale)| ≤ 127), so the −128 × −128 corner never occurs in real data. Keep it in the RTL test vectors anyway.
- **Frozen int16 ports (§13.3):** the int8 RM receives `a[15:0]` and must **saturate** it to int8, not truncate it. Truncating an out-of-range int16 wraps (for example 200 becomes −56). Saturation matches `quant.clip_to_width`, so golden = clip then matmul.
- **Accumulator headroom:** int8 × int8 fits in 16 bits. K = 4 sums fit in 18 bits, so `sat32` never fires for int8. int16 × int16 is 32 bits and K = 4 sums need 34 bits, so the existing `sat32` stays necessary for int16. ACC_W = 48 costs nothing, because it is the DSP P register.
- **Scaling stays on the host:** the RM outputs integer C. The host dequantises with C · s_A · s_B. For an output-stationary array, per-row scales on A and per-column scales on B also work with no RTL change (C[i][j] · s_A[i] · s_B[j]). No requantisation logic goes in the PL, so the frozen interface stays simple.
- **Clipping vs rounding error:** max-abs calibration (the current `quantise` default) never clips, but outliers waste resolution. Percentile calibration (for example 99.9 %) gives better resolution for most values but clips outliers. `quantise(x, w, scale=...)` already accepts either scale, so this is a host-side choice for the MNIST stage.
- **Resource story for T3 (the reason for DFX):** an int8 RM mapped to DSPs uses the same 16 DSP as int16, so it shows no resource gain. Two options show a real difference: (a) int8 multipliers in LUTs (`use_dsp = "no"`, 0 DSP), the same contrast T1 rehearses with `rm_add` and `rm_mul`; (b) two int8 multiplies packed into one DSP48E1 with a shared operand (8 DSP), which needs correction logic. Suggested first variant: (a), because it is the simplest; (b) can come later.
