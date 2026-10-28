#include "nativax/display_list.h"

#include "nativax/text.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define NX_CORNER_SEGS 12 /* fixed per-90deg arc segments: deterministic goldens */

/* ---- texture registry ---- */
typedef struct NxTexEntry {
    NxTextureInfo info;
} NxTexEntry;

static NxTexEntry* g_tex;
static int g_tex_count, g_tex_cap;
static uint32_t g_tex_gen = 1;
static uint8_t g_white_pixel = 255;

static int32_t tex_alloc_slot(void) {
    if (g_tex_count == g_tex_cap) {
        g_tex_cap = g_tex_cap ? g_tex_cap * 2 : 32;
        g_tex = realloc(g_tex, (size_t)g_tex_cap * sizeof(NxTexEntry));
    }
    return g_tex_count++;
}

int32_t nx_tex_register(NxTexKind kind, int width, int height, int stride,
                        const uint8_t* pixels) {
    int32_t slot = tex_alloc_slot();
    g_tex[slot].info = (NxTextureInfo){kind, width, height, stride, pixels};
    return slot + 1; /* id 0 is reserved for the implicit white texture */
}

const NxTextureInfo* nx_tex_info(int32_t id) {
    if (id <= 0 || id > g_tex_count) {
        return NULL;
    }
    return &g_tex[id - 1].info;
}

void nx_tex_detach(int32_t id) {
    if (id > 0 && id <= g_tex_count) {
        g_tex[id - 1].info.pixels = NULL;
    }
}

void nx_tex_reset_all(void) {
    free(g_tex);
    g_tex = NULL;
    g_tex_count = g_tex_cap = 0;
    g_tex_gen++;
    (void)g_white_pixel;
}

uint32_t nx_tex_generation(void) { return g_tex_gen; }
int nx_tex_count(void) { return g_tex_count; }

/* ---- matrices ---- */
NxMat2x3 nx_mat_identity(void) { return (NxMat2x3){1, 0, 0, 1, 0, 0}; }
NxMat2x3 nx_mat_translate(float tx, float ty) { return (NxMat2x3){1, 0, 0, 1, tx, ty}; }
NxMat2x3 nx_mat_scale(float sx, float sy) { return (NxMat2x3){sx, 0, 0, sy, 0, 0}; }

NxMat2x3 nx_mat_mul(const NxMat2x3* m, const NxMat2x3* n) {
    /* m ∘ n: apply n first, then m */
    return (NxMat2x3){
        m->a * n->a + m->c * n->b,
        m->b * n->a + m->d * n->b,
        m->a * n->c + m->c * n->d,
        m->b * n->c + m->d * n->d,
        m->a * n->e + m->c * n->f + m->e,
        m->b * n->e + m->d * n->f + m->f,
    };
}

static void xform_pt(const NxDisplayList* dl, float x, float y, float* ox, float* oy) {
    const NxMat2x3* m = &dl->transform;
    *ox = m->a * x + m->c * y + m->e;
    *oy = m->b * x + m->d * y + m->f;
}

uint32_t nx_rgba_pack(NxColor c) {
    uint32_t r = (uint32_t)(c.r < 0 ? 0 : c.r > 1 ? 255 : c.r * 255.0f + 0.5f);
    uint32_t g = (uint32_t)(c.g < 0 ? 0 : c.g > 1 ? 255 : c.g * 255.0f + 0.5f);
    uint32_t b = (uint32_t)(c.b < 0 ? 0 : c.b > 1 ? 255 : c.b * 255.0f + 0.5f);
    uint32_t a = (uint32_t)(c.a < 0 ? 0 : c.a > 1 ? 255 : c.a * 255.0f + 0.5f);
    /* byte order in memory must be [r,g,b,a] for the UBYTE4N vertex
       attribute (little-endian: value 0xAABBGGRR) */
    return (a << 24) | (b << 16) | (g << 8) | r;
}

/* ---- display list ---- */
void nx_dl_init(NxDisplayList* dl) { memset(dl, 0, sizeof(*dl)); }

void nx_dl_reset(NxDisplayList* dl) {
    dl->vert_count = dl->index_count = dl->group_count = 0;
    dl->transform = nx_mat_identity();
    dl->clip_depth = 0;
}

void nx_dl_free(NxDisplayList* dl) {
    free(dl->verts);
    free(dl->indices);
    free(dl->groups);
    memset(dl, 0, sizeof(*dl));
}

