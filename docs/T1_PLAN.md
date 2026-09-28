# T1 Plan — DFX Mechanism Proof on the ZedBoard

**Project:** Precision-scalable systolic matrix multiplier (CS G553, BITS Hyderabad)
**Tier:** T1 — prove Dynamic Function eXchange (partial reconfiguration) works on *this* board, with *this* toolchain, before the datapath is put at risk in T2.
**Board / tools:** ZedBoard `xc7z020clg484-1`, Vivado 2022.2 **project mode**, Windows, repo at `D:\Projects\RC_Project\`
**Hard constraints:** PL-only (no PS, no ICAP controller, no UART). All control and observation through **VIO over JTAG**. Partial bitstreams loaded through **Hardware Manager over JTAG**.
**Baseline carried forward (do not change):** T0 int16 = 16 DSP48E1, 1,335 LUT, 665 FF, 0 BRAM, WNS +0.378 ns @ 100 MHz (UART system). VIO system: WNS +1.427 ns.

This file is the **single source of truth** for T1. Claude Code implements Sections 4–6 and the scripts in Section 9. You (the human) do Sections 7–8 in the Vivado GUI and on the board.

---

## 0. What T1 must prove (definition of done)

T1 is finished when **all** of these are true and recorded in `docs/T1_RESULTS.md`:

1. All simulations pass (`scripts/t1/run_sims.py` prints `ALL PASS`).
2. Three DFX configurations (`cfg_add`, `cfg_mul`, `cfg_grey`) implement with **timing met** at 100 MHz and **`pr_verify` passes** across them.
3. On the board, after programming the **full** bitstream (`cfg_add`): `rm_id = A1`, add test vectors correct.
4. After loading **only the partial** `rm_mul` bitstream over JTAG: `rm_id = B2`, multiply vectors correct, **and** the static region never stopped: the heartbeat LED kept blinking and `vio_uptime` kept counting up across the swap (it did not reset to ~0). This is the single most important observation of T1.
5. Swap back to `rm_add`, and to the greybox (`rm_id = 00`), both work, repeatedly.
6. Measured and recorded: full vs partial bitstream sizes, JTAG program time for each, per-config utilization (static, RP, Pblock), WNS/WHS per config.

The "static never stopped" proof is what separates partial reconfiguration from simply reprogramming the chip. Reprogramming the full bitstream resets `vio_uptime` to 0; loading a partial must not.

---

## 1. DFX in five minutes, mapped to our names

| DFX term | Meaning | Our T1 name |
|---|---|---|
| **Static region** | Logic that never changes and keeps running during a swap | everything in `top_dfx` except `U_RP` (VIO, reset sync, uptime/heartbeat, decoupler, LED drivers, clock) |
| **Reconfigurable Partition (RP)** | A hierarchical instance whose contents can be swapped | instance `U_RP` of module `rp_t1` |
| **Partition Definition (PD)** | Vivado's name for "the set of things that can live in this RP" | `pd_t1` |
| **Reconfigurable Module (RM)** | One concrete implementation of the RP | `rm_add` (file `rm_add.v`), `rm_mul` (file `rm_mul.v`) |
| **Greybox** | An empty RM: outputs tied to 0, used as a blank / low-power state | the greybox option of `pd_t1` |
| **Pblock** | A rectangle on the die that the RP is confined to; its frames are what the partial bitstream rewrites | `pblock_U_RP` |
| **Partition pins** | Fixed routing points where static wires meet RP wires; identical across all RMs | created automatically on every `rp_t1` port |
| **Configuration** | One full design = static + one RM choice per RP | `cfg_add`, `cfg_mul`, `cfg_grey` |
| **Parent / child runs** | Parent implements static + first RM and **locks** static; children reuse the locked static with other RMs | parent `impl_1` (`cfg_add`), children `child_0_impl_1` (`cfg_mul`), `child_1_impl_1` (`cfg_grey`) |
| **Full / partial bitstream** | Full = whole chip; partial = only the Pblock's frames | `top_dfx.bit` / `*_partial.bit` in each run folder |
| **Decoupling** | Static logic that isolates RP outputs while the RP is being rewritten (outputs are garbage mid-swap) | `dfx_decouple` + VIO `vio_decouple` |
| **`pr_verify`** | Checks that all configurations share an identical static (so any partial is safe on any full) | run in `scripts/t1/reports_t1.tcl` |

**The frozen-interface rule:** every RM of `pd_t1` has *exactly* the same module name (`rp_t1`) and *exactly* the same port list. That is what makes partition pins possible. T2 will apply the same rule to the precision variants.

---

## 2. T1 architecture

```
                                   top_dfx   (STATIC region)
 clk  (Y9, 100 MHz) ──IBUF/BUFG──►──────────────────────────────────────────────────────────── clk to all
 btn_rst (P16, BTNC, act-high) ─► rst_sync (2-FF) ─► sys_rst_n          (press = reset, release = run)

 ┌──────── vio_dfx  (JTAG) ─────────┐
 │ probe_out0  vio_decouple   [0]   │──┐
 │ probe_out1  vio_rm_rst     [0]   │──┤  rm_rst_n = sys_rst_n & ~vio_decouple & ~vio_rm_rst   (registered)
 │ probe_out2  vio_a        [15:0]  │──┼────────────────►┌─────────────────────────────────┐
 │ probe_out3  vio_b        [15:0]  │──┼────────────────►│  U_RP : rp_t1   (RECONFIGURABLE)│  confined to pblock_U_RP
 │                                  │  │                 │   rm_add  |  rm_mul  |  greybox │
 │ probe_in0   vio_y        [31:0]  │◄─┼──┐              └───┬──────────┬──────────┬───────┘
 │ probe_in1   vio_rm_id     [7:0]  │◄─┼──┤          y[31:0] │ rm_id[7:0]│ led_pat[3:0]
 │ probe_in2   vio_uptime   [31:0]  │◄─┼┐ │                  ▼          ▼          ▼
 └──────────────────────────────────┘  ││ │            ┌───────── dfx_decouple (registered) ─────────┐
                                       ││ └────────────│ decouple=1: y→0, rm_id→FF, led_pat→0        │
                                       ││              │ decouple=0: pass RM outputs through         │
            uptime (seconds counter) ──┘│              └─────────────────────────────────────────────┘
            heartbeat (1 Hz)            └── vio_decouple
 LEDs:  led[3:0] = RM pattern (after decoupler)   led[4] = 0 (reserved)
        led[5]   = decouple active                led[6] = RM held in reset (~rm_rst_n)   led[7] = heartbeat
