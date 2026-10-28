#include "nativax/raster.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "stb_image_write.h"

void nx_raster_init(NxRaster* r, int width, int height) {
    r->width = width;
    r->height = height;
    r->pixels = malloc((size_t)width * height * 4);
    memset(r->pixels, 0, (size_t)width * height * 4);
}

void nx_raster_clear(NxRaster* r, NxColor c) {
    uint8_t px[4] = {(uint8_t)(c.r * 255), (uint8_t)(c.g * 255), (uint8_t)(c.b * 255),
                     (uint8_t)(c.a * 255)};
    for (int i = 0; i < r->width * r->height; i++) {
        memcpy(r->pixels + (size_t)i * 4, px, 4);
    }
}

void nx_raster_free(NxRaster* r) {
    free(r->pixels);
    r->pixels = NULL;
}

bool nx_raster_write_png(const NxRaster* r, const char* path) {
    return stbi_write_png(path, r->width, r->height, 4, r->pixels, r->width * 4) != 0;
}

/* bilinear sample with clamp; white when texture missing/detached */
static void sample_tex(const NxTextureInfo* tex, float u, float v, float* cr, float* cg, float* cb,
                       float* ca) {
    *cr = *cg = *cb = *ca = 1.0f;
    if (!tex || !tex->pixels || tex->width <= 0 || tex->height <= 0) return;
    float fx = u * tex->width - 0.5f;
    float fy = v * tex->height - 0.5f;
    /* clamp into the texture: attribute extrapolation at pixel centers just
       outside a triangle can push uv beyond the quad edge */
    if (fx < 0) fx = 0;
    if (fy < 0) fy = 0;
    if (fx > tex->width - 1.0f) fx = tex->width - 1.0f;
    if (fy > tex->height - 1.0f) fy = tex->height - 1.0f;
    int x0 = (int)floorf(fx), y0 = (int)floorf(fy);
    float tx = fx - x0, ty = fy - y0;
    int x1 = x0 + 1, y1 = y0 + 1;
    if (x1 >= tex->width) x1 = tex->width - 1;
    if (y1 >= tex->height) y1 = tex->height - 1;

    const uint8_t* p00 = tex->pixels + (size_t)y0 * tex->stride + x0 * (tex->kind == NX_TEX_IMAGE ? 4 : 1);
    const uint8_t* p10 = tex->pixels + (size_t)y0 * tex->stride + x1 * (tex->kind == NX_TEX_IMAGE ? 4 : 1);
    const uint8_t* p01 = tex->pixels + (size_t)y1 * tex->stride + x0 * (tex->kind == NX_TEX_IMAGE ? 4 : 1);
    const uint8_t* p11 = tex->pixels + (size_t)y1 * tex->stride + x1 * (tex->kind == NX_TEX_IMAGE ? 4 : 1);

    if (tex->kind == NX_TEX_IMAGE) {
        float r = 0, g = 0, b = 0, a = 0;
        const uint8_t* ps[4] = {p00, p10, p01, p11};
        float ws[4] = {(1 - tx) * (1 - ty), tx * (1 - ty), (1 - tx) * ty, tx * ty};
        for (int i = 0; i < 4; i++) {
            r += ps[i][0] * ws[i];
            g += ps[i][1] * ws[i];
            b += ps[i][2] * ws[i];
            a += ps[i][3] * ws[i];
        }
        *cr = r / 255.0f;
        *cg = g / 255.0f;
        *cb = b / 255.0f;
        *ca = a / 255.0f;
    } else {
        /* coverage-only (glyph / white) */
        float cov = p00[0] * (1 - tx) * (1 - ty) + p10[0] * tx * (1 - ty) + p01[0] * (1 - tx) * ty +
                    p11[0] * tx * ty;
        *cr = *cg = *cb = 1.0f;
        *ca = cov / 255.0f;
    }
}

static inline float edge(float ax, float ay, float bx, float by, float px, float py) {
    return (bx - ax) * (py - ay) - (by - ay) * (px - ax);
}

/* Canonical endpoint order for an edge: lexicographic on (x, y). Both triangles
   sharing an edge evaluate it with the SAME arithmetic (bitwise-identical edge
   value), so "sample exactly on the shared edge" is decided identically by
   both. The triangle that traverses the edge in canonical order owns such
   samples (fwd); the other excludes them -> exactly-once coverage. */
static inline bool canon_fwd(const NxVertex* a, const NxVertex* b) {
    return a->x < b->x || (a->x == b->x && a->y <= b->y);
}

/* ---- triangle setup ------------------------------------------------------ */

