# T2 Lab Playbook — Phase D (board session)

**Status: Phases A1, B, C and D are all done.** Phase D ran on 2026-10-22 (tag `t2-onboard`): 23 programs, 14/14 self-test steps, 0 failures. Sections A–E are the playbook as it was used (reusable for the next demo session); **section F is the record of what that session actually measured.** Source of truth for names and expectations is still `docs/t2/T2_PLAN.md`.

All shell commands are **PowerShell** (not Git Bash). Nothing in the lab needs Copilot or Claude Code.

---

## A. At home, before the lab (≈ 30 min)

1. Repo on branch `t2-precision`, tag `t2-lab-ready` pushed, `git status --short` empty.
2. Run the mock once more in Vivado (30 s): last lines must be `MOCK TESTS PASS` and `NEGATIVE MOCKS OK (5/5 failed as required)`.
3. Windows: power plan set to **never sleep**, charger packed. Close browsers, other Vivado windows, and any other tool that can hold the JTAG cable (xsdb, Vitis, hw_server).
4. Pack: laptop + charger, ZedBoard + its power supply, the micro-USB cable for **J17 (PROG)**, a phone for video, a USB stick with a zip of the repo at `t2-lab-ready` (fallback if the laptop dies), this playbook (printed or on the phone).
5. Make the log folder: `mkdir D:\Projects\RC_Project\vivado\lab_t2 -Force`.

## B. At the bench, pre-flight (5 min)

| # | Check | OK |
|---|---|---|
| 1 | Boot-mode jumpers set to **JTAG exactly as in the T1 session** (see `docs/t1/T1_BOARD_RUNBOOK.md`) | |
| 2 | USB cable in **J17 (PROG)**, board powered, power LED on, DONE LED off (blank chip) | |
| 3 | No other Vivado / hw_server running (Task Manager) | |
| 4 | Launch Vivado **from PowerShell so the whole session is logged to a file** (the T1 log was lost to copy-paste truncation) | |

```powershell
cd D:\Projects\RC_Project\vivado\lab_t2
C:\Xilinx\Vivado\2022.2\bin\vivado.bat -mode gui -log lab_t2.log -journal lab_t2.jou
```

5. Welcome screen → **Open Hardware Manager** → **Open Target → Auto Connect**; the `xc7z020_1` device appears (no design loaded yet).

## C. The session (≈ 45–60 min with filming)

In the Hardware Manager **Tcl Console**, one command at a time, fill the sheet as you go. Don't type the next command before the previous one finished.

| # | Command | Expected | Observed | OK |
|---|---|---|---|---|
| 1 | `source D:/Projects/RC_Project/scripts/t2/hw_t2.tcl` | `hw_t2.tcl loaded (mock=0)` | | |
| 2 | `t2_connect` | `connected (device xc7z020_1; JTAG clock N Hz)`; **write N down** | N = | |
| 3 | `t2_program full int16` | ≈ 9 s; startup status HIGH; DONE LED on; LD3..0 all four blinking together; LD7 heartbeat | ms = | |
| 4 | `t2_probes` | `all 11 resolved` | | |
| 5 | `t2_status` | `rm_id 16 (int16)`, uptime counting, `runs 0` | | |
| 6 | `t2_check ones` | PASS, `C[0][2] = 00000004` (simplest smoke test) | | |
| 7 | `t2_check_all` | `ALL CASES on int16: 9/9 PASS`; counting `C[0][2] = 0000006E`; extremes_neg `7FFFFFFF` | | |
| 8 | `t2_swap_demo int8` | rm_id `ff` during, `08` after; ≈ 1.4 s; uptime +1…3 s, **not reset**; LD1..0 blinking; VERDICT PASS | ms = | |
| 9 | `t2_check_all` | `ALL CASES on int8: 9/9 PASS`; counting `C[0][2] = 0000006E`; extremes_neg `00010000` | | |
| 10 | `t2_swap_demo int4` | rm_id `04`; only LD0 blinking; VERDICT PASS | ms = | |
| 11 | `t2_check_all` | `ALL CASES on int4: 9/9 PASS`; counting `C[0][2] = 00000046`; extremes_neg `00000100` | | |
| 12 | `t2_block_test` | start refused while decoupled and while `rm_rst`; accepted after release; `block test PASS` | | |
| 13 | `t2_demo` | **film this.** Three tables; int4 column has `*` where it differs; `demo PASS` | | |
| 14 | `t2_swap_demo grey` | rm_id `00`; LD3..0 dark, LD7 still blinking; results 0 | | |
| 15 | `t2_swap_demo int16` | rm_id `16`; PASS | | |
| 16 | `t2_full_contrast` | ≈ 9 s, everything stops incl. LD7, uptime resets; PASS | | |
| 17 | `t2_selftest 3` | 14 steps; `T2 SELFTEST PASS`; CSV path printed (**8–15 min, my estimate since JTAG speed is unmeasured; do not interrupt**) | | |

