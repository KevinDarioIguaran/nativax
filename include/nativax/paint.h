#ifndef NATIVAX_PAINT_H
#define NATIVAX_PAINT_H

/*
    Paint: walk a laid-out box tree and emit a display list.

    Draws backgrounds, borders and text runs in tree order. Consumes the same
    NxDisplayList the GPU renderer and CPU rasterizer both understand, so
    headless goldens exercise the real geometry.
*/

#include <stdbool.h>

#include "nativax/display_list.h"
#include "nativax/layout.h"

/* Emit the full display list for a layout. font is the loaded font used for
   every run (v1 uses one font; per-element font selection is a later step). */
bool nx_paint(NxDisplayList* dl, const NxLayout* lay, int32_t font);

#endif /* NATIVAX_PAINT_H */
