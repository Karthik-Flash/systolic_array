# Demo Guide: Dynamic Precision-Scalable Systolic Array

How to run the live demo, what to say at each step, what you should see, and what it means.
Takes about 10 minutes (5 minutes for the short version in section 5).

**Status of the LED descriptions:** they come from the RTL design and the plan. The 2026-10-22 session log cannot show LEDs, so the first demo run is also the first time they are confirmed. Please note what you actually see (section 8).

---

## 1. The 60-second pitch

> "This is a 4×4 matrix multiplier on an FPGA, the core operation of neural networks. It can work with 16-bit, 8-bit or 4-bit numbers. Normally you would need three separate circuits. We keep **one fenced region** of the chip and swap what is inside it **while the rest of the chip keeps running**. A swap takes under half a second. Every answer is checked against a Python reference, and I will show you that smaller numbers change the answer in exactly the way the maths predicts."

---

## 2. What you are looking at: the LEDs

Eight user LEDs, labelled **LD0 to LD7** on the board silkscreen (read the labels), plus the blue **DONE** LED that lights when the FPGA is configured.

| LED | Meaning | Normal behaviour | Why it matters |
|---|---|---|---|
| **LD7** | Heartbeat of the **static region**. Blinks once per second (0.5 s on, 0.5 s off). | Always blinking while the chip is configured | If it keeps blinking through a swap, the fixed part of the chip was never interrupted |
| **LD6** | The swappable module is **held in reset** | Off. On during a swap, and while the reset is forced | Shows the module is being kept quiet |
| **LD5** | The region is **decoupled** (the door is closed) | Off. On during a swap | Shows its outputs are forced to safe values |
| **LD4** | **Done flag**: a calculation has finished | On after a run finishes. Cleared by a swap, a reset, or the next start | Shows a result is ready to read |
| **LD3..LD0** | **Precision badge**, blinking about 3 times a second (toggles every 168 ms) | see table below | Proves the loaded module is alive and tells you which one it is |

### The precision badge: count the lit LEDs

The number of LEDs that blink = the bits ÷ 4.

| Loaded module | LD3 LD2 LD1 LD0 | Module ID read by the laptop |
|---|---|---|
| int16 | all four blink together | 16 |
| int8 | LD1 and LD0 blink | 08 |
| int4 | only LD0 blinks | 04 |
| Empty (greybox) | all four dark | 00 |
| During a swap (decoupled) | all four dark | FF |

### Decoding any state at a glance

| What you see | What is happening |
|---|---|
| Everything dark, DONE off | Blank chip, nothing loaded |
| LD7 blinking, LD3..0 blinking, LD5/LD6 off | A module is loaded and running, idle |
| Same plus LD4 on | A calculation finished; the result is waiting |
| LD5 and LD6 on, LD3..0 dark, LD7 still blinking | **Mid-swap.** Region is isolated and held in reset; the static region is alive |
| LD3..0 dark but LD7 blinking, LD5/LD6 off | Greybox loaded (empty module): chip healthy, region does nothing |
| Everything stops for about 2.5 s, then restarts | A **full** reprogramming: the static region itself was rewritten (this is the contrast to a swap) |

---

## 3. Setup (5 minutes before you start)

1. Boot-mode jumpers on JTAG as in the T1 session, USB cable in **J17 (PROG)**, board powered.
2. Launch Vivado from PowerShell so the whole session is logged:
   ```powershell
   cd D:\Projects\RC_Project\vivado\lab_t2
   C:\Xilinx\Vivado\2022.2\bin\vivado.bat -mode gui -log demo.log -journal demo.jou
   ```
3. Open Hardware Manager, then Open Target, then Auto Connect. The device `xc7z020_1` appears.
4. Bring a phone: film the LEDs during steps 3, 5, 7 and 9.

---

## 4. The demo script

Type each command in the Hardware Manager **Tcl Console**, one at a time. Add `-quiet` to the `source` line if you want a clean console.

### Act 1. It works

| # | Command | You should see | What it represents |
|---|---|---|---|
| 1 | `source D:/Projects/RC_Project/scripts/t2/hw_t2.tcl` | `hw_t2.tcl loaded (mock=0)` | Loads the board-control commands |
| 2 | `t2_connect` | `connected (device xc7z020_1; JTAG clock 15000000 Hz)` | Talking to the chip over the same USB cable |
| 3 | `t2_program full int16` | about 2.5 s; DONE LED on; **LD7 blinks; LD3..0 blink together** | Full programming: the fixed part plus the int16 module |
| 4 | `t2_status` | `rm_id 16 (int16)`, uptime counting up, `runs 0` | The module identifies itself; uptime proves the static counter runs |
| 5 | `t2_set_precision int16 counting` | A 4×4 matrix with **110** at row 0, column 2, then `matches golden: yes` | A real calculation on silicon, checked against Python |

> Say: "That 110 is 1×9 + 2×10 + 3×11 + 4×12. The hardware computed it with 16 DSP multipliers working at once."

### Act 2. Swap while it runs

| # | Command | You should see | What it represents |
|---|---|---|---|
| 6 | `t2_set_precision int8 counting` | `now int8 (swap about 430 ms)`. **LD5/LD6 light and LD3..0 go dark during the swap, then LD1 and LD0 blink.** **LD7 never stops.** Same matrix as step 5, `matches golden: yes` | The swappable region got a new module in under half a second |
| 7 | `t2_set_precision int4 counting` | `now int4`. **Only LD0 blinks.** The matrix changes: **70** at row 0, column 2 (not 110). `matches golden: yes` | Smaller numbers give different answers, exactly as predicted |

