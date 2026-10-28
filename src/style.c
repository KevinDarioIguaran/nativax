#include "nativax/style.h"

#include <ctype.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

/* ---- small helpers ------------------------------------------------------- */

static bool str_ieq(const char* a, int alen, const char* b, int blen) {
    if (alen != blen) return false;
    for (int i = 0; i < alen; i++)
        if (tolower((unsigned char)a[i]) != tolower((unsigned char)b[i])) return false;
    return true;
}

static bool node_is_element(NxDocument* doc, NxNodeRef n) {
    return nx_node_type(doc, n) == NX_NODE_ELEMENT;
}

/* ---- selector matching --------------------------------------------------- */

static bool has_class(NxDocument* doc, NxNodeRef el, const char* cls, int clen) {
    const char* v = nx_node_get_attr(doc, el, "class");
    if (!v) return false;
    const char* p = v;
    while (*p) {
        while (*p == ' ' || *p == '\t' || *p == '\n' || *p == '\r') p++;
        const char* start = p;
        while (*p && *p != ' ' && *p != '\t' && *p != '\n' && *p != '\r') p++;
        int len = (int)(p - start);
        if (len == clen && str_ieq(start, len, cls, clen)) return true;
    }
    return false;
}

/* Attribute value lookup by possibly non-null-terminated name slice. */
static const char* attr_by_name(NxDocument* doc, NxNodeRef el, const char* name, int len) {
    int n = nx_node_attr_count(doc, el);
    for (int i = 0; i < n; i++) {
        const char* an = nx_node_attr_name(doc, el, i);
        if (!an) continue;
        if ((int)strlen(an) == len && str_ieq(an, len, name, len))
            return nx_node_attr_value(doc, el, i);
    }
    return NULL;
}

static bool attr_eq(const char* v, int vlen, const char* val, int vlen2, bool case_i) {
    if (vlen != vlen2) return false;
    if (case_i) return str_ieq(v, vlen, val, vlen2);
    return memcmp(v, val, (size_t)vlen) == 0;
}

static bool attr_matches(NxDocument* doc, NxNodeRef el, const CsAttrSel* a) {
    const char* v = attr_by_name(doc, el, a->name, a->name_len);
    if (!v) return false;
    int vlen = (int)strlen(v);
    bool ci = a->case_i;
    switch (a->op) {
    case CS_ATTR_PRESENT:
        return true;
    case CS_ATTR_EQ:
        return attr_eq(v, vlen, a->val, a->val_len, ci);
    case CS_ATTR_INCLUDES: {
        if (a->val_len == 0) return false;
        const char* p = v;
        while (*p) {
            while (*p == ' ') p++;
            const char* s = p;
            while (*p && *p != ' ') p++;
            if (attr_eq(s, (int)(p - s), a->val, a->val_len, ci)) return true;
        }
        return false;
    }
    case CS_ATTR_DASH:
        if (attr_eq(v, vlen, a->val, a->val_len, ci)) return true;
        return vlen > a->val_len && v[a->val_len] == '-' &&
               attr_eq(v, a->val_len, a->val, a->val_len, ci);
    case CS_ATTR_PREFIX:
        return vlen >= a->val_len && attr_eq(v, a->val_len, a->val, a->val_len, ci);
    case CS_ATTR_SUFFIX:
        return vlen >= a->val_len &&
               attr_eq(v + (vlen - a->val_len), a->val_len, a->val, a->val_len, ci);
    case CS_ATTR_SUBSTR: {
        if (a->val_len == 0) return true;
        for (int i = 0; i + a->val_len <= vlen; i++)
            if (attr_eq(v + i, a->val_len, a->val, a->val_len, ci)) return true;
        return false;
    }
    }
    return false;
}

static int nth_index(NxDocument* doc, NxNodeRef el, bool of_type) {
    NxNodeRef parent = nx_node_parent(doc, el);
    const char* tag = of_type ? nx_node_name(doc, el) : NULL;
    int idx = 0;
    for (NxNodeRef c = nx_node_first_child(doc, parent); c;
         c = nx_node_next_sibling(doc, c)) {
        if (!node_is_element(doc, c)) continue;
        if (of_type && !str_ieq(nx_node_name(doc, c), (int)strlen(nx_node_name(doc, c)),
                                tag, (int)strlen(tag)))
            continue;
        idx++;
        if (c == el) return idx;
    }
    return 0;
}

static int count_siblings(NxDocument* doc, NxNodeRef el, bool of_type) {
    NxNodeRef parent = nx_node_parent(doc, el);
    const char* tag = of_type ? nx_node_name(doc, el) : NULL;
    int n = 0;
    for (NxNodeRef c = nx_node_first_child(doc, parent); c;
         c = nx_node_next_sibling(doc, c)) {
        if (!node_is_element(doc, c)) continue;
        if (of_type && !str_ieq(nx_node_name(doc, c), (int)strlen(nx_node_name(doc, c)),
                                tag, (int)strlen(tag)))
            continue;
        n++;
    }
    return n;
}

static bool nth_matches(int index, int a, int b) {
    if (a == 0) return index == b;
    int diff = index - b;
    return diff % a == 0 && diff / a >= 0;
}

static bool simple_matches(NxDocument* doc, NxNodeRef el, const CsSimple* s) {
    if (s->tag) {
        const char* t = nx_node_name(doc, el);
        if (!str_ieq(t, (int)strlen(t), s->tag, s->tag_len)) return false;
    }
    if (s->id) {
        const char* id = nx_node_get_attr(doc, el, "id");
        if (!id || !str_ieq(id, (int)strlen(id), s->id, s->id_len)) return false;
    }
    for (int i = 0; i < s->cls_count; i++)
        if (!has_class(doc, el, s->cls[i], s->cls_len[i])) return false;
    for (int i = 0; i < s->attr_count; i++)
        if (!attr_matches(doc, el, &s->attrs[i])) return false;
    return true;
}

