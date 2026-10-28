"""Build and run every T2 bench (T2_PLAN sec. 8.2).

Simulator: Vivado 2022.2 XSim (xvlog -> xelab -> xsim) for all builds -- the installed
Icarus is v0.9.7, which cannot parse T0's rtl/array.v (2-D net arrays); see plan sec. 16.
Icarus is still used as a lint (iverilog -g2005 -Wall, compile only) on every build
that does not contain rtl/array.v.

  positive : tb_rp_t2 x 3 RMs, tb_top_t2 x 3 RMs        -> ALL PASS, 0 warnings
  negative : N1 tb_rp_t2 expects int8, built with rm_int16 files
             N2 tb_rp_t2 expects int4, built with rm_int8 files
             N3 tb_top_t2 +NEG_UNGATED (start gate forced open)  -> each must FAIL
  port list: the rp_t2 port declarations of the three RM files are identical

File lists come only from scripts/t2/t2_filesets.tcl. Outputs: sim/t2_build/<build>/,
docs/t2/reports/sim_summary.txt, docs/t2/reports/sim_cycles.csv.
Run from anywhere: python scripts/t2/run_sims.py
"""
import csv
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BUILD = ROOT / "sim" / "t2_build"
REPORTS = ROOT / "docs" / "t2" / "reports"
VIVADO_BIN = Path("C:/Xilinx/Vivado/2022.2/bin")      # calibration knob: Vivado install
STUB = "tb/t2/vio_t2_stub.v"
PREC_OF = {"rm_int16": "INT16", "rm_int8": "INT8", "rm_int4": "INT4"}


def filesets():
    """Parse `set ::NAME {...}` / `set ::NAME(key) {...}` from t2_filesets.tcl."""
    text = (ROOT / "scripts" / "t2" / "t2_filesets.tcl").read_text()
    out = {}
    for name, key, val in re.findall(r"^set ::(\w+)(?:\((\w+)\))?\s+\{([^{}]*)\}", text, re.M):
        out[(name, key or None)] = val.split()
    return out


FS = filesets()
STATIC = FS[("T2_STATIC_FILES", None)]
RM_FILES = {rm: FS[("T2_RM_FILES", rm)] for rm in FS[("T2_RMS", None)]}


def ordered(files):
    # files with a `timescale first, so xvlog never sees a module before any timescale
    return sorted(files, key=lambda f: "`timescale" not in (ROOT / f).read_text())


def build_list():
    b = []
    for rm in RM_FILES:
        p = PREC_OF[rm]
        b.append(dict(name=f"tb_rp_t2_{rm}", top="tb_rp_t2", defs=[f"PREC_{p}"],
                      srcs=["tb/t2/tb_rp_t2.v"] + RM_FILES[rm], kind="pos", rm=rm))
    for rm in RM_FILES:
        p = PREC_OF[rm]
        b.append(dict(name=f"tb_top_t2_{rm}", top="tb_top_t2", defs=[f"PREC_{p}"],
                      srcs=["tb/t2/tb_top_t2.v", STUB] + STATIC + RM_FILES[rm], kind="pos", rm=rm))
    b.append(dict(name="N1_rp_int8_exp_with_rm_int16", top="tb_rp_t2", defs=["PREC_INT8"],
                  srcs=["tb/t2/tb_rp_t2.v"] + RM_FILES["rm_int16"], kind="neg", rm="rm_int16",
                  reason=[r"FAIL rm_id after release", r"FAIL result"]))
    b.append(dict(name="N2_rp_int4_exp_with_rm_int8", top="tb_rp_t2", defs=["PREC_INT4"],
                  srcs=["tb/t2/tb_rp_t2.v"] + RM_FILES["rm_int8"], kind="neg", rm="rm_int8",
                  reason=[r"FAIL rm_id after release", r"FAIL result"]))
    b.append(dict(name="N3_top_ungated_rm_int8", top="tb_top_t2", defs=["PREC_INT8", "NEG_UNGATED"],
                  srcs=["tb/t2/tb_top_t2.v", STUB] + STATIC + RM_FILES["rm_int8"], kind="neg", rm="rm_int8",
                  reason=[r"FAIL gate: decoupled runs unchanged", r"FAIL gate: rm_rst runs unchanged",
                          r"FAIL gate: decoupled blocked 1"]))
    return b


def sh(cmd, cwd):
    p = subprocess.run([str(c) for c in cmd], cwd=cwd, capture_output=True, text=True)
    return p.returncode, p.stdout + p.stderr


def lint(b):
    """Icarus compile-only lint; None if the build contains a file Icarus 0.9.7 cannot parse."""
    if "rtl/array.v" in b["srcs"]:
        return None
    cmd = ["iverilog", "-g2005", "-Wall", "-s", b["top"], "-o", BUILD / b["name"] / "lint.vvp"]
    cmd += [f"-D{d}" for d in b["defs"]] + b["srcs"]
    rc, out = sh(cmd, ROOT)
    return rc, out.strip()


