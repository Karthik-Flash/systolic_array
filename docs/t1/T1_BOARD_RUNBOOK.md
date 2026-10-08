# T1 Board Runbook — Session 2 (partial swaps)

Goal: prove that a partial bitstream swaps `U_RP` over JTAG **while the static region keeps running**: LD7 never pauses and `vio_uptime` keeps counting. Expected time: about 10 minutes. Spec: [T1_PLAN.md](T1_PLAN.md) §8; results go into [T1_RESULTS.md](T1_RESULTS.md) Tables C and D.

## a. Setup

1. ZedBoard: power on, JTAG USB on **J17**, boot jumpers in JTAG mode (as in T0 and session 1). Nothing else attached.
2. Vivado 2022.2 → Tcl console. You don't need to open Hardware Manager first; `t1_connect` does it.
3. Bitstreams are already in `D:/Projects/RC_Project/bitstreams/t1/` (tag `t1-built`; check with `manifest.csv`). Do not rebuild anything.
4. Phone ready to film the LEDs (step c). Pen for the sheet (step d).

## b. Command sequence (paste one line at a time)

```tcl
source D:/Projects/RC_Project/scripts/t1/hw_t1.tcl
t1_connect
t1_program full add      ;# ~9 s. LD7 blinks, LD3..0 count, rm_id A1. Wait ~10 s so uptime climbs.
t1_swap_demo mul         ;# FILM THIS. Expect rm_id B2, y 0000_000C, uptime +N s, VERDICT: PASS
t1_swap_demo grey        ;# rm_id 00, y 0000_0000, LD3..0 dark, LD6 off (greybox, not reset)
t1_swap_demo add         ;# rm_id A1, y 0000_0007, LD3..0 counting again
t1_full_contrast         ;# full program: uptime drops to ~0 (expected). This is what a partial must NOT do
t1_selftest              ;# ~2-3 min: 3 full + 15 partial swaps, all vectors, CSV -> docs/t1/reports/
```

Each `t1_swap_demo` prints one block:
```
BEFORE  : rm_id A1  y 0000_0007  uptime 142 s
DECOUPLE -> rm_id FF  y 0000_0000
PROGRAM  t1_partial_mul.bit (585,560 B) ... 1830 ms
RELEASE  -> rm_id B2  y 0000_000C
AFTER   : uptime 146 s   (+4 s across the swap; static NOT reset)   VERDICT: PASS
```
"Static NOT reset" means uptime rose by at least the whole seconds the program took. A partial that restarted the static region would print `static WAS RESET` and `FAIL`.

## c. What to film

- Phone on the LED row (LD0–LD7) during **`t1_swap_demo mul`**, from Enter until the AFTER line prints. It should show:
  - **LD7 heartbeat never pauses** (1 Hz: 0.5 s on, 0.5 s off).
  - LD5 and LD6 turn on at DECOUPLE and off at RELEASE.
  - LD3..0 go dark at DECOUPLE, then show a **walking one** (mul) instead of the binary count (add).
- Keep the Tcl console in frame or screenshot it straight after, so the video and the uptime numbers match.
- Optional contrast clip: `t1_full_contrast`. LD7 stops briefly and LD3..0 restart while the whole chip is reprogrammed.

## d. Fill-in sheet

| Step | uptime before (s) | uptime after (s) | program ms | rm_id after | y after (a=3, b=4) | LD3..0 pattern | LD7 paused? | VERDICT |
|---|---|---|---|---|---|---|---|---|
| `t1_program full add` | — | | | A1 | 0000_0007 | binary count | — | — |
| `t1_swap_demo mul` | | | | B2 | 0000_000C | walking one | | |
| `t1_swap_demo grey` | | | | 00 | 0000_0000 | dark | | |
| `t1_swap_demo add` | | | | A1 | 0000_0007 | binary count | | |
| `t1_full_contrast` | | (~0) | | A1 | — | restarts | yes (expected) | |
| `t1_selftest` | — | — | full / add / mul / grey mean ± sd: | — | — | — | — | PASS / FAIL |

Selftest CSV file name: `docs/t1/reports/hw_selftest_________________.csv`

## e. If something goes wrong

| Symptom | Fix |
|---|---|
| `VIO probe 'uptime' not found (patterns: ...). Probes: ...` | Run `t1_probes`, find the real name, then in the console: `dict set ::t1_probe_pat uptime {*real_name*}` (same for `y`, `rm_id`, ...). Re-run the command. Afterwards, add the pattern to `t1_probe_pat` in `hw_t1.tcl`. |
| `xc7z020_1 not found in the JTAG chain` | Check J17 cable and power; `close_hw_target; t1_connect`. |
| `rm_id` stuck at `FF` | Decoupler still on: `t1_set decouple 0`. |
| `rm_id` `00` but not greybox, LD6 on | RM held in reset: `t1_set rm_rst 0`. |
| Partial fails to program / design dead after partial | Device didn't have the matching full: `t1_program full add`, then retry the swap. |
| Values look stale | `refresh_hw_device [t1_dev]`, then re-read. |

Dry run without the board (checks the script, not the silicon): from `vivado/`, `C:/Xilinx/Vivado/2022.2/bin/vivado.bat -mode batch -nojournal -nolog -source ../scripts/t1/hw_t1_mock.tcl` must end with `MOCK TESTS PASS`.