static void ensure_verts(NxDisplayList* dl, uint32_t n) {
    if (dl->vert_count + n <= dl->vert_cap) return;
    dl->vert_cap = dl->vert_cap ? dl->vert_cap * 2 : 256;
    while (dl->vert_cap < dl->vert_count + n) dl->vert_cap *= 2;
    dl->verts = realloc(dl->verts, (size_t)dl->vert_cap * sizeof(NxVertex));
}

static void ensure_indices(NxDisplayList* dl, uint32_t n) {
    if (dl->index_count + n <= dl->index_cap) return;
    dl->index_cap = dl->index_cap ? dl->index_cap * 2 : 384;
    while (dl->index_cap < dl->index_count + n) dl->index_cap *= 2;
    dl->indices = realloc(dl->indices, (size_t)dl->index_cap * sizeof(uint32_t));
}

void nx_dl_begin_group(NxDisplayList* dl, int32_t texture, bool alpha_only) {
    if (dl->group_count > 0) {
        NxDrawGroup* prev = &dl->groups[dl->group_count - 1];
        if (prev->texture == texture && prev->alpha_only == alpha_only &&
            prev->has_scissor == (dl->clip_depth > 0)) {
            if (!dl->clip_depth ||
                (prev->scissor[0] == dl->scissor_stack[dl->clip_depth - 1].x &&
                 prev->scissor[1] == dl->scissor_stack[dl->clip_depth - 1].y &&
                 prev->scissor[2] == dl->scissor_stack[dl->clip_depth - 1].w &&
                 prev->scissor[3] == dl->scissor_stack[dl->clip_depth - 1].h)) {
                return; /* merge with previous group */
            }
        }
    }
    if (dl->group_count == dl->group_cap) {
        dl->group_cap = dl->group_cap ? dl->group_cap * 2 : 32;
        dl->groups = realloc(dl->groups, (size_t)dl->group_cap * sizeof(NxDrawGroup));
    }
    NxDrawGroup* g = &dl->groups[dl->group_count++];
    *g = (NxDrawGroup){.first_index = dl->index_count,
                       .index_count = 0,
                       .texture = texture,
                       .alpha_only = alpha_only,
                       .has_scissor = dl->clip_depth > 0};
    if (dl->clip_depth > 0) {
        const void* cs = &dl->scissor_stack[dl->clip_depth - 1];
        memcpy(g->scissor, cs, sizeof(g->scissor));
    }
}

static uint32_t push_vert(NxDisplayList* dl, float x, float y, float u, float v, uint32_t rgba) {
    ensure_verts(dl, 1);
    float dx, dy;
    xform_pt(dl, x, y, &dx, &dy);
    NxVertex* vt = &dl->verts[dl->vert_count++];
    *vt = (NxVertex){dx, dy, u, v, rgba};
    return dl->vert_count - 1;
}

void nx_dl_emit_quad(NxDisplayList* dl, float x0, float y0, float x1, float y1, float u0, float v0,
                     float u1, float v1, NxColor color, int32_t texture, bool alpha_only) {
    nx_dl_begin_group(dl, texture, alpha_only);
    uint32_t rgba = nx_rgba_pack(color);
    uint32_t i0 = push_vert(dl, x0, y0, u0, v0, rgba);
    uint32_t i1 = push_vert(dl, x1, y0, u1, v0, rgba);
    uint32_t i2 = push_vert(dl, x1, y1, u1, v1, rgba);
    uint32_t i3 = push_vert(dl, x0, y1, u0, v1, rgba);
    ensure_indices(dl, 6);
    uint32_t* ix = &dl->indices[dl->index_count];
    ix[0] = i0; ix[1] = i1; ix[2] = i2;
    ix[3] = i0; ix[4] = i2; ix[5] = i3;
    dl->index_count += 6;
    dl->groups[dl->group_count - 1].index_count += 6;
}

