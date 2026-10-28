#include "nativax/paint.h"

#include <stddef.h>

static NxColor rgba(float r, float g, float b, float a) {
    NxColor c;
    c.r = r; c.g = g; c.b = b; c.a = a;
    return c;
}

/* Paint one box: background, border, its own text runs, then children. */
static void paint_box(NxDisplayList* dl, const NxBox* box, int32_t font, int depth) {
    if (!box || depth > NX_MAX_DEPTH) return;
    const NxComputedStyle* st = box->style;

    if (st) {
        /* background covers the border box */
        if (st->ba > 0)
            nx_dl_fill_rect(dl, box->x, box->y, box->w, box->h,
                            rgba(st->br, st->bg, st->bb, st->ba), NULL);
        /* borders: v1 draws them as four solid strokes */
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
            /* v1: uniform outer stroke using the widest side */
            nx_dl_stroke_rect(dl, box->x + bw / 2, box->y + bw / 2,
                              box->w - bw, box->h - bw, bc, NULL, bw);
            (void)bw;
        }
        /* text runs */
        for (int i = 0; i < box->run_count; i++) {
            const NxTextRun* r = &box->runs[i];
            nx_dl_text(dl, r->x, r->y, font, st->font_size,
                       rgba(st->r, st->g, st->b, st->a), r->utf8, r->len);
        }
    }

    for (int i = 0; i < box->child_count; i++)
        paint_box(dl, box->children[i], font, depth + 1);
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
