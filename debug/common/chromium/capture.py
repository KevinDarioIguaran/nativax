#!/usr/bin/env python3
"""Capture a Chromium screenshot for a local HTML file."""
import argparse
import subprocess
from pathlib import Path

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("html")
    ap.add_argument("--out", required=True)
    ap.add_argument("--width", type=int, default=800)
    ap.add_argument("--height", type=int, default=900)
    args = ap.parse_args()
    html = Path(args.html).resolve()
    out = Path(args.out).resolve()
    out.parent.mkdir(parents=True, exist_ok=True)
    cmd = [
        "google-chrome", "--headless=new", "--disable-gpu",
        f"--window-size={args.width},{args.height}",
        f"--screenshot={out}", str(html),
    ]
    subprocess.run(cmd, check=True)
    print(out)

if __name__ == "__main__":
    main()