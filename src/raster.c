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

static void raster_triangle(NxRaster* r, const NxVertex* v0, const NxVertex* v1, const NxVertex* v2,
                            const NxTextureInfo* tex, bool alpha_only) {
    float area = edge(v0->x, v0->y, v1->x, v1->y, v2->x, v2->y);
    if (fabsf(area) < 1e-6f) return;
    float inv_area = 1.0f / area;
    int winding = area > 0 ? 1 : -1;

    int minx = (int)floorf(fminf(v0->x, fminf(v1->x, v2->x)));
    int maxx = (int)ceilf(fmaxf(v0->x, fmaxf(v1->x, v2->x)));
    int miny = (int)floorf(fminf(v0->y, fminf(v1->y, v2->y)));
    int maxy = (int)ceilf(fmaxf(v0->y, fmaxf(v1->y, v2->y)));
    if (minx < 0) minx = 0;
    if (miny < 0) miny = 0;
    if (maxx > r->width) maxx = r->width;
    if (maxy > r->height) maxy = r->height;

    static const float subs[4][2] = {{0.25f, 0.25f}, {0.75f, 0.25f}, {0.25f, 0.75f}, {0.75f, 0.75f}};

    for (int y = miny; y < maxy; y++) {
        for (int x = minx; x < maxx; x++) {
            int hits = 0;
            for (int s = 0; s < 4; s++) {
                float px = x + subs[s][0], py = y + subs[s][1];
                float e0 = edge(v0->x, v0->y, v1->x, v1->y, px, py) * winding;
                float e1 = edge(v1->x, v1->y, v2->x, v2->y, px, py) * winding;
                float e2 = edge(v2->x, v2->y, v0->x, v0->y, px, py) * winding;
                if (e0 >= 0 && e1 >= 0 && e2 >= 0) hits++;
            }
            if (hits == 0) continue;
            float cov = hits * 0.25f;

            /* barycentric for attribute interpolation */
            float px = x + 0.5f, py = y + 0.5f;
            float b0 = edge(v1->x, v1->y, v2->x, v2->y, px, py) * inv_area; /* weight of v0 */
            float b1 = edge(v2->x, v2->y, v0->x, v0->y, px, py) * inv_area; /* weight of v1 */
            float b2 = 1.0f - b0 - b1;                                       /* weight of v2 */
            float u = v0->u * b0 + v1->u * b1 + v2->u * b2;
            float v = v0->v * b0 + v1->v * b1 + v2->v * b2;

            /* vertex rgba memory layout is [r,g,b,a] (see nx_rgba_pack) */
            float sr, sg, sb, sa;
            sample_tex(tex, u, v, &sr, &sg, &sb, &sa);

            float fr = (v0->rgba & 255) * b0 + (v1->rgba & 255) * b1 + (v2->rgba & 255) * b2;
            float fg = ((v0->rgba >> 8) & 255) * b0 + ((v1->rgba >> 8) & 255) * b1 + ((v2->rgba >> 8) & 255) * b2;
            float fb = ((v0->rgba >> 16) & 255) * b0 + ((v1->rgba >> 16) & 255) * b1 + ((v2->rgba >> 16) & 255) * b2;
            float fa = ((v0->rgba >> 24) & 255) * b0 + ((v1->rgba >> 24) & 255) * b1 + ((v2->rgba >> 24) & 255) * b2;
            fr /= 255.0f; fg /= 255.0f; fb /= 255.0f; fa /= 255.0f;

            float out_r, out_g, out_b, out_a;
            if (alpha_only) {
                out_r = fr;
                out_g = fg;
                out_b = fb;
                out_a = fa * sa;
            } else {
                out_r = fr * sr;
                out_g = fg * sg;
                out_b = fb * sb;
                out_a = fa * sa;
            }
            out_a *= cov;
            if (out_a <= 0) continue;

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

void nx_raster_run(NxRaster* r, const NxDisplayList* dl) {
    for (uint32_t gi = 0; gi < dl->group_count; gi++) {
        const NxDrawGroup* g = &dl->groups[gi];
        const NxTextureInfo* tex = nx_tex_info(g->texture);
        int clip_x0 = 0, clip_y0 = 0, clip_x1 = r->width, clip_y1 = r->height;
        if (g->has_scissor) {
            clip_x0 = g->scissor[0];
            clip_y0 = g->scissor[1];
            clip_x1 = g->scissor[0] + g->scissor[2];
            clip_y1 = g->scissor[1] + g->scissor[3];
            if (clip_x0 < 0) clip_x0 = 0;
            if (clip_y0 < 0) clip_y0 = 0;
            if (clip_x1 > r->width) clip_x1 = r->width;
            if (clip_y1 > r->height) clip_y1 = r->height;
        }
        for (uint32_t k = 0; k + 2 < g->index_count; k += 3) {
            const NxVertex* v0 = &dl->verts[dl->indices[g->first_index + k]];
            const NxVertex* v1 = &dl->verts[dl->indices[g->first_index + k + 1]];
            const NxVertex* v2 = &dl->verts[dl->indices[g->first_index + k + 2]];
            if (g->has_scissor) {
                /* clip triangles against the scissor rect in pixel space by
                   clamping raster bounds: cheap approach — clip each triangle
                   via bbox filter, then raster into full buffer with an
                   intersected bbox. Reuse raster_triangle with a temp raster
                   view is complex; instead clip with Sutherland-Hodgman into
                   up to 4 triangles? v1: bbox-cull + per-pixel scissor test. */
                float tminx = fminf(v0->x, fminf(v1->x, v2->x));
                float tmaxx = fmaxf(v0->x, fmaxf(v1->x, v2->x));
                float tminy = fminf(v0->y, fminf(v1->y, v2->y));
                float tmaxy = fmaxf(v0->y, fmaxf(v1->y, v2->y));
                if (tmaxx < clip_x0 || tminx >= clip_x1 || tmaxy < clip_y0 || tminy >= clip_y1) {
                    continue;
                }
                /* Sutherland-Hodgman clip to scissor for correct AA edges */
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
                for (int i = 2; i < src_n; i++) {
                    raster_triangle(r, &buf[which][0], &buf[which][i - 1], &buf[which][i], tex,
                                    g->alpha_only);
                }
            } else {
                raster_triangle(r, v0, v1, v2, tex, g->alpha_only);
            }
        }
    }
}
