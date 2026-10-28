"""Build and run all T1 iverilog sims (T1_PLAN §6.4).

tb_rp_t1 x {add, mul} and tb_top_dfx x {add, mul}, iverilog -g2005 -> vvp,
outputs in sim/t1_build/. Prints a summary and ALL PASS; exits non-zero on
any failure. Run from anywhere: python scripts/t1/run_sims.py
"""
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BUILD = ROOT / "sim" / "t1_build"
RTL = "rtl/t1"
STATIC = [f"{RTL}/top_dfx.v", f"{RTL}/rst_sync.v", f"{RTL}/uptime.v",
          f"{RTL}/dfx_decouple.v", "tb/t1/vio_dfx_stub.v"]

SIMS = []
for rm in ("add", "mul"):
    rm_file = f"{RTL}/rm/rm_{rm}.v"
    SIMS.append((f"tb_rp_t1_{rm}", "tb_rp_t1", rm, ["tb/t1/tb_rp_t1.v", rm_file]))
    SIMS.append((f"tb_top_dfx_{rm}", "tb_top_dfx", rm,
                 ["tb/t1/tb_top_dfx.v", rm_file] + STATIC))


def run(name, top, rm, srcs):
    vvp = BUILD / f"{name}.vvp"
    log = BUILD / f"{name}.log"
    cmd = ["iverilog", "-g2005", "-Wall", f"-DRM_{rm.upper()}", "-s", top,
           "-o", str(vvp)] + srcs
    comp = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
    out = comp.stdout + comp.stderr
    if comp.returncode == 0:
        sim = subprocess.run(["vvp", "-n", str(vvp)], cwd=ROOT,
                             capture_output=True, text=True, timeout=300)
        out += sim.stdout + sim.stderr
    log.write_text(out)
    ok = comp.returncode == 0 and "PASS" in out and "FAIL" not in out
    return ok, out


def main():
    BUILD.mkdir(parents=True, exist_ok=True)
    results = []
    for name, top, rm, srcs in SIMS:
        ok, out = run(name, top, rm, srcs)
        results.append((name, ok))
        if not ok:
            print(f"--- {name} output ---\n{out}")
    print(f"{'bench':<20} result")
    for name, ok in results:
        print(f"{name:<20} {'PASS' if ok else 'FAIL'}")
    if all(ok for _, ok in results):
        print("ALL PASS")
        return 0
    print("FAIL")
    return 1


if __name__ == "__main__":
    sys.exit(main())
