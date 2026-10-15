# T2 Lab Playbook — Phase D (board session)

Status when this was written: Phases A1, B, C are **done** (tag `t2-built`: 4 configurations routed, WNS/WHS ≥ 0, DRC 0, `pr_verify` PASS, `BUNDLE OK`, mock PASS). This file covers only what remains: the lab. Source of truth for names and expectations is still `docs/t2/T2_PLAN.md`.

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

**Do not edit or reset anything else. Don't tag yet.** Send me: the log, the two CSVs, the sheet, and any failing block. I write the final T2 guide from them, then we merge to `main` and tag `t2-onboard`.
