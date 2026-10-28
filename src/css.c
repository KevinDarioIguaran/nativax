#include "nativax/css.h"

#include <ctype.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ------------------------------------------------------------------ */
/* tokenizer                                                          */
/* ------------------------------------------------------------------ */

static char lower_c(char c) { return (char)tolower((unsigned char)c); }

static bool is_ws_c(char c) {
    return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f';
}

static bool is_ident_start(char c) {
    return isalpha((unsigned char)c) || c == '_' || (unsigned char)c >= 0x80 || c == '\\';
}

static bool is_ident_char(char c) {
    return isalnum((unsigned char)c) || c == '-' || c == '_' || (unsigned char)c >= 0x80 ||
           c == '\\';
}

static void tok_push(CsTokens* t, CsTok tok) {
    if (t->count == t->cap) {
        t->cap = t->cap ? t->cap * 2 : 64;
        t->toks = realloc(t->toks, (size_t)t->cap * sizeof(CsTok));
    }
    t->toks[t->count++] = tok;
}

static char* str_new(CsTokens* t, const char* s, int len) {
    char* c = malloc((size_t)len + 1);
    memcpy(c, s, (size_t)len);
    c[len] = '\0';
    if (t->str_count == t->str_cap) {
        t->str_cap = t->str_cap ? t->str_cap * 2 : 32;
        t->strs = realloc(t->strs, (size_t)t->str_cap * sizeof(char*));
    }
    t->strs[t->str_count++] = c;
    return c;
}

/* decode \XX hex and \c escapes; returns length (NUL-terminated) */
static int decode_escapes(const char* s, int len, char* out) {
    int o = 0;
    for (int i = 0; i < len; i++) {
        if (s[i] != '\\') {
            out[o++] = s[i];
            continue;
        }
        i++;
        if (i >= len) break;
        if (isxdigit((unsigned char)s[i])) {
            int cp = 0, digits = 0;
            while (i < len && digits < 6 && isxdigit((unsigned char)s[i])) {
                char c = lower_c(s[i]);
                cp = cp * 16 + (c <= '9' ? c - '0' : c - 'a' + 10);
                i++;
                digits++;
            }
            /* one optional whitespace after a hex escape is consumed */
            if (i < len && is_ws_c(s[i])) {
                if (s[i] == '\r' && i + 1 < len && s[i + 1] == '\n') i++;
                i++;
            }
            i--;
            if (cp == 0 || cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF)) {
                out[o++] = (char)0xEF; /* U+FFFD */
                out[o++] = (char)0xBF;
                out[o++] = (char)0xBD;
            } else if (cp < 0x80) {
                out[o++] = (char)cp;
            } else if (cp < 0x800) {
                out[o++] = (char)(0xC0 | (cp >> 6));
                out[o++] = (char)(0x80 | (cp & 0x3F));
            } else if (cp < 0x10000) {
                out[o++] = (char)(0xE0 | (cp >> 12));
                out[o++] = (char)(0x80 | ((cp >> 6) & 0x3F));
                out[o++] = (char)(0x80 | (cp & 0x3F));
            } else {
                out[o++] = (char)(0xF0 | (cp >> 18));
                out[o++] = (char)(0x80 | ((cp >> 12) & 0x3F));
                out[o++] = (char)(0x80 | ((cp >> 6) & 0x3F));
                out[o++] = (char)(0x80 | (cp & 0x3F));
            }
            continue;
        }
        if (s[i] == '\n') continue; /* escaped newline yields nothing */
        out[o++] = s[i];
    }
    out[o] = '\0';
    return o;
}

/* lowercased ident name with CSS escapes decoded; returns length */
static int ident_name(const char* s, int len, char* out, int cap) {
    char tmp[512];
    const char* src = s;
    int slen = len;
    if (memchr(s, '\\', (size_t)len)) {
        slen = decode_escapes(s, len, tmp);
        src = tmp;
    }
    int n = slen > cap - 1 ? cap - 1 : slen;
    for (int k = 0; k < n; k++) out[k] = lower_c(src[k]);
    out[n] = '\0';
    return n;
}

