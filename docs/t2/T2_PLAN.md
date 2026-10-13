# T2 Plan — Precision Variants Behind One Frozen Interface

**Project:** Precision-scalable systolic matrix multiplier with runtime precision swapping via DFX (CS G553, BITS Hyderabad)
**Tier:** T2 — the reconfigurable partition becomes the real 4×4 array in **int16 / int8 / int4**
**Board / tools:** ZedBoard `xc7z020clg484-1` · Vivado 2022.2 (project mode) · Icarus Verilog · Python 3 (`.venv`) · Windows · repo `D:/Projects/RC_Project`
**Starts from:** `main` @ `274c37f` (tag `t1-onboard`)

**This file is the single source of truth for T2.** Claude Code implements from it. Every deviation is logged in §16 and the affected section is corrected in the same commit. Numbers in this plan marked *predicted* or *computed* are not results; results come only from reports, logs and CSVs.

---

## Contents

0. Phases, roles, today's target
1. Goal and definition of done
2. Kickoff decisions (handoff §6.1), made
3. Architecture
4. Locked names
5. Repo layout, .gitignore, cleanup policy
6. RTL specification
7. Golden model and test vectors
8. Verification before Vivado (Phase A1)
9. Vivado build walkthrough (Phase B) with checkpoints
10. Collect, report, verify (Phase C)
11. Board (Phase D): scripts, mock, session
12. Predictions and the measurement table
13. Gotchas
14. Claude Code prompts (A1, A2, C, D)
15. Today's timeline
16. As-built log

---

## 0. Phases, roles, today's target

| Phase | Who | What | Ends with |
|---|---|---|---|
| **A1** | Claude Code | branch, harvest T1 facts, cleanup, skeleton; golden + vectors; RTL; benches; OOC gates; project script validated in scratch | tag `t2-rtl` |
| **B** | Karthik (Vivado GUI) | create `t2_dfx` from the script, inspect, synthesise, DRC, implement 4 configurations to bitstream | CP5 screenshot |
| **A2** | Claude Code, *in parallel with B* | collect + report scripts, `hw_t2.tcl` + mock harness, board runbook, results skeleton | commit (no tag) |
| **C** | Claude Code | collect bitstreams, reports, `pr_verify`, gates, results tables | tag `t2-built` |
| **D** | Karthik (lab), then Claude Code | board session; ingest CSVs and logs | tag `t2-onboard` |

**Today:** A1 → B (A2 runs alongside the build) → C. **Next lab session:** D.

Roles are unchanged from T0/T1: the chat plans, reviews checkpoints and diagnoses; Karthik carries prompts and results and does every GUI and board step; Claude Code writes and runs everything in the repo and cannot see the GUI or the board.

Rules carried from T0/T1: never invent numbers; rehearse every board script in mock mode first; program only collected, staleness-checked bitstreams; run `pr_verify` before any partial; always load the matching full bitstream first.

---

## 1. Goal and definition of done

**Goal.** `U_RP` holds the 4×4 output-stationary systolic array in three precisions behind one frozen port list, inside the unchanged T1 Pblock. Each RM is bit-exact against its own golden vectors in simulation and on silicon, and swapping between them at runtime leaves the static region running.

**T2 is done when all of these hold:**

1. `python python/test_golden_t2.py` → ALL PASS; vectors for 3 precisions × 9 cases exist under `sim/t2_vectors/`.
2. `python scripts/t2/run_sims.py` → **ALL PASS** (6 positive builds) and **NEGATIVE OK** (3 negative builds fail as required); the three RM port lists are identical.
3. `scripts/t2/ooc_check.tcl` → **OOC PASS** (gates in §8.3).
4. `scripts/t2/create_project_t2.tcl` validated in a scratch project, including synthesis of the static design and all three RMs → **SCRATCH OK**.
5. Four configurations routed to bitstream; each has WNS ≥ 0, WHS ≥ 0 and 0 DRC errors; `pr_verify` PASS across all four.
6. `bitstreams/t2/` holds 4 full + 4 partial `.bit`, `t2_full_int16.ltx` and `manifest.csv`; the staleness guard passes.
7. `scripts/t2/hw_t2_mock.tcl` → **MOCK TESTS PASS**, and every negative mock fails as required.
8. On silicon (§11): every RM reproduces its golden `c_out` for the board case set; 12 partial swaps with uptime continuity; start refused while decoupled; self-test CSV saved.
9. `docs/t2/T2_RESULTS.md` is filled from reports and CSVs only; tags `t2-rtl`, `t2-built`, `t2-onboard` exist.

---

## 2. Kickoff decisions (handoff §6.1), made

Format: decision → why → consequence.

### D1. Partition boundary: array + input clamps + readout inside the RP

- The RP contains the boundary input register, per-lane input saturation, the 4×4 array, the 16:1 result select, the accumulator → 32-bit conversion, `rm_id` and the LED badge.
- **≈ 179 partition pins** (134 in, 45 out) instead of ≈ 900 for a bare array.
- **Why:** 5× fewer partition pins means fewer PPLOCs to place and fewer static↔RP timing paths; the static region becomes precision-independent; each RM owns its arithmetic end to end (clamp in, convert out). Reading one result at a time through `sel` costs nothing, because VIO reads one value per transaction anyway.
- **Consequence:** the static side never sees an accumulator width. A future precision is one new RM file.

### D2. Frozen interface: int16 lanes for every variant; each RM saturates at the array edge

- Lanes stay 16-bit signed. Each RM clamps its 8 edge lanes (4 west + 4 north) once, to the **full two's-complement range** of its width, [−2^(W−1), 2^(W−1)−1]. The relay registers inside the array are therefore W bits wide.
- Saturate, never truncate (truncating 200 to 8 bits gives −56).
- Results always leave as 32-bit signed: `sat32` for int16, sign extension for int8/int4.
- Host-side quantisation (T3) is symmetric with zero-point 0 and produces values already in range. The RM clamp is a safety net, and it is the semantic the golden model must match bit for bit.

### D3. Arithmetic: int16 on DSPs (T0's PE, unchanged); int8 and int4 in LUTs with minimal accumulators

- `rm_int16` instantiates T0's `rtl/pe.v` and `rtl/array.v` **unchanged** (DATA_W 16, ACC_W 48): one DSP48E1 per PE, 16 in total. This is the like-for-like T0 baseline inside the DFX build.
- `rm_int8` and `rm_int4` use `pe_lut` with module-level `use_dsp = "no"`: 0 DSP.
- Accumulator width = 2W + 2 (four products, log2 4 = 2): **int8 18 bits, int4 10 bits.**
- **Correction to the handoff.** "17 / 9 bits" only holds for symmetric inputs (±127, ±7). The RM clamps to the full range, so −128 and −8 can occur: 4·(−128)² = 65,536 needs 18 signed bits, and 4·(−8)² = 256 needs 10. The `extremes_neg` case proves this boundary in simulation and on silicon.
- Rejected: DSP-based int8 (no resource contrast with int16); two int8 MACs per DSP (signed packing needs correction terms, gives no throughput gain for a fixed 4×4, and costs time).
- **Consequence:** the T3 table shows a clean DSP ↔ LUT trade-off: 16 / 0 / 0 DSP, with LUTs rising for the LUT-based variants.

### D4. Static side: T0 controller unchanged, a registered feed stage, a gated start

- `rtl/controller.v` (T0) is instantiated unchanged. Its `a_bus`/`b_bus` come straight from the VIO.
- New in `top_t2`: a register stage on `west_bus`, `north_bus` and `clr_acc` between the controller and the RP (see D6).
- **Start gating (the open T1 requirement):** `start_ok = start_rise & rm_rst_n & ~vio_decouple & ~busy`. A refused start sets a sticky `blocked` flag, cleared by the next accepted start. Accepted starts increment `runs`.
- `done_flag` is set 2 cycles after the controller's done rises (one cycle per boundary register) and is cleared by decouple, RM reset or a new accepted start. After any swap, results are invalid until a re-run, and the flag says so.
- Reused unchanged, by reference: `rtl/t1/rst_sync.v`, `rtl/t1/uptime.v`, `rtl/t1/dfx_decouple.v` (new `W` = 45 and `SAFE` set by parameters from the static top).

### D5. Matrices in: VIO-loaded A and B; results out through a `sel` loop

- Two 256-bit VIO output probes (`vio_a`, `vio_b`) carry A and B; any matrix can be run live. The same probes serve the self-test, the demo and T3's error measurements.
- The same golden hex files drive the benches and the board. `a_probe.hex` / `b_probe.hex` are the exact 64-hex-digit probe strings, so one answer key runs from Python to silicon.
- No hardcoded matrix sets in RTL.

### D6. DSP pipelining: no AREG/BREG change; register the partition boundary on both sides

- Static feed register → partition pin → RM input register. Every static↔RP data path becomes flop → pin → flop: the structure T1 measured at +3.5 ns with 0 logic levels.
- The controller's staircase selector (T0's critical path, +0.378 ns into an unregistered DSP A input with 3.7 ns setup) now ends at an ordinary flop.
- Cost: +2 cycles of latency, identical for every RM. Revisit AREG/BREG only if `cfg_int16` WNS < +0.5 ns.

### D7. Cycles: identical across precisions by construction

- Compute latency = T0's controller schedule + 2 boundary registers. `tb_top_t2` measures it for every case and RM and writes `docs/t2/reports/sim_cycles.csv`. The plan predicts equality; the bench proves it.
- No on-board cycle counter: `done` is generated in the static region, so a counter there would measure static logic, not the RM.

### D8. Pblock: reuse `pblock_U_RP` unchanged

- Same instance name `U_RP`, so the T1 Pblock text applies verbatim. Capacity 4,400 LUT / 8,800 FF / 40 DSP / 10 BRAM.
- Fit is gated by out-of-context synthesis in Phase A1: LUT ≤ 2,200 (≤ 50 %, leaving routing headroom), DSP 16 / 0 / 0, BRAM 0.

### D9. Four configurations, greybox included

int16 (parent), int8, int4, grey. The greybox is a blank-RP control for the self-test and a static-only baseline for T3. With `-jobs 4` the children run in parallel, so it costs almost no wall time.

### D10. Build method: scripted project, GUI-driven runs

