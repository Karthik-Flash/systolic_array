#!/usr/bin/env python3
"""verify_bundle.py -- is bitstreams/t2 ready to carry to the lab?  (read-only, no Vivado needed)

    python scripts/t2/verify_bundle.py

Checks: 9 files present; sizes and sha256 match manifest.csv; every .bit has a Xilinx header;
4 fulls and 4 partials are each mutually distinct (catches a wrongly collected file);
partial sizes equal, full sizes equal; the .ltx names all 11 vio_* probes; nothing is gitignored.
Predictions P1/P2 (plan §12.1) are reported as held / not held but never fail the check.
Prints BUNDLE OK or BUNDLE FAIL and exits 0 / 1.
"""
import csv, hashlib, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
D = ROOT / "bitstreams" / "t2"
PRECS = ["int16", "int8", "int4", "grey"]
EXPECT = [f"t2_{k}_{p}.bit" for k in ("full", "partial") for p in PRECS] + ["t2_full_int16.ltx"]
PROBES = ["vio_decouple", "vio_rm_rst", "vio_start", "vio_sel", "vio_a", "vio_b",
          "vio_result", "vio_rm_id", "vio_uptime", "vio_flags", "vio_runs"]
MAGIC = b"\x00\x09\x0f\xf0\x0f\xf0\x0f\xf0\x0f\xf0\x00\x00\x01"
P1_PARTIAL, P2_FULL = 585560, 4045667


def sha256(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for c in iter(lambda: f.read(1 << 20), b""):
            h.update(c)
    return h.hexdigest()


def header_fields(p):
    """Return the design-name string from the .bit header, or None if the header is malformed."""
    with open(p, "rb") as f:
        b = f.read(256)
    if not b.startswith(MAGIC) or len(b) < 17 or b[13:14] != b"a":
        return None
    n = int.from_bytes(b[14:16], "big")
    return b[16:16 + n].rstrip(b"\x00").decode("ascii", "replace")


def main():
    fails, warns = [], []
    man = D / "manifest.csv"
    if not man.exists():
        print("BUNDLE FAIL: bitstreams/t2/manifest.csv missing (run collect_bitstreams.py)")
        return 1
    with open(man, newline="") as f:
        rows = {r["file"]: r for r in csv.DictReader(f)}

    for name in EXPECT:
        if name not in rows:
            fails.append(f"{name}: not listed in manifest.csv")
        if not (D / name).exists():
            fails.append(f"{name}: file missing")
    extra = sorted(p.name for p in D.iterdir() if p.is_file() and p.name not in EXPECT
                   and p.name not in ("manifest.csv", ".gitkeep"))
    if extra:
        warns.append(f"unexpected files in bitstreams/t2: {extra}")

    info = {}
    for name in EXPECT:
        p = D / name
        if not p.exists() or name not in rows:
            continue
        size, digest = p.stat().st_size, sha256(p)
        if size != int(rows[name]["bytes"]):
            fails.append(f"{name}: {size} B on disk, manifest says {rows[name]['bytes']}")
        if digest != rows[name]["sha256"]:
            fails.append(f"{name}: sha256 differs from manifest (file changed after collection)")
        design = None
        if name.endswith(".bit"):
            design = header_fields(p)
            if design is None:
                fails.append(f"{name}: not a Xilinx .bit file (bad header)")
        info[name] = (size, digest, design)

    for kind in ("full", "partial"):
        names = [f"t2_{kind}_{p}.bit" for p in PRECS if f"t2_{kind}_{p}.bit" in info]
        sizes = {info[n][0] for n in names}
        if len(sizes) > 1:
            (fails if kind == "full" else warns).append(f"{kind} sizes differ: {sorted(sizes)}")
        digs = [info[n][1] for n in names]
        if len(set(digs)) != len(digs):
            fails.append(f"two {kind} bitstreams are byte-identical: a wrong file was collected")

    ltx = D / "t2_full_int16.ltx"
    if ltx.exists():
        t = ltx.read_text(errors="ignore")
        miss = [n for n in PROBES if n not in t]
        if miss:
            warns.append(f".ltx lacks probe names {miss} (hw_t2.tcl will match by VIO port; use T2_ALIAS if it complains)")

    try:
        out = subprocess.run(["git", "check-ignore", "-v"] + [str(D / n) for n in EXPECT + ["manifest.csv"]],
                             cwd=ROOT, capture_output=True, text=True)
        if out.returncode == 0 and out.stdout.strip():
            fails.append("gitignored (would not be pushed): " + out.stdout.strip().replace("\n", "; "))
        elif out.returncode == 128:
            warns.append("not a git repo here; skipped the gitignore check")
    except FileNotFoundError:
        warns.append("git not found; skipped the gitignore check")

    print(f"{'file':22} {'bytes':>10}  {'sha256[:12]':12}  header design string")
    for n in EXPECT:
        if n in info:
            s, d, des = info[n]
            print(f"{n:22} {s:>10,}  {d[:12]:12}  {des if des else ''}")
    full_sz = {info[f't2_full_{p}.bit'][0] for p in PRECS if f't2_full_{p}.bit' in info}
    part_sz = {info[f't2_partial_{p}.bit'][0] for p in PRECS if f't2_partial_{p}.bit' in info}
    print(f"P1 partial = {P1_PARTIAL:,} B predicted: " + ("held" if part_sz == {P1_PARTIAL} else f"NOT held, measured {sorted(part_sz)}"))
    print(f"P2 full    = {P2_FULL:,} B predicted: " + ("held" if full_sz == {P2_FULL} else f"NOT held, measured {sorted(full_sz)}"))
    for w in warns:
        print("WARN:", w)
    for e in fails:
        print("FAIL:", e)
    print("BUNDLE FAIL" if fails else "BUNDLE OK")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