bool cs_tokenize(const char* css, int len, CsTokens* out) {
    memset(out, 0, sizeof(*out));
    if (len < 0) len = (int)strlen(css);
    char dbuf[4096];
    int i = 0;
    while (i < len) {
        char c = css[i];
        int start = i;
        if (is_ws_c(c)) {
            while (i < len && is_ws_c(css[i])) i++;
            CsTok t = {CS_WS, css + start, i - start, 0, NULL, start};
            tok_push(out, t);
            continue;
        }
        if (c == '/' && i + 1 < len && css[i + 1] == '*') {
            i += 2;
            while (i + 1 < len && !(css[i] == '*' && css[i + 1] == '/')) i++;
            i = i + 1 < len ? i + 2 : len;
            continue; /* comments produce no tokens */
        }
        if (c == '<' && i + 3 < len && strncmp(css + i, "<!--", 4) == 0) {
            i += 4;
            CsTok t = {CS_CDO, css + start, 4, 0, NULL, start};
            tok_push(out, t);
            continue;
        }
        if (c == '-' && i + 2 < len && strncmp(css + i, "-->", 3) == 0) {
            i += 3;
            CsTok t = {CS_CDC, css + start, 3, 0, NULL, start};
            tok_push(out, t);
            continue;
        }
        {
            CsTokKind simple = CS_EOF;
            switch (c) {
                case '{': simple = CS_LBRACE; break;
                case '}': simple = CS_RBRACE; break;
                case '(': simple = CS_LPAREN; break;
                case ')': simple = CS_RPAREN; break;
                case '[': simple = CS_LBRACKET; break;
                case ']': simple = CS_RBRACKET; break;
                case ':': simple = CS_COLON; break;
                case ';': simple = CS_SEMI; break;
                case ',': simple = CS_COMMA; break;
                default: break;
            }
            if (simple != CS_EOF) {
                i++;
                CsTok t = {simple, css + start, 1, 0, NULL, start};
                tok_push(out, t);
                continue;
            }
        }
        if (c == '@') {
            i++;
            int s0 = i;
            while (i < len && is_ident_char(css[i])) i++;
            CsTok t = {CS_AT_KEYWORD, css + s0, i - s0, 0, NULL, start};
            tok_push(out, t);
            continue;
        }
        if (c == '"' || c == '\'') {
            char q = c;
            i++;
            int o = 0;
            bool bad = false;
            while (i < len) {
                if (css[i] == q) {
                    i++;
                    break;
                }
                if (css[i] == '\n') {
                    bad = true;
                    break;
                }
                if (css[i] == '\\' && i + 1 < len) {
                    /* keep the raw pair; decoded below from the raw slice */
                    if (o < (int)sizeof(dbuf) - 2) {
                        dbuf[o++] = '\\';
                        dbuf[o++] = css[i + 1];
                    }
                    i += (css[i + 1] == '\r' && i + 2 < len && css[i + 2] == '\n')
                             ? 3
                             : 2;
                    continue;
                }
                if (o < (int)sizeof(dbuf) - 1) dbuf[o++] = css[i];
                i++;
            }
            dbuf[o] = '\0';
            CsTok t;
            memset(&t, 0, sizeof(t));
            t.kind = bad ? CS_BAD_STRING : CS_STRING;
            t.s = css + start;
            t.len = i - start;
            t.pos = start;
            if (memchr(dbuf, '\\', (size_t)o)) {
                /* escaped content: decode over the raw slice (both quotes
                excluded) for correctness */
                int raw_len = i - start - 2;
                if (raw_len < 0) raw_len = 0;
                char* tmp = malloc((size_t)raw_len * 4 + 4);
                int dl = decode_escapes(css + start + 1, raw_len, tmp);
                t.str = str_new(out, tmp, dl);
                free(tmp);
            } else {
                t.str = str_new(out, dbuf, o);
            }
            tok_push(out, t);
            continue;
        }
        if (c == '#') {
            i++;
            int s0 = i;
            while (i < len && is_ident_char(css[i])) i++;
            CsTok t = {CS_HASH, css + s0, i - s0, 0, NULL, start};
            tok_push(out, t);
            continue;
        }
        if (isdigit((unsigned char)c) ||
            ((c == '+' || c == '-' || c == '.') && i + 1 < len &&
             (isdigit((unsigned char)css[i + 1]) ||
              (css[i + 1] == '.' && i + 2 < len && isdigit((unsigned char)css[i + 2]))))) {
            const char* p = css + i;
            const char* end = css + len;
            if (*p == '+' || *p == '-') p++;
            while (p < end && isdigit((unsigned char)*p)) p++;
            if (p < end && *p == '.') {
                p++;
                while (p < end && isdigit((unsigned char)*p)) p++;
            }
            if (p < end && (*p == 'e' || *p == 'E')) {
                const char* save = p;
                p++;
                if (p < end && (*p == '+' || *p == '-')) p++;
                if (p < end && isdigit((unsigned char)*p)) {
                    while (p < end && isdigit((unsigned char)*p)) p++;
                } else {
                    p = save;
                }
            }
            double num = strtod(css + i, NULL);
            i = (int)(p - css);
            CsTok t;
            memset(&t, 0, sizeof(t));
            t.num = num;
            t.pos = start;
            if (i < len && css[i] == '%') {
                i++;
                t.kind = CS_PERCENTAGE;
                t.s = css + start;
                t.len = i - start;
            } else if (i < len && is_ident_start(css[i])) {
                int u0 = i;
                while (i < len && is_ident_char(css[i])) i++;
                t.kind = CS_DIMENSION;
                t.s = css + u0; /* unit */
                t.len = i - u0;
            } else {
                t.kind = CS_NUMBER;
                t.s = css + start;
                t.len = i - start;
            }
            tok_push(out, t);
            continue;
        }
        if (is_ident_start(c) ||
            (c == '-' && i + 1 < len &&
             (is_ident_start(css[i + 1]) || css[i + 1] == '-' || css[i + 1] == '\\'))) {
            int s0 = i;
            while (i < len) {
                if (css[i] == '\\') {
                    i++;
                    int hx = 0;
                    while (i < len && hx < 6 && isxdigit((unsigned char)css[i])) {
                        i++;
                        hx++;
                    }
                    if (hx > 0 && i < len && is_ws_c(css[i])) {
                        if (css[i] == '\r' && i + 1 < len && css[i + 1] == '\n') i++;
                        i++; /* optional whitespace belongs to the escape */
                    } else if (hx == 0 && i < len) {
                        i++; /* \c escapes a single character */
                    }
                    continue;
                }
                if (is_ident_char(css[i])) {
                    i++;
                    continue;
                }
                break;
            }
            int name_len = i - s0;
            bool is_url = name_len == 3 && lower_c(css[s0]) == 'u' &&
                          lower_c(css[s0 + 1]) == 'r' && lower_c(css[s0 + 2]) == 'l';
            if (i < len && css[i] == '(') {
                i++;
                if (is_url) {
                    int save_i = i;
                    while (i < len && is_ws_c(css[i])) i++;
                    if (i < len && (css[i] == '"' || css[i] == '\'')) {
                        /* url("...") is a function token, not a url token */
                        i = save_i;
                        char nm[4] = "url";
                        CsTok t = {CS_FUNCTION, NULL, 0, 0, NULL, start};
                        t.str = str_new(out, nm, 3);
                        t.len = 3;
                        tok_push(out, t);
                        continue;
                    }
                    while (i < len && is_ws_c(css[i])) i++; /* leading ws ok */
                    int v0 = i;
                    int o = 0;
                    bool bad = false;
                    while (i < len) {
                        if (css[i] == ')') break;
                        if (css[i] == '(' || css[i] == '"' || css[i] == '\'') {
                            bad = true;
                            break;
                        }
                        if (is_ws_c(css[i])) {
                            int j = i;
                            while (j < len && is_ws_c(css[j])) j++;
                            if (j < len && css[j] == ')') { /* trailing ws before ) */
                                i = j;
                                break;
                            }
                            bad = true;
                            break;
                        }
                        if (o < (int)sizeof(dbuf) - 1) dbuf[o++] = css[i];
                        i++;
                    }
                    dbuf[o] = '\0';
                    if (i < len && css[i] == ')') i++;
                    CsTok t;
                    memset(&t, 0, sizeof(t));
                    t.pos = start;
                    if (bad) {
                        while (i < len && css[i] != ')') i++;
                        if (i < len) i++;
                        t.kind = CS_BAD_URL;
                        t.s = css + v0;
                        t.len = 0;
                    } else {
                        t.kind = CS_URL;
                        if (memchr(dbuf, '\\', (size_t)o)) {
                            char* tmp = malloc((size_t)o * 4 + 4);
                            int dl = decode_escapes(dbuf, o, tmp);
                            t.str = str_new(out, tmp, dl);
                            free(tmp);
                        } else {
                            t.str = str_new(out, dbuf, o);
                        }
                    }
                    tok_push(out, t);
                    continue;
                }
                /* function token: name lowercased into str */
                char nm[128];
                int copy = ident_name(css + s0, name_len, nm, sizeof(nm));
                CsTok t = {CS_FUNCTION, NULL, 0, 0, NULL, start};
                t.str = str_new(out, nm, copy);
                t.len = copy;
                tok_push(out, t);
                continue;
            }
            {
                char nm[128];
                int copy = ident_name(css + s0, name_len, nm, sizeof(nm));
                CsTok t = {CS_IDENT, NULL, 0, 0, NULL, start};
                t.str = str_new(out, nm, copy);
                t.len = copy;
                tok_push(out, t);
                continue;
            }
        }
        /* delim */
        i++;
        CsTok t = {CS_DELIM, css + start, 1, 0, NULL, start};
        tok_push(out, t);
    }
    CsTok eof = {CS_EOF, "", 0, 0, NULL, len};
    tok_push(out, eof);
    return true;
}

void cs_tokens_free(CsTokens* t) {
    free(t->toks);
    for (int i = 0; i < t->str_count; i++) free(t->strs[i]);
    free(t->strs);
    memset(t, 0, sizeof(*t));
}