static bool pseudo_matches(NxDocument* doc, NxNodeRef el, const CsCompound* c) {
    switch (c->pseudo) {
    case CS_P_NONE:
        return true;
    case CS_P_ROOT: {
        NxNodeRef p = nx_node_parent(doc, el);
        return !p || nx_node_type(doc, p) == NX_NODE_DOCUMENT;
    }
    case CS_P_FIRST_CHILD:
        return nth_index(doc, el, false) == 1;
    case CS_P_LAST_CHILD: {
        int total = count_siblings(doc, el, false);
        return total > 0 && nth_index(doc, el, false) == total;
    }
    case CS_P_ONLY_CHILD:
        return count_siblings(doc, el, false) == 1;
    case CS_P_FIRST_OF_TYPE:
        return nth_index(doc, el, true) == 1;
    case CS_P_LAST_OF_TYPE: {
        int total = count_siblings(doc, el, true);
        return total > 0 && nth_index(doc, el, true) == total;
    }
    case CS_P_ONLY_OF_TYPE:
        return count_siblings(doc, el, true) == 1;
    case CS_P_NTH_CHILD:
        return nth_matches(nth_index(doc, el, false), c->nth_a, c->nth_b);
    case CS_P_NTH_LAST_CHILD: {
        int total = count_siblings(doc, el, false);
        return nth_matches(total - nth_index(doc, el, false) + 1, c->nth_a, c->nth_b);
    }
    case CS_P_NTH_OF_TYPE:
        return nth_matches(nth_index(doc, el, true), c->nth_a, c->nth_b);
    case CS_P_NTH_LAST_OF_TYPE: {
        int total = count_siblings(doc, el, true);
        return nth_matches(total - nth_index(doc, el, true) + 1, c->nth_a, c->nth_b);
    }
    case CS_P_EMPTY: {
        for (NxNodeRef ch = nx_node_first_child(doc, el); ch;
             ch = nx_node_next_sibling(doc, ch)) {
            NxNodeType t = nx_node_type(doc, ch);
            if (t == NX_NODE_ELEMENT) return false;
            if (t == NX_NODE_TEXT) {
                int len = 0;
                const char* txt = nx_node_text(doc, ch, &len);
                for (int i = 0; i < len; i++)
                    if (!isspace((unsigned char)txt[i])) return false;
            }
        }
        return true;
    }
    /* Interaction/state pseudo-classes depend on live state that static style
       resolution does not model: they never match here (documented). */
    case CS_P_HOVER:
    case CS_P_FOCUS:
    case CS_P_ACTIVE:
    case CS_P_LINK:
    case CS_P_VISITED:
    case CS_P_FOCUS_VISIBLE:
    case CS_P_FOCUS_WITHIN:
    case CS_P_TARGET:
    case CS_P_CHECKED:
    case CS_P_DISABLED:
    case CS_P_ENABLED:
        return false;
    case CS_P_NOT:
        return !simple_matches(doc, el, &c->not);
    default:
        /* Remaining parser-recorded pseudo-classes are non-matching in style v1. */
        return false;
    }
}

static bool compound_matches(NxDocument* doc, NxNodeRef el, const CsCompound* c) {
    if (!simple_matches(doc, el, &c->s)) return false;
    return pseudo_matches(doc, el, c);
}

static bool complex_matches(NxDocument* doc, NxNodeRef el, const CsComplex* cx) {
    int n = cx->count;
    if (n == 0) return false;
    if (!compound_matches(doc, el, &cx->parts[n - 1])) return false;

    NxNodeRef cur = el;
    for (int i = n - 2; i >= 0; i--) {
        char comb = cx->comb[i];
        if (comb == '>') {
            cur = nx_node_parent(doc, cur);
            if (!cur || !node_is_element(doc, cur)) return false;
            if (!compound_matches(doc, cur, &cx->parts[i])) return false;
        } else if (comb == '+') {
            cur = nx_node_prev_sibling(doc, cur);
            if (!cur || !node_is_element(doc, cur)) return false;
            if (!compound_matches(doc, cur, &cx->parts[i])) return false;
        } else if (comb == '~') {
            bool ok = false;
            for (NxNodeRef s = nx_node_prev_sibling(doc, cur); s;
                 s = nx_node_prev_sibling(doc, s)) {
                if (!node_is_element(doc, s)) continue;
                if (compound_matches(doc, s, &cx->parts[i])) { ok = true; cur = s; break; }
            }
            if (!ok) return false;
        } else { /* descendant */
            bool ok = false;
            for (NxNodeRef p = nx_node_parent(doc, cur); p;
                 p = nx_node_parent(doc, p)) {
                if (!node_is_element(doc, p)) continue;
                if (compound_matches(doc, p, &cx->parts[i])) { ok = true; cur = p; break; }
            }
            if (!ok) return false;
        }
    }
    return true;
}

bool nx_selector_matches(NxDocument* doc, NxNodeRef el, const CsGroup* grp) {
    if (!doc || !el || !grp) return false;
    if (!node_is_element(doc, el)) return false;
    for (int i = 0; i < grp->count; i++)
        if (complex_matches(doc, el, &grp->items[i])) return true;
    return false;
}

/* Best specificity among the matching alternatives of a group (CSS uses the
   specificity of the matching selector in the list). -1 when none match. */
static int group_best_spec(NxDocument* doc, NxNodeRef el, const CsGroup* grp, int out[3]) {
    int best = -1;
    for (int i = 0; i < grp->count; i++) {
        if (!complex_matches(doc, el, &grp->items[i])) continue;
        const CsComplex* cx = &grp->items[i];
        if (best < 0 || cx->spec[0] > out[0] ||
            (cx->spec[0] == out[0] &&
             (cx->spec[1] > out[1] || (cx->spec[1] == out[1] && cx->spec[2] > out[2])))) {
            out[0] = cx->spec[0];
            out[1] = cx->spec[1];
            out[2] = cx->spec[2];
            best = i;
        }
    }
    return best;
}

/* ---- value parsing ------------------------------------------------------- */

/* A computed length. Percentages stay symbolic here and are resolved by the
   layout pass against the real containing block (documented design). */
static NxLength len_px(float px) {
    NxLength L;
    L.px = px; L.pct = 0; L.auto_ = false; L.pct_ = false;
    return L;
}
static NxLength len_pct(float frac) {
    NxLength L;
    L.px = 0; L.pct = frac; L.auto_ = false; L.pct_ = true;
    return L;
}
static NxLength len_auto(void) {
    NxLength L;
    L.px = 0; L.pct = 0; L.auto_ = true; L.pct_ = false;
    return L;
}

NxLength nx_len_resolve(const NxLength* L, float auto_val, float ctx) {
    if (L->auto_) return len_px(auto_val);
    if (L->pct_) return len_px(L->pct * ctx);
    return *L;
}

static NxLength parse_length(const CsTok* t, int ntoks, float font_size) {
    if (ntoks <= 0) return len_auto();
    if (t->kind == CS_NUMBER) {
        if (t->num == 0) return len_px(0);
        return len_auto(); /* unitless non-zero is invalid for a length */
    }
    if (t->kind == CS_PERCENTAGE) return len_pct((float)(t->num / 100.0));
    if (t->kind == CS_DIMENSION) {
        if (str_ieq(t->s, t->len, "px", 2)) return len_px((float)t->num);
        if (str_ieq(t->s, t->len, "em", 2) || str_ieq(t->s, t->len, "rem", 3))
            return len_px((float)t->num * font_size);
        return len_auto(); /* unsupported unit -> auto (documented) */
    }
    return len_auto();
}

static unsigned hex_val(char c) {
    if (c >= '0' && c <= '9') return (unsigned)(c - '0');
    c = (char)tolower((unsigned char)c);
    if (c >= 'a' && c <= 'f') return (unsigned)(c - 'a' + 10);
    return 0;
}

