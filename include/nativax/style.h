#ifndef NATIVAX_STYLE_H
#define NATIVAX_STYLE_H

/*
    Style resolution: selector matching + cascade + inheritance.

    Produces one NxComputedStyle per element node. Only the properties the
    layout/paint pipeline actually consumes are resolved (documented subset):

      display (block|inline|none), width/height (auto|px|%), margin, padding,
      border-width/border-color, border-radius, color, background-color,
      font-size, font-weight, text-align, line-height, overflow,
      opacity, transform, transform-origin.

    Renderer effects are a deliberate subset: border-radius takes 1-4 px
    lengths (elliptical radii are not supported), overflow clips to the
    axis-aligned border box, transform supports translate/scale/rotate/matrix
    with px/unitless lengths (percentage translation is not supported), and
    opacity < 1 creates a real offscreen compositing layer.

    Values are resolved to CSS px at cascade time using the supplied viewport
    width for percentages. Unsupported or unknown properties keep the initial
    value; the resolver never invents values.

    Selector matching supports: type/#id/.class, attribute selectors, the
    pseudo-classes the CSS parser records, descendant/child/sibling combinators,
    and :not(). Pseudo-elements are ignored by style v1 (documented).
*/

#include <stdbool.h>
#include <stdint.h>

#include "nativax/css.h"
#include "nativax/display_list.h"
#include "nativax/dom.h"

typedef enum NxDisplayKind {
    NX_DISPLAY_BLOCK = 0,
    NX_DISPLAY_INLINE,
    NX_DISPLAY_FLEX,
    NX_DISPLAY_NONE,
} NxDisplayKind;

typedef enum NxFlexDirection { NX_FLEX_ROW=0, NX_FLEX_ROW_REVERSE, NX_FLEX_COLUMN, NX_FLEX_COLUMN_REVERSE } NxFlexDirection;
typedef enum NxFlexWrap { NX_FLEX_NOWRAP=0, NX_FLEX_WRAP, NX_FLEX_WRAP_REVERSE } NxFlexWrap;
typedef enum NxJustify { NX_JUSTIFY_START=0, NX_JUSTIFY_END, NX_JUSTIFY_CENTER, NX_JUSTIFY_SPACE_BETWEEN, NX_JUSTIFY_SPACE_AROUND, NX_JUSTIFY_SPACE_EVENLY } NxJustify;
typedef enum NxAlignKind { NX_ALIGN_LEFT = 0, NX_ALIGN_CENTER, NX_ALIGN_RIGHT } NxAlignKind;

typedef enum NxFlexAlign { NX_FLEX_ALIGN_STRETCH=0, NX_FLEX_ALIGN_START, NX_FLEX_ALIGN_END, NX_FLEX_ALIGN_CENTER, NX_FLEX_ALIGN_BASELINE } NxFlexAlign;

/* A computed length: absolute px, a deferred percentage, or auto. */
typedef struct NxLength {
    float px;    /* resolved px when neither pct_ nor auto_ */
    float pct;   /* percentage as a fraction (0.5 = 50%) when pct_ */
    bool auto_;
    bool pct_;   /* resolved by layout against the containing block */
} NxLength;

/* Resolve against an auto fallback and a containing-block context. */
NxLength nx_len_resolve(const NxLength* L, float auto_val, float ctx);

typedef struct NxComputedStyle {
    NxDisplayKind display;
    NxLength width, height;
    NxLength margin[4];  /* top, right, bottom, left */
    NxLength padding[4];
    float border[4];     /* border-width px, top/right/bottom/left */
    float r, g, b, a;    /* text color */
    float br, bg, bb, ba;/* background color (a<=0 = transparent) */
    /* border color: currentColor when bc_set is false (CSS initial value) */
    bool bc_set;
    float bc_r, bc_g, bc_b, bc_a;
    float font_size;
    int font_weight;
    NxAlignKind align;
    float line_height;   /* px; <=0 means "normal" (use font metrics) */

    /* Phase 3 renderer effects (documented subset) */
    float opacity;             /* 0..1, initial 1 */
    float radius[4];           /* border-radius px: tl, tr, br, bl; 0 = square */
    bool overflow_hidden;      /* overflow: hidden/clip (axis-aligned clip) */
    bool transform_set;        /* transform != none */
    NxMat2x3 transform;        /* CSS transform list, no origin applied */
    NxLength transform_origin[2]; /* x, y; initial 50% 50% */

    /* Flexbox (subset) */
    NxFlexDirection flex_direction;
    NxFlexWrap flex_wrap;
    NxJustify justify_content;
    NxFlexAlign align_items;
    NxFlexAlign align_content;
    float gap;                 /* px, main+cross (single gap value) */
    float flex_grow;
    float flex_shrink;
    NxLength flex_basis;       /* auto/px/% */
    int order;
} NxComputedStyle;

/* Match a parsed selector group against an element in the document.
   viewport_w is used for percentage resolution inside attribute-free matching
   (not needed for matching itself, kept for symmetry with the resolver). */
bool nx_selector_matches(NxDocument* doc, NxNodeRef el, const CsGroup* grp);

/* Parse every <style> element's text content into a sheet (document order).
   Returns the number written (up to cap); each sheet is owned by the caller
   (cs_sheet_free). <link rel=stylesheet> is not fetched in v1 (documented). */
int nx_style_collect_inline(NxDocument* doc, CsSheet** out, int cap);

/* Apply a declaration list (a style="" attribute's contents) on top of an
   already-computed style, as the last and most specific author declarations.
   !important declarations are applied after the normal ones. Returns false
   when the text could not be tokenized. */
bool nx_style_apply_declarations(NxComputedStyle* st, const char* text, int len);

/* Resolve styles for every element under root (inclusive when root is an
   element). Returns a heap array of NX_MAX_NODES entries; free with free().
   Index entries with nx_node_index(handle); non-element slots are zeroed.
   Inline style attributes participate in the cascade (after author rules). */
NxComputedStyle* nx_style_resolve(NxDocument* doc, const CsSheet* const* sheets, int sheet_count,
                                  float viewport_w, float default_font_size);

/* Resolve into a caller-provided array of `cap` entries (zeroed first).
   Nodes whose slot is >= cap are skipped. cap should be at least
   nx_node_slot_bound(doc)+1; the hot-reload path reuses the layout's array so
   restyling does not allocate a second full copy. */
bool nx_style_resolve_into(NxDocument* doc, const CsSheet* const* sheets, int sheet_count,
                           float viewport_w, float default_font_size, NxComputedStyle* out,
                           int cap);

#endif /* NATIVAX_STYLE_H */