Claude Code writes `scripts/t2/create_project_t2.tcl` from T1's own Vivado journal and project file, and validates it in a scratch project (including synthesis). Karthik sources it inside the Vivado GUI, inspects every object at checkpoints, and launches synthesis and implementation from the GUI.
Why: DFX setup is irreversible and click-heavy; a script is exact, reproducible for the report, and removes the misclick class of bugs. Inspecting the result in the GUI, with the Tcl↔GUI map in §9.3, keeps the learning.

### D11. Identity codes and LEDs

- `rm_id`: int16 **`16`**, int8 **`08`**, int4 **`04`**, greybox `00`, decoupled `FF`. Readable at a glance in the VIO dashboard. (`08` is also the Tcl 8.5 octal trap; see G19.)
- LED badge on LD3..0: **number of lit LEDs = precision / 4.** int16 `1111`, int8 `0011`, int4 `0001`, blinking at about 3 Hz (prescaler 2²⁴). Blinking proves the RM is clocked; dark means greybox or decoupled.

---

## 3. Architecture

```
                                        top_t2   (STATIC region)
 clk (Y9, 100 MHz) ─IBUF/BUFG─────────────────────────────────────────────────────── clk to all
 btn_rst (P16, BTNC) ─► U_RST rst_sync ─► sys_rst_n          (press = reset, release = run)
                        U_UP  uptime   ─► vio_uptime[31:0] (seconds), heartbeat (1 Hz)

 U_VIO : vio_t2 (JTAG)
   out ─► vio_decouple  vio_rm_rst  vio_start  vio_sel[3:0]  vio_a[255:0]  vio_b[255:0]
   in  ◄─ vio_result[31:0]  vio_rm_id[7:0]  vio_uptime[31:0]  vio_flags[3:0]  vio_runs[15:0]

 vio_start ─► edge ─► start_rise ─► gate: rm_rst_n & ~vio_decouple & ~busy ─► start_ok ─► runs + 1
                                       └─ refused ─► blocked (sticky)
 vio_a, vio_b ─► U_CT controller (T0, unchanged) ─► ct_west[63:0] ct_north[63:0] ct_clr ct_done
                                                        │  feed registers (static)
                                                        ▼
                                  west_q[63:0]  north_q[63:0]  clr_q        vio_sel[3:0]    rm_rst_n
 ═══════════════════════════════════ partition boundary (pblock_U_RP) ══════════════════════════════
                                                        ▼                         ▼              ▼
   U_RP : rp_t2  ┌─────────────────────────────────────────────────────────────────────────────┐
                 │ input register  (+ lane_sat 16 → W bits in int8 / int4)                     │
                 │ 4×4 array: int16 = T0 pe/array (DSP48E1) │ int8, int4 = pe_lut (LUT fabric) │
                 │ 16:1 select by sel ─► sat32 (int16) / sign-extend ─► result, ovf (flops)    │
                 │ rm_badge: rm_id (dont_touch flops), led_pat                                 │
                 └───────────────┬──────────────────────┬────────────────────┬────────────────┘
 ════════════════════════════════│══════════════════════│════════════════════│═══════════════════
                         result[31:0], ovf          rm_id[7:0]          led_pat[3:0]
                                 ▼                      ▼                    ▼
                 U_DC dfx_decouple W = 45   decouple=1 → result 0, ovf 0, rm_id FF, led 0000
                                 ▼
                 result_s, ovf_s, rm_id_s, led_s ─► VIO inputs and LEDs

 ct_done ─► 2-cycle delay ─► done_flag   (cleared by vio_decouple, RM reset, start_ok)
 rm_rst_n <= sys_rst_n & ~vio_decouple & ~vio_rm_rst            (registered, as in T1)
 LEDs: LD3..0 = led_s (precision badge) │ LD4 = done_flag │ LD5 = vio_decouple │ LD6 = ~rm_rst_n │ LD7 = heartbeat
```

**Partition-pin budget** (clock excluded):

| Direction | Signals | Pins |
|---|---|---|
| in | `rst_n` 1, `clr_acc` 1, `west_bus` 64, `north_bus` 64, `sel` 4 | 134 |
| out | `result` 32, `ovf` 1, `rm_id` 8, `led_pat` 4 | 45 |
| **total** | | **179** (T1: 78) |

**Latency.** A run follows T0's controller schedule (CLEAR + 10 STREAM cycles); the feed register and the RM input register delay everything by 2 cycles, so accumulators are final 2 cycles after `ct_done` rises, and `done_flag` rises one cycle later. Reading a result: `sel` → RM `result` register → decoupler register = 2 cycles; JTAG makes this irrelevant on the board, but benches wait ≥ 3 cycles after changing `sel`.

**The swap protocol is T1's, unchanged:** `vio_decouple = 1` (outputs safe, RM held in reset, `done_flag` cleared, start refused) → program partial → write `vio_decouple` 1 then 0 (a real write) → `rm_id` shows the new RM → load A/B, run, read.

---

## 4. Locked names

| Item | Locked value |
|---|---|
| Git branch | `t2-precision`, from `main` @ `t1-onboard` |
| Tags | `t2-rtl` (end A1), `t2-built` (end C), `t2-onboard` (end D) |
| Vivado project | `t2_dfx` at `D:/Projects/RC_Project/vivado/t2_dfx` (gitignored; DFX enabled; never `-force`) |
| Scratch area | `D:/Projects/RC_Project/vivado/scratch_t2/` (gitignored; batch validation, OOC, mocks, reports) |
| Part | `xc7z020clg484-1` |
| Top module / file | `top_t2` / `rtl/t2/top_t2.v`; ports `clk` (Y9), `btn_rst` (P16, LVCMOS18, active high), `led[7:0]` |
| Static instances | `U_RST` rst_sync · `U_UP` uptime · `U_CT` controller · `U_DC` dfx_decouple · `U_VIO` vio_t2 |
| RP instance / module | `U_RP` / `rp_t2` |
| Partition definition | `pd_t2` |
| Reconfigurable modules | `rm_int16` (`rtl/t2/rm/rm_int16.v`), `rm_int8` (`rm_int8.v`), `rm_int4` (`rm_int4.v`), plus greybox |
| Configurations | `cfg_int16`, `cfg_int8`, `cfg_int4`, `cfg_grey` |
| Implementation runs | `impl_1` → `cfg_int16` (parent) · `child_0_impl_1` → `cfg_int8` · `child_1_impl_1` → `cfg_int4` · `child_2_impl_1` → `cfg_grey` |
| Synthesis runs | `synth_1` (static) · `rm_int16_synth_1` · `rm_int8_synth_1` · `rm_int4_synth_1` · `vio_t2_synth_1` |
| Pblock | `pblock_U_RP` = `SLICE_X80Y50:SLICE_X103Y99`, `DSP48_X3Y20:DSP48_X4Y39`, `RAMB18_X4Y20:RAMB18_X4Y39`, `RAMB36_X4Y10:RAMB36_X4Y19`; `RESET_AFTER_RECONFIG true`; `SNAPPING_MODE ON` |
| VIO core | `vio_t2` (IP inside the project), 5 inputs / 6 outputs, input activity detectors off |
| `rm_id` | int16 `16` · int8 `08` · int4 `04` · greybox `00` · decoupled `FF` |
| LED badge (LD3..0) | int16 `1111` · int8 `0011` · int4 `0001` (blinking) · greybox / decoupled `0000` |
| Constraint files | `constraints/top_t2.xdc` (pins + clock) · `constraints/top_t2_pblock.xdc` (Pblock; target file; not used in synthesis) |
| Run-folder outputs | `top_t2.bit` · `U_RP_rm_int16_partial.bit` · `U_RP_rm_int8_partial.bit` · `U_RP_rm_int4_partial.bit` · `U_RP_greybox_partial.bit` · `top_t2_routed.dcp` |
| Collected bitstreams | `bitstreams/t2/t2_full_{int16,int8,int4,grey}.bit` · `t2_partial_{int16,int8,int4,grey}.bit` · `t2_full_int16.ltx` · `manifest.csv` |
| Board Tcl | `scripts/t2/hw_t2.tcl` (procs `t2_*`, §11.1) · `scripts/t2/hw_t2_mock.tcl` |

**VIO probes** (the RTL nets carry exactly these names, because the `.ltx` probe names are the net names):

| Port | Net | Width | Direction | Meaning |
|---|---|---|---|---|
| `probe_out0` | `vio_decouple` | 1 | laptop → chip | isolate the RP and hold the RM in reset |
| `probe_out1` | `vio_rm_rst` | 1 | laptop → chip | hold the RM in reset without decoupling |
| `probe_out2` | `vio_start` | 1 | laptop → chip | run (rising edge, gated) |
| `probe_out3` | `vio_sel` | 4 | laptop → chip | result index 4i + j |
| `probe_out4` | `vio_a` | 256 | laptop → chip | A, row-major int16; `A[i][j]` at `[16(4i+j) +: 16]` |
| `probe_out5` | `vio_b` | 256 | laptop → chip | B, same packing |
| `probe_in0` | `vio_result` | 32 | chip → laptop | C[sel] as int32, after the decoupler |
| `probe_in1` | `vio_rm_id` | 8 | chip → laptop | RM signature after the decoupler |
| `probe_in2` | `vio_uptime` | 32 | chip → laptop | static seconds counter |
| `probe_in3` | `vio_flags` | 4 | chip → laptop | `[0] done_flag  [1] ovf_s  [2] busy  [3] blocked` |
| `probe_in4` | `vio_runs` | 16 | chip → laptop | accepted runs since reset |

**Static internal names** (locked because benches force or peek them): `sys_rst_n`, `rm_rst_n`, `start_d`, `start_rise`, `start_ok`, `busy`, `blocked`, `runs`, `ct_west`, `ct_north`, `ct_clr`, `ct_done`, `west_q`, `north_q`, `clr_q`, `done_sr`, `done_rise`, `done_flag`, `result_s`, `ovf_s`, `rm_id_s`, `led_s`. Inside each RM: `acc_bus`.

---

## 5. Repo layout, .gitignore, cleanup policy

### 5.1 T2 additions (everything else is frozen)

