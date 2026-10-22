"""Self-tests of the T2 golden model and the generated vectors (T2_PLAN sec. 7.6).

Run from the project root after gen_vectors_t2.py: python python/test_golden_t2.py
Prints one line per check and ALL PASS; exits non-zero on any failure.
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np

import gen_vectors_t2 as gv
import golden_t2 as g

ROOT = Path(__file__).resolve().parents[1]
VEC = ROOT / "sim" / "t2_vectors"
T0 = ROOT / "sim" / "vectors"
fails = []


def check(name, cond, detail=""):
    print(f"{'ok  ' if cond else 'FAIL'} {name}{'' if cond else '  ' + str(detail)}")
    if not cond:
        fails.append(name)


def read(path, bits):
    return [g.from_hex(s, bits) for s in path.read_text().split()]


def c_out(prec, case):
    return read(VEC / prec / case / "c_out.hex", 32)


# 1. clamp_full (and quant.saturate == full-range clamp on a sweep)
check("clamp 200->127, -200->-128 @8", list(g.clamp_full(np.array([200, -200]), 8)) == [127, -128])
check("clamp 9->7, -9->-8 @4", list(g.clamp_full(np.array([9, -9]), 4)) == [7, -8])
sweep = np.arange(-32768, 32768, dtype=np.int64)
check("clamp int16 identity over full range", np.array_equal(g.clamp_full(sweep, 16), sweep))
for w in (8, 4):
    lo, hi = -(1 << (w - 1)), (1 << (w - 1)) - 1
    check(f"clamp_full == min(max(x,lo),hi) sweep @{w}",
          np.array_equal(g.clamp_full(sweep, w), np.minimum(np.maximum(sweep, lo), hi)))

# 2. accumulator bounds: extremes_neg needs exactly 2W+2 bits
for prec in ("int8", "int4"):
    w, acc_w, _ = g.PRECISIONS[prec]
    r = g.rm_reference(np.full((4, 4), -32768), np.full((4, 4), -32768), prec)
    check(f"{prec} extremes_neg needs exactly {acc_w} bits", r["acc_bits"] == acc_w, r["acc_bits"])
    check(f"{prec} 2W+1 = {2 * w + 1} bits would overflow", int(r["C"].max()) > (1 << (2 * w)) - 1)

# 3. control and discriminating cases
check("asym_small identical in all precisions",
      c_out("int16", "asym_small") == c_out("int8", "asym_small") == c_out("int4", "asym_small"))
check("random_full differs int16 vs int8", c_out("int16", "random_full") != c_out("int8", "random_full"))

# 4. int16 regression against every T0 case
for d in sorted(p for p in T0.iterdir() if p.is_dir()):
    A = np.array(read(d / "a.hex", 16)).reshape(4, 4)
    B = np.array(read(d / "b.hex", 16)).reshape(4, 4)
    got = [int(v) for v in g.rm_reference(A, B, "int16")["c_out"].flatten()]
    check(f"int16 == T0 c_out ({d.name})", got == read(d / "c_out.hex", 32))

# 5. probe packing
M = np.arange(-8, 8, dtype=np.int64).reshape(4, 4) * 1000
s = g.pack_probe256(M)
check("unpack(pack(M)) == M", np.array_equal(g.unpack_probe256(s), M))
check("last 4 digits are A[0][0]", s[-4:] == g.to_hex(M[0, 0], 16), s)
check("first 4 digits are A[3][3]", s[:4] == g.to_hex(M[3, 3], 16), s)
for prec in g.PRECISIONS:
    for case in gv.CASES:
        d = VEC / prec / case
        a = np.array(read(d / "a.hex", 16)).reshape(4, 4)
        ok = np.array_equal(g.unpack_probe256((d / "a_probe.hex").read_text().strip()), a)
        if not ok:
            check(f"a_probe.hex matches a.hex {prec}/{case}", ok)

# 6. hex round trip
for bits in (4, 8, 10, 16, 18, 32, 48):
    lo, hi = -(1 << (bits - 1)), (1 << (bits - 1)) - 1
    vals = [lo, lo + 1, -1, 0, 1, hi - 1, hi]
    check(f"hex round trip @{bits}", [g.from_hex(g.to_hex(v, bits), bits) for v in vals] == vals)

# 7. plan sec. 7.5 rows (from the generated files)
cnt16 = [30, 70, 110, 150, 70, 174, 278, 382, 110, 278, 446, 614, 150, 382, 614, 846]
cnt4 = [30, 66, 70, 70, 66, 159, 175, 175, 70, 175, 196, 196, 70, 175, 196, 196]
check("counting int16", c_out("int16", "counting") == cnt16)
check("counting int8", c_out("int8", "counting") == cnt16)
check("counting int4", c_out("int4", "counting") == cnt4)
check("counting C[0][2] 110/110/70", [c_out(p, "counting")[2] for p in ("int16", "int8", "int4")] == [110, 110, 70])
exp = {"extremes_neg": {"int16": (0x7FFFFFFF, 1), "int8": (65536, 0), "int4": (256, 0)},
       "extremes_mix": {"int16": (-0x80000000, 1), "int8": (-65024, 0), "int4": (-224, 0)}}
for case, per in exp.items():
    for prec, (v, o) in per.items():
        ovf = [int(x) for x in (VEC / prec / case / "ovf.hex").read_text().split()]
        check(f"{case} {prec} = {v} ovf {o}", c_out(prec, case) == [v] * 16 and ovf == [o] * 16)
r = g.rm_reference(np.full((4, 4), -32768), np.full((4, 4), -32768), "int16")
check("extremes_neg int16 exact 4294967296", int(r["C"][0, 0]) == 4294967296)
r = g.rm_reference(np.full((4, 4), -32768), np.full((4, 4), 32767), "int16")
check("extremes_mix int16 exact -4294836224", int(r["C"][0, 0]) == -4294836224)

# vectors exist: 3 precisions x 9 cases
n = sum((VEC / p / c / "meta.json").exists() for p in g.PRECISIONS for c in gv.CASES)
check("3 x 9 vector dirs", n == 27, n)

print("ALL PASS" if not fails else f"FAIL ({len(fails)}): {fails}")
sys.exit(1 if fails else 0)
