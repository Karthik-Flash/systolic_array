"""Generate golden test vectors for the 4x4 output-stationary systolic array.

Run from the project root: `python python/gen_vectors.py [options]`.
Writes one subdirectory per case under sim/vectors/ (default).
"""
from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path

import numpy as np

import golden
import quant

CASES = ["identity", "ones", "counting", "random", "extremes", "zeros"]


def _range(width: int) -> tuple[int, int]:
    """Signed range for width, using quant.LIMITS when cached."""
    return quant.LIMITS.get(width, (-(1 << (width - 1)), (1 << (width - 1)) - 1))


def make_matrices(
    case: str, n: int, k: int, width: int, seed: int
) -> tuple[np.ndarray, np.ndarray]:
    """Build the (A, B) pair -- shapes (n, k) and (k, n) -- for one named case."""
    rng = np.random.default_rng(seed)
    lo, hi = _range(width)
    if case == "identity":
        A = np.eye(n, k, dtype=np.int64)
        B = rng.integers(lo, hi + 1, size=(k, n)).astype(np.int64)
    elif case == "ones":
        A = np.ones((n, k), dtype=np.int64)
        B = np.ones((k, n), dtype=np.int64)
    elif case == "counting":
        A = np.array([[k * i + j + 1 for j in range(k)] for i in range(n)], dtype=np.int64)
        B = A.T.copy()
    elif case == "random":
        A = rng.integers(lo, hi + 1, size=(n, k)).astype(np.int64)
        B = rng.integers(lo, hi + 1, size=(k, n)).astype(np.int64)
    elif case == "extremes":
        A = np.full((n, k), lo, dtype=np.int64)
        B = np.full((k, n), lo, dtype=np.int64)
    elif case == "zeros":
        A = np.zeros((n, k), dtype=np.int64)
        B = np.zeros((k, n), dtype=np.int64)
    else:
        raise ValueError(f"unknown case {case!r}")
    return A, B


def write_lines(path: Path, values, bits: int) -> None:
    """Write one hex-encoded value per line."""
    path.write_text("\n".join(quant.to_hex(v, bits) for v in values) + "\n")


def dump_schedule(case: str, west: np.ndarray, north: np.ndarray) -> None:
    """Print the feed schedule as an aligned cycle x lane text table."""
    n = west.shape[1]

    def table(name: str, arr: np.ndarray, prefix: str) -> None:
        print(f"\n[{case}] {name} (rows=cycle, cols=lane):")
        print("cyc " + " ".join(f"{prefix}{c:<4}" for c in range(n)))
        for t, row in enumerate(arr):
            print(f"{t:>3} " + " ".join(f"{v:>5}" for v in row))

    table("feed_west", west, "i")
    table("feed_north", north, "j")


def write_case(
    case: str, n: int, k: int, width: int, seed: int, out_root: Path, dump: bool
) -> bool:
    """Generate and write every vector file for one case. Returns overflow flag."""
    data_w, acc_w, out_w = width, golden.ACC_W, golden.OUT_W
    A, B = make_matrices(case, n, k, width, seed)
    c_acc = golden.matmul_ref(A, B)
    c_out, ovf_mask = golden.matmul_out(A, B, out_w)
    west, north = golden.feed_schedule(A, B)
    _, trace = golden.simulate_array(A, B)
    T = west.shape[0]

    out_dir = out_root / case
    out_dir.mkdir(parents=True, exist_ok=True)

    write_lines(out_dir / "a.hex", A.flatten(), data_w)
    write_lines(out_dir / "b.hex", B.flatten(), data_w)
    write_lines(out_dir / "c_acc.hex", c_acc.flatten(), acc_w)
    write_lines(out_dir / "c_out.hex", c_out.flatten(), out_w)

    lane_w = n * data_w
    west_packed = [quant.pack_lanes(row, data_w) for row in west]
    north_packed = [quant.pack_lanes(row, data_w) for row in north]
    write_lines(out_dir / "feed_west.hex", west_packed, lane_w)
    write_lines(out_dir / "feed_north.hex", north_packed, lane_w)

    a_seq, b_seq, acc_seq = golden.pe_stream(A[0, :], B[:, 0])
    write_lines(out_dir / "pe_a.hex", a_seq, data_w)
    write_lines(out_dir / "pe_b.hex", b_seq, data_w)
    write_lines(out_dir / "pe_acc.hex", acc_seq, acc_w)

    with (out_dir / "trace.csv").open("w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["cycle"] + [f"acc_{i}_{j}" for i in range(n) for j in range(n)])
        for t in range(T + 1):
            writer.writerow([t] + trace[t].flatten().tolist())

    overflow = bool(ovf_mask.any())
    meta = {
        "n": n, "k": k, "data_w": data_w, "acc_w": acc_w, "out_w": out_w,
        "T": T, "seed": seed, "case": case, "overflow": overflow,
    }
    (out_dir / "meta.json").write_text(json.dumps(meta, indent=2) + "\n")

    if dump:
        dump_schedule(case, west, north)
    return overflow


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--case", choices=CASES + ["all"], default="all")
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--width", type=int, default=16)
    parser.add_argument("--n", type=int, default=4)
    parser.add_argument("--k", type=int, default=4)
    parser.add_argument("--out", type=Path, default=Path("sim/vectors"))
    parser.add_argument("--dump", action="store_true")
    args = parser.parse_args()

    cases = CASES if args.case == "all" else [args.case]
    for case in cases:
        overflow = write_case(case, args.n, args.k, args.width, args.seed, args.out, args.dump)
        print(f"wrote {args.out / case}  (overflow={overflow})")


if __name__ == "__main__":
    main()
