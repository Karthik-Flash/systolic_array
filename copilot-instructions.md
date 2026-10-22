# Instructions for GitHub Copilot in this repository

**This file lives at the repo root (`copilot-instructions.md`), not in `.github/`.** Copilot only auto-loads `.github/copilot-instructions.md`, so every task prompt starts with "Read copilot-instructions.md first" and you must do that before anything else.

## What this project is

Dynamic Precision-Scalable Systolic Array using DFX: a 4x4 output-stationary systolic matrix multiplier on a ZedBoard (xc7z020clg484-1, Vivado 2022.2) whose arithmetic precision (int16 / int8 / int4) is swapped at runtime with Dynamic Function eXchange. Course project (CS G553). The human is the orchestrator and does every Vivado GUI and board step.

## Where the project stands

- T0 (4x4 int16 array on silicon), T1 (DFX swap on silicon, 15/15) and T2 (three precisions behind one frozen interface, on silicon, 14/14 self-test steps, 144/144 demo elements) are **complete and merged to `main`**. Tags: see `git tag --list` (includes `t1-onboard`, `t2-rtl`, `t2-built`, `t2-onboard`).
- Now: documentation and wrap-up. T3 (host-side quantisation, error-vs-int16 analysis, real workloads) is **future work**: do not start it and do not describe it as done.
- There are more lab sessions planned (demos). Hardware evidence collected so far is final; do not overwrite it.

## How to work here

1. Do exactly what the current task says, nothing more. No refactors, renames, reformatting or "cleanups" unless the task names them.
2. Before editing a file, say which file and why. After editing, show `git diff --stat`.
3. If a command fails or output differs from what the task says to expect: STOP, paste the command and its full output, and wait. Never "fix" a failure by editing RTL, constraints, Tcl or Python, and never re-run a failing command in a loop.
4. **Never invent a number.** Every figure written into a document must be copied from a file in the repo (log, report, CSV, source); name the file next to it. If a fact is not in the repo, write "not recorded in the repo" and list it under evidence gaps. Mark inferences as inferences.
5. Do not claim anything the project has not shown: no MNIST or accuracy results, no power or energy figures, no Fmax beyond the 100 MHz timing closure that was run, no on-board int4 coverage beyond what the CSVs and log show.
6. Ask before deleting any tracked file. Regenerable, git-ignored output may be deleted only when the task's cleanup rule allows it.

## Read-only (never modify unless the task names the exact file)

`rtl/**`, `constraints/**`, `tb/**`, `sim/**`, `python/**`, `scripts/**`, `bitstreams/**`, `docs/t0/**`, `docs/t1/**`, `docs/t2/T2_PLAN.md`, `docs/t2/ref/**`, `docs/t2/reports/**`, `docs/t2/img/**`, `.venv/`, `NOTE.txt`, and every folder under `vivado/` that is a Vivado project (`t2_dfx`, `t1_dfx`, `systolic_t0`).
Do not move or rename any file: scripts and documents reference these paths.

## Documentation you may write (only when a task asks)

`README.md`, `docs/t2/T2_Complete_Guide.md`, `docs/t2/T2_BOARD_RUNBOOK.md`, `docs/PROJECT_DETAIL.md` (later), and files the task creates. Style: teach from scratch, define each acronym at first use, explain why before how, show real code excerpts with `path:line` (never retyped from memory), keep tables sourced.

## Environment

- Windows. Run commands in **PowerShell**, not Git Bash. Python: `.\.venv\Scripts\python.exe`.
- Never run Vivado. The human runs every `vivado.bat` command. For Vivado/Tcl facts, read the repo's logs, reports and scripts.
- Vivado's Tcl is 8.5: no `lmap`, no `try`; hex strings never go through `expr`.

## Git rules

- Work on the branch the task names (documentation work: `docs-wrapup`, created from `main`). Never commit directly to `main`, never merge, rebase or amend, never `--force`.
- Before any commit run `git status --short` and add only the paths the task lists. Never `git add -A` or `git add .`.
- Never commit `vivado/`, `.Xil/`, `*.jou`, `*.dcp`, `*.vcd`, `sim/t2_build/`, `__pycache__/`.
- Create tags only when the task says so, with the exact name given. Push only when the task says so, and never push `main`.

## Style for answers

Short. Use the report format the task asks for. Paste command output verbatim; do not summarise i

# Instructions for GitHub Copilot in this repository

## What this project is

Dynamic Precision-Scalable Systolic Array using DFX: a 4x4 output-stationary systolic matrix multiplier on a ZedBoard (xc7z020clg484-1, Vivado 2022.2) whose arithmetic precision (int16 / int8 / int4) is swapped at runtime with Dynamic Function eXchange. Course project (CS G553). The human is the orchestrator and does every Vivado GUI and board step.

## How to work here

1. Do exactly what the current task says, nothing more. No refactors, renames, reformatting, "cleanups" or dependency changes unless the task names them.
2. Before editing any file, say which file and why. After editing, show `git diff --stat`.
3. If a command fails or output is not what the task says to expect: STOP, paste the command and its full output, and wait. Never "fix" a failure by editing RTL, constraints, Tcl or Python scripts, and never re-run a failing command in a loop.
4. Never invent a number. Every figure you write into a document must be copied from a log, report or CSV that exists in the repo; name the file.
5. Ask before deleting anything. Never delete tracked files.

## Never modify (read-only unless the task explicitly names the file)

`rtl/**`, `constraints/**`, `tb/**`, `sim/**`, `python/**`, `scripts/**`, `bitstreams/**` (the collect script writes it, you do not), `docs/t0/**`, `docs/t1/**`, `docs/t2/T2_PLAN.md`, `vivado/**`, `.venv/`, `NOTE.txt`. Do not move or rename any file: scripts and docs hardcode these paths.

## Environment

- Windows. Run commands in **PowerShell**, not Git Bash. Python: `.\.venv\Scripts\python.exe`.
- Never run Vivado. The human runs every `vivado.bat` command.
- Vivado's Tcl is 8.5: no `lmap`, no `try`; hex strings never go through `expr`.

## Git rules

- Work on branch `t2-precision`. Never commit to `main`, never merge, rebase or amend, never `--force`.
- Before any commit run `git status --short` and commit only the paths the task lists. Never `git add -A` or `git add .`.
- Never commit `vivado/`, `.Xil/`, `*.jou`, `*.log` outside `docs/`, `*.dcp`, `*.vcd`, `sim/t2_build/`, `__pycache__/`.
- Tags are only created when the task says so, with the exact name given.
- Push only when the task says so: `git push origin <branch>` and `git push origin <tag>`.

## Style for answers

Short. Report in the format the task asks for. Paste command output verbatim; do not summarise it.