/* Emit an arbitrary triangle fan/polygon (already in CSS px). */
static void emit_poly(NxDisplayList* dl, const float* xy, int n, NxColor color, int32_t texture) {
    if (n < 3) return;
    nx_dl_begin_group(dl, texture, false);
    uint32_t rgba = nx_rgba_pack(color);
    uint32_t base = dl->vert_count;
    ensure_verts(dl, (uint32_t)n);
    for (int i = 0; i < n; i++) {
        float dx, dy;
        xform_pt(dl, xy[i * 2], xy[i * 2 + 1], &dx, &dy);
        dl->verts[dl->vert_count++] = (NxVertex){dx, dy, 0.5f, 0.5f, rgba};
    }
    ensure_indices(dl, (uint32_t)(n - 2) * 3);
    for (int i = 2; i < n; i++) {
        uint32_t* ix = &dl->indices[dl->index_count];
        ix[0] = base; ix[1] = base + (uint32_t)(i - 1); ix[2] = base + (uint32_t)i;
        dl->index_count += 3;
        dl->groups[dl->group_count - 1].index_count += 3;
    }
}

/* ---- transforms / clips ---- */
void nx_dl_push_transform(NxDisplayList* dl, const NxMat2x3* m) {
    dl->transform = nx_mat_mul(&dl->transform, m);
}
void nx_dl_pop_transform(NxDisplayList* dl) { (void)dl; /* single-slot build; see paint.c */ }

void nx_dl_push_clip(NxDisplayList* dl, float x, float y, float w, float h) {
    if (dl->clip_depth >= 32) return;
    float xs[4], ys[4];
    xform_pt(dl, x, y, &xs[0], &ys[0]);
    xform_pt(dl, x + w, y, &xs[1], &ys[1]);
    xform_pt(dl, x + w, y + h, &xs[2], &ys[2]);
    xform_pt(dl, x, y + h, &xs[3], &ys[3]);
    int minx = (int)floorf(fminf(fminf(xs[0], xs[1]), fminf(xs[2], xs[3])));
    int miny = (int)floorf(fminf(fminf(ys[0], ys[1]), fminf(ys[2], ys[3])));
    int maxx = (int)ceilf(fmaxf(fmaxf(xs[0], xs[1]), fmaxf(xs[2], xs[3])));
    int maxy = (int)ceilf(fmaxf(fmaxf(ys[0], ys[1]), fmaxf(ys[2], ys[3])));
    int cx = minx, cy = miny, cw = maxx - minx, ch = maxy - miny;
    if (dl->clip_depth > 0) {
        const int* p = (const int*)&dl->scissor_stack[dl->clip_depth - 1];
        int x0 = p[0] > cx ? p[0] : cx, y0 = p[1] > cy ? p[1] : cy;
        int x1 = (p[0] + p[2]) < (cx + cw) ? (p[0] + p[2]) : (cx + cw);
        int y1 = (p[1] + p[3]) < (cy + ch) ? (p[1] + p[3]) : (cy + ch);
        cx = x0; cy = y0; cw = x1 > x0 ? x1 - x0 : 0; ch = y1 > y0 ? y1 - y0 : 0;
    }
    dl->scissor_stack[dl->clip_depth++] = (typeof(dl->scissor_stack[0])){cx, cy, cw, ch};
}

void nx_dl_pop_clip(NxDisplayList* dl) {
    if (dl->clip_depth > 0) dl->clip_depth--;
}

/* ---- geometry ---- */
static float clamp_radius(float r, float w, float h) {
    if (r < 0) r = 0;
    float lim = (w < h ? w : h) * 0.5f;
    return r > lim ? lim : r;
}

typedef struct RectGeom {
    float r[4]; /* clamped radii tl,tr,br,bl */
} RectGeom;

static RectGeom clamp_radii(float w, float h, const float radii[4]) {
    RectGeom g = {{0, 0, 0, 0}};
    if (!radii) return g;
    for (int i = 0; i < 4; i++) g.r[i] = clamp_radius(radii[i], w, h);
    /* CSS spec corner clamping (proportional) */
    float s = 1.0f;
    float wsum = g.r[0] + g.r[1], hsum = g.r[1] + g.r[2];
    if (wsum > w) s = fminf(s, w / wsum);
    if (g.r[2] + g.r[3] > w) s = fminf(s, w / (g.r[2] + g.r[3]));
    if (hsum > h) s = fminf(s, h / hsum);
    if (g.r[3] + g.r[0] > h) s = fminf(s, h / (g.r[3] + g.r[0]));
    for (int i = 0; i < 4; i++) g.r[i] *= s;
    return g;
}