bool cs_is_ident(const CsTok* t, const char* lit) {
    if (t->kind != CS_IDENT) return false;
    int n = (int)strlen(lit);
    return t->len == n && strncasecmp(t->str ? t->str : t->s, lit, (size_t)n) == 0;
}

bool cs_parse_number(const CsTok* t, double* out) {
    if (t->kind == CS_NUMBER || t->kind == CS_PERCENTAGE || t->kind == CS_DIMENSION) {
        *out = t->num;
        return true;
    }
    return false;
}

/* ------------------------------------------------------------------ */
/* selector parser                                                    */
/* ------------------------------------------------------------------ */

typedef struct SelP {
    const char* s;
    int len;
    int i;
} SelP;

static void sp_ws(SelP* p) {
    while (p->i < p->len && is_ws_c(p->s[p->i])) p->i++;
}

static bool sp_ident(SelP* p, const char** out, int* out_len) {
    int s0 = p->i;
    if (p->i < p->len &&
        (isalpha((unsigned char)p->s[p->i]) || p->s[p->i] == '_' ||
         p->s[p->i] == '-' || (unsigned char)p->s[p->i] >= 0x80)) {
        p->i++;
        while (p->i < p->len &&
               (isalnum((unsigned char)p->s[p->i]) || p->s[p->i] == '-' ||
                p->s[p->i] == '_' || (unsigned char)p->s[p->i] >= 0x80)) {
            p->i++;
        }
        *out = p->s + s0;
        *out_len = p->i - s0;
        return true;
    }
    return false;
}

static bool sp_compound(SelP* p, CsCompound* c);
static bool sp_simple(SelP* p, CsSimple* c);

/* reference pseudoElements set from the V1 selector implementation */
static bool pe_name_known(const char* nm, int len) {
    static const char* const names[] = {
        "before", "after", "marker", "placeholder", "backdrop", "selection",
        "first-line", "first-letter", "file-selector-button", "part",
        "slotted", "cue", "grammar-error", "spelling-error", "target-text",
        "details-content",
    };
    for (size_t i = 0; i < sizeof(names) / sizeof(names[0]); i++) {
        int nl = (int)strlen(names[i]);
        if (len == nl && strncasecmp(nm, names[i], (size_t)nl) == 0) return true;
    }
    if (len >= 8 && strncasecmp(nm, "-webkit-", 8) == 0) return true;
    if (len >= 5 && strncasecmp(nm, "-moz-", 5) == 0) return true;
    return false;
}

