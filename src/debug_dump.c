#include "nativax/debug_dump.h"

#include <ctype.h>
#include <string.h>

/* ------------------------------------------------------------------ */
/* DOM                                                                 */
/* ------------------------------------------------------------------ */

static void put_escaped(FILE* out, const char* s, int len) {
    fputc('"', out);
    int shown = 0;
    for (int i = 0; i < len && shown < 96; i++) {
        unsigned char c = (unsigned char)s[i];
        if (c == '\n') fputs("\\n", out);
        else if (c == '\t') fputs("\\t", out);
        else if (c == '\r') fputs("\\r", out);
        else if (c < 0x20 || c == 0x7f) fprintf(out, "\\x%02x", c);
        else fputc((char)c, out);
        shown++;
    }
    if (len > 96) fputs("...", out);
    fputc('"', out);
}

void nxd_dump_dom(FILE* out, NxDocument* doc, NxNodeRef node, int depth) {
    if (!node) return;
    for (int i = 0; i < depth; i++) fputs("  ", out);
    NxNodeType type = nx_node_type(doc, node);
    if (type == NX_NODE_TEXT) {
        int len = 0;
        const char* t = nx_node_text(doc, node, &len);
        fputs("text ", out);
        put_escaped(out, t ? t : "", len);
        fputc('\n', out);
        return;
    }
    if (type == NX_NODE_COMMENT) {
        int len = 0;
        const char* t = nx_node_text(doc, node, &len);
        fputs("<!-- ", out);
        if (t && len > 0) fwrite(t, 1, (size_t)(len > 60 ? 60 : len), out);
        fputs(" -->\n", out);
        return;
    }
    const char* name = nx_node_name(doc, node);
    fprintf(out, "<%s", name ? name : "?");
    int ac = nx_node_attr_count(doc, node);
    for (int i = 0; i < ac; i++) {
        fprintf(out, " %s=", nx_node_attr_name(doc, node, i));
        const char* v = nx_node_attr_value(doc, node, i);
        put_escaped(out, v ? v : "", (int)strlen(v ? v : ""));
    }
    fputs(">\n", out);
    for (NxNodeRef c = nx_node_first_child(doc, node); c;
         c = nx_node_next_sibling(doc, c)) {
        nxd_dump_dom(out, doc, c, depth + 1);
    }
}

void nxd_dom_stats(NxDocument* doc, NxNodeRef node, int depth, NxdDomStats* st) {
    if (!node) return;
    NxNodeType type = nx_node_type(doc, node);
    if (type == NX_NODE_ELEMENT) {
        st->elements++;
        if (depth > st->max_depth) st->max_depth = depth;
    } else if (type == NX_NODE_TEXT) {
        st->text++;
        return;
    } else if (type == NX_NODE_COMMENT) {
        st->comments++;
        return;
    }
    for (NxNodeRef c = nx_node_first_child(doc, node); c;
         c = nx_node_next_sibling(doc, c)) {
        nxd_dom_stats(doc, c, depth + 1, st);
    }
}

/* ------------------------------------------------------------------ */
/* selectors                                                           */
/* ------------------------------------------------------------------ */

