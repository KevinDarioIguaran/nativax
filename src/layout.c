#include "nativax/layout.h"

#include <stdlib.h>
#include <string.h>

#include "nativax/text.h"

/* v1 scope (documented): normal-flow block boxes, inline text with word
   wrapping, text-align, auto margins (centering). No floats, no flex/grid
   algorithms, no absolute positioning, no inline-block boxes: inline elements
   are flattened into their containing block's line boxes (so their own
   backgrounds/borders do not paint — recorded gap). */

/* ---- box helpers --------------------------------------------------------- */

static NxBox* box_new(NxNodeRef node, const NxComputedStyle* st) {
    NxBox* b = (NxBox*)calloc(1, sizeof(NxBox));
    if (!b) return NULL;
    b->node = node;
    b->style = st;
    return b;
}

static bool box_add_child(NxBox* parent, NxBox* child) {
    if (parent->child_count == parent->child_cap) {
        int nc = parent->child_cap ? parent->child_cap * 2 : 4;
        NxBox** arr = (NxBox**)realloc(parent->children, (size_t)nc * sizeof(NxBox*));
        if (!arr) return false;
        parent->children = arr;
        parent->child_cap = nc;
    }
    parent->children[parent->child_count++] = child;
    return true;
}

static bool box_add_run(NxBox* b, const char* utf8, int len, float x, float y, float w) {
    if (b->run_count == b->run_cap) {
        int nc = b->run_cap ? b->run_cap * 2 : 4;
        NxTextRun* arr = (NxTextRun*)realloc(b->runs, (size_t)nc * sizeof(NxTextRun));
        if (!arr) return false;
        b->runs = arr;
        b->run_cap = nc;
    }
    NxTextRun* r = &b->runs[b->run_count++];
    r->utf8 = utf8; r->len = len; r->x = x; r->y = y; r->width = w;
    return true;
}

static void box_free_tree(NxBox* b) {
    if (!b) return;
    for (int i = 0; i < b->child_count; i++) box_free_tree(b->children[i]);
    free(b->children);
    free(b->runs);
    free(b);
}

/* Drop previously built children and runs: makes layout_block idempotent so
   nx_layout_run can re-run after mutations. */
static void box_clear_children(NxBox* b) {
    for (int i = 0; i < b->child_count; i++) box_free_tree(b->children[i]);
    b->child_count = 0;
    b->run_count = 0;
}

/* ---- text measurement ---------------------------------------------------- */

#define NX_MAX_WORDS 512

typedef struct Word {
    const char* s;
    int len;
    float w;
} Word;

/* ---- line breaking ------------------------------------------------------- */

typedef struct LineState {
    NxBox* box;
    const NxComputedStyle* st;
    float* cy;       /* vertical pen of the owning layout_block */
    float cx;        /* line box left edge */
    float max_x;     /* right limit */
    float x, w;      /* pen and consumed width on the current line */
    float ascent, descent, lh;
    float content_w;
    int run_start;   /* box->run_count when the current line started */
    bool ws_pending; /* collapsed whitespace carried to the next word */
    int32_t font;
} LineState;

static void line_init(LineState* ls, NxBox* box, float cx, float content_w,
                      const NxComputedStyle* st, float* cy, int32_t font) {
    ls->box = box;
    ls->st = st;
    ls->cy = cy;
    ls->cx = cx;
    ls->content_w = content_w;
    ls->max_x = cx + content_w;
    ls->x = cx;
    ls->w = 0;
    ls->font = font;
    ls->ascent = nx_font_ascent(font, st->font_size);
    ls->descent = nx_font_descent(font, st->font_size);
    ls->lh = st->line_height > 0 ? st->line_height : (ls->ascent + ls->descent);
    ls->run_start = box->run_count;
    ls->ws_pending = false;
}

