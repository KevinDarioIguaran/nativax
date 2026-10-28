#ifndef NATIVAX_LAYOUT_H
#define NATIVAX_LAYOUT_H

/*
    Layout: block and inline formatting over the styled DOM.

    Produces a box tree rooted at the document. Each box carries its content
    box position/size in CSS px plus the text runs that belong to it. v1
    supports:

      - block flow (vertical stacking, margin collapsing not yet applied),
      - inline text with word wrapping inside a block's content width,
      - width/height/margin/padding/border resolution,
      - text-align (left/center/right).

    Flexbox, grid, floats, absolute positioning and inline-block are not yet
    implemented (documented v1 gaps). Boxes for display:none are omitted.
*/

#include <stdbool.h>

#include "nativax/dom.h"
#include "nativax/style.h"

typedef struct NxTextRun {
    const char* utf8; /* points into the DOM text node */
    int len;
    float x, y;       /* run origin: x = left, y = baseline */
    float width;
} NxTextRun;

typedef struct NxBox {
    NxNodeRef node;
    const NxComputedStyle* style; /* borrowed from the style array */
    float x, y;                   /* border-box origin, CSS px */
    float w, h;                   /* border-box size */
    float content_x, content_y;   /* content-box origin */
    float content_w, content_h;
    NxTextRun* runs;
    int run_count, run_cap;
    struct NxBox** children;
    int child_count, child_cap;
} NxBox;

typedef struct NxLayout {
    NxBox* root;            /* viewport box; owned */
    NxComputedStyle* styles;/* owned, indexed by node slot; sized to the document */
    int styles_cap;         /* entries in styles (>= node slot bound at build) */
    float viewport_w, viewport_h;
    float* scroll_x;        /* per-node horizontal scroll offset, CSS px */
    float* scroll_y;        /* per-node vertical scroll offset, CSS px */
    int scroll_cap;
} NxLayout;

/* Build + run layout for a document with the given sheets. `font` is the loaded
   font used for text measurement. Returns NULL on allocation failure; otherwise
   free with nx_layout_free(). */
NxLayout* nx_layout_build(NxDocument* doc, const CsSheet* const* sheets, int sheet_count,
                           float viewport_w, float viewport_h, int32_t font);
void nx_layout_free(NxLayout* lay);

/* Recompute layout in place after a DOM/style mutation. */
void nx_layout_run(NxLayout* lay, NxDocument* doc, float viewport_w, float viewport_h,
                   int32_t font);

/* Set/get scroll offsets for a node (only meaningful for overflow:scroll/auto). */
void nx_layout_set_scroll(NxLayout* lay, NxNodeRef node, float x, float y);
void nx_layout_get_scroll(const NxLayout* lay, NxNodeRef node, float* x, float* y);

/* Re-resolve styles into the layout's own array (no second allocation) and
   re-run layout. Returns false when the document outgrew the array, in which
   case the caller must rebuild with nx_layout_build(). */
bool nx_layout_restyle(NxLayout* lay, NxDocument* doc, const CsSheet* const* sheets,
                       int sheet_count, float viewport_w, float viewport_h, int32_t font);

#endif /* NATIVAX_LAYOUT_H */
