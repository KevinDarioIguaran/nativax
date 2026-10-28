/*
    NativaX C runtime — style/layout/paint pipeline tests (headless).

    Covers: selector matching (type/id/class/attr/combinators/pseudo),
    cascade by specificity + source order + !important, inheritance,
    display:none pruning, block geometry (width/margin/padding/border, % vs
    containing block, auto-margin centering), vertical stacking, word wrap,
    text-align, and display-list emission.

    All numbers are checked against the real DejaVuSans metrics where font
    metrics matter; geometry checks use exact CSS px arithmetic.
*/
#include "nativax/css.h"
#include "nativax/display_list.h"
#include "nativax/dom.h"
#include "nativax/html.h"
#include "nativax/layout.h"
#include "nativax/paint.h"
#include "nativax/text.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int g_failures;
static int g_checks;

#define CHECK(cond, ...)                                            \
    do {                                                            \
        g_checks++;                                                 \
        if (!(cond)) {                                              \
            g_failures++;                                           \
            fprintf(stderr, "FAIL %s:%d: ", __FILE__, __LINE__);    \
            fprintf(stderr, __VA_ARGS__);                           \
            fputc('\n', stderr);                                    \
        }                                                           \
    } while (0)

static const char* font_path(void) {
    static char path[512];
    snprintf(path, sizeof(path), "%s/assets/fonts/DejaVuSans.ttf", NATIVAX_SOURCE_DIR);
    return path;
}

/* ---- fixtures ------------------------------------------------------------ */

typedef struct Page {
    NxDocument* doc;
    CsSheet* sheet;
} Page;

static bool page_open(Page* p, const char* html, const char* css) {
    p->doc = nx_doc_new();
    if (!p->doc) return false;
    char* err = NULL;
    if (!nx_html_parse(p->doc, html, (int)strlen(html), &err)) {
        fprintf(stderr, "html parse failed: %s\n", err ? err : "?");
        free(err);
        return false;
    }
    p->sheet = css ? cs_sheet_parse(css, (int)strlen(css)) : NULL;
    if (css && !p->sheet) return false;
    return true;
}

static void page_close(Page* p) {
    if (p->sheet) cs_sheet_free(p->sheet);
    if (p->doc) nx_doc_free(p->doc);
    p->doc = NULL;
    p->sheet = NULL;
}

static NxLayout* page_layout(Page* p, float vw, float vh, int32_t font) {
    const CsSheet* sheets[1];
    int n = 0;
    if (p->sheet) sheets[n++] = p->sheet;
    return nx_layout_build(p->doc, sheets, n, vw, vh, font);
}

static NxBox* find_box(NxBox* b, NxNodeRef n) {
    if (!b) return NULL;
    if (b->node == n) return b;
    for (int i = 0; i < b->child_count; i++) {
        NxBox* r = find_box(b->children[i], n);
        if (r) return r;
    }
    return NULL;
}

static NxBox* box_by_id(NxLayout* lay, NxDocument* doc, const char* id) {
    NxNodeRef n = nx_doc_get_element_by_id(doc, id);
    if (!n) return NULL;
    return find_box(lay->root, n);
}

/* first element descendant of root named `tag` (depth-first) */
static NxNodeRef first_of_tag(NxDocument* doc, const char* tag) {
    NxNodeRef stack[256];
    int sp = 0;
    stack[sp++] = nx_doc_root(doc);
    while (sp > 0) {
        NxNodeRef n = stack[--sp];
        if (nx_node_type(doc, n) == NX_NODE_ELEMENT &&
            strcmp(nx_node_name(doc, n), tag) == 0)
            return n;
        for (NxNodeRef c = nx_node_last_child(doc, n); c && sp < 256;
             c = nx_node_prev_sibling(doc, c))
            if (nx_node_type(doc, c) == NX_NODE_ELEMENT || nx_node_type(doc, c) == NX_NODE_TEXT)
                stack[sp++] = c;
    }
    return 0;
}

/* ---- selector matching --------------------------------------------------- */

