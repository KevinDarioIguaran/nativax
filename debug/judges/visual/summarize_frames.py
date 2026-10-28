#!/usr/bin/env python3
"""Compact, AI-oriented summary of a directory of rendered frames.

Reads PNGs (frame-*.png or any *.png), computes per-frame metadata and
pixel deltas between consecutive frames, and prints single-line JSON.
"""
import argparse
import os
import sys
from pathlib import Path
import hashlib
import json
try:
    from PIL import Image
except ModuleNotFoundError:
    _venv = Path(__file__).resolve().parents[3] / "debug" / ".venv" / "bin" / "python"
    if _venv.exists():
        os.execv(str(_venv), [str(_venv), __file__] + sys.argv[1:])
    raise


def sha256_file(p: Path) -> str:
    h = hashlib.sha256()
    with p.open("rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def pixel_delta(a: Image.Image, b: Image.Image, tol: int = 3) -> dict:
    if a.size != b.size:
        return {"size_mismatch": True, "a": a.size, "b": b.size}
    w, h = a.size
    changed = 0
    maxd = 0
    for y in range(h):
        for x in range(w):
            pa = a.getpixel((x, y))
            pb = b.getpixel((x, y))
            d = max(abs(pa[i] - pb[i]) for i in range(4))
            if d > tol:
                changed += 1
            if d > maxd:
                maxd = d
    total = w * h
    return {"changed_pixels": changed, "changed_percent": round(100.0 * changed / total, 4),
            "max_channel_delta": maxd, "tolerance": tol}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("directory")
    ap.add_argument("--tolerance", type=int, default=3)
    args = ap.parse_args()
    d = Path(args.directory)
    frames = sorted(p for p in d.glob("*.png"))
    if not frames:
        print(json.dumps({"error": "no png frames", "directory": str(d)}, separators=(",", ":")))
        return 1
    images = [Image.open(p).convert("RGBA") for p in frames]
    out = {
        "directory": str(d),
        "frame_count": len(frames),
        "frames": [{"file": p.name, "size": list(img.size), "bytes": p.stat().st_size,
                    "sha256": sha256_file(p)} for p, img in zip(frames, images)],
        "deltas": [],
    }
    for i in range(1, len(images)):
        out["deltas"].append({"from": frames[i - 1].name, "to": frames[i].name,
                              **pixel_delta(images[i - 1], images[i], args.tolerance)})
    print(json.dumps(out, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
