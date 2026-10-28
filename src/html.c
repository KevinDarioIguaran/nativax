#include "nativax/html.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define NX_MAX_ACTIVE 128

typedef struct Parser {
    NxDocument* doc;
    const char* s;
    int len;
    int pos;
    NxNodeRef stack[NX_MAX_DEPTH + 4]; /* open elements (handles) */
    int sp;
    int mode; /* 0 initial/after-head, 1 head, 2 body */
    NxNodeRef html, head, body;
    /* simplified active formatting list (adoption-agency subset): entries
       stay active when popped incidentally and are reconstructed before
       text insertion; removed on their own end tag or same-tag reopen */
    NxNodeRef active[NX_MAX_ACTIVE];
    int active_count;
    bool in_rawtext; /* appending content of script/style/textarea/title */
    char err[256];
    bool failed;
} Parser;

static char ascii_lower(char c) {
    return (c >= 'A' && c <= 'Z') ? (char)(c - 'A' + 'a') : c;
}

static bool starts_with_ci(const char* s, int len, int pos, const char* lit) {
    int n = (int)strlen(lit);
    if (pos + n > len) return false;
    for (int i = 0; i < n; i++) {
        if (ascii_lower(s[pos + i]) != ascii_lower(lit[i])) return false;
    }
    return true;
}

static bool is_ws(char c) {
    return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f';
}

static bool is_name_char(char c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') ||
           c == '-' || c == '_' || c == ':';
}

static void fail(Parser* p, const char* msg) {
    if (p->failed) return;
    p->failed = true;
    snprintf(p->err, sizeof(p->err), "%s (offset %d)", msg, p->pos);
}

static const char* tag_of(Parser* p, NxNodeRef n) { return nx_node_name(p->doc, n); }

static bool stack_has(Parser* p, NxNodeRef el) {
    for (int i = 0; i < p->sp; i++) {
        if (p->stack[i] == el) return true;
    }
    return false;
}

/* returns false when the depth limit is reached (caller keeps the element
   appended but unpushed — nesting is flattened, parse continues) */
static bool push_open(Parser* p, NxNodeRef el) {
    if (p->sp >= NX_MAX_DEPTH) return false;
    p->stack[p->sp++] = el;
    return true;
}

/* find open element by tag with scope stoppers; -1 = not found */
static int find_open(Parser* p, const char* tag, const char* const* stop, int stop_n) {
    for (int i = p->sp - 1; i >= 0; i--) {
        const char* t = tag_of(p, p->stack[i]);
        if (!t) continue;
        if (strcmp(t, tag) == 0) return i;
        for (int j = 0; j < stop_n; j++) {
            if (strcmp(t, stop[j]) == 0) return -1;
        }
    }
    return -1;
}

static void close_at(Parser* p, int idx) {
    if (idx >= 0 && idx < p->sp) p->sp = idx; /* pops idx and everything above */
}

static NxNodeRef make_el(Parser* p, const char* tag) {
    NxNodeRef n = nx_node_create_element(p->doc, tag);
    if (!n) fail(p, "node limit exceeded");
    return n;
}

static void ensure_html(Parser* p) {
    if (p->html || p->failed) return;
    p->html = make_el(p, "html");
    if (p->failed) return;
    if (!nx_node_append_child(p->doc, nx_doc_root(p->doc), p->html)) {
        fail(p, "cannot attach html");
        return;
    }
    push_open(p, p->html);
}

static void ensure_head(Parser* p) {
    ensure_html(p);
    if (p->failed || p->mode == 2) return;
    if (p->head) {
        /* head existed and was closed: re-open it */
        if (!stack_has(p, p->head)) push_open(p, p->head);
        p->mode = 1;
        return;
    }
    p->head = make_el(p, "head");
    if (p->failed) return;
    nx_node_append_child(p->doc, p->html, p->head);
    push_open(p, p->head);
    p->mode = 1;
}

