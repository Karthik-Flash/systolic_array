"""Compare golden vs. simulated per-cycle accumulator traces for one test case.

Run from the project root: `python python/diff_trace.py --case <name>`.
Locates the first cycle/PE where trace.csv (golden) and sim_trace.csv (from
tb_array.v) diverge, to pin a failing sim to an exact cycle and PE.
"""
from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path


def load_csv(path: Path) -> tuple[list[str], list[list[int]]]:
    with path.open(newline="") as f:
        rows = list(csv.reader(f))
    header, body = rows[0], rows[1:]
    return header, [[int(v) for v in row] for row in body]


def grid(row: list[int], n: int) -> list[list[int]]:
    return [row[i * n : (i + 1) * n] for i in range(n)]


def print_grid(title: str, g: list[list[int]]) -> None:
    width = max(len(str(v)) for r in g for v in r)
    print(title)
    for r in g:
        print("  " + " ".join(f"{v:>{width}}" for v in r))


def mask_rows(gold: list[list[int]], sim: list[list[int]]) -> list[str]:
    return ["".join("." if g == s else "X" for g, s in zip(gr, sr)) for gr, sr in zip(gold, sim)]


def transpose(g: list[list[int]]) -> list[list[int]]:
    return [list(r) for r in zip(*g)]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--case", required=True)
    parser.add_argument("--dir", type=Path, default=Path("sim/vectors"))
    parser.add_argument("--n", type=int, default=4)
    args = parser.parse_args()

    case_dir = args.dir / args.case
    golden_path = case_dir / "trace.csv"
    sim_path = case_dir / "sim_trace.csv"

    print(f"case: {args.case}")
    print(f"golden: {golden_path}")
    print(f"sim:    {sim_path}\n")

    if not golden_path.exists():
        print(f"error: golden trace not found at {golden_path}")
        print("run python/gen_vectors.py first to generate it.")
        sys.exit(1)
    if not sim_path.exists():
        print(f"error: sim trace not found at {sim_path}")
        print("run the Vivado simulation first -- it is written by tb/tb_array.v.")
        sys.exit(1)

    gold_header, gold_rows = load_csv(golden_path)
    sim_header, sim_rows = load_csv(sim_path)

    if len(gold_rows) != len(sim_rows) or len(gold_header) != len(sim_header):
        print("shape mismatch -- the run was likely cut short:")
        print(f"  golden: {len(gold_rows)} rows x {len(gold_header)} cols")
        print(f"  sim:    {len(sim_rows)} rows x {len(sim_header)} cols")
        sys.exit(1)

    n = args.n
    for cycle, (grow, srow) in enumerate(zip(gold_rows, sim_rows)):
        if grow == srow:
            continue
        gg, sg = grid(grow[1:], n), grid(srow[1:], n)
        print(f"first divergence at cycle {cycle}\n")
        print_grid("golden:", gg)
        print()
        print_grid("sim:", sg)
        print()
        print("mask ('.' match, 'X' mismatch):")
        for line in mask_rows(gg, sg):
            print("  " + " ".join(line))
        if sg == transpose(gg):
            print("\nhint: sim grid is the TRANSPOSE of golden -- a transposed")
            print("row/col or acc index is the likely cause.")
        sys.exit(1)

    print(f"traces identical: {len(gold_rows)} cycles, {n * n} PEs")
    sys.exit(0)


if __name__ == "__main__":
    main()