/* Apply text-align to the runs of the current line. */
static void line_flush_align(LineState* ls) {
    const NxComputedStyle* st = ls->st;
    if (st->align == NX_ALIGN_LEFT || ls->content_w <= 0) return;
    float slack = ls->content_w - ls->w;
    if (slack < 0) slack = 0;
    float off = st->align == NX_ALIGN_CENTER ? slack / 2 : slack;
    for (int i = ls->run_start; i < ls->box->run_count; i++)
        ls->box->runs[i].x += off;
}

/* Finish the current line: align it and advance the vertical pen. */
static void line_end(LineState* ls) {
    if (ls->box->run_count <= ls->run_start) return;
    line_flush_align(ls);
    *ls->cy += ls->lh;
    ls->run_start = ls->box->run_count;
    ls->x = ls->cx;
    ls->w = 0;
}

/* Place one word preceded by `gap` px of collapsed whitespace. The gap is
   dropped when the line wraps or is empty (CSS discards line-leading space). */
static void line_word(LineState* ls, const Word* wd, float gap) {
    if (ls->w > 0) {
        if (ls->x + ls->w + gap + wd->w > ls->max_x) {
            line_end(ls);
            gap = 0;
        } else {
            ls->w += gap;
        }
    }
    box_add_run(ls->box, wd->s, wd->len, ls->x + ls->w, *ls->cy + ls->ascent, wd->w);
    ls->w += wd->w;
}

/* Split a text node into words and place them. Whitespace runs collapse into
   one space (CSS text processing, <pre> not supported in v1); trailing
   whitespace stays pending so `a <span>b</span>` keeps its separating space. */
static void emit_text(LineState* ls, const char* txt, int len) {
    float space_w = nx_font_advance(ls->font, ls->st->font_size, " ", 1);
    bool pending = ls->ws_pending;
    int i = 0;
    while (i < len) {
        char c = txt[i];
        if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
            pending = true;
            i++;
            continue;
        }
        int start = i;
        while (i < len && !(txt[i] == ' ' || txt[i] == '\t' || txt[i] == '\n' ||
                            txt[i] == '\r'))
            i++;
        Word wd;
        wd.s = txt + start;
        wd.len = i - start;
        wd.w = nx_font_advance(ls->font, ls->st->font_size, wd.s, wd.len);
        line_word(ls, &wd, pending ? space_w : 0);
        pending = false;
    }
    ls->ws_pending = pending;
}

/* ---- layout -------------------------------------------------------------- */

static void layout_block(NxBox* box, NxDocument* doc, const NxComputedStyle* styles,
                         float x, float y, float avail_w, int32_t font, int depth);

static NxBox* make_box(NxDocument* doc, NxNodeRef node, const NxComputedStyle* styles) {
    const NxComputedStyle* st = &styles[nx_node_index(node)];
    if (st->display == NX_DISPLAY_NONE) return NULL;
    return box_new(node, st);
}

/* Emit all text inside an inline subtree onto the current line boxes. */
static void emit_inline_text(NxDocument* doc, NxNodeRef node, LineState* ls, int depth) {
    if (depth > NX_MAX_DEPTH) return;
    for (NxNodeRef c = nx_node_first_child(doc, node); c;
         c = nx_node_next_sibling(doc, c)) {
        NxNodeType t = nx_node_type(doc, c);
        if (t == NX_NODE_COMMENT) continue;
        if (t == NX_NODE_TEXT) {
            int len = 0;
            const char* txt = nx_node_text(doc, c, &len);
            if (!txt || len == 0) continue;
            emit_text(ls, txt, len);
        } else {
            emit_inline_text(doc, c, ls, depth + 1);
        }
    }
}

static void layout_flex(NxBox* box, NxDocument* doc, const NxComputedStyle* styles,
                      float x, float y, float avail_w, int32_t font, int depth);