static void ensure_body(Parser* p) {
    ensure_html(p);
    if (p->failed || p->mode == 2) return;
    /* an explicit <head> always precedes body content (HTML5 rules) */
    if (p->mode == 0) ensure_head(p);
    if (p->failed) return;
    /* implied </head> */
    static const char* stop[] = {"body", "html"};
    close_at(p, find_open(p, "head", stop, 2));
    if (p->body) {
        if (!stack_has(p, p->body)) push_open(p, p->body); /* re-open after </body> */
        p->mode = 2;
        return;
    }
    p->body = make_el(p, "body");
    if (p->failed) return;
    nx_node_append_child(p->doc, p->html, p->body);
    push_open(p, p->body);
    p->mode = 2;
}

/* repair insertion modes after explicit </head> / </body> closes */
static void sync_modes(Parser* p) {
    if (p->mode == 1 && p->head && !stack_has(p, p->head)) {
        p->mode = p->body ? 2 : 0;
    }
    if (p->mode == 2 && p->body && !stack_has(p, p->body)) {
        push_open(p, p->body); /* content after </body> stays in body */
    }
}

/* ---- active formatting (simplified adoption agency) ---- */
static bool is_formatting(const char* tag) {
    static const char* k_fmt[] = {"a",      "b",    "big", "code", "em",  "font",
                                  "i",      "nobr", "s",   "small", "strike", "strong",
                                  "tt",     "u"};
    for (size_t i = 0; i < sizeof(k_fmt) / sizeof(k_fmt[0]); i++) {
        if (strcmp(tag, k_fmt[i]) == 0) return true;
    }
    return false;
}

static void active_remove_tag(Parser* p, const char* tag) {
    for (int i = 0; i < p->active_count;) {
        const char* t = tag_of(p, p->active[i]);
        if (t && strcmp(t, tag) == 0) {
            memmove(&p->active[i], &p->active[i + 1],
                    sizeof(NxNodeRef) * (size_t)(p->active_count - i - 1));
            p->active_count--;
        } else {
            i++;
        }
    }
}

static void active_push(Parser* p, NxNodeRef el) {
    if (p->active_count == NX_MAX_ACTIVE) {
        memmove(&p->active[0], &p->active[1], sizeof(NxNodeRef) * (NX_MAX_ACTIVE - 1));
        p->active_count--;
    }
    p->active[p->active_count++] = el;
}

/* recreate formatting elements that were popped incidentally, before text */
static void reconstruct_active(Parser* p) {
    while (p->active_count > 0) {
        NxNodeRef last = p->active[p->active_count - 1];
        if (stack_has(p, last)) return;
        const char* t = tag_of(p, last);
        if (!t) {
            p->active_count--; /* stale handle */
            continue;
        }
        if (p->sp == 0) {
            ensure_body(p);
            if (p->failed || p->sp == 0) return;
        }
        NxNodeRef copy = make_el(p, t);
        if (p->failed) return;
        int n = nx_node_attr_count(p->doc, last);
        for (int i = 0; i < n; i++) {
            nx_node_set_attr(p->doc, copy, nx_node_attr_name(p->doc, last, i),
                             nx_node_attr_value(p->doc, last, i));
        }
        if (!nx_node_append_child(p->doc, p->stack[p->sp - 1], copy)) return;
        if (!push_open(p, copy)) return;
        p->active[p->active_count - 1] = copy; /* list tracks the live handle */
    }
}

/* ---- text with merging into a trailing text sibling ---- */
static void append_text(Parser* p, const char* txt, int len, bool decode) {
    if (len <= 0 || p->failed) return;
    /* mode transitions never apply to rawtext/RCDATA content: it belongs to
       the open script/style/textarea/title element */
    if (!p->in_rawtext && p->mode < 2) {
        bool only_ws = true;
        for (int i = 0; i < len; i++) {
            if (!is_ws(txt[i])) {
                only_ws = false;
                break;
            }
        }
        if (only_ws) {
            if (p->mode == 0) return; /* whitespace before <html> is dropped */
            /* mode 1: whitespace between head elements falls through */
        } else {
            ensure_body(p); /* real content always starts/moves to body */
            if (p->failed) return;
        }
    }
    if (p->sp == 0) return;
    if (!p->in_rawtext) reconstruct_active(p);
    if (p->failed || p->sp == 0) return;
    NxNodeRef parent = p->stack[p->sp - 1];

    char* decoded = NULL;
    if (decode) {
        decoded = nx_html_unescape(txt, len, &len);
        txt = decoded;
    }

    NxNodeRef last = nx_node_last_child(p->doc, parent);
    if (last && nx_node_type(p->doc, last) == NX_NODE_TEXT) {
        int old_len = 0;
        const char* old = nx_node_text(p->doc, last, &old_len);
        char* merged = malloc((size_t)old_len + (size_t)len + 1);
        memcpy(merged, old, (size_t)old_len);
        memcpy(merged + old_len, txt, (size_t)len);
        nx_node_replace_text(p->doc, last, merged, old_len + len);
        free(merged);
    } else {
        NxNodeRef t = nx_node_create_text(p->doc, txt, len);
        if (!t) {
            fail(p, "node limit exceeded");
            free(decoded);
            return;
        }
        nx_node_append_child(p->doc, parent, t);
    }
    free(decoded);
}

/* ---- implied end tags ---- */
static bool closes_p(const char* tag) {
    static const char* k[] = {"address", "article", "aside", "blockquote", "center",
                              "details", "dd",       "dialog", "dir",       "div",
                              "dl",      "dt",       "fieldset", "figcaption", "figure",
                              "footer",  "form",     "h1",    "h2",        "h3",
                              "h4",      "h5",       "h6",    "header",    "hgroup",
                              "hr",      "li",       "listing", "main",     "menu",
                              "nav",     "ol",       "p",     "plaintext", "pre",
                              "section", "summary",  "table", "ul",        "xmp"};
    for (size_t i = 0; i < sizeof(k) / sizeof(k[0]); i++) {
        if (strcmp(tag, k[i]) == 0) return true;
    }
    return false;
}

static void close_implied(Parser* p, const char* tag) {
    static const char* stop_li[] = {"ul", "ol", "menu", "table"};
    static const char* stop_dl[] = {"dl", "table"};
    static const char* stop_p[] = {"table", "td", "th", "body", "html"};
    static const char* stop_select[] = {"select", "table"};
    static const char* stop_table[] = {"table", "html"};
    static const char* stop_tr[] = {"tr", "table", "html"};
    static const char* stop_cell[] = {"tr", "table", "html"};
    static const char* stop_fmt[] = {"table", "html"};

    if (closes_p(tag)) close_at(p, find_open(p, "p", stop_p, 5));

    if (strcmp(tag, "li") == 0) {
        close_at(p, find_open(p, "li", stop_li, 4));
    } else if (strcmp(tag, "dd") == 0 || strcmp(tag, "dt") == 0) {
        int a = find_open(p, "dd", stop_dl, 2);
        int b = find_open(p, "dt", stop_dl, 2);
        close_at(p, a > b ? a : b);
    } else if (strcmp(tag, "option") == 0) {
        close_at(p, find_open(p, "option", stop_select, 2));
    } else if (strcmp(tag, "optgroup") == 0) {
        int a = find_open(p, "optgroup", stop_select, 2);
        int b = find_open(p, "option", stop_select, 2);
        close_at(p, a > b ? a : b);
    } else if (strcmp(tag, "thead") == 0 || strcmp(tag, "tbody") == 0 ||
               strcmp(tag, "tfoot") == 0) {
        int best = -1;
        const char* parts[3] = {"thead", "tbody", "tfoot"};
        for (int i = 0; i < 3; i++) {
            int idx = find_open(p, parts[i], stop_table, 2);
            if (idx > best) best = idx;
        }
        close_at(p, best);
    } else if (strcmp(tag, "tr") == 0) {
        close_at(p, find_open(p, "tr", stop_tr, 3));
    } else if (strcmp(tag, "td") == 0 || strcmp(tag, "th") == 0) {
        int a = find_open(p, "td", stop_cell, 3);
        int b = find_open(p, "th", stop_cell, 3);
        close_at(p, a > b ? a : b);
    } else if (is_formatting(tag)) {
        /* same-tag reopen: close the previous instance (stack + active list) */
        close_at(p, find_open(p, tag, stop_fmt, 2));
        active_remove_tag(p, tag);
    }
}