```

### 2.1 The two RMs (deliberately "trivial but datapath-shaped")

The handoff suggested two LED patterns. T1 does that **and** gives each RM a tiny arithmetic datapath with the same shape as a PE (two signed 16-bit inputs, one 32-bit output), so T1 also rehearses the T2 situation: one RM uses a DSP48E1, the other uses none, and both must fit the same Pblock.

| | `rm_add` | `rm_mul` | greybox |
|---|---|---|---|
| `y` | `sext(a) + sext(b)` (signed, 32-bit) | `a * b` (signed 16×16 → 32) | 0 |
| `rm_id` | `8'hA1` | `8'hB2` | `8'h00` |
| `led_pat` | 4-bit binary up-counter (~6 Hz step) | walking one `0001→0010→0100→1000→…` | `0000` |
| DSP48E1 | **0** (forced with `use_dsp = "no"`) | **1** (forced with `use_dsp = "yes"`) | 0 |

`rm_id` values read through VIO: `A1` = add loaded, `B2` = mul loaded, `00` = greybox (or an RM held in reset), `FF` = decoupler active (RP outputs isolated).

### 2.2 The swap protocol (what the static logic guarantees)

1. Host sets `vio_decouple = 1` → decoupler forces safe outputs, **and** the RM is held in reset.
2. Host programs the partial bitstream over JTAG. Static keeps running (heartbeat, uptime, VIO).
3. Host sets `vio_decouple = 0` → the new RM leaves reset in a known state, outputs flow again.

Two independent mechanisms make the new RM start clean: `RESET_AFTER_RECONFIG` on the Pblock (the silicon re-initialises the Pblock's flops after the partial load) and the static-driven `rm_rst_n` held low during the swap. Either alone would work; together they make T1 robust against getting one of them wrong.

---

## 3. Names — locked

Use these exact names everywhere (RTL, Vivado GUI, scripts, docs). Changing any of them later breaks scripts.

| Thing | Name |
|---|---|
| Git branch | `t1-dfx` |
| Vivado project name | `t1_dfx` |
| Vivado project directory | `D:\Projects\RC_Project\vivado\t1_dfx\` (inside gitignored `vivado/`) |
| Part | `xc7z020clg484-1` (same as T0) |
| Top module / file | `top_dfx` / `rtl/t1/top_dfx.v` |
| RP instance / module | `U_RP` / `rp_t1` |
| Partition definition | `pd_t1` |
| RMs | `rm_add` (file `rtl/t1/rm/rm_add.v`), `rm_mul` (file `rtl/t1/rm/rm_mul.v`) — **both files declare `module rp_t1`** |
| Pblock | `pblock_U_RP` |
| Configurations | `cfg_add`, `cfg_mul`, `cfg_grey` |
| Implementation runs | `impl_1` → `cfg_add` (parent); `child_0_impl_1` → `cfg_mul`; `child_1_impl_1` → `cfg_grey` |
| Synthesis runs (auto) | `synth_1` (static), `rm_add_synth_1`, `rm_mul_synth_1`, `vio_dfx_synth_1` |
| VIO IP | `vio_dfx` (new core; do **not** reuse T0's `vio_0`) |
| Other static instances | `U_VIO` (vio_dfx), `U_RST` (rst_sync), `U_UP` (uptime), `U_DC` (dfx_decouple) |
| Constraint files | `constraints/top_dfx.xdc` (pins, clock), `constraints/top_dfx_pblock.xdc` (Pblock; written by Vivado) |
| Collected bitstreams | `bitstreams/t1/t1_full_add.bit`, `t1_full_add.ltx`, `t1_partial_add.bit`, `t1_partial_mul.bit`, `t1_partial_grey.bit`, `t1_full_mul.bit`, `t1_full_grey.bit`, `manifest.csv` |
| Git tags | `t1-rtl` (sims pass), `t1-built` (bitstreams + pr_verify pass), `t1-onboard` (swap proven on silicon) |

**Why a new Vivado project:** `Tools → Enable Dynamic Function eXchange` is **irreversible** for a project. Never enable it in the T0 project. T0 stays reproducible exactly as it was.

---

## 4. Repo structure after T1

T0 files stay exactly where they are and are **not modified** (T0 Vivado projects reference them by path). Everything new goes in `t1/` subfolders.

```
RC_Project/
├── rtl/
│   ├── pe.v array.v controller.v uart_rx.v uart_tx.v loader.v top.v top_vio.v    (T0 — FROZEN)
│   └── t1/
│       ├── top_dfx.v          static top: IO, VIO, rst_sync, uptime, decoupler, U_RP
│       ├── rst_sync.v         2-FF reset synchroniser (active-high button in, active-low out)
│       ├── uptime.v           seconds counter + 1 Hz heartbeat (TICK_DIV parameter)
│       ├── dfx_decouple.v     registered output isolator, parameterised (reused in T2)
│       └── rm/
│           ├── rm_add.v       module rp_t1  — RM "rm_add"
│           └── rm_mul.v       module rp_t1  — RM "rm_mul"
├── tb/
│   ├── (T0 benches — FROZEN)
│   └── t1/
│       ├── vio_dfx_stub.v     sim-only stand-in for the VIO IP (module vio_dfx) — NEVER add to Vivado
│       ├── tb_rp_t1.v         self-checking RM bench (compile once per RM: -DRM_ADD / -DRM_MUL)
│       └── tb_top_dfx.v       self-checking static+RM bench (compile once per RM)
├── constraints/
│   ├── top.xdc top_vio.xdc    (T0 — FROZEN)
│   ├── top_dfx.xdc            pins + clock (same pins as top_vio.xdc, port btn_rst)
│   └── top_dfx_pblock.xdc     header comment only; Vivado writes the Pblock into it
├── scripts/
│   └── t1/
│       ├── run_sims.py        builds + runs all T1 iverilog sims, prints ALL PASS / FAIL
│       ├── ooc_check.tcl      (optional) Vivado batch OOC synth of each RM → DSP/LUT/FF sanity
│       ├── reports_t1.tcl     Vivado batch: per-config timing/util/pblock reports + pr_verify
│       ├── collect_bitstreams.py  copies/renames bits from run dirs → bitstreams/t1/, writes manifest.csv
│       └── hw_t1.tcl          Hardware Manager procs: connect, program, swap, read VIO, t1_selftest
├── bitstreams/t1/             milestone bitstreams + manifest.csv (committed once at t1-onboard)
├── docs/
│   ├── T1_PLAN.md             this file
│   ├── T1_RESULTS.md          results template → filled after hardware run
│   └── t1_reports/            reports written by reports_t1.tcl and hw_t1.tcl (committed)
└── vivado/t1_dfx/             Vivado project (gitignored)
```

`.gitignore` additions: `sim/t1_build/`, `vivado*.jou`, `vivado*.log`, `*.str`, `.Xil/`. Do **not** ignore `bitstreams/`.

---

## 5. RTL specification (authoritative for Claude Code)

General rules for all T1 RTL:
- Verilog-2001, same style as T0 (synchronous, active-low `rst_n`, `always @(posedge clk)`), must compile in Icarus Verilog **and** Vivado 2022.2.
- No SystemVerilog, no `initial` blocks in synthesizable RTL, no latches.
- **Nothing inside an RM except fabric logic**: no IBUF/OBUF, no BUFG/MMCM, no VIO/ILA, no top-level ports, no `initial`. The RM receives an already-buffered `clk`.
- `top_dfx` instantiates `rp_t1` with **no parameter overrides** (RMs are synthesized out-of-context with their defaults).

### 5.1 `rtl/t1/rm/rm_add.v` and `rtl/t1/rm/rm_mul.v` — both `module rp_t1`

Frozen port list (identical, character for character, in both files):

```verilog
module rp_t1 #(
    parameter PRESCALE_W = 24                  // led_pat step every 2^24 cycles (~0.17 s @ 100 MHz); tb overrides
) (
    input  wire        clk,
    input  wire        rst_n,                  // synchronous, active low (driven by static)
    input  wire [15:0] a,                      // two's complement
    input  wire [15:0] b,                      // two's complement
    output reg  [31:0] y,                      // registered
    output wire [7:0]  rm_id,                  // RM signature
    output wire [3:0]  led_pat                 // RM LED pattern
);
```

Behaviour:
- `y` registered, reset to 0. `rm_add`: `y <= {{16{a[15]}},a} + {{16{b[15]}},b};` with `(* use_dsp = "no" *)` on the module. `rm_mul`: `y <= $signed(a) * $signed(b);` (explicit signed 32-bit product, same care as T0 `pe.v` about signedness) with `(* use_dsp = "yes" *)`.
- `rm_id` comes from an 8-bit register `id_q` marked `(* dont_touch = "true" *)`, reset to `8'h00`, loaded with `8'hA1` (add) / `8'hB2` (mul) every cycle out of reset. Reason: keeps every RP output pin driven by a real flop inside the RP rather than a constant (avoids constant-driven partition pins) and shows RM reset release in VIO.
- `led_pat`: free-running `PRESCALE_W`-bit prescaler; on wrap, step the pattern. `rm_add`: `pat <= pat + 1` (reset `0000`). `rm_mul`: walking one, `pat <= {pat[2:0], pat[3]}`, reset `4'b0001`, **and** if `pat == 4'b0000` load `4'b0001` (self-heal in case the RM ever starts with all-zero state).