static bool sp_pseudo(SelP* p, CsCompound* c) {
    if (p->i >= p->len || p->s[p->i] != ':') return false;
    p->i++;
    if (p->i < p->len && p->s[p->i] == ':') {
        p->i++;
        const char* nm;
        int nlen;
        if (!sp_ident(p, &nm, &nlen)) return false;
        /* reference set (V1 pseudoElements) + -webkit-/-moz-
           prefixed names; anything else fails the selector */
        if (!pe_name_known(nm, nlen)) return false;
        c->pseudo_elem = nm;
        c->pseudo_elem_len = nlen;
        c->is_pseudo_elem = true; /* kept but skipped by cascade v1 */
        if (p->i < p->len && p->s[p->i] == '(') {
            /* ::part(x) / ::slotted(x): skip the argument (never matches) */
            int depth = 0;
            while (p->i < p->len) {
                if (p->s[p->i] == '(') depth++;
                else if (p->s[p->i] == ')') {
                    depth--;
                    if (depth == 0) {
                        p->i++;
                        break;
                    }
                }
                p->i++;
            }
            if (depth != 0) return false;
        }
        return true; /* the preceding pseudo-class (if any) stays */
    }
    const char* nm;
    int nlen;
    if (!sp_ident(p, &nm, &nlen)) return false;
    if (nlen == 4 && strncasecmp(nm, "root", 4) == 0) c->pseudo = CS_P_ROOT;
    else if (nlen == 5 && strncasecmp(nm, "hover", 5) == 0) c->pseudo = CS_P_HOVER;
    else if (nlen == 5 && strncasecmp(nm, "focus", 5) == 0) c->pseudo = CS_P_FOCUS;
    else if (nlen == 6 && strncasecmp(nm, "active", 6) == 0) c->pseudo = CS_P_ACTIVE;
    else if (nlen == 4 && strncasecmp(nm, "link", 4) == 0) c->pseudo = CS_P_LINK;
    else if (nlen == 7 && strncasecmp(nm, "visited", 7) == 0) c->pseudo = CS_P_VISITED;
    else if (nlen == 11 && strncasecmp(nm, "first-child", 11) == 0) c->pseudo = CS_P_FIRST_CHILD;
    else if (nlen == 10 && strncasecmp(nm, "last-child", 10) == 0) c->pseudo = CS_P_LAST_CHILD;
    else if (nlen == 10 && strncasecmp(nm, "only-child", 10) == 0) c->pseudo = CS_P_ONLY_CHILD;
    else if (nlen == 13 && strncasecmp(nm, "first-of-type", 13) == 0) c->pseudo = CS_P_FIRST_OF_TYPE;
    else if (nlen == 12 && strncasecmp(nm, "last-of-type", 12) == 0) c->pseudo = CS_P_LAST_OF_TYPE;
    else if (nlen == 5 && strncasecmp(nm, "empty", 5) == 0) c->pseudo = CS_P_EMPTY;
    else if (nlen == 7 && strncasecmp(nm, "checked", 7) == 0) c->pseudo = CS_P_CHECKED;
    else if (nlen == 8 && strncasecmp(nm, "disabled", 8) == 0) c->pseudo = CS_P_DISABLED;
    else if (nlen == 7 && strncasecmp(nm, "enabled", 7) == 0) c->pseudo = CS_P_ENABLED;
    else if (nlen == 9 && strncasecmp(nm, "nth-child", 9) == 0) c->pseudo = CS_P_NTH_CHILD;
    else if (nlen == 14 && strncasecmp(nm, "nth-last-child", 14) == 0) c->pseudo = CS_P_NTH_LAST_CHILD;
    else if (nlen == 12 && strncasecmp(nm, "nth-of-type", 12) == 0) c->pseudo = CS_P_NTH_OF_TYPE;
    else if (nlen == 3 && strncasecmp(nm, "not", 3) == 0) {
        if (p->i >= p->len || p->s[p->i] != '(') return false;
        p->i++;
        c->pseudo = CS_P_NOT;
        c->has_not = true;
        if (!sp_simple(p, &c->not)) return false;
        if (p->i >= p->len || p->s[p->i] != ')') return false;
        p->i++;
        return true;
    } else if (nlen == 6 && strncasecmp(nm, "before", 6) == 0) {
        c->pseudo_elem = nm; c->pseudo_elem_len = nlen;
        c->is_pseudo_elem = true;
        return true;
    } else if (nlen == 5 && strncasecmp(nm, "after", 5) == 0) {
        c->pseudo_elem = nm; c->pseudo_elem_len = nlen;
        c->is_pseudo_elem = true;
        return true;
    } else if (nlen == 10 && strncasecmp(nm, "first-line", 10) == 0) {
        c->pseudo_elem = nm; c->pseudo_elem_len = nlen;
        c->is_pseudo_elem = true;
        return true;
    } else if (nlen == 12 && strncasecmp(nm, "first-letter", 12) == 0) {
        c->pseudo_elem = nm; c->pseudo_elem_len = nlen;
        c->is_pseudo_elem = true;
        return true;
    } else if (nlen == 13 && strncasecmp(nm, "focus-visible", 13) == 0) c->pseudo = CS_P_FOCUS_VISIBLE;
    else if (nlen == 13 && strncasecmp(nm, "focus-within", 13) == 0) c->pseudo = CS_P_FOCUS_WITHIN;
    else if (nlen == 6 && strncasecmp(nm, "target", 6) == 0) c->pseudo = CS_P_TARGET;
    else if (nlen == 7 && strncasecmp(nm, "defined", 7) == 0) c->pseudo = CS_P_DEFINED;
    else if (nlen == 5 && strncasecmp(nm, "scope", 5) == 0) c->pseudo = CS_P_SCOPE;
    else if (nlen == 8 && strncasecmp(nm, "any-link", 8) == 0) c->pseudo = CS_P_ANY_LINK;
    else if (nlen == 4 && strncasecmp(nm, "open", 4) == 0) c->pseudo = CS_P_OPEN;
    else if (nlen == 5 && strncasecmp(nm, "modal", 5) == 0) c->pseudo = CS_P_MODAL;
    else if (nlen == 8 && strncasecmp(nm, "required", 8) == 0) c->pseudo = CS_P_REQUIRED;
    else if (nlen == 8 && strncasecmp(nm, "optional", 8) == 0) c->pseudo = CS_P_OPTIONAL;
    else if (nlen == 9 && strncasecmp(nm, "read-only", 9) == 0) c->pseudo = CS_P_READ_ONLY;
    else if (nlen == 10 && strncasecmp(nm, "read-write", 10) == 0) c->pseudo = CS_P_READ_WRITE;
    else if (nlen == 17 && strncasecmp(nm, "placeholder-shown", 17) == 0) c->pseudo = CS_P_PLACEHOLDER_SHOWN;
    else if (nlen == 5 && strncasecmp(nm, "valid", 5) == 0) c->pseudo = CS_P_VALID;
    else if (nlen == 7 && strncasecmp(nm, "invalid", 7) == 0) c->pseudo = CS_P_INVALID;
    else if (nlen == 10 && strncasecmp(nm, "user-valid", 10) == 0) c->pseudo = CS_P_USER_VALID;
    else if (nlen == 12 && strncasecmp(nm, "user-invalid", 12) == 0) c->pseudo = CS_P_USER_INVALID;
    else if (nlen == 8 && strncasecmp(nm, "in-range", 8) == 0) c->pseudo = CS_P_IN_RANGE;
    else if (nlen == 12 && strncasecmp(nm, "out-of-range", 12) == 0) c->pseudo = CS_P_OUT_OF_RANGE;
    else if (nlen == 13 && strncasecmp(nm, "indeterminate", 13) == 0) c->pseudo = CS_P_INDETERMINATE;
    else if (nlen == 7 && strncasecmp(nm, "default", 7) == 0) c->pseudo = CS_P_DEFAULT;
    else if (nlen == 7 && strncasecmp(nm, "autofill", 7) == 0) c->pseudo = CS_P_AUTOFILL;
    else if (nlen == 13 && strncasecmp(nm, "only-of-type", 13) == 0) c->pseudo = CS_P_ONLY_OF_TYPE;
    else if (nlen == 16 && strncasecmp(nm, "nth-last-of-type", 16) == 0) c->pseudo = CS_P_NTH_LAST_OF_TYPE;
    else if (nlen == 5 && strncasecmp(nm, "first", 5) == 0) c->pseudo = CS_P_FIRST;
    else if (nlen == 12 && strncasecmp(nm, "popover-open", 12) == 0) c->pseudo = CS_P_POPOVER_OPEN;
    else if (nlen == 7 && strncasecmp(nm, "heading", 7) == 0) c->pseudo = CS_P_HEADING;
    else if (nlen == 3 && strncasecmp(nm, "dir", 3) == 0) c->pseudo = CS_P_DIR;
    else if (nlen == 4 && strncasecmp(nm, "lang", 4) == 0) c->pseudo = CS_P_LANG;
    else {
        return false; /* unknown pseudo-class invalidates the selector */
    }
    if ((c->pseudo == CS_P_NTH_CHILD || c->pseudo == CS_P_NTH_LAST_CHILD ||
         c->pseudo == CS_P_NTH_OF_TYPE ||
         c->pseudo == CS_P_NTH_LAST_OF_TYPE) &&
        p->i < p->len && p->s[p->i] == '(') {
        p->i++;
        sp_ws(p);
        int a = 0, b = 0;
        const char* nm2;
        int n2;
        if (sp_ident(p, &nm2, &n2)) {
            if (n2 == 3 && strncasecmp(nm2, "odd", 3) == 0) {
                a = 2;
                b = 1;
            } else if (n2 == 4 && strncasecmp(nm2, "even", 4) == 0) {
                a = 2;
                b = 0;
            } else {
                return false;
            }
        } else {
            /* an+b: [ws] sign? digits? n? [ws] sign? digits?  |  plain integer */
            int sign = 1;
            if (p->i < p->len && (p->s[p->i] == '+' || p->s[p->i] == '-')) {
                sign = p->s[p->i] == '-' ? -1 : 1;
                p->i++;
            }
            int an = 0;
            bool has_digits = false;
            while (p->i < p->len && isdigit((unsigned char)p->s[p->i])) {
                an = an * 10 + (p->s[p->i] - '0');
                p->i++;
                has_digits = true;
            }
            bool has_n = p->i < p->len && (p->s[p->i] == 'n' || p->s[p->i] == 'N');
            if (has_n) {
                p->i++;
                a = sign * (has_digits ? an : 1);
                sp_ws(p);
                int bsign = 0;
                if (p->i < p->len && (p->s[p->i] == '+' || p->s[p->i] == '-')) {
                    bsign = p->s[p->i] == '-' ? -1 : 1;
                    p->i++;
                    sp_ws(p);
                }
                int bnum = 0, bd = 0;
                while (p->i < p->len && isdigit((unsigned char)p->s[p->i])) {
                    bnum = bnum * 10 + (p->s[p->i] - '0');
                    p->i++;
                    bd++;
                }
                if (bsign != 0 && bd > 0) b = bsign * bnum;
            } else {
                if (!has_digits) return false;
                b = sign * an;
            }
        }
        c->nth_a = a;
        c->nth_b = b;
        sp_ws(p);
        if (p->i >= p->len || p->s[p->i] != ')') return false;
        p->i++;
    }
    if (c->pseudo == CS_P_DIR || c->pseudo == CS_P_LANG) {
        if (p->i >= p->len || p->s[p->i] != '(') return false;
        p->i++;
        sp_ws(p);
        const char* an = NULL;
        int al = 0;
        if (!sp_ident(p, &an, &al)) return false;
        c->arg = an;
        c->arg_len = al;
        sp_ws(p);
        if (p->i >= p->len || p->s[p->i] != ')') return false;
        p->i++;
    }
    return true;
}

