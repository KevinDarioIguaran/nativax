"""Structural validation of the effects GPU screenshot."""
import sys

from PIL import Image


def near(c, target, tol=30):
    return all(abs(c[i] - target[i]) <= tol for i in range(3))


def bbox_of(px, W, H, target, tol=30, step=2):
    minx, miny, maxx, maxy = W, H, -1, -1
    n = 0
    for y in range(0, H, step):
        for x in range(0, W, step):
            if near(px[x, y], target, tol):
                n += 1
                if x < minx: minx = x
                if y < miny: miny = y
                if x > maxx: maxx = x
                if y > maxy: maxy = y
    if n == 0:
        return None, 0
    return (minx, miny, maxx, maxy), n


def main():
    path, reqW, reqH = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
    im = Image.open(path).convert("RGB")
    W, H = im.size
    if W < reqW or H < reqH:
        print(f"FAIL size {im.size}")
        return 1
    px = im.load()

    BG = (16, 24, 32)
    HEADER = (29, 53, 87)
    BADGE = (230, 57, 70)
    GROUP_BLEND = (43, 74, 95)   # #457b9d @ 0.5 over #101820
    CLIP = (42, 157, 143)
    MOVED = (233, 196, 106)

    seen = {"bg": 0, "header": 0, "badge": 0, "group": 0, "clip": 0, "moved": 0}
    for y in range(0, H, 3):
        for x in range(0, W, 3):
            c = px[x, y]
            if near(c, BG, 8):
                seen["bg"] += 1
            elif near(c, HEADER, 8):
                seen["header"] += 1
            elif near(c, BADGE, 10):
                seen["badge"] += 1
            elif near(c, GROUP_BLEND, 12):
                seen["group"] += 1
            elif near(c, CLIP, 12):
                seen["clip"] += 1
            elif near(c, MOVED, 12):
                seen["moved"] += 1

    for k in ("bg", "header", "badge", "group", "clip", "moved"):
        if seen[k] < 5:
            print(f"FAIL color '{k}' barely present ({seen[k]})")
            return 1

    # rounded badge: its bounding box corner should not be badge-colored
    bb, bn = bbox_of(px, W, H, BADGE, 10)
    if bb is None:
        print("FAIL badge bbox missing")
        return 1
    minx, miny, maxx, maxy = bb
    corner_pixels = [px[minx, miny], px[maxx, miny], px[minx, maxy], px[maxx, maxy]]
    if all(near(c, BADGE, 10) for c in corner_pixels):
        print("FAIL badge corners all badge-colored (not rounded)")
        return 1

    # transform: moved box should be shifted well to the right
    mb, mn = bbox_of(px, W, H, MOVED, 12)
    if mb is None or mb[0] < 100:
        print(f"FAIL moved box not shifted right (bbox={mb})")
        return 1

    print(f"ok size={W}x{H} colors={seen} badge_bbox={bb} moved_bbox={mb}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