static void layout_block(NxBox* box, NxDocument* doc, const NxComputedStyle* styles,
                         float x, float y, float avail_w, int32_t font, int depth) {
    if (depth > NX_MAX_DEPTH) return;
    const NxComputedStyle* st = box->style;

    box_clear_children(box); /* idempotent re-run */

    float bl = st->border[3], brr = st->border[1];
    float bt = st->border[0], bb = st->border[2];
    float pl_r = nx_len_resolve(&st->padding[3], 0, avail_w).px;
    float pr_r = nx_len_resolve(&st->padding[1], 0, avail_w).px;
    float pt_r = nx_len_resolve(&st->padding[0], 0, avail_w).px;
    float pb_r = nx_len_resolve(&st->padding[2], 0, avail_w).px;
    float ml_r = nx_len_resolve(&st->margin[3], 0, avail_w).px;
    float mr_r = nx_len_resolve(&st->margin[1], 0, avail_w).px;

    /* width resolution + auto margins (CSS 2.1 §10.3.3, simplified) */
    float bw;
    if (st->width.auto_) {
        if (st->margin[3].auto_) ml_r = 0;
        if (st->margin[1].auto_) mr_r = 0;
        bw = avail_w - ml_r - mr_r;
    } else {
        bw = nx_len_resolve(&st->width, 0, avail_w).px;
        if (st->margin[3].auto_ && st->margin[1].auto_) {
            float extra = avail_w - bw;
            if (extra < 0) extra = 0;
            ml_r = mr_r = extra / 2;
        } else if (st->margin[3].auto_) {
            ml_r = avail_w - bw - mr_r;
        } else if (st->margin[1].auto_) {
            mr_r = avail_w - bw - ml_r;
        }
    }
    if (bw < 0) bw = 0;

    float content_w = bw - pl_r - pr_r - bl - brr;
    if (content_w < 0) content_w = 0;

    box->x = x + ml_r;
    box->y = y;
    box->w = bw;
    box->content_w = content_w;
    box->content_x = box->x + bl + pl_r;
    box->content_y = box->y + bt + pt_r;

    float cy = box->content_y;
    if (st->display == NX_DISPLAY_FLEX) {
        layout_flex(box, doc, styles, x, y, avail_w, font, depth);
        return;
    }
    LineState ls;
    line_init(&ls, box, box->content_x, content_w, st, &cy, font);

    NxNodeRef node = box->node;
    for (NxNodeRef ch = nx_node_first_child(doc, node); ch;
         ch = nx_node_next_sibling(doc, ch)) {
        NxNodeType t = nx_node_type(doc, ch);
        if (t == NX_NODE_COMMENT) continue;

        if (t == NX_NODE_TEXT) {
            int len = 0;
            const char* txt = nx_node_text(doc, ch, &len);
            if (!txt || len == 0) continue;
            emit_text(&ls, txt, len);
        } else {
            const NxComputedStyle* cst = &styles[nx_node_index(ch)];
            if (cst->display == NX_DISPLAY_NONE) continue;
            if (cst->display == NX_DISPLAY_BLOCK || cst->display == NX_DISPLAY_FLEX) {
                line_end(&ls); /* blocks drop below the pending line */
                ls.ws_pending = false; /* whitespace around blocks is discarded */
                NxBox* child = make_box(doc, ch, styles);
                if (child && box_add_child(box, child)) {
                    layout_block(child, doc, styles, ls.cx, cy, content_w, font, depth + 1);
                    cy += child->h;
                }
            } else {
                emit_inline_text(doc, ch, &ls, depth + 1);
            }
        }
    }
    line_end(&ls);

    float used_h = cy - box->content_y;
    /* CSS 2.1 §10.6.4: a specified height wins (content overflows); a
       percentage height with an auto-height parent behaves as auto. */
    float h;
    if (st->height.pct_ || st->height.auto_) h = used_h + bt + pt_r + pb_r + bb;
    else h = st->height.px;
    box->h = h;
    box->content_h = used_h;
}

void nx_layout_run(NxLayout* lay, NxDocument* doc, float viewport_w, float viewport_h,
                   int32_t font) {
    if (!lay || !lay->root) return;
    lay->viewport_w = viewport_w;
    lay->viewport_h = viewport_h;
    NxBox* root = lay->root;
    for (int i = 0; i < root->child_count; i++)
        layout_block(root->children[i], doc, lay->styles, 0, 0, viewport_w, font, 0);
}