static const char* pseudo_name(CsPseudo p) {
    switch (p) {
        case CS_P_ROOT: return "root";
        case CS_P_HOVER: return "hover";
        case CS_P_FOCUS: return "focus";
        case CS_P_ACTIVE: return "active";
        case CS_P_LINK: return "link";
        case CS_P_VISITED: return "visited";
        case CS_P_FIRST_CHILD: return "first-child";
        case CS_P_LAST_CHILD: return "last-child";
        case CS_P_ONLY_CHILD: return "only-child";
        case CS_P_FIRST_OF_TYPE: return "first-of-type";
        case CS_P_LAST_OF_TYPE: return "last-of-type";
        case CS_P_NTH_CHILD: return "nth-child";
        case CS_P_NTH_LAST_CHILD: return "nth-last-child";
        case CS_P_NTH_OF_TYPE: return "nth-of-type";
        case CS_P_EMPTY: return "empty";
        case CS_P_CHECKED: return "checked";
        case CS_P_DISABLED: return "disabled";
        case CS_P_ENABLED: return "enabled";
        case CS_P_NOT: return "not";
        case CS_P_FOCUS_VISIBLE: return "focus-visible";
        case CS_P_FOCUS_WITHIN: return "focus-within";
        case CS_P_TARGET: return "target";
        case CS_P_DEFINED: return "defined";
        case CS_P_SCOPE: return "scope";
        case CS_P_ANY_LINK: return "any-link";
        case CS_P_OPEN: return "open";
        case CS_P_MODAL: return "modal";
        case CS_P_REQUIRED: return "required";
        case CS_P_OPTIONAL: return "optional";
        case CS_P_READ_ONLY: return "read-only";
        case CS_P_READ_WRITE: return "read-write";
        case CS_P_PLACEHOLDER_SHOWN: return "placeholder-shown";
        case CS_P_VALID: return "valid";
        case CS_P_INVALID: return "invalid";
        case CS_P_USER_VALID: return "user-valid";
        case CS_P_USER_INVALID: return "user-invalid";
        case CS_P_IN_RANGE: return "in-range";
        case CS_P_OUT_OF_RANGE: return "out-of-range";
        case CS_P_INDETERMINATE: return "indeterminate";
        case CS_P_DEFAULT: return "default";
        case CS_P_AUTOFILL: return "autofill";
        case CS_P_ONLY_OF_TYPE: return "only-of-type";
        case CS_P_NTH_LAST_OF_TYPE: return "nth-last-of-type";
        case CS_P_FIRST: return "first";
        case CS_P_POPOVER_OPEN: return "popover-open";
        case CS_P_HEADING: return "heading";
        case CS_P_DIR: return "dir";
        case CS_P_LANG: return "lang";
        default: return NULL;
    }
}

static const char* attr_op_str(CsAttrOp op) {
    switch (op) {
        case CS_ATTR_EQ: return "=";
        case CS_ATTR_INCLUDES: return "~=";
        case CS_ATTR_DASH: return "|=";
        case CS_ATTR_PREFIX: return "^=";
        case CS_ATTR_SUFFIX: return "$=";
        case CS_ATTR_SUBSTR: return "*=";
        default: return "";
    }
}

typedef struct Fmt {
    char* buf;
    int cap;
    int n; /* written so far (excluding NUL) */
} Fmt;

static void fmt_str(Fmt* f, const char* s, int len) {
    if (f->n >= f->cap - 1) return;
    if (len < 0) len = (int)strlen(s);
    if (len > f->cap - 1 - f->n) len = f->cap - 1 - f->n;
    memcpy(f->buf + f->n, s, (size_t)len);
    f->n += len;
    f->buf[f->n] = '\0';
}

static void fmt_lit(Fmt* f, const char* s) { fmt_str(f, s, -1); }

static void fmt_nth(Fmt* f, int a, int b) {
    char tmp[32];
    if (a == 0) {
        /* plain integer: print b only, never the "+b" suffix */
        snprintf(tmp, sizeof(tmp), "%d", b);
        fmt_lit(f, tmp);
        return;
    } else if (a == 1) {
        snprintf(tmp, sizeof(tmp), "n");
    } else if (a == -1) {
        snprintf(tmp, sizeof(tmp), "-n");
    } else {
        snprintf(tmp, sizeof(tmp), "%dn", a);
    }
    fmt_lit(f, tmp);
    if (b > 0) snprintf(tmp, sizeof(tmp), "+%d", b);
    else if (b < 0) snprintf(tmp, sizeof(tmp), "%d", b);
    else tmp[0] = '\0';
    if (b != 0 || a == 0) fmt_lit(f, tmp);
}

static void fmt_simple(Fmt* f, const CsSimple* s, bool allow_star) {
    bool pure_universal =
        !(s->id && s->id_len > 0) && s->cls_count == 0 && s->attr_count == 0;
    if (s->tag && s->tag_len > 0) fmt_str(f, s->tag, s->tag_len);
    else if (pure_universal && allow_star)
        fmt_lit(f, "*"); /* bare .x/[a] keep no star; :root prints no star */
    if (s->id && s->id_len > 0) {
        fmt_lit(f, "#");
        fmt_str(f, s->id, s->id_len);
    }
    for (int i = 0; i < s->cls_count; i++) {
        fmt_lit(f, ".");
        fmt_str(f, s->cls[i], s->cls_len[i]);
    }
    for (int i = 0; i < s->attr_count; i++) {
        const CsAttrSel* a = &s->attrs[i];
        fmt_lit(f, "[");
        fmt_str(f, a->name, a->name_len);
        if (a->op != CS_ATTR_PRESENT) {
            fmt_lit(f, attr_op_str(a->op));
            if (a->val) fmt_str(f, a->val, a->val_len);
        }
        if (a->case_i) fmt_lit(f, " i");
        fmt_lit(f, "]");
    }
}

void nxd_format_selector(const CsGroup* grp, char* buf, int cap) {
    Fmt f = {buf, cap, 0};
    buf[0] = '\0';
    for (int i = 0; i < grp->count; i++) {
        if (i > 0) fmt_lit(&f, ", ");
        const CsComplex* cx = &grp->items[i];
        for (int j = 0; j < cx->count; j++) {
            if (j > 0) {
                char c = cx->comb[j - 1];
                if (c == ' ') fmt_lit(&f, " ");
                else {
                    fmt_lit(&f, " ");
                    fmt_lit(&f, (char[]){c, 0});
                    fmt_lit(&f, " ");
                }
            }
            const CsCompound* c = &cx->parts[j];
            bool has_pseudo = c->pseudo != CS_P_NONE || c->is_pseudo_elem;
            fmt_simple(&f, &c->s, !has_pseudo);
            if (c->has_not) {
                fmt_lit(&f, ":not(");
                fmt_simple(&f, &c->not, true);
                fmt_lit(&f, ")");
            }
            if (c->pseudo != CS_P_NONE && c->pseudo != CS_P_NOT) {
                const char* nm = pseudo_name(c->pseudo);
                if (nm) {
                    fmt_lit(&f, ":");
                    fmt_lit(&f, nm);
                    if (c->pseudo == CS_P_NTH_CHILD ||
                        c->pseudo == CS_P_NTH_LAST_CHILD ||
                        c->pseudo == CS_P_NTH_OF_TYPE ||
                        c->pseudo == CS_P_NTH_LAST_OF_TYPE) {
                        fmt_lit(&f, "(");
                        fmt_nth(&f, c->nth_a, c->nth_b);
                        fmt_lit(&f, ")");
                    } else if (c->arg) {
                        fmt_lit(&f, "(");
                        fmt_str(&f, c->arg, c->arg_len);
                        fmt_lit(&f, ")");
                    }
                }
            }
            if (c->is_pseudo_elem && c->pseudo_elem) {
                fmt_lit(&f, "::");
                fmt_str(&f, c->pseudo_elem, c->pseudo_elem_len);
            }
        }
        if (cx->spec[0] || cx->spec[1] || cx->spec[2]) {
            char sp[32];
            snprintf(sp, sizeof(sp), " (%d,%d,%d)", cx->spec[0], cx->spec[1],
                     cx->spec[2]);
            fmt_lit(&f, sp);
        }
    }
}

/* ------------------------------------------------------------------ */
/* CSS sheets                                                          */
/* ------------------------------------------------------------------ */

static void fmt_tok(Fmt* f, const CsTok* t) {
    char tmp[64];
    switch (t->kind) {
        case CS_IDENT:
        case CS_FUNCTION:
            fmt_str(f, t->str ? t->str : "", -1);
            if (t->kind == CS_FUNCTION) fmt_lit(f, "(");
            break;
        case CS_STRING:
            snprintf(tmp, sizeof(tmp), "\"%s\"", t->str ? t->str : "");
            fmt_lit(f, tmp);
            break;
        case CS_URL:
            snprintf(tmp, sizeof(tmp), "url(%s)", t->str ? t->str : "");
            fmt_lit(f, tmp);
            break;
        case CS_NUMBER:
        case CS_PERCENTAGE:
        case CS_DIMENSION:
            snprintf(tmp, sizeof(tmp), "%g", t->num);
            fmt_lit(f, tmp);
            if (t->kind == CS_PERCENTAGE) fmt_lit(f, "%");
            else if (t->kind == CS_DIMENSION) fmt_str(f, t->s, t->len);
            break;
        case CS_HASH:
            fmt_lit(f, "#");
            fmt_str(f, t->s, t->len);
            break;
        case CS_DELIM:
            fmt_str(f, t->s, t->len);
            break;
        case CS_COLON: fmt_lit(f, ":"); break;
        case CS_LBRACKET: fmt_lit(f, "["); break;
        case CS_RBRACKET: fmt_lit(f, "]"); break;
        case CS_LPAREN: fmt_lit(f, "("); break;
        case CS_RPAREN: fmt_lit(f, ")"); break;
        case CS_COMMA: fmt_lit(f, ","); break;
        default: break;
    }
}