typedef struct {
    const NxVertex *v0, *v1, *v2;
    const NxVertex *ca0, *cb0, *ca1, *cb1, *ca2, *cb2; /* canonical edge ends */
    float s0, s1, s2;  /* +1 when the canonical edge is traversed by this tri */
    float m0, m1, m2;  /* edge sign, normalized by this triangle's winding */
    float inv_area;
} TriPrep;

/* returns false on degenerate triangles (zero area) */
static bool tri_prep(TriPrep* t, const NxVertex* v0, const NxVertex* v1, const NxVertex* v2) {
    float area = edge(v0->x, v0->y, v1->x, v1->y, v2->x, v2->y);
    if (fabsf(area) < 1e-6f) return false;
    t->v0 = v0;
    t->v1 = v1;
    t->v2 = v2;
    t->inv_area = 1.0f / area;
    int winding = area > 0 ? 1 : -1;

    t->ca0 = v0; t->cb0 = v1; t->s0 = 1.0f;
    if (!canon_fwd(v0, v1)) { t->ca0 = v1; t->cb0 = v0; t->s0 = -1.0f; }
    t->m0 = t->s0 * winding;

    t->ca1 = v1; t->cb1 = v2; t->s1 = 1.0f;
    if (!canon_fwd(v1, v2)) { t->ca1 = v2; t->cb1 = v1; t->s1 = -1.0f; }
    t->m1 = t->s1 * winding;

    t->ca2 = v2; t->cb2 = v0; t->s2 = 1.0f;
    if (!canon_fwd(v2, v0)) { t->ca2 = v0; t->cb2 = v2; t->s2 = -1.0f; }
    t->m2 = t->s2 * winding;
    return true;
}

/* how many of the 4 sub-samples of pixel (x,y) fall inside the triangle */
static int tri_hits(const TriPrep* t, float x, float y) {
    static const float subs[4][2] = {
        {0.25f, 0.25f}, {0.75f, 0.25f}, {0.25f, 0.75f}, {0.75f, 0.75f}};
    int hits = 0;
    for (int s = 0; s < 4; s++) {
        float px = x + subs[s][0], py = y + subs[s][1];
        /* canonical edge values (identical arithmetic in every triangle that
           shares the edge); s_i reconstructs this triangle's orientation */
        float e0 = edge(t->ca0->x, t->ca0->y, t->cb0->x, t->cb0->y, px, py);
        float e1 = edge(t->ca1->x, t->ca1->y, t->cb1->x, t->cb1->y, px, py);
        float e2 = edge(t->ca2->x, t->ca2->y, t->cb2->x, t->cb2->y, px, py);
        /* inside: positive side of all three (winding-normalized), or exactly
           on a canonically-traversed edge (sample owned by this triangle) */
        float f0 = e0 * t->m0, f1 = e1 * t->m1, f2 = e2 * t->m2;
        if (f0 > 0 && f1 > 0 && f2 > 0) {
            hits++;
        } else if ((e0 == 0.0f && t->s0 > 0) || (e1 == 0.0f && t->s1 > 0) ||
                   (e2 == 0.0f && t->s2 > 0)) {
            if (f0 >= 0 && f1 >= 0 && f2 >= 0) hits++;
        }
    }
    return hits;
}

/* Rasterize one primitive: a set of triangles that PARTITION it without
   overlapping (a quad = 2, a clipped/fan polygon = up to 8). Sub-sample
   coverage of all its triangles is accumulated per pixel and composited
   exactly ONCE. Compositing per triangle would seam along shared diagonals:
   src-over is not associative (0.75 then 0.25 of the same opaque color lands
   at 81% coverage, drawing a faint line across every large quad). */
