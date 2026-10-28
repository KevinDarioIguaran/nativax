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
            if (cst->display == NX_DISPLAY_BLOCK) {
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