bool nx_layout_restyle(NxLayout* lay, NxDocument* doc, const CsSheet* const* sheets,
                       int sheet_count, float viewport_w, float viewport_h, int32_t font) {
    if (!lay || !doc || !lay->styles) return false;
    if (nx_node_slot_bound(doc) > lay->styles_cap) return false;
    if (!nx_style_resolve_into(doc, sheets, sheet_count, viewport_w, 16.0f, lay->styles,
                               lay->styles_cap))
        return false;
    nx_layout_run(lay, doc, viewport_w, viewport_h, font);
    return true;
}

void nx_layout_free(NxLayout* lay) {
    if (!lay) return;
    box_free_tree(lay->root);
    free(lay->styles);
    free(lay);
}

NxLayout* nx_layout_build(NxDocument* doc, const CsSheet* const* sheets, int sheet_count,
                           float viewport_w, float viewport_h, int32_t font) {
    if (!doc) return NULL;
    /* Size per-node arrays to the live document, not the 100k hard limit:
       a small page must not pay for a 100k-entry style table. */
    int cap = nx_node_slot_bound(doc);
    if (cap < 1) cap = 1;
    NxComputedStyle* styles = (NxComputedStyle*)calloc((size_t)cap, sizeof(NxComputedStyle));
    if (!styles) return NULL;
    if (!nx_style_resolve_into(doc, sheets, sheet_count, viewport_w, 16.0f, styles, cap)) {
        free(styles);
        return NULL;
    }

    NxLayout* lay = (NxLayout*)calloc(1, sizeof(NxLayout));
    if (!lay) { free(styles); return NULL; }
    lay->styles = styles;
    lay->styles_cap = cap;
    lay->viewport_w = viewport_w;
    lay->viewport_h = viewport_h;

    NxBox* root = box_new(0, NULL);
    if (!root) { free(styles); free(lay); return NULL; }
    lay->root = root;

    NxNodeRef doc_root = nx_doc_root(doc);
    for (NxNodeRef c = nx_node_first_child(doc, doc_root); c;
         c = nx_node_next_sibling(doc, c)) {
        if (nx_node_type(doc, c) != NX_NODE_ELEMENT) continue;
        if (styles[nx_node_index(c)].display == NX_DISPLAY_NONE) continue;
        NxBox* child = make_box(doc, c, styles);
        if (!child) continue;
        if (!box_add_child(root, child)) { box_free_tree(child); continue; }
        layout_block(child, doc, styles, 0, 0, viewport_w, font, 0);
    }
    return lay;
}

/* ---- Flexbox (subset) --------------------------------------------------- */
typedef struct FlexItem {
    NxBox* box;
    int order;
    float grow, shrink, base, final_main, cross_pref;
} FlexItem;

static int flex_cmp(const void* a, const void* b) {
    const FlexItem* x = a; const FlexItem* y = b;
    if (x->order != y->order) return x->order - y->order;
    return 0;
}