void nxd_dump_css(FILE* out, CsSheet* sheet) {
    fprintf(out, "# rules=%d dropped_rules=%d dropped_decls=%d\n",
            sheet->rule_count, sheet->dropped_rules, sheet->dropped_decls);
    if (sheet->font_family) {
        fprintf(out, "# font-face family=\"%s\" url=\"%s\"\n", sheet->font_family,
                sheet->font_url ? sheet->font_url : "");
    }
    for (int i = 0; i < sheet->rule_count; i++) {
        const CsRule* r = &sheet->rules[i];
        char sel[512];
        nxd_format_selector(&r->sel, sel, sizeof(sel));
        if (r->media) fprintf(out, "[%d] @media %s {\n", i, r->media);
        else fprintf(out, "[%d] %s {\n", i, sel);
        if (r->media) fprintf(out, "      selector: %s\n", sel);
        if (r->is_pseudo_element) fputs("      (pseudo-element rule)\n", out);
        for (int d = 0; d < r->decl_count; d++) {
            const CsDecl* dc = &r->decls[d];
            Fmt f = {NULL, 0, 0};
            char val[256];
            f.buf = val;
            f.cap = (int)sizeof(val);
            val[0] = '\0';
            for (int t = 0; t < dc->ntoks; t++) {
                if (dc->toks[t].kind == CS_WS) continue;
                if (f.n > 0) fmt_lit(&f, " ");
                fmt_tok(&f, &dc->toks[t]);
            }
            fprintf(out, "      %s: %s%s\n", dc->name, val,
                    dc->important ? " !important" : "");
        }
        fputs("    }\n", out);
    }
}

/* ------------------------------------------------------------------ */
/* JSON DOM tree                                                       */
/* ------------------------------------------------------------------ */

static void json_str(FILE* out, const char* s, int len) {
    if (len < 0) len = (int)strlen(s);
    fputc('"', out);
    for (int i = 0; i < len; i++) {
        unsigned char c = (unsigned char)s[i];
        switch (c) {
            case '"': fputs("\\\"", out); break;
            case '\\': fputs("\\\\", out); break;
            case '\n': fputs("\\n", out); break;
            case '\r': fputs("\\r", out); break;
            case '\t': fputs("\\t", out); break;
            default:
                if (c < 0x20 || c == 0x7f) fprintf(out, "\\u%04x", c);
                else fputc((char)c, out);
        }
    }
    fputc('"', out);
}

static void dump_json_node(FILE* out, NxDocument* doc, NxNodeRef node) {
    NxNodeType type = nx_node_type(doc, node);
    if (type == NX_NODE_TEXT) {
        int len = 0;
        const char* t = nx_node_text(doc, node, &len);
        fputs("{\"text\":", out);
        json_str(out, t ? t : "", len);
        fputc('}', out);
        return;
    }
    if (type == NX_NODE_COMMENT) {
        int len = 0;
        const char* t = nx_node_text(doc, node, &len);
        fputs("{\"comment\":", out);
        json_str(out, t ? t : "", len);
        fputc('}', out);
        return;
    }
    const char* name = nx_node_name(doc, node);
    fputs("{\"tag\":", out);
    json_str(out, name ? name : "", -1);
    const char* id = nx_node_get_attr(doc, node, "id");
    if (id) {
        fputs(",\"id\":", out);
        json_str(out, id, -1);
    }
    const char* cls = nx_node_get_attr(doc, node, "class");
    if (cls) {
        fputs(",\"class\":[", out);
        bool first = true;
        const char* p = cls;
        while (*p) {
            while (*p == ' ' || *p == '\t' || *p == '\n' || *p == '\r') p++;
            if (!*p) break;
            const char* s = p;
            while (*p && *p != ' ' && *p != '\t' && *p != '\n' && *p != '\r') p++;
            if (!first) fputc(',', out);
            json_str(out, s, (int)(p - s));
            first = false;
        }
        fputc(']', out);
    }
    int ac = nx_node_attr_count(doc, node);
    bool any = false;
    for (int i = 0; i < ac; i++) {
        const char* an = nx_node_attr_name(doc, node, i);
        if (strcmp(an, "id") == 0 || strcmp(an, "class") == 0) continue;
        if (!any) {
            fputs(",\"attrs\":{", out);
            any = true;
        } else {
            fputc(',', out);
        }
        json_str(out, an, -1);
        fputc(':', out);
        const char* v = nx_node_attr_value(doc, node, i);
        json_str(out, v ? v : "", -1);
    }
    if (any) fputc('}', out);
    fprintf(out, ",\"node\":%d", (int)nx_node_index(node));
    fputs(",\"children\":[", out);
    bool first = true;
    for (NxNodeRef c = nx_node_first_child(doc, node); c;
         c = nx_node_next_sibling(doc, c)) {
        if (!first) fputc(',', out);
        dump_json_node(out, doc, c);
        first = false;
    }
    fputc(']', out);
    fputc('}', out);
}