static bool parse_color(const CsTok* t, int ntoks, float* r, float* g, float* b, float* a) {
    if (ntoks <= 0) return false;
    if (t->kind == CS_HASH && (t->len == 3 || t->len == 6)) {
        unsigned rv, gv, bv;
        if (t->len == 3) {
            rv = hex_val(t->s[0]) * 17; gv = hex_val(t->s[1]) * 17; bv = hex_val(t->s[2]) * 17;
        } else {
            rv = hex_val(t->s[0]) * 16 + hex_val(t->s[1]);
            gv = hex_val(t->s[2]) * 16 + hex_val(t->s[3]);
            bv = hex_val(t->s[4]) * 16 + hex_val(t->s[5]);
        }
        *r = rv / 255.0f; *g = gv / 255.0f; *b = bv / 255.0f; *a = 1.0f;
        return true;
    }
    if (t->kind == CS_IDENT) {
        static const struct { const char* n; float r, g, b; } named[] = {
            {"black", 0, 0, 0}, {"white", 1, 1, 1}, {"red", 1, 0, 0},
            {"green", 0, 0.5f, 0}, {"blue", 0, 0, 1}, {"yellow", 1, 1, 0},
            {"gray", 0.5f, 0.5f, 0.5f}, {"grey", 0.5f, 0.5f, 0.5f},
            {"silver", 0.75f, 0.75f, 0.75f}, {"navy", 0, 0, 0.5f},
            {"teal", 0, 0.5f, 0.5f}, {"olive", 0.5f, 0.5f, 0},
            {"purple", 0.5f, 0, 0.5f}, {"maroon", 0.5f, 0, 0},
            {"aqua", 0, 1, 1}, {"fuchsia", 1, 0, 1}, {"orange", 1, 0.65f, 0},
            {"transparent", 0, 0, 0},
        };
        for (size_t i = 0; i < sizeof(named) / sizeof(named[0]); i++) {
            int nl = (int)strlen(named[i].n);
            const char* ts = t->str ? t->str : t->s;
            if (str_ieq(ts, t->len, named[i].n, nl)) {
                *r = named[i].r; *g = named[i].g; *b = named[i].b;
                *a = str_ieq(ts, t->len, "transparent", 11) ? 0.0f : 1.0f;
                return true;
            }
        }
    }
    /* rgb()/rgba() functional color (comma-separated numeric args) */
    if (t->kind == CS_FUNCTION) {
        /* CS_FUNCTION keeps its name in `str`; `s` is NULL for these tokens. */
        const char* fname = t->str ? t->str : t->s;
        int flen = t->str ? (int)strlen(t->str) : t->len;
        if (fname && (str_ieq(fname, flen, "rgb", 3) ||
                      str_ieq(fname, flen, "rgba", 4))) {
            float v[4] = {0, 0, 0, 1};
            int n = 0;
            for (int i = 1; i < ntoks && n < 4; i++) {
                if (t[i].kind == CS_NUMBER || t[i].kind == CS_PERCENTAGE) {
                    double x = t[i].num;
                    if (t[i].kind == CS_PERCENTAGE) x /= 100.0;
                    else if (x > 1.0) x /= 255.0;
                    v[n++] = (float)x;
                }
            }
            if (n >= 3) {
                *r = v[0]; *g = v[1]; *b = v[2]; *a = n == 4 ? v[3] : 1.0f;
                return true;
            }
        }
        if (fname && (str_ieq(fname, flen, "hsl", 3) ||
                      str_ieq(fname, flen, "hsla", 4))) {
            /* collect h, s, l, a; track percentage-ness for s/l/a */
            double hv = 0, sv = 0, lv = 0, av = 1;
            (void)0;
            int n = 0;
            /* We need know which values are percentages; store flags parallel. */
            bool is_pct[4] = {false, false, false, false};
            double vals[4] = {0, 0, 0, 1};
            for (int i = 1; i < ntoks && n < 4; i++) {
                if (t[i].kind == CS_NUMBER || t[i].kind == CS_PERCENTAGE) {
                    vals[n] = t[i].num;
                    is_pct[n] = (t[i].kind == CS_PERCENTAGE);
                    n++;
                }
            }
            if (n >= 3) {
                hv = vals[0];
                sv = vals[1];
                lv = vals[2];
                if (is_pct[1]) sv /= 100.0; else if (sv > 1.0) sv /= 100.0;
                if (is_pct[2]) lv /= 100.0; else if (lv > 1.0) lv /= 100.0;
                if (n == 4) {
                    av = vals[3];
                    if (is_pct[3]) av /= 100.0;
                }
                /* HSL -> RGB */
                double h = fmod(hv, 360.0);
                if (h < 0) h += 360.0;
                double c = (1.0 - fabs(2.0 * lv - 1.0)) * sv;
                double x = c * (1.0 - fabs(fmod(h / 60.0, 2.0) - 1.0));
                double m = lv - c / 2.0;
                double r1, g1, b1;
                if (h < 60) { r1 = c; g1 = x; b1 = 0; }
                else if (h < 120) { r1 = x; g1 = c; b1 = 0; }
                else if (h < 180) { r1 = 0; g1 = c; b1 = x; }
                else if (h < 240) { r1 = 0; g1 = x; b1 = c; }
                else if (h < 300) { r1 = x; g1 = 0; b1 = c; }
                else { r1 = c; g1 = 0; b1 = x; }
                *r = (float)(r1 + m);
                *g = (float)(g1 + m);
                *b = (float)(b1 + m);
                *a = (float)av;
                return true;
            }
        }
    }
    return false;
}

/* ---- declaration application -------------------------------------------- */

static void style_init(NxComputedStyle* s, float font_size) {
    memset(s, 0, sizeof(*s));
    s->display = NX_DISPLAY_INLINE;
    for (int i = 0; i < 4; i++) {
        /* CSS initial margin is 0 (not auto) */
        s->margin[i] = len_px(0);
        s->padding[i] = len_px(0);
        s->border[i] = 0;
    }
    s->width = len_auto();
    s->height = len_auto();
    s->r = s->g = s->b = 0; s->a = 1;
    s->br = s->bg = s->bb = 0; s->ba = 0;
    s->font_size = font_size;
    s->font_weight = 400;
    s->align = NX_ALIGN_LEFT;
    s->line_height = 0;
    s->opacity = 1.0f;
    s->transform = nx_mat_identity();
    s->transform_origin[0] = len_pct(0.5f);
    s->transform_origin[1] = len_pct(0.5f);
    s->flex_direction = NX_FLEX_ROW;
    s->flex_wrap = NX_FLEX_NOWRAP;
    s->justify_content = NX_JUSTIFY_START;
    s->align_items = NX_FLEX_ALIGN_STRETCH;
    s->align_content = NX_FLEX_ALIGN_STRETCH;
    s->gap = 0;
    s->flex_grow = 0;
    s->flex_shrink = 1;
    s->flex_basis = len_auto();
    s->order = 0;
}