`[Labtools 27-1952] … OUTPUT_VALUE properties differ` after every program is expected and harmless.

**Film** (phone, 3 clips): (a) the board during `t2_demo` with LD3..0 and LD7 both in frame: badge `1111` → `0011` → `0001` while LD7 never stops; (b) the swap moment of `t2_swap_demo int8` (LD5/LD6 light, LD3..0 dark, come back as `0011`); (c) the Tcl console showing `ALL CASES … 9/9 PASS` for each precision.

## D. If something fails: diagnostic ladder (don't improvise, don't reprogram blindly)

| Symptom | Meaning | Do |
|---|---|---|
| `t2_probes` shows `MISSING vio_x` | `.ltx` names differ from the RTL nets | the console printed the real names: `set ::T2_ALIAS(vio_x) <real_name>` for each, then `t2_probes` again |
| `no VIO core` | no full T2 bitstream loaded, or `.ltx` not applied | `t2_program full int16` |
| `[Xicom 50-103]` on a partial | partial on a blank/other-design chip | `t2_program full int16` first |
| `run NOT accepted` | decoupled, reset held, or blocked | `t2_status`; then `t2_hw_write vio_decouple 0; t2_hw_write vio_rm_rst 0` |
| a case FAILs | read the `got … expected …` lines | go **down** the ladder on the same RM: `t2_check zeros` → `ones` → `identity` → `counting` → `asym_small`. `zeros`/`ones` fail = control path or readout; `identity` fails but `ones` passes = lane/probe order; only `random_full`/`extremes_*` fail = clamp or saturation; fails on one precision only = that RM |
| everything fails after a swap but passed before | stale VIO cache after the partial | `t2_hw_write vio_decouple 1; t2_hw_write vio_decouple 0`, re-run |
| script misbehaves entirely | | manual fallback below |
| board does not enumerate | | re-seat J17, check power switch and boot jumpers, close other Vivado instances, Open Target → Auto Connect again |

Send me the **first** failing block (the command, its output, and `t2_status`) before trying anything else.

**Manual fallback (VIO dashboard, no script).** Program `bitstreams/t2/t2_full_int16.bit` with probes file `bitstreams/t2/t2_full_int16.ltx` (Program Device dialog). In the `hw_vio_1` dashboard add all probes, radix hex, then:
- `vio_a` = `0010000F000E000D000C000B000A000900080007000600050004000300020001`
- `vio_b` = `0010000C00080004000F000B00070003000E000A00060002000D000900050001`
- toggle `vio_start` 0 → 1 → 0; `vio_flags` bit 0 = 1; `vio_sel` = 2 → `vio_result` = `0000006E` (int16, int8) or `00000046` (int4).
- swap: `vio_decouple` = 1 → Program Device with `t2_partial_int8.bit` (probes file stays `t2_full_int16.ltx`) → `vio_decouple` = 0 → `vio_rm_id` = 08 → start again → read.

(These are the `counting` probe strings; confirm they equal `sim/t2_vectors/int16/counting/a_probe.hex` / `b_probe.hex`, ignoring case.)

## E. Before you leave the bench: save everything

```powershell
cd D:\Projects\RC_Project
copy vivado\lab_t2\lab_t2.log docs\t2\reports\hw_session_$(Get-Date -Format yyyyMMdd).log
dir docs\t2\reports\hw_demo_*.csv, docs\t2\reports\hw_selftest_*.csv
```

Also: in the Tcl console right-click → **Copy All** → paste into a text file as a backup of the log; fill in the observed column above (a photo of the sheet is enough); copy the phone videos to the laptop; note the **JTAG clock N** from row 2 and the date.

**Done for the 2026-10-22 session:** log, CSVs and sheet were saved under `docs/t2/reports/` and the work was tagged `t2-onboard`. For a repeat or demo session, reuse sections A–D unchanged.

---

## F. Session record — 2026-10-22

Sources (all in `docs/t2/reports/`): `hw_session_20261022.log` (Vivado log, 855 lines), `hw_demo_20261022_134038.csv`, `hw_selftest_20261022_134926.csv`. Board: ZedBoard, xc7z020, Digilent cable `210248685158`, **JTAG clock 15,000,000 Hz** (printed by `t2_connect`).

### F.1 The sheet, as observed