void nxd_dump_dom_json(FILE* out, NxDocument* doc, NxNodeRef node) {
    fputs("{\"children\":[", out);
    if (node) {
        NxNodeType type = nx_node_type(doc, node);
        if (type == NX_NODE_DOCUMENT) {
            bool first = true;
            for (NxNodeRef c = nx_node_first_child(doc, node); c;
                 c = nx_node_next_sibling(doc, c)) {
                if (!first) fputc(',', out);
                dump_json_node(out, doc, c);
                first = false;
            }
        } else {
            dump_json_node(out, doc, node);
        }
    }
    fputs("]}\n", out);
}

/* ------------------------------------------------------------------ */
/* layout tree                                                         */
/* ------------------------------------------------------------------ */

static void box_label(NxDocument* doc, NxNodeRef node, char* buf, int cap) {
    if (!node) {
        snprintf(buf, (size_t)cap, "viewport");
        return;
    }
    const char* tag = nx_node_name(doc, node);
    int n = snprintf(buf, (size_t)cap, "%s", tag ? tag : "?");
    if (n < 0 || n >= cap) return;
    const char* id = nx_node_get_attr(doc, node, "id");
    if (id) n += snprintf(buf + n, (size_t)(cap - n), "#%s", id);
    if (n < 0 || n >= cap) return;
    const char* cls = nx_node_get_attr(doc, node, "class");
    if (cls && *cls) {
        /* first class only: keeps dump lines short */
        const char* sp = strchr(cls, ' ');
        int cl = sp ? (int)(sp - cls) : (int)strlen(cls);
        snprintf(buf + n, (size_t)(cap - n), ".*%.*s", cl, cls);
    }
}

static void dump_box(FILE* out, NxDocument* doc, const NxBox* b, int depth) {
    if (!b) return;
    char label[256];
    box_label(doc, b->node, label, sizeof(label));
    for (int i = 0; i < depth; i++) fputs("  ", out);
    fprintf(out, "%s pos=[%.1f %.1f] size=[%.1f %.1f] content=[%.1f %.1f %.1f %.1f] runs=%d\n",
            label, b->x, b->y, b->w, b->h, b->content_x, b->content_y, b->content_w,
            b->content_h, b->run_count);
    for (int i = 0; i < b->run_count; i++) {
        const NxTextRun* r = &b->runs[i];
        for (int d = 0; d < depth + 1; d++) fputs("  ", out);
        fputs("run ", out);
        put_escaped(out, r->utf8 ? r->utf8 : "", r->len);
        fprintf(out, " @ [%.1f %.1f] w=%.1f\n", r->x, r->y, r->width);
    }
    for (int i = 0; i < b->child_count; i++) dump_box(out, doc, b->children[i], depth + 1);
}

void nxd_dump_layout(FILE* out, NxDocument* doc, const NxLayout* lay) {
    if (!lay) {
        fputs("# layout unavailable\n", out);
        return;
    }
    fprintf(out, "# viewport %.0fx%.0f\n", lay->viewport_w, lay->viewport_h);
    char label[256];
    box_label(doc, 0, label, sizeof(label));
    fprintf(out, "%s size=[%.1f %.1f] children=%d\n", label, lay->viewport_w,
            lay->viewport_h, lay->root ? lay->root->child_count : 0);
    if (!lay->root) return;
    for (int i = 0; i < lay->root->child_count; i++)
        dump_box(out, doc, lay->root->children[i], 1);
}

static void count_box(const NxBox* b, int* boxes, int* runs) {
    if (!b) return;
    (*boxes)++;
    *runs += b->run_count;
    for (int i = 0; i < b->child_count; i++) count_box(b->children[i], boxes, runs);
}

void nxd_layout_stats(const NxLayout* lay, int* boxes, int* runs) {
    *boxes = 0;
    *runs = 0;
    if (!lay || !lay->root) return;
    for (int i = 0; i < lay->root->child_count; i++)
        count_box(lay->root->children[i], boxes, runs);
}

/* ---- display list ------------------------------------------------------- */
void nxd_dump_display_list(FILE* out, const NxDisplayList* dl) {
    if (!out || !dl) return;
    char buf[65536];
    nx_dl_describe(dl, buf, (int)sizeof(buf));
    fputs(buf, out);
    fprintf(out, "\nlayers=%u\n", dl->layer_count);
    for (uint32_t i = 0; i < dl->layer_count; i++) {
        fprintf(out, "  layer %u: groups %u..%u opacity=%.3f parent=%d\n", i,
                dl->layers[i].first_group,
                dl->layers[i].first_group + dl->layers[i].group_count,
                dl->layers[i].opacity, dl->layers[i].parent);
    }
    fprintf(out, "transform_depth=%d clip_depth=%d\n", dl->transform_depth,
            dl->clip_depth);
}

/* ------------------------------------------------------------------ */
/* JSON dumps for the laboratory                                       */
/* ------------------------------------------------------------------ */

static void json_len(FILE* out, const NxLength* L) {
    fprintf(out, "{\"px\":%.4f,\"pct\":%.4f,\"auto\":%s,\"is_pct\":%s}",
            L->px, L->pct, L->auto_ ? "true" : "false",
            L->pct_ ? "true" : "false");
}

static const char* display_name(NxDisplayKind k) {
    switch (k) {
        case NX_DISPLAY_BLOCK: return "block";
        case NX_DISPLAY_INLINE: return "inline";
        case NX_DISPLAY_FLEX: return "flex";
        case NX_DISPLAY_NONE: return "none";
    }
    return "unknown";
}

static const char* align_name(NxAlignKind k) {
    switch (k) {
        case NX_ALIGN_LEFT: return "left";
        case NX_ALIGN_CENTER: return "center";
        case NX_ALIGN_RIGHT: return "right";
    }
    return "unknown";
}

static const char* flex_dir_name(NxFlexDirection k) {
    switch (k) {
        case NX_FLEX_ROW: return "row";
        case NX_FLEX_ROW_REVERSE: return "row-reverse";
        case NX_FLEX_COLUMN: return "column";
        case NX_FLEX_COLUMN_REVERSE: return "column-reverse";
    }
    return "unknown";
}

static const char* flex_wrap_name(NxFlexWrap k) {
    switch (k) {
        case NX_FLEX_NOWRAP: return "nowrap";
        case NX_FLEX_WRAP: return "wrap";
        case NX_FLEX_WRAP_REVERSE: return "wrap-reverse";
    }
    return "unknown";
}

static const char* justify_name(NxJustify k) {
    switch (k) {
        case NX_JUSTIFY_START: return "flex-start";
        case NX_JUSTIFY_END: return "flex-end";
        case NX_JUSTIFY_CENTER: return "center";
        case NX_JUSTIFY_SPACE_BETWEEN: return "space-between";
        case NX_JUSTIFY_SPACE_AROUND: return "space-around";
        case NX_JUSTIFY_SPACE_EVENLY: return "space-evenly";
    }
    return "unknown";
}

static const char* flex_align_name(NxFlexAlign k) {
    switch (k) {
        case NX_FLEX_ALIGN_STRETCH: return "stretch";
        case NX_FLEX_ALIGN_START: return "flex-start";
        case NX_FLEX_ALIGN_END: return "flex-end";
        case NX_FLEX_ALIGN_CENTER: return "center";
        case NX_FLEX_ALIGN_BASELINE: return "baseline";
    }
    return "unknown";
}

static void json_node_ident(FILE* out, NxDocument* doc, NxNodeRef node) {
    fprintf(out, "\"node\":%d,\"tag\":", (int)nx_node_index(node));
    json_str(out, nx_node_name(doc, node), -1);
    const char* id = nx_node_get_attr(doc, node, "id");
    if (id) {
        fputs(",\"id\":", out);
        json_str(out, id, -1);
    }
    const char* cls = nx_node_get_attr(doc, node, "class");
    if (cls) {
        fputs(",\"class\":[", out);
        const char* p = cls;
        bool first = true;
        while (*p) {
            while (*p == ' ' || *p == '\t' || *p == '\n' || *p == '\r') p++;
            if (!*p) break;
            const char* s = p;
            while (*p && *p != ' ' && *p != '\t' && *p != '\n' && *p != '\r') p++;
            if (!first) fputc(',', out);
            json_str(out, s, (int)(p - s));
            first = false;
        }
        fputc(']', out);
    }
}

static void json_layout_box(FILE* out, NxDocument* doc, const NxBox* b) {
    if (!b) return;
    fputc('{', out);
    if (b->node) json_node_ident(out, doc, b->node);
    else fputs("\"node\":-1,\"tag\":\"viewport\"", out);
    fprintf(out, ",\"x\":%.4f,\"y\":%.4f,\"w\":%.4f,\"h\":%.4f",
            b->x, b->y, b->w, b->h);
    fprintf(out, ",\"cx\":%.4f,\"cy\":%.4f,\"cw\":%.4f,\"ch\":%.4f",
            b->content_x, b->content_y, b->content_w, b->content_h);
    fputs(",\"runs\":[", out);
    for (int i = 0; i < b->run_count; i++) {
        const NxTextRun* r = &b->runs[i];
        if (i) fputc(',', out);
        fputs("{\"text\":", out);
        json_str(out, r->utf8 ? r->utf8 : "", r->len);
        fprintf(out, ",\"x\":%.4f,\"y\":%.4f,\"w\":%.4f}", r->x, r->y, r->width);
    }
    fputs("],\"children\":[", out);
    for (int i = 0; i < b->child_count; i++) {
        if (i) fputc(',', out);
        json_layout_box(out, doc, b->children[i]);
    }
    fputs("]}", out);
}

void nxd_dump_layout_json(FILE* out, NxDocument* doc, const NxLayout* lay) {
    if (!lay) {
        fputs("{\"viewport\":[0,0],\"boxes\":[],\"error\":\"no layout\"}\n", out);
        return;
    }
    fprintf(out, "{\"viewport\":[%.4f,%.4f],\"boxes\":[",
            lay->viewport_w, lay->viewport_h);
    if (lay->root) {
        for (int i = 0; i < lay->root->child_count; i++) {
            if (i) fputc(',', out);
            json_layout_box(out, doc, lay->root->children[i]);
        }
    }
    fputs("]}\n", out);
}

static void json_style_decl(FILE* out, NxDocument* doc, NxNodeRef node,
                            const NxComputedStyle* s) {
    fputc('{', out);
    json_node_ident(out, doc, node);
    fprintf(out, ",\"display\":\"%s\"", display_name(s->display));
    fputs(",\"width\":", out);
    json_len(out, &s->width);
    fputs(",\"height\":", out);
    json_len(out, &s->height);
    fputs(",\"margin\":[", out);
    for (int i = 0; i < 4; i++) {
        if (i) fputc(',', out);
        json_len(out, &s->margin[i]);
    }
    fputs("],\"padding\":[", out);
    for (int i = 0; i < 4; i++) {
        if (i) fputc(',', out);
        json_len(out, &s->padding[i]);
    }
    fprintf(out, "],\"border\":[%.4f,%.4f,%.4f,%.4f]", s->border[0],
            s->border[1], s->border[2], s->border[3]);
    fprintf(out, ",\"color\":[%.4f,%.4f,%.4f,%.4f]", s->r, s->g, s->b, s->a);
    fprintf(out, ",\"bg\":[%.4f,%.4f,%.4f,%.4f]", s->br, s->bg, s->bb, s->ba);
    fprintf(out, ",\"font_size\":%.4f,\"font_weight\":%d,\"text_align\":\"%s\"",
            s->font_size, s->font_weight, align_name(s->align));
    fprintf(out, ",\"line_height\":%.4f,\"opacity\":%.4f", s->line_height,
            s->opacity);
    fprintf(out, ",\"radius\":[%.4f,%.4f,%.4f,%.4f]", s->radius[0],
            s->radius[1], s->radius[2], s->radius[3]);
    fprintf(out, ",\"overflow_hidden\":%s", s->overflow_hidden ? "true" : "false");
    fprintf(out, ",\"transform\":{\"set\":%s,\"a\":%.4f,\"b\":%.4f,\"c\":%.4f,"
                 "\"d\":%.4f,\"e\":%.4f,\"f\":%.4f}",
            s->transform_set ? "true" : "false", s->transform.a, s->transform.b,
            s->transform.c, s->transform.d, s->transform.e, s->transform.f);
    fprintf(out, ",\"flex\":{\"direction\":\"%s\",\"wrap\":\"%s\","
                 "\"justify\":\"%s\",\"align_items\":\"%s\",\"gap\":%.4f,"
                 "\"grow\":%.4f,\"shrink\":%.4f,\"basis\":",
            flex_dir_name(s->flex_direction), flex_wrap_name(s->flex_wrap),
            justify_name(s->justify_content), flex_align_name(s->align_items),
            s->gap, s->flex_grow, s->flex_shrink);
    json_len(out, &s->flex_basis);
    fprintf(out, ",\"order\":%d}}", s->order);
}