static bool is_void(const char* tag) {
    static const char* k_void[] = {"area",   "base",   "basefont", "bgsound", "br",
                                   "col",    "embed",  "frame",    "hr",      "img",
                                   "input",  "keygen", "link",     "meta",    "param",
                                   "source", "track",  "wbr"};
    for (size_t i = 0; i < sizeof(k_void) / sizeof(k_void[0]); i++) {
        if (strcmp(tag, k_void[i]) == 0) return true;
    }
    return false;
}

static bool is_headish(const char* tag) {
    static const char* k_head[] = {"base",    "basefont", "bgsound", "link",
                                   "meta",    "noembed",  "noframes", "script",
                                   "style",   "template", "title"};
    for (size_t i = 0; i < sizeof(k_head) / sizeof(k_head[0]); i++) {
        if (strcmp(tag, k_head[i]) == 0) return true;
    }
    return false;
}

static bool is_ignored_in_body(const char* tag) {
    /* frame/frameset are ignored in document bodies (matches reference) */
    return strcmp(tag, "frame") == 0 || strcmp(tag, "frameset") == 0;
}

/* breakout of foreign content (svg/math) back into HTML parsing */
static bool is_breakout(const char* tag) {
    static const char* k[] = {
        "b", "big", "blockquote", "body", "br", "center", "code", "dd", "div", "dl",
        "dt", "em", "embed", "h1", "h2", "h3", "h4", "h5", "h6", "head", "hr", "i",
        "img", "li", "menu", "meta", "nobr", "ol", "p", "pre", "ruby", "s", "small",
        "span", "strong", "strike", "sub", "sup", "table", "tt", "u", "ul", "var"};
    for (size_t i = 0; i < sizeof(k) / sizeof(k[0]); i++) {
        if (strcmp(tag, k[i]) == 0) return true;
    }
    return false;
}

static bool in_foreign(Parser* p) {
    for (int i = p->sp - 1; i >= 0; i--) {
        const char* t = tag_of(p, p->stack[i]);
        if (t && (strcmp(t, "svg") == 0 || strcmp(t, "math") == 0)) return true;
    }
    return false;
}

static void breakout_foreign(Parser* p) {
    while (p->sp > 0) {
        const char* t = tag_of(p, p->stack[p->sp - 1]);
        if (t && (strcmp(t, "svg") == 0 || strcmp(t, "math") == 0)) {
            p->sp--;
        } else {
            break;
        }
    }
}

/* ---- raw text / rcdata (script, style, textarea, title) ---- */
static void do_raw_text(Parser* p, const char* tag, bool rcdata) {
    int content_start = p->pos;
    char close_lit[32];
    snprintf(close_lit, sizeof(close_lit), "</%s", tag);
    int close_pos = -1;
    for (int i = content_start; i + (int)strlen(close_lit) < p->len; i++) {
        if (starts_with_ci(p->s, p->len, i, close_lit)) {
            int after = i + (int)strlen(close_lit);
            /* requires a real tag terminator; "</script" at EOF stays raw */
            if (is_ws(p->s[after]) || p->s[after] == '>' || p->s[after] == '/') {
                close_pos = i;
                break;
            }
        }
    }
    p->in_rawtext = true;
    if (close_pos < 0) {
        append_text(p, p->s + content_start, p->len - content_start, rcdata);
        p->pos = p->len;
        p->in_rawtext = false;
        return;
    }
    if (close_pos > content_start) {
        append_text(p, p->s + content_start, close_pos - content_start, rcdata);
    }
    p->in_rawtext = false;
    /* skip to '>' of the close tag */
    p->pos = close_pos;
    while (p->pos < p->len && p->s[p->pos] != '>') p->pos++;
    if (p->pos < p->len) p->pos++;
    /* pop the raw-text element if it was pushed */
    static const char* stop[] = {"html", "body"};
    close_at(p, find_open(p, tag, stop, 2));
}

