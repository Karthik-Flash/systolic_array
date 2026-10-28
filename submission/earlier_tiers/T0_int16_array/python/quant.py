"""Width-parametric integer quantisation helpers.

All internal arithmetic happens in np.int64 (or plain Python int for the
scalar hex/pack helpers) so values never silently wrap the way a narrower
NumPy integer dtype would.
"""
from __future__ import annotations

import numpy as np

# Cached signed two's-complement ranges for the data widths this project
# actually quantises to. Wider widths (accumulator/output) fall back to the
# generic formula in _bounds().
LIMITS: dict[int, tuple[int, int]] = {
    16: (-32768, 32767),
    8: (-128, 127),
    4: (-8, 7),
}


def _bounds(w: int) -> tuple[int, int]:
    """Signed two's-complement (min, max) for width w."""
    if w in LIMITS:
        return LIMITS[w]
    return (-(1 << (w - 1)), (1 << (w - 1)) - 1)


def saturate(x: np.ndarray, w: int) -> tuple[np.ndarray, np.ndarray]:
    """Clip x to width w. Returns (clipped_int64, per-element overflow mask)."""
    lo, hi = _bounds(w)
    x64 = np.asarray(x, dtype=np.int64)
    overflow = (x64 < lo) | (x64 > hi)
    clipped = np.clip(x64, lo, hi).astype(np.int64)
    return clipped, overflow


def clip_to_width(x: np.ndarray, w: int) -> np.ndarray:
    """Clip x to width w, discarding the overflow mask."""
    clipped, _ = saturate(x, w)
    return clipped


def quantise(
    x_float: np.ndarray, w: int, scale: float | None = None
) -> tuple[np.ndarray, float]:
    """Symmetric per-tensor quantisation of x_float to width w.

    If scale is None it is derived from max(abs(x_float)) so the largest
    magnitude sample maps exactly to the width's positive limit.
    """
    x_float = np.asarray(x_float, dtype=np.float64)
    _, hi = _bounds(w)
    if scale is None:
        peak = float(np.max(np.abs(x_float)))
        scale = peak / hi if peak > 0 else 1.0
    q = np.round(x_float / scale).astype(np.int64)
    clipped = clip_to_width(q, w)
    return clipped, scale


def to_hex(x: int, bits: int) -> str:
    """Two's-complement hex string: lowercase, zero-padded, bits/4 chars."""
    mask = (1 << bits) - 1
    return format(int(x) & mask, f"0{bits // 4}x")


def pack_lanes(vals: "list[int] | np.ndarray", lane_bits: int) -> int:
    """Pack per-lane values into one int; vals[0] is the least-significant lane.

    Equivalent to the Verilog concatenation {v3, v2, v1, v0}.
    """
    mask = (1 << lane_bits) - 1
    packed = 0
    for idx, v in enumerate(vals):
        packed |= (int(v) & mask) << (idx * lane_bits)
    return packed
