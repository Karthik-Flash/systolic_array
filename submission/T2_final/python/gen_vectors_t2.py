"""Generate T2 vectors: sim/t2_vectors/<int16|int8|int4>/<case>/ (T2_PLAN sec. 7.3, 7.4).

Run from the project root: python python/gen_vectors_t2.py
Seeds are fixed per case (recorded in meta.json), so the output is reproducible.
"""
from __future__ import annotations

from pathlib import Path

import numpy as np

import golden_t2 as g

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "sim" / "t2_vectors"
CASES = ["identity", "ones", "zeros", "counting", "asym_small",
         "random_inrange", "random_full", "extremes_neg", "extremes_mix"]
SEEDS = {"identity": 21, "asym_small": 22, "random_inrange": 23, "random_full": 24}


def make(case: str, prec: str):
    """(A16, B16, seed) for one case; only random_inrange depends on the precision."""
    w = g.PRECISIONS[prec][0]
    seed = SEEDS.get(case)
    rng = np.random.default_rng(seed)
    if case == "identity":
        return np.eye(4, dtype=np.int64), rng.integers(-32768, 32768, (4, 4)), seed
    if case == "ones":
        return np.ones((4, 4), np.int64), np.ones((4, 4), np.int64), seed
    if case == "zeros":
        return np.zeros((4, 4), np.int64), np.zeros((4, 4), np.int64), seed
    if case == "counting":
        A = np.arange(1, 17, dtype=np.int64).reshape(4, 4)
        return A, A.T.copy(), seed
    if case == "asym_small":
        A, B = rng.integers(-8, 8, (4, 4)), rng.integers(-8, 8, (4, 4))
        assert not np.array_equal(A, B.T) and not np.array_equal(A @ B, B @ A)
        return A, B, seed
    if case == "random_inrange":
        rng = np.random.default_rng(seed + w)              # per-precision inputs
        lo, hi = -(1 << (w - 1)), (1 << (w - 1)) - 1
        A, B = rng.integers(lo, hi + 1, (4, 4)), rng.integers(lo, hi + 1, (4, 4))
        A[0, 0], B[0, 0] = lo, lo                          # the full range includes -2^(W-1)
        return A, B, seed + w
    if case == "random_full":
        return rng.integers(-32768, 32768, (4, 4)), rng.integers(-32768, 32768, (4, 4)), seed
    if case == "extremes_neg":
        return np.full((4, 4), -32768, np.int64), np.full((4, 4), -32768, np.int64), seed
    if case == "extremes_mix":
        return np.full((4, 4), -32768, np.int64), np.full((4, 4), 32767, np.int64), seed
    raise ValueError(case)


def main() -> None:
    for prec in g.PRECISIONS:
        for case in CASES:
            A, B, seed = make(case, prec)
            m = g.write_case(OUT / prec / case, A, B, prec, case, seed)
            print(f"wrote {prec}/{case:<15} any_ovf={m['any_ovf']!s:<5} clamped={m['n_clamped_inputs']}")


if __name__ == "__main__":
    main()
