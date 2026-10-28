#!/usr/bin/env python3
"""Visual regression gate: render a scene with NativaX and diff against a golden."""
import argparse
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
BUILD = ROOT / "build"
RUNTIME = BUILD / "nativax-runtime"
PY = "/usr/bin/python3" if Path("/usr/bin/python3").exists() else sys.executable


def render(root: str, out: Path, w=1024, h=768, frames=3):
    root_abs = str((ROOT / root).resolve()) if not Path(root).is_absolute() else root
    cmd = [str(RUNTIME), "--headless", "--root", root_abs,
           "--frames", str(frames), "--screenshot", str(out)]
    r = subprocess.run(cmd, cwd=str(BUILD), capture_output=True, text=True)
    return r.returncode == 0 and out.exists()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True)
    ap.add_argument("--golden", required=True)
    ap.add_argument("--out", default="/tmp/nativax_regression.png")
    ap.add_argument("--tolerance", type=int, default=3)
    ap.add_argument("--max-changed-percent", type=float, default=0.5)
    args = ap.parse_args()

    out = Path(args.out)
    if not render(args.root, out):
        print(json.dumps({"error": "render failed"}))
        raise SystemExit(2)

    # reuse compare logic
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from compare import compare
    import io, contextlib
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        rc = compare(Path(args.golden), out, None, args.tolerance)
    res = json.loads(buf.getvalue())
    res["rendered"] = str(out)
    res["gate"] = "PASS" if (res["changed_percent"] <= args.max_changed_percent) else "FAIL"
    print(json.dumps(res, indent=2))
    raise SystemExit(0 if res["gate"] == "PASS" else 1)


if __name__ == "__main__":
    main()