/* Collect the space-separated components of a box shorthand. Returns count. */
static int split_components(const CsTok* v, int nt, float font_size, NxLength* out, int max) {
    int n = 0;
    int i = 0;
    while (i < nt && n < max) {
        if (v[i].kind == CS_WS) { i++; continue; }
        if (v[i].kind == CS_IDENT && cs_is_ident(&v[i], "auto")) {
            out[n++] = len_auto();
            i++;
            continue;
        }
        if (v[i].kind == CS_NUMBER || v[i].kind == CS_PERCENTAGE ||
            v[i].kind == CS_DIMENSION) {
            out[n++] = parse_length(&v[i], 1, font_size);
            i++;
            continue;
        }
        break; /* unsupported component: stop (shorthand becomes partial) */
    }
    return n;
}

/* Expand 1-4 components into top/right/bottom/left. */
static void expand_box(const NxLength* c, int n, NxLength out[4]) {
    if (n <= 0) return;
    if (n == 1) { out[0] = out[1] = out[2] = out[3] = c[0]; }
    else if (n == 2) { out[0] = out[2] = c[0]; out[1] = out[3] = c[1]; }
    else if (n == 3) { out[0] = c[0]; out[1] = out[3] = c[1]; out[2] = c[2]; }
    else { for (int i = 0; i < 4; i++) out[i] = c[i]; }
}

/* ---- Phase 3 effect values ---------------------------------------------- */

/* Absolute px value for radius/translate: px, em, rem, or the number 0.
   Percentages are deliberately unsupported (documented). */
static bool effect_px(const CsTok* t, float font_size, float* out) {
    if (t->kind == CS_NUMBER) {
        if (t->num != 0) return false; /* unitless non-zero is not a length */
        *out = 0;
        return true;
    }
    if (t->kind != CS_DIMENSION) return false;
    if (str_ieq(t->s, t->len, "px", 2)) {
        *out = (float)t->num;
        return true;
    }
    if (str_ieq(t->s, t->len, "em", 2) || str_ieq(t->s, t->len, "rem", 3)) {
        *out = (float)t->num * font_size;
        return true;
    }
    return false;
}

/* Angle for rotate(): deg, rad, turn, grad or the number 0. */
static bool effect_angle(const CsTok* t, float* out) {
    if (t->kind == CS_NUMBER) {
        if (t->num != 0) return false;
        *out = 0;
        return true;
    }
    if (t->kind != CS_DIMENSION) return false;
    if (str_ieq(t->s, t->len, "deg", 3)) { *out = (float)(t->num * M_PI / 180.0); return true; }
    if (str_ieq(t->s, t->len, "rad", 3)) { *out = (float)t->num; return true; }
    if (str_ieq(t->s, t->len, "turn", 4)) { *out = (float)(t->num * 2.0 * M_PI); return true; }
    if (str_ieq(t->s, t->len, "grad", 4)) { *out = (float)(t->num * M_PI / 200.0); return true; }
    return false;
}

/* Collect the argument tokens of one transform function up to its closing
   parenthesis. Commas and whitespace are separators; nested functions make the
   declaration invalid for this subset. */
static bool function_args(const CsTok* v, int nt, int start, const CsTok* args[8], int* nargs,
                          int* next) {
    int n = 0;
    int i = start;
    while (i < nt) {
        CsTokKind k = v[i].kind;
        if (k == CS_RPAREN) {
            *nargs = n;
            *next = i + 1;
            return true;
        }
        if (k == CS_FUNCTION || k == CS_LPAREN) return false;
        if (k != CS_WS && k != CS_COMMA) {
            if (n >= 8) return false;
            args[n++] = &v[i];
        }
        i++;
    }
    return false;
}

static bool parse_transform(const CsTok* v, int nt, float font_size, NxMat2x3* out) {
    NxMat2x3 acc = nx_mat_identity();
    int i = 0;
    bool any = false;
    while (i < nt) {
        if (v[i].kind == CS_WS || v[i].kind == CS_COMMA) { i++; continue; }
        if (v[i].kind != CS_FUNCTION) return false;
        const char* name = v[i].str ? v[i].str : "";
        int nl = v[i].len;
        const CsTok* a[8];
        int na = 0, next = 0;
        if (!function_args(v, nt, i + 1, a, &na, &next)) return false;

        NxMat2x3 step = nx_mat_identity();
        if (str_ieq(name, nl, "translate", 9) && (na == 1 || na == 2)) {
            float tx, ty = 0;
            if (!effect_px(a[0], font_size, &tx)) return false;
            if (na == 2 && !effect_px(a[1], font_size, &ty)) return false;
            step = nx_mat_translate(tx, ty);
        } else if (str_ieq(name, nl, "translatex", 10) && na == 1) {
            float tx;
            if (!effect_px(a[0], font_size, &tx)) return false;
            step = nx_mat_translate(tx, 0);
        } else if (str_ieq(name, nl, "translatey", 10) && na == 1) {
            float ty;
            if (!effect_px(a[0], font_size, &ty)) return false;
            step = nx_mat_translate(0, ty);
        } else if (str_ieq(name, nl, "scale", 5) && (na == 1 || na == 2)) {
            float sx, sy;
            if (a[0]->kind != CS_NUMBER) return false;
            sx = sy = (float)a[0]->num;
            if (na == 2) {
                if (a[1]->kind != CS_NUMBER) return false;
                sy = (float)a[1]->num;
            }
            step = nx_mat_scale(sx, sy);
        } else if (str_ieq(name, nl, "scalex", 6) && na == 1) {
            if (a[0]->kind != CS_NUMBER) return false;
            step = nx_mat_scale((float)a[0]->num, 1);
        } else if (str_ieq(name, nl, "scaley", 6) && na == 1) {
            if (a[0]->kind != CS_NUMBER) return false;
            step = nx_mat_scale(1, (float)a[0]->num);
        } else if (str_ieq(name, nl, "rotate", 6) && na == 1) {
            float ang;
            if (!effect_angle(a[0], &ang)) return false;
            float c = cosf(ang), s = sinf(ang);
            /* CSS/SVG convention with y down: [c -s; s c] */
            step = (NxMat2x3){c, s, -s, c, 0, 0};
        } else if (str_ieq(name, nl, "matrix", 6) && na == 6) {
            float m[6];
            for (int k = 0; k < 6; k++) {
                if (a[k]->kind != CS_NUMBER) return false;
                m[k] = (float)a[k]->num;
            }
            /* matrix(a,b,c,d,e,f): x' = a*x + c*y + e (same field order) */
            step = (NxMat2x3){m[0], m[1], m[2], m[3], m[4], m[5]};
        } else {
            return false; /* unsupported function: reject the declaration */
        }
        acc = nx_mat_mul(&acc, &step);
        any = true;
        i = next;
    }
    if (!any) return false;
    *out = acc;
    return true;
}