/* parse the simple part: (universal|type)? #id? .class* [attr]* */
static bool sp_simple(SelP* p, CsSimple* c) {
    memset(c, 0, sizeof(*c));
    bool any = false;
    if (p->i < p->len && p->s[p->i] == '*') {
        p->i++;
        any = true;
    } else {
        const char* nm;
        int nlen;
        int save = p->i;
        if (sp_ident(p, &nm, &nlen)) {
            if (p->i < p->len && p->s[p->i] == '(') {
                p->i = save; /* function in selector position = invalid */
                return false;
            }
            c->tag = nm;
            c->tag_len = nlen;
            any = true;
        }
    }
    for (;;) {
        if (p->i < p->len && p->s[p->i] == '#') {
            p->i++;
            const char* nm;
            int nlen;
            if (!sp_ident(p, &nm, &nlen)) return false;
            c->id = nm;
            c->id_len = nlen;
            any = true;
            continue;
        }
        if (p->i < p->len && p->s[p->i] == '.') {
            p->i++;
            const char* nm;
            int nlen;
            if (!sp_ident(p, &nm, &nlen)) return false;
            if (c->cls_count < CS_MAX_COMPOUND_CLS) {
                c->cls[c->cls_count] = nm;
                c->cls_len[c->cls_count] = nlen;
                c->cls_count++;
            }
            any = true;
            continue;
        }
        if (p->i < p->len && p->s[p->i] == '[') {
            p->i++;
            sp_ws(p);
            const char* nm;
            int nlen;
            if (!sp_ident(p, &nm, &nlen)) return false;
            sp_ws(p);
            CsAttrOp op = CS_ATTR_PRESENT;
            const char* val = NULL;
            int vlen = 0;
            bool case_i = false;
            if (p->i < p->len && p->s[p->i] != ']') {
                if (p->i + 1 < p->len && p->s[p->i + 1] == '=' &&
                    (p->s[p->i] == '~' || p->s[p->i] == '|' || p->s[p->i] == '^' ||
                     p->s[p->i] == '$' || p->s[p->i] == '*')) {
                    op = p->s[p->i] == '~'   ? CS_ATTR_INCLUDES
                         : p->s[p->i] == '|' ? CS_ATTR_DASH
                         : p->s[p->i] == '^' ? CS_ATTR_PREFIX
                         : p->s[p->i] == '$' ? CS_ATTR_SUFFIX
                                             : CS_ATTR_SUBSTR;
                    p->i += 2;
                } else if (p->i < p->len && p->s[p->i] == '=') {
                    op = CS_ATTR_EQ;
                    p->i++;
                } else {
                    return false;
                }
                sp_ws(p);
                if (p->i < p->len && (p->s[p->i] == '\'' || p->s[p->i] == '"')) {
                    char q = p->s[p->i++];
                    int v0 = p->i;
                    while (p->i < p->len && p->s[p->i] != q) p->i++;
                    val = p->s + v0;
                    vlen = p->i - v0;
                    if (p->i < p->len) p->i++;
                } else {
                    const char* vnm;
                    int vnlen;
                    if (!sp_ident(p, &vnm, &vnlen)) return false;
                    val = vnm;
                    vlen = vnlen;
                }
                sp_ws(p);
                if (p->i < p->len && (p->s[p->i] == 'i' || p->s[p->i] == 'I')) {
                    char after = p->i + 1 < p->len ? p->s[p->i + 1] : ']';
                    if (after == ']' || is_ws_c(after)) {
                        case_i = true;
                        p->i++;
                        sp_ws(p);
                    }
                }
            }
            if (p->i >= p->len || p->s[p->i] != ']') return false;
            p->i++;
            if (c->attr_count < CS_MAX_COMPOUND_ATTRS) {
                CsAttrSel* a = &c->attrs[c->attr_count++];
                a->name = nm;
                a->name_len = nlen;
                a->val = val;
                a->val_len = vlen;
                a->op = op;
                a->case_i = case_i;
            }
            any = true;
            continue;
        }
        break;
    }
    return any;
}

static bool sp_compound(SelP* p, CsCompound* c) {
    memset(c, 0, sizeof(*c));
    int start = p->i;
    bool any = sp_simple(p, &c->s);
    /* a compound may be pseudo-only (:root, :hover...); a simple that
       consumed input and failed is a real syntax error */
    if (!any && p->i != start) return false;
    for (;;) {
        if (p->i < p->len && p->s[p->i] == ':') {
            if (c->pseudo != CS_P_NONE && !c->has_not) {
                /* a pseudo-element may follow a pseudo-class (:hover::after);
                   a second pseudo-class is invalid */
                if (!(p->i + 1 < p->len && p->s[p->i + 1] == ':')) return false;
            }
            if (!sp_pseudo(p, c)) return false;
            any = true;
            if (c->is_pseudo_elem) return any; /* pseudo-element ends compound */
            continue;
        }
        break;
    }
    return any;
}

bool cs_parse_selector(const char* sel, int len, CsGroup* out) {
    memset(out, 0, sizeof(*out));
    if (len < 0) len = (int)strlen(sel);
    SelP p = {sel, len, 0};
    while (out->count < CS_MAX_GROUP) {
        sp_ws(&p);
        if (p.i >= p.len) break;
        CsComplex* cx = &out->items[out->count];
        memset(cx, 0, sizeof(*cx));
        if (!sp_compound(&p, &cx->parts[0])) return false;
        cx->count = 1;
        for (;;) {
            sp_ws(&p);
            char comb = ' ';
            if (p.i < p.len &&
                (p.s[p.i] == '>' || p.s[p.i] == '+' || p.s[p.i] == '~')) {
                comb = p.s[p.i++];
                sp_ws(&p);
            }
            if (p.i >= p.len || p.s[p.i] == ',') break;
            if (cx->parts[cx->count - 1].is_pseudo_elem)
                return false; /* a pseudo-element must be last */
            if (cx->count == CS_MAX_CHAIN) return false;
            if (!sp_compound(&p, &cx->parts[cx->count])) return false;
            cx->comb[cx->count - 1] = comb;
            cx->count++;
        }
        for (int i = 0; i < cx->count; i++) {
            CsCompound* c = &cx->parts[i];
            if (c->s.id_len > 0) cx->spec[0]++;
            cx->spec[1] += c->s.cls_count + c->s.attr_count;
            /* :not() itself contributes nothing (Selectors 4) */
            if (c->pseudo != CS_P_NONE && c->pseudo != CS_P_NOT) cx->spec[1]++;
            if (c->s.tag_len > 0) cx->spec[2]++;
            if (c->has_not) {
                if (c->not.id_len > 0) cx->spec[0]++;
                cx->spec[1] += c->not.cls_count + c->not.attr_count;
                if (c->not.tag_len > 0) cx->spec[2]++;
            }
        }
        out->count++;
        sp_ws(&p);
        if (p.i < p.len && p.s[p.i] == ',') {
            p.i++;
            continue;
        }
        if (p.i < p.len) return false; /* trailing garbage */
        break;
    }
    sp_ws(&p);
    return p.i >= p.len && out->count > 0;
}

