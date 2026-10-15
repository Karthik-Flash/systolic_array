# T2 Runbook — Phases B, C, D without Claude Code

Companion to `docs/t2/T2_PLAN.md` (still the source of truth; don't overwrite it, it holds Claude Code's §16 entries).
The four scripts this runbook uses were written in the planning chat and rehearsed against a simulated board (`hw_t2_mock.tcl`: MOCK TESTS PASS, NEGATIVE MOCKS OK 5/5) on Tcl 8.6. Vivado ships Tcl 8.5, so step C0 re-runs that rehearsal inside Vivado before any board time.

All shell commands are **PowerShell** (G28: Vivado batch jobs fail from Git Bash). `VIV` below means `C:\Xilinx\Vivado\2022.2\bin\vivado.bat`.

---

## 0. Install the scripts (5 min, before Phase B)

Copy into the repo, keeping these paths:

```
scripts/t2/hw_t2.tcl
scripts/t2/hw_t2_mock.tcl
scripts/t2/collect_bitstreams.py
scripts/t2/reports_t2.tcl
docs/t2/T2_BOARD_RUNBOOK.md
```

Then the offline rehearsal in Vivado's own Tcl 8.5 (no board, no project needed; safe to run while nothing is building):

```powershell
cd D:\Projects\RC_Project
mkdir vivado\scratch_t2 -Force
cd vivado\scratch_t2
C:\Xilinx\Vivado\2022.2\bin\vivado.bat -mode batch -nojournal -nolog -source ..\..\scripts\t2\hw_t2_mock.tcl
```

**Green:** the last two lines are `MOCK TESTS PASS` and `NEGATIVE MOCKS OK (5/5 failed as required)`, and every `MOCK  ok` line above them (17). This also checks every one of the 27 golden vector sets that Phase A1 generated against an independent Tcl implementation of the arithmetic. If anything fails, send me the first error block.

Commit:
```powershell
cd D:\Projects\RC_Project
git add scripts/t2 docs/t2/T2_BOARD_RUNBOOK.md
git commit -m "t2: board, collect and report scripts (planner-written); mock PASS"
```

---

## 1. Phase B — build in the GUI

Exactly plan §9 (B0–B5, checkpoints CP1–CP5). Expected at B1: a console note that `rm_common.v` is moved into `rm_int16` (A1 deviation; harmless). Expected at B3: RM synth DSP 16 / 0 / 0; `rm_int4_synth_1` ≈ 674 LUT (A1 scratch run).

While implementation runs (B5), don't touch `rtl/`, `constraints/`, or anything under `vivado/t2_dfx`.

**Green at the end of B:** four rows *write_bitstream Complete!*, WNS / TNS / WHS / THS ≥ 0 in every row (CP5).

---

## 2. Phase C — collect, report, re-rehearse (≈ 15 min)