```
rtl/t2/top_t2.v                    static top
rtl/t2/rm/rm_int16.v               module rp_t2 — int16, T0 pe/array, DSP
rtl/t2/rm/rm_int8.v                module rp_t2 — int8, LUT
rtl/t2/rm/rm_int4.v                module rp_t2 — int4, LUT
rtl/t2/rm/pe_lut.v                 LUT PE (use_dsp = "no"), parameterised DATA_W / ACC_W
rtl/t2/rm/array_lut.v              4×4 mesh of pe_lut (same geometry and bus layout as T0 array.v)
rtl/t2/rm/rm_common.v              lane_sat, rm_readout, rm_badge (shared by all RMs)
tb/t2/tb_rp_t2.v                   RP bench (one RM at a time)
tb/t2/tb_top_t2.v                  whole-design bench through the VIO stub
tb/t2/vio_t2_stub.v                simulation-only VIO model (never added to Vivado)
constraints/top_t2.xdc             pins + 100 MHz clock (copy of top_dfx.xdc)
constraints/top_t2_pblock.xdc      pblock_U_RP (the 8 Pblock lines of top_dfx_pblock.xdc)
python/golden_t2.py                precision-aware golden model (imports quant.py, golden.py)
python/gen_vectors_t2.py           writes sim/t2_vectors/
python/test_golden_t2.py           self-tests of the T2 golden model
sim/t2_vectors/<int16|int8|int4>/<case>/   vectors (committed)
sim/t2_build/                      Icarus outputs (ignored)
scripts/t2/t2_filesets.tcl         THE list of static files and per-RM files
scripts/t2/run_sims.py             all benches + negative tests
scripts/t2/ooc_check.tcl           OOC synthesis of each RM + gates
scripts/t2/create_project_t2.tcl   creates the DFX project (scratch or real)
scripts/t2/collect_bitstreams.py   run dirs → bitstreams/t2 + manifest (staleness guard)
scripts/t2/reports_t2.tcl          per-config reports, partition pins, pr_verify, build_summary.csv
scripts/t2/hw_t2.tcl               Hardware Manager procs
scripts/t2/hw_t2_mock.tcl          runs hw_t2.tcl against a simulated device
bitstreams/t2/                     collected bitstreams + manifest.csv
docs/t2/T2_PLAN.md                 this file
docs/t2/T2_RESULTS.md              every number, with its source
docs/t2/T2_BOARD_RUNBOOK.md        lab steps + fill-in sheet
docs/t2/reports/                   reports, CSVs, logs
docs/t2/img/                       checkpoint screenshots
docs/t2/ref/                       T1 journal excerpt + project facts (reference for the project script)
vivado/t2_dfx/                     the DFX project (ignored)
vivado/scratch_t2/                 scratch work (ignored)
```

### 5.2 .gitignore

Must cover (add only what is missing): `vivado/` (already), `sim/t2_build/`, `**/__pycache__/`, `.pytest_cache/`, `*.jou`, `*.str`, `.Xil/`. Do **not** ignore `docs/t2/reports/` or `sim/t2_vectors/`.

### 5.3 Cleanup policy (A1 task 2)

Order matters: **harvest first, delete second.** Vivado journals (`*.jou`) are the only record of the exact Tcl the T1 GUI issued; extract the DFX/VIO lines into `docs/t2/ref/t1_journal_excerpt.tcl` before anything is deleted (search `vivado/`, the repo root and `%APPDATA%/Xilinx/Vivado/`).

| Class | Paths | Action |
|---|---|---|
| Tool scratch | `vivado/.Xil/`, `.Xil/` at repo root | delete |
| Batch/GUI leftovers | `vivado/*.jou`, `vivado/*.log`, `vivado/*.str`, `vivado/*backup*`, `vivado/webtalk*`, `vivado/usage_statistics_webtalk.*`; the same patterns at repo root | delete (after harvest) |
| Regenerable sim output | `sim/t1_build/`, untracked `*.vvp` / `*.vcd` under `sim/` | delete |
| Python caches | `**/__pycache__/`, `.pytest_cache/` | delete |
| Vivado projects | `vivado/t1_dfx/`, every T0 project under `vivado/` | **never touch**; report size only |
| Everything else | `.venv/`, `bitstreams/`, `docs/`, `NOTE.txt`, any tracked file | **never touch** |

Delete only if the path is untracked or gitignored (`git ls-files` / `git check-ignore`). Print the candidate table (path, size, status) first, then delete, then report freed MB and free space on D:.

---

## 6. RTL specification

### 6.1 Coding rules (all T2 RTL)