/* corner index → center + start angle (radians) for the arc sweep */
static void corner_arc(int corner, float x, float y, float w, float h, const float r[4],
                       float* cx, float* cy, float* a0, float* a1) {
    switch (corner) {
        case 0: *cx = x + r[0]; *cy = y + r[0]; *a0 = (float)M_PI; *a1 = 1.5f * (float)M_PI; break;
        case 1: *cx = x + w - r[1]; *cy = y + r[1]; *a0 = 1.5f * (float)M_PI; *a1 = 2.0f * (float)M_PI; break;
        case 2: *cx = x + w - r[2]; *cy = y + h - r[2]; *a0 = 0; *a1 = 0.5f * (float)M_PI; break;
        default: *cx = x + r[3]; *cy = y + h - r[3]; *a0 = 0.5f * (float)M_PI; *a1 = (float)M_PI; break;
    }
}

static void arc_point(float cx, float cy, float r, float a, float* px, float* py) {
    *px = cx + cosf(a) * r;
    *py = cy + sinf(a) * r;
}

static void fill_rounded(NxDisplayList* dl, float x, float y, float w, float h, NxColor color,
                         const float radii[4]) {
    RectGeom g = clamp_radii(w, h, radii);
    bool rounded = g.r[0] + g.r[1] + g.r[2] + g.r[3] > 0.01f;
    if (!rounded) {
        nx_dl_emit_quad(dl, x, y, x + w, y + h, 0, 0, 0, 0, color, 0, false);
        return;
    }
    float pts[(NX_CORNER_SEGS + 1) * 4 * 2];
    int n = 0;
    for (int c = 0; c < 4; c++) {
        if (g.r[c] <= 0.01f) {
            /* sharp corner: single point */
            float px, py;
            switch (c) {
                case 0: px = x; py = y; break;
                case 1: px = x + w; py = y; break;
                case 2: px = x + w; py = y + h; break;
                default: px = x; py = y + h; break;
            }
            pts[n++] = px; pts[n++] = py;
            continue;
        }
        float cx, cy, a0, a1;
        corner_arc(c, x, y, w, h, g.r, &cx, &cy, &a0, &a1);
        for (int i = 0; i <= NX_CORNER_SEGS; i++) {
            float a = a0 + (a1 - a0) * ((float)i / NX_CORNER_SEGS);
            float px, py;
            arc_point(cx, cy, g.r[c], a, &px, &py);
            pts[n++] = px; pts[n++] = py;
        }
    }
    emit_poly(dl, pts, n / 2, color, 0);
}

/* ring between outer and inner rounded rects (borders, no overlap blending) */
static void stroke_rounded(NxDisplayList* dl, float x, float y, float w, float h, NxColor color,
                           const float radii[4], float bw) {
    if (bw <= 0) return;
    RectGeom og = clamp_radii(w, h, radii);
    float iw = w - 2 * bw, ih = h - 2 * bw;
    if (iw <= 0 || ih <= 0) { /* degenerate: fill solid */
        fill_rounded(dl, x, y, w, h, color, radii);
        return;
    }
    /* inner radii: r - bw, floored at 0 */
    float ir[4];
    for (int i = 0; i < 4; i++) ir[i] = og.r[i] > bw ? og.r[i] - bw : 0.0f;
    bool rounded = og.r[0] + og.r[1] + og.r[2] + og.r[3] > 0.01f;
    float ix = x + bw, iy = y + bw;

    if (!rounded) {
        /* 4 edge quads (no overlap) */
        nx_dl_emit_quad(dl, x, y, x + w, iy, 0, 0, 0, 0, color, 0, false);              /* top */
        nx_dl_emit_quad(dl, x, iy + ih, x + w, y + h, 0, 0, 0, 0, color, 0, false);     /* bottom */
        nx_dl_emit_quad(dl, x, iy, ix, iy + ih, 0, 0, 0, 0, color, 0, false);           /* left */
        nx_dl_emit_quad(dl, ix + iw, iy, x + w, iy + ih, 0, 0, 0, 0, color, 0, false);  /* right */
        return;
    }
    for (int c = 0; c < 4; c++) {
        float ocx, ocy, oa0, oa1, icx, icy, ia0, ia1;
        corner_arc(c, x, y, w, h, og.r, &ocx, &ocy, &oa0, &oa1);
        corner_arc(c, ix, iy, iw, ih, ir, &icx, &icy, &ia0, &ia1);
        if (og.r[c] <= 0.01f) continue; /* sharp outer corners covered by edges below */
        for (int i = 0; i < NX_CORNER_SEGS; i++) {
            float a0 = oa0 + (oa1 - oa0) * ((float)i / NX_CORNER_SEGS);
            float a1 = oa0 + (oa1 - oa0) * ((float)(i + 1) / NX_CORNER_SEGS);
            float b0 = ia0 + (ia1 - ia0) * ((float)i / NX_CORNER_SEGS);
            float b1 = ia0 + (ia1 - ia0) * ((float)(i + 1) / NX_CORNER_SEGS);
            float o0x, o0y, o1x, o1y, n1x, n1y, n0x, n0y;
            arc_point(ocx, ocy, og.r[c], a0, &o0x, &o0y);
            arc_point(ocx, ocy, og.r[c], a1, &o1x, &o1y);
            arc_point(icx, icy, ir[c], b1, &n1x, &n1y);
            arc_point(icx, icy, ir[c], b0, &n0x, &n0y);
            float quad[8] = {o0x, o0y, o1x, o1y, n1x, n1y, n0x, n0y};
            emit_poly(dl, quad, 4, color, 0);
        }
    }
    /* straight edge quads filling between corner arcs (sharp corners degenerate
       to the full edge) */
    /* top: */
    nx_dl_emit_quad(dl, x + og.r[0], y, x + w - og.r[1], iy, 0, 0, 0, 0, color, 0, false);
    /* right: */
    nx_dl_emit_quad(dl, x + w - og.r[1], iy, x + w, iy + ih, 0, 0, 0, 0, color, 0, false);
    /* bottom: */
    nx_dl_emit_quad(dl, x + og.r[3], iy + ih, x + w - og.r[2], y + h, 0, 0, 0, 0, color, 0, false);
    /* left: */
    nx_dl_emit_quad(dl, x, iy + og.r[0], ix, iy + ih - og.r[3], 0, 0, 0, 0, color, 0, false);
}