```powershell
cd D:\Projects\RC_Project
.\.venv\Scripts\python.exe scripts\t2\collect_bitstreams.py --dry-run
```
**Green:** `STALENESS GUARD PASS`, nine files listed, partials all the same size, and the line `probes file top_t2.ltx: all 11 vio_* names present`. (If it says names are missing, that's the unconfirmed A1 item: still fine, `hw_t2.tcl` falls back to matching the VIO port, but tell me.)

```powershell
.\.venv\Scripts\python.exe scripts\t2\collect_bitstreams.py
cd vivado\scratch_t2
C:\Xilinx\Vivado\2022.2\bin\vivado.bat -mode batch -nojournal -source ..\..\scripts\t2\reports_t2.tcl
C:\Xilinx\Vivado\2022.2\bin\vivado.bat -mode batch -nojournal -nolog -source ..\..\scripts\t2\hw_t2_mock.tcl
```

**Green:**
- reports: for each configuration a line `WNS … WHS … U_RP LUT/FF/DSP …`; U_RP DSP 16 / 0 / 0 / 0; `DRC errors 0`; then `wrote build_summary.csv (4 configurations)` and `PR_VERIFY PASS`;
- mock again: `MOCK TESTS PASS` (now using the real file sizes from the manifest).

Gates C1–C7 (plan §10.3) are now readable straight from that console output and `docs/t2/reports/build_summary.csv`. Send me the console output and the CSV; I fill `T2_RESULTS.md` and the predictions table from them.

```powershell
cd D:\Projects\RC_Project
git add bitstreams/t2 docs/t2/reports
git commit -m "t2: built, collected, reported"
git tag t2-built
```

---

## 3. Phase D — the lab session

**Bring:** laptop with the repo at `t2-built`, ZedBoard, power supply, the USB cable for **J17 (PROG)**. Boot-mode jumpers as in T1 (`docs/t1/T1_BOARD_RUNBOOK.md`). Phone for filming.

1. Power on; the board has no design (DONE LED off is fine).
2. Vivado → **Open Hardware Manager** → **Open Target → Auto Connect**.
3. Tcl console, one command at a time; tick the sheet as you go:

| # | Command | Expected | Observed | OK |
|---|---|---|---|---|
| 1 | `source D:/Projects/RC_Project/scripts/t2/hw_t2.tcl` | `hw_t2.tcl loaded (mock=0)` | | |
| 2 | `t2_connect` | `connected (device xc7z020_1)` | | |
| 3 | `t2_program full int16` | ≈ 9 s; LD3..0 all blinking, LD7 heartbeat | | |
| 4 | `t2_status` | `rm_id 16 (int16)`, uptime counting | | |
| 5 | `t2_check counting` | PASS, C[0][2] = 0000006E | | |
| 6 | `t2_check extremes_neg` | PASS, 7FFFFFFF (ovf 1) | | |
| 7 | `t2_swap_demo int8` | rm_id ff during, 08 after; ≈ 1.4 s; uptime +1…3 s, NOT reset; LD1..0 blinking; VERDICT PASS | | |
| 8 | `t2_swap_demo int4` | rm_id 04; counting C[0][2] = 00000046 (70); LD0 blinking; PASS | | |
| 9 | `t2_block_test` | both starts refused, release start accepted; block test PASS | | |
| 10 | `t2_demo` | **film this.** Three tables; int4 column marked `*` where it differs; demo PASS | | |
| 11 | `t2_swap_demo grey` | rm_id 00; LD3..0 dark; LD7 still blinking; results 0 | | |
| 12 | `t2_swap_demo int16` | rm_id 16; PASS | | |
| 13 | `t2_full_contrast` | ≈ 9 s, everything stops incl. LD7; uptime reset; PASS | | |
| 14 | `t2_selftest 3` | 14 steps; **T2 SELFTEST PASS**; CSV in `docs/t2/reports/` (≈ 5 min) | | |

`[Labtools 27-1952] … OUTPUT_VALUE properties differ` after every program is expected (G11).

**Save:** the whole Tcl console (right-click → Copy all, paste into `docs/t2/reports/hw_session_<date>.log`), the two CSVs (`hw_demo_*`, `hw_selftest_*`), the video. Commit, tag `t2-onboard`, send me the log and CSVs.

### If something goes wrong on the board

| Symptom | Do this |
|---|---|
| `probe 'vio_x': 0 matches. Probes on the core: …` | Send me that list. Workaround now: `set ::T2_ALIAS(vio_x) <actual_name>` for each unmatched probe (it survives reprogramming), then retry. |
| `no VIO core` | A full bitstream isn't loaded, or the .ltx wasn't applied: `t2_program full int16` |
| `[Xicom 50-103] Static bitstream must first be programmed` | You programmed a partial onto a blank chip: `t2_program full int16` first |
| `run NOT accepted (runs a -> a)` | Check `t2_status`: decoupled or blocked? `t2_hw_write vio_decouple 0; t2_hw_write vio_rm_rst 0` |
| a check FAILs with mismatches | Don't retry blindly: copy the mismatch lines and `t2_status`, then do the rest of the sheet |
| the script misbehaves entirely | Manual fallback below |

**Manual fallback (VIO dashboard, no script).** Program `bitstreams/t2/t2_full_int16.bit` with probes file `bitstreams/t2/t2_full_int16.ltx` (Program Device dialog). In the `hw_vio_1` dashboard add all probes, set radix hex, then:
- `vio_a` = `0010000F000E000D000C000B000A000900080007000600050004000300020001`
- `vio_b` = `0010000C00080004000F000B00070003000E000A00060002000D000900050001`
- toggle `vio_start` 0 → 1 → 0; `vio_flags` bit 0 = 1; `vio_sel` = 2 → `vio_result` = `0000006E` (int16 and int8) or `00000046` (int4).
- swap: `vio_decouple` = 1 → Program Device with `t2_partial_int8.bit` (probes file still `t2_full_int16.ltx`) → `vio_decouple` = 0 → `vio_rm_id` = 08 → toggle `vio_start` again → read.

(These two strings are the counting case in the plan's packing: A[3][3] first. Confirm they equal your repo's `sim/t2_vectors/int16/counting/a_probe.hex` / `b_probe.hex`, ignoring case.)
