# T2 in Plain Language

**Dynamic Precision-Scalable Systolic Array using DFX**
Swapping the "number size" of a hardware calculator while it keeps running, on a ZedBoard FPGA.

*Who this is for:* someone smart who has never touched an FPGA. Every technical word is explained the first time it appears. A glossary is at the end. The deeper, line-by-line version comes later in `T2_Complete_Guide.md`.

---

## 1. The one-minute version

- **What it is.** A small hardware calculator (a 4×4 grid, 16 tiny calculators) that multiplies tables of numbers (matrices). Matrix multiplication is the main workload of neural networks.
- **The trick.** The calculator can work with three "number sizes": 16-bit, 8-bit and 4-bit. Smaller numbers are less exact but cheaper. We can **swap between the three while the rest of the chip keeps running**, in about **0.43 seconds**.
- **How.** A Xilinx feature called Dynamic Function eXchange (DFX) lets us rewrite only one fenced-off region of the chip, not the whole thing.
- **Proof.** Every result the hardware produced matched a Python reference model exactly. 23 programming operations on the real board, no failures.
- **What we did not do.** No neural-network accuracy test, no power measurement. Those are future work (T3).

| Result | Value |
|---|---|
| Swap time between precisions (average of 12) | 0.43 s (full chip programming: 2.5 s) |
| Timing on a 100 MHz clock | met in all four builds (worst spare time +1.48 ns) |
| Board self-test | 14 of 14 steps passed, 58 of 58 checks |
| Live demo: same matrices on 16, 8 and 4 bits | 144 of 144 numbers matched the reference |
| Cost of 16-bit vs 8-bit vs 4-bit (lookup tables used) | 253 vs 1,451 vs 693 (16-bit uses 16 dedicated multipliers instead) |

---

## 2. The problem in everyday terms

A neural network is mostly one operation repeated billions of times: multiply two tables of numbers.

Numbers on a chip are stored with a fixed number of **bits** (binary digits). More bits means more precise but costs more chip area and energy. Think of measuring a table: a ruler with millimetre marks (16-bit) is more exact than one with centimetre marks (8-bit) or one with only 16 marks in total (4-bit). Sometimes "good enough" is fine and cheaper.

A normal chip design must pick one precision forever. We wanted the choice to be **changeable at run time**, without needing three separate calculators sitting on the chip.

---

## 3. The ideas you need

### 3.1 Matrix multiplication

Multiply row by column, add up the pieces:

```
A = | 1 2 |    B = | 5 6 |    C = A × B
    | 3 4 |        | 7 8 |

C[0][0] = 1×5 + 2×7 = 19      C[0][1] = 1×6 + 2×8 = 22
C[1][0] = 3×5 + 4×7 = 43      C[1][1] = 3×6 + 4×8 = 50
```

Each output needs a "multiply, then add to a running total" step. That step is called a **MAC** (multiply-accumulate).

### 3.2 The systolic array (an assembly line for MACs)

A **systolic array** is a grid of small calculators called **PEs** (processing elements). Each PE does one MAC per clock tick and passes its inputs to its neighbours, like buckets passed along a line.

Ours is **output-stationary**: PE(i, j) never moves its running total. It stays put and becomes output C[i][j]. Row values of A flow in from the west, column values of B from the north. Because neighbours get data one tick later, the inputs are fed in a **staircase**: row 1 starts one tick after row 0, row 2 one tick after that, and so on. That timing makes the right A and B values meet at the right PE. Our 4×4 grid has 16 PEs and finishes after 10 feed ticks.

### 3.3 Precision: what "int16, int8, int4" mean

"int" means whole number. The number is how many bits:

| Type | Range it can hold |
|---|---|
| int16 | −32,768 to 32,767 |
| int8 | −128 to 127 |
| int4 | −8 to 7 |

What if a value does not fit? Two options:

- **Saturate** (clamp to the limit): 200 in int8 becomes **127**. Like a thermometer that stops at its maximum.
- **Wrap** (keep only the low bits): 200 becomes **−56**. The sign flips, and the answer is silently wrong.

We always saturate.

### 3.4 Why the running total needs a bigger bucket

The sum of products is larger than the inputs. Worst case in int8: (−128) × (−128) = 16,384, and we add four of them = 65,536. That needs **18 bits** to store, not 8 or 17. For int4 the worst case is 4 × 64 = 256, which needs **10 bits**. For int16 the hardware uses 48 bits, and the final answer is clamped to 32 bits. (Rule of thumb: product bits double, plus 2 for adding four of them.)

### 3.5 Inside the FPGA: LUTs and DSPs

An **FPGA** is a chip full of reconfigurable logic. Two ingredients matter here:

- **LUT** (lookup table): a tiny programmable logic cell. You can build almost anything from thousands of them.
- **DSP slice**: a ready-made multiplier-adder baked into the chip. Fast and compact for 16-bit math.

Our int16 version uses 16 DSP slices (one per PE). Our int8 and int4 versions use **zero DSPs** and build their multipliers out of LUTs.

### 3.6 DFX: swapping part of the chip while the rest runs

