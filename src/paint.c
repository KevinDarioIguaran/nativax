#include "nativax/paint.h"

#include <stddef.h>

static NxColor rgba(float r, float g, float b, float a) {
    NxColor c;
    c.r = r; c.g = g; c.b = b; c.a = a;
    return c;
}

NxMat2x3 nx_box_transform(const NxBox* box) {
    NxMat2x3 id = nx_mat_identity();
    if (!box || !box->style || !box->style->transform_set) return id;
    const NxComputedStyle* st = box->style;
    /* transform-origin defaults to the border-box center (50% 50%) */
    float ox = nx_len_resolve(&st->transform_origin[0], box->w * 0.5f, box->w).px;
    float oy = nx_len_resolve(&st->transform_origin[1], box->h * 0.5f, box->h).px;
    NxMat2x3 m = nx_mat_translate(ox, oy);
    m = nx_mat_mul(&m, &st->transform);
    NxMat2x3 back = nx_mat_translate(-ox, -oy);
    return nx_mat_mul(&m, &back);
}

static const float* box_radii(const NxComputedStyle* st, float out[4]) {
    if (!st) return NULL;
    if (st->radius[0] <= 0 && st->radius[1] <= 0 && st->radius[2] <= 0 && st->radius[3] <= 0)
        return NULL;
    for (int i = 0; i < 4; i++) out[i] = st->radius[i];
    return out;
}

/* Paint one box: background, border, its own text runs, then children.
   The element's transform wraps everything it paints (background included);
   overflow:hidden clips its text and descendants; opacity<1 wraps the whole
   subtree in a real offscreen compositing layer (see raster.c/gfx_sokol.c). */
static void paint_box(NxDisplayList* dl, const NxBox* box, int32_t font, int depth) {
    if (!box || depth > NX_MAX_DEPTH) return;
    const NxComputedStyle* st = box->style;

    bool layered = st && st->opacity < 1.0f;
    if (layered) nx_dl_begin_layer(dl, st->opacity);

    bool transformed = st && st->transform_set;
    if (transformed) {
        NxMat2x3 m = nx_box_transform(box);
        nx_dl_push_transform(dl, &m);
    }

    float radii[4];
    const float* rr = box_radii(st, radii);

    if (st) {
        /* background covers the border box */
        if (st->ba > 0)
            nx_dl_fill_rect(dl, box->x, box->y, box->w, box->h,
                            rgba(st->br, st->bg, st->bb, st->ba), rr);
        /* borders: v1 draws them as four solid strokes (uniform widest side) */
        bool any_border = st->border[0] > 0 || st->border[1] > 0 ||
                          st->border[2] > 0 || st->border[3] > 0;
        if (any_border) {
            /* border-color: currentColor unless a border color was declared */
            NxColor bc = st->bc_set ? rgba(st->bc_r, st->bc_g, st->bc_b, st->bc_a)
                                    : rgba(st->r, st->g, st->b, st->a);
            float bw = st->border[0];
            if (st->border[1] > bw) bw = st->border[1];
            if (st->border[2] > bw) bw = st->border[2];
            if (st->border[3] > bw) bw = st->border[3];
            nx_dl_stroke_rect(dl, box->x, box->y, box->w, box->h, bc, rr, bw);
        }
    }

    bool clipped = st && st->overflow_hidden && box->w > 0 && box->h > 0;
    if (clipped) nx_dl_push_clip(dl, box->x, box->y, box->w, box->h);

    if (st) {
        /* text runs */
        for (int i = 0; i < box->run_count; i++) {
            const NxTextRun* r = &box->runs[i];
            nx_dl_text(dl, r->x, r->y, font, st->font_size,
                       rgba(st->r, st->g, st->b, st->a), r->utf8, r->len);
        }
    }

    for (int i = 0; i < box->child_count; i++)
        paint_box(dl, box->children[i], font, depth + 1);

    if (clipped) nx_dl_pop_clip(dl);
    if (transformed) nx_dl_pop_transform(dl);
    if (layered) nx_dl_end_layer(dl);
}

bool nx_paint(NxDisplayList* dl, const NxLayout* lay, int32_t font) {
    if (!dl || !lay || !lay->root) return false;
    nx_dl_reset(dl);
    /* page background: white if unspecified (initial value is transparent) */
    nx_dl_fill_rect(dl, 0, 0, lay->viewport_w, lay->viewport_h,
                    rgba(1, 1, 1, 1), NULL);
    for (int i = 0; i < lay->root->child_count; i++)
        paint_box(dl, lay->root->children[i], font, 0);
    return true;
}