static void layout_flex(NxBox* box, NxDocument* doc, const NxComputedStyle* styles,
                        float x, float y, float avail_w, int32_t font, int depth) {
    if (depth > NX_MAX_DEPTH) return;
    const NxComputedStyle* st = box->style;
    /* geometry already computed by caller */
    float bt = st->border[0], bb = st->border[2], bl = st->border[3], brr = st->border[1];
    float pt_r = nx_len_resolve(&st->padding[0], 0, avail_w).px;
    float pb_r = nx_len_resolve(&st->padding[2], 0, avail_w).px;
    (void)pt_r; (void)pb_r; (void)bl; (void)brr;
    bool horizontal = (st->flex_direction == NX_FLEX_ROW ||
                       st->flex_direction == NX_FLEX_ROW_REVERSE);
    bool reverse = (st->flex_direction == NX_FLEX_ROW_REVERSE ||
                    st->flex_direction == NX_FLEX_COLUMN_REVERSE);

    /* collect items */
    int cap = 8, n = 0;
    FlexItem* items = (FlexItem*)malloc((size_t)cap * sizeof(FlexItem));
    for (NxNodeRef ch = nx_node_first_child(doc, box->node); ch;
         ch = nx_node_next_sibling(doc, ch)) {
        if (nx_node_type(doc, ch) != NX_NODE_ELEMENT) continue;
        const NxComputedStyle* cst = &styles[nx_node_index(ch)];
        if (cst->display == NX_DISPLAY_NONE) continue;
        NxBox* child = make_box(doc, ch, styles);
        if (!child) continue;
        if (!box_add_child(box, child)) { box_free_tree(child); continue; }
        /* preferred layout at full container size */
        layout_block(child, doc, styles, 0, 0,
                     horizontal ? box->content_w : box->content_w, font, depth + 1);
        if (n == cap) {
            cap *= 2;
            items = (FlexItem*)realloc(items, (size_t)cap * sizeof(FlexItem));
        }
        items[n].box = child;
        items[n].order = cst->order;
        items[n].grow = cst->flex_grow;
        items[n].shrink = cst->flex_shrink;
        /* flex basis */
        float basis = 0;
        if (cst->flex_basis.auto_) {
            basis = horizontal ? child->w : child->h;
        } else if (cst->flex_basis.pct_) {
            float ctx = horizontal ? box->content_w : (st->height.pct_ || st->height.auto_ ? 0 : box->content_h);
            if (ctx <= 0) ctx = horizontal ? box->content_w : child->h;
            basis = cst->flex_basis.pct * ctx;
        } else {
            basis = cst->flex_basis.px;
        }
        items[n].base = basis;
        items[n].cross_pref = horizontal ? child->h : child->w;
        items[n].final_main = basis;
        n++;
    }

    if (n == 0) {
        box->h = (st->height.pct_ || st->height.auto_) ? (box->content_y - box->y + 0) : st->height.px;
        if (st->height.auto_ || st->height.pct_) {
            box->h = bt + pt_r + pb_r + bb;
            box->content_h = 0;
        }
        free(items);
        return;
    }

    /* sort by order */
    qsort(items, (size_t)n, sizeof(FlexItem), flex_cmp);

    float main_avail = horizontal ? box->content_w : ((st->height.pct_ || st->height.auto_) ? 0 : (box->h - bt - pt_r - pb_r - bb));
    /* if auto height, main_avail unknown -> use sum of bases */
    float total_base = 0, total_grow = 0, total_shrink = 0;
    for (int i = 0; i < n; i++) total_base += items[i].base;
    for (int i = 0; i < n; i++) { total_grow += items[i].grow; total_shrink += items[i].shrink * items[i].base; }
    float gaps = st->gap * (n > 1 ? n - 1 : 0);

    if (main_avail <= 0) {
        main_avail = total_base + gaps; /* auto: no free space */
    }
    float free_space = main_avail - total_base - gaps;

    if (free_space >= 0) {
        if (total_grow > 0) {
            for (int i = 0; i < n; i++) {
                items[i].final_main = items[i].base + free_space * (items[i].grow / total_grow);
            }
        } else {
            for (int i = 0; i < n; i++) items[i].final_main = items[i].base;
        }
    } else {
        float deficit = -free_space;
        if (total_shrink > 0) {
            for (int i = 0; i < n; i++) {
                float factor = (items[i].shrink * items[i].base) / (total_shrink > 0 ? total_shrink : 1);
                items[i].final_main = items[i].base - deficit * factor;
                if (items[i].final_main < 0) items[i].final_main = 0;
            }
        } else {
            for (int i = 0; i < n; i++) items[i].final_main = items[i].base;
        }
    }

    /* recompute leftover for justify */
    float sum_final = 0;
    for (int i = 0; i < n; i++) sum_final += items[i].final_main;
    float leftover = main_avail - sum_final - gaps;

    float start_offset = 0, between = 0;
    switch (st->justify_content) {
        case NX_JUSTIFY_START: start_offset = 0; between = 0; break;
        case NX_JUSTIFY_END: start_offset = leftover; between = 0; break;
        case NX_JUSTIFY_CENTER: start_offset = leftover / 2; between = 0; break;
        case NX_JUSTIFY_SPACE_BETWEEN:
            start_offset = 0;
            between = (n > 1) ? leftover / (n - 1) : 0;
            break;
        case NX_JUSTIFY_SPACE_AROUND:
            between = (n > 0) ? leftover / n : 0;
            start_offset = between / 2;
            break;
        case NX_JUSTIFY_SPACE_EVENLY:
            between = (n > 0) ? leftover / (n + 1) : 0;
            start_offset = between;
            break;
    }

    /* cross container size */
    float max_cross = 0;
    for (int i = 0; i < n; i++) if (items[i].cross_pref > max_cross) max_cross = items[i].cross_pref;
    float cross_container = 0;
    if (!(st->height.pct_ || st->height.auto_)) {
        cross_container = (box->h - bt - pt_r - pb_r - bb);
    } else {
        cross_container = max_cross;
    }
    if (cross_container < max_cross) cross_container = max_cross;

    /* position */
    float main_cursor = (horizontal ? box->content_x : box->content_y) + start_offset;
    if (reverse) main_cursor = (horizontal ? box->content_x : box->content_y) + main_avail - start_offset;

    for (int i = 0; i < n; i++) {
        FlexItem* it = reverse ? &items[n - 1 - i] : &items[i];
        NxBox* child = it->box;
        float cross_size = it->cross_pref;
        if (st->align_items == NX_FLEX_ALIGN_STRETCH) cross_size = cross_container;
        /* align-items mapping */
        float cross_offset = 0;
        switch (st->align_items) {
            case NX_FLEX_ALIGN_START: cross_offset = 0; break;
            case NX_FLEX_ALIGN_END: cross_offset = cross_container - cross_size; break;
            case NX_FLEX_ALIGN_CENTER: cross_offset = (cross_container - cross_size) / 2; break;
            case NX_FLEX_ALIGN_STRETCH: cross_offset = 0; break;
            case NX_FLEX_ALIGN_BASELINE: cross_offset = 0; break;
        }

        if (horizontal) {
            child->w = it->final_main;
            child->h = cross_size;
            child->x = main_cursor;
            child->y = box->content_y + cross_offset;
            child->content_w = child->w - child->style->padding[1].px - child->style->padding[3].px - child->style->border[1] - child->style->border[3];
            if (child->content_w < 0) child->content_w = 0;
            child->content_x = child->x + child->style->border[3] + nx_len_resolve(&child->style->padding[3],0,child->w).px;
            child->content_y = child->y + child->style->border[0] + nx_len_resolve(&child->style->padding[0],0,child->w).px;
            main_cursor += it->final_main + st->gap + between;
        } else {
            child->h = it->final_main;
            child->w = cross_size;
            child->x = box->content_x + cross_offset;
            child->y = main_cursor;
            child->content_w = child->w - child->style->padding[1].px - child->style->padding[3].px - child->style->border[1] - child->style->border[3];
            if (child->content_w < 0) child->content_w = 0;
            child->content_x = child->x + child->style->border[3] + nx_len_resolve(&child->style->padding[3],0,child->w).px;
            child->content_y = child->y + child->style->border[0] + nx_len_resolve(&child->style->padding[0],0,child->w).px;
            main_cursor += it->final_main + st->gap + between;
        }
    }

    /* container height */
    if (st->height.auto_ || st->height.pct_) {
        if (horizontal) {
            box->h = bt + pt_r + pb_r + bb + cross_container;
            box->content_h = cross_container;
        } else {
            box->h = bt + pt_r + pb_r + bb + sum_final + st->gap * (n > 1 ? n - 1 : 0);
            box->content_h = sum_final + st->gap * (n > 1 ? n - 1 : 0);
        }
    }
    free(items);
}