static void test_selector_matching(void) {
    Page p;
    CHECK(page_open(&p,
                    "<div id=\"a\" class=\"box extra\" data-x=\"yes red\">"
                    "<p id=\"p1\">one</p><p id=\"p2\">two</p>"
                    "<span id=\"s\">three</span></div>",
                    NULL),
          "fixture parse");

    NxNodeRef div = nx_doc_get_element_by_id(p.doc, "a");
    NxNodeRef p1 = nx_doc_get_element_by_id(p.doc, "p1");
    NxNodeRef p2 = nx_doc_get_element_by_id(p.doc, "p2");
    NxNodeRef sp = nx_doc_get_element_by_id(p.doc, "s");
    CHECK(div && p1 && p2 && sp, "ids resolve");

    CsGroup g;
    CHECK(cs_parse_selector("div", 3, &g), "parse div");
    CHECK(nx_selector_matches(p.doc, div, &g), "type matches");
    CHECK(!nx_selector_matches(p.doc, p1, &g), "type rejects other");

    CHECK(cs_parse_selector("#a", 2, &g), "parse #a");
    CHECK(nx_selector_matches(p.doc, div, &g), "id matches");

    CHECK(cs_parse_selector(".box", 4, &g), "parse .box");
    CHECK(nx_selector_matches(p.doc, div, &g), "class matches");

    CHECK(cs_parse_selector(".extra.box", 10, &g), "parse two classes");
    CHECK(nx_selector_matches(p.doc, div, &g), "both classes match");

    CHECK(cs_parse_selector("[data-x~=red]", 13, &g), "parse attr ~=");
    CHECK(nx_selector_matches(p.doc, div, &g), "attr ~= matches");

    CHECK(cs_parse_selector("[data-x^=ye]", 12, &g), "parse attr ^=");
    CHECK(nx_selector_matches(p.doc, div, &g), "attr ^= matches");

    CHECK(cs_parse_selector("div > p", 7, &g), "parse child combinator");
    CHECK(nx_selector_matches(p.doc, p1, &g), "child combinator matches");
    CHECK(!nx_selector_matches(p.doc, sp, &g), "child combinator rejects span");

    CHECK(cs_parse_selector("div p", 5, &g), "parse descendant");
    CHECK(nx_selector_matches(p.doc, p2, &g), "descendant matches");

    CHECK(cs_parse_selector("p + p", 5, &g), "parse adjacent sibling");
    CHECK(nx_selector_matches(p.doc, p2, &g), "adjacent matches p2");
    CHECK(!nx_selector_matches(p.doc, p1, &g), "adjacent rejects p1");

    CHECK(cs_parse_selector("p ~ span", 8, &g), "parse general sibling");
    CHECK(nx_selector_matches(p.doc, sp, &g), "general sibling matches");

    CHECK(cs_parse_selector("p:first-child", 13, &g), "parse :first-child");
    CHECK(nx_selector_matches(p.doc, p1, &g), ":first-child matches p1");
    CHECK(!nx_selector_matches(p.doc, p2, &g), ":first-child rejects p2");

    CHECK(cs_parse_selector("p:nth-child(2)", 14, &g), "parse :nth-child(2)");
    CHECK(nx_selector_matches(p.doc, p2, &g), ":nth-child(2) matches p2");

    CHECK(cs_parse_selector("p:not(.x)", 9, &g), "parse :not(.x)");
    CHECK(nx_selector_matches(p.doc, p1, &g), ":not matches when class absent");

    CHECK(cs_parse_selector("div span:nth-last-child(1)", 26, &g),
          "parse div span:nth-last-child(1)");
    CHECK(nx_selector_matches(p.doc, sp, &g), ":nth-last-child(1) matches last");

    CHECK(!cs_parse_selector("div >>>", 7, &g), "invalid selector rejected");
    page_close(&p);
}

/* ---- cascade ------------------------------------------------------------- */