/* transform-origin component: px/em/rem length or a keyword. */
static bool origin_component(const CsTok* t, float font_size, NxLength* out, bool horizontal) {
    if (t->kind == CS_IDENT) {
        if (cs_is_ident(t, "center")) { *out = len_pct(0.5f); return true; }
        if (cs_is_ident(t, "left") || cs_is_ident(t, "top")) { *out = len_px(0); return true; }
        if (cs_is_ident(t, "right") || cs_is_ident(t, "bottom")) {
            *out = len_pct(1.0f);
            return true;
        }
        return false;
    }
    if (t->kind == CS_PERCENTAGE) {
        *out = len_pct((float)(t->num / 100.0));
        return true;
    }
    float px;
    if (!effect_px(t, font_size, &px)) return false;
    (void)horizontal;
    *out = len_px(px);
    return true;
}

/* 1-4 radii with the CSS expansion rule; elliptical ("/" syntax) is
   unsupported and rejects the declaration. Returns false on invalid input. */
static bool parse_radii(const CsTok* v, int nt, float font_size, float out[4]) {
    float c[4] = {0, 0, 0, 0};
    int n = 0;
    for (int i = 0; i < nt; i++) {
        if (v[i].kind == CS_WS) continue;
        if (v[i].kind == CS_DELIM && v[i].s && v[i].s[0] == '/') return false;
        if (n >= 4) return false;
        if (!effect_px(&v[i], font_size, &c[n])) return false;
        if (c[n] < 0) return false;
        n++;
    }
    if (n == 0) return false;
    if (n == 1) { out[0] = out[1] = out[2] = out[3] = c[0]; }
    else if (n == 2) { out[0] = out[2] = c[0]; out[1] = out[3] = c[1]; }
    else if (n == 3) { out[0] = c[0]; out[1] = out[3] = c[1]; out[2] = c[2]; }
    else { for (int i = 0; i < 4; i++) out[i] = c[i]; }
    return true;
}

