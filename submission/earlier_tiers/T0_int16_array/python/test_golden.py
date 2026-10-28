"""Plain-assert regression tests for golden.py, quant.py and gen_vectors.py.

Run directly: `python python/test_golden.py` (no pytest required).
"""
from __future__ import annotations

import sys
import tempfile
from pathlib import Path

import numpy as np

import gen_vectors
import golden
import quant

RESULTS: list[tuple[str, bool]] = []


def check(name: str, condition: bool) -> None:
    RESULTS.append((name, bool(condition)))
    print(f"[{'PASS' if condition else 'FAIL'}] {name}")


def test_identity() -> None:
    rng = np.random.default_rng(1)
    B = rng.integers(-32768, 32768, size=(4, 4)).astype(np.int64)
    I = np.eye(4, dtype=np.int64)
    check("identity: matmul_ref(I, B) == B", np.array_equal(golden.matmul_ref(I, B), B))


def test_random_matmul(n_cases: int = 500) -> None:
    rng = np.random.default_rng(2)
    ok = True
    for _ in range(n_cases):
        A = rng.integers(-32768, 32768, size=(4, 4)).astype(np.int16)
        B = rng.integers(-32768, 32768, size=(4, 4)).astype(np.int16)
        ref = A.astype(np.int64) @ B.astype(np.int64)
        ok &= np.array_equal(golden.matmul_ref(A, B), ref)
    check(f"matmul_ref matches int64 numpy reference ({n_cases} random cases)", ok)


def test_simulate_matches_ref(n_cases: int = 500) -> None:
    rng = np.random.default_rng(3)
    ok = True
    for _ in range(n_cases):
        A = rng.integers(-32768, 32768, size=(4, 4)).astype(np.int64)
        B = rng.integers(-32768, 32768, size=(4, 4)).astype(np.int64)
        acc_final, _ = golden.simulate_array(A, B)
        ok &= np.array_equal(acc_final, golden.matmul_ref(A, B))
    check(f"simulate_array final acc matches matmul_ref ({n_cases} random cases)", ok)


def test_feed_schedule() -> None:
    n, k = 4, 4
    rng = np.random.default_rng(4)
    A = rng.integers(-32768, 32768, size=(n, k)).astype(np.int64)
    B = rng.integers(-32768, 32768, size=(k, n)).astype(np.int64)
    west, north = golden.feed_schedule(A, B)
    T = west.shape[0]
    west_slots = sum(1 for t in range(T) for i in range(n) if 0 <= t - i < k)
    north_slots = sum(1 for t in range(T) for j in range(n) if 0 <= t - j < k)
    check("feed_schedule: exactly N*K injection slots on west", west_slots == n * k)
    check("feed_schedule: exactly N*K injection slots on north", north_slots == n * k)
    west_edges_zero = all(
        west[t, i] == 0 for t in range(T) for i in range(n) if t < i or t >= i + k
    )
    north_edges_zero = all(
        north[t, j] == 0 for t in range(T) for j in range(n) if t < j or t >= j + k
    )
    check("feed_schedule: west is zero outside its valid window", west_edges_zero)
    check("feed_schedule: north is zero outside its valid window", north_edges_zero)


def test_extremes_overflow() -> None:
    A, B = gen_vectors.make_matrices("extremes", 4, 4, 16, seed=7)
    c_out, ovf_mask = golden.matmul_out(A, B, 32)
    check("extremes: overflow mask is all True", bool(ovf_mask.all()))
    check("extremes: c_out saturates to 0x7fffffff", bool(np.all(c_out == 0x7FFFFFFF)))


def test_pe_stream() -> None:
    rng = np.random.default_rng(5)
    a_vec = rng.integers(-100, 100, size=4).astype(np.int64)
    b_vec = rng.integers(-100, 100, size=4).astype(np.int64)
    a_seq, b_seq, acc_seq = golden.pe_stream(a_vec, b_vec, lead=2, tail=2)
    dot = int(np.dot(a_vec, b_vec))
    check("pe_stream: acc_seq[-1] == dot(a_vec, b_vec)", int(acc_seq[-1]) == dot)
    check("pe_stream: acc_seq is flat (zero) during lead", bool(np.all(acc_seq[:2] == 0)))


def test_hex_roundtrip() -> None:
    ok = True
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        for case in gen_vectors.CASES:
            A, B = gen_vectors.make_matrices(case, 4, 4, 16, seed=7)
            gen_vectors.write_case(case, 4, 4, 16, seed=7, out_root=root, dump=False)

            def read_signed(path: Path) -> list[int]:
                vals = [int(h, 16) for h in path.read_text().split()]
                return [v - 0x10000 if v >= 0x8000 else v for v in vals]

            a_back = read_signed(root / case / "a.hex")
            b_back = read_signed(root / case / "b.hex")
            ok &= a_back == A.flatten().tolist()
            ok &= b_back == B.flatten().tolist()
    check("hex round-trip: re-parsed .hex files match in-memory arrays", ok)


def test_to_hex_known_values() -> None:
    check("to_hex(-1, 16) == 'ffff'", quant.to_hex(-1, 16) == "ffff")
    check("to_hex(-32768, 16) == '8000'", quant.to_hex(-32768, 16) == "8000")


def main() -> None:
    test_identity()
    test_random_matmul()
    test_simulate_matches_ref()
    test_feed_schedule()
    test_extremes_overflow()
    test_pe_stream()
    test_hex_roundtrip()
    test_to_hex_known_values()

    passed = sum(1 for _, ok in RESULTS if ok)
    total = len(RESULTS)
    print(f"\n{passed}/{total} checks passed")
    print("PASS" if passed == total else "FAIL")
    sys.exit(0 if passed == total else 1)


if __name__ == "__main__":
    main()