static void json_styles_node(FILE* out, NxDocument* doc, NxNodeRef node,
                             const NxLayout* lay, bool* first) {
    if (!node) return;
    NxNodeType type = nx_node_type(doc, node);
    if (type == NX_NODE_ELEMENT) {
        int idx = (int)nx_node_index(node);
        if (idx >= 0 && idx < lay->styles_cap) {
            if (!*first) fputc(',', out);
            json_style_decl(out, doc, node, &lay->styles[idx]);
            *first = false;
        }
    }
    for (NxNodeRef c = nx_node_first_child(doc, node); c;
         c = nx_node_next_sibling(doc, c))
        json_styles_node(out, doc, c, lay, first);
}

void nxd_dump_styles_json(FILE* out, NxDocument* doc, const NxLayout* lay) {
    if (!lay) {
        fputs("{\"styles\":[],\"error\":\"no layout\"}\n", out);
        return;
    }
    fputs("{\"styles\":[", out);
    bool first = true;
    json_styles_node(out, doc, nx_doc_root(doc), lay, &first);
    fputs("]}\n", out);
}

static void json_decl_value(FILE* out, const CsDecl* dc) {
    Fmt f = {NULL, 0, 0};
    char val[512];
    f.buf = val;
    f.cap = (int)sizeof(val);
    val[0] = '\0';
    for (int t = 0; t < dc->ntoks; t++) {
        if (dc->toks[t].kind == CS_WS) continue;
        if (f.n > 0) fmt_lit(&f, " ");
        fmt_tok(&f, &dc->toks[t]);
    }
    json_str(out, val, -1);
}

void nxd_dump_css_json(FILE* out, CsSheet* sheet) {
    fprintf(out, "{\"rules\":[");
    for (int i = 0; i < sheet->rule_count; i++) {
        const CsRule* r = &sheet->rules[i];
        char sel[512];
        nxd_format_selector(&r->sel, sel, sizeof(sel));
        if (i) fputc(',', out);
        fputs("{\"selector\":", out);
        json_str(out, sel, -1);
        fputs(",\"media\":", out);
        if (r->media) json_str(out, r->media, -1);
        else fputs("null", out);
        fprintf(out, ",\"pseudo_element\":%s,\"decls\":[",
                r->is_pseudo_element ? "true" : "false");
        for (int d = 0; d < r->decl_count; d++) {
            const CsDecl* dc = &r->decls[d];
            if (d) fputc(',', out);
            fputs("{\"name\":", out);
            json_str(out, dc->name, dc->name_len);
            fputs(",\"value\":", out);
            json_decl_value(out, dc);
            fprintf(out, ",\"important\":%s}", dc->important ? "true" : "false");
        }
        fputs("]}", out);
    }
    fprintf(out, "],\"dropped_rules\":%d,\"dropped_decls\":%d,"
                 "\"unknown_decls\":%d}\n",
            sheet->dropped_rules, sheet->dropped_decls, sheet->unknown_decls);
}