static void apply_decl(NxComputedStyle* st, const CsDecl* d, float font_size) {
    const char* n = d->name;
    int nl = d->name_len;
    const CsTok* v = d->toks;
    int nt = d->ntoks;
    if (nt == 0) return;

#define IS(name) str_ieq(n, nl, name, (int)strlen(name))
    if (IS("display")) {
        if (v[0].kind == CS_IDENT) {
            if (cs_is_ident(&v[0], "block")) st->display = NX_DISPLAY_BLOCK;
            else if (cs_is_ident(&v[0], "inline")) st->display = NX_DISPLAY_INLINE;
            else if (cs_is_ident(&v[0], "none")) st->display = NX_DISPLAY_NONE;
            else if (cs_is_ident(&v[0], "flex") || cs_is_ident(&v[0], "inline-flex"))
                st->display = NX_DISPLAY_FLEX;
        }
    } else if (IS("width")) st->width = parse_length(v, nt, font_size);
    else if (IS("height")) st->height = parse_length(v, nt, font_size);
    else if (IS("margin-top")) st->margin[0] = parse_length(v, nt, font_size);
    else if (IS("margin-right")) st->margin[1] = parse_length(v, nt, font_size);
    else if (IS("margin-bottom")) st->margin[2] = parse_length(v, nt, font_size);
    else if (IS("margin-left")) st->margin[3] = parse_length(v, nt, font_size);
    else if (IS("margin")) {
        NxLength c[4]; int n_c = split_components(v, nt, font_size, c, 4);
        expand_box(c, n_c, st->margin);
    } else if (IS("padding-top")) st->padding[0] = parse_length(v, nt, font_size);
    else if (IS("padding-right")) st->padding[1] = parse_length(v, nt, font_size);
    else if (IS("padding-bottom")) st->padding[2] = parse_length(v, nt, font_size);
    else if (IS("padding-left")) st->padding[3] = parse_length(v, nt, font_size);
    else if (IS("padding")) {
        NxLength c[4]; int n_c = split_components(v, nt, font_size, c, 4);
        expand_box(c, n_c, st->padding);
    } else if (IS("border-top-width")) st->border[0] = parse_length(v, nt, font_size).px;
    else if (IS("border-right-width")) st->border[1] = parse_length(v, nt, font_size).px;
    else if (IS("border-bottom-width")) st->border[2] = parse_length(v, nt, font_size).px;
    else if (IS("border-left-width")) st->border[3] = parse_length(v, nt, font_size).px;
    else if (IS("border-width")) {
        NxLength one[4]; int cnt = split_components(v, nt, font_size, one, 4);
        NxLength tmp[4]; expand_box(one, cnt, tmp);
        for (int i = 0; i < 4; i++) st->border[i] = tmp[i].auto_ ? st->border[i] : tmp[i].px;
    } else if (IS("border")) {
        /* width component applies to all sides; style/color accepted and the
           color is ignored (v1 paints borders in the text color). */
        for (int i = 0; i < nt; i++) {
            if (v[i].kind == CS_DIMENSION || v[i].kind == CS_NUMBER) {
                NxLength L = parse_length(&v[i], 1, font_size);
                if (!L.auto_) {
                    for (int k = 0; k < 4; k++) st->border[k] = L.px;
                }
            } else if (v[i].kind == CS_IDENT) {
                if (cs_is_ident(&v[i], "none")) {
                    for (int k = 0; k < 4; k++) st->border[k] = 0;
                } else if (cs_is_ident(&v[i], "thin")) {
                    for (int k = 0; k < 4; k++) st->border[k] = 1;
                } else if (cs_is_ident(&v[i], "medium")) {
                    for (int k = 0; k < 4; k++) st->border[k] = 3;
                } else if (cs_is_ident(&v[i], "thick")) {
                    for (int k = 0; k < 4; k++) st->border[k] = 5;
                }
            } else if (v[i].kind == CS_HASH) {
                float r, g, b, a;
                if (parse_color(&v[i], 1, &r, &g, &b, &a)) {
                    st->bc_set = true;
                    st->bc_r = r; st->bc_g = g; st->bc_b = b; st->bc_a = a;
                }
            }
        }
    } else if (IS("border-style")) {
        if (v[0].kind == CS_IDENT && cs_is_ident(&v[0], "none"))
            for (int k = 0; k < 4; k++) st->border[k] = 0;
    } else if (IS("color")) {
        parse_color(v, nt, &st->r, &st->g, &st->b, &st->a);
    } else if (IS("border-color")) {
        float r, g, b, a;
        if (parse_color(v, nt, &r, &g, &b, &a)) {
            st->bc_set = true;
            st->bc_r = r; st->bc_g = g; st->bc_b = b; st->bc_a = a;
        }
    } else if (IS("background-color") || IS("background")) {
        float r, g, b, a;
        if (parse_color(v, nt, &r, &g, &b, &a)) { st->br = r; st->bg = g; st->bb = b; st->ba = a; }
    } else if (IS("font-size")) {
        NxLength L = parse_length(v, nt, font_size);
        if (!L.auto_ && !L.pct_ && L.px > 0) st->font_size = L.px;
        else if (v[0].kind == CS_PERCENTAGE && v[0].num > 0)
            st->font_size = (float)(v[0].num / 100.0) * font_size;
    } else if (IS("font-weight")) {
        if (v[0].kind == CS_NUMBER) st->font_weight = (int)v[0].num;
        else if (v[0].kind == CS_IDENT) {
            if (cs_is_ident(&v[0], "bold") || cs_is_ident(&v[0], "bolder"))
                st->font_weight = 700;
            else if (cs_is_ident(&v[0], "normal") || cs_is_ident(&v[0], "lighter"))
                st->font_weight = 400;
        }
    } else if (IS("text-align")) {
        if (v[0].kind == CS_IDENT) {
            if (cs_is_ident(&v[0], "center")) st->align = NX_ALIGN_CENTER;
            else if (cs_is_ident(&v[0], "right") || cs_is_ident(&v[0], "end"))
                st->align = NX_ALIGN_RIGHT;
            else st->align = NX_ALIGN_LEFT;
        }
    } else if (IS("line-height")) {
        if (v[0].kind == CS_NUMBER) st->line_height = (float)v[0].num * st->font_size;
        else if (v[0].kind == CS_PERCENTAGE)
            st->line_height = (float)(v[0].num / 100.0) * st->font_size;
        else {
            NxLength L = parse_length(v, nt, font_size);
            if (!L.auto_ && !L.pct_) st->line_height = L.px;
            else if (L.pct_) st->line_height = L.pct * st->font_size;
        }
    } else if (IS("border-radius")) {
        float r[4];
        if (parse_radii(v, nt, font_size, r))
            for (int i = 0; i < 4; i++) st->radius[i] = r[i];
    } else if (IS("border-top-left-radius")) {
        float px;
        if (effect_px(&v[0], font_size, &px)) st->radius[0] = px;
    } else if (IS("border-top-right-radius")) {
        float px;
        if (effect_px(&v[0], font_size, &px)) st->radius[1] = px;
    } else if (IS("border-bottom-right-radius")) {
        float px;
        if (effect_px(&v[0], font_size, &px)) st->radius[2] = px;
    } else if (IS("border-bottom-left-radius")) {
        float px;
        if (effect_px(&v[0], font_size, &px)) st->radius[3] = px;
    } else if (IS("overflow")) {
        for (int i = 0; i < nt; i++) {
            if (v[i].kind != CS_IDENT) continue;
            if (cs_is_ident(&v[i], "hidden") || cs_is_ident(&v[i], "clip")) {
                st->overflow_hidden = true;
                st->overflow_scroll = false;
                break;
            }
            if (cs_is_ident(&v[i], "scroll") || cs_is_ident(&v[i], "auto")) {
                st->overflow_hidden = true;
                st->overflow_scroll = true;
                break;
            }
            if (cs_is_ident(&v[i], "visible")) {
                st->overflow_hidden = false;
                st->overflow_scroll = false;
                break;
            }
        }
    } else if (IS("opacity")) {
        if (v[0].kind == CS_NUMBER) {
            float o = (float)v[0].num;
            st->opacity = o < 0 ? 0 : o > 1 ? 1 : o;
        } else if (v[0].kind == CS_PERCENTAGE) {
            float o = (float)(v[0].num / 100.0);
            st->opacity = o < 0 ? 0 : o > 1 ? 1 : o;
        }
    } else if (IS("transform")) {
        if (v[0].kind == CS_IDENT && cs_is_ident(&v[0], "none")) {
            st->transform_set = false;
            st->transform = nx_mat_identity();
        } else {
            NxMat2x3 m;
            if (parse_transform(v, nt, font_size, &m)) {
                st->transform = m;
                st->transform_set = true;
            }
        }
    } else if (IS("flex-direction")) {
        if (v[0].kind == CS_IDENT) {
            if (cs_is_ident(&v[0], "row")) st->flex_direction = NX_FLEX_ROW;
            else if (cs_is_ident(&v[0], "row-reverse")) st->flex_direction = NX_FLEX_ROW_REVERSE;
            else if (cs_is_ident(&v[0], "column")) st->flex_direction = NX_FLEX_COLUMN;
            else if (cs_is_ident(&v[0], "column-reverse")) st->flex_direction = NX_FLEX_COLUMN_REVERSE;
        }
    } else if (IS("flex-wrap")) {
        if (v[0].kind == CS_IDENT) {
            if (cs_is_ident(&v[0], "nowrap")) st->flex_wrap = NX_FLEX_NOWRAP;
            else if (cs_is_ident(&v[0], "wrap")) st->flex_wrap = NX_FLEX_WRAP;
            else if (cs_is_ident(&v[0], "wrap-reverse")) st->flex_wrap = NX_FLEX_WRAP_REVERSE;
        }
    } else if (IS("justify-content")) {
        if (v[0].kind == CS_IDENT) {
            if (cs_is_ident(&v[0], "flex-start") || cs_is_ident(&v[0], "start"))
                st->justify_content = NX_JUSTIFY_START;
            else if (cs_is_ident(&v[0], "flex-end") || cs_is_ident(&v[0], "end"))
                st->justify_content = NX_JUSTIFY_END;
            else if (cs_is_ident(&v[0], "center")) st->justify_content = NX_JUSTIFY_CENTER;
            else if (cs_is_ident(&v[0], "space-between")) st->justify_content = NX_JUSTIFY_SPACE_BETWEEN;
            else if (cs_is_ident(&v[0], "space-around")) st->justify_content = NX_JUSTIFY_SPACE_AROUND;
            else if (cs_is_ident(&v[0], "space-evenly")) st->justify_content = NX_JUSTIFY_SPACE_EVENLY;
        }
    } else if (IS("align-items")) {
        if (v[0].kind == CS_IDENT) {
            if (cs_is_ident(&v[0], "stretch")) st->align_items = NX_FLEX_ALIGN_STRETCH;
            else if (cs_is_ident(&v[0], "flex-start") || cs_is_ident(&v[0], "start"))
                st->align_items = NX_FLEX_ALIGN_START;
            else if (cs_is_ident(&v[0], "flex-end") || cs_is_ident(&v[0], "end"))
                st->align_items = NX_FLEX_ALIGN_END;
            else if (cs_is_ident(&v[0], "center")) st->align_items = NX_FLEX_ALIGN_CENTER;
            else if (cs_is_ident(&v[0], "baseline")) st->align_items = NX_FLEX_ALIGN_BASELINE;
        }
    } else if (IS("align-content")) {
        if (v[0].kind == CS_IDENT) {
            if (cs_is_ident(&v[0], "stretch")) st->align_content = NX_FLEX_ALIGN_STRETCH;
            else if (cs_is_ident(&v[0], "flex-start") || cs_is_ident(&v[0], "start"))
                st->align_content = NX_FLEX_ALIGN_START;
            else if (cs_is_ident(&v[0], "flex-end") || cs_is_ident(&v[0], "end"))
                st->align_content = NX_FLEX_ALIGN_END;
            else if (cs_is_ident(&v[0], "center")) st->align_content = NX_FLEX_ALIGN_CENTER;
        }
    } else if (IS("gap") || IS("row-gap") || IS("column-gap")) {
        NxLength L = parse_length(v, nt, font_size);
        if (!L.auto_ && !L.pct_) st->gap = L.px;
        else if (v[0].kind == CS_NUMBER) st->gap = (float)v[0].num;
    } else if (IS("flex")) {
        /* flex: grow shrink basis | grow | grow shrink | none */
        if (v[0].kind == CS_IDENT && cs_is_ident(&v[0], "none")) {
            st->flex_grow = 0; st->flex_shrink = 0; st->flex_basis = len_px(0); /* auto? none => 0 */
        } else {
            int n = 0;
            for (int i = 0; i < nt; i++) {
                if (v[i].kind == CS_WS) continue;
                if (v[i].kind == CS_NUMBER && n == 0) { st->flex_grow = (float)v[i].num; n++; }
                else if (v[i].kind == CS_NUMBER && n == 1) { st->flex_shrink = (float)v[i].num; n++; }
                else {
                    NxLength L = parse_length(&v[i], 1, font_size);
                    if (!L.auto_) { st->flex_basis = L; n++; }
                    else if (v[i].kind == CS_IDENT && cs_is_ident(&v[i], "auto")) { st->flex_basis = len_auto(); n++; }
                }
            }
            if (n == 1 && st->flex_basis.auto_ && st->flex_grow > 0 && st->flex_shrink == 1) {
                /* flex: <grow> => basis 0% */
                st->flex_basis = len_px(0);
            }
        }
    } else if (IS("flex-grow")) {
        if (v[0].kind == CS_NUMBER) st->flex_grow = (float)v[0].num;
    } else if (IS("flex-shrink")) {
        if (v[0].kind == CS_NUMBER) st->flex_shrink = (float)v[0].num;
    } else if (IS("flex-basis")) {
        if (v[0].kind == CS_IDENT && cs_is_ident(&v[0], "auto")) st->flex_basis = len_auto();
        else st->flex_basis = parse_length(v, nt, font_size);
    } else if (IS("order")) {
        if (v[0].kind == CS_NUMBER) st->order = (int)v[0].num;
    } else if (IS("transform-origin")) {
        const CsTok* a[4];
        int na = 0;
        for (int i = 0; i < nt && na < 4; i++)
            if (v[i].kind != CS_WS) a[na++] = &v[i];
        NxLength x, y;
        bool ok = false;
        if (na == 1) {
            if (a[0]->kind == CS_IDENT &&
                (cs_is_ident(a[0], "top") || cs_is_ident(a[0], "bottom"))) {
                ok = origin_component(a[0], font_size, &y, false) &&
                     origin_component(&(CsTok){CS_IDENT, "center", 6, 0, NULL, 0},
                                      font_size, &x, true);
            } else {
                ok = origin_component(a[0], font_size, &x, true) &&
                     origin_component(&(CsTok){CS_IDENT, "center", 6, 0, NULL, 0},
                                      font_size, &y, false);
            }
        } else if (na == 2) {
            ok = origin_component(a[0], font_size, &x, true) &&
                 origin_component(a[1], font_size, &y, false);
        }
        if (ok) {
            st->transform_origin[0] = x;
            st->transform_origin[1] = y;
        }
    }
#undef IS
}

