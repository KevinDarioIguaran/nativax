#ifndef NATIVAX_DISPLAY_LIST_H
#define NATIVAX_DISPLAY_LIST_H

/*
    Display list: the retained, GPU- and CPU- consumable output of painting.

    Geometry is emitted already transformed (2D affine applied at build time);
    clipping is expressed as axis-aligned scissor groups. Both the Sokol GPU
    renderer (gfx_sokol.c) and the CPU rasterizer (raster.c) consume the same
    vertex/index/group arrays, so headless goldens exercise the real geometry.

    Texture ids resolve through the registry below: 0 = white 1x1, ids > 0 are
    registered by text.c (glyph atlas pages, kind GLYPH) and image.c (kind
    IMAGE). Ordering of vertices, indices and groups is deterministic for
    golden comparisons.
*/

#include <stdbool.h>
#include <stdint.h>

typedef struct NxColor {
    float r, g, b, a;
} NxColor;

typedef struct NxVertex {
    float x, y;     /* device pixels, y down */
    float u, v;     /* texture coordinates */
    uint32_t rgba;  /* packed 0xAARRGGBB */
} NxVertex;

typedef struct NxDrawGroup {
    uint32_t first_index;
    uint32_t index_count;
    int32_t texture;        /* registry id, 0 = white */
    bool alpha_only;        /* glyph-style blend (coverage * color) */
    bool has_scissor;
    int scissor[4];         /* x, y, w, h in device pixels */
} NxDrawGroup;

typedef struct NxMat2x3 {
    float a, b, c, d, e, f; /* x' = a*x + c*y + e; y' = b*x + d*y + f */
} NxMat2x3;

/* ---- texture registry ---- */
typedef enum NxTexKind { NX_TEX_WHITE = 0, NX_TEX_GLYPH = 1, NX_TEX_IMAGE = 2 } NxTexKind;

typedef struct NxTextureInfo {
    NxTexKind kind;
    int width, height, stride;
    const uint8_t* pixels; /* RGBA8 for IMAGE, A8 coverage for GLYPH/WHITE */
} NxTextureInfo;

int32_t nx_tex_register(NxTexKind kind, int width, int height, int stride,
                        const uint8_t* pixels);
const NxTextureInfo* nx_tex_info(int32_t id);
void nx_tex_detach(int32_t id);   /* owner freed pixels: consumers fall back to white */
void nx_tex_reset_all(void);      /* teardown: frees the registry (not pixels) */
uint32_t nx_tex_generation(void); /* bumped by reset_all: caches must invalidate */
int nx_tex_count(void);

/* ---- display list ---- */
typedef struct NxDisplayList {
    NxVertex* verts;
    uint32_t vert_count, vert_cap;
    uint32_t* indices;
    uint32_t index_count, index_cap;
    NxDrawGroup* groups;
    uint32_t group_count, group_cap;

    NxMat2x3 transform;
    int clip_depth;
    struct {
        int x, y, w, h;
    } scissor_stack[32];
} NxDisplayList;

void nx_dl_init(NxDisplayList* dl);
void nx_dl_reset(NxDisplayList* dl);
void nx_dl_free(NxDisplayList* dl);

void nx_dl_push_transform(NxDisplayList* dl, const NxMat2x3* m);
void nx_dl_pop_transform(NxDisplayList* dl);
void nx_dl_push_clip(NxDisplayList* dl, float x, float y, float w, float h);
void nx_dl_pop_clip(NxDisplayList* dl);

/* All coordinates in CSS pixels; builder converts via current transform. */
void nx_dl_fill_rect(NxDisplayList* dl, float x, float y, float w, float h, NxColor color,
                     const float radii[4]); /* radii: tl, tr, br, bl; NULL = square */
void nx_dl_stroke_rect(NxDisplayList* dl, float x, float y, float w, float h, NxColor color,
                       const float radii[4], float border_w);
void nx_dl_text(NxDisplayList* dl, float x, float baseline_y, int32_t font, float size_px,
                NxColor color, const char* utf8, int len);
void nx_dl_image(NxDisplayList* dl, float x, float y, float w, float h, int32_t texture,
                 NxColor tint);

/* Canonical text dump for golden tests (stable across runs). */
void nx_dl_describe(const NxDisplayList* dl, char* out, int out_size);

NxMat2x3 nx_mat_identity(void);
NxMat2x3 nx_mat_translate(float tx, float ty);
NxMat2x3 nx_mat_scale(float sx, float sy);
NxMat2x3 nx_mat_mul(const NxMat2x3* m, const NxMat2x3* n);

uint32_t nx_rgba_pack(NxColor c);

/* Internal emitters (used by text.c for glyph quads). */
void nx_dl_emit_quad(NxDisplayList* dl, float x0, float y0, float x1, float y1, float u0, float v0,
                     float u1, float v1, NxColor color, int32_t texture, bool alpha_only);
void nx_dl_begin_group(NxDisplayList* dl, int32_t texture, bool alpha_only);

#endif /* NATIVAX_DISPLAY_LIST_H */