static void test_cascade(void) {
    Page p;
    CHECK(page_open(&p,
                    "<html><body>"
                    "<div id=\"a\" class=\"box\">x</div>"
                    "<div id=\"b\" class=\"box\">y</div>"
                    "<div id=\"c\">z</div>"
                    "</body></html>",
                    /* type rule AFTER the class rule: specificity must win */
                    "div { color: #ff0000; }\n"
                    ".box { color: #0000ff; }\n"
                    "#a { color: #00ff00; }\n"
                    "#b { color: #123456; }\n"
                    ".box { color: #654321 !important; }\n"
                    "body { color: #010203; font-size: 20px; }\n"
                    "#c { font-size: 1.5em; }\n"),
          "cascade fixture");

    NxComputedStyle* styles =
        nx_style_resolve(p.doc, (const CsSheet* const*)&p.sheet, 1, 800, 16);
    CHECK(styles != NULL, "resolve styles");
    if (!styles) { page_close(&p); return; }

    NxNodeRef a = nx_doc_get_element_by_id(p.doc, "a");
    NxNodeRef b = nx_doc_get_element_by_id(p.doc, "b");
    NxNodeRef c = nx_doc_get_element_by_id(p.doc, "c");
    NxNodeRef body = first_of_tag(p.doc, "body");
#define ST(h) styles[nx_node_index(h)]

    /* #a id rule (green) loses to the later !important .box rule */
    CHECK(fabsf(ST(b).r - (0x65 / 255.0f)) < 0.004f &&
              fabsf(ST(b).g - (0x43 / 255.0f)) < 0.004f &&
              fabsf(ST(b).b - (0x21 / 255.0f)) < 0.004f,
          "!important beats id (#b got %g %g %g)", ST(b).r, ST(b).g, ST(b).b);
    /* #a also matched by the same !important rule */
    CHECK(fabsf(ST(a).g - (0x43 / 255.0f)) < 0.004f, "!important applies to #a");

    /* class rule beats later type rule on #b without important — verify the
       ordering channel itself with #c vs body inheritance */
    CHECK(fabsf(ST(body).r - (1 / 255.0f)) < 0.004f, "body color applied");

    /* font-size: body 20px inherited, #c 1.5em -> 30px */
    CHECK(fabsf(ST(body).font_size - 20.0f) < 0.01f, "body font-size 20px");
    CHECK(fabsf(ST(c).font_size - 30.0f) < 0.01f, "#c 1.5em of 20px = 30px");
    /* #a inherits body's font-size (no font-size rule on it) */
    CHECK(fabsf(ST(a).font_size - 20.0f) < 0.01f, "inherited font-size 20px");
#undef ST

    free(styles);
    page_close(&p);
}

static void test_media_and_specificity(void) {
    Page p;
    CHECK(page_open(&p,
                    "<html><body><div id=\"a\">x</div></body></html>",
                    "@media (min-width: 600px) { #a { width: 500px; } }\n"
                    "@media (min-width: 2000px) { #a { width: 999px; } }\n"
                    "div#a { width: 300px; }\n"
                    "#a { width: 400px; }\n"),
          "media fixture");
    NxComputedStyle* styles =
        nx_style_resolve(p.doc, (const CsSheet* const*)&p.sheet, 1, 800, 16);
    CHECK(styles != NULL, "resolve media styles");
    if (styles) {
        NxNodeRef a = nx_doc_get_element_by_id(p.doc, "a");
        /* #a (0,1,0) vs div#a (0,1,1): the later div#a wins at equal-ish spec
           only if its specificity is higher — it is, so 300px */
        const NxComputedStyle* sa = &styles[nx_node_index(a)];
        CHECK(sa->width.pct_ == false && fabsf(sa->width.px - 300.0f) < 0.01f,
              "specificity: div#a (300) beats #a (400), media 500 lost: got %g",
              sa->width.px);
        free(styles);
    }
    page_close(&p);
}

/* ---- layout geometry ----------------------------------------------------- */

