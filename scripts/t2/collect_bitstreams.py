#!/usr/bin/env python3
"""collect_bitstreams.py -- T2 run folders -> bitstreams/t2/ + manifest.csv (docs/t2/T2_PLAN.md §10.1)

    python scripts/t2/collect_bitstreams.py --dry-run     # check only
    python scripts/t2/collect_bitstreams.py               # check, copy, write manifest

Aborts (exit 1) if any staleness check fails. Never modifies the Vivado project.
"""
import argparse, csv, hashlib, os, shutil, sys
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RUNS = ROOT / "vivado" / "t2_dfx" / "t2_dfx.runs"
OUT = ROOT / "bitstreams" / "t2"
RUNMAP = [  # run, config, precision, partial name in the run folder
    ("impl_1",         "cfg_int16", "int16", "U_RP_rm_int16_partial.bit"),
    ("child_0_impl_1", "cfg_int8",  "int8",  "U_RP_rm_int8_partial.bit"),
    ("child_1_impl_1", "cfg_int4",  "int4",  "U_RP_rm_int4_partial.bit"),
    ("child_2_impl_1", "cfg_grey",  "grey",  "U_RP_greybox_partial.bit"),
]
SOURCES = (sorted((ROOT / "rtl" / "t2").rglob("*.v"))
           + [ROOT / "rtl" / "t1" / n for n in ("rst_sync.v", "uptime.v", "dfx_decouple.v")]
           + [ROOT / "rtl" / n for n in ("controller.v", "pe.v", "array.v")]
           + [ROOT / "constraints" / n for n in ("top_t2.xdc", "top_t2_pblock.xdc")])
PROBES = ["vio_decouple", "vio_rm_rst", "vio_start", "vio_sel", "vio_a", "vio_b",
          "vio_result", "vio_rm_id", "vio_uptime", "vio_flags", "vio_runs"]


def sha256(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def ts(p):
    return datetime.fromtimestamp(p.stat().st_mtime).strftime("%Y-%m-%d %H:%M:%S")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    errors, warns, plan = [], [], []

    if not RUNS.is_dir():
        print(f"FAIL: {RUNS} not found (has Phase B run?)")
        return 1
    parent_dcp = RUNS / "impl_1" / "top_t2_routed.dcp"
    for run, cfg, prec, partial in RUNMAP:
        d = RUNS / run
        log = d / "runme.log"
        dcp = d / "top_t2_routed.dcp"
        full = d / "top_t2.bit"
        part = d / partial
        missing = [p.name for p in (log, dcp, full, part) if not p.exists()]
        if missing:
            errors.append(f"{run}: missing {', '.join(missing)}")
            continue
        text = log.read_text(errors="ignore")
        if "write_bitstream completed successfully" not in text:
            errors.append(f"{run}: runme.log has no 'write_bitstream completed successfully'")
        for b in (full, part):
            if b.stat().st_mtime < dcp.stat().st_mtime:
                errors.append(f"{run}: {b.name} is older than {dcp.name}")
        if run != "impl_1" and parent_dcp.exists() and dcp.stat().st_mtime < parent_dcp.stat().st_mtime:
            errors.append(f"{run}: routed dcp older than the parent's (built against an old static?)")
        plan.append((full, OUT / f"t2_full_{prec}.bit", cfg, run))
        plan.append((part, OUT / f"t2_partial_{prec}.bit", cfg, run))

    # probes file: the full design's .ltx from impl_1 (the VIO is static)
    ltx = None
    for name in ("top_t2.ltx", "debug_nets.ltx"):
        if (RUNS / "impl_1" / name).exists():
            ltx = RUNS / "impl_1" / name
            break
    if ltx is None:
        errors.append("impl_1: no top_t2.ltx / debug_nets.ltx")
    else:
        plan.append((ltx, OUT / "t2_full_int16.ltx", "cfg_int16", "impl_1"))
        text = ltx.read_text(errors="ignore")
        absent = [p for p in PROBES if p not in text]
        print(f"probes file {ltx.name}: " + ("all 11 vio_* names present" if not absent
              else f"MISSING names {absent} -> hw_t2.tcl falls back to PROBE_PORT matching"))
        if absent:
            warns.append(f"ltx lacks {absent}")

    # out-of-date sources
    bits = [src for src, _, _, _ in plan if src.suffix == ".bit"]
    if bits:
        oldest = min(b.stat().st_mtime for b in bits)
        for s in SOURCES:
            if s.exists() and s.stat().st_mtime > oldest:
                errors.append(f"source newer than the oldest bitstream: {s.relative_to(ROOT)} (runs out of date)")

    sizes = {src.stat().st_size for src, dst, _, _ in plan if dst.name.startswith("t2_partial")}
    if len(sizes) > 1:
        warns.append(f"partial sizes differ: {sorted(sizes)}")

    print(f"{'source':58} -> {'collected':24} {'bytes':>10}  mtime")
    for src, dst, cfg, run in plan:
        print(f"{str(src.relative_to(ROOT)):58} -> {dst.name:24} {src.stat().st_size:>10,}  {ts(src)}")
    for w in warns:
        print("WARN:", w)
    for e in errors:
        print("FAIL:", e)
    if errors:
        print("STALENESS GUARD FAIL: nothing copied")
        return 1
    print("STALENESS GUARD PASS")
    if args.dry_run:
        print("dry run: nothing copied")
        return 0

    OUT.mkdir(parents=True, exist_ok=True)
    rows = []
    for src, dst, cfg, run in plan:
        shutil.copy2(src, dst)
        rows.append({"file": dst.name, "bytes": dst.stat().st_size, "sha256": sha256(dst),
                     "config": cfg, "source_run": run,
                     "source_path": str(src.relative_to(ROOT)).replace("\\", "/"), "mtime": ts(src)})
    with open(OUT / "manifest.csv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)
    print(f"collected {len(rows)} files -> {OUT.relative_to(ROOT)}/manifest.csv")
    return 0


if __name__ == "__main__":
    sys.exit(main())