/* ------------------------------------------------------------------ */
/* stylesheet parser                                                  */
/* ------------------------------------------------------------------ */

typedef struct PP {
    CsTokens* toks;
    int i;
    CsSheet* sh;
} PP;

static CsTok* pk(PP* p) { return &p->toks->toks[p->i]; }

static void p_ws(PP* p) {
    while (pk(p)->kind != CS_EOF && pk(p)->kind == CS_WS) p->i++;
}

/* collect raw source text for a token range (media conditions) */
static char* range_text(const char* src, int start_tok, int end_tok, CsTokens* toks) {
    int a = toks->toks[start_tok].pos;
    int b = end_tok < toks->count ? toks->toks[end_tok].pos : (int)strlen(src);
    if (b <= a) return strdup("");
    char* out = malloc((size_t)(b - a) + 1);
    memcpy(out, src + a, (size_t)(b - a));
    out[b - a] = '\0';
    return out;
}

static void p_skip_block(PP* p) {
    /* current token is LBRACE: consume through its matching RBRACE */
    int depth = 0;
    while (pk(p)->kind != CS_EOF) {
        CsTokKind k = pk(p)->kind;
        p->i++;
        if (k == CS_LBRACE) depth++;
        if (k == CS_RBRACE && --depth == 0) return;
    }
}

static void p_declarations(PP* p, CsRule* rule) {
    p->i++; /* past LBRACE */
    for (;;) {
        p_ws(p);
        if (pk(p)->kind == CS_EOF) return;
        if (pk(p)->kind == CS_RBRACE) {
            p->i++;
            return;
        }
        if (pk(p)->kind == CS_SEMI) {
            p->i++;
            continue;
        }
        if (pk(p)->kind != CS_IDENT) {
            p->sh->dropped_decls++;
            while (pk(p)->kind != CS_EOF && pk(p)->kind != CS_SEMI &&
                   pk(p)->kind != CS_RBRACE) {
                p->i++;
            }
            continue;
        }
        int name_tok = p->i;
        p->i++;
        p_ws(p);
        if (pk(p)->kind != CS_COLON) {
            p->sh->dropped_decls++;
            while (pk(p)->kind != CS_EOF && pk(p)->kind != CS_SEMI &&
                   pk(p)->kind != CS_RBRACE) {
                p->i++;
            }
            continue;
        }
        p->i++; /* colon */
        int val_start = p->i;
        int depth = 0;
        while (pk(p)->kind != CS_EOF) {
            CsTokKind k = pk(p)->kind;
            if ((k == CS_SEMI || k == CS_RBRACE) && depth == 0) break;
            if (k == CS_LPAREN || k == CS_FUNCTION) depth++;
            if (k == CS_RPAREN && depth > 0) depth--;
            p->i++;
        }
        int val_end = p->i;
        if (pk(p)->kind == CS_SEMI) p->i++;
        while (val_start < val_end && p->toks->toks[val_start].kind == CS_WS)
            val_start++;
        while (val_end > val_start && p->toks->toks[val_end - 1].kind == CS_WS)
            val_end--;
        bool important = false;
        {
            int ve2 = val_end;
            while (ve2 > val_start && p->toks->toks[ve2 - 1].kind == CS_WS) ve2--;
            if (ve2 > val_start && p->toks->toks[ve2 - 1].kind == CS_IDENT &&
                p->toks->toks[ve2 - 1].len == 9 &&
                strncasecmp(p->toks->toks[ve2 - 1].str, "important", 9) == 0) {
                ve2--;
                while (ve2 > val_start && p->toks->toks[ve2 - 1].kind == CS_WS) ve2--;
                if (ve2 > val_start && p->toks->toks[ve2 - 1].kind == CS_DELIM &&
                    p->toks->toks[ve2 - 1].s[0] == '!') {
                    important = true;
                    val_end = ve2 - 1;
                    while (val_end > val_start &&
                           p->toks->toks[val_end - 1].kind == CS_WS) {
                        val_end--;
                    }
                }
            }
        }
        if (val_end == val_start) {
            p->sh->dropped_decls++;
            continue;
        }
        rule->decls = realloc(rule->decls, sizeof(CsDecl) * (size_t)(rule->decl_count + 1));
        CsDecl* nd = &rule->decls[rule->decl_count++];
        CsTok* nt = &p->toks->toks[name_tok];
        nd->name = nt->str;
        nd->name_len = (int)strlen(nt->str);
        nd->toks = &p->toks->toks[val_start];
        nd->ntoks = val_end - val_start;
        nd->important = important;
    }
}

static void p_qualified(PP* p, const char* src, const char* media) {
    int prelude_start = p->i;
    int depth = 0;
    while (pk(p)->kind != CS_EOF) {
        CsTokKind k = pk(p)->kind;
        if (k == CS_LBRACE && depth == 0) break;
        if (k == CS_SEMI && depth == 0) {
            p->sh->dropped_rules++; /* qualified rule without block */
            p->i++;
            return;
        }
        if (k == CS_LPAREN || k == CS_FUNCTION) depth++;
        if (k == CS_RPAREN && depth > 0) depth--;
        p->i++;
    }
    if (pk(p)->kind != CS_LBRACE) {
        p->sh->dropped_rules++;
        return;
    }
    int prelude_end = p->i;
    int a = p->toks->toks[prelude_start].pos;
    int b = p->toks->toks[prelude_end].pos;
    while (a < b && is_ws_c(src[a])) a++;
    while (b > a && is_ws_c(src[b - 1])) b--;
    CsGroup grp;
    bool ok = b > a && cs_parse_selector(src + a, b - a, &grp);
    if (!ok) {
        p->sh->dropped_rules++;
        p_skip_block(p);
        return;
    }
    CsRule rule;
    memset(&rule, 0, sizeof(rule));
    rule.sel = grp;
    rule.media = media ? strdup(media) : NULL;
    for (int gi = 0; gi < grp.count; gi++) {
        for (int pi = 0; pi < grp.items[gi].count; pi++) {
            if (grp.items[gi].parts[pi].is_pseudo_elem) rule.is_pseudo_element = true;
        }
    }
    p_declarations(p, &rule);
    if (rule.decl_count == 0) {
        free(rule.media);
        return;
    }
    if (p->sh->rule_count == p->sh->rule_cap) {
        p->sh->rule_cap = p->sh->rule_cap ? p->sh->rule_cap * 2 : 32;
        p->sh->rules = realloc(p->sh->rules, (size_t)p->sh->rule_cap * sizeof(CsRule));
    }
    rule.order = p->sh->rule_count;
    p->sh->rules[p->sh->rule_count++] = rule;
}

static void p_skip_nested_at(PP* p);

