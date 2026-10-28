# Handoff: demo results, report, deck and Q&A

This file briefs a new chat that will finish the course deliverables for the FPGA project "Dynamic Precision-Scalable Systolic Array using DFX". That chat cannot see the repository. Upload this file, `BRIEFING_PACK.md` (every fact and table) and `docs/PROJECT_DETAIL.md` (the whole story in plain language).

---

## 1. What to produce, in this order

| # | Deliverable | Input it needs |
|---|---|---|
| 1 | Tabulate and explain the final demo results (lab on 2026-10-29) | the files the student uploads after the lab (section 3) |
| 2 | Text of the 2-page PDF report | section 2 rules, the results table in the briefing pack |
| 3 | The PPT, with speaker notes | the outline in section 7, the figures listed in the briefing pack |
| 4 | A short README or statement for the submission upload, only if the course wants one | `submission/note.txt` (the source package is already built) |
| 5 | Q&A practice | the seed table in section 8 |

---

## 2. The course rules (verbatim) and what they mean

1. **PPT.** Explain the motivation, the implementation details, and show the outputs. It is used during the FPGA-based demonstration scheduled between 23rd and 27th November 2026.
2. **Project report.** A well-formatted 2-page PDF, font size 12, single line spacing, explaining the project. A block diagram is allowed. No snapshots of Verilog code, no simulation waveforms, no Verilog code at all. Must include LUT usage, Delay and Power consumption results in table form. Do not paste images from Vivado. It is checked for plagiarism; marks are deducted if a significant portion is copied from other sources.
3. **Source files.** A separate folder with all Verilog files, xdc files, bit files and memory (.coe) files as applicable.

| Rule | What it means here |
|---|---|
| 2 pages, 12 pt, single spacing | About 600 to 800 words, one block diagram, one results table |
| LUT, delay, power in a table | All three exist for every configuration; type them by hand from the briefing pack |
| No code, waveforms or Vivado images in the report | Redraw the block diagram; screenshots may appear in the PPT only |
| Plagiarism check | Fresh wording; do not paste sentences from the project guides |
| Source folder | Already built in `submission/`; there are no .coe files (no memory initialisation is used) |
| Demo 23 to 27 November | The deck needs a live-demo slide and a recorded backup clip |

---

## 3. The demo-data job (first task)

**The student will upload after the lab:**
- the Vivado log of the session (`demo.log` or a console copy);
- any new `hw_demo_*.csv` and `hw_selftest_*.csv`;
- section 8 of `docs/DEMO.md`, filled in (what the LEDs actually did);
- LED photos or video stills (badge for int16, int8, int4, empty; one swap with LD7 in frame).

**Tables to produce:**