Think of a house where you replace the furniture in one room while the rest of the house stays in use.

| House | Chip |
|---|---|
| The rest of the house | **Static region**: controller, debug link, LEDs, uptime counter. Never changes. |
| One fenced room | **Reconfigurable partition (RP)**, named `U_RP`, placed in a fenced area called a **Pblock** |
| The doorway, always the same size | **Frozen interface**: the same 180 wires cross the boundary for every module |
| Different furniture sets | **Reconfigurable modules (RMs)**: int16, int8, int4 |
| An empty room | **Greybox**: an RM that does nothing |
| New furniture delivery | **Partial bitstream**: a small file that rewrites only the fenced area |
| Closing the door during the move | **Decoupler**: forces the wires to safe values while the swap happens |

A **bitstream** is the file that configures an FPGA. A **full** bitstream rewrites everything (4.05 MB, 2.5 s). A **partial** one rewrites only the Pblock (0.59 MB, 0.43 s), and its size depends on the fenced area, not on what is inside.

---

## 4. What we built

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

- **Controller** (reused from the earlier tier T0) feeds the staircase of numbers.
- **Start gate:** a run is refused while the region is decoupled or held in reset. A `blocked` flag records any refused start.
- **VIO** (virtual input/output): a debug core that lets the laptop set switches and read values over the JTAG cable, no extra wiring needed.
- **Identity code:** each module reports an ID (16, 08 or 04; 00 for the empty one; FF while decoupled).
- **LEDs by design:** a blinking badge shows the loaded precision (four LEDs for int16, two for int8, one for int4) and a heartbeat LED proves the fixed part is alive.

### Timing of one calculation

The clock ticks 100 million times a second (10 ns per tick). The controller needs 12 ticks, plus 3 ticks for registers at the region boundary and the done flag: **15 ticks = 150 nanoseconds**, identical for every precision.

### How a swap works

1. Close the door (decouple). Results read as 0, the module ID reads FF, starts are refused.
2. Load the partial bitstream over JTAG (~0.43 s). The fixed part keeps running.
3. Re-open the door (release). The new module resets and reports its ID.
4. Load matrices, start, read results.

---

## 5. How we knew the answers were right

We wrote the maths twice: once in hardware, once in Python (the **golden model**). Every test compares the two exactly.

| Test case | What it catches |
|---|---|
| zeros, ones | Basic wiring |
| identity | Input clamping (multiplying by identity shows each value directly) |
| counting (1…16 and its transpose) | Row/column mix-ups |
| asym_small | Transposes that a symmetric test would hide |
| random_inrange | Ordinary arithmetic |
| random_full | Clamping at the array edge |
| extremes_neg, extremes_mix | Overflow and saturation |

The same files drive three checks: simulation, a pretend board, and the real board. Sample result for `counting`, element C[0][2] (row 0 of A times column 2 of B = 1×9 + 2×10 + 3×11 + 4×12): **110 in int16 and int8, but 70 in int4**, because int4 clamps every value above 7 down to 7.

We also ran **deliberately wrong builds** (the wrong module, a start gate forced open). Each one failed the tests, which proves the tests can detect mistakes. The board scripts were first rehearsed on a software mock of the board, which caught real bugs before the hardware was ever touched.

---

## 6. The build in Vivado

Vivado is Xilinx's design tool. We followed these stages:

1. **Create the project by script** (so it is exactly reproducible), with the fixed part plus three modules.
2. **Synthesis:** turn the Verilog code into LUTs and DSPs.
3. **Floorplan:** reuse the T1 fenced area in the right half of clock region **X1Y1**. That half contains DSP columns (the left half has none), so it can hold the int16 module. Capacity: 4,400 LUTs, 8,800 flip-flops, 40 DSPs, 10 block RAMs.
4. **Place and route** four configurations (int16, int8, int4, empty).
5. **Checks:** DRC (design-rule check) found 0 errors. `pr_verify` confirmed that all four builds have the identical fixed part, so any partial file fits any base design.

### Build results

| | int16 | int8 | int4 | empty |
|---|---|---|---|---|
| LUTs used by the swappable region | 253 | 1,451 | 693 | 179 |
| DSP slices | 16 | 0 | 0 | 0 |
| Share of the fenced area's LUTs | 5.75% | 32.98% | 15.75% | 4.07% |
| Worst setup slack (ns) | +2.135 | +1.481 | +2.981 | +2.981 |
| Worst hold slack (ns) | +0.088 | +0.088 | +0.088 | +0.088 |

**Reading the table:**
- **Slack** is spare time. A signal has 10 ns per tick; slack is how much is left on the slowest path. Positive means the timing is met. **Hold** slack checks that data does not change too early.
- The identical hold slack in all four builds is expected: the fixed part is locked and shared.
- The fixed part uses 1,300 LUTs and 2,659 flip-flops in every build (total minus the swappable region).
- The empty module still shows 179 LUTs, equal to the number of region wires (a likely interface cost; not yet confirmed in the reports).
- int4 is about 2.1 times smaller than int8 in LUTs, not 4 times: the adders, accumulators and control around the multipliers do not shrink with the number size.