| # | Command | Observed | OK |
|---|---|---|---|
| 1 | `source …/hw_t2.tcl` | `hw_t2.tcl loaded (mock=0)` | yes |
| 2 | `t2_connect` | `connected (device xc7z020_1; JTAG clock 15000000 Hz)`; N = 15,000,000 | yes |
| 3 | `t2_program full int16` | 2,537 ms; startup status HIGH; 1 VIO core found | yes |
| 4 | `t2_probes` | all 11 probes resolved by name (widths 1/1/1/4/256/256 out, 32/8/32/4/16 in) | yes |
| 5 | `t2_status` | `rm_id 16 (int16)`, uptime 126 s, runs 0, result 00000000 | yes |
| 6 | `t2_check ones` | PASS, `C[0][2] = 00000004` | yes |
| 7 | `t2_check_all` (int16) | 9/9 PASS; counting `0000006E`; extremes_neg `7FFFFFFF` | yes |
| 8 | `t2_swap_demo int8` | rm_id `ff` during, `08` after; 431 ms; uptime 330 → 331 s (not reset); VERDICT PASS | yes |
| 9 | `t2_check_all` (int8) | 9/9 PASS; counting `0000006E`; extremes_neg `00010000`; extremes_mix `FFFF0200` | yes |
| 10 | `t2_swap_demo int4` | **not run** (int4 swaps are covered by the demo and the self-test, rows 13 and 17) | — |
| 11 | `t2_check_all` (int4) | **not run** (see F.4) | — |
| 12 | `t2_block_test` | start refused while decoupled (runs 21 → 21, blocked 1) and while `vio_rm_rst` held (21 → 21, blocked 1); accepted after release, blocked cleared; PASS | yes |
| 13 | `t2_demo` | PASS; 144 rows, 0 mismatches; swaps int8 417 ms, int4 416 ms | yes |
| 14 | `t2_swap_demo grey` | rm_id `00`; 418 ms; uptime 689 → 690 s; PASS | yes |
| 15 | `t2_swap_demo int16` | rm_id `16`; 423 ms; uptime 770 → 771 s; PASS | yes |
| 16 | `t2_full_contrast` | 2,492 ms; uptime 1006 → 0 s (reset, as expected for a full program); PASS | yes |
| 17 | `t2_selftest 3` | `T2 SELFTEST PASS`; 14/14 steps; 58/58 case checks | yes |

LED behaviour (badge `1111` / `0011` / `0001`, LD7 heartbeat, LD5/LD6 during a swap) is not in the log. Record the photo or video file names here: ______________

### F.2 Totals

- 23 programs in the session: 19 partial, 4 full. No failed program, no error line in the log. The only warnings are the expected `[Labtools 27-1952]` after full programs.
- Self-test: 2 full programs (second one resets uptime 3 → 0), then 3 rounds × {int8, int4, grey, int16}. Partial-phase uptime ran 2 → 29 s without ever going backwards.

### F.3 Swap and program times (self-test CSV, N = 12 partials, 2 fulls)

| Operation | Bytes | N | Mean (ms) | Min – max (ms) |
|---|---|---|---|---|
| Partial, all four RMs | 585,559 | 12 | 429.3 (sd 29.1) | 411 – 518 |
| Partial int8 / int4 / grey / int16 | 585,559 | 3 each | 452.3 / 433.0 / 417.3 / 414.7 | 418–518 / 427–436 / 415–421 / 411–419 |
| Full | 4,045,666 | 2 | 2,500.5 | 2,497 – 2,504 |

The int8 mean includes one 518 ms outlier (step 11). Per-precision differences are within scatter; all partials are the same size, so swap time does not depend on precision. Effective rate: 10.9 Mbit/s (partial), 12.9 Mbit/s (full), against a 15 Mbit/s raw clock. Two-point fit: 0.599 µs/byte + 0.079 s (T1: 2.21 µs/byte + 0.13 s at an unrecorded, slower clock).

### F.4 Predictions and limits

| Item | Predicted | Measured | Verdict |
|---|---|---|---|
| P1 partial size | 585,560 B | 585,559 B | within 1 B (header string is probably 1 char shorter: `top_t2` vs `top_dfx`; unconfirmed) |
| P2 full size | 4,045,667 B | 4,045,666 B | within 1 B, same reason |
| P3 swap time | ≈ 1.42 s | 0.429 s mean | **not held**: this session's JTAG clock was 15 MHz, T1's was not recorded (effective 3.25 Mbit/s then) |
| P9 bit-exact on silicon | all RMs | int16 9/9, int8 9/9, int4 5 case types × 3 rounds + 3 in the demo; 144/144 demo elements | held |

Limits to state honestly:
- int4 never got the 9-case sweep on the board. Not run on int4: `identity`, `ones`, `zeros`, `random_inrange` (all pass in simulation).
- Rows 10–11 were skipped for the same reason; the self-test still checked int4 `rm_id`, continuity and 5 case types in steps 4, 8, 12.
- LED observations are not in the log.
- Continuity check: with programs under 1 s the rule `after − before ≥ floor(ms/1000)` reduces to "uptime did not go backwards"; the evidence of continuity is the monotonic 2 → 29 s sequence.

### F.5 Next session

A demo-only session needs sections A–D (about 30 min). Optional add-ons: run rows 10–11 to close the int4 gap, and photograph the LEDs for each precision.

