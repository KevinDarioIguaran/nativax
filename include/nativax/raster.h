#ifndef NATIVAX_RASTER_H
#define NATIVAX_RASTER_H

/*
    CPU rasterizer over the display list — the headless/test consumer.
    2x2 rotated-grid antialiasing, bilinear sampling, straight-alpha blending.
    Used for golden PNGs and visual regression without a GPU or display.
*/

#include "nativax/display_list.h"

#include <stdbool.h>

typedef struct NxRaster {
    uint8_t* pixels; /* RGBA8 */
    int width, height;
} NxRaster;

void nx_raster_init(NxRaster* r, int width, int height);
void nx_raster_clear(NxRaster* r, NxColor color);
void nx_raster_run(NxRaster* r, const NxDisplayList* dl);
bool nx_raster_write_png(const NxRaster* r, const char* path);
void nx_raster_free(NxRaster* r);

#endif /* NATIVAX_RASTER_H */