Header comment in each file must say: "DFX RM `rm_add`/`rm_mul` for partition `pd_t1`. Port list is FROZEN — must match the other RM exactly."

### 5.2 `rtl/t1/rst_sync.v`

`module rst_sync (input wire clk, input wire btn_rst, output wire rst_n);` — two-flop synchroniser of `~btn_rst`. Assert immediately-ish, release synchronously. Button pressed (1) → `rst_n = 0`. Button released → design runs. (Fixes T0 bug #8 for good: the design runs without touching any button.)

### 5.3 `rtl/t1/uptime.v`

`module uptime #(parameter TICK_DIV = 100_000_000) (input clk, input rst_n, output reg [31:0] seconds, output reg heartbeat);`
- Counts clock cycles; every `TICK_DIV/2` cycles toggle `heartbeat`; every full `TICK_DIV` cycles `seconds <= seconds + 1`. Reset clears both.
- `seconds` is the "static never stopped" proof: it must keep increasing across a partial reconfiguration.

### 5.4 `rtl/t1/dfx_decouple.v`

```verilog
module dfx_decouple #(
    parameter W      = 44,                     // 32 y + 8 rm_id + 4 led_pat
    parameter [W-1:0] SAFE = {32'h0000_0000, 8'hFF, 4'b0000}
) (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         decouple,
    input  wire [W-1:0] rp_out,                // raw RP outputs {y, rm_id, led_pat}
    output reg  [W-1:0] safe_out               // registered
);
```
Reset → `SAFE`. `decouple=1` → `SAFE`. Otherwise `rp_out`. Generic on purpose: T2 reuses it with a different `W`.

### 5.5 `rtl/t1/top_dfx.v`

```verilog
module top_dfx #(parameter TICK_DIV = 100_000_000) (
    input  wire       clk,
    input  wire       btn_rst,                 // BTNC P16, active high
    output wire [7:0] led
);
```
Instances and nets (net names matter — they become the VIO probe names in Hardware Manager):
- `U_RST : rst_sync` → `sys_rst_n`
- `U_UP : uptime #(.TICK_DIV(TICK_DIV))` → `uptime_s[31:0]`, `heartbeat`
- `U_VIO : vio_dfx` with `.clk(clk)`, `.probe_in0(vio_y)`, `.probe_in1(vio_rm_id)`, `.probe_in2(vio_uptime)`, `.probe_out0(vio_decouple)`, `.probe_out1(vio_rm_rst)`, `.probe_out2(vio_a)`, `.probe_out3(vio_b)`. (Check `rtl/top_vio.v` for the exact VIO instantiation style used in T0.)
- Registered `rm_rst_n <= sys_rst_n & ~vio_decouple & ~vio_rm_rst;`
- `U_RP : rp_t1` with `.clk(clk)`, `.rst_n(rm_rst_n)`, `.a(vio_a)`, `.b(vio_b)`, `.y(rp_y)`, `.rm_id(rp_rm_id)`, `.led_pat(rp_led_pat)` — **no parameter override**.
- `U_DC : dfx_decouple` on `{rp_y, rp_rm_id, rp_led_pat}` → `{vio_y, vio_rm_id, led_pat_q}`; `decouple = vio_decouple`, `rst_n = sys_rst_n`.
- `assign vio_uptime = uptime_s;`
- LEDs: `led[3:0] = led_pat_q`, `led[4] = 1'b0`, `led[5] = vio_decouple`, `led[6] = ~rm_rst_n`, `led[7] = heartbeat`.

### 5.6 `constraints/top_dfx.xdc`

Same pins and standards as `constraints/top_vio.xdc`: `clk` Y9 LVCMOS33 + `create_clock -period 10.000 -name sys_clk`; `btn_rst` P16 **LVCMOS18**; `led[0..7]` T22 T21 U22 U21 V22 W22 U19 U14, LVCMOS33. No Pblock here.

### 5.7 `constraints/top_dfx_pblock.xdc`

Only a comment header: "Written by Vivado when pblock_U_RP is drawn (T1_PLAN §7.6). Implementation-only." The human sets it as the target constraint file before drawing.

---

## 6. Verification before Vivado (Claude Code runs these)

### 6.1 Expected values (Claude Code must re-derive these with Python before trusting them)

| a (hex) | b (hex) | a, b (dec) | `rm_add` y | `rm_mul` y |
|---|---|---|---|---|
| 0003 | 0004 | 3, 4 | 0000_0007 | 0000_000C |
| FFFD | 0004 | −3, 4 | 0000_0001 | FFFF_FFF4 |
| 0007 | FFFA | 7, −6 | 0000_0001 | FFFF_FFD6 |
| 7FFF | 7FFF | 32767, 32767 | 0000_FFFE | 3FFF_0001 |
| 8000 | 8000 | −32768, −32768 | FFFF_0000 | 4000_0000 |
| 8000 | 7FFF | −32768, 32767 | FFFF_FFFF | C000_8000 |
| 0000 | 0000 | 0, 0 | 0000_0000 | 0000_0000 |

The same vector table is used by `tb_rp_t1.v`, `tb_top_dfx.v` and `hw_t1.tcl` (on silicon). Keep them identical.

### 6.2 `tb/t1/tb_rp_t1.v`
Compiled twice (`-DRM_ADD` with `rm_add.v`, `-DRM_MUL` with `rm_mul.v`), `PRESCALE_W` overridden to 4. Checks: reset values (`y=0`, `rm_id=00`), `rm_id` after reset release (A1/B2), every vector in 6.1 (accounting for the 1-cycle output register), and the LED pattern sequence over ≥ 5 steps (binary count vs walking one). Prints `PASS tb_rp_t1 <RM>` or `FAIL ...` with details, then `$finish`.

### 6.3 `tb/t1/tb_top_dfx.v` + `tb/t1/vio_dfx_stub.v`
`vio_dfx_stub.v` declares `module vio_dfx` with the same ports as the IP (`clk`, `probe_in0[31:0]`, `probe_in1[7:0]`, `probe_in2[31:0]`, `probe_out0[0:0]`, `probe_out1[0:0]`, `probe_out2[15:0]`, `probe_out3[15:0]`); outputs are `reg`s initialised to 0 that the bench drives hierarchically (`dut.U_VIO.probe_out2 = 16'h0003;`). Top instantiated with `TICK_DIV = 100`. Compiled twice (add, mul). Checks:
1. Hold `btn_rst=1`, release → design runs; `led[6]=0`, `led[5]=0`.
2. All vectors of 6.1 through the VIO stub (account for RM + decoupler latency, ≥ 2 cycles).
3. `vio_rm_id` = A1/B2.
4. `vio_decouple=1` → `vio_y = 0`, `vio_rm_id = FF`, `led[3:0] = 0`, `led[5] = 1`, `led[6] = 1`. Release → values return.
5. `vio_uptime` increments once per 100 cycles and **keeps incrementing while decoupled** (static is independent of the RP).
6. `led[7]` toggles every 50 cycles.
7. `vio_rm_rst=1` → `led[6]=1`, `vio_rm_id=00`.

A real runtime swap cannot be simulated in Icarus; running the same bench against both RMs is the simulation-side equivalent. The on-silicon swap is tested by `hw_t1.tcl`.

### 6.4 `scripts/t1/run_sims.py`
Runs the four builds (tb_rp_t1 × {add, mul}, tb_top_dfx × {add, mul}) with `iverilog -g2005` → `vvp`, outputs in `sim/t1_build/`, scans for `PASS`/`FAIL`, prints a summary table and `ALL PASS`, non-zero exit on any failure.

### 6.5 Optional: `scripts/t1/ooc_check.tcl`
If Vivado is callable from the shell (`where vivado`, or `C:\Xilinx\Vivado\2022.2\bin\vivado.bat`), run from inside `vivado/` (so journals land in the gitignored folder): `synth_design -mode out_of_context -top rp_t1 -part xc7z020clg484-1` for each RM file, `report_utilization`. Expect `rm_add` 0 DSP, `rm_mul` 1 DSP. This catches DSP inference surprises before the GUI flow.

---

## 7. Vivado walkthrough (human, GUI) — Phase B

Prerequisite: Claude Code has finished Phase A (Section 12), `run_sims.py` says `ALL PASS`, branch `t1-dfx` is committed and tagged `t1-rtl`.

Throughout: **never tick "Copy sources into project"**. The project must reference the repo files in place, so every fix Claude Code makes is picked up.

### 7.1 Create the project
1. Vivado 2022.2 → **Create Project** → Name `t1_dfx`, Location `D:/Projects/RC_Project/vivado` (Vivado makes `vivado/t1_dfx/`). Tick "Create project subdirectory".
2. **RTL Project**, tick "Do not specify sources at this time".
3. Part: `xc7z020clg484-1` (same as T0). Finish.

### 7.2 Add sources (static + the FIRST RM only)
1. **Add Sources → Add or create design sources → Add Files**:
   `rtl/t1/top_dfx.v`, `rtl/t1/rst_sync.v`, `rtl/t1/uptime.v`, `rtl/t1/dfx_decouple.v`, **`rtl/t1/rm/rm_add.v`**.
   **Do NOT add `rm_mul.v` here.** Both RM files declare `module rp_t1`; adding both gives a duplicate-module error. `rm_mul.v` enters only through "Add Reconfigurable Module" (7.5).
   **Do NOT add anything from `tb/`** (in particular not `vio_dfx_stub.v`).
2. **Add Sources → Add or create constraints**: `constraints/top_dfx.xdc`, `constraints/top_dfx_pblock.xdc`.
3. In Sources, select `top_dfx_pblock.xdc` → Source File Properties → **untick "Synthesis"** (keep "Implementation"). Then right-click it → **Set as Target Constraint File**. (So the Pblock you draw later lands in this file and doesn't make synthesis stale.)
4. Confirm `top_dfx` is the top (bold). The hierarchy shows `U_VIO : vio_dfx` as missing — that's next.

### 7.3 Create the VIO core `vio_dfx`
**IP Catalog → search "VIO" → VIO (Virtual Input/Output)** (not IP Integrator).
- Component Name: `vio_dfx`
- General Options: Input Probe Count **3**, Output Probe Count **4**, Enable Input Probe Activity Detectors: off
- PROBE_IN Ports: PROBE_IN0 width **32**, PROBE_IN1 **8**, PROBE_IN2 **32**
- PROBE_OUT Ports: PROBE_OUT0 **1** (init 0), PROBE_OUT1 **1** (init 0), PROBE_OUT2 **16** (init 0), PROBE_OUT3 **16** (init 0)
- OK → Generate (Synthesis Options: Out of context per IP).

Equivalent Tcl (paste in the Tcl console instead, if you prefer):
```tcl
create_ip -name vio -vendor xilinx.com -library ip -version 3.0 -module_name vio_dfx
set_property -dict [list CONFIG.C_NUM_PROBE_IN {3} CONFIG.C_NUM_PROBE_OUT {4} \
  CONFIG.C_PROBE_IN0_WIDTH {32} CONFIG.C_PROBE_IN1_WIDTH {8} CONFIG.C_PROBE_IN2_WIDTH {32} \
  CONFIG.C_PROBE_OUT0_WIDTH {1} CONFIG.C_PROBE_OUT1_WIDTH {1} \
  CONFIG.C_PROBE_OUT2_WIDTH {16} CONFIG.C_PROBE_OUT3_WIDTH {16} \
  CONFIG.C_EN_PROBE_IN_ACTIVITY {0}] [get_ips vio_dfx]
generate_target all [get_ips vio_dfx]
create_ip_run [get_ips vio_dfx]
```
The VIO lives in the **static** region. Debug cores must never be inside an RM.

### 7.4 Turn the project into a DFX project
**Tools → Enable Dynamic Function eXchange…** → confirm the "cannot be undone" dialog. (No separate licence is needed in Vivado 2022.2; DFX has been included since 2019.1. If the menu item is missing or greyed out, stop and report it.)

A new entry **Dynamic Function eXchange Wizard** appears in the Flow Navigator under Project Manager.

### 7.5 Create the partition and add the second RM
1. Sources → Hierarchy → expand `top_dfx` → right-click **`U_RP : rp_t1 (rm_add.v)`** → **Create Partition Definition…**
   - Partition Definition Name: `pd_t1`
   - Reconfigurable Module Name: `rm_add`
   - OK. `U_RP` now shows a partition icon, and a **Partition Definitions** tab appears in Sources.
2. **Partition Definitions** tab → right-click `pd_t1` → **Add Reconfigurable Module…**
   - Reconfigurable Module Name: `rm_mul`
   - Add Files → `rtl/t1/rm/rm_mul.v` (Copy unticked)
   - Leave "Sources are already synthesized" unticked
   - Top module: `rp_t1`
   - OK. `pd_t1` now lists `rm_add` and `rm_mul`.

### 7.6 DFX Wizard: configurations and runs
Flow Navigator → **Dynamic Function eXchange Wizard** → Next.
1. **Edit Reconfigurable Modules:** confirm `rm_add`, `rm_mul` under `pd_t1`. Next.
2. **Edit Configurations:** click **"automatically create configurations"**. Rename them: the one using `rm_add` → `cfg_add`, the one using `rm_mul` → `cfg_mul`. Click **+** to add `cfg_grey`, and set its `U_RP` entry to **greybox**. Next.
3. **Edit Configuration Runs:** click **"automatically create configuration runs"**. Check the mapping is: `impl_1` → `cfg_add` (Parent: synth_1), `child_0_impl_1` → `cfg_mul` (Parent: impl_1), `child_1_impl_1` → `cfg_grey` (Parent: impl_1). Fix any row that differs. Next → Finish.

Result: `impl_1` implements static + `rm_add` and **locks** the static placement and routing; the two children import that locked static and only implement their RM inside the Pblock. That shared static is what makes any partial loadable on top of any full.

### 7.7 Synthesize
**Run Synthesis.** Vivado launches `synth_1` (static, with `U_RP` as a black box), `rm_add_synth_1`, `rm_mul_synth_1` (OOC), and `vio_dfx_synth_1`. When done, glance at each RM run's utilization: `rm_add` 0 DSP, `rm_mul` 1 DSP. If not, stop and report.

### 7.8 Floorplan: draw `pblock_U_RP`
1. **Open Synthesized Design.** Open the **Device** window.
2. **Netlist** window → right-click `U_RP` → **Floorplanning → Draw Pblock** → drag a rectangle.

Where and how big — the rules:
- **Full clock-region height.** The top and bottom edges of the rectangle sit exactly on the top and bottom of one clock region (the Device view outlines clock regions as `X?Y?`). On 7-series, `RESET_AFTER_RECONFIG` requires this vertical alignment.
- **Include at least one DSP column** (the tall thin columns of DSP48 sites). One DSP column over one clock-region height = **20 DSP48E1** — enough for T2's 16 PEs, so draw the T1 Pblock at T2 size and reuse it.
- **Width:** roughly 10 CLB columns plus that DSP column (≈ 4,000 LUTs). Far more than T1 needs, deliberately T2-sized, and it keeps partial bitstream sizes comparable between T1 and T2.
- **Stay off the device edges** (IO columns) and away from the PS corner. A region in the right half of the die (e.g. inside `X1Y1` or `X1Y0`) is a good first choice. The exact position is not critical for T1; DRC will tell you if it's illegal.
3. In **Pblock Properties** (select the Pblock):
   - Name: `pblock_U_RP`
   - General / Properties: tick **RESET_AFTER_RECONFIG**
   - If the property **SNAPPING_MODE** is offered, set it to **ON** (it nudges edges to legal reconfigurable-frame boundaries). If it isn't offered, just keep the edges exactly on the clock-region boundary.
   - Statistics tab: note LUT / FF / DSP / BRAM capacity for `T1_RESULTS.md`.
4. **Ctrl+S** (save constraints) → writes into `top_dfx_pblock.xdc`. Expect content shaped like:
   ```tcl
   create_pblock pblock_U_RP
   add_cells_to_pblock [get_pblocks pblock_U_RP] [get_cells -quiet [list U_RP]]
   resize_pblock [get_pblocks pblock_U_RP] -add {SLICE_X..Y..:SLICE_X..Y..}
   resize_pblock [get_pblocks pblock_U_RP] -add {DSP48_X..Y..:DSP48_X..Y..}
   resize_pblock [get_pblocks pblock_U_RP] -add {RAMB18_X..Y..:RAMB18_X..Y..}   (if a BRAM column is inside)
   set_property RESET_AFTER_RECONFIG true [get_pblocks pblock_U_RP]
   set_property SNAPPING_MODE ON [get_pblocks pblock_U_RP]
   ```
   If Vivado then marks synthesis out-of-date, right-click `synth_1` → **Force Up-to-Date** (Pblock constraints don't affect synthesis).

### 7.9 DFX design-rule check (before implementation)
With the synthesized design still open: **Reports → Report DRC** → in the rule deck list tick the **Dynamic Function eXchange** (a.k.a. partial reconfiguration) rules, plus defaults → OK. Require **0 errors**. Save the report (`docs/t1_reports/drc_dfx_synth.rpt`). Warnings about Pblock size or clock-region alignment are exactly what to fix now, not after routing.

### 7.10 Implement and generate all bitstreams
1. Flow Navigator → **Generate Bitstream**. In a DFX project this runs `impl_1` and, depending on the dialog, the child runs too.
2. Open the **Design Runs** tab. If `child_0_impl_1` / `child_1_impl_1` have not run: select both → right-click → **Generate Bitstream** (they wait for / reuse `impl_1`).
3. Every run must end with WNS ≥ 0, WHS ≥ 0, write_bitstream complete. Note WNS/WHS per run from the Design Runs table.
4. Each run folder `vivado/t1_dfx/t1_dfx.runs/<run>/` should contain `top_dfx.bit` (full) and one `*_partial.bit` (expected like `U_RP_rm_add_partial.bit`; exact prefix varies — the collector globs for it). `impl_1` also has `top_dfx.ltx` (debug probes). The greybox run's partial is the **blanking** bitstream.

**Consistency rule:** if `impl_1` is ever re-run, *all* child runs and *all* partials are stale and must be regenerated. Never mix bitstreams from different static builds. `collect_bitstreams.py` refuses stale sets.

### 7.11 Hand back to Claude Code (Phase C)
Give Claude Code the Phase C prompt (Appendix B). It runs `collect_bitstreams.py` and `reports_t1.tcl` (including `pr_verify`), fills the build half of `T1_RESULTS.md`, commits, tags `t1-built`.

---

## 8. On-board test (human) — Phase D

Board: ZedBoard powered, JTAG USB (J17) connected, boot jumpers as in T0 (JTAG mode). Nothing else attached.

### 8.1 Manual walkthrough (do this once, by hand, to *see* it)
1. **Open Hardware Manager → Open Target → Auto Connect.** Chain shows `arm_dap_0` and `xc7z020_1`.
2. **Program Device** → Bitstream `bitstreams/t1/t1_full_add.bit`, Debug probes `bitstreams/t1/t1_full_add.ltx` → Program.
   Expect: `led[7]` blinking at 1 Hz, `led[3:0]` binary counting, `led[5]`/`led[6]` off.
3. `hw_vio_1` dashboard → **+** → add all 7 probes. Set radix hex. Read `vio_rm_id = A1`. Set `vio_a = 0003`, `vio_b = 0004` → `vio_y = 0000_0007`. Note `vio_uptime` (e.g. `0000_0025` = 37 s).
4. **Decouple:** `vio_decouple = 1` → `led[5]` and `led[6]` on, `led[3:0]` off, `vio_rm_id = FF`, `vio_y = 0`.
5. **Swap:** Program Device → Bitstream `bitstreams/t1/t1_partial_mul.bit`, Debug probes **still** `t1_full_add.ltx` → Program. Watch `led[7]`: it must **never stop blinking**. Time it roughly.
6. Refresh the VIO dashboard (Refresh Device if probes look stale). **Release:** `vio_decouple = 0` → `vio_rm_id = B2`, `vio_y = 0000_000C` (3×4), `led[3:0]` now a walking one, and `vio_uptime` is **larger** than in step 3 (e.g. `0000_0041`), not reset.
   **This is T1.** Static untouched, RP swapped, over JTAG, PL-only.
7. Contrast: program the **full** `t1_full_add.bit` again → `vio_uptime` restarts near 0. Partial ≠ full, demonstrated.
8. Try `t1_partial_grey.bit` (decouple first) → after release `vio_rm_id = 00`, `vio_y = 0`, `led[3:0]` dark. Then `t1_partial_add.bit` → back to A1.

Take photos/screenshots of steps 3, 5 (heartbeat) and 6 for the report.

### 8.2 Automated self-test (`scripts/t1/hw_t1.tcl`)
In the Vivado Tcl console (Hardware Manager, target open or not):
```tcl
source D:/Projects/RC_Project/scripts/t1/hw_t1.tcl
t1_selftest
```
It programs the full `add` bitstream, then runs the swap sequence `mul → add → grey → mul → add` (decouple → program partial (timed) → release → all 6.1 vectors → rm_id check → uptime-monotonic check), repeats the full program 3× and each partial 5× for timing statistics, prints a PASS/FAIL table and writes `docs/t1_reports/hw_selftest_<timestamp>.csv`.

---

## 9. Scripts specification (Claude Code writes these)

### 9.1 `scripts/t1/collect_bitstreams.py`
- Run dir: `vivado/t1_dfx/t1_dfx.runs/`. Mapping: `impl_1 → add`, `child_0_impl_1 → mul`, `child_1_impl_1 → grey`.
- In each run dir: require exactly one `top_dfx.bit` and exactly one `*_partial.bit`; copy to `bitstreams/t1/t1_full_<rm>.bit` and `t1_partial_<rm>.bit`; copy `impl_1/top_dfx.ltx` → `t1_full_add.ltx`.
- **Staleness guard:** every child run's bitstreams must be newer than `impl_1`'s routed checkpoint (`impl_1/*_routed.dcp`); otherwise abort with a clear message ("static was rebuilt; regenerate child runs").
- Write `bitstreams/t1/manifest.csv`: `file, source_run, size_bytes, sha256, mtime`. Print sizes and partial/full ratio.

### 9.2 `scripts/t1/reports_t1.tcl` (Vivado batch)
Run from `vivado/`: `vivado -mode batch -source ../scripts/t1/reports_t1.tcl`. Resolve paths from `[info script]`. For each run (glob `*_routed.dcp`): `open_checkpoint`, then write into `docs/t1_reports/<cfg>_…rpt`: `report_timing_summary`, `report_utilization`, `report_utilization -hierarchical`, `report_utilization -pblocks [get_pblocks pblock_U_RP]`, `report_utilization -cells [get_cells U_RP]`; `close_design`. Then `pr_verify -full_check -initial <impl_1 routed dcp> -additional [list <child_0> <child_1>] -file docs/t1_reports/pr_verify.rpt`. Print a one-line summary per config (WNS, WHS, total LUT/FF/DSP, U_RP LUT/FF/DSP) and the pr_verify verdict.

### 9.3 `scripts/t1/hw_t1.tcl` (Hardware Manager)
- Root from `[info script]`; bitstream paths from `bitstreams/t1/`; forward slashes only.
- `t1_connect`: `open_hw_manager` (if needed), `connect_hw_server`, `open_hw_target`, pick `[get_hw_devices xc7z020_1]`, `current_hw_device`.
- `t1_program <bitfile>`: set `PROBES.FILE` and `FULL_PROBES.FILE` to `t1_full_add.ltx`, `PROGRAM.FILE` to the bit; time `program_hw_devices` with `clock milliseconds`; `refresh_hw_device`; return ms.
- Probe helpers using `get_hw_probes -of_objects [get_hw_vios -of_objects $dev]` filtered by `NAME =~ *vio_y*` etc. (robust to hierarchy prefixes). Writes: set `OUTPUT_VALUE_RADIX HEX`, `OUTPUT_VALUE`, then `commit_hw_vio`. Reads: `refresh_hw_vio`, `INPUT_VALUE_RADIX HEX`, `INPUT_VALUE`.
- `t1_swap <add|mul|grey>`: decouple=1 → program partial (timed) → decouple=0 → return ms.
- `t1_check <add|mul|grey>`: vectors of 6.1 (grey expects y=0), `rm_id` (A1/B2/00), returns pass/fail list.
- `t1_selftest`: as in 8.2; uptime read before and after every partial, must be non-decreasing; after a full program, record that uptime reset (expected). CSV + console table.
- Never call anything that could program the PS or touch `arm_dap_0`.

---

## 10. Measurements for `docs/T1_RESULTS.md`

Claude Code creates the template in Phase A and fills it in Phases C/D.

**Table A — Build (per configuration)**

| Config | WNS (ns) | WHS (ns) | Total LUT | Total FF | Total DSP | U_RP LUT | U_RP FF | U_RP DSP | Pblock util (LUT% / DSP%) |
|---|---|---|---|---|---|---|---|---|---|
| cfg_add | | | | | | | | 0 | |
| cfg_mul | | | | | | | | 1 | |
| cfg_grey | | | | | | | | 0 | |

Static cost (VIO + debug hub + static logic) = `cfg_grey` totals minus greybox tie-offs. Record the Pblock capacity (LUT/FF/DSP/BRAM) from the Statistics tab.

**Table B — Bitstreams**

| File | Size (bytes) | vs full |
|---|---|---|
| t1_full_add.bit | | 100% |
| t1_partial_add.bit | | |
| t1_partial_mul.bit | | |
| t1_partial_grey.bit | | |

**Table C — JTAG programming time (host wall-clock, mean ± sd over N)**

| Operation | N | ms |
|---|---|---|
| Full program | 3 | |
| Partial add / mul / grey | 5 each | |

Note for the report: over JTAG this is **cable-bound**, so time scales with bitstream size. It is an upper bound on swap latency, not the fabric's intrinsic reconfiguration time (an ICAP-based loader would be far faster; out of scope, PL-only via JTAG).

**Table D — Functional**: vectors pass per RM, `rm_id` per RM, uptime continuity across every partial (yes/no), uptime reset on full program (expected yes).

**Relation to the T0 baseline:** the T0 numbers (16 DSP / 1,335 LUT / 665 FF / +0.378 ns) stay as the historical anchor. Important for T2/T3: T0's 1,335 LUTs include UART, loader and controller. When the precision RMs are compared in T3, compare RM-to-RM inside the same DFX build (the int16 RM rebuilt as an RM is the like-for-like baseline), and cite T0 alongside.

---

## 11. Gotchas (read before the GUI session)

| # | Symptom | Cause | Fix |
|---|---|---|---|
| 1 | Want to undo DFX in a project | Enabling DFX is irreversible | Separate project `t1_dfx`; T0 project untouched |
| 2 | "Module rp_t1 already defined" | Both RM files added to sources | Only `rm_add.v` in sources; `rm_mul.v` via Add Reconfigurable Module |
| 3 | Edits in repo don't show in Vivado | "Copy sources into project" was ticked | Re-add files without copying |
| 4 | DRC errors about the RP | IO buffers, clock buffers or debug cores inside the RM | RMs contain fabric logic only; VIO stays in static |
| 5 | Warnings about constant-driven partition pins | An RM output tied to a constant | `rm_id` comes from a `dont_touch` flop; if another pin is flagged, report exact message |
| 6 | DRC on Pblock / RESET_AFTER_RECONFIG | Pblock not aligned to clock-region top/bottom, or overlaps IO/PS | Redraw full clock-region height, interior of die; or as a last resort untick RESET_AFTER_RECONFIG (the static `rm_rst_n` still resets the RM) |
| 7 | Partial loads but design misbehaves | Partial from a different static build | Re-generate all runs; use `collect_bitstreams.py` (staleness guard) |
| 8 | Partial loaded onto a blank / wrong chip | Partial needs the matching full already in the device | Program `t1_full_add.bit` first |
| 9 | VIO shows old values after a program | Dashboard not refreshed | Refresh Device / `refresh_hw_vio` |
| 10 | Probes missing after partial | Wrong or missing `.ltx` | Always use `t1_full_add.ltx` (VIO is static, so one `.ltx` serves all) |
| 11 | Design only runs while BTNC held | Reset polarity (T0 bug #8) | Handled in `rst_sync`: press = reset, released = run |
| 12 | `rm_id = 00` — greybox or reset? | Both read 00 | Check `led[6]`: on = RM held in reset; off = greybox loaded |
| 13 | Synthesis goes out-of-date after saving the Pblock | Target XDC used in synthesis | Untick "Synthesis" on `top_dfx_pblock.xdc`, or Force Up-to-Date |
| 14 | Paths break in Tcl | Backslashes / spaces | Forward slashes; no spaces (T0 bug #3) |

---

## 12. Phases, owners, milestones

| Phase | Owner | Output | Tag |
|---|---|---|---|
| A. RTL + benches + scripts + results template | Claude Code | sims `ALL PASS`, optional OOC DSP check | `t1-rtl` |
| B. Vivado DFX project, Pblock, DRC, bitstreams | Human (GUI, §7) | 3 configs routed, bitstreams present | — |
| C. Collect bitstreams, reports, pr_verify, fill Table A/B | Claude Code | `bitstreams/t1/`, `docs/t1_reports/`, `pr_verify` PASS | `t1-built` |
| D. On-board swap + `t1_selftest`, fill Table C/D, photos | Human + Claude Code | `hw_selftest_*.csv`, results complete | `t1-onboard` |

---

## 13. What T1 decides for T2 (write the answers into T1_RESULTS.md at the end)

1. **Pblock:** does the T2-sized `pblock_U_RP` (≥ 20 DSP, ~4k LUT, one clock-region tall) close timing and pass DRC? If yes, T2 reuses it unchanged.
2. **Partition boundary for T2 (to decide at T2 kickoff, informed by T1):** the natural RP is the whole 4×4 `array` (precision lives in the PEs; one RP, one Pblock; 16 separate per-PE RPs would be unmanageable). But the raw `array` interface is ~900 partition pins (`west_bus` 64 + `north_bus` 64 + `acc_bus` 768 + control). Moving the result select + `sat32` inside the RM shrinks that to ~150 (64 + 64 + `sel` 4 + `result` 32 + control). T1's partition-pin count and routing results tell us how much that matters.
3. **Frozen interface convention:** RMs keep int16-wide ports even for int8/int4 variants; quantisation happens inside the RM so the static side never changes.
4. **Decoupler:** `dfx_decouple` is reused with a new `W`/`SAFE`; the controller must also be prevented from starting a run while decoupled.
5. **Swap latency method:** T1's JTAG timing method (Table C) is the one T3 reports, clearly labelled as JTAG-bound.

---

## Appendix A — Claude Code prompt, Phase A (build everything that doesn't need Vivado)

```text
You are implementing T1 (DFX mechanism proof) of the systolic_array project.
The spec is docs/T1_PLAN.md — read it completely first; it is authoritative. Also read
rtl/top_vio.v, rtl/pe.v and constraints/top_vio.xdc to match T0 style, VIO instantiation
and pin constraints.

HARD RULES
- Do NOT modify any T0 file: rtl/*.v at the top level of rtl/, tb/*.v at the top level of tb/,
  constraints/top.xdc, constraints/top_vio.xdc, python/*. At the end,
  `git diff --name-status t0-onboard -- rtl tb constraints python` must list ONLY added (A)
  files under rtl/t1/, tb/t1/ and constraints/top_dfx*.xdc. New work lives only in the paths
  listed in T1_PLAN §4.
- Use the names in T1_PLAN §3 exactly. Both RM files declare `module rp_t1` with the
  identical frozen port list of §5.1.
- Verilog-2001 only; must compile with iverilog -g2005 and be synthesizable in Vivado 2022.2.
  No initial blocks in RTL. Nothing but fabric logic inside the RMs.
- vio_dfx_stub.v lives in tb/t1/ only and is sim-only.
- Paths have no spaces; Tcl uses forward slashes.

TASKS
0. `git status` must be clean; create and switch to branch `t1-dfx` from main.
1. Re-derive the §6.1 vector table with a short Python check (two's complement, 32-bit) and
   stop if any expected value in the plan is wrong.
2. Write RTL: rtl/t1/{top_dfx.v, rst_sync.v, uptime.v, dfx_decouple.v},
   rtl/t1/rm/{rm_add.v, rm_mul.v}  per §5.1–§5.5.
3. Write constraints/top_dfx.xdc (§5.6) and constraints/top_dfx_pblock.xdc (§5.7).
4. Write tb/t1/{vio_dfx_stub.v, tb_rp_t1.v, tb_top_dfx.v} per §6.2–§6.3 (self-checking,
   print PASS/FAIL, $finish).
5. Write scripts/t1/run_sims.py (§6.4) and run it until ALL PASS. If a bench fails, fix the
   RTL or bench and explain the root cause in one line per bug.
6. Optional §6.5: if Vivado 2022.2 is callable (try `where vivado`, then
   C:/Xilinx/Vivado/2022.2/bin/vivado.bat), write and run scripts/t1/ooc_check.tcl from inside
   vivado/ and report LUT/FF/DSP per RM (expect add 0 DSP, mul 1 DSP). If Vivado isn't
   callable, write the script anyway and say so.
7. Write (do not run — they need the built project / the board):
   scripts/t1/collect_bitstreams.py (§9.1), scripts/t1/reports_t1.tcl (§9.2),
   scripts/t1/hw_t1.tcl (§9.3). Python must at least pass `python -m py_compile`.
8. Create docs/T1_RESULTS.md from §10 (empty tables, plus a "T2 decisions" section from §13).
9. Update .gitignore per §4. Update README.md with a short "T1 — DFX (in progress)" section
   linking docs/T1_PLAN.md.
10. Show me: the new tree (only T1 paths), run_sims.py output, OOC numbers if any, and
    `git status`. Then commit in logical commits (rtl / tb+sims / scripts / docs) and tag
    `t1-rtl`. Do NOT push until I say so.

If anything in the plan is ambiguous or looks wrong for Vivado 2022.2 DFX, say so explicitly
and propose the fix instead of silently deviating.
```

## Appendix B — Claude Code prompt, Phase C (after the GUI build)

```text
Phase B is done: vivado/t1_dfx has impl_1 (cfg_add), child_0_impl_1 (cfg_mul) and
child_1_impl_1 (cfg_grey) all through write_bitstream. Per docs/T1_PLAN.md:
1. Run scripts/t1/collect_bitstreams.py. Show the manifest and partial/full size ratios.
2. From inside vivado/, run `vivado -mode batch -source ../scripts/t1/reports_t1.tcl`.
   Show per-config WNS/WHS, total and U_RP LUT/FF/DSP, Pblock utilization, and the
   pr_verify verdict. If pr_verify fails, stop and explain.
3. Fill Tables A and B of docs/T1_RESULTS.md from the reports (cite the report file for each
   number). Record the Pblock ranges from constraints/top_dfx_pblock.xdc.
4. Commit docs/t1_reports/, bitstreams/t1/, constraints/top_dfx_pblock.xdc, results; tag
   `t1-built`. Do not push until I say so.
```

## Appendix C — Claude Code prompt, Phase D (after the board run)

```text
I ran t1_selftest on the board; the CSV is in docs/t1_reports/. Also my manual observations:
<paste: heartbeat never stopped? uptime before/after swap values, photos taken>.
Fill Tables C and D of docs/T1_RESULTS.md (mean ± sd), write the "What T1 decides for T2"
answers (§13) from the build + board evidence, update README (T1 complete), commit, tag
`t1-onboard`, and push branch + tags after showing me the final diff summary.
```
