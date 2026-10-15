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