static void p_at_rule(PP* p, const char* src) {
    CsTok* t = pk(p);
    char name[32];
    int copy = t->len > 31 ? 31 : t->len;
    for (int k = 0; k < copy; k++) name[k] = lower_c(t->s[k]);
    name[copy] = '\0';
    p->i++;
    bool is_media = strcmp(name, "media") == 0;
    bool is_ff = strcmp(name, "font-face") == 0;
    int prelude_tok = p->i; /* first token after the at-keyword */
    while (pk(p)->kind != CS_EOF && pk(p)->kind != CS_LBRACE &&
           pk(p)->kind != CS_SEMI) {
        p->i++;
    }
    if (pk(p)->kind == CS_SEMI) {
        p->i++; /* statement at-rule (@import/@charset) skipped (documented) */
        return;
    }
    if (pk(p)->kind != CS_LBRACE) return; /* EOF */
    if (!is_media && !is_ff) {
        p_skip_block(p);
        return;
    }
    if (is_media) {
        /* condition text: token range [prelude_tok .. brace) trimmed */
        int brace = p->i;
        int pe = brace;
        while (pe > prelude_tok && p->toks->toks[pe - 1].kind == CS_WS) pe--;
        int ps = prelude_tok;
        while (ps < pe && p->toks->toks[ps].kind == CS_WS) ps++;
        char* cond = range_text(src, ps < pe ? ps : pe, pe, p->toks);
        p->i++; /* past { */
        for (;;) {
            p_ws(p);
            if (pk(p)->kind == CS_EOF) break;
            if (pk(p)->kind == CS_RBRACE) {
                p->i++;
                break;
            }
            if (pk(p)->kind == CS_AT_KEYWORD) {
                /* nested @media flattens; other at-rules are skipped */
                CsTok* nt = pk(p);
                if (nt->len == 5 && strncasecmp(nt->s, "media", 5) == 0) {
                    p_at_rule(p, src);
                } else {
                    p_skip_nested_at(p);
                }
                continue;
            }
            p_qualified(p, src, cond);
        }
        free(cond);
        return;
    }
    /* @font-face: record family + src url */
    p->i++; /* past { */
    for (;;) {
        p_ws(p);
        if (pk(p)->kind == CS_EOF) return;
        if (pk(p)->kind == CS_RBRACE) {
            p->i++;
            return;
        }
        if (pk(p)->kind != CS_IDENT) {
            while (pk(p)->kind != CS_EOF && pk(p)->kind != CS_SEMI &&
                   pk(p)->kind != CS_RBRACE) {
                p->i++;
            }
            continue;
        }
        int nt = p->i;
        p->i++;
        p_ws(p);
        if (pk(p)->kind != CS_COLON) {
            while (pk(p)->kind != CS_EOF && pk(p)->kind != CS_SEMI &&
                   pk(p)->kind != CS_RBRACE) {
                p->i++;
            }
            continue;
        }
        p->i++;
        int vs = p->i;
        while (pk(p)->kind != CS_EOF && pk(p)->kind != CS_SEMI &&
               pk(p)->kind != CS_RBRACE) {
            p->i++;
        }
        int ve = p->i;
        if (pk(p)->kind == CS_SEMI) p->i++;
        while (vs < ve && p->toks->toks[vs].kind == CS_WS) vs++;
        CsTok* nt_tok = &p->toks->toks[nt];
        if (nt_tok->len == 11 && strncasecmp(nt_tok->str, "font-family", 11) == 0 &&
            ve > vs) {
            CsTok* v = &p->toks->toks[vs];
            if (v->kind == CS_STRING || v->kind == CS_IDENT) {
                free(p->sh->font_family);
                p->sh->font_family = strdup(v->str ? v->str : v->s);
            }
        }
        if (nt_tok->len == 3 && strncasecmp(nt_tok->str, "src", 3) == 0) {
            for (int k = vs; k < ve; k++) {
                if (p->toks->toks[k].kind == CS_URL) {
                    free(p->sh->font_url);
                    p->sh->font_url = strdup(p->toks->toks[k].str);
                    break;
                }
            }
        }
    }
}

/* skip a nested at-rule (own prelude + optional block) — @supports/@keyframes
   inside @media etc. */
static void p_skip_nested_at(PP* p) {
    p->i++; /* at-keyword */
    while (pk(p)->kind != CS_EOF && pk(p)->kind != CS_LBRACE &&
           pk(p)->kind != CS_SEMI) {
        p->i++;
    }
    if (pk(p)->kind == CS_SEMI) {
        p->i++;
        return;
    }
    if (pk(p)->kind == CS_LBRACE) p_skip_block(p);
}

CsSheet* cs_sheet_parse(const char* css, int len) {
    CsSheet* sh = calloc(1, sizeof(CsSheet));
    if (len < 0) len = (int)strlen(css);
    /* own a copy: selectors/decls keep slices into it */
    sh->src = malloc((size_t)len + 1);
    memcpy(sh->src, css, (size_t)len);
    sh->src[len] = '\0';
    cs_tokenize(sh->src, len, &sh->toks);
    PP p = {&sh->toks, 0, sh};
    for (;;) {
        p_ws(&p);
        CsTok* t = pk(&p);
        if (t->kind == CS_EOF) break;
        if (t->kind == CS_CDO || t->kind == CS_CDC) {
            p.i++;
            continue;
        }
        if (t->kind == CS_RBRACE) {
            p.i++; /* stray close: skip */
            continue;
        }
        if (t->kind == CS_AT_KEYWORD) {
            p_at_rule(&p, sh->src);
            continue;
        }
        p_qualified(&p, sh->src, NULL);
    }
    return sh;
}

void cs_sheet_free(CsSheet* sh) {
    if (!sh) return;
    for (int i = 0; i < sh->rule_count; i++) {
        free(sh->rules[i].decls);
        free(sh->rules[i].media);
    }
    free(sh->rules);
    cs_tokens_free(&sh->toks);
    free(sh->src);
    free(sh->font_family);
    free(sh->font_url);
    free(sh);
}

/* ------------------------------------------------------------------ */
/* media conditions                                                   */
/* ------------------------------------------------------------------ */

typedef struct MP {
    const char* s;
    int len;
    int i;
} MP;

static void mp_ws(MP* p) {
    while (p->i < p->len && is_ws_c(p->s[p->i])) p->i++;
}

static bool mp_lit(MP* p, const char* lit) {
    mp_ws(p);
    int n = (int)strlen(lit);
    if (p->i + n <= p->len && strncasecmp(p->s + p->i, lit, (size_t)n) == 0) {
        char after = p->i + n < p->len ? p->s[p->i + n] : ' ';
        if (!isalnum((unsigned char)after) && after != '-') {
            p->i += n;
            return true;
        }
    }
    return false;
}

static bool mp_length(MP* p, float* out) {
    mp_ws(p);
    int s0 = p->i;
    if (p->i < p->len && (p->s[p->i] == '+' || p->s[p->i] == '-')) p->i++;
    bool digits = false;
    while (p->i < p->len && (isdigit((unsigned char)p->s[p->i]) || p->s[p->i] == '.')) {
        p->i++;
        digits = true;
    }
    if (!digits) {
        p->i = s0;
        return false;
    }
    double v = strtod(p->s + s0, NULL);
    int u0 = p->i;
    while (p->i < p->len && isalpha((unsigned char)p->s[p->i])) p->i++;
    int ulen = p->i - u0;
    char unit[8] = "";
    if (ulen > 0) {
        if (ulen > 7) ulen = 7;
        for (int k = 0; k < ulen; k++) unit[k] = lower_c(p->s[u0 + k]);
    }
    float px;
    if (ulen == 0 || strcmp(unit, "px") == 0) px = (float)v;
    else if (strcmp(unit, "em") == 0 || strcmp(unit, "rem") == 0) px = (float)v * 16.f;
    else if (strcmp(unit, "in") == 0) px = (float)v * 96.f;
    else if (strcmp(unit, "cm") == 0) px = (float)(v * 96.0 / 2.54);
    else if (strcmp(unit, "mm") == 0) px = (float)(v * 96.0 / 25.4);
    else if (strcmp(unit, "pt") == 0) px = (float)(v * 96.0 / 72.0);
    else if (strcmp(unit, "pc") == 0) px = (float)(v * 16.0);
    else if (strcmp(unit, "q") == 0) px = (float)(v * 96.0 / 101.6);
    else {
        p->i = s0;
        return false;
    }
    *out = px;
    return true;
}