static void inherit(NxComputedStyle* child, const NxComputedStyle* parent) {
    child->r = parent->r; child->g = parent->g; child->b = parent->b; child->a = parent->a;
    child->font_size = parent->font_size;
    child->font_weight = parent->font_weight;
    child->align = parent->align;
    child->line_height = parent->line_height;
}

/* Default display when no author rule applies: the HTML UA stylesheet's
   display:none set plus block/inline defaults. */
static NxDisplayKind default_display(const char* tag) {
    static const char* none_tags[] = {"head", "style", "script", "meta", "link",
                                      "title", "base", "template", "param", NULL};
    for (int i = 0; none_tags[i]; i++)
        if (str_ieq(tag, (int)strlen(tag), none_tags[i], (int)strlen(none_tags[i])))
            return NX_DISPLAY_NONE;
    static const char* block_tags[] = {
        "html", "body", "div", "p", "h1", "h2", "h3", "h4", "h5", "h6",
        "ul", "ol", "li", "section", "article", "header", "footer", "nav",
        "main", "aside", "figure", "figcaption", "blockquote", "pre", "hr",
        "table", "thead", "tbody", "tfoot", "tr", "td", "th", "form",
        "fieldset", "address", "dl", "dt", "dd", NULL};
    for (int i = 0; block_tags[i]; i++)
        if (str_ieq(tag, (int)strlen(tag), block_tags[i], (int)strlen(block_tags[i])))
            return NX_DISPLAY_BLOCK;
    return NX_DISPLAY_INLINE;
}

/* ---- cascade ------------------------------------------------------------- */

#define NX_MAX_CAND 1024

typedef struct Cand {
    const CsRule* rule;
    int spec[3];
    long order; /* global source order across sheets */
} Cand;

static bool cand_before(const Cand* x, const Cand* y) {
    if (x->spec[0] != y->spec[0]) return x->spec[0] < y->spec[0];
    if (x->spec[1] != y->spec[1]) return x->spec[1] < y->spec[1];
    if (x->spec[2] != y->spec[2]) return x->spec[2] < y->spec[2];
    return x->order < y->order;
}

static void cand_sort(Cand* c, int n) {
    /* insertion sort: stable, tiny n */
    for (int i = 1; i < n; i++) {
        Cand key = c[i];
        int j = i - 1;
        while (j >= 0 && cand_before(&key, &c[j])) {
            c[j + 1] = c[j];
            j--;
        }
        c[j + 1] = key;
    }
}