def run(b):
    d = BUILD / b["name"]
    shutil.rmtree(d, ignore_errors=True)
    d.mkdir(parents=True)
    srcs = [ROOT / f for f in ordered(b["srcs"])]
    defs = [x for df in b["defs"] for x in ("-d", df)]
    log = ""
    rc, out = sh([VIVADO_BIN / "xvlog.bat", "-nolog"] + defs + srcs, d)
    log += out
    if rc == 0:
        rc, out = sh([VIVADO_BIN / "xelab.bat", "-nolog", "-debug", "off", b["top"], "-s", "snap"], d)
        log += out
    sim = ""
    if rc == 0:
        rc, sim = sh([VIVADO_BIN / "xsim.bat", "snap", "-R", "-nolog"], d)
    lt = lint(b)
    (d / "build.log").write_text(log + "\n==== xsim ====\n" + sim
                                 + ("\n==== iverilog lint ====\n" + lt[1] if lt else ""))
    warns = [ln for ln in log.splitlines() if ln.startswith("WARNING")]
    passed = rc == 0 and re.search(rf"^PASS {b['top']}", sim, re.M) and "FAIL" not in sim
    return dict(b, compiled=rc == 0 or bool(sim), warns=warns, sim=sim, passed=bool(passed), lint=lt)


def port_block(path):
    t = (ROOT / path).read_text()
    m = re.search(r"module\s+rp_t2\b.*?\);", t, re.S)
    return " ".join(m.group(0).split()) if m else None


def main():
    BUILD.mkdir(parents=True, exist_ok=True)
    REPORTS.mkdir(parents=True, exist_ok=True)
    res = [run(b) for b in build_list()]
    lines, ok_pos, ok_neg = [], True, True
    lines.append("T2 simulation summary (scripts/t2/run_sims.py; XSim 2022.2, Icarus lint)")
    lines.append(f"{'build':<32} {'result':<26} xvlog/xelab warnings  iverilog lint")
    for r in res:
        lt = "n/a (rtl/array.v)" if r["lint"] is None else ("clean" if r["lint"][0] == 0 and not r["lint"][1] else f"rc={r['lint'][0]} {r['lint'][1][:60]}")
        if r["kind"] == "pos":
            good = r["passed"] and not r["warns"] and (r["lint"] is None or (r["lint"][0] == 0 and not r["lint"][1]))
            ok_pos &= good
            verdict = "PASS" if good else "FAIL"
        else:
            failed = (not r["passed"]) and r["compiled"]
            why = [p for p in r["reason"] if re.search(p, r["sim"])]
            good = failed and len(why) == len(r["reason"])
            ok_neg &= good
            verdict = "FAILED as expected" if good else "NOT AS EXPECTED"
        lines.append(f"{r['name']:<32} {verdict:<26} {len(r['warns']):<21} {lt}")
        for w in r["warns"]:
            lines.append(f"    {w}")
        if r["kind"] == "neg":
            for p in r["reason"]:
                hit = re.search(rf"^.*{p}.*$", r["sim"], re.M)
                lines.append(f"    reason {'seen' if hit else 'MISSING'}: {hit.group(0).strip() if hit else p}")
    blocks = {rm: port_block(fs[0]) for rm, fs in RM_FILES.items()}
    same = len(set(blocks.values())) == 1 and None not in blocks.values()
    lines.append(f"port list check (rp_t2 declarations, whitespace-normalised): {'IDENTICAL' if same else 'DIFFERENT'}")

    rows = []
    for r in res:
        if r["kind"] == "pos" and r["top"] == "tb_top_t2":
            ct = dict(re.findall(r"^CT_CYCLES \S+ (\S+) (-?\d+)", r["sim"], re.M))
            cy = dict(re.findall(r"^CYCLES \S+ (\S+) (-?\d+)", r["sim"], re.M))
            rows += [(r["rm"], c, ct[c], cy.get(c, "")) for c in ct]
    with (REPORTS / "sim_cycles.csv").open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["rm", "case", "ct_cycles", "cycles"])
        w.writerows(rows)
    lat = {(c, y) for _, _, c, y in rows}
    lines.append(f"latency: {len(rows)} (rm, case) rows; distinct (ct_cycles, cycles) = {sorted(lat)}"
                 f" -> {'IDENTICAL across RMs and cases' if len(lat) == 1 and len(rows) == 27 else 'NOT identical'}")
    ok_lat = len(lat) == 1 and len(rows) == 27
    lines.append("ALL PASS" if ok_pos and same and ok_lat else "FAIL (positive builds / port list / latency)")
    lines.append("NEGATIVE OK" if ok_neg else "NEGATIVE NOT OK")
    text = "\n".join(lines) + "\n"
    (REPORTS / "sim_summary.txt").write_text(text)
    print(text, end="")
    for r in res:
        if (r["kind"] == "pos" and not r["passed"]) or (r["kind"] == "neg" and not r["compiled"]):
            print(f"--- {r['name']} (see {BUILD / r['name'] / 'build.log'}) ---\n{r['sim'][-3000:]}")
    return 0 if ok_pos and same and ok_lat and ok_neg else 1


if __name__ == "__main__":
    sys.exit(main())
