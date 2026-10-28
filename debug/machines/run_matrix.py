#!/usr/bin/env python3
"""Run a benchmark matrix entry: collect env + run nativax_perf, save JSON."""
import json, subprocess, sys, datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BUILD = ROOT / "build"
PY = "/usr/bin/python3" if Path("/usr/bin/python3").exists() else sys.executable

def main():
    env = json.loads(subprocess.check_output([PY, str(ROOT/"debug/machines/collect_env.py")], text=True))
    outdir = ROOT / "debug" / "artifacts" / "machines"
    outdir.mkdir(parents=True, exist_ok=True)
    ts = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    runid = f"{ts}-{env['git_commit'][:8]}"
    # run nativax_perf if available
    perf = BUILD / "nativax_perf"
    perf_result = None
    if perf.exists():
        r = subprocess.run([str(perf), "--root", str(ROOT/"examples/counter"),
                            "--frames", "5", "--iters", "2", "--nav", "1"],
                           capture_output=True, text=True)
        perf_result = {"rc": r.returncode, "stdout": r.stdout[-500:]}
    record = {"run_id": runid, "env": env, "perf": perf_result}
    path = outdir / f"{runid}.json"
    path.write_text(json.dumps(record, indent=2))
    print("Saved", path)
    raise SystemExit(0)

if __name__ == "__main__":
    main()