Bitstream sizes: partial 585,559 bytes, full 4,045,666 bytes. (We predicted one byte more for each; the header text differs by a character. Likely cause, not confirmed.)

---

## 7. On the real board (22 October 2026)

Setup: ZedBoard, Vivado Hardware Manager, **JTAG clock 15 MHz**. A script (`hw_t2.tcl`) drives the board: it programs the files, writes matrices into the VIO, starts runs and reads results back.

What happened:

- Programmed the full int16 design, checked all 9 test cases: **9 of 9**. Swapped to int8, all 9: **9 of 9**.
- Start-gating test: starts were **refused** while decoupled and while the module was held in reset, and accepted after release.
- Live demo (same matrices through int16, int8, int4, int16): **144 of 144** numbers matched. For `counting`, int8 equals int16 but int4 differs in 15 of 16 elements. For `extremes_neg`, every element reads 2,147,483,647 (saturated, with overflow flag) in int16, 65,536 in int8, and 256 in int4.
- Self-test: 2 full programs and 12 swaps (int8, int4, empty, int16, three times). **14 of 14 steps passed.** The fixed part's uptime counter ran from 2 to 29 seconds without ever going backwards, so it was never disturbed. It reset only on the full re-programming, as designed.
- Total: **23 programming operations (19 partial, 4 full), none failed.**

Swap time: average **0.43 s** (range 0.41–0.52 s). It is the same for every module because the partial file has the same size.

**One prediction missed.** We expected about 1.4 s per swap. The measured 0.43 s is faster because this session's JTAG cable ran at 15 MHz, while the earlier T1 clock speed was not recorded. The effective speed was about 11 Mbit/s.

---

## 8. What this shows, and what it does not

**Shows**
- One fenced chip region can host three precision variants behind one frozen interface.
- Each variant matched the reference model bit for bit.
- Swapping takes under half a second and leaves the rest of the design running.
- Smaller precision trades accuracy for logic: the DSP-free modules cost 693 to 1,451 LUTs, while int16 costs 16 DSPs and 253 LUTs.

**Does not show**
- Neural-network accuracy (no MNIST or other workload was run).
- Power or energy (not measured).
- A full 9-case test of int4 on the board. int4 passed 5 case types in the self-test and 3 in the demo. The other four (identity, ones, zeros, random_inrange) passed in simulation only.
- LED behaviour in the log (designed and simulated, not recorded).
- Anything beyond one board, one JTAG speed and 12 timed swaps.

---

## 9. What comes next (T3 ideas, not started)

- Convert real-valued data to 16/8/4-bit integers on the host, run through each precision, and **measure the error against int16**.
- Try a small real workload, and measure power.
- Close the int4 on-board test gap and photograph the LEDs.
- Explore larger arrays or more modules in the same region, and faster reconfiguration.

---

## 10. Glossary

| Term | Meaning |
|---|---|
| Accumulator | The running total inside a PE |
| Bit | One binary digit; n bits hold 2ⁿ values |
| Bitstream | File that configures the FPGA (full or partial) |
| Clock | The tick (100 MHz here) that paces the logic |
| DFX | Dynamic Function eXchange: reconfiguring part of an FPGA at run time |
| Decoupler | Logic that forces boundary wires to safe values during a swap |
| DRC | Design-rule check |
| DSP slice | Built-in multiplier-adder block |
| FPGA | Chip whose logic can be rewired by loading a file |
| Golden model | Trusted Python reference used to check hardware |
| Greybox | Empty module used as a blank or baseline |
| JTAG | Cable interface used to program and debug the chip |
| LUT | Small programmable logic cell |
| MAC | Multiply-accumulate step |
| Output-stationary | Each PE keeps one output's running total |
| Partition pin | A wire crossing the region boundary (180 here) |
| Pblock | The fenced physical area for the swappable region |
| PE | Processing element, one tile of the array |
| `pr_verify` | Vivado check that builds share an identical fixed part |
| RM / RP | Reconfigurable module / reconfigurable partition |
| Saturation | Clamping a value to the largest or smallest allowed |
| Slack | Spare time on a signal path (setup or hold) |
| Static region | The part of the chip that is never swapped |
| Systolic array | Grid of PEs passing data between neighbours |
| VIO | Debug core giving virtual switches and displays over JTAG |

---

## 11. Where the numbers come from

| Topic | File |
|---|---|
| Timing, resources, pin count, DRC | `docs/t2/reports/build_summary.csv` |
| Compatibility check | `docs/t2/reports/pr_verify.rpt` |
| Simulation cycles and results | `docs/t2/reports/sim_cycles.csv`, `sim_summary.txt` |
| Bitstream sizes | `bitstreams/t2/manifest.csv` |
| Board session log | `docs/t2/reports/hw_session_20261022.log` |
| Self-test and demo data | `docs/t2/reports/hw_selftest_20261022_134926.csv`, `hw_demo_20261022_134038.csv` |
| Session summary and predictions | `docs/t2/T2_BOARD_RUNBOOK.md` (section F) |
| Design decisions and names | `docs/t2/T2_PLAN.md` |