static void raster_prim(NxRaster* r, const TriPrep* tris, int nt, const NxTextureInfo* tex,
                        bool alpha_only) {
    /* union bbox of the primitive */
    int minx = r->width, miny = r->height, maxx = 0, maxy = 0;
    for (int i = 0; i < nt; i++) {
        const TriPrep* t = &tris[i];
        int x0 = (int)floorf(fminf(t->v0->x, fminf(t->v1->x, t->v2->x)));
        int x1 = (int)ceilf(fmaxf(t->v0->x, fmaxf(t->v1->x, t->v2->x)));
        int y0 = (int)floorf(fminf(t->v0->y, fminf(t->v1->y, t->v2->y)));
        int y1 = (int)ceilf(fmaxf(t->v0->y, fmaxf(t->v1->y, t->v2->y)));
        if (x0 < minx) minx = x0;
        if (y0 < miny) miny = y0;
        if (x1 > maxx) maxx = x1;
        if (y1 > maxy) maxy = y1;
    }
    if (minx < 0) minx = 0;
    if (miny < 0) miny = 0;
    if (maxx > r->width) maxx = r->width;
    if (maxy > r->height) maxy = r->height;

    for (int y = miny; y < maxy; y++) {
        for (int x = minx; x < maxx; x++) {
            /* accumulated premultiplied fragment of the whole primitive */
            float ar = 0, ag = 0, ab = 0, aa = 0;
            for (int i = 0; i < nt; i++) {
                const TriPrep* t = &tris[i];
                int hits = tri_hits(t, (float)x, (float)y);
                if (hits == 0) continue;

                /* barycentric for attribute interpolation (pixel center) */
                float px = x + 0.5f, py = y + 0.5f;
                float b0 = edge(t->v1->x, t->v1->y, t->v2->x, t->v2->y, px, py) * t->inv_area;
                float b1 = edge(t->v2->x, t->v2->y, t->v0->x, t->v0->y, px, py) * t->inv_area;
                float b2 = 1.0f - b0 - b1;
                float u = t->v0->u * b0 + t->v1->u * b1 + t->v2->u * b2;
                float v = t->v0->v * b0 + t->v1->v * b1 + t->v2->v * b2;

                float sr, sg, sb, sa;
                sample_tex(tex, u, v, &sr, &sg, &sb, &sa);

                /* vertex rgba memory layout is [r,g,b,a] (see nx_rgba_pack) */
                float fr = (t->v0->rgba & 255) * b0 + (t->v1->rgba & 255) * b1 + (t->v2->rgba & 255) * b2;
                float fg = ((t->v0->rgba >> 8) & 255) * b0 + ((t->v1->rgba >> 8) & 255) * b1 + ((t->v2->rgba >> 8) & 255) * b2;
                float fb = ((t->v0->rgba >> 16) & 255) * b0 + ((t->v1->rgba >> 16) & 255) * b1 + ((t->v2->rgba >> 16) & 255) * b2;
                float fa = ((t->v0->rgba >> 24) & 255) * b0 + ((t->v1->rgba >> 24) & 255) * b1 + ((t->v2->rgba >> 24) & 255) * b2;
                fr /= 255.0f; fg /= 255.0f; fb /= 255.0f; fa /= 255.0f;

                float out_a = fa * sa;
                if (out_a <= 0) continue;
                float a1 = out_a * (hits * 0.25f); /* this triangle's contribution */
                if (alpha_only) {
                    ar += fr * a1;
                    ag += fg * a1;
                    ab += fb * a1;
                } else {
                    ar += fr * sr * a1;
                    ag += fg * sg * a1;
                    ab += fb * sb * a1;
                }
                aa += a1;
            }
            if (aa <= 0) continue;

            /* one src-over blend with the primitive's total coverage */
            float inv = 1.0f / aa;
            float out_r = ar * inv, out_g = ag * inv, out_b = ab * inv;
            float out_a = aa > 1.0f ? 1.0f : aa;

            uint8_t* dst = r->pixels + ((size_t)y * r->width + x) * 4;
            float dst_a = dst[3] / 255.0f;
            float ia = 1.0f - out_a;
            float res_a = out_a + dst_a * ia;
            dst[0] = (uint8_t)fminf(255.0f, (out_r * out_a + (dst[0] / 255.0f) * dst_a * ia) / (res_a > 0 ? res_a : 1) * 255.0f + 0.5f);
            dst[1] = (uint8_t)fminf(255.0f, (out_g * out_a + (dst[1] / 255.0f) * dst_a * ia) / (res_a > 0 ? res_a : 1) * 255.0f + 0.5f);
            dst[2] = (uint8_t)fminf(255.0f, (out_b * out_a + (dst[2] / 255.0f) * dst_a * ia) / (res_a > 0 ? res_a : 1) * 255.0f + 0.5f);
            dst[3] = (uint8_t)fminf(255.0f, res_a * 255.0f + 0.5f);
        }
    }
}

static void raster_triangle(NxRaster* r, const NxVertex* v0, const NxVertex* v1, const NxVertex* v2,
                            const NxTextureInfo* tex, bool alpha_only) {
    TriPrep t;
    if (!tri_prep(&t, v0, v1, v2)) return;
    raster_prim(r, &t, 1, tex, alpha_only);
}

