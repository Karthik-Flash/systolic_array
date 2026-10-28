# Demo Video Shot List

A 40-second clip for the slides: one region of the chip changes precision while the rest keeps running. The same input (A all 200, B all 1) goes through int16, int8 and int4 and gives 800, 508 and 28. The heartbeat LED LD7 never stops during the swaps. Then a full reprogram stops everything, LD7 included, for about 2.5 s. That contrast is the point of the clip.

**Status of the LED descriptions:** every LED statement below is expected from the design, to be confirmed on the board. No LED footage exists yet.

---

## 1. Setup (not recorded)

In the Vivado Hardware Manager Tcl console, one command at a time:

| # | Command | Expected console line |
|---|---|---|
| 1 | `source D:/Projects/RC_Project/scripts/t2/hw_t2.tcl` | `hw_t2.tcl loaded (mock=0) ...` |
| 2 | `t2_connect` | `T2: connected (device xc7z020_1; JTAG clock 15000000 Hz) ...` |
| 3 | `t2_program full int16` | `T2:   done in ... ms` |
| 4 | `source D:/Projects/RC_Project/scripts/t2/video_t2.tcl` | `video_t2.tcl loaded: vid_ready vid_1 vid_2 vid_3 vid_4 ...` |
| 5 | `vid_ready` | `READY: int16 loaded, uptime N s` |

`vid_ready` also hides Vivado's routine programming messages so the console stays clean. `vid_verbose` brings them back.

Before the first take, run `vid_1` once and check that its line appears in the console. In batch mode the lines appear one by one as each step finishes; the GUI console has not been checked yet.

---

## 2. Camera and screen

- Phone on a stand, landscape. In frame: LD0 to LD7 with their silkscreen labels, and the blue DONE LED.
- Room lights dimmed. Focus and exposure locked on the LEDs (tap and hold on the phone screen).
- 60 frames per second if the phone offers it.
- Record the Tcl console at the same time: OBS, or Win+Alt+R (Xbox Game Bar).
- Clap once in view of the phone at the start of each take, to line up the two recordings.
- Takes loop: `vid_1`, `vid_2`, `vid_3`, `vid_4`, then `vid_1` again for the next take. No setup needed between takes.

---

## 3. Shot table

Target length 40 s. On the board a swap takes about 0.43 s and a full reprogram about 2.5 s (measured on 2026-10-22). Each command also needs a few seconds of JTAG reads and writes.

| Time | Command | LEDs: what to see | Console line | Caption for Canva | What it means |
|---|---|---|---|---|---|
| 0–9 s | `vid_1` | Expected: LD3..LD0 blink together; LD7 blinks once per second; LD4 lights after the run | `int16   result 800   expected 800  OK` | 16-bit precision: result 800 | The 16-bit module multiplies exactly: 4 × 200 × 1 = 800. |
| 9–19 s | `vid_2` | Expected: LD5 and LD6 flash briefly and the badge goes dark; then only LD1 and LD0 blink; LD4 off during the swap, on after the run; LD7 never stops | `swap to int8 in N ms \| uptime A -> B s (not reset)` then `int8    result 508   expected 508  OK   (200 clamped to 127)` | Swapped to 8-bit: 200 clamps, result 508 | Only the fenced region was rewritten; 200 does not fit in 8 bits, so it is clamped to 127, and 4 × 127 = 508. |
| 19–28 s | `vid_3` | Expected: the same brief LD5/LD6 flash; then only LD0 blinks; LD7 never stops | `swap to int4 in N ms \| uptime A -> B s (not reset)` then `int4    result 28    expected 28   OK   (200 clamped to 7)` | Swapped to 4-bit: 200 becomes 7, result 28 | The 4-bit module clamps 200 to 7, so 4 × 7 = 28; the rest of the chip kept running. |
| 28–37 s | `vid_4` | Expected: every LED, LD7 included, stops blinking (expected dark) and DONE goes off for about 2.5 s; then DONE, LD7 and all four badge LEDs restart | `FULL reprogram in N ms \| uptime A -> 0 s (whole chip restarted)` | Full reprogram: whole chip stops, LD7 included | Rewriting the whole chip stops everything; a swap never did. |
| 37–40 s | closing card | – | – | One region changed precision; the rest never stopped. | – |

LED key: LD7 = heartbeat of the fixed part of the chip; LD6 = module held in reset; LD5 = region isolated during a swap; LD4 = calculation finished; LD3..LD0 = precision badge (number of blinking LEDs = bits ÷ 4).

---

## 4. Observation sheet (fill in on the day)

| Shot | What to check | Seen? (yes / no) | Notes (blink speed, anything different) |
|---|---|---|---|
| 1 | LD3..LD0 blink together | | |
| 1 | LD7 blinks once per second | | |
| 1 | LD4 lights after the run | | |
| 1 | Console shows `result 800 ... OK` | | |
| 2 | LD5 and LD6 flash during the swap | | |
| 2 | Badge dark during the swap, then LD1 and LD0 blink | | |
| 2 | LD7 never stops | | |
| 2 | Console shows `result 508 ... OK` and the swap time | | |
| 3 | Only LD0 blinks after the swap | | |
| 3 | LD7 never stops | | |
| 3 | Console shows `result 28 ... OK` | | |
| 4 | All LEDs and DONE stop for about 2.5 s | | |
| 4 | LD7 and the badge restart afterwards | | |
| 4 | Console shows `uptime A -> 0 s` | | |
| All | Console lines appear while each command runs, not only at the end | | |

---

## 5. Editing notes for Canva

- Slow the swap moment to 25% speed so the brief LD5/LD6 flash is visible.
- Put each result (800, 508, 28) on screen as large text when its console line appears.
- Keep LD7 visible in every shot; it is the proof that the fixed part of the chip kept running.
- Place the console recording next to the LED video, lined up on the clap.
- In shot 4, hold on the dark board for the whole 2.5 s; the pause is the message.

---

## 6. Backup clip (2–3 min)

For the live-demo slide, in case the board fails on the day. Record the short version of the demo script in `docs/DEMO.md`: steps 1 to 5, then step 7 (int4), then step 9 (the 200 example), then step 11 (greybox) or step 14 (full-program contrast). Keep LD7 in the camera frame for every swap step.

---

## 7. Commands and what they print

| Command | What it does | Prints |
|---|---|---|
| `vid_ready` | Checks the board is connected and int16 is loaded (swaps to int16 if not); hides routine Vivado messages | `READY: int16 loaded, uptime N s` |
| `vid_1` | On int16, loads A = 16 × 200 and B = 16 × 1, runs, reads C[0][0] | `int16   result 800   expected 800  OK` |
| `vid_2` | Swaps to int8, then the same load, run and read | swap line, then `int8 ... 508 ... OK   (200 clamped to 127)` |
| `vid_3` | Swaps to int4, then the same load, run and read | swap line, then `int4 ... 28 ... OK   (200 clamped to 7)` |
| `vid_4` | Full reprogram with `t2_full_int16.bit`; leaves the board on int16, ready for `vid_1` | `FULL reprogram in N ms \| uptime A -> 0 s (whole chip restarted)` |
| `vid_verbose` | Shows Vivado's programming messages again | `Vivado program messages shown again` |

If a check fails, the command prints `MISMATCH got X expected Y` and stops.

*Sources: scripts/t2/video_t2.tcl, scripts/t2/hw_t2.tcl, docs/DEMO.md (step 9 expected values), docs/t2/reports/hw_selftest_20261022_134926.csv (swap and full-program times)*