| Table | Columns |
|---|---|
| Per command | step, command, expected output (from the briefing pack's demo script), observed output, match yes/no |
| LED legend | LED, expected behaviour, observed behaviour, confirmed yes/no |
| Swap time | operation, N, mean, standard deviation, min, max (ms), compared with the 2026-10-22 session (429.3 ms mean, N = 12) |
| Demo values | case, precision, elements matched / 16, notable value (for example C[0][2]) |

Then write **one crisp paragraph per demo act** (Act 1 "it works", Act 2 "swap while it runs", Act 3 "live saturation", Act 4 "full comparison and safety", Act 5 "the contrast"): what was shown, what it proves, any difference from the expectation. If a number in the new files differs from the briefing pack, the new file wins for that session; say so.

---

## 4. Writing style

- Crisp, plain language a layman can follow. Explain every technical term once, the first time it appears.
- Short paragraphs; tables over prose.
- No file paths or line numbers in the prose.
- No bracket tags such as [MEASURED].
- Never invent a number. Every figure must come from the briefing pack or a file the student uploads.
- Analogies are welcome: a house where one room is refurnished while people live in the rest; an assembly line; a thermometer that stops at its maximum.

---

## 5. Honest limits (never overstate)

- **Power is a Vivado vectorless estimate on the routed design, confidence Medium; not measured on the board.**
- No neural-network workload, no accuracy measurement.
- int4 did not get the full 9-case sweep on the board (5 case types in the self-test, 3 in the demo; the other 4 in simulation only).
- The swap-time prediction (about 1.42 s) was not met: 0.43 s measured, because the JTAG clock was faster than in T1.
- Fmax values are estimates from timing slack; only 100 MHz was built and tested.
- LED behaviour comes from the design until the final demo confirms it.
- One board, one JTAG speed, 12 timed swaps; swaps are driven from a laptop.

---

## 6. The numbers to quote

| Item | Value |
|---|---|
| Swappable-region LUTs, int16 / int8 / int4 / empty | 253 / 1,451 / 693 / 179 |
| Whole-design LUTs | 1,553 / 2,751 / 1,993 / 1,479 |
| DSP slices | 16 / 0 / 0 / 0 |
| Setup slack (WNS) at 100 MHz | +2.135 / +1.481 / +2.981 / +2.981 ns; hold slack +0.088 ns in all |
| Worst-path delay | 7.732 / 8.538 / 6.532 / 6.532 ns |
| Estimated Fmax = 1000 / (10 − WNS) | 127.1 / 117.4 / 142.5 / 142.5 MHz |
| Total power (estimate) | 0.135 / 0.127 / 0.124 / 0.116 W |
| Dynamic power (estimate) | 0.032 / 0.021 / 0.017 / 0.013 W |
| Partition pins | 180 (179 signals + clock) |
| Bitstreams | partial 585,559 B, full 4,045,666 B |
| Swap time | 429.3 ms mean (N = 12, sd 29.1, 411 to 518); full program 2,500.5 ms (N = 2) |
| Board session | 23 programs (19 partial, 4 full), 0 failures; self-test 14/14 steps; demo 144/144 values |

Everything else (T0, T1, demo per case, self-test rows, manifest, glossary) is in `BRIEFING_PACK.md`.

---

## 7. Ask the student first, then outline

**Questions (one numbered message, then wait):**
1. Is there a report or slide template, title page or required section order?
2. Slide count and demo slot length? PowerPoint or Google Slides?
3. Rubric weights (design, results, analysis, presentation, demo)?
4. Solo or group submission?
5. Is a statement about AI assistance required, and in what form?
6. Will the board and the laptop with Vivado be available at the demo? (Decides whether a recorded backup is essential.)
7. Does the course want a README or statement with the source upload?

**Report outline (2 pages).** Title and one-line abstract; motivation (3 to 4 lines); design with one block diagram (array, frozen interface, swappable region, swap protocol); implementation and verification (reference model, simulation, Vivado DFX flow, board); the results table (configuration, LUTs whole design, LUTs swappable region, DSPs, worst-path delay, estimated Fmax, total and dynamic power); analysis (DSP-versus-LUT trade, power ranking, swap time and why, static region undisturbed); limits and future work; conclusion.

**Deck outline (12 to 15 slides, speaker notes on each).** Title; motivation; the idea (swap precision, not circuits); the systolic array in one picture; precision and saturation (200 becomes 127, not −56); DFX in one picture (house analogy); architecture; how it was verified; the Vivado build (floorplan, parent and child runs; screenshots allowed); results table; live demo with LED legend; swap time analysis; limits; applications and future work; summary. Add a backup-clip slide.

---

## 8. Q&A seed

| Question | Key point of the answer |
|---|---|
| Why 16 DSPs? | 16 PEs (4×4), one multiply-accumulate each, one DSP slice each. int8 and int4 use LUTs on purpose, to show the DSP-versus-LUT trade. |
| Why not two int8 multiplies per DSP? | Considered and rejected: signed packing needs correction terms and gives no gain for a fixed 4×4. |
| Why is int4 only about 2.1× smaller than int8? | Adders, accumulators, registers and readout shrink less than the multipliers. |
| Why 18 bits for the int8 accumulator? | 4 × (−128)² = 65,536 needs 18 signed bits; int4 needs 10. |
| Why saturate instead of wrap? | Wrapping flips the sign (200 → −56 in 8 bits); saturating gives 127. |
| What does the decoupler do? | Forces the 45 output wires to safe values during a swap; the module is held in reset and starts are refused. |
| Why is swap time the same for every precision? | The partial file covers the whole fenced area, so it is 585,559 B whatever is inside. |
| Why was the swap faster than predicted? | JTAG ran at 15 MHz (about 10.9 Mbit/s effective); T1's clock was not recorded (about 3.3 Mbit/s effective). |
| Why the right part of clock region X1Y1? | A configuration column splits X1Y1; only the right part has DSP columns. |
| How do you know the tests can fail? | Three negative simulation builds and five negative mocks all fail as required. |
| Where does the power figure come from? | Vivado's vectorless estimate on the routed design, confidence Medium; static power (about 0.10 W) dominates; not measured on the board. |
| Why do int4 and empty have the same worst path? | It lies inside the VIO debug core in the static region, not in the module. |
| When does swapping pay off? | When a mode lasts many calculations: one 0.43 s swap equals about 2.9 million 4×4 products of 150 ns. |
| Does it speed up a neural network? | Not claimed; accuracy and measured power are future work (T3). |

---

## 9. Upload list

**Must have:** this file; `BRIEFING_PACK.md`; `docs/PROJECT_DETAIL.md`; the course material (assignment text, rubric, any template); the images wanted in the deck (see the figure inventory in the briefing pack); after the lab, the files in section 3.

**Optional:** `docs/DEMO.md` (the demo script and LED legend); `docs/t2/T2_Complete_Guide.md` (the long technical version); `submission/note.txt`.

---

## 10. Starter message to paste

```
I finished an FPGA project (Dynamic Precision-Scalable Systolic Array using DFX, ZedBoard) and need help with the deliverables. Read the attached HANDOFF.md first (it holds the exact course rules and the order of work), then BRIEFING_PACK.md (all facts and tables), then PROJECT_DETAIL.md.

Rules: use only numbers from these files or files I upload; follow the writing style in HANDOFF section 4; respect the limits in section 5. The report must obey the 2-page, 12-pt, single-spacing, no-code, no-waveform, no-Vivado-image rules and contain the LUT / delay / power table.

Start by asking me the questions in HANDOFF section 7 in one numbered message and wait. Then do the work in the order of HANDOFF section 1: first tabulate and explain my demo results from the files I upload, then the report text, then the deck with speaker notes, then (if needed) the upload statement. Show me each piece for approval before moving on. Finally run a Q&A session: one question at a time, then tell me how an examiner would judge my answer and give a model answer.
```
