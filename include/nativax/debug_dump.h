#ifndef NATIVAX_DEBUG_DUMP_H
#define NATIVAX_DEBUG_DUMP_H

/*
    Debug dumps for the native pipeline: DOM tree and CSS rule/selector
    views, plus a machine-readable summary. Written to files by
    nativax-debug and to memory streams by tests. Style and layout dumps
    join here when style.c/layout.c land (Phase 6 steps 2-3).
*/

#include <stdio.h>

#include "nativax/css.h"
#include "nativax/display_list.h"
#include "nativax/dom.h"
#include "nativax/layout.h"

/* indented DOM tree: tag#id.class, attributes, escaped/truncated text */
void nxd_dump_dom(FILE* out, NxDocument* doc, NxNodeRef node, int depth);

/* JSON element tree (analogous to the V1 elements.json):
   {"children":[{"tag":"div","id":"x","class":["a"],"attrs":{...},
     "children":[...]} | {"text":"..."} | {"comment":"..."}]} */
void nxd_dump_dom_json(FILE* out, NxDocument* doc, NxNodeRef node);

/* canonical selector text for a parsed group ("div > .x#y[attr=val]:hover") */
void nxd_format_selector(const CsGroup* grp, char* buf, int cap);

/* rules: index, selector, media, declarations name: value (!important) */
void nxd_dump_css(FILE* out, CsSheet* sheet);

/* counts: elements/text/comments/max depth (root's own depth excluded) */
typedef struct NxdDomStats {
    int elements, text, comments, max_depth;
} NxdDomStats;

void nxd_dom_stats(NxDocument* doc, NxNodeRef node, int depth, NxdDomStats* st);

/* ---- layout (style/layout/paint phase) ---- */

/* indented box tree: tag#id.class, border-box/content-box geometry, runs */
void nxd_dump_layout(FILE* out, NxDocument* doc, const NxLayout* lay);

/* display list: groups, vertices, indices, scissor and layer records */
void nxd_dump_display_list(FILE* out, const NxDisplayList* dl);

/* box and text-run counts for summary.json */
void nxd_layout_stats(const NxLayout* lay, int* boxes, int* runs);

/* ---- machine-readable dumps (laboratory assertions) ---- */

/* {"viewport":[w,h],"boxes":[{node,tag,id,class,x,y,w,h,cx,cy,cw,ch,
     runs:[{text,x,y,w}]}]} in paint order (pre-order, viewport excluded). */
void nxd_dump_layout_json(FILE* out, NxDocument* doc, const NxLayout* lay);

/* {"styles":[{node,tag,id,class,display,width,height,margin,padding,border,
     color,bg,font_size,font_weight,text_align,line_height,opacity,radius,
     overflow,transform,flex:{...}}]} for every element slot with a style. */
void nxd_dump_styles_json(FILE* out, NxDocument* doc, const NxLayout* lay);

/* {"rules":[{selector,media,decls:[{name,value,important}]}],
     "dropped_rules":n,"dropped_decls":n} */
void nxd_dump_css_json(FILE* out, CsSheet* sheet);

#endif /* NATIVAX_DEBUG_DUMP_H */