> Say: "int4 can only hold -8 to 7, so every value above 7 is clamped to 7. 1×7 + 2×7 + 3×7 + 4×7 = 70. Still 'matches golden: yes', because the reference model clamps the same way."

### Act 3. Live saturation (the "aha" moment)

Paste this helper once (it swaps to the precision you name, loads two matrices, runs, and prints two corner results):

```tcl
proc show {prec A B} { if {[t2_prec_of [t2_rmid]] ne $prec} { t2_swap $prec }; t2_load $A $B; if {![t2_run]} { puts "run failed"; return }; lassign [t2_read_c] c o; puts "$prec: C\[0\]\[0\] = [lindex $c 0]   C\[3\]\[3\] = [lindex $c 15]   overflow flag [lindex $o 0]" }
```

| # | Command | Expected |
|---|---|---|
| 8 | `foreach p {int16 int8 int4} { show $p [lrepeat 16 100] [lrepeat 16 1] }` | `int16: 400`, `int8: 400`, `int4: 28` |
| 9 | `foreach p {int16 int8 int4} { show $p [lrepeat 16 200] [lrepeat 16 1] }` | `int16: 800`, `int8: 508`, `int4: 28` |

What it represents: every cell is A (all 100, then all 200) times B (all 1), summed four times.
- 100 fits in int8 (limit 127) so int8 matches int16. In int4, 100 is clamped to 7: 4 × 7 = 28.
- 200 does not fit in int8, so it is clamped to 127: 4 × 127 = **508**, not 800. In int4 it is again 4 × 7 = 28.

> Say: "The hardware saturates instead of wrapping around. If it wrapped, 200 would become -56 and the answer would be negative. Saturating is the safer choice for neural networks."

### Act 4. The full comparison, then the safety features

| # | Command | You should see | What it represents |
|---|---|---|---|
| 10 | `t2_demo` | Three tables (counting, random_full, extremes_neg), each showing int16 / int8 / int4 side by side with `*` where a value differs from int16. For extremes_neg: 2147483647 (saturated), 65536, 256. Ends with `demo PASS` and a CSV path | 144 numbers, all matching their precision's reference. Saves `hw_demo_*.csv` |
| 11 | `t2_swap_demo grey` | BEFORE / DECOUPLE (`rm_id ff`, result 0) / PROGRAM (about 420 ms) / RELEASE (`rm_id 00`) / AFTER; `VERDICT: PASS`. **LD3..0 dark, LD7 still blinking** | The empty module: chip healthy, region does nothing |
| 12 | `t2_swap_demo int16` | Same layout, `rm_id 16`, `VERDICT: PASS`, badge blinks again | Back to the start |
| 13 | `t2_block_test` | Two lines `refused (PASS)` (while decoupled; while in reset) and one `accepted ... PASS`; `block test PASS`. **LD5/LD6 light briefly** | The start gate: nobody can run a calculation while the region is mid-swap |

### Act 5. The contrast

| # | Command | You should see | What it represents |
|---|---|---|---|
| 14 | `t2_full_contrast` | About 2.5 s: **all LEDs including LD7 stop**, then restart. `uptime N -> 0` and `PASS` | A full program resets the static region too. A partial swap never did. That is the whole point of DFX |

Optional: `t2_selftest 1` runs an automatic check of two full programs and four swaps and writes a CSV (takes a few minutes).

---

## 5. Short version (5 minutes)

Steps 1-5, then 7 (int4), then 9 (the 200 example), then 11 (grey) or 14 (contrast). Keep LD7 in the camera frame for the swap steps.

---

## 6. What to say if asked

| Question | Short answer |
|---|---|
| Why not three separate circuits? | They would use three times the area. DFX reuses one region; we measured the region's cost per module (253, 1,451 or 693 lookup tables). |
| What stops a bad value during a swap? | The decoupler forces the boundary wires to zero, the module is held in reset, and the start gate refuses runs. |
| Why 0.43 s? | The partial file is 585,559 bytes and the JTAG cable ran at 15 MHz. The time depends on the region's size, not on what is inside. |
| Is int4 "wrong"? | No. It is a coarser number format. The hardware matches the reference for int4. The *answer* differs because the inputs were clamped. |
| Does this speed up a neural network? | Not claimed. We show correct swapping and the resource trade-off. Accuracy and power are future work. |
| What would make swaps faster? | A faster path than JTAG (for example the processor's configuration port). Not used or measured here. |

---

## 7. If something goes wrong

| Symptom | Do this |
|---|---|
| `t2_connect` cannot find the device | Re-seat the J17 cable, close other Vivado windows, Open Target again |
| `no VIO core` | Run `t2_program full int16` |
| `[Xicom 50-103]` | A partial was loaded onto a blank chip: `t2_program full int16` first |
| A check says FAIL | Stop, copy the `got ... expected` lines, send them to me |
| `[Labtools 27-1952]` warnings | Expected after a full program, harmless |

---

## 8. After the demo: what to bring back

- The Tcl console text or `demo.log`.
- For each LED row in section 2: **what you actually saw** (matches or differs, and the blink speed if it looked different).
- Phone video of one swap with LD7 in frame, and a photo of each badge (int16, int8, int4, greybox).
- Anything that surprised you, and any command that behaved differently from the "You should see" column.

Save logs to `docs/t2/reports/` and tell me the file names.