/* ---- tags ---- */
static void handle_open_tag(Parser* p) {
    bool foreign = in_foreign(p);
    p->pos++; /* skip '<' */
    int name_start = p->pos;
    while (p->pos < p->len && is_name_char(p->s[p->pos])) p->pos++;
    int name_len = p->pos - name_start;
    if (name_len == 0) {
        append_text(p, "<", 1, false);
        return;
    }
    char name[64];
    if (name_len > 63) name_len = 63;
    for (int i = 0; i < name_len; i++) {
        name[i] = foreign ? p->s[name_start + i] : ascii_lower(p->s[name_start + i]);
    }
    name[name_len] = '\0';

    /* attributes (values malloc'd: realistic style/src values exceed small
       stack buffers; reads truncate at 2047 bytes — documented limit) */
    struct {
        char name[128];
        char* value;
    } attrs[64];
    int attr_count = 0;
    bool self_closing = false;
    bool closed = false;
    while (p->pos < p->len && !closed) {
        while (p->pos < p->len && is_ws(p->s[p->pos])) p->pos++;
        if (p->pos >= p->len) break;
        char c = p->s[p->pos];
        if (c == '>') {
            p->pos++;
            closed = true;
            break;
        }
        if (c == '/') {
            if (p->pos + 1 < p->len && p->s[p->pos + 1] == '>') {
                self_closing = true;
                p->pos += 2;
                closed = true;
                break;
            }
            p->pos++; /* stray slash */
            continue;
        }
        /* attribute name */
        int an_start = p->pos;
        while (p->pos < p->len && !is_ws(p->s[p->pos]) && p->s[p->pos] != '=' &&
               p->s[p->pos] != '>' && p->s[p->pos] != '/') {
            p->pos++;
        }
        int an_len = p->pos - an_start;
        if (an_len == 0) {
            p->pos++; /* skip offending char (e.g. quote) */
            continue;
        }
        char an[128];
        int an_copy = an_len > 127 ? 127 : an_len;
        for (int i = 0; i < an_copy; i++) {
            an[i] = foreign ? p->s[an_start + i] : ascii_lower(p->s[an_start + i]);
        }
        an[an_copy] = '\0';
        /* optional value */
        char av[2048] = "";
        while (p->pos < p->len && is_ws(p->s[p->pos])) p->pos++;
        if (p->pos < p->len && p->s[p->pos] == '=') {
            p->pos++;
            while (p->pos < p->len && is_ws(p->s[p->pos])) p->pos++;
            if (p->pos < p->len && (p->s[p->pos] == '"' || p->s[p->pos] == '\'')) {
                char q = p->s[p->pos++];
                int vs = p->pos;
                while (p->pos < p->len && p->s[p->pos] != q) p->pos++;
                int vl = p->pos - vs;
                if (p->pos < p->len) p->pos++; /* closing quote */
                if (vl > 2047) vl = 2047;
                memcpy(av, p->s + vs, (size_t)vl);
                av[vl] = '\0';
            } else {
                int vs = p->pos;
                while (p->pos < p->len && !is_ws(p->s[p->pos]) && p->s[p->pos] != '>') {
                    p->pos++;
                }
                int vl = p->pos - vs;
                if (vl > 2047) vl = 2047;
                memcpy(av, p->s + vs, (size_t)vl);
                av[vl] = '\0';
            }
        } else {
            av[0] = '\0'; /* boolean attribute: empty value (HTML5) */
        }
        if (attr_count < 64) {
            bool dup = false;
            for (int i = 0; i < attr_count; i++) {
                if (strcmp(attrs[i].name, an) == 0) {
                    dup = true; /* first wins */
                    break;
                }
            }
            if (!dup) {
                snprintf(attrs[attr_count].name, sizeof(attrs[0].name), "%s", an);
                int out_len = 0;
                attrs[attr_count].value = nx_html_unescape(av, -1, &out_len);
                attr_count++;
            }
        }
    }
    if (!closed) {
        /* truncated tag at EOF: dropped (documented) */
        for (int i = 0; i < attr_count; i++) free(attrs[i].value);
        p->pos = p->len;
        return;
    }

    /* special elements */
    if (!foreign && strcmp(name, "html") == 0) {
        ensure_html(p);
        if (p->failed) {
            for (int i = 0; i < attr_count; i++) free(attrs[i].value);
            return;
        }
        for (int i = 0; i < attr_count; i++) {
            if (!nx_node_get_attr(p->doc, p->html, attrs[i].name)) {
                nx_node_set_attr(p->doc, p->html, attrs[i].name, attrs[i].value);
            }
            free(attrs[i].value);
        }
        return;
    }
    if (!foreign && strcmp(name, "head") == 0) {
        if (p->mode == 2) {
            for (int i = 0; i < attr_count; i++) free(attrs[i].value);
            return; /* stray head in body: dropped */
        }
        ensure_head(p);
        if (p->failed) {
            for (int i = 0; i < attr_count; i++) free(attrs[i].value);
            return;
        }
        for (int i = 0; i < attr_count; i++) {
            if (!nx_node_get_attr(p->doc, p->head, attrs[i].name)) {
                nx_node_set_attr(p->doc, p->head, attrs[i].name, attrs[i].value);
            }
            free(attrs[i].value);
        }
        return; /* head is managed by ensure_head, never appended as content */
    }
    if (!foreign && strcmp(name, "body") == 0) {
        ensure_body(p);
        if (p->failed) {
            for (int i = 0; i < attr_count; i++) free(attrs[i].value);
            return;
        }
        for (int i = 0; i < attr_count; i++) {
            if (!nx_node_get_attr(p->doc, p->body, attrs[i].name)) {
                nx_node_set_attr(p->doc, p->body, attrs[i].name, attrs[i].value);
            }
            free(attrs[i].value);
        }
        return;
    }
    if (!foreign && is_ignored_in_body(name)) {
        for (int i = 0; i < attr_count; i++) free(attrs[i].value);
        return; /* frame/frameset dropped */
    }
    if (!foreign && strcmp(name, "form") == 0) {
        static const char* stop[] = {"table", "html"};
        if (find_open(p, "form", stop, 2) >= 0) {
            for (int i = 0; i < attr_count; i++) free(attrs[i].value);
            return; /* nested forms ignored */
        }
    }
    if (foreign && is_breakout(name)) {
        for (int i = 0; i < attr_count; i++) free(attrs[i].value);
        breakout_foreign(p);
        foreign = false;
        /* fall through and parse as normal HTML */
    }

    /* insertion mode (HTML content only) */
    if (!foreign) {
        if (is_headish(name)) {
            if (p->mode == 0) ensure_head(p);
        } else {
            if (p->mode < 2) ensure_body(p);
        }
        if (p->failed) {
            for (int i = 0; i < attr_count; i++) free(attrs[i].value);
            return;
        }
        close_implied(p, name);
    }

    NxNodeRef parent = p->sp > 0 ? p->stack[p->sp - 1] : 0;
    if (!parent) {
        for (int i = 0; i < attr_count; i++) free(attrs[i].value);
        return;
    }
    /* nesting limit: drop the token and keep parsing (flattened, like the
       reference runtime) */
    if (nx_node_depth(p->doc, parent) + 1 > NX_MAX_DEPTH) {
        for (int i = 0; i < attr_count; i++) free(attrs[i].value);
        return;
    }
    NxNodeRef el = make_el(p, name);
    if (p->failed) {
        for (int i = 0; i < attr_count; i++) free(attrs[i].value);
        return;
    }
    for (int i = 0; i < attr_count; i++) {
        nx_node_set_attr(p->doc, el, attrs[i].name, attrs[i].value);
        free(attrs[i].value);
    }
    if (!nx_node_append_child(p->doc, parent, el)) {
        fail(p, "cannot attach element");
        return;
    }
    if (is_formatting(name) && !foreign) active_push(p, el);

    bool pushed = false;
    if (is_void(name)) return;
    if (self_closing && foreign) return; /* self-closing honored in svg/math */
    /* HTML: "/>" on non-void is ignored — element stays open (HTML5) */
    pushed = push_open(p, el);
    (void)pushed;
    if (strcmp(name, "script") == 0 || strcmp(name, "style") == 0) {
        do_raw_text(p, name, false);
    } else if (strcmp(name, "textarea") == 0 || strcmp(name, "title") == 0) {
        do_raw_text(p, name, true);
    }
}

