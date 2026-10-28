# Dynamic Precision-Scalable Systolic Array using DFX

This project implements a 4×4 output-stationary systolic array for matrix multiplication, the core operation of neural-network inference, on a ZedBoard (Zynq-7020). Using Dynamic Function eXchange (DFX), the array's arithmetic precision (int16, int8 or int4) is hot-swapped at runtime inside a single reconfigurable partition while the rest of the design keeps running. Each precision is a partial bitstream behind one frozen interface: int16 uses DSP slices, while int8 and int4 use LUT fabric. Every variant is checked bit-exact against a Python golden model. One physical region therefore serves several accuracy and resource trade-offs, avoiding dedicated arrays for each precision.

## Status

| Tier | What | Status | Read |
|---|---|---|---|
| **T0** | 4×4 int16 systolic array: datapath, controller, UART system (sim), VIO bring-up (silicon) | ✅ complete | [T0 Complete Guide](docs/t0/T0_Complete_Guide.md) |
| **T1** | DFX mechanism proof: one reconfigurable partition, swap adder ↔ multiplier ↔ greybox over JTAG | ✅ complete on silicon | [T1 Complete Guide](docs/t1/T1_Complete_Guide.md) · [T1 Results](docs/t1/T1_RESULTS.md) |
| **T2** | Precision variants (int16 / int8 / int4 array) as reconfigurable modules in the T1 Pblock | ✅ complete on silicon | [T2 Complete Guide](docs/t2/T2_Complete_Guide.md) · [Project detail](docs/PROJECT_DETAIL.md) |
| T3 | Runtime precision control and measurement (optionally MNIST) | later | — |

Tags: `t0-datapath`, `t0-system`, `t0-onboard`, `t1-rtl`, `t1-built`, `t1-onboard`, `t2-rtl`, `t2-built`, `t2-onboard`.

## Headline numbers

