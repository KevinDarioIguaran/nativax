#include "nativax/style.h"

#include <ctype.h>
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
            if (str_ieq(t->s, t->len, named[i].n, nl)) {
                *r = named[i].r; *g = named[i].g; *b = named[i].b;
                *a = str_ieq(t->s, t->len, "transparent", 11) ? 0.0f : 1.0f;
                return true;
            }
        }
    }
    /* rgb()/rgba() functional color (comma-separated numeric args) */
    if (t->kind == CS_FUNCTION &&
        (str_ieq(t->s, t->len, "rgb", 3) || str_ieq(t->s, t->len, "rgba", 4))) {
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
            else if (cs_is_ident(&v[0], "flex") || cs_is_ident(&v[0], "grid") ||
                     cs_is_ident(&v[0], "inline-block") || cs_is_ident(&v[0], "list-item"))
                st->display = NX_DISPLAY_BLOCK; /* v1: block layout (documented) */
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
                         int sheet_count, float viewport_w, float font_size, int depth) {
    if (depth > NX_MAX_DEPTH) return;
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
        mst.height = 0;
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
        parent = st;
    }
    for (NxNodeRef c = nx_node_first_child(doc, node); c;
         c = nx_node_next_sibling(doc, c))
        resolve_node(doc, c, parent, styles, sheets, sheet_count, viewport_w, font_size,
                     depth + 1);
}

NxComputedStyle* nx_style_resolve(NxDocument* doc, const CsSheet* const* sheets, int sheet_count,
                                  float viewport_w, float default_font_size) {
    if (!doc) return NULL;
    NxComputedStyle* styles =
        (NxComputedStyle*)calloc((size_t)NX_MAX_NODES, sizeof(NxComputedStyle));
    if (!styles) return NULL;
    NxNodeRef root = nx_doc_root(doc);
    style_init(&styles[nx_node_index(root)], default_font_size);
    styles[nx_node_index(root)].display = NX_DISPLAY_BLOCK;
    resolve_node(doc, root, &styles[nx_node_index(root)], styles, sheets, sheet_count,
                 viewport_w, default_font_size, 0);
    return styles;
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