static void handle_close_tag(Parser* p) {
    int gt_pos = p->pos;
    while (gt_pos < p->len && p->s[gt_pos] != '>') gt_pos++;
    if (gt_pos >= p->len) {
        /* truncated end tag at EOF: dropped (documented) */
        p->pos = p->len;
        return;
    }
    p->pos += 2; /* skip '</' */
    int name_start = p->pos;
    while (p->pos < p->len && is_name_char(p->s[p->pos])) p->pos++;
    int name_len = p->pos - name_start;
    char name[64] = "";
    if (name_len > 0) {
        if (name_len > 63) name_len = 63;
        for (int i = 0; i < name_len; i++) name[i] = ascii_lower(p->s[name_start + i]);
    }
    p->pos = gt_pos + 1;
    if (name_len == 0) return; /* </> : ignore */

    /* quirks: </br> acts as <br>; </p> with no open p inserts one */
    if (strcmp(name, "br") == 0) {
        if (p->mode == 0) ensure_body(p);
        if (!p->failed && p->sp > 0) {
            NxNodeRef br = make_el(p, "br");
            if (!p->failed) nx_node_append_child(p->doc, p->stack[p->sp - 1], br);
        }
        return;
    }
    if (strcmp(name, "p") == 0) {
        static const char* stop_p[] = {"table", "td", "th", "body", "html"};
        if (find_open(p, "p", stop_p, 5) < 0) {
            if (p->mode == 0) ensure_body(p);
            if (!p->failed && p->sp > 0) {
                NxNodeRef pp = make_el(p, "p");
                if (!p->failed) nx_node_append_child(p->doc, p->stack[p->sp - 1], pp);
            }
            return;
        }
    }
    /* </form> only closes when form is the innermost open element
       (simplification matching the reference runtime) */
    if (strcmp(name, "form") == 0) {
        if (p->sp > 0 && strcmp(tag_of(p, p->stack[p->sp - 1]), "form") == 0) {
            p->sp--;
        }
        return;
    }

    for (int i = p->sp - 1; i >= 0; i--) {
        const char* t = tag_of(p, p->stack[i]);
        if (t && strcmp(t, name) == 0) {
            p->sp = i;
            /* formatting elements popped by their OWN end tag leave the
               active list; popped incidentally (by an outer close) stay */
            if (is_formatting(name)) active_remove_tag(p, name);
            return;
        }
    }
    /* stray close tag: ignored */
    if (is_formatting(name)) active_remove_tag(p, name);
}

