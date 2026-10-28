"""Collect T1 DFX bitstreams from the Vivado run dirs (T1_PLAN §9.1).

vivado/t1_dfx/t1_dfx.runs/{impl_1, child_0_impl_1, child_1_impl_1}
  -> bitstreams/t1/t1_full_<rm>.bit, t1_partial_<rm>.bit, t1_full_add.ltx
  -> bitstreams/t1/manifest.csv  (file, source_run, size_bytes, sha256, mtime)

Refuses a stale set: every run's bitstreams must be newer than impl_1's
routed checkpoint, otherwise static was rebuilt after the children ran.
Run from anywhere: python scripts/t1/collect_bitstreams.py
"""
import csv
import hashlib
import shutil
import sys
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RUNS = ROOT / "vivado" / "t1_dfx" / "t1_dfx.runs"
OUT = ROOT / "bitstreams" / "t1"
RUN_RM = {"impl_1": "add", "child_0_impl_1": "mul", "child_1_impl_1": "grey"}


def die(msg):
    sys.exit(f"ERROR: {msg}")


def one(run_dir, pattern):
    hits = sorted(run_dir.glob(pattern))
    if len(hits) != 1:
        die(f"{run_dir.name}: expected exactly one {pattern}, found {[h.name for h in hits]}")
    return hits[0]


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    if not RUNS.is_dir():
        die(f"{RUNS} not found -- build the t1_dfx project first (T1_PLAN sec. 7)")

    # staleness guard: newest routed checkpoint of the parent (static) run
    dcps = list((RUNS / "impl_1").glob("*_routed.dcp"))
    if not dcps:
        die("impl_1 has no *_routed.dcp -- parent run not implemented")
    static_mtime = max(p.stat().st_mtime for p in dcps)

    copies = []  # (src, dst name, run)
    for run, rm in RUN_RM.items():
        run_dir = RUNS / run
        if not run_dir.is_dir():
            die(f"run dir {run_dir} missing")
        full = one(run_dir, "top_dfx.bit")
        partial = one(run_dir, "*_partial.bit")
        for bit in (full, partial):
            if bit.stat().st_mtime < static_mtime:
                die(f"{run}/{bit.name} is older than impl_1's routed checkpoint: "
                    "static was rebuilt; regenerate child runs")
        copies += [(full, f"t1_full_{rm}.bit", run), (partial, f"t1_partial_{rm}.bit", run)]
    copies.append((one(RUNS / "impl_1", "top_dfx.ltx"), "t1_full_add.ltx", "impl_1"))

    OUT.mkdir(parents=True, exist_ok=True)
    rows = []
    for src, name, run in copies:
        dst = OUT / name
        shutil.copy2(src, dst)
        st = dst.stat()
        rows.append({"file": name, "source_run": f"{run}/{src.name}",
                     "size_bytes": st.st_size, "sha256": sha256(dst),
                     "mtime": datetime.fromtimestamp(st.st_mtime).isoformat(timespec="seconds")})

    with open(OUT / "manifest.csv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)

    full_add = next(r["size_bytes"] for r in rows if r["file"] == "t1_full_add.bit")
    print(f"{'file':<22} {'bytes':>10}  vs full_add")
    for r in rows:
        print(f"{r['file']:<22} {r['size_bytes']:>10}  {100 * r['size_bytes'] / full_add:6.1f}%")
    print(f"wrote {OUT / 'manifest.csv'}")


if __name__ == "__main__":
    main()