static bool mp_clause(MP* p, const CsMediaState* st) {
    mp_ws(p);
    int s0 = p->i;
    while (p->i < p->len &&
           (isalnum((unsigned char)p->s[p->i]) || p->s[p->i] == '-')) {
        p->i++;
    }
    int nlen = p->i - s0;
    char feat[64];
    if (nlen == 0 || nlen > 63) return false;
    for (int k = 0; k < nlen; k++) feat[k] = lower_c(p->s[s0 + k]);
    feat[nlen] = '\0';
    mp_ws(p);
    if (p->i >= p->len || p->s[p->i] != ':') return false;
    p->i++;
    if (strcmp(feat, "orientation") == 0) {
        mp_ws(p);
        char v[32] = "";
        int vi = 0;
        while (p->i < p->len && isalpha((unsigned char)p->s[p->i]) && vi < 31) {
            v[vi++] = lower_c(p->s[p->i++]);
        }
        v[vi] = '\0';
        bool portrait = st->height >= st->width;
        if (strcmp(v, "portrait") == 0) return portrait;
        if (strcmp(v, "landscape") == 0) return !portrait;
        return false;
    }
    bool is_w = strstr(feat, "width") != NULL;
    bool is_h = strstr(feat, "height") != NULL;
    if (!is_w && !is_h) return false; /* unknown feature -> clause false */
    float vp = is_w ? st->width : st->height;
    float want;
    if (!mp_length(p, &want)) return false;
    if (strncmp(feat, "min-", 4) == 0) return vp >= want - 0.01f;
    if (strncmp(feat, "max-", 4) == 0) return vp <= want + 0.01f;
    return fabsf(vp - want) < 0.01f;
}

static bool mp_primary(MP* p, const CsMediaState* st) {
    mp_ws(p);
    if (p->i < p->len && p->s[p->i] == '(') {
        p->i++;
        bool ok = mp_clause(p, st);
        mp_ws(p);
        if (p->i < p->len && p->s[p->i] == ')') p->i++;
        return ok;
    }
    if (mp_lit(p, "all")) return true;
    if (mp_lit(p, "screen")) return !st->print;
    if (mp_lit(p, "print")) return st->print;
    if (mp_lit(p, "speech")) return false;
    return false;
}

static bool mp_not(MP* p, const CsMediaState* st) {
    if (mp_lit(p, "not")) return !mp_primary(p, st);
    return mp_primary(p, st);
}

static bool mp_and(MP* p, const CsMediaState* st) {
    bool v = mp_not(p, st);
    while (mp_lit(p, "and")) {
        bool rhs = mp_not(p, st);
        v = v && rhs;
    }
    return v;
}

bool cs_media_matches(const char* cond, const CsMediaState* st) {
    if (!cond || !*cond) return true;
    MP p = {cond, (int)strlen(cond), 0};
    bool v = mp_and(&p, st);
    while (mp_lit(&p, "or")) {
        bool rhs = mp_and(&p, st);
        v = v || rhs;
    }
    mp_ws(&p);
    return v && p.i >= p.len;
}




/* ---- standalone declaration lists ---------------------------------------- */

CsDeclList* cs_decls_parse(const char* text, int len) {
    if (!text || len <= 0) return NULL;
    CsDeclList* list = (CsDeclList*)calloc(1, sizeof(*list));
    if (!list) return NULL;
    list->src = (char*)malloc((size_t)len + 1);
    if (!list->src) {
        free(list);
        return NULL;
    }
    memcpy(list->src, text, (size_t)len);
    list->src[len] = '\0';
    if (!cs_tokenize(list->src, len, &list->toks)) {
        free(list->src);
        free(list);
        return NULL;
    }

    int i = 0;
    int n = list->toks.count;
    while (i < n) {
        CsTokKind k = list->toks.toks[i].kind;
        if (k == CS_WS || k == CS_SEMI) {
            i++;
            continue;
        }
        if (k != CS_IDENT) {
            i++; /* unrecoverable token: skip it (error recovery) */
            continue;
        }
        int name_tok = i++;
        while (i < n && list->toks.toks[i].kind == CS_WS) i++;
        if (i >= n || list->toks.toks[i].kind != CS_COLON) continue;
        i++; /* ':' */
        int val_start = i;
        int val_end = i;
        int depth = 0;
        while (i < n) {
            CsTokKind vk = list->toks.toks[i].kind;
            if (vk == CS_SEMI && depth == 0) break;
            if (vk == CS_LPAREN || vk == CS_FUNCTION) depth++;
            else if (vk == CS_RPAREN && depth > 0) depth--;
            i++;
            val_end = i;
        }
        if (i < n && list->toks.toks[i].kind == CS_SEMI) i++; /* consume ';' */

        while (val_start < val_end && list->toks.toks[val_start].kind == CS_WS) val_start++;
        while (val_end > val_start && list->toks.toks[val_end - 1].kind == CS_WS) val_end--;

        /* trailing "!important" belongs to the declaration, not the value */
        bool important = false;
        if (val_end - val_start >= 2) {
            const CsTok* last = &list->toks.toks[val_end - 1];
            const CsTok* bang = &list->toks.toks[val_end - 2];
            if (last->kind == CS_IDENT && cs_is_ident(last, "important") &&
                bang->kind == CS_DELIM && bang->len == 1 && bang->s && bang->s[0] == '!') {
                important = true;
                val_end -= 2;
                while (val_end > val_start && list->toks.toks[val_end - 1].kind == CS_WS) val_end--;
            }
        }
        if (val_end == val_start) continue;

        if (list->count == list->cap) {
            int nc = list->cap ? list->cap * 2 : 8;
            CsDecl* nd = (CsDecl*)realloc(list->decls, (size_t)nc * sizeof(CsDecl));
            if (!nd) break;
            list->decls = nd;
            list->cap = nc;
        }
        CsTok* nt = &list->toks.toks[name_tok];
        CsDecl* nd = &list->decls[list->count++];
        nd->name = nt->str;
        nd->name_len = (int)strlen(nt->str);
        nd->toks = &list->toks.toks[val_start];
        nd->ntoks = val_end - val_start;
        nd->important = important;
    }
    return list;
}

void cs_decls_free(CsDeclList* list) {
    if (!list) return;
    cs_tokens_free(&list->toks);
    free(list->src);
    free(list->decls);
    free(list);
}