void nx_dl_fill_rect(NxDisplayList* dl, float x, float y, float w, float h, NxColor color,
                     const float radii[4]) {
    if (w <= 0 || h <= 0) return;
    fill_rounded(dl, x, y, w, h, color, radii);
}

void nx_dl_stroke_rect(NxDisplayList* dl, float x, float y, float w, float h, NxColor color,
                       const float radii[4], float border_w) {
    if (w <= 0 || h <= 0 || border_w <= 0) return;
    stroke_rounded(dl, x, y, w, h, color, radii, border_w);
}

void nx_dl_text(NxDisplayList* dl, float x, float baseline_y, int32_t font, float size_px,
                NxColor color, const char* utf8, int len) {
    nx_text_emit(dl, x, baseline_y, font, size_px, color, utf8, len);
}

void nx_dl_image(NxDisplayList* dl, float x, float y, float w, float h, int32_t texture,
                 NxColor tint) {
    if (w <= 0 || h <= 0 || texture <= 0) return;
    nx_dl_emit_quad(dl, x, y, x + w, y + h, 0, 0, 1, 1, tint, texture, false);
}

void nx_dl_describe(const NxDisplayList* dl, char* out, int out_size) {
    int off = 0;
#define APP(...) off += snprintf(out + off, off < out_size ? (size_t)(out_size - off) : 0, __VA_ARGS__)
    APP("dl verts=%u indices=%u groups=%u\n", dl->vert_count, dl->index_count, dl->group_count);
    for (uint32_t gi = 0; gi < dl->group_count; gi++) {
        const NxDrawGroup* g = &dl->groups[gi];
        float minx = 1e9f, miny = 1e9f, maxx = -1e9f, maxy = -1e9f;
        for (uint32_t k = 0; k < g->index_count; k++) {
            const NxVertex* v = &dl->verts[dl->indices[g->first_index + k]];
            if (v->x < minx) minx = v->x;
            if (v->y < miny) miny = v->y;
            if (v->x > maxx) maxx = v->x;
            if (v->y > maxy) maxy = v->y;
        }
        APP("g%u tex=%d alpha=%d idx=%u..%u bbox=[%.1f %.1f %.1f %.1f]", gi, g->texture,
            g->alpha_only ? 1 : 0, g->first_index, g->first_index + g->index_count, minx, miny,
            maxx, maxy);
        if (g->has_scissor) {
            APP(" clip=[%d %d %d %d]", g->scissor[0], g->scissor[1], g->scissor[2], g->scissor[3]);
        }
        APP("\n");
    }
#undef APP
    if (off > out_size) off = out_size;
    out[off < out_size ? off : out_size - 1] = 0;
}