**T0** (int16 array, 100 MHz; [details](docs/t0/T0_Complete_Guide.md#1-the-result-in-one-page)): 16 DSP48E1, 1,335 LUT, 665 FF (UART system), WNS +0.378 ns (UART) / +1.427 ns (VIO build). On silicon: VIO readout `C[0][2] = 110`, correct.

![T0 on-board VIO result](docs/t0/img/T0_screen.png)

**T1** (DFX; [details](docs/t1/T1_RESULTS.md)):

| | |
|---|---|
| Partial swap over JTAG | **1,424 ± 27 ms** (N = 15), vs full program 9,060 ± 73 ms (N = 3) |
| Partial bitstream | 585,560 B = **14.5%** of the full 4,045,667 B; the same for every module |
| Static region during swaps | uninterrupted on **15/15** swaps (uptime counter +2 s each; reset only by full programs) |
| Timing @ 100 MHz | WNS +4.304 / +3.501 / +4.304 ns (add / mul / grey), `pr_verify` PASS |
| Pblock (reused by T2) | right part of clock region X1Y1: 4,400 LUT, 8,800 FF, **40 DSP**, 10 BRAM |

**T2** (precision swap; [details](docs/t2/T2_Complete_Guide.md#20-what-the-numbers-mean)):

| | |
|---|---|
| Swappable region, LUTs | int16 **253** (+ 16 DSP) · int8 **1,451** · int4 **693** · empty 179 (0 DSP in int8 / int4 / empty) |
| Timing @ 100 MHz | WNS +2.135 / +1.481 / +2.981 / +2.981 ns (int16 / int8 / int4 / empty), WHS +0.088 ns, `pr_verify` PASS (180 partition pins) |
| Partial swap over JTAG (15 MHz) | **429.3 ms** mean (N = 12, sd 29.1, 411–518 ms), vs full program 2,500.5 ms (N = 2) |
| Partial bitstream | 585,559 B = **14.5%** of the full 4,045,666 B; the same for every module |
| On silicon | **14/14** self-test steps, **144/144** demo values bit-exact, 23 programs (19 partial, 4 full) without a failure |
| Power | 0.135 / 0.127 / 0.124 / 0.116 W total (int16 / int8 / int4 / empty): Vivado vectorless estimate, confidence Medium; not measured on the board |

## Repo map

```
rtl/            T0 Verilog (pe, array, controller, uart, loader, top, top_vio)
rtl/t1/         T1 static top + reconfigurable modules (rm/rm_add.v, rm/rm_mul.v)
rtl/t2/         T2 static top + int16 / int8 / int4 modules (rm/)
tb/  tb/t1/ tb/t2/  self-checking testbenches (T0 / T1 / T2)
constraints/    XDC: top.xdc, top_vio.xdc (T0); top_dfx*.xdc (T1); top_t2*.xdc (T2)
python/         golden models (T0, T2), quantisation helpers, vector generators, trace diff, UART host
sim/vectors/    golden test vectors for the T0 benches
sim/t2_vectors/ golden test vectors for T2, per precision and case
scripts/t1/ scripts/t2/  sims, OOC checks, project script, collectors, reports, board scripts + mocks
bitstreams/t1/ bitstreams/t2/  full + partial bitstreams, probes file, manifest.csv
docs/t0/        T0 guide (+ img/)
docs/t1/        T1 guide, results, original plan, board runbook, reports/, img/
docs/t2/        T2 guide, plan, board runbook, reports/, img/
docs/           PROJECT_DETAIL.md (whole project), DEMO.md (live demo script)
docs/handoff/   HANDOFF.md, BRIEFING_PACK.md (for the report and slides)
submission/     course source package: T2_final/ (self-contained final project), earlier_tiers/ (T0, T1), README.txt
vivado/         Vivado projects (gitignored; regenerate from sources)
```

## Quick start

Tools: Python 3 with NumPy, Icarus Verilog (`iverilog`, `vvp`), Vivado 2022.2. Paths must not contain spaces.

**Python setup (once):**
```
py -3 -m venv .venv
.\.venv\Scripts\python.exe -m pip install numpy
```

**T0: golden model and vectors**
```
python python/test_golden.py                          # model self-checks: 14/14 PASS
python python/gen_vectors.py --case all --seed 1      # writes sim/vectors/<case>/
python python/gen_vectors.py --case counting --dump   # one case, with the feed staircase printed
```
The T0 benches (`tb/*.v`) run in XSim or Icarus against `sim/vectors/`. The Vivado flow and board bring-up are in [T0 guide §12–14](docs/t0/T0_Complete_Guide.md#12-fpgas-and-the-vivado-flow).

**T1: DFX**
```
python scripts/t1/run_sims.py                         # 4 benches: ALL PASS
```
The DFX build in Vivado, bitstream collection and reports are in [T1 guide §8 and §13](docs/t1/T1_Complete_Guide.md#13-how-to-reproduce-t1-from-a-clean-clone). The committed bitstreams in `bitstreams/t1/` can be used directly. On the board (Vivado Tcl console; full steps in the [runbook](docs/t1/T1_BOARD_RUNBOOK.md)):
```tcl
source D:/Projects/RC_Project/scripts/t1/hw_t1.tcl
t1_connect ; t1_program full add ; t1_swap_demo mul ; t1_selftest
```
Dry run without a board: from `vivado/`, `vivado -mode batch -nojournal -nolog -source ../scripts/t1/hw_t1_mock.tcl` → `MOCK TESTS PASS`.

**T2: precision swap**
```
python python/test_golden_t2.py                       # ALL PASS
python scripts/t2/run_sims.py                         # 6 benches pass, 3 negative builds fail as expected
python scripts/t2/verify_bundle.py                    # BUNDLE OK
```
On the board: `source D:/Projects/RC_Project/scripts/t2/hw_t2.tcl`, then `t2_connect ; t2_program full int16 ; t2_set_precision int8 counting`. The full demo is in [DEMO.md](docs/DEMO.md). Dry run without a board (PowerShell, from `vivado/scratch_t2/`): `vivado -mode batch -nojournal -nolog -source ../../scripts/t2/hw_t2_mock.tcl` → `MOCK TESTS PASS`.

## Documentation

- [T0 guide](docs/t0/T0_Complete_Guide.md)
- [T1 guide](docs/t1/T1_Complete_Guide.md)
- [T2 Complete Guide](docs/t2/T2_Complete_Guide.md)
- [T2 board runbook and session record](docs/t2/T2_BOARD_RUNBOOK.md)
- [Project detail: the whole project, from scratch](docs/PROJECT_DETAIL.md)
- [Demo guide and LED legend](docs/DEMO.md)
- [Handoff for the report and slides](docs/handoff/) ([HANDOFF.md](docs/handoff/HANDOFF.md), [BRIEFING_PACK.md](docs/handoff/BRIEFING_PACK.md))
- [Submission source package index](submission/README.txt) (`submission/T2_final/` is the final project; T0 and T1 are under `submission/earlier_tiers/`)