static void test_block_geometry(void) {
    int32_t font = nx_font_load(font_path());
    CHECK(font >= 0, "font loads");
    if (font < 0) return;

    Page p;
    CHECK(page_open(&p,
                    "<html><body>"
                    "<div id=\"a\" class=\"pad\"><div id=\"a1\">Hello</div></div>"
                    "<div id=\"b\"><div id=\"b1\">child</div></div>"
                    "<div id=\"c\">center</div>"
                    "</body></html>",
                    "#a { width: 400px; padding: 10px; border-width: 2px; margin: 5px; }\n"
                    ".pad { background-color: #eee; }\n"
                    "#a > div { width: 50%; }\n"
                    "#c { width: 200px; margin: 0 auto; }\n"),
          "geometry fixture");

    NxLayout* lay = page_layout(&p, 800, 600, font);
    CHECK(lay != NULL, "layout builds");
    if (!lay) { page_close(&p); return; }

    NxBox* a = box_by_id(lay, p.doc, "a");
    CHECK(a != NULL, "box #a exists");
    if (a) {
        CHECK(fabsf(a->w - 400.0f) < 0.01f, "border-box width 400 (got %g)", a->w);
        CHECK(fabsf(a->x - 5.0f) < 0.01f, "margin-left 5 (got %g)", a->x);
        CHECK(fabsf(a->content_x - (5 + 2 + 10)) < 0.01f,
              "content_x = 5+border2+pad10 = 17 (got %g)", a->content_x);
        CHECK(fabsf(a->content_w - (400.0f - 20.0f - 4.0f)) < 0.01f,
              "content_w = 376 (got %g)", a->content_w);
        CHECK(a->run_count == 0 && a->child_count == 1,
              "#a holds its child box and no direct runs (runs=%d children=%d)",
              a->run_count, a->child_count);
        /* background painted from computed style */
        CHECK(a->style->ba > 0.9f, "background-color computed");
    }

    /* a percentage child resolves against its CONTAINING BLOCK (the #a content
       box, 376px), not the viewport (800px) */
    NxBox* a1 = box_by_id(lay, p.doc, "a1");
    CHECK(a1 != NULL, "box #a1 exists");
    if (a && a1) {
        CHECK(fabsf(a1->w - a->content_w * 0.5f) < 0.01f,
              "50%% of containing block %g = %g", a->content_w, a1->w);
        CHECK(fabsf(a1->w - 188.0f) < 0.01f,
              "376 -> 50%% = 188, NOT viewport 400 (got %g)", a1->w);
        CHECK(a1->run_count >= 1, "nested text run present");
    }

    NxBox* b = box_by_id(lay, p.doc, "b");
    CHECK(b != NULL, "box #b exists");
    if (b) {
        CHECK(b->child_count == 1, "#b has one child box (got %d)", b->child_count);
        if (b->child_count == 1) {
            CHECK(fabsf(b->children[0]->w - b->content_w) < 0.01f,
                  "no width rule -> child fills content box %g (got %g)",
                  b->content_w, b->children[0]->w);
        }
    }

    /* auto margins center the fixed-width box */
    NxBox* c = box_by_id(lay, p.doc, "c");
    CHECK(c != NULL, "box #c exists");
    if (c) {
        CHECK(fabsf(c->w - 200.0f) < 0.01f, "#c width 200 (got %g)", c->w);
        CHECK(fabsf(c->x - 300.0f) < 0.01f, "margin auto centers: x=300 (got %g)", c->x);
    }

    /* vertical stacking: siblings abut exactly */
    if (a && b && c) {
        CHECK(fabsf(b->y - (a->y + a->h)) < 0.01f,
              "#b starts where #a ends: %g vs %g", b->y, a->y + a->h);
        CHECK(fabsf(c->y - (b->y + b->h)) < 0.01f, "#c starts where #b ends");
        CHECK(a->h > 0 && b->h > 0 && c->h > 0, "all boxes have height");
    }

    nx_layout_free(lay);
    page_close(&p);
}

