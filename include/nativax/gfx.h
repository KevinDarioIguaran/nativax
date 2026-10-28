#ifndef NATIVAX_GFX_H
#define NATIVAX_GFX_H

/*
    Sokol GFX renderer for display lists: batched quads, scissor stacks,
    glyph/image textures, straight-alpha blending. Requires sg_setup()
    (sokol glue environment) on the calling thread before nx_gfx_init().
*/

#include "nativax/display_list.h"

void nx_gfx_init(void);      /* shader, pipeline, sampler, white texture */
void nx_gfx_shutdown(void);
void nx_gfx_sync_textures(void); /* upload new registry textures (call per frame) */
void nx_gfx_render(const NxDisplayList* dl, int fb_w, int fb_h, const float clear_rgba[4]);

/* stats for benchmarks/docs */
typedef struct NxGfxStats {
    long texture_uploads;
    long buffer_recreates;
    long draw_calls;
} NxGfxStats;

const NxGfxStats* nx_gfx_stats(void);
void nx_gfx_reset_stats(void);

#endif /* NATIVAX_GFX_H */
