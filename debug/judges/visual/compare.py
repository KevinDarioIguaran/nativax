#!/usr/bin/env python3
"""Pixel-level visual comparison between two PNG images."""
import argparse
import json
import math
from pathlib import Path

from PIL import Image


def compare(ref_path: Path, actual_path: Path, diff_path: Path | None, tolerance: int = 3):
    ref = Image.open(ref_path).convert("RGBA")
    actual = Image.open(actual_path).convert("RGBA")
    if ref.size != actual.size:
        raise SystemExit(f"size mismatch: {ref.size} vs {actual.size}")
    w, h = ref.size
    diff = Image.new("RGBA", (w, h))
    changed = 0
    max_delta = 0
    for y in range(h):
        for x in range(w):
            r = ref.getpixel((x, y))
            a = actual.getpixel((x, y))
            d = max(abs(r[i] - a[i]) for i in range(4))
            if d > tolerance:
                changed += 1
                diff.putpixel((x, y), (255, 0, 0, 255))
            else:
                diff.putpixel((x, y), (0, 0, 0, 0))
            max_delta = max(max_delta, d)
    total = w * h
    pct = 100.0 * changed / total
    result = {
        "width": w,
        "height": h,
        "changed_pixels": changed,
        "total_pixels": total,
        "changed_percent": round(pct, 4),
        "max_channel_delta": max_delta,
        "tolerance": tolerance,
    }
    if diff_path:
        diff.save(diff_path)
        result["diff_image"] = str(diff_path)
    print(json.dumps(result, indent=2))
    return 0 if changed == 0 else 1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("reference")
    ap.add_argument("actual")
    ap.add_argument("--diff", default=None)
    ap.add_argument("--tolerance", type=int, default=3)
    args = ap.parse_args()
    raise SystemExit(compare(Path(args.reference), Path(args.actual),
                            Path(args.diff) if args.diff else None,
                            args.tolerance))


if __name__ == "__main__":
    main()