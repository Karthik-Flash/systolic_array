"""T2 precision-aware golden model (T2_PLAN sec. 7).

What every rp_t2 RM must reproduce bit for bit, for W in {16, 8, 4}:
  Aq, Bq = clamp_full(A16, W), clamp_full(B16, W)   (full two's-complement range)
  C      = Aq @ Bq exactly; every element must fit in signed ACC_W bits
  c_out  = sat32(C); ovf = (c_out != C)

Reuses the frozen T0 helpers: quant.saturate is the full-range clamp, golden.matmul_ref
the exact product, golden.feed_schedule the T0 staircase.
"""
from __future__ import annotations

import numpy as np

import golden
import quant

# prec -> (W, ACC_W, rm_id)
PRECISIONS = {"int16": (16, 48, 0x16), "int8": (8, 18, 0x08), "int4": (4, 10, 0x04)}
OUT_W = 32


def clamp_full(x: np.ndarray, w: int) -> np.ndarray:
    """Clamp to [-2^(w-1), 2^(w-1)-1] (saturate, never truncate)."""
    return quant.clip_to_width(x, w)


def min_signed_bits(v: int) -> int:
    """Smallest two's-complement width that holds v."""
    v = int(v)
    return (v if v >= 0 else ~v).bit_length() + 1


def rm_reference(A16: np.ndarray, B16: np.ndarray, prec: str) -> dict:
    """Golden result of RM `prec` for raw int16 lanes A16, B16 (4x4 each)."""
    w, acc_w, rm_id = PRECISIONS[prec]
    A16 = np.asarray(A16, dtype=np.int64)
    B16 = np.asarray(B16, dtype=np.int64)
    assert A16.min() >= -32768 and A16.max() <= 32767 and B16.min() >= -32768 and B16.max() <= 32767
    Aq, Bq = clamp_full(A16, w), clamp_full(B16, w)
    C = golden.matmul_ref(Aq, Bq)
    worst = max(min_signed_bits(v) for v in C.flatten())
    assert worst <= acc_w, f"{prec}: C needs {worst} bits > ACC_W {acc_w}"
    c_out, ovf = quant.saturate(C, OUT_W)
    return {
        "Aq": Aq, "Bq": Bq, "C": C, "c_out": c_out, "ovf": ovf.astype(np.int64),
        "n_clamped": int((Aq != A16).sum() + (Bq != B16).sum()), "acc_bits": worst,
    }


def to_hex(v: int, bits: int) -> str:
    """Two's complement at `bits`, ceil(bits/4) lowercase digits (quant.to_hex floors)."""
    return format(int(v) & ((1 << bits) - 1), f"0{(bits + 3) // 4}x")


def from_hex(s: str, bits: int) -> int:
    v = int(s, 16) & ((1 << bits) - 1)
    return v - (1 << bits) if v >> (bits - 1) else v


def pack_probe256(M: np.ndarray) -> str:
    """4x4 int16 -> 64-digit VIO probe string. M[i][j] at bits [16(4i+j) +: 16],
    so the first digit is M[3][3]'s top nibble and the last four are M[0][0]."""
    return format(quant.pack_lanes(np.asarray(M).flatten(), 16), "064x")


def unpack_probe256(s: str) -> np.ndarray:
    assert len(s) == 64, s
    v = int(s, 16)
    return np.array([from_hex(format((v >> (16 * k)) & 0xFFFF, "04x"), 16) for k in range(16)],
                    dtype=np.int64).reshape(4, 4)


def feed_lines(A16: np.ndarray, B16: np.ndarray) -> tuple[list[str], list[str]]:
    """T0 staircase on the RAW lanes (the RM clamps), packed as in sim/vectors/*/feed_*.hex."""
    west, north = golden.feed_schedule(np.asarray(A16, dtype=np.int64), np.asarray(B16, dtype=np.int64))
    return ([quant.to_hex(quant.pack_lanes(r, 16), 64) for r in west],
            [quant.to_hex(quant.pack_lanes(r, 16), 64) for r in north])


def write_case(out_dir, A16, B16, prec: str, case: str, seed) -> dict:
    """Write every sec. 7.4 file for one (precision, case) into out_dir. Returns meta."""
    import json
    from pathlib import Path

    w, acc_w, rm_id = PRECISIONS[prec]
    r = rm_reference(A16, B16, prec)
    # cross-check against the T0 cycle model on the clamped operands (asserts internally)
    golden.simulate_array(r["Aq"], r["Bq"])
    d = Path(out_dir)
    d.mkdir(parents=True, exist_ok=True)

    def lines(name, items):
        (d / name).write_text("\n".join(items) + "\n")

    lines("a.hex", [to_hex(v, 16) for v in np.asarray(A16).flatten()])
    lines("b.hex", [to_hex(v, 16) for v in np.asarray(B16).flatten()])
    lines("a_probe.hex", [pack_probe256(A16)])
    lines("b_probe.hex", [pack_probe256(B16)])
    west, north = feed_lines(A16, B16)
    lines("feed_west.hex", west)
    lines("feed_north.hex", north)
    lines("c_exact.hex", [to_hex(v, acc_w) for v in r["C"].flatten()])
    lines("c_out.hex", [to_hex(v, OUT_W) for v in r["c_out"].flatten()])
    lines("ovf.hex", [str(int(v)) for v in r["ovf"].flatten()])
    meta = {"prec": prec, "W": w, "ACC_W": acc_w, "rm_id": f"{rm_id:02x}", "case": case, "seed": seed,
            "any_ovf": bool(r["ovf"].any()), "n_clamped_inputs": r["n_clamped"]}
    (d / "meta.json").write_text(json.dumps(meta, indent=2) + "\n")
    return meta
