#!/usr/bin/env python3
"""Experimental visual judge for the NativaX debug laboratory.

This is a first, honest building block: it drives the real runtime, captures
real screenshots and records measurable facts about them. It is not yet a
pixel oracle; extending it with reference images and tolerances is the next
step.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
LAB = HERE.parent / "lab"
DEBUG = HERE.parent
ROOT = DEBUG.parent
for path in (str(DEBUG), str(LAB)):
    if path not in sys.path:
        sys.path.insert(0, path)

import harness  # noqa: E402


def run_capture(runtime, root, entry, out, *, frames=3, input_spec="", size=(1024, 768)):
    args = [str(runtime), "--headless", "--root", str(root), "--entry", entry,
            "--size", str(size[0]), str(size[1]), "--max-frames", str(frames),
            "--screenshot", str(out)]
    if input_spec:
        args += ["--input", input_spec]
    r = subprocess.run(args, capture_output=True, text=True, timeout=120)
    return r.returncode, r.stdout, r.stderr


def image_info(path: Path) -> dict:
    try:
        from PIL import Image
        with Image.open(path) as im:
            return {"width": im.width, "height": im.height, "mode": im.mode,
                    "bytes": path.stat().st_size}
    except Exception as exc:  # noqa: BLE001
        return {"error": str(exc), "bytes": path.stat().st_size if path.exists() else 0}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--case", required=True, help="case id, e.g. jsdom.003")
    ap.add_argument("--widths", default="320,768,1024,1280")
    ap.add_argument("--frames", default="3,12,24", help="comma list of frame counts")
    ap.add_argument("--scroll", default="0", help="comma list of vertical scroll offsets")
    ap.add_argument("--out", default=str(HERE / "captures"))
    args = ap.parse_args()

    lab = harness.Lab(responsive=False)
    harness.load_sections()
    case_dir = lab.case_dir(args.case)
    meta = lab.case_meta(args.case)
    entry = meta.get("entry", "index.html")
    out_root = Path(args.out)
    out_root.mkdir(parents=True, exist_ok=True)

    report = {"case": args.case, "captures": []}
    for width in (int(x) for x in args.widths.split(",")):
        for frame_count in (int(x) for x in args.frames.split(",")):
            for scroll in (int(x) for x in args.scroll.split(",")):
                name = f"{args.case.replace('.', '_')}_{width}x{768}_f{frame_count}_s{scroll}.png"
                path = out_root / name
                input_spec = f"scroll:{scroll}" if scroll else ""
                rc, stdout, stderr = run_capture(
                    lab.runtime_bin, case_dir, entry, path,
                    frames=frame_count, input_spec=input_spec,
                    size=(width, 768))
                report["captures"].append({
                    "width": width, "frames": frame_count, "scroll": scroll,
                    "path": str(path), "returncode": rc,
                    "image": image_info(path) if path.exists() else None,
                    "stderr": stderr.strip()[-500:] if rc != 0 else "",
                })

    report_path = out_root / f"{args.case.replace('.', '_')}.json"
    report_path.write_text(json.dumps(report, indent=2))
    print(json.dumps({"captures": len(report["captures"]),
                      "report": str(report_path)}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())