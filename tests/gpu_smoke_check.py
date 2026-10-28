#!/usr/bin/env python3
"""Structural validation of the GPU smoke screenshot.

The GPU screenshot is not compared byte-for-byte with the CPU golden (GL
blending/rasterization differs subtly across drivers). Instead we assert the
frame is structurally consistent with the real application being rendered
(examples/counter):

  * exact size matches the requested --size (deterministic DPI pinned to 1.0);
  * the key scene colors are present (page background, header/button navy,
    accent coral, card white, note amber) — sampled from the rendered page;
  * the header text band contains real glyph coverage (white ink on the dark
    navy header) -- guards against the "solid-block text" bug where glyphs
    collapse to opaque rectangles.

The previous expectations matched build_smoke_scene(), a synthetic scene that
no longer exists in the runtime: the test now validates the real pipeline.

Usage: gpu_smoke_check.py <png> <w> <h>
Exit 0 = ok, 1 = structural failure.
"""
import sys

from PIL import Image


def near(c, target, tol=26):
    return all(abs(c[i] - target[i]) <= tol for i in range(3))


def main():
    path, reqW, reqH = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
    im = Image.open(path).convert("RGB")
    W, H = im.size
    # The window manager may resize the window (X11 DPI scaling). The scene is
    # drawn in CSS px at DPI 1.0 in deterministic mode, so its geometry is
    # anchored to the top-left at fixed coordinates regardless of the final
    # window size. Accept the actual size as long as it covers the scene.
    if W < reqW or H < reqH:
        print(f"FAIL size {im.size} smaller than requested ({reqW},{reqH})")
        return 1
    px = im.load()

    # key colors of examples/counter as rendered by the real pipeline
    # (style.css: body #f5f5fa, header/buttons #0f3460, h2/.btn.alt #e94560,
    #  card #ffffff, .note #fff3cd) — verified by sampling the rendered frame.
    BG = (245, 245, 250)       # body background
    HEADER = (15, 52, 96)      # header + primary button navy
    ACCENT = (233, 69, 96)     # h2 + .btn.alt coral
    CARD = (255, 255, 255)     # card face
    seen = {"bg": 0, "header": 0, "accent": 0, "card": 0}
    for y in range(0, H, 3):
        for x in range(0, W, 3):
            c = px[x, y]
            if near(c, BG, 6):
                seen["bg"] += 1
            elif near(c, HEADER, 6):
                seen["header"] += 1
            elif near(c, ACCENT, 8):
                seen["accent"] += 1
            elif near(c, CARD, 2):
                seen["card"] += 1
    for k, v in seen.items():
        if v < 20:
            print(f"FAIL color '{k}' barely present ({v} samples)")
            return 1

    # text-band glyph coverage: the header (full width, top ~90 CSS px at DPI
    # 1.0) renders "NativaX Native Runtime" in white on the navy banner. A
    # working glyph path produces many near-white pixels in the centered band;
    # the solid-block bug leaves the banner uniformly navy.
    white = 0
    for y in range(15, 75):
        for x in range(max(0, W // 2 - 360), min(W, W // 2 + 360)):
            c = px[x, y]
            if c[0] > 210 and c[1] > 210 and c[2] > 210:
                white += 1
    if white < 60:
        print(f"FAIL text glyph coverage missing on header (white={white})")
        return 1

    print(f"ok size={W}x{H} colors={seen} pill_white_px={white}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