static void handle_comment(Parser* p, int start_after_open, const char* close_lit) {
    int content_start = start_after_open;
    int close_pos = -1;
    int clen = (int)strlen(close_lit);
    for (int i = content_start; i + clen <= p->len; i++) {
        if (memcmp(p->s + i, close_lit, (size_t)clen) == 0) {
            close_pos = i;
            break;
        }
    }
    int content_end = close_pos >= 0 ? close_pos : p->len;
    NxNodeRef c = nx_node_create_comment(p->doc, p->s + content_start, content_end - content_start);
    if (!c) {
        fail(p, "node limit exceeded");
        return;
    }
    NxNodeRef parent = p->sp > 0 ? p->stack[p->sp - 1] : nx_doc_root(p->doc);
    nx_node_append_child(p->doc, parent, c);
    p->pos = close_pos >= 0 ? close_pos + clen : p->len;
}

static void skip_to_gt(Parser* p) {
    while (p->pos < p->len && p->s[p->pos] != '>') p->pos++;
    if (p->pos < p->len) p->pos++;
}

/* ---- main loop ---- */
static bool parse_loop(Parser* p) {
    while (p->pos < p->len && !p->failed) {
        sync_modes(p);
        char c = p->s[p->pos];
        if (c == '<') {
            if (p->pos + 1 >= p->len) {
                append_text(p, "<", 1, false);
                p->pos++;
                continue;
            }
            char n1 = p->s[p->pos + 1];
            if (n1 == '/') {
                if (p->pos + 2 < p->len && is_name_char(p->s[p->pos + 2])) {
                    handle_close_tag(p);
                } else {
                    p->pos += 2; /* </ or </x garbage: bogus comment */
                    skip_to_gt(p);
                }
                continue;
            }
            if (n1 == '!') {
                if (starts_with_ci(p->s, p->len, p->pos + 2, "--")) {
                    handle_comment(p, p->pos + 4, "-->");
                } else if (starts_with_ci(p->s, p->len, p->pos + 2, "doctype")) {
                    p->pos += 2;
                    skip_to_gt(p); /* doctype recorded as skipped (documented) */
                } else if (starts_with_ci(p->s, p->len, p->pos + 2, "[CDATA[")) {
                    p->pos += 2;
                    skip_to_gt(p); /* not HTML-recognized: bogus (documented) */
                } else {
                    p->pos += 2;
                    skip_to_gt(p); /* bogus comment */
                }
                continue;
            }
            if (n1 == '?') {
                p->pos += 2;
                skip_to_gt(p); /* bogus comment (XML PI) */
                continue;
            }
            if (is_name_char(n1)) {
                handle_open_tag(p);
                continue;
            }
            append_text(p, "<", 1, false); /* literal '<' */
            p->pos++;
            continue;
        }
        /* text run */
        int start = p->pos;
        while (p->pos < p->len && p->s[p->pos] != '<') p->pos++;
        append_text(p, p->s + start, p->pos - start, true);
    }
    return !p->failed;
}

bool nx_html_parse(NxDocument* doc, const char* html, int len, char** error_out) {
    if (error_out) *error_out = NULL;
    if (!doc || !html) {
        if (error_out) *error_out = strdup("null argument");
        return false;
    }
    if (len < 0) len = (int)strlen(html);
    if (len > NX_HTML_MAX_INPUT) {
        if (error_out) *error_out = strdup("input exceeds 4 MiB limit");
        return false;
    }

    /* clear existing children (fresh document per page load; hot reload
       creates a new document) */
    for (NxNodeRef c = nx_node_first_child(doc, nx_doc_root(doc)); c;) {
        NxNodeRef next = nx_node_next_sibling(doc, c);
        nx_node_remove_child(doc, nx_doc_root(doc), c);
        c = next;
    }

    Parser p;
    memset(&p, 0, sizeof(p));
    p.doc = doc;
    p.s = html;
    p.len = len;
    p.pos = 0;

    bool ok = parse_loop(&p);
    if (ok) {
        /* every document ends with html/head/body (reference behavior) */
        ensure_body(&p);
        ok = !p.failed;
    }
    if (!ok && error_out) *error_out = strdup(p.err);
    return ok;
}