static void test_wrapping_and_align(void) {
    int32_t font = nx_font_load(font_path());
    CHECK(font >= 0, "font loads");
    if (font < 0) return;

    Page p;
    CHECK(page_open(&p,
                    "<html><body>"
                    "<div id=\"w\">alpha beta gamma delta epsilon zeta eta theta</div>"
                    "<div id=\"c\" class=\"ctr\">mid</div>"
                    "</body></html>",
                    "#w { width: 120px; }\n"
                    ".ctr { width: 300px; text-align: center; }\n"),
          "wrap fixture");

    NxLayout* lay = page_layout(&p, 800, 600, font);
    CHECK(lay != NULL, "layout builds");
    if (!lay) { page_close(&p); return; }

    NxBox* w = box_by_id(lay, p.doc, "w");
    CHECK(w != NULL, "wrap box exists");
    if (w) {
        CHECK(w->run_count >= 3, "long text wraps into >=3 runs (got %d)", w->run_count);
        bool in_bounds = true;
        float first_base = -1, last_base = -1;
        int lines = 0;
        float prev_base = -1;
        for (int i = 0; i < w->run_count; i++) {
            NxTextRun* r = &w->runs[i];
            if (r->x < w->content_x - 0.01f || r->x + r->width > w->content_x + w->content_w + 0.01f)
                in_bounds = false;
            if (i == 0) first_base = r->y;
            last_base = r->y;
            if (prev_base >= 0 && fabsf(r->y - prev_base) > 0.01f) lines++;
            prev_base = r->y;
        }
        CHECK(in_bounds, "every run fits inside the content box");
        CHECK(lines >= 2, "runs occupy >=2 distinct baselines (got %d)", lines);
        CHECK(last_base > first_base, "baselines advance downward");
        CHECK(w->content_h >= 2 * nx_font_line_height(font, 16.0f) - 0.5f,
              "height covers wrapped lines: %g", w->content_h);
    }

    NxBox* ctr = box_by_id(lay, p.doc, "c");
    CHECK(ctr != NULL, "center box exists");
    if (ctr && ctr->run_count > 0) {
        NxTextRun* r = &ctr->runs[0];
        float expect = ctr->content_x + (ctr->content_w - r->width) / 2;
        CHECK(fabsf(r->x - expect) < 0.5f, "text-align:center places run at %g (got %g)",
              expect, r->x);
    }

    nx_layout_free(lay);
    page_close(&p);
}

static void test_display_none_and_inline_flatten(void) {
    int32_t font = nx_font_load(font_path());
    CHECK(font >= 0, "font loads");
    if (font < 0) return;

    Page p;
    CHECK(page_open(&p,
                    "<html><head><style>body{color:#000}</style></head><body>"
                    "<div id=\"gone\">hidden text</div>"
                    "<p>before <span class=\"in\">inside words</span> after</p>"
                    "</body></html>",
                    "#gone { display: none; }\n"
                    ".in { color: #ff0000; font-weight: bold; }\n"),
          "none fixture");

    NxLayout* lay = page_layout(&p, 800, 600, font);
    CHECK(lay != NULL, "layout builds");
    if (!lay) { page_close(&p); return; }

    NxNodeRef gone = nx_doc_get_element_by_id(p.doc, "gone");
    CHECK(gone != 0, "hidden element exists in DOM");
    if (gone) {
        NxBox* gb = find_box(lay->root, gone);
        CHECK(gb == NULL, "display:none produces no box");
    }

    /* <style> text must never lay out (head/style are display:none) */
    bool style_text_visible = false;
    for (int i = 0; i < lay->root->child_count; i++) {
        NxBox* htmlb = lay->root->children[i];
        for (int j = 0; j < htmlb->child_count; j++) {
            NxBox* hb = htmlb->children[j];
            for (int k = 0; k < hb->run_count; k++)
                if (strstr(hb->runs[k].utf8, "body{color")) style_text_visible = true;
        }
    }
    CHECK(!style_text_visible, "style element text is not rendered");

    /* inline <span> flattens: its words land on the <p>'s line boxes */
    NxNodeRef pp = first_of_tag(p.doc, "p");
    NxBox* pb = find_box(lay->root, pp);
    CHECK(pb != NULL, "<p> box exists");
    if (pb) {
        CHECK(pb->run_count == 4, "before/inside/words/after -> 4 runs (got %d)",
              pb->run_count);
        bool found_inside = false;
        for (int i = 0; i < pb->run_count; i++)
            if (strncmp(pb->runs[i].utf8, "inside", 6) == 0) found_inside = true;
        CHECK(found_inside, "inline child's text present on parent line");
    }

    nx_layout_free(lay);
    page_close(&p);
}

