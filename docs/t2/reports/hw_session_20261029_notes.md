# Board Session Record, 2026-10-29

Second T2 board session: the demo run and the video take. Two evidence files cover it:

| File | Content |
|---|---|
| `hw_session_20261029_console.txt` | Saved Vivado Tcl console text, from opening the project to the first full-program contrast (all at a 6 MHz JTAG clock) |
| `hw_demo_20261029_132829.csv` | `t2_demo` output: 144 rows, 0 mismatches |

The steps after the saved console text (the second part at 6 MHz, the change to 12 MHz, the video take) and the LED observations were recorded by the operator during the session. They are listed in sections 3 and 4.

## 1. Connection

| Item | Value |
|---|---|
| Hardware target | `localhost:3121/xilinx_tcf/Xilinx/20250619a5ce01` |
| JTAG clocks offered by this cable | 750,000, 1,500,000, 3,000,000, 6,000,000 and 12,000,000 Hz |
| Clock used | 6,000,000 Hz at the start (printed by `t2_connect`), then set to 12,000,000 Hz |
| 2026-10-22 session, for comparison | target `localhost:3121/xilinx_tcf/Digilent/210248685158`, 15,000,000 Hz |

The two sessions used different cable types: the 2026-10-22 target is a Digilent cable, the 2026-10-29 target a Xilinx cable.

## 2. Saved console (6 MHz)

| Step | Result |
|---|---|
| `t2_program full int16` | 8,885 ms; 1 VIO core; `rm_id 16`, uptime 37 s |
| `t2_set_precision` int16 / int8 / int4, `counting` | matches golden in all three; swaps int8 1,449 ms, int4 1,407 ms; C[0][2] = 110 / 110 / 70 |
| DEMO.md step 8 (A all 100, B all 1) | 400 / 400 / 28; swaps 1,379, 1,395, 1,390 ms |
| DEMO.md step 9 (A all 200, B all 1) | 800 / 508 / 28; swaps 1,371, 1,389, 1,405 ms |
| `t2_demo` | PASS, 144 of 144 values; swaps int16 1,389, int8 1,393, int4 1,396, back to int16 1,406 ms |
| `t2_swap_demo grey` | 1,394 ms; uptime 365 → 367 s, not reset; ID 00; VERDICT PASS |
| `t2_swap_demo int16` | 1,422 ms; uptime 391 → 393 s, not reset; ID 16; VERDICT PASS |
| `t2_block_test` | refused while decoupled and while in reset (runs 22 → 22, blocked 1); accepted after release; PASS |
| `t2_full_contrast` | 8,909 ms; uptime 430 → 0 s (static region reset, as expected); PASS |

## 3. Operator record (after the saved console text)

| Clock | Step | Result |
|---|---|---|
| 6 MHz | `t2_swap_demo grey` | 1,395 ms; uptime 589 → 591 s; VERDICT PASS |
| 6 MHz | `t2_swap_demo int16` | 1,367 ms; uptime 592 → 594 s; VERDICT PASS |
| 6 MHz | `t2_block_test` | refused while decoupled and while in reset (runs 4 → 4); accepted after release; PASS |
| 12 MHz | `t2_swap_demo grey` | 857 ms; uptime 1,111 → 1,112 s; VERDICT PASS |
| 12 MHz | `t2_swap_demo int16` | 883 ms; uptime 1,113 → 1,115 s; VERDICT PASS |
| 12 MHz | video take, `vid_1` | int16 result 800, OK |
| 12 MHz | video take, `vid_2` | swap to int8 884 ms; uptime 1,378 → 1,379 s; result 508, OK |
| 12 MHz | video take, `vid_3` | swap to int4 976 ms; uptime 1,387 → 1,389 s; result 28, OK |
| 12 MHz | video take, `vid_4` | full program 5,522 ms; uptime 1,396 → 0 s |

The Vivado GUI Tcl console printed each `vid_*` line as it happened, not only at the end of a command.

## 4. LEDs (observed on the board)

| LED | Observed |
|---|---|
| LD7 heartbeat | kept blinking through every partial swap |
| LD3..LD0 badge | int16 all four; int8 LD1 and LD0; int4 LD0 only; empty module dark |
| LD5, LD6 | lit during swaps |
| LD4 done flag | on after runs; cleared by swaps and resets |
| Full program | every LED, LD7 included, stopped, then restarted |

The video and photos of the session are kept outside the repository.