- Verilog-2001; must pass `iverilog -g2005` with 0 warnings. No SystemVerilog.
- Synchronous, active-low resets (`rst_n`) with a defined reset value on every register.
- Signed arithmetic: every operand in a signed expression is signed; zero constants in `?:` are `$signed({W{1'b0}})` (T0 bug #1).
- Attributes on nets: declare the net, then `assign` (Icarus limitation, T1 bug #2). Module-level `(* use_dsp = "no" *)` on `pe_lut` is allowed and intended.
- No `#(...)` parameter overrides from `top_t2` into `U_RP`. Parameters may be passed *inside* an RM.
- RMs: fabric logic only (no IO buffers, BUFG, MMCM, VIO, ILA). Every RP output is driven directly by a flop inside the RM.
- No `initial` blocks in synthesisable RTL.

### 6.2 `top_t2` (static)

```verilog
module top_t2 #(
    parameter TICK_DIV = 100_000_000            // uptime: 1 s at 100 MHz; benches use 100
) (
    input  wire       clk,                       // Y9, 100 MHz
    input  wire       btn_rst,                   // P16 BTNC, active high, LVCMOS18
    output wire [7:0] led
);
```

Instances: `U_RST` (`rtl/t1/rst_sync.v`), `U_UP` (`rtl/t1/uptime.v`, `TICK_DIV` passed through), `U_CT` (`rtl/controller.v`, `a_bus = vio_a`, `b_bus = vio_b`, `start = start_ok`, `rst_n = sys_rst_n`), `U_VIO` (`vio_t2`), `U_RP` (`rp_t2`, no parameter overrides), `U_DC` (`rtl/t1/dfx_decouple.v`, `W = 45`, `SAFE = {32'h0000_0000, 1'b0, 8'hFF, 4'b0000}`, order `{result, ovf, rm_id, led_pat}`). Port names of the reused modules are taken from the files as they are (Claude Code reads them; the names here describe intent).

Behaviour, in RTL terms:

```verilog
// RM reset: decoupling also holds the RM in reset (T1 protocol)
always @(posedge clk) rm_rst_n <= sys_rst_n & ~vio_decouple & ~vio_rm_rst;

// start: edge detect, gate, account
always @(posedge clk) start_d <= sys_rst_n ? vio_start : 1'b0;
assign start_rise = vio_start & ~start_d;
assign start_ok   = start_rise & rm_rst_n & ~vio_decouple & ~busy;
// blocked: <= 0 on !sys_rst_n or start_ok; <= 1 on start_rise & ~start_ok; else hold
// runs:    <= 0 on !sys_rst_n; +1 on start_ok

// feed stage: static side of the registered boundary
always @(posedge clk)
    if (!sys_rst_n) begin west_q <= 0; north_q <= 0; clr_q <= 0; end
    else            begin west_q <= ct_west; north_q <= ct_north; clr_q <= ct_clr; end

// done: controller done delayed by the two boundary registers
always @(posedge clk) done_sr <= {done_sr[1:0], ct_done};   // 3 bits
assign done_rise = done_sr[1] & ~done_sr[2];                 // accumulators final here
// done_flag: <= 0 on !sys_rst_n | vio_decouple | !rm_rst_n | start_ok; <= 1 on done_rise; else hold
// busy:      <= 0 on !sys_rst_n | vio_decouple | !rm_rst_n | done_rise; <= 1 on start_ok; else hold

assign vio_flags = {blocked, busy, ovf_s, done_flag};
assign led       = {heartbeat, ~rm_rst_n, vio_decouple, done_flag, led_s};
```

If `controller.v`'s `done` is a level (Moore `DONE` state), `done_rise` still fires once per run because the controller leaves `DONE` on the next start. Claude Code confirms the controller's actual ports and `done` behaviour and logs them in §16.

### 6.3 `rp_t2` — the frozen RP port list (byte-identical in all three RM files)

```verilog
module rp_t2 #(
    parameter PRESCALE_W = 24                  // LED badge toggles every 2^PRESCALE_W cycles (~168 ms); benches override
) (
    input  wire        clk,
    input  wire        rst_n,                  // synchronous, active low (static rm_rst_n)
    input  wire        clr_acc,                // from the static feed register
    input  wire [63:0] west_bus,               // A lanes, int16, lane i at [16i +: 16] (static feed register)
    input  wire [63:0] north_bus,              // B lanes, int16, lane j at [16j +: 16] (static feed register)
    input  wire [3:0]  sel,                    // result index 4*i + j (row-major)
    output wire [31:0] result,                 // registered: C[sel] as int32
    output wire        ovf,                    // registered: C[sel] was clamped by sat32
    output wire [7:0]  rm_id,                  // registered, dont_touch: 16 / 08 / 04
    output wire [3:0]  led_pat                 // registered: badge pattern or 0000
);
```

### 6.4 Inside each RM

Common structure: input register stage → array → `rm_readout` → outputs; `rm_badge` alongside.

| | `rm_int16` | `rm_int8` | `rm_int4` |
|---|---|---|---|
| Input stage (registered, reset 0) | `west_bus`/`north_bus` 16-bit as-is, `clr_acc` | `lane_sat #(8)` per lane → 8-bit lanes, `clr_acc` | `lane_sat #(4)` → 4-bit lanes, `clr_acc` |
| Array | T0 `array #(.DATA_W(16), .ACC_W(48))` with T0 `pe` (both unchanged) | `array_lut #(.DATA_W(8), .ACC_W(18))` | `array_lut #(.DATA_W(4), .ACC_W(10))` |
| MAC | DSP48E1, accumulator in the P register | LUT multiplier + carry-chain adder | same |
| `acc_bus` | 16 × 48 = 768 bits | 16 × 18 = 288 | 16 × 10 = 160 |
| Readout | `rm_readout #(48)`: `sat32`, real `ovf` | `rm_readout #(18)`: sign-extend; `ovf` flop with D = 0 (dont_touch) | `rm_readout #(10)`: same |
| Badge | `rm_badge #(.ID(8'h16), .PAT(4'b1111))` | `#(.ID(8'h08), .PAT(4'b0011))` | `#(.ID(8'h04), .PAT(4'b0001))` |
| Expected DSP / BRAM | 16 / 0 | 0 / 0 | 0 / 0 |

`acc_bus` layout is T0's: PE(i,j) at `[ACC_W*(4i+j) +: ACC_W]`, so `sel = 4i + j` indexes it directly.

### 6.5 Shared RM submodules

```verilog
// rtl/t2/rm/pe_lut.v — T0 pe.v semantics, LUT-only
(* use_dsp = "no" *)
module pe_lut #(parameter DATA_W = 8, parameter ACC_W = 18) (
    input  wire                     clk, rst_n, clr_acc,
    input  wire signed [DATA_W-1:0] a_in, b_in,
    output reg  signed [DATA_W-1:0] a_out, b_out,   // registered relays, W bits wide
    output reg  signed [ACC_W-1:0]  acc             // acc <= clr_acc ? 0 : acc + a_in*b_in
);

// rtl/t2/rm/array_lut.v — T0 array.v geometry and bus layout, pe_lut inside
module array_lut #(parameter DATA_W = 8, parameter ACC_W = 18) (
    input  wire                  clk, rst_n, clr_acc,
    input  wire [4*DATA_W-1:0]   west_bus,          // lane i at [DATA_W*i +: DATA_W]
    input  wire [4*DATA_W-1:0]   north_bus,
    output wire [16*ACC_W-1:0]   acc_bus            // PE(i,j) at [ACC_W*(4i+j) +: ACC_W]
);

// rtl/t2/rm/rm_common.v
module lane_sat #(parameter OUT_W = 8) (            // combinational
    input  wire signed [15:0]      x,
    output wire signed [OUT_W-1:0] y                // clamp to [-2^(OUT_W-1), 2^(OUT_W-1)-1]
);
module rm_readout #(parameter ACC_W = 48) (
    input  wire                 clk, rst_n,
    input  wire [16*ACC_W-1:0]  acc_bus,
    input  wire [3:0]           sel,
    output reg  [31:0]          result,             // ACC_W > 32: sat32 (T0 loader.v semantics); else sign-extend
    output reg                  ovf                 // (* dont_touch = "true" *); 0 when ACC_W <= 32
);
module rm_badge #(parameter [7:0] ID = 8'h00, parameter [3:0] PAT = 4'b0000, parameter PRESCALE_W = 24) (
    input  wire       clk, rst_n,
    output wire [7:0] rm_id,                        // (* dont_touch = "true" *) register: 00 in reset, ID after
    output reg  [3:0] led_pat                       // toggles PAT <-> 0000 each prescaler wrap; 0000 in reset
);
```

`sat32` is re-implemented in `rm_readout` with exactly T0 `loader.v`'s semantics (clamp to `7FFFFFFF` / `80000000`); `loader.v` itself is not instantiated.

### 6.6 Checklist every RM must satisfy

1. Module name `rp_t2`; port list byte-identical to §6.3 (`run_sims.py` diffs the three files' port declarations).
2. Fabric only; no debug cores; no `initial`.
3. Every output driven by a flop inside the RM; constant-valued outputs (`rm_id`, int8/int4 `ovf`) are `dont_touch` flops.
4. Uses only the files listed for it in `scripts/t2/t2_filesets.tcl`.
5. DSP count in OOC synthesis: 16 (int16) or 0 (int8, int4).

### 6.7 Constraints

- `constraints/top_t2.xdc`: the content of `constraints/top_dfx.xdc` (clock Y9 + `create_clock -period 10.000`, `btn_rst` P16 LVCMOS18, `led[7:0]`), header comment updated. Same ports, same pins.
- `constraints/top_t2_pblock.xdc`: only the 8 Pblock lines from `top_dfx_pblock.xdc` (`create_pblock` … `SNAPPING_MODE ON`), no `dbg_hub` lines. In the project: `used_in_synthesis false`, `used_in_implementation true`, and it is the **target** constraints file. If a later GUI save writes `dbg_hub` lines into it, they stay (same as T1).

---

## 7. Golden model and test vectors

### 7.1 Semantics (what every RM must reproduce bit for bit)

For precision W ∈ {16, 8, 4} with ACC_W = 48 / 18 / 10:

1. Inputs `A16`, `B16`: 4×4 int16 (the RP's lanes).
2. `Aq = clamp_full(A16, W)`, `Bq = clamp_full(B16, W)`, where `clamp_full` clamps to [−2^(W−1), 2^(W−1)−1].
3. `C = Aq @ Bq` exactly (int64). Assert every element fits in signed ACC_W bits.
4. `c_out = sat32(C)`; `ovf = (c_out != C)` per element. Only int16 can overflow.

`golden_t2.py` reuses `quant.py` and `golden.py` (imports only; they are frozen). If `quant.saturate` / `clip_to_width` match `clamp_full` on a sweep, use them; if not (for example a symmetric ±127 clip), `golden_t2.py` uses its own `clamp_full` and the difference is logged in §16.

### 7.2 Files

- `python/golden_t2.py`: `PRECISIONS = {"int16": (16, 48, 0x16), "int8": (8, 18, 0x08), "int4": (4, 10, 0x04)}`; `clamp_full`, `rm_reference(A16, B16, prec)`, `pack_probe256(M)` / `unpack_probe256(s)`, writers for every file in §7.4. Feed schedule: `golden.feed_schedule` on the **raw** `A16`/`B16` (the RM clamps); optional trace: `golden.simulate_array` on `Aq`/`Bq`.
- `python/gen_vectors_t2.py`: writes `sim/t2_vectors/<prec>/<case>/` for 3 × 9; fixed seeds recorded in `meta.json`.
- `python/test_golden_t2.py`: self-tests (§7.6).

### 7.3 Cases

| Case | A16, B16 | Purpose | Discriminates precisions? |
|---|---|---|---|
| `identity` | A = I, B = random full int16 (seeded) | C = clamp(B): shows the input clamp directly | yes |
| `ones` | all 1 | sanity (every C = 4) | no |
| `zeros` | all 0 | nothing moves | no |
| `counting` | A[i][j] = 4i + j + 1, B = Aᵀ | hand-checkable; T0's board case | int4 only (values > 7) |
| `asym_small` | random in [−8, 7], asymmetric, seeded | transpose catcher; **identical results in all three precisions** (control) | no |
| `random_inrange` | random over each precision's own full range (incl. −2^(W−1)) | arithmetic proper | per-precision inputs |
| `random_full` | random full int16, same A/B for all precisions | clamping exercised on most elements | **yes** |
| `extremes_neg` | all −32768 | int16: sat32 + `ovf`; int8/int4: proves 18 / 10-bit accumulators | **yes** |
| `extremes_mix` | A all −32768, B all +32767 | negative saturation; min products | **yes** |

### 7.4 Files per case directory

| File | Content |
|---|---|
| `a.hex`, `b.hex` | 16 lines, 4 hex digits, int16 two's complement, row-major (raw lanes, before clamping) |
| `a_probe.hex`, `b_probe.hex` | 1 line, 64 hex digits = the exact VIO probe string: **A[3][3] first … A[0][0] last** (bit 255 is the leftmost digit) |
| `feed_west.hex`, `feed_north.hex` | the staircase in T0's format (raw int16 lanes) |
| `c_exact.hex` | 16 lines, ceil(ACC_W/4) hex digits, two's complement at ACC_W |
| `c_out.hex` | 16 lines, 8 hex digits (int32 after `sat32`) |
| `ovf.hex` | 16 lines, `0` / `1` |
| `meta.json` | prec, W, ACC_W, rm_id, case, seed, any_ovf, n_clamped_inputs |

### 7.5 Hand-checkable expectations (computed independently by the planner with numpy; the generated files are authoritative and A1 must confirm them)

| Case / element | int16 | int8 | int4 |
|---|---|---|---|
| `counting` C row-major | 30 70 110 150 / 70 174 278 382 / 110 278 446 614 / 150 382 614 846 | same as int16 | 30 66 70 70 / 66 159 175 175 / 70 175 196 196 / 70 175 196 196 |
| `counting` C[0][2] (`sel` 2) | 110 = `0000006E` | 110 = `0000006E` | 70 = `00000046` |
| `extremes_neg` every element | exact 4,294,967,296 → `7FFFFFFF`, ovf 1 | 65,536 = `00010000`, ovf 0 | 256 = `00000100`, ovf 0 |
| `extremes_mix` every element | exact −4,294,836,224 → `80000000`, ovf 1 | −65,024 = `FFFF0200`, ovf 0 | −224 = `FFFFFF20`, ovf 0 |

### 7.6 `test_golden_t2.py` must check

1. `clamp_full`: 200 → 127 and −200 → −128 at W = 8; 9 → 7 and −9 → −8 at W = 4; int16 unchanged across the full range.
2. Accumulator bounds: `extremes_neg` needs exactly 18 (int8) and 10 (int4) signed bits; 2W + 1 bits would overflow.
3. `asym_small` gives identical `c_out` in all three precisions; `random_full` differs between int16 and int8.
4. int16 regression: for every T0 case in `sim/vectors/`, `rm_reference(int16)` equals T0's `c_out`.
5. Probe packing: `unpack_probe256(pack_probe256(M)) == M`; the last 4 hex digits are A[0][0].
6. Hex two's-complement round trip at 4, 8, 10, 16, 18, 32 and 48 bits.
7. The §7.5 rows.

---

## 8. Verification before Vivado (Phase A1)

### 8.1 Benches

**`tb/t2/tb_rp_t2.v`** (the RP alone; `+define+PREC_INT16|PREC_INT8|PREC_INT4` selects expectations and vector directory; `run_sims.py` chooses the RM file; `PRESCALE_W` overridden to 4):
- during reset: `rm_id` 00, `result` 0, `ovf` 0, `led_pat` 0000; after release: `rm_id` = the precision's code;
- every case: drive `feed_west.hex`/`feed_north.hex` and `clr_acc` exactly as the static feed register would, then read all 16 results via `sel` and compare with `c_out.hex` and `ovf.hex`;
- results unchanged 20 cycles later;
- badge: `led_pat` alternates between PAT and 0000 exactly every 2^PRESCALE_W cycles, over 6 toggles.

**`tb/t2/tb_top_t2.v` + `tb/t2/vio_t2_stub.v`** (whole design; `TICK_DIV` = 100; `defparam` sets `U_RP.PRESCALE_W` = 4):
1. design runs with the button released; `vio_rm_id` = code after reset;
2. every case: load `vio_a`/`vio_b` **from `a_probe.hex`/`b_probe.hex`** (checks the packing end to end), pulse `vio_start`, wait for `done_flag`, read 16 results via `vio_sel` (≥ 3 cycles per read), compare `vio_result` and `vio_flags[1]` with the golden files;
3. print `CT_CYCLES` (start_ok → ct_done) and `CYCLES` (start_ok → done_flag) per case; they must be identical across every case and every RM;
4. decouple: `vio_result` 0, `vio_rm_id` FF, `ovf_s` 0, `led_s` 0000, `done_flag` 0, LD5 and LD6 on; `vio_uptime` keeps ticking while decoupled;
5. start while decoupled: `vio_runs` unchanged, `busy` stays 0, `blocked` = 1; same with `vio_rm_rst` = 1;
6. release: `rm_id` returns, `done_flag` stays 0 until a new run; re-run gives correct results and clears `blocked`;
7. heartbeat half-period = `TICK_DIV/2`; LD4 = `done_flag`; LD3..0 show the badge.

`vio_t2_stub.v` has the IP's exact port names (`clk`, `probe_in0..4`, `probe_out0..5`); the bench drives its outputs hierarchically. Compile with `iverilog -g2005 -s <bench>` so unused modules in `rm_common.v` are not elaborated as extra roots.

### 8.2 `scripts/t2/run_sims.py`

- Positive builds: `tb_rp_t2` × 3 RMs, `tb_top_t2` × 3 RMs → **ALL PASS**, 0 compiler warnings. Outputs in `sim/t2_build/`.
- Negative builds, each must FAIL:
  - **N1** `tb_rp_t2` expecting int8, compiled with `rm_int16.v`;
  - **N2** `tb_rp_t2` expecting int4, compiled with `rm_int8.v`;
  - **N3** `tb_top_t2 +define+NEG_UNGATED`: the bench does `force dut.start_ok = dut.start_rise;` → the start-gating checks must fail.
  → **NEGATIVE OK** only if all three fail, each for the expected reason.
- Port-list check: the `rp_t2` port declarations in the three RM files are identical after whitespace normalisation.
- File lists come from `scripts/t2/t2_filesets.tcl` (parsed), never duplicated.
- Writes `docs/t2/reports/sim_summary.txt` and `docs/t2/reports/sim_cycles.csv` (`rm,case,ct_cycles,cycles`).

### 8.3 `scripts/t2/ooc_check.tcl` (run from `vivado/scratch_t2/`)

For each RM: `read_verilog` its file list from `t2_filesets.tcl` → `synth_design -mode out_of_context -top rp_t2 -part xc7z020clg484-1` → `create_clock -period 10.000 [get_ports clk]` → `report_utilization` + `report_timing_summary` → `docs/t2/reports/ooc_<rm>_utilization.rpt`, `ooc_<rm>_timing.rpt`, and one row in `docs/t2/reports/ooc_summary.csv`. FF counts come from `report_utilization`, not from a `PRIMITIVE_GROUP` filter (T1 bug #3).

| Gate | `rm_int16` | `rm_int8` | `rm_int4` |
|---|---|---|---|
| DSP48E1 | = 16 | = 0 | = 0 |
| LUT | ≤ 2,200 | ≤ 2,200 | ≤ 2,200 |
| BRAM | 0 | 0 | 0 |
| Post-synth WNS @ 10 ns (estimate) | > 0 (warn < +1.5 ns) | > 0 (warn < +1.5 ns) | > 0 |

→ **OOC PASS** if every hard gate holds.

### 8.4 `scripts/t2/t2_filesets.tcl` and `scripts/t2/create_project_t2.tcl`

`t2_filesets.tcl` defines, once:
- `::T2_STATIC_FILES` = `rtl/t2/top_t2.v rtl/t1/rst_sync.v rtl/t1/uptime.v rtl/t1/dfx_decouple.v rtl/controller.v`
- `::T2_RM_FILES(rm_int16)` = `rtl/t2/rm/rm_int16.v rtl/array.v rtl/pe.v rtl/t2/rm/rm_common.v`
- `::T2_RM_FILES(rm_int8)` = `rtl/t2/rm/rm_int8.v rtl/t2/rm/array_lut.v rtl/t2/rm/pe_lut.v rtl/t2/rm/rm_common.v`
- `::T2_RM_FILES(rm_int4)` = `rtl/t2/rm/rm_int4.v rtl/t2/rm/array_lut.v rtl/t2/rm/pe_lut.v rtl/t2/rm/rm_common.v`
- constraint files, VIO probe widths, config → run map.

`create_project_t2.tcl`:
- **Usage:** in the GUI Tcl console, `source .../create_project_t2.tcl` creates the real project at `vivado/t2_dfx`. In batch: `-tclargs <project_dir> [synth]`. Refuses if the directory exists, except under `vivado/scratch_t2/`.
- **Derived from T1's ground truth:** the command forms come from `docs/t2/ref/t1_journal_excerpt.tcl` and `docs/t2/ref/t1_project_facts.md` (A1 task 1). The implementation flow string is read from the existing `impl_1` run, not hardcoded.
- **Steps** (each prints `[T2] step N ...`):
  1. `create_project t2_dfx <dir> -part xc7z020clg484-1`; target language Verilog.
  2. Add static files + `rm_int16` files to `sources_1` **by reference** (no copy); `top` = `top_t2`; `update_compile_order`.
  3. Add both XDCs; Pblock XDC: `used_in_synthesis false`, target constraints file.
  4. `create_ip ... vio ... -module_name vio_t2`; probe widths in 32/8/32/4/16 in, 1/1/1/4/256/256 out; input activity detectors off; `generate_target`; `create_ip_run`.
  5. Enable DFX (`PR_FLOW 1`); `create_partition_def pd_t2 -module rp_t2`; `rm_int16` from the existing sources (as T1 did for `rm_add`).
  6. `rm_int8`, `rm_int4`: `create_reconfig_module -top rp_t2` + `add_files -of_objects` with their file lists.
  7. **Assert filesets:** `sources_1` holds exactly the static files (+ the VIO IP); each RM fileset holds exactly its list. If `rm_int16`'s submodule files stayed in `sources_1`, move them into the RM fileset and log it in §16. If Vivado refuses a file shared by two RM filesets (`rm_common.v`, `pe_lut.v`, `array_lut.v`), **stop and report**; do not work around it.
  8. Configurations `cfg_int16` (U_RP:rm_int16), `cfg_int8`, `cfg_int4`, `cfg_grey` (greybox); `impl_1` → `cfg_int16`; create `child_0/1/2_impl_1` with parent `impl_1`.
  9. Print a summary: files per fileset, RMs, configurations, run → configuration map, constraint properties, VIO widths read back; then `T2 PROJECT READY`.
- With `synth` (scratch only): `launch_runs synth_1 rm_int16_synth_1 rm_int8_synth_1 rm_int4_synth_1 -jobs 4`, wait, assert all complete, print each run's LUT/FF/DSP, check `U_RP` is a black box in `synth_1`, then **SCRATCH OK**. Claude Code deletes the scratch project afterwards.
- Never launches implementation; never touches `vivado/t1_dfx`.

---

## 9. Vivado build walkthrough (Phase B) with checkpoints

**Rules for the whole phase:** don't edit any repo file the project uses while runs are active (they would go out of date). If Vivado asks to "update" or "reset" an out-of-date run, answer No and send a screenshot. Paths are typed exactly as written (forward slashes). Save every checkpoint screenshot to `docs/t2/img/` as `cp1_hierarchy.png`, `cp1_partitions.png`, `cp2_config_runs.png`, `cp3_synth_runs.png`, `cp4_pblock_drc.png`, `cp5_impl_runs.png`; they go into the T2 guide and the report.

### B0. Preconditions

- Claude Code reported **SCRATCH OK** and tagged `t2-rtl`; D: has ≥ 10 GB free (A1 reports it).
- Close any open Vivado. Don't open `t1_dfx`.

### B1. Create the project from the script (≈ 2 min)

1. Start Vivado 2022.2 from the Start menu. Don't open a project.
2. In the **Tcl Console** at the bottom, type:
   ```tcl
   cd D:/Projects/RC_Project/vivado
   source D:/Projects/RC_Project/scripts/t2/create_project_t2.tcl
   ```
3. **Green:** the console ends with `T2 PROJECT READY`, and the window title shows `t2_dfx`.

**CP1 — send two screenshots:**
- **Sources → Hierarchy**, `top_t2` expanded: `U_RST`, `U_UP`, `U_CT`, `U_VIO (vio_t2)`, `U_DC`, and `U_RP` with the partition icon; **Constraints** showing `top_t2.xdc` and `top_t2_pblock.xdc (target)`.
- **Sources → Partition Definitions** tab: `pd_t2` → `rm_int16`, `rm_int8`, `rm_int4`, each expanded to show its files.

### B2. Look at the DFX configuration (≈ 1 min, read-only)

**Tools → Dynamic Function eXchange Wizard** → Next through *Edit Reconfigurable Modules* (3 RMs) → *Edit Configurations* (`cfg_int16`, `cfg_int8`, `cfg_int4`, `cfg_grey`) → *Edit Configuration Runs* (`impl_1` parent = `cfg_int16`; `child_0_impl_1` = `cfg_int8`; `child_1_impl_1` = `cfg_int4`; `child_2_impl_1` = `cfg_grey`). **Cancel** at the end; change nothing.

**CP2 — screenshot** of the *Edit Configuration Runs* page.

### B3. Synthesise (≈ 5–10 min)

```tcl
launch_runs synth_1 rm_int16_synth_1 rm_int8_synth_1 rm_int4_synth_1 -jobs 4
```

Watch **Design Runs** (bottom panel). `vio_t2_synth_1` runs first as a dependency.
**Green:** `vio_t2_synth_1`, `rm_int16_synth_1`, `rm_int8_synth_1`, `rm_int4_synth_1`, `synth_1` all *synth_design Complete*, no red errors in Messages.

**CP3 — screenshot** of Design Runs with the LUT / FF / DSP columns visible. Expect the RM runs' DSP column to read 16 / 0 / 0 and to match `docs/t2/reports/ooc_summary.csv`.

### B4. Open the synthesised design, check the Pblock, run DRC (≈ 3 min)

1. Flow Navigator → **Synthesis → Open Synthesized Design**.
2. In the Tcl console:
   ```tcl
   get_property GRID_RANGES [get_pblocks pblock_U_RP]
   get_cells -of_objects [get_pblocks pblock_U_RP]
   report_drc -file D:/Projects/RC_Project/docs/t2/reports/drc_t2_synth.rpt
   ```
3. **Window → Device**: the Pblock rectangle sits in the right part of clock region X1Y1, as in T1.
4. **Green:** GRID_RANGES lists the four T1 ranges; the cell list is `U_RP`; DRC shows 0 errors (ZPS7-1 expected; send me any other warning).

**CP4 — screenshot** of the device view with `pblock_U_RP` selected, plus the DRC summary.

### B5. Implement all four configurations to bitstream (≈ 25–45 min, unattended)

```tcl
launch_runs impl_1 child_0_impl_1 child_1_impl_1 child_2_impl_1 -to_step write_bitstream -jobs 4
```

`impl_1` runs first (it implements the static region and locks it); the three children start when it finishes and run in parallel. **Now paste the A2 prompt (§14.2) into Claude Code.**

**Green:** all four rows read *write_bitstream Complete!*, and WNS, TNS, WHS, THS are ≥ 0 in every row.
**If a run fails:** don't reset it. Send a screenshot of the run row and of the Messages tab (errors only).

**CP5 — screenshot** of Design Runs with all four implementation rows and their timing columns. Then paste the Phase C prompt (§14.3). Keep Vivado open or close it; Phase C reads the run folders directly.

### 9.3 What the script did, in GUI terms (T1 did these by hand)

| Script step | The T1 GUI action it replaces | Where to see the result |
|---|---|---|
| `create_project` | File → Project → New | window title |
| `add_files` (no copy) | Add Sources, "Copy sources into project" unticked | Sources → Hierarchy |
| XDC properties | Source File Properties: "Synthesis" unticked, Set as Target | Constraints, `(target)` tag |
| `create_ip vio` + config | IP Catalog → VIO → Customize IP | Sources → IP Sources → `vio_t2` (double-click shows the probe widths) |
| `PR_FLOW 1` | Tools → Enable Dynamic Function eXchange | the DFX Wizard appears in Tools |
| `create_partition_def` + first RM | right-click `U_RP` → Create Partition Definition | Partition Definitions tab |
| `create_reconfig_module` + `add_files -of_objects` | Partition Definitions → Add Reconfigurable Module | RM file lists |
| `create_pr_configuration` | DFX Wizard → Edit Configurations | wizard page 2 |
| `create_run -pr_config`, `PR_CONFIGURATION` | DFX Wizard → Edit Configuration Runs | Design Runs tree |

---

## 10. Collect, report, verify (Phase C)

### 10.1 `scripts/t2/collect_bitstreams.py`

| Run | Config | Full → collected | Partial → collected |
|---|---|---|---|
| `impl_1` | `cfg_int16` | `top_t2.bit` → `t2_full_int16.bit` | `U_RP_rm_int16_partial.bit` → `t2_partial_int16.bit` |
| `child_0_impl_1` | `cfg_int8` | → `t2_full_int8.bit` | `U_RP_rm_int8_partial.bit` → `t2_partial_int8.bit` |
| `child_1_impl_1` | `cfg_int4` | → `t2_full_int4.bit` | `U_RP_rm_int4_partial.bit` → `t2_partial_int4.bit` |
| `child_2_impl_1` | `cfg_grey` | → `t2_full_grey.bit` | `U_RP_greybox_partial.bit` → `t2_partial_grey.bit` |

Plus `impl_1`'s full-design probes file → `t2_full_int16.ltx` (the VIO is static, so this one `.ltx` serves every configuration).

**Staleness guard** (abort on any failure): each run's log says `write_bitstream` completed; each child's routed checkpoint is newer than the parent's; each `.bit` is newer than its run's routed checkpoint; no file in `t2_filesets.tcl` or the two XDCs is newer than the oldest `.bit`. Warn (don't abort) if the four partials differ in size. `--dry-run` lists actions without copying.
**Manifest** `bitstreams/t2/manifest.csv`: `file,bytes,sha256,config,source_run,source_path,mtime`.

### 10.2 `scripts/t2/reports_t2.tcl` (batch, from `vivado/scratch_t2/`)

For each configuration, `open_checkpoint <run>/top_t2_routed.dcp` (exact name; not a `*_routed.dcp` glob, which also matches `U_RP_*_routed.dcp` and `top_t2_routed_bb.dcp`) and write to `docs/t2/reports/`:
`cfg_<x>_timing_summary.rpt`, `cfg_<x>_utilization.rpt`, `cfg_<x>_utilization_U_RP.rpt` (`-cells U_RP`), `cfg_<x>_utilization_pblock.rpt` (`-pblocks pblock_U_RP`), `cfg_<x>_utilization_hier.rpt`, `cfg_<x>_drc.rpt`.
Extract per configuration: WNS / TNS / WHS / THS; total LUT / FF / DSP / BRAM; U_RP LUT / FF / DSP / BRAM; Pblock LUT % and DSP %; the number of partition pins (state the method used); the worst setup path (start, end, logic levels, data-path delay, slack); the BUFG list.
Then `pr_verify -full_check -initial impl_1/top_t2_routed.dcp -additional {child_0, child_1, child_2 routed dcps} -file docs/t2/reports/pr_verify.rpt`.
Write `docs/t2/reports/build_summary.csv`, one row per configuration.

### 10.3 Phase C gates

| # | Gate | Source |
|---|---|---|
| C1 | WNS ≥ 0 and WHS ≥ 0 in all four configurations | `cfg_*_timing_summary.rpt` |
| C2 | 0 DRC errors in all four | `cfg_*_drc.rpt` |
| C3 | `pr_verify` PASS (all four compatible) | `pr_verify.rpt` |
| C4 | U_RP DSP = 16 / 0 / 0 / 0 | `cfg_*_utilization_U_RP.rpt` |
| C5 | Staleness guard PASS; manifest complete (9 files) | `manifest.csv` |
| C6 | Mock re-run against the collected files: MOCK TESTS PASS | mock log |
| C7 (warn) | In-project RM synthesis utilisation within ±5 % of OOC | `ooc_summary.csv` vs synth reports |

---

## 11. Board (Phase D): scripts, mock, session

### 11.1 `scripts/t2/hw_t2.tcl`

Only four wrappers touch Hardware Manager: `t2_hw_connect`, `t2_hw_program`, `t2_hw_write`, `t2_hw_read`. With `set ::T2_MOCK 1` they drive the simulated device instead. Every write that matters is forced (written even if the cached value looks equal), and every read is preceded by a VIO refresh (T1 lesson: cached tool state is not the hardware).

| Proc | Does | Prints / returns |
|---|---|---|
| `t2_connect` | open HW manager, server, target; select the xc7z020 | device, VIO count |
| `t2_program full\|partial <int16\|int8\|int4\|grey>` | program a file **listed in `bitstreams/t2/manifest.csv`** (anything else is refused); `PROBES.FILE` always `t2_full_int16.ltx`; refresh; re-commit outputs | ms |
| `t2_load <A16> <B16>` / `t2_load_case <case>` | pack 16 signed ints into the 64-digit probe string (A[3][3] first) and write `vio_a`/`vio_b`; `t2_load_case` uses `a_probe.hex`/`b_probe.hex` | probe strings |
| `t2_run` | `vio_start` 0 → 1 → 0 (forced); poll `vio_flags` until `done` (timeout); check `vio_runs` advanced by 1 | runs |
| `t2_read_c` | `vio_sel` 0..15 → 16 signed int32 + 16 ovf bits | lists |
| `t2_check <case>` | precision from `vio_rm_id`; load, run, read, compare with that precision's `c_out.hex` / `ovf.hex` | PASS/FAIL + mismatches |
| `t2_swap <prec>` | decouple 1 → program partial → decouple 1 then 0 → `rm_id` check | ms |
| `t2_swap_demo <prec>` | T1-style BEFORE / DECOUPLE / PROGRAM / RELEASE / AFTER with uptime continuity and one check case | verdict |
| `t2_block_test` | start while decoupled and while `vio_rm_rst` = 1 → `runs` unchanged, `blocked` = 1; after release a start → `runs` + 1, `blocked` = 0 | verdict |
| `t2_demo ?cases?` | same A/B per case run on int16 → int8 → int4 → int16; table of C per precision and difference from int16; swap ms | `docs/t2/reports/hw_demo_<ts>.csv` |
| `t2_full_contrast` | full program resets uptime | verdict |
| `t2_selftest ?rounds 3?` | 2 full programs (reset check), then rounds × {int8, int4, grey, int16} partials; each: continuity, `rm_id`, the board case set | `docs/t2/reports/hw_selftest_<ts>.csv`; `T2 SELFTEST PASS/FAIL` |

- **Board case set:** `counting`, `asym_small`, `random_full`, `extremes_neg`, `extremes_mix`. For grey: `rm_id` 00 and all results 0.
- **Continuity check (T1 lesson):** `uptime_after − uptime_before ≥ floor(program_ms / 1000)` for a partial; a full must reset uptime.
- **Hex handling (Tcl 8.5):** never pass a hex string to `expr`; compare `rm_id` as strings (`string equal -nocase`) or after `scan`; convert 32-bit results to signed explicitly (≥ 2^31 → subtract 2^32); build probe strings with `format %04X` on `(v & 0xFFFF)`.
- Self-test CSV columns: `step,op,file,bytes,ms,uptime_before,uptime_after,check,rm_id,cases_pass,cases_total,verdict`.
- Demo CSV columns: `case,prec,idx,c_hw,c_golden,match,ovf,swap_ms`.

### 11.2 `scripts/t2/hw_t2_mock.tcl` (run in Vivado's Tcl 8.5, from `vivado/scratch_t2/`)

**Simulated device:** tracks the loaded bitstream (full or partial, which precision); refuses a partial on a blank device (emulating `[Xicom 50-103]`); uptime from a virtual clock; program time = 0.13 s + 2.21 µs × bytes (T1 fit, virtual time, no real waiting), sizes from the manifest if present, else from disk, else 585,560 / 4,045,667; decouple semantics; start gating; `runs`, `blocked`, `done`; results computed by **its own Tcl implementation** of clamp + matmul + sat32, so a passing mock also proves the Tcl arithmetic and hex parsing agree with Python's `c_out.hex`.

**Positive suite:** every proc, including `t2_selftest 3`, `t2_demo`, `t2_block_test`, `t2_full_contrast`; every board case on every precision matches `c_out.hex`; `rm_id` values `08` and `04` pass through every path (the octal trap).

**Negative mocks** (each must make the named check FAIL):

| # | Injected fault | Must fail |
|---|---|---|
| NM1 | a partial resets uptime | `t2_selftest` continuity |
| NM2 | the device unpacks probe lanes in reverse order | `t2_check asym_small` |
| NM3 | the int8 RM does not clamp | `t2_check random_full` / `extremes_neg` on int8 |
| NM4 | a start is accepted while decoupled | `t2_block_test` |
| NM5 | partial requested before any full | `t2_program partial` raises the blank-device error |

→ prints `MOCK TESTS PASS` and `NEGATIVE MOCKS OK (5/5 failed as required)`.

### 11.3 The lab session (details and fill-in sheet in `docs/t2/T2_BOARD_RUNBOOK.md`)

Physical setup as in T1 (`docs/t1/T1_BOARD_RUNBOOK.md`): USB cable in **J17 (PROG)**, JTAG boot mode, power on. Hardware Manager → Open Target → Auto Connect, then in the Tcl console:

```tcl
source D:/Projects/RC_Project/scripts/t2/hw_t2.tcl
t2_connect
t2_program full int16          ;# ~9 s; rm_id 16; LD3..0 all four blinking; LD7 heartbeat
t2_check counting              ;# C[0][2] = 0000006E
t2_check extremes_neg          ;# 7FFFFFFF, ovf 1
t2_swap_demo int8              ;# rm_id 08; uptime +~2 s, not reset; LD1..0 blinking
t2_check counting              ;# same as int16
t2_check extremes_neg          ;# 00010000, ovf 0
t2_swap_demo int4              ;# rm_id 04; LD0 blinking
t2_check counting              ;# C[0][2] = 00000046 (70)
t2_block_test
t2_demo                        ;# film this: same A/B, three precisions
t2_swap_demo grey
t2_swap_demo int16
t2_full_contrast
t2_selftest 3                  ;# CSV → docs/t2/reports/
```

Film `t2_demo`: the badge goes `1111` → `0011` → `0001` while LD7 never stops.

---

## 12. Predictions and the measurement table

### 12.1 Predictions, recorded before the build (Phase C reports predicted / measured / held?)

| # | Prediction | Basis |
|---|---|---|
| P1 | Every partial = **585,560 B** | same Pblock as T1; a partial rewrites every Pblock frame (T1: add / mul / grey identical) |
| P2 | Every full = **4,045,667 B** | uncompressed full size depends on the device, not the design (T1: three identical fulls) |
| P3 | Every swap ≈ **1.42 s** over JTAG | 0.13 s + 2.21 µs × 585,560 B (T1 fit) |
| P4 | U_RP DSP = **16 / 0 / 0 / 0** | D3 |
| P5 | U_RP LUT: int8 > int4; int16's LUTs are mostly the readout mux and `sat32` | LUT multipliers scale ≈ with W² |
| P6 | Compute latency identical for all RMs and cases (T0 schedule + 2) | D6, D7 |
| P7 | Static LUT/FF higher than T1's 636 / 1,412 | the VIO grows from 34 to 519 output bits; 179 partition pins |
| P8 | WNS ≥ 0 at 100 MHz in all four; worst path either the controller selector → feed register (static) or an int8 multiply-accumulate inside a PE | D6 removes the T0/T1 DSP-input paths from the boundary |
| P9 | Board results bit-exact with `c_out.hex` in every precision | same files drive sims and board |

### 12.2 The T3 table (T2 fills every row except error)

| Metric | int16 | int8 | int4 | Source |
|---|---|---|---|---|
| DSP48E1 (U_RP) | | | | `cfg_*_utilization_U_RP.rpt` |
| LUT / FF (U_RP) | | | | same |
| Pblock LUT % / DSP % | | | | `cfg_*_utilization_pblock.rpt` |
| WNS / WHS (ns) | | | | `cfg_*_timing_summary.rpt` |
| Compute latency (cycles) | | | | `sim_cycles.csv` |
| Partial size (B) / swap time (ms, mean ± sd) | | | | `manifest.csv` / `hw_selftest_*.csv` |
| Mean / max error vs int16 after rescale | 0 | T3 | T3 | T3 host quantisation + board runs |

---

## 13. Gotchas

### 13.1 Carried from T1 (handoff §4.4)

| # | Rule |
|---|---|
| 1 | Enabling DFX is irreversible: new project `t2_dfx`; never touch `t1_dfx` or the T0 projects |
| 2 | All RMs declare `rp_t2`: only `rm_int16`'s files start in `sources_1`; the script asserts the filesets |
| 3 | Never "copy sources into project" |
| 4 | RMs are fabric only; debug cores stay static |
| 5 | Constant-driven partition pins → drive from `dont_touch` flops |
| 6 | `use_dsp` scope: on `pe_lut` only, and only `"no"` |
| 7 | Pblock reused verbatim; full clock-region height; BRAM by site-name range |
| 8 | A partial on a blank chip is refused: always program the matching full first |
| 9 | Always `t2_full_int16.ltx`, never a `U_RP_*_partial.ltx`; clear `PARTIAL_PROBES.FILES` if the GUI set it |
| 10 | Program only the collected, `pr_verify`-checked set in `bitstreams/t2/` |
| 11 | `[Labtools 27-1952]` after every program is harmless; scripts re-write outputs, then read |
| 12 | `rt-undefined` synthesis crash → delete `.Xil/`, re-run |
| 13 | Tcl 8.5: no `lmap`; no hex through `expr` |
| 14 | Hold slack was +0.039 ns in T1; watch WHS |
| 15 | `btn_rst` is active high, LVCMOS18; the design runs with the button released |

### 13.2 New in T2

| # | Gotcha | Rule |
|---|---|---|
| G16 | int8/int4 accumulator width | 18 / 10 bits (full-range −128 / −8), not 17 / 9 |
| G17 | Precision-blind vectors | small in-range values give identical results in every RM; negative tests and board checks must include `random_full` / `extremes_*` |
| G18 | 256-bit probe ordering | the probe string's first hex digit is bit 255 = A[3][3]'s top nibble; the last four digits are A[0][0] |
| G19 | Tcl hex | `rm_id` `08` / `04` through `expr` throw "invalid octal number"; 32-bit results need explicit sign conversion; build probe strings with `format`, never `expr` |
| G20 | int8/int4 constant outputs | `ovf` and the sign-extension bits of `result` are constants; `dont_touch` flops keep the pins flop-driven; LUT1 buffers on merged sign bits are expected (T1 saw 20) |
| G21 | RM file lists | one list in `t2_filesets.tcl`; a missing submodule only shows up in the RM synthesis run |
| G22 | Edits during a build | RTL, constraints and filesets are frozen from `t2-rtl` until `t2-built`; a build-blocking fix goes through re-sim, a commit, and a log entry in §16 |
| G23 | Concurrent Vivado | while the GUI builds, batch jobs run only from `vivado/scratch_t2/` (separate `.Xil/`) and only Tcl-only work |
| G24 | Wrong-tier bitstreams | `hw_t2.tcl` refuses any file not in `bitstreams/t2/manifest.csv` (a T1 partial on T2 static would corrupt the RP) |
| G25 | Stale results after a swap | `done_flag` is cleared by decouple; scripts always re-run before reading |
| G26 | Icarus extra roots | compile with `-s <bench>`; `rm_common.v` has modules some RMs don't use |
| G27 | Probe names | `.ltx` names are the RTL net names; keep `vio_*` nets named exactly as in §4 |

---

## 14. Claude Code prompts

Start **one new** Claude Code conversation for T2 (not the T1 one) and paste A1 there. A2 and C can continue in the same conversation; if Claude Code reports its context is getting full, open a fresh one, because every prompt is self-contained and points back to this plan.

### 14.1 Phase A1 (paste first)

```
T2 PHASE A1. You are the implementer for T2 of RC_Project (precision-scalable systolic matmul, DFX on a ZedBoard).
Planner = the Claude chat; orchestrator = me (Karthik); I do every Vivado GUI and board step.

SOURCE OF TRUTH: docs/t2/T2_PLAN.md (I placed it; untracked). Read it end to end before doing anything.
Then read what T2 reuses: rtl/pe.v, rtl/array.v, rtl/controller.v, rtl/loader.v (sat32 only), rtl/t1/*.v,
rtl/t1/rm/rm_mul.v, tb/t1/*, constraints/top_dfx.xdc, constraints/top_dfx_pblock.xdc, scripts/t1/*,
python/quant.py, python/golden.py, python/gen_vectors.py.
If the plan contradicts the repo (port names, function names, paths), STOP and tell me before writing code.

HARD RULES
1. Read-only (never edit, move or delete): rtl/*.v, rtl/t1/**, tb/ except the new tb/t2/, constraints/top.xdc,
   top_vio.xdc, top_dfx.xdc, top_dfx_pblock.xdc, scripts/t1/**, bitstreams/t1/**, docs/t0/**, docs/t1/**,
   every python/*.py that exists today, sim/vectors/**, NOTE.txt, .venv/, vivado/t1_dfx/** and every other
   existing project folder under vivado/.
2. Do NOT create vivado/t2_dfx: I create it in the GUI in Phase B. All Vivado validation runs in
   vivado/scratch_t2/ and is deleted when done. Never "copy sources into project". Never -force outside
   vivado/scratch_t2/.
3. Verilog-2001 that passes iverilog -g2005 with 0 warnings. Tcl must run in Vivado 2022.2's Tcl 8.5:
   no lmap, never pass a hex string through expr.
4. Every number you report comes from a log, report or CSV produced in this session. Never estimate a result.
5. Work on branch t2-precision only. Never push.

TASKS (plan sections in brackets)
0. Branch [§4]. Run git status, git branch -a, git log --oneline -3 main t1-dfx, git describe --tags main.
   Expect main == t1-onboard == 274c37f and t1-dfx already merged into main. If tracked files are modified,
   or main is not at t1-onboard, STOP and report. Otherwise: git switch main; git switch -c t2-precision.
1. Harvest T1 ground truth BEFORE any cleanup [§5.3, §8.4]:
   a) Find Vivado journals (*.jou, *backup*.jou) in vivado/, the repo root and %APPDATA%/Xilinx/Vivado/.
      Extract every line matching create_ip|CONFIG.C_|set_property -dict|PR_FLOW|create_partition_def|
      create_reconfig_module|-of_objects|create_pr_configuration|create_run|PR_CONFIGURATION|launch_runs|
      used_in_synthesis|target_constrs_file|create_pblock|resize_pblock into
      docs/t2/ref/t1_journal_excerpt.tcl, with a comment naming the source file above each block.
   b) From vivado/t1_dfx (read-only): the vio_dfx .xci CONFIG keys and values, and the .xpr's partition
      definition, RM, configuration and run entries (including the run FLOW string) into
      docs/t2/ref/t1_project_facts.md. If no journal survives, say so; the .xpr and .xci are then the reference.
2. Cleanup [§5.3]. Print the candidate table (path, size, tracked/ignored), delete only the safe classes and
   only untracked or ignored paths, then report: freed MB, free space on D:, and the size of each
   vivado/<project>/ (report only).
3. Skeleton + .gitignore [§5.1, §5.2] with .gitkeep in empty folders. Commit "t2: plan + skeleton".
4. Golden + vectors [§7]: python/golden_t2.py, gen_vectors_t2.py, test_golden_t2.py → sim/t2_vectors/.
   test_golden_t2.py must print ALL PASS.
5. Constraints [§6.7]: constraints/top_t2.xdc, constraints/top_t2_pblock.xdc.
6. RTL [§6]: rtl/t2/top_t2.v; rtl/t2/rm/rm_int16.v, rm_int8.v, rm_int4.v, pe_lut.v, array_lut.v, rm_common.v.
   Use the locked names in §4 exactly (VIO nets, static internal names, acc_bus).
7. scripts/t2/t2_filesets.tcl [§8.4]: the single list; run_sims.py, ooc_check.tcl and create_project_t2.tcl all read it.
8. Benches + runner [§8.1, §8.2]: tb/t2/tb_rp_t2.v, tb_top_t2.v, vio_t2_stub.v; scripts/t2/run_sims.py.
   Expect ALL PASS + NEGATIVE OK + identical port lists; writes docs/t2/reports/sim_summary.txt and sim_cycles.csv.
9. OOC [§8.3]: scripts/t2/ooc_check.tcl, run from vivado/scratch_t2/ → OOC PASS;
   writes docs/t2/reports/ooc_summary.csv, ooc_<rm>_utilization.rpt, ooc_<rm>_timing.rpt.
10. Project script [§8.4, §9.3]: scripts/t2/create_project_t2.tcl, built from the task-1 references.
    Validate in batch: -tclargs <repo>/vivado/scratch_t2/t2_dfx_check synth. Every assert must pass and it must
    print T2 PROJECT READY and SCRATCH OK. Save the console output to docs/t2/reports/scratch_validation.log,
    then delete vivado/scratch_t2/t2_dfx_check.
11. Plan sync: record every difference from the plan (actual controller/uptime/decoupler ports, quant.py
    semantics, Vivado command forms, anything else) in §16 of docs/t2/T2_PLAN.md and fix the affected section.
12. Commit, then tag t2-rtl. Don't push.

SHOW ME (one compact report; numbers copied from the files you produced):
- git: branch, HEAD short hash, tags on HEAD, git status --short
- cleanup: deleted paths, freed MB, D: free, size of each vivado/<project>/
- test_golden_t2 result line, plus the counting and extremes_neg c_out per precision next to plan §7.5
- run_sims: 6 positive builds PASS/FAIL, N1-N3 each FAILED-as-expected with its reason, the port-list check,
  CT_CYCLES and CYCLES per RM
- ooc_summary.csv as a table (LUT, FF, DSP, BRAM, est. WNS per RM) with each gate verdict
- scratch validation: fileset contents per RM, configuration -> run map, the four synth runs' status + LUT/FF/DSP,
  the U_RP black-box check
- the list of §16 deviations
```

### 14.2 Phase A2 (paste right after launching implementation in B5)

```
T2 PHASE A2. Runs while I build vivado/t2_dfx in the Vivado GUI. Source of truth: docs/t2/T2_PLAN.md (§10, §11, §13).

HARD RULES
1. All Phase A1 hard rules still apply.
2. A build is running on vivado/t2_dfx. Do not modify ANY file the project uses (rtl/**, constraints/**,
   scripts/t2/t2_filesets.tcl) and never open or touch vivado/t2_dfx. If you find an RTL or constraint bug,
   STOP and tell me instead of fixing it.
3. Vivado batch only from vivado/scratch_t2/ and only Tcl-only jobs (no synthesis); the GUI build needs the CPU.

TASKS
1. scripts/t2/collect_bitstreams.py [§10.1]: run map, names, staleness guard, manifest, --dry-run.
   Run only --dry-run now (it will report missing or unfinished runs; that is expected).
2. scripts/t2/reports_t2.tcl [§10.2]. Don't run it yet.
3. scripts/t2/hw_t2.tcl [§11.1], based on the patterns in scripts/t1/hw_t1.tcl (wrappers, forced writes,
   refresh before read, continuity rule, CSV logging).
4. scripts/t2/hw_t2_mock.tcl [§11.2]. Run it from vivado/scratch_t2/ in Vivado batch mode:
   expect MOCK TESTS PASS and NEGATIVE MOCKS OK (5/5 failed as required).
5. docs/t2/T2_BOARD_RUNBOOK.md [§11.3] with a fill-in sheet (expected value, observed value, OK) for every
   command; docs/t2/T2_RESULTS.md skeleton with the §12 tables, every cell "—" plus a source column.
6. Record deviations in §16 of the plan; commit "t2: phase A2 board + report scripts". No tag, no push.

SHOW ME: the mock summary (positive results; each negative mock's failing check and message), the proc list
with one line each, the collect --dry-run output, the §16 deviations.
```

### 14.3 Phase C (paste after CP5 is approved)

```
T2 PHASE C. All four implementation runs of vivado/t2_dfx finished (CP5 approved). Source of truth:
docs/t2/T2_PLAN.md (§10, §12).

HARD RULES: all Phase A1 hard rules; rtl/** and constraints/** stay untouched; vivado/t2_dfx is read-only
(opening its checkpoints in batch is fine).

TASKS
1. python scripts/t2/collect_bitstreams.py → bitstreams/t2/ + manifest.csv. The staleness guard must pass.
2. From vivado/scratch_t2/: Vivado batch -source ../../scripts/t2/reports_t2.tcl → docs/t2/reports/,
   including pr_verify.rpt and build_summary.csv.
3. Evaluate gates C1-C7 [§10.3]; print PASS/FAIL per gate with its source file.
4. Re-run hw_t2_mock.tcl against the collected files (real sizes from the manifest) → MOCK TESTS PASS.
5. Fill T2_RESULTS.md tables from the reports and CSVs (OOC, build, bitstreams, sim cycles). Add the
   predictions table from §12.1 with columns predicted / measured / held?
6. Commit "t2: built, collected, reported"; tag t2-built. Don't push.

SHOW ME: manifest as a table; build_summary.csv as a table; gates C1-C7; the pr_verify verdict line;
predictions vs measured; partition-pin count and method; worst setup path per configuration
(start -> end, logic levels, slack).
```

### 14.4 Phase D (paste after the lab session, with the console log attached)

```
T2 PHASE D. The board session is done. The Hardware Manager console log is pasted below; the self-test and
demo CSVs are in docs/t2/reports/. Source of truth: docs/t2/T2_PLAN.md (§1 item 8, §11, §12).

HARD RULES: all Phase A1 hard rules; never invent a value that is not in the log or a CSV; if the log is
truncated, say which values are missing.

TASKS
1. Parse the log and CSVs: per command, expected vs observed; swap times (mean ± sd, N) per precision;
   full program times; continuity on every partial; block-test result; demo table.
2. Check definition-of-done item 8; list anything not satisfied.
3. Fill the board tables and the swap-time row of the T3 table in T2_RESULTS.md; update README tier status.
4. Commit "t2: on silicon"; tag t2-onboard. Don't push.

SHOW ME: the per-command verdict table, swap-time stats, DoD item 8 verdict, the T3 table as filled so far.

<paste the console log here>
```

---

## 15. Today's timeline

| Clock | Who | Step | Green looks like |
|---|---|---|---|
| 0:00 | Karthik | place this file at `docs/t2/T2_PLAN.md`; open a **new** Claude Code conversation; paste §14.1 | Claude Code starts reading |
| 0:05–1:15 | Claude Code | Phase A1 | the SHOW ME report; send it to the chat |
| 1:15 | chat | review A1; go / no-go for the build | "go" |
| 1:20 | Karthik | B1–B2 (CP1, CP2) | `T2 PROJECT READY`; four configurations |
| 1:30 | Karthik | B3–B4 (CP3, CP4) | synth complete, DSP 16/0/0; Pblock in X1Y1; DRC 0 errors |
| 1:45 | Karthik | B5 launch; paste §14.2 | four runs queued; A2 running |
| 1:45–2:25 | Vivado / Claude Code | implementation / Phase A2 | four runs complete with WNS, WHS ≥ 0; MOCK TESTS PASS |
| 2:25 | Karthik | CP5; paste §14.3 | |
| 2:25–2:45 | Claude Code | Phase C | gates C1–C7 PASS; tag `t2-built` |
| next lab | Karthik | §11.3 session, then §14.4 | `T2 SELFTEST PASS`; tag `t2-onboard` |

The biggest uncertainty is how long A1 takes; the implementation time is second. Neither is a commitment.

---

## 16. As-built log

Claude Code appends one row per deviation and fixes the referenced section in the same commit.

| # | Phase | Plan said | Actual | Why | Sections updated |
|---|---|---|---|---|---|
| | | | | | |