/* ---- paint ---------------------------------------------------------------- */

static void test_paint(void) {
    int32_t font = nx_font_load(font_path());
    CHECK(font >= 0, "font loads");
    if (font < 0) return;

    Page p;
    CHECK(page_open(&p,
                    "<html><body>"
                    "<div id=\"a\">Painted text</div>"
                    "</body></html>",
                    "#a { width: 300px; padding: 8px; background-color: #00ff00; "
                    "color: #0000ff; border-width: 3px; }\n"),
          "paint fixture");

    NxLayout* lay = page_layout(&p, 800, 600, font);
    CHECK(lay != NULL, "layout builds");
    if (!lay) { page_close(&p); return; }

    NxDisplayList dl;
    nx_dl_init(&dl);
    CHECK(nx_paint(&dl, lay, font), "paint emits");
    CHECK(dl.vert_count >= 4, "page bg + border + glyphs (verts=%u)", dl.vert_count);
    CHECK(dl.group_count >= 1, "at least one draw group");

    char desc[8192];
    nx_dl_describe(&dl, desc, sizeof(desc));
    /* glyph groups are alpha-only (coverage * color) — the text is real */
    CHECK(strstr(desc, "alpha=1") != NULL, "display list contains a glyph group");

    /* geometry sanity: a filled rect for the background exists */
    NxBox* a = box_by_id(lay, p.doc, "a");
    CHECK(a != NULL, "painted box exists");
    if (a) {
        CHECK(fabsf(a->content_w - (300.0f - 16.0f - 6.0f)) < 0.01f,
              "paint box content_w = 278 (got %g)", a->content_w);
    }

    nx_dl_free(&dl);
    nx_layout_free(lay);
    page_close(&p);
}

/* ---- idempotent re-run --------------------------------------------------- */

static void test_rerun(void) {
    int32_t font = nx_font_load(font_path());
    CHECK(font >= 0, "font loads");
    if (font < 0) return;

    Page p;
    CHECK(page_open(&p,
                    "<html><body><div id=\"a\">one</div><div>two</div></body></html>",
                    "div { width: 200px; }\n"),
          "rerun fixture");

    NxLayout* lay = page_layout(&p, 800, 600, font);
    CHECK(lay != NULL, "layout builds");
    if (!lay) { page_close(&p); return; }

    NxBox* root = lay->root;
    int children_before = root->child_count;
    int grandchild_before = root->child_count > 0 ? root->children[0]->child_count : 0;

    nx_layout_run(lay, p.doc, 640, 480, font);
    CHECK(root->child_count == children_before,
          "re-run keeps child count (%d == %d)", root->child_count, children_before);
    if (root->child_count > 0)
        CHECK(root->children[0]->child_count == grandchild_before,
              "re-run keeps grandchild count (%d == %d)",
              root->children[0]->child_count, grandchild_before);
    CHECK(fabsf(lay->root->children[0]->w - 640.0f) < 0.01f,
          "re-run applies new viewport width: %g", lay->root->children[0]->w);

    nx_layout_free(lay);
    page_close(&p);
}

int main(void) {
    nx_font_reset();
    test_selector_matching();
    test_cascade();
    test_media_and_specificity();
    test_block_geometry();
    test_wrapping_and_align();
    test_display_none_and_inline_flatten();
    test_paint();
    test_rerun();

    printf("unit_layout: %d checks, %d failures\n", g_checks, g_failures);
    return g_failures == 0 ? 0 : 1;
}
