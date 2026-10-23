# Dynamic Precision-Scalable Systolic Array using DFX

## The whole project, from scratch

**Course:** Reconfigurable Computing (CS G553), BITS Pilani Hyderabad
**Board:** ZedBoard (Xilinx Zynq-7000, FPGA part `xc7z020clg484-1`) · **Tools:** Vivado 2022.2, Python 3 with NumPy, XSim and Icarus Verilog
**Status:** T0, T1 and T2 are complete and verified on real hardware. T3 is future work.

This document explains the project end to end for a reader with no FPGA background. It follows the order in which we built things. Every number comes from a report, log or CSV in the repository (the last section says where).

## Contents

1. [What this project is](#1-what-this-project-is)
2. [The ideas, from the ground up](#2-the-ideas-from-the-ground-up)
3. [How the project is organised](#3-how-the-project-is-organised)
4. [T0: the calculator](#4-t0-the-calculator)
5. [T1: the swap mechanism](#5-t1-the-swap-mechanism)
6. [T2: three precisions in one region](#6-t2-three-precisions-in-one-region)
7. [How we made sure it was right](#7-how-we-made-sure-it-was-right)
8. [All results in one place](#8-all-results-in-one-place)
9. [What it does not show, and what comes next](#9-what-it-does-not-show-and-what-comes-next)
10. [Applications](#10-applications)
11. [Glossary](#11-glossary)
12. [Where everything lives](#12-where-everything-lives)

---

## 1. What this project is

Neural networks spend nearly all their time on one operation: multiplying tables of numbers (matrices). We built a small hardware multiplier for that operation on an FPGA, a chip whose wiring can be rewritten by loading a file.

The twist is **precision**. Numbers can be stored with 16, 8 or 4 bits. Fewer bits cost less chip area and energy but give coarser answers. A normal design chooses one precision forever. Ours can **change precision while it runs**, by rewriting only a fenced-off region of the chip (a feature called Dynamic Function eXchange, DFX) while the rest keeps working.

We did it in three steps:

| Tier | What it proved | Where it ran |
|---|---|---|
| **T0** | A 4×4 grid of multiply-accumulate units works and gives correct answers at 100 MHz | Simulation, then real silicon |
| **T1** | DFX works on this board with this toolchain: swap a region's contents in about 1.4 s without disturbing the rest | Real silicon, 15 of 15 swaps |
| **T2** | The region can hold the real multiplier in three precisions (int16, int8, int4) behind one fixed interface, and swap between them | Real silicon, 14 of 14 self-test steps |
| T3 | (future) Measure accuracy against precision on real data, power, real workloads | not started |

---

## 2. The ideas, from the ground up

### 2.1 Bits and numbers

A chip stores everything as switches that are off (0) or on (1). One switch is a **bit**; n bits can hold 2ⁿ different values. Negative numbers use **two's complement**: the top bit carries a negative weight.

| Name | Range |
|---|---|
| int16 | −32,768 to 32,767 |
| int8 | −128 to 127 |
| int4 | −8 to 7 |

If a value does not fit, hardware can **wrap** (keep the low bits: 200 in 8 bits becomes −56) or **saturate** (clamp to the limit: 200 becomes 127). We always saturate, because wrapping silently flips the sign.

### 2.2 Matrices and the MAC

To multiply matrices A and B, each output is a row of A times a column of B, summed:

```
A = | 1 2 |   B = | 5 6 |   C[0][0] = 1×5 + 2×7 = 19    C[0][1] = 1×6 + 2×8 = 22
    | 3 4 |       | 7 8 |   C[1][0] = 3×5 + 4×7 = 43    C[1][1] = 3×6 + 4×8 = 50
```

Each step is "multiply, then add to a running total": a **MAC** (multiply-accumulate). A 4×4 product needs 64 MACs.

### 2.3 Why special hardware: the memory wall

A processor spends more time moving numbers than multiplying them. Our own T0 shows it: a 4×4 multiply takes **110 ns** of compute, but sending 64 bytes in and 64 bytes out over a 115,200-baud serial link takes about **11 ms**, roughly 100,000 times longer. Accelerators win by keeping data close to the arithmetic and reusing it.

### 2.4 The systolic array

A **systolic array** is a grid of small calculators (**PEs**, processing elements). Each PE does one MAC per clock tick and hands its inputs to its neighbours, like buckets passed along a line. Data pulses through the grid like blood through the body ("systolic" comes from the heartbeat).

Ours is **output-stationary**: PE(i, j) never moves its running total; it stays put and becomes output C[i][j]. Values of A enter from the west, values of B from the north. Neighbours receive data one tick later, so inputs are fed in a **staircase** (row 1 starts one tick after row 0, row 2 one more, and so on) so the right numbers meet at the right PE. A 4×4 grid has 16 PEs doing 16 MACs every tick.

### 2.5 Precision and the accumulator

The running total needs a bigger "bucket" than the inputs. Worst case in int8: (−128) × (−128) = 16,384, and four of them add to 65,536, which needs **18 bits**. In int4 the worst case is 4 × 64 = 256, which needs **10 bits**. In int16 the hardware accumulates in 48 bits and clamps the final answer to 32. Rule of thumb: input width doubles for the product, plus 2 bits for summing four products.

### 2.6 What is inside an FPGA

An **FPGA** is a chip of reconfigurable logic. Two ingredients matter here:

- **LUT** (lookup table): a tiny programmable logic cell. Everything can be built from them, at the cost of area.
- **DSP slice**: a ready-made multiplier-adder baked into the chip. Compact and fast for 16-bit arithmetic. Our chip has 220 of them.

The chip is paced by a **clock**: 100 MHz here, so each tick is 10 ns.

### 2.7 Timing: slack

Every signal must travel from one register to the next within one clock period. **Setup slack** is the spare time on the slowest path (positive means it arrives in time). **Hold slack** checks data does not change too early. The report summarises them as **WNS** (worst negative slack) and **WHS** (worst hold slack); both must be zero or above.

### 2.8 Configuration, bitstreams and DFX

A **bitstream** is the file that configures an FPGA. A **full** bitstream rewrites the whole chip. DFX lets us rewrite one region with a small **partial** bitstream while the rest keeps running. Think of a house where you redo one room while everyone lives in the others.

| House | FPGA |
|---|---|
| Rest of the house | **Static region**: fixed logic that never changes |
| One fenced room | **Reconfigurable partition (RP)**, placed in a fenced area called a **Pblock** |
| The doorway, always the same | **Frozen interface**: the same wires cross the boundary for every module |
| Furniture sets | **Reconfigurable modules (RMs)**, here int16 / int8 / int4 |
| Empty room | **Greybox** |
| Closing the door during the move | **Decoupler**: forces the boundary wires to safe values during a swap |

The partial file's size depends on the *size of the fenced area*, not on what is inside it, so swap time is the same for every module.

---

## 3. How the project is organised

**Tiers and tags.** Each tier has a plan, an implementation, a verification stage and a board session. Git tags mark the milestones: `t0-datapath`, `t0-system`, `t0-onboard`, `t1-rtl`, `t1-built`, `t1-onboard`, `t2-rtl`, `t2-built`, `t2-onboard`.

**Timeline.** T0 on silicon first; T1 board sessions followed (the self-test data is dated 2026-10-08); T2's build, collection and reports were finished by 2026-10-16 (the report scripts ran that day), and it ran on the board on 2026-10-22.

**Method.** Each tier followed the same loop: write a plan with decisions and predictions, implement from it, verify in simulation against a Python reference, build in Vivado, collect and check the bitstreams, rehearse the board scripts on a software mock, then run on the real board and compare with the predictions. The human orchestrator ran every Vivado GUI step and every board step, with AI coding assistants helping to plan, write and review code and scripts.

**Repository layout.**

```
rtl/           Verilog: T0 modules, rtl/t1/ (DFX modules), rtl/t2/ (T2 top and RMs)
tb/            testbenches
python/        golden model, quantisation, vector generators
constraints/   pin, clock and Pblock constraints
scripts/       Tcl and Python automation for builds, reports, board control, mocks
bitstreams/    the collected, checked bitstreams that were loaded on the board
sim/           test vectors (inputs and expected outputs)
docs/          guides, plans, runbooks, reports, images
vivado/        Vivado projects (not committed; regenerated from scripts)
```

---

## 4. T0: the calculator

**Goal:** a correct 4×4 int16 matrix multiplier on silicon.

### 4.1 What was built

| Module | Job |
|---|---|
| `pe.v` | One PE: multiply two int16 inputs, add to a 48-bit running total, pass inputs on to neighbours. Maps to one DSP slice. |
| `array.v` | The 4×4 grid of 16 PEs wired west-to-east and north-to-south |
| `controller.v` | Generates the staircase feed schedule and a clear signal |
| `loader.v` | Reads one result at a time and clamps it from 48 to 32 bits |
| `uart_rx.v`, `uart_tx.v`, `top.v` | A serial-port system: laptop sends A and B, gets C back (verified in simulation) |
| `top_vio.v` | The bring-up version: a Xilinx debug core (VIO) lets the laptop set start and read results over the programming cable |

The ZedBoard's serial connector is wired to the ARM processor side, not to the FPGA fabric our design lives in, so the serial system could only be verified in simulation. On the board we used the VIO debug core over JTAG instead.

### 4.2 Verification

A Python **golden model** computes the right answers and the exact feed schedule. Test vectors are generated from it, and every testbench compares hardware against those files. The model has its own self-checks (14 of 14 pass).

### 4.3 Results

| What | Result |
|---|---|
| Multipliers | 16 DSP slices, one per PE |
| Logic (serial-port system) | 1,335 LUTs, 665 flip-flops, no block RAM |
| Timing at 100 MHz | met: worst setup slack +0.378 ns (serial system), +1.427 ns (VIO system) |
| Compute latency | 10 streaming cycles + 1 clear = 110 ns per 4×4 product |
| Peak throughput | 16 MACs × 100 MHz = 1.6 GMAC/s |
| Power | 0.117 W total on-chip estimate (0.011 W dynamic), Vivado's estimate, not measured on the board |
| On silicon | Selecting result 2 read back `0x0000006E` = 110, exactly C[0][2] = 1×9 + 2×10 + 3×11 + 4×12 |

### 4.4 Lessons

- A subtle signed-arithmetic bug: a zero constant in a conditional expression silently turned a signed operation unsigned. Fix: make every operand signed.
- The reset button read 1 when pressed, but the design expected active-low; the design sat in reset until the button was held. Fix: rename the port and invert it.

---

## 5. T1: the swap mechanism

**Goal:** prove DFX works on this board before spending effort on the real arithmetic.

### 5.1 What was built

One fenced partition `U_RP` with a fixed set of 78 wires, and three modules that fit it: an adder (`rm_add`), a multiplier (`rm_mul`) and an empty greybox. The static region held a reset synchroniser, an uptime counter (counts seconds, so we can see whether the static region was ever disturbed), a decoupler, and a VIO debug core.

### 5.2 Choosing where to put the fence

The Zynq-7020's programmable logic is divided into six **clock regions**. We chose the right part of region **X1Y1**. A configuration column runs through X1Y1 and splits it, and the left part has no DSP columns, so it could never host a multiplier. The right part holds slices X80 to X103 and both DSP columns. Its capacity is 4,400 LUTs, 8,800 flip-flops, **40 DSPs** and 10 block RAMs.

This Pblock was reused unchanged in T2.

### 5.3 The Vivado DFX flow

Project mode with DFX enabled: one partition definition, three modules, three configurations. The first configuration is the **parent run** that places and routes the whole design; the others are **child runs** that reuse the parent's locked static region and only implement their module. A check called `pr_verify` confirms all builds share an identical static region, so any partial file fits any base design.

### 5.4 Results

| What | Result |
|---|---|
| Partial swap over JTAG | 1,424 ± 27 ms (N = 15) |
| Full programming | 9,060 ± 73 ms (N = 3) |
| Partial bitstream size | 585,560 bytes = 14.5% of the full 4,045,667 bytes |
| Static region during swaps | uninterrupted in 15 of 15 swaps (uptime kept counting) |
| Timing at 100 MHz | WNS +4.304 / +3.501 / +4.304 ns (add / mul / greybox), WHS +0.039 ns |
| `pr_verify` | pass |
| Static region cost | 636 LUTs, 1,412 flip-flops, no DSPs (about 97% of the LUTs are debug cores) |

**Conclusion:** a swap takes about 1.4 s, depends only on the fence size, and the rest of the chip never notices.

### 5.5 Lessons (selection)

- A DSP attribute applied to a whole module also pulled a counter into a DSP. Apply attributes to the exact signal.
- Vivado's Tcl is version 8.5; some newer commands do not exist. Test scripts in Vivado's own interpreter.
- Passing a zero-padded hex string through Tcl's `expr` makes it read as octal. Avoid `expr` on hex strings.
- A negative test (a deliberately bad swap) caught only 1 of 15 bad cases with a weak check, which led to a better continuity check.
- A partial bitstream cannot load onto a blank chip: always load the matching full bitstream first.
- The Hardware Manager's cached probe values go stale after programming (a harmless warning), so scripts rewrite values before reading.

---

## 6. T2: three precisions in one region

**Goal:** make the swappable region hold the real 4×4 multiplier in int16, int8 and int4, behind one frozen interface, and swap between them on silicon.

### 6.1 The key decisions

| # | Decision | Reason |
|---|---|---|
| D1 | The region holds the input clamps, the 4×4 array and the result select | About 180 boundary wires instead of about 900; the static side never needs to know the precision |
| D2 | All variants keep 16-bit input lanes; each module saturates its inputs at the array edge | One frozen interface; out-of-range values clamp instead of wrapping |
| D3 | int16 reuses the T0 PE and DSP slices; int8 and int4 use LUT multipliers (no DSPs); accumulators are 48 / 18 / 10 bits | A clean DSP-versus-LUT comparison; exact accumulator sizes |
| D4 | The T0 controller is reused; a start gate refuses runs while the region is decoupled or in reset | Closes a requirement left open in T1 |
| D5 | Matrices are loaded through two 256-bit VIO probes; results are read through a selector | Any matrix can run live; the same files drive simulation and board |
| D6 | Registers on both sides of the boundary | Every path across the boundary becomes register-wire-register, giving the timing margin T1 measured |
| D7 | Cycle count is identical for every precision by construction | Measured in simulation |
| D8 | Reuse the T1 Pblock unchanged | Already proven on silicon; capacity checked before building |
| D9 | Four configurations: int16, int8, int4, greybox | An empty-region control comes almost free |
| D10 | The Vivado project is created by a script; the builds are launched from the GUI | DFX setup is click-heavy and cannot be undone; a script is exact and reproducible |
| D11 | Module IDs 16 / 08 / 04 (00 empty, FF decoupled); LED badge with lit LEDs = bits ÷ 4 | The precision is readable at a glance |

One correction to the early estimate: the int8 accumulator needs **18 bits, not 17**, and int4 needs **10, not 9**, because the clamp allows −128 and −8.

### 6.2 Architecture

```
  Laptop (Vivado) ──── JTAG cable ────▶ VIO debug core
                                         │ matrices A, B · start · pick-a-result
  ┌──────────────────────────────────────┴────────────────────────┐
  │  STATIC REGION (never reprogrammed in normal use)             │
  │   controller ─▶ feed registers ───────────┐                   │
  │   start gate · done flag                  │ 180 wires         │
  │   uptime counter · LEDs                   ▼                   │
  │                      ┌─────────────────────────────┐          │
  │                      │  SWAPPABLE REGION  U_RP     │          │
  │                      │  int16 │ int8 │ int4 │ empty│          │
  │                      └──────────────┬──────────────┘          │
  │   decoupler (the door) ◀────────────┘ results                 │
  └───────────────────────────────────────────────────────────────┘
```

- **One calculation takes 15 ticks (150 ns):** 12 for the controller, 2 for the boundary registers, 1 for the done flag. This is identical for every precision.
- **A swap:** close the door (decouple, outputs forced to safe values, module held in reset, starts refused); load the partial bitstream over JTAG; open the door; the new module resets and announces its ID.
- **The 180 boundary wires** are 179 signals plus the clock: 134 inputs (two 64-bit lane buses, clear, reset, a 4-bit selector) and 45 outputs (32-bit result, overflow flag, 8-bit ID, 4-bit LED pattern).

### 6.3 The three modules

| | int16 | int8 | int4 |
|---|---|---|---|
| Input stage | pass-through | clamp to 8 bits | clamp to 4 bits |
| PE | T0 PE on a DSP slice | LUT multiplier | LUT multiplier |
| Accumulator | 48 bits | 18 bits | 10 bits |
| Output | clamp 48 to 32 bits | sign-extend | sign-extend |
| DSP slices | 16 | 0 | 0 |

### 6.4 Verification before Vivado

- **Golden model and 9 test cases** (zeros, ones, identity, counting, asym_small, random_inrange, random_full, extremes_neg, extremes_mix) for each precision. Several cases are designed to be *precision-sensitive* so a wrong-width module cannot pass by accident.
- **Simulation (XSim):** six positive builds (a bench for the region and a whole-design bench, three modules each) all pass. Three **negative builds** (the wrong module in a bench, a start gate forced open) all fail for the expected reason, which proves the tests can detect mistakes. Cycle counts are measured: controller 12, start to done flag 15, for every module and case.
- **Out-of-context synthesis** of each module checked the LUT count, DSP count (16 / 0 / 0) and estimated timing against gates before any Vivado project existed.
- **A scratch project** validated the whole project-creation script, including synthesis of all runs, before the real project was created.

### 6.5 The Vivado build

1. **Create the project** by script (static files, the three modules, the VIO core, constraints, partition definition `pd_t2`).
2. **Synthesise** five runs: the static design, three modules and the VIO. The region is a black box in the static run, as expected.
3. **Check the fence** in the Device view and run DRC (design-rule check): the fence sits in the right part of X1Y1 and DRC reports 0 errors.
4. **Implement four configurations.** The parent run `impl_1` builds `cfg_int16` and locks the static routing. Three child runs (`child_0_impl_1` = `cfg_int8`, `child_1_impl_1` = `cfg_int4`, `child_2_impl_1` = `cfg_grey`) reuse that locked static design and only implement their module, so they can run in parallel.
5. **Collect and check:** a script copies the bitstreams and checks that none is stale (older than its source). `pr_verify` compares the four static regions: identical, 180 partition pins compared. A bundle check confirms all nine files exist, are distinct and match the manifest.

### 6.6 Build results

| | int16 | int8 | int4 | empty |
|---|---|---|---|---|
| LUTs in the swappable region | 253 | 1,451 | 693 | 179 |
| Flip-flops | 166 | 600 | 336 | 1 |
| DSP slices | 16 | 0 | 0 | 0 |
| Share of the fence's LUTs | 5.75% | 32.98% | 15.75% | 4.07% |
| Worst setup slack (ns) | +2.135 | +1.481 | +2.981 | +2.981 |
| Worst hold slack (ns) | +0.088 | +0.088 | +0.088 | +0.088 |

- The static region costs the same in every build: 1,300 LUTs and 2,659 flip-flops (total minus the swappable region), which supports the locked static design.
- The identical hold slack in all four builds is expected for the same reason.
- int4 is about 2.1 times smaller than int8 in LUTs, not 4 times, because adders, accumulators and control do not shrink with the number size.
- int16 is the cheapest in LUTs because its multipliers are the 16 DSP slices.
- The empty module still reports 179 LUTs, the same as the number of non-clock boundary wires, which looks like a per-wire interface cost (an inference to confirm in the reports).
- Bitstreams: partial 585,559 bytes, full 4,045,666 bytes (predicted 585,560 and 4,045,667; the header string probably accounts for the one-byte difference).

### 6.7 On the board (2026-10-22)

The board was driven by a Tcl script (`hw_t2.tcl`) in Vivado's Hardware Manager at a **15 MHz JTAG clock**. It programs the files, writes matrices into the VIO, starts runs and reads results back, comparing with the golden files.

| Check | Result |
|---|---|
| All 9 golden cases, int16 | 9 of 9 |
| All 9 golden cases, int8 | 9 of 9 |
| Live demo: same matrices through int16, int8, int4, int16 | 144 of 144 values matched; for `counting` int8 equals int16 and int4 differs in 15 of 16 elements; for `extremes_neg` int16 saturates at 2,147,483,647 with the overflow flag, int8 gives 65,536, int4 gives 256 |
| Start gating | refused while decoupled and while held in reset; accepted after release |
| Self-test (2 full programs, 12 swaps) | 14 of 14 steps, 58 of 58 case checks |
| Static region during swaps | uptime ran 2 to 29 s without going backwards; reset only on the full re-programming |
| Whole session | 23 programs (19 partial, 4 full), no failures |
| Swap time | mean 429.3 ms (N = 12, sd 29.1, range 411 to 518); full programming mean 2,500.5 ms |

### 6.7.1 Analysis

- **Swap time did not match the prediction.** We predicted about 1.42 s (from T1) and measured 0.43 s. The cause is the JTAG clock: 15 MHz this time, and T1's clock was never recorded (its effective rate was 3.25 Mbit/s against about 11 Mbit/s now). The new two-point fit is 0.599 µs per byte plus 0.079 s.
- **Swap time does not depend on precision.** All partial files have the same size; the per-module means differ only within run-to-run scatter.
- **Perspective.** In 0.43 s the multiplier could have performed about 2.9 million 4×4 products (0.43 s ÷ 150 ns), so a swap pays off when a precision mode lasts many calculations.

### 6.8 Lessons

- The simulator choice mattered: the installed Icarus (version 0.9.7) rejected T0's two-dimensional net arrays, so all T2 benches ran in Vivado's XSim.
- Vivado batch jobs failed from Git Bash with "couldn't read file" but worked from PowerShell.
- The board-script mock caught two real bugs before the hardware was touched: a hex string passed through `expr` (turned `00007E45` into a floating-point number) and a bracket error in a format string.
- "Precision-blind" test vectors (small values) give identical answers in every precision; the suite needed cases that distinguish them.
- A markdown editor with a WYSIWYG view silently rewrote tables and code blocks when saving; documents should be edited in plain-text mode.

---

## 7. How we made sure it was right

| Layer | What it guards against |
|---|---|
| Golden model (Python) | wrong arithmetic: one answer key serves simulation, the mock and the board |
| Precision-sensitive test cases | a wrong-width module passing by accident |
| Negative tests | tests that cannot fail: each deliberate fault must be caught |
| Out-of-context synthesis gates | a module that does not fit, or uses the wrong resources, found before the long build |
| Scripted project creation, validated in a scratch project | click mistakes in an irreversible DFX setup |
| Staleness guard and manifest with checksums | loading an old or wrong bitstream |
| `pr_verify` | a partial file that does not fit the base design |
| Software mock of the board | script bugs found without risking hardware |
| Predictions written before building | fooling ourselves: results are compared with what we said would happen |
| Evidence trail | every number traceable to a report, log or CSV |

---

## 8. All results in one place

| | T0 | T1 | T2 |
|---|---|---|---|
| What | 4×4 int16 systolic array | DFX swap: adder, multiplier, empty | int16 / int8 / int4 arrays swapped in one region |
| Multipliers | 16 DSP | small adder/multiplier modules | 16 DSP (int16), none (int8, int4) |
| Timing at 100 MHz | met (+0.378 ns serial system, +1.427 ns VIO) | met (+3.501 to +4.304 ns) | met (+1.481 to +2.981 ns) |
| Compute per 4×4 product | 110 ns | n/a | 150 ns start to done flag (15 ticks) |
| Partial bitstream | n/a | 585,560 B | 585,559 B |
| Swap time | n/a | 1,424 ± 27 ms (JTAG clock not recorded) | 429.3 ms mean (JTAG at 15 MHz) |
| On silicon | result 110 read back | 15 of 15 swaps | 14 of 14 self-test steps, 144 of 144 demo values |

**Predictions versus measurements (T2):** results bit-exact (held); partial and full sizes within one byte (held); swap time 1.42 s predicted versus 0.43 s measured (not held, explained by the JTAG clock); partition pins 179 plus clock (held); cycle count identical across modules (held, in simulation).

---

## 9. What it does not show, and what comes next

**Not shown**
- Neural-network accuracy: no MNIST or other workload was run.
- Power or energy on the board: only T0's Vivado estimate exists, and none for T2.
- A full 9-case test of int4 on the board. int4 passed 5 case types in the self-test and 3 in the demo; the other four (identity, ones, zeros, random_inrange) passed in simulation only.
- LED behaviour in the logs (it is covered in `DEMO.md` and to be confirmed visually).
- Anything beyond one board, one JTAG speed and 12 timed swaps.

**T3 (not started)**
- Convert real-valued data to 16/8/4-bit integers on the host (symmetric quantisation), run it through each precision and **measure the error against int16**.
- Try a small real workload and measure power.
- Close the int4 on-board gap.
- Explore larger arrays or more modules in the same region, and faster reconfiguration paths than JTAG.

---

## 10. Applications

This is a demonstrator: it proves the mechanism and the resource trade-off, not an end product. These are the places the idea applies, and what would be needed to get there.

| Application | How runtime precision swapping helps | What is still needed |
|---|---|---|
| **Edge AI inference** (cameras, wearables, drones) | Run int4 or int8 when battery is low or latency matters, int16 when accuracy matters; or pick precision per layer | A larger array, a quantisation toolflow, accuracy and power measurements (T3) |
| **Always-on sensing** | A cheap low-precision "wake-up" detector that escalates to a precise module on demand | Autonomous control: the processor, not a laptop, triggering swaps |
| **Cloud and shared FPGAs** | Several tenants or workloads share one region by swapping accelerators in and out | Fast, secure partial-bitstream loading and isolation guarantees |
| **Satellites and remote systems** | Update or repair hardware functions in the field without a full restart, and change modes under a tight power budget | Fault handling, verified bitstreams and radiation-aware design |
| **Software-defined radio and video** | Swap filters, codecs or arithmetic widths as the signal or standard changes | Real-time swap control and glitch-free handover |
| **Automotive and robotics** | Mode-dependent perception pipelines: coarse and fast at speed, precise when parked or docking | Safety certification and deterministic swap latency |
| **Teaching and research** | A compact platform for studying mixed-precision and approximate computing, with a golden model and full evidence trail | Nothing: it is ready as it is |

**The numbers that decide whether swapping is worthwhile.** A swap takes 0.43 s over JTAG. A 4×4 product takes 150 ns, so one swap is equivalent to about 2.9 million products. Swapping pays off when a precision mode lasts for many calculations, such as a whole network layer, a whole video frame sequence or a battery state, and not when it must change every few microseconds. Faster configuration paths exist (for example through the processor's own configuration port), but they were not used or measured here.

**The core engineering idea carries over directly:** keep a fixed interface, isolate the swappable region with a decoupler, check that every build shares the same static region, and prove each variant against a reference model.

---

## 11. Glossary

| Term | Meaning |
|---|---|
| Accumulator | The running total inside a PE |
| Bit | One binary digit |
| Bitstream | File that configures an FPGA (full or partial) |
| Clock region | A fixed tile of the FPGA fabric; the Zynq-7020 has six |
| Decoupler | Logic that forces boundary wires to safe values during a swap |
| DFX | Dynamic Function eXchange: reconfiguring part of an FPGA at run time |
| DRC | Design-rule check |
| DSP slice | Built-in multiplier-adder block |
| FPGA | Chip whose logic is rewired by loading a file |
| Golden model | Trusted Python reference used to check hardware |
| Greybox | An empty module used as a blank or baseline |
| JTAG | Cable interface used to program and debug the chip |
| LUT | Small programmable logic cell |
| MAC | Multiply-accumulate step |
| Mock | A software stand-in for the board used to test scripts safely |
| Output-stationary | Each PE keeps one output's running total |
| Partition pin | A wire crossing the region boundary (180 here) |
| Pblock | The fenced physical area for the swappable region |
| PE | Processing element, one tile of the array |
| `pr_verify` | Vivado check that builds share an identical static region |
| RM / RP | Reconfigurable module / reconfigurable partition |
| Saturation | Clamping a value to the largest or smallest allowed |
| Slack | Spare time on a signal path (setup or hold) |
| Static region | The part of the chip that is never swapped |
| Systolic array | Grid of PEs passing data between neighbours |
| VIO | Debug core giving virtual switches and displays over JTAG |
| WNS / WHS | Worst setup slack / worst hold slack |

---

## 12. Where everything lives

| Topic | File |
|---|---|
| T0 guide | `docs/t0/T0_Complete_Guide.md` |
| T1 guide, plan, results, runbook | `docs/t1/` |
| T2 guide | `docs/t2/T2_Complete_Guide.md` |
| T2 plan (decisions, names, gotchas) | `docs/t2/T2_PLAN.md` |
| T2 board runbook and session record | `docs/t2/T2_BOARD_RUNBOOK.md` |
| Demo script and LED legend | `docs/DEMO.md` |
| T2 build results | `docs/t2/reports/build_summary.csv`, `pr_verify.rpt`, `sim_cycles.csv`, `ooc_summary.csv` |
| T2 board data | `docs/t2/reports/hw_session_20261022.log`, `hw_selftest_20261022_134926.csv`, `hw_demo_20261022_134038.csv` |
| Collected bitstreams and checksums | `bitstreams/t2/` (with `manifest.csv`) |
| Screenshots | `docs/t0/img`, `docs/t1/img`, `docs/t2/img` |
