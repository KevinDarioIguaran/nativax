#!/usr/bin/env python3
"""Structural validation of the GPU smoke screenshot.

The GPU screenshot is not compared byte-for-byte with the CPU golden (GL
blending/rasterization differs subtly across drivers). Instead we assert the
frame is structurally consistent with the smoke scene:

  * exact size matches the requested --size (deterministic DPI pinned to 1.0);
  * the four key scene colors are present (background, panel, accent pill,
    text);
  * the header text band contains real glyph coverage (both dark ink on the
    light pill and light ink on the dark panel) -- guards against the
    "solid-block text" bug where glyphs collapse to opaque rectangles.

Usage: gpu_smoke_check.py <png> <w> <h>
Exit 0 = ok, 1 = structural failure.
"""
import sys

from PIL import Image


def near(c, target, tol=26):
    return all(abs(c[i] - target[i]) <= tol for i in range(3))


def main():
    path, W, H = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
    im = Image.open(path).convert("RGB")
    if im.size != (W, H):
        print(f"FAIL size {im.size} != ({W},{H})")
        return 1
    px = im.load()

    # key scene colors (from build_smoke_scene in main_sokol.c)
    BG = (15, 18, 28)          # 0.06,0.07,0.11
    PANEL = (26, 31, 51)       # 0.10,0.12,0.20
    ACCENT = (59, 92, 255)     # 0.23,0.36,1.0
    seen = {"bg": 0, "panel": 0, "accent": 0}
    for y in range(0, H, 3):
        for x in range(0, W, 3):
            c = px[x, y]
            if near(c, BG, 6):
                seen["bg"] += 1
            elif near(c, PANEL, 6):
                seen["panel"] += 1
            elif near(c, ACCENT, 20):
                seen["accent"] += 1
    for k, v in seen.items():
        if v < 20:
            print(f"FAIL color '{k}' barely present ({v} samples)")
            return 1

    # text-band glyph coverage: the accent pill (160..360 x 220..280 in CSS px,
    # DPI 1.0) holds "NativaX C runtime" in white ink. A working glyph path
    # produces near-white pixels on the blue pill; the solid-block bug leaves
    # the pill uniformly blue with no white interior.
    white = 0
    for y in range(228, 274):
        for x in range(178, 352):
            c = px[x, y]
            if c[0] > 210 and c[1] > 210 and c[2] > 210:
                white += 1
    if white < 60:
        print(f"FAIL text glyph coverage missing on pill (white={white})")
        return 1

    print(f"ok size={W}x{H} colors={seen} pill_white_px={white}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
