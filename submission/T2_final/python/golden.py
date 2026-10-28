"""Reference and cycle-accurate golden model for the output-stationary
systolic array.

A is (N, K), B is (K, N), C = A @ B is (N, N). Project defaults: N = K = 4,
DATA_W = 16, ACC_W = 48, OUT_W = 32. N and K are inferred from the shapes of
A and B in every function below.
"""
from __future__ import annotations

import numpy as np

import quant

DATA_W = 16
ACC_W = 48
OUT_W = 32


def matmul_ref(A: np.ndarray, B: np.ndarray) -> np.ndarray:
    """Exact int64 matrix product, no saturation."""
    return A.astype(np.int64) @ B.astype(np.int64)


def matmul_out(
    A: np.ndarray, B: np.ndarray, out_w: int = OUT_W
) -> tuple[np.ndarray, np.ndarray]:
    """matmul_ref then saturate to out_w bits. Returns (C, overflow_mask)."""
    C = matmul_ref(A, B)
    return quant.saturate(C, out_w)


def feed_schedule(A: np.ndarray, B: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Build the skewed west/north input streams fed into the array.

    west[t][i] = A[i][t-i] if 0 <= t-i < K else 0
    north[t][j] = B[t-j][j] if 0 <= t-j < K else 0
    T = 2*(N-1) + K cycles are needed to drain the last diagonal.
    """
    n, k = A.shape
    T = 2 * (n - 1) + k
    west = np.zeros((T, n), dtype=np.int64)
    north = np.zeros((T, n), dtype=np.int64)
    for t in range(T):
        for i in range(n):
            d = t - i
            if 0 <= d < k:
                west[t, i] = A[i, d]
        for j in range(n):
            d = t - j
            if 0 <= d < k:
                north[t, j] = B[d, j]
    return west, north


def simulate_array(A: np.ndarray, B: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Cycle-accurate N x N PE array simulation.

    Each PE(i, j) holds an accumulator plus registered a_out/b_out copies.
    Every cycle, all next-state values are computed from the CURRENT state
    and committed together, so no PE observes another PE's updated state
    within the same cycle. trace[t] is the accumulator grid BEFORE cycle t
    runs, so trace[T] holds the final result.
    """
    n = A.shape[0]
    west, north = feed_schedule(A, B)
    T = west.shape[0]
    acc = np.zeros((n, n), dtype=np.int64)
    a_reg = np.zeros((n, n), dtype=np.int64)
    b_reg = np.zeros((n, n), dtype=np.int64)
    trace = np.zeros((T + 1, n, n), dtype=np.int64)
    trace[0] = acc
    for t in range(T):
        a_in = np.zeros((n, n), dtype=np.int64)
        b_in = np.zeros((n, n), dtype=np.int64)
        for i in range(n):
            for j in range(n):
                a_in[i, j] = west[t, i] if j == 0 else a_reg[i, j - 1]
                b_in[i, j] = north[t, j] if i == 0 else b_reg[i - 1, j]
        acc = acc + a_in * b_in
        a_reg, b_reg = a_in, b_in
        trace[t + 1] = acc
    ref = matmul_ref(A, B)
    assert np.array_equal(acc, ref), "simulate_array diverged from matmul_ref"
    return acc, trace


def pe_stream(
    a_vec: np.ndarray, b_vec: np.ndarray, lead: int = 2, tail: int = 2
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Single-PE stimulus: `lead` zero cycles, the K pairs, then `tail` zeros.

    acc_seq[t] is the accumulator value after cycle t retires, so acc_seq is
    flat at zero during lead and flat at the final dot product during tail.
    """
    zeros_lead = np.zeros(lead, dtype=np.int64)
    zeros_tail = np.zeros(tail, dtype=np.int64)
    a_seq = np.concatenate([zeros_lead, np.asarray(a_vec, dtype=np.int64), zeros_tail])
    b_seq = np.concatenate([zeros_lead, np.asarray(b_vec, dtype=np.int64), zeros_tail])
    acc_seq = np.cumsum(a_seq * b_seq).astype(np.int64)
    return a_seq, b_seq, acc_seq