/* Recursive resolver: carries the parent style down the tree. */
static void resolve_node(NxDocument* doc, NxNodeRef node, const NxComputedStyle* parent,
                         NxComputedStyle* styles, const CsSheet* const* sheets,
                         int sheet_count, float viewport_w, float viewport_h, float font_size, int depth,
                         int cap) {
    if (depth > NX_MAX_DEPTH) return;
    if (nx_node_index(node) >= cap) return;
    NxNodeType t = nx_node_type(doc, node);
    if (t == NX_NODE_ELEMENT) {
        NxComputedStyle* st = &styles[nx_node_index(node)];
        style_init(st, font_size);
        if (parent) inherit(st, parent);
        st->display = default_display(nx_node_name(doc, node));

        /* collect matching rules (media-filtered), then cascade by
           (specificity, source order); !important is applied in a second pass */
        Cand cands[NX_MAX_CAND];
        int nc = 0;
        CsMediaState mst;
        mst.width = viewport_w;
        mst.height = viewport_h;
        mst.print = false;
        for (int si = 0; si < sheet_count && nc < NX_MAX_CAND; si++) {
            const CsSheet* sh = sheets[si];
            if (!sh) continue;
            for (int ri = 0; ri < sh->rule_count && nc < NX_MAX_CAND; ri++) {
                const CsRule* rule = &sh->rules[ri];
                if (rule->is_pseudo_element) continue;
                if (rule->media && !cs_media_matches(rule->media, &mst)) continue;
                int spec[3] = {0, 0, 0};
                if (group_best_spec(doc, node, &rule->sel, spec) < 0) continue;
                cands[nc].rule = rule;
                cands[nc].spec[0] = spec[0];
                cands[nc].spec[1] = spec[1];
                cands[nc].spec[2] = spec[2];
                cands[nc].order = (long)si * 1000000L + rule->order;
                nc++;
            }
        }
        cand_sort(cands, nc);
        for (int i = 0; i < nc; i++)
            for (int di = 0; di < cands[i].rule->decl_count; di++) {
                const CsDecl* d = &cands[i].rule->decls[di];
                if (!d->important) apply_decl(st, d, st->font_size);
            }
        for (int i = 0; i < nc; i++)
            for (int di = 0; di < cands[i].rule->decl_count; di++) {
                const CsDecl* d = &cands[i].rule->decls[di];
                if (d->important) apply_decl(st, d, st->font_size);
            }

        /* inline style attribute: author origin, most specific (applied last,
           so script-driven style writes win over stylesheet rules) */
        const char* inline_style = nx_node_get_attr(doc, node, "style");
        if (inline_style && *inline_style)
            nx_style_apply_declarations(st, inline_style, (int)strlen(inline_style));
        parent = st;
    }
    for (NxNodeRef c = nx_node_first_child(doc, node); c;
         c = nx_node_next_sibling(doc, c))
        resolve_node(doc, c, parent, styles, sheets, sheet_count, viewport_w, viewport_h, font_size,
                     depth + 1, cap);
}

NxComputedStyle* nx_style_resolve(NxDocument* doc, const CsSheet* const* sheets, int sheet_count,
                                  float viewport_w, float viewport_h, float default_font_size) {
    if (!doc) return NULL;
    NxComputedStyle* styles =
        (NxComputedStyle*)calloc((size_t)NX_MAX_NODES, sizeof(NxComputedStyle));
    if (!styles) return NULL;
    NxNodeRef root = nx_doc_root(doc);
    style_init(&styles[nx_node_index(root)], default_font_size);
    styles[nx_node_index(root)].display = NX_DISPLAY_BLOCK;
    resolve_node(doc, root, &styles[nx_node_index(root)], styles, sheets, sheet_count,
                 viewport_w, viewport_h, default_font_size, 0, NX_MAX_NODES);
    return styles;
}

bool nx_style_resolve_into(NxDocument* doc, const CsSheet* const* sheets, int sheet_count,
                           float viewport_w, float viewport_h, float default_font_size, NxComputedStyle* out,
                           int cap) {
    if (!doc || !out || cap <= 0) return false;
    memset(out, 0, sizeof(NxComputedStyle) * (size_t)cap);
    NxNodeRef root = nx_doc_root(doc);
    if (nx_node_index(root) >= cap) return false;
    style_init(&out[nx_node_index(root)], default_font_size);
    out[nx_node_index(root)].display = NX_DISPLAY_BLOCK;
    resolve_node(doc, root, &out[nx_node_index(root)], out, sheets, sheet_count, viewport_w,
                 viewport_h, default_font_size, 0, cap);
    return true;
}

bool nx_style_apply_declarations(NxComputedStyle* st, const char* text, int len) {
    if (!st || !text || len <= 0) return false;
    CsDeclList* list = cs_decls_parse(text, len);
    if (!list) return false;
    for (int i = 0; i < list->count; i++) {
        const CsDecl* d = &list->decls[i];
        if (!d->important) apply_decl(st, d, st->font_size);
    }
    for (int i = 0; i < list->count; i++) {
        const CsDecl* d = &list->decls[i];
        if (d->important) apply_decl(st, d, st->font_size);
    }
    cs_decls_free(list);
    return true;
}

/* ---- inline <style> sheets --------------------------------------------- */

/* Concatenated text under an element (caller frees; NULL when empty). */
static char* element_text(NxDocument* doc, NxNodeRef el, int* out_len) {
    int total = 0;
    for (NxNodeRef c = nx_node_first_child(doc, el); c;
         c = nx_node_next_sibling(doc, c)) {
        if (nx_node_type(doc, c) != NX_NODE_TEXT) continue;
        int len = 0;
        nx_node_text(doc, c, &len);
        total += len;
    }
    *out_len = 0;
    if (total == 0) return NULL;
    char* buf = (char*)malloc((size_t)total);
    if (!buf) return NULL;
    int off = 0;
    for (NxNodeRef c = nx_node_first_child(doc, el); c;
         c = nx_node_next_sibling(doc, c)) {
        if (nx_node_type(doc, c) != NX_NODE_TEXT) continue;
        int len = 0;
        const char* t = nx_node_text(doc, c, &len);
        if (t && len > 0) {
            memcpy(buf + off, t, (size_t)len);
            off += len;
        }
    }
    *out_len = off;
    return buf;
}

static void collect_style_nodes(NxDocument* doc, NxNodeRef node, CsSheet** out, int cap,
                                int* n, int depth) {
    if (depth > NX_MAX_DEPTH || *n >= cap) return;
    if (nx_node_type(doc, node) == NX_NODE_ELEMENT &&
        str_ieq(nx_node_name(doc, node), (int)strlen(nx_node_name(doc, node)), "style", 5)) {
        int len = 0;
        char* text = element_text(doc, node, &len);
        if (text && len > 0) {
            out[*n] = cs_sheet_parse(text, len);
            if (out[*n]) (*n)++;
        }
        free(text);
        return;
    }
    for (NxNodeRef c = nx_node_first_child(doc, node); c;
         c = nx_node_next_sibling(doc, c))
        collect_style_nodes(doc, c, out, cap, n, depth + 1);
}

int nx_style_collect_inline(NxDocument* doc, CsSheet** out, int cap) {
    if (!doc || !out || cap <= 0) return 0;
    int n = 0;
    collect_style_nodes(doc, nx_doc_root(doc), out, cap, &n, 0);
    return n;
}
