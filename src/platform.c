/*
    Backend-independent platform helpers.

    Kept free of OS/graphics headers so the coordinate contract can be unit
    tested on CI without a display: every backend must normalize pointer
    positions with nx_platform_css_coord() and size its framebuffer with
    nx_platform_physical_size().
*/
#include "nativax/platform.h"

#include <math.h>

float nx_platform_css_coord(float pixels, float dpi) {
    if (dpi <= 0.0f) dpi = 1.0f;
    return pixels / dpi;
}

int nx_platform_physical_size(int css_px, float dpi) {
    if (dpi <= 0.0f) dpi = 1.0f;
    if (css_px <= 0) return 0;
    return (int)lroundf((float)css_px * dpi);
}