void nx_raster_run(NxRaster* r, const NxDisplayList* dl) {
    for (uint32_t gi = 0; gi < dl->group_count; gi++) {
        const NxDrawGroup* g = &dl->groups[gi];
        const NxTextureInfo* tex = nx_tex_info(g->texture);
        if (g->has_scissor) {
            int clip_x0 = g->scissor[0], clip_y0 = g->scissor[1];
            int clip_x1 = g->scissor[0] + g->scissor[2], clip_y1 = g->scissor[1] + g->scissor[3];
            if (clip_x0 < 0) clip_x0 = 0;
            if (clip_y0 < 0) clip_y0 = 0;
            if (clip_x1 > r->width) clip_x1 = r->width;
            if (clip_y1 > r->height) clip_y1 = r->height;
            for (uint32_t k = 0; k + 2 < g->index_count; k += 3) {
                const NxVertex* v0 = &dl->verts[dl->indices[g->first_index + k]];
                const NxVertex* v1 = &dl->verts[dl->indices[g->first_index + k + 1]];
                const NxVertex* v2 = &dl->verts[dl->indices[g->first_index + k + 2]];
                float tminx = fminf(v0->x, fminf(v1->x, v2->x));
                float tmaxx = fmaxf(v0->x, fmaxf(v1->x, v2->x));
                float tminy = fminf(v0->y, fminf(v1->y, v2->y));
                float tmaxy = fmaxf(v0->y, fmaxf(v1->y, v2->y));
                if (tmaxx < clip_x0 || tminx >= clip_x1 || tmaxy < clip_y0 || tminy >= clip_y1) {
                    continue;
                }
                /* Sutherland-Hodgman clip to scissor, then rasterize the
                   clipped polygon as ONE primitive (fan partition) */
                NxVertex buf[2][10];
                int src_n = 3, which = 0;
                buf[0][0] = *v0; buf[0][1] = *v1; buf[0][2] = *v2;
                const float planes[4][4] = {
                    {(float)clip_x0, 0, 1, 0}, {(float)clip_x1, 0, -1, 0},
                    {0, (float)clip_y0, 0, 1}, {0, (float)clip_y1, 0, -1},
                };
                for (int p = 0; p < 4 && src_n > 0; p++) {
                    int dst_n = 0;
                    for (int i = 0; i < src_n; i++) {
                        NxVertex a = buf[which][i];
                        NxVertex b = buf[which][(i + 1) % src_n];
                        float da = planes[p][2] * a.x + planes[p][3] * a.y - planes[p][0] * planes[p][2] - planes[p][1] * planes[p][3];
                        float db = planes[p][2] * b.x + planes[p][3] * b.y - planes[p][0] * planes[p][2] - planes[p][1] * planes[p][3];
                        if (da >= 0) buf[1 - which][dst_n++] = a;
                        if ((da >= 0) != (db >= 0)) {
                            float t = da / (da - db);
                            NxVertex m = a;
                            m.x = a.x + (b.x - a.x) * t;
                            m.y = a.y + (b.y - a.y) * t;
                            m.u = a.u + (b.u - a.u) * t;
                            m.v = a.v + (b.v - a.v) * t;
                            buf[1 - which][dst_n++] = m;
                        }
                        if (dst_n >= 9) break;
                    }
                    which = 1 - which;
                    src_n = dst_n;
                }
                if (src_n < 3) continue;
                TriPrep tris[8];
                int nt = 0;
                for (int i = 2; i < src_n && nt < 8; i++) {
                    if (tri_prep(&tris[nt], &buf[which][0], &buf[which][i - 1], &buf[which][i]))
                        nt++;
                }
                if (nt > 0) raster_prim(r, tris, nt, tex, g->alpha_only);
            }
        } else {
            /* 6 consecutive indices = one quad primitive (nx_dl_emit_quad);
               accumulate both triangles per pixel and compose once so the
               shared quad diagonal cannot leave a seam line */
            uint32_t k = 0;
            for (; k + 5 < g->index_count; k += 6) {
                TriPrep tris[2];
                int nt = 0;
                if (tri_prep(&tris[nt], &dl->verts[dl->indices[g->first_index + k + 0]],
                             &dl->verts[dl->indices[g->first_index + k + 1]],
                             &dl->verts[dl->indices[g->first_index + k + 2]]))
                    nt++;
                if (tri_prep(&tris[nt], &dl->verts[dl->indices[g->first_index + k + 3]],
                             &dl->verts[dl->indices[g->first_index + k + 4]],
                             &dl->verts[dl->indices[g->first_index + k + 5]]))
                    nt++;
                if (nt > 0) raster_prim(r, tris, nt, tex, g->alpha_only);
            }
            /* leftover triangles of an odd fan (emit_poly) */
            for (; k + 2 < g->index_count; k += 3)
                raster_triangle(r, &dl->verts[dl->indices[g->first_index + k]],
                                &dl->verts[dl->indices[g->first_index + k + 1]],
                                &dl->verts[dl->indices[g->first_index + k + 2]], tex,
                                g->alpha_only);
        }
    }
}
