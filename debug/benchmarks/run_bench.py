#!/usr/bin/env python3
"""Run nativax_perf and archive result to benchmarks/results/."""
import json, subprocess, sys, datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BUILD = ROOT / "build"
PY = "/usr/bin/python3" if Path("/usr/bin/python3").exists() else sys.executable

def main():
    env = json.loads(subprocess.check_output([PY, str(ROOT/"debug/machines/collect_env.py")], text=True))
    outdir = ROOT / "benchmarks" / "results"
    outdir.mkdir(parents=True, exist_ok=True)
    ts = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    commit = env.get("git_commit", "unknown")[:8]
    runid = f"{ts}-{commit}"
    perf = BUILD / "nativax_perf"
    if not perf.exists():
        print("nativax_perf not built"); raise SystemExit(1)
    r = subprocess.run([str(perf), "--root", str(ROOT/"examples/counter"),
                        "--frames", "10", "--iters", "3", "--nav", "2"],
                       capture_output=True, text=True)
    if r.returncode != 0:
        print(r.stderr); raise SystemExit(r.returncode)
    data = json.loads(r.stdout)
    data["env"] = env
    data["run_id"] = runid
    path = outdir / f"{runid}.json"
    path.write_text(json.dumps(data, indent=2))
    print("Saved", path)
    raise SystemExit(0)

if __name__ == "__main__":
    main()
