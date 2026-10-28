#ifndef NATIVAX_CSS_H
#define NATIVAX_CSS_H

/*
    CSS tokenizer + stylesheet parser (CSS Syntax Level 3 subset).

    Produces a token array per stylesheet, then rules: qualified rules with
    parsed selectors + declarations, @media flattened into rules carrying a
    condition string (evaluated against the viewport at cascade time).
    At-rules other than @media are skipped with their blocks (@font-face
    family/url recorded for future use). Error recovery: invalid selectors
    drop the whole rule; invalid declarations are dropped individually.

    Documented v1 gaps: no @supports/@import/@keyframes/@page, no nesting,
    attribute selectors limited to the matcher subset in style.h.
*/

#include <stdbool.h>

/* ---- tokens ---- */
typedef enum CsTokKind {
    CS_EOF = 0,
    CS_WS,
    CS_IDENT,
    CS_FUNCTION,   /* ident followed by ( */
    CS_AT_KEYWORD, /* @name */
    CS_HASH,       /* #name or #abc (unquoted color) */
    CS_STRING,     /* decoded content in tok.str */
    CS_URL,        /* url(unquoted) decoded into tok.str */
    CS_BAD_URL,
    CS_BAD_STRING,
    CS_NUMBER,
    CS_PERCENTAGE,
    CS_DIMENSION, /* num + unit (tok.s/len = unit) */
    CS_DELIM,     /* single char */
    CS_LBRACE,
    CS_RBRACE,
    CS_LBRACKET,
    CS_RBRACKET,
    CS_LPAREN,
    CS_RPAREN,
    CS_COLON,
    CS_SEMI,
    CS_COMMA,
    CS_CDO, /* <!-- */
    CS_CDC, /* --> */
} CsTokKind;

typedef struct CsTok {
    CsTokKind kind;
    const char* s; /* slice into source for ident/hash/delim/number text */
    int len;
    double num; /* number/percentage/dimension value */
    char* str;  /* decoded string/url content, owned by the token list */
    int pos;    /* source offset (diagnostics) */
} CsTok;

typedef struct CsTokens {
    CsTok* toks;
    int count, cap;
    char** strs; /* owned decoded strings for freeing */
    int str_count, str_cap;
} CsTokens;

bool cs_tokenize(const char* css, int len, CsTokens* out);
void cs_tokens_free(CsTokens* t);

/* ---- declarations ---- */
typedef struct CsDecl {
    const char* name; /* lowercased name (stylesheet lives long) */
    int name_len;
    CsTok* toks; /* value tokens (points into CsTokens storage) */
    int ntoks;
    bool important;
} CsDecl;

/* ---- selectors ---- */
typedef enum CsAttrOp {
    CS_ATTR_PRESENT = 0,
    CS_ATTR_EQ,
    CS_ATTR_INCLUDES, /* ~= */
    CS_ATTR_DASH,     /* |= */
    CS_ATTR_PREFIX,   /* ^= */
    CS_ATTR_SUFFIX,   /* $= */
    CS_ATTR_SUBSTR,   /* *= */
} CsAttrOp;

typedef struct CsAttrSel {
    const char* name;
    int name_len;
    const char* val;
    int val_len;
    CsAttrOp op;
    bool case_i;
} CsAttrSel;

typedef enum CsPseudo {
    CS_P_NONE = 0,
    CS_P_ROOT,
    CS_P_HOVER,
    CS_P_FOCUS,
    CS_P_ACTIVE,
    CS_P_LINK,
    CS_P_VISITED,
    CS_P_FIRST_CHILD,
    CS_P_LAST_CHILD,
    CS_P_ONLY_CHILD,
    CS_P_FIRST_OF_TYPE,
    CS_P_LAST_OF_TYPE,
    CS_P_NTH_CHILD,
    CS_P_NTH_LAST_CHILD,
    CS_P_NTH_OF_TYPE,
    CS_P_EMPTY,
    CS_P_CHECKED,
    CS_P_DISABLED,
    CS_P_ENABLED,
    CS_P_NOT,
    /* reference parity (PseudoClassSelector.supported, selectors.dart) */
    CS_P_FOCUS_VISIBLE, CS_P_FOCUS_WITHIN, CS_P_TARGET, CS_P_DEFINED,
    CS_P_SCOPE, CS_P_ANY_LINK, CS_P_OPEN, CS_P_MODAL, CS_P_REQUIRED,
    CS_P_OPTIONAL, CS_P_READ_ONLY, CS_P_READ_WRITE, CS_P_PLACEHOLDER_SHOWN,
    CS_P_VALID, CS_P_INVALID, CS_P_USER_VALID, CS_P_USER_INVALID,
    CS_P_IN_RANGE, CS_P_OUT_OF_RANGE, CS_P_INDETERMINATE, CS_P_DEFAULT,
    CS_P_AUTOFILL, CS_P_ONLY_OF_TYPE, CS_P_NTH_LAST_OF_TYPE, CS_P_FIRST,
    CS_P_POPOVER_OPEN, CS_P_HEADING, CS_P_DIR, CS_P_LANG
} CsPseudo;

#define CS_MAX_COMPOUND_ATTRS 8
#define CS_MAX_COMPOUND_CLS 8

/* simple selector part: type + #id + .classes + [attrs] (no combinators) */
typedef struct CsSimple {
    const char* tag; /* NULL = any */
    int tag_len;
    const char* id;
    int id_len;
    const char* cls[CS_MAX_COMPOUND_CLS];
    int cls_len[CS_MAX_COMPOUND_CLS];
    int cls_count;
    CsAttrSel attrs[CS_MAX_COMPOUND_ATTRS];
    int attr_count;
} CsSimple;

typedef struct CsCompound {
    CsSimple s;
    CsPseudo pseudo;
    int nth_a, nth_b; /* for nth-* (an+b); odd=2n+1 even=2n */
    bool is_pseudo_elem;    /* ::x / CSS2 single-colon aliases — skipped
                               by cascade v1 */
    const char* pseudo_elem; /* slice: "before", "after", "backdrop"... */
    int pseudo_elem_len;
    /* :dir(x) / :lang(x) argument (slice, no parens) */
    const char* arg;
    int arg_len;
    /* :not(...) — one simple selector, no nesting (documented) */
    bool has_not;
    CsSimple not;
} CsCompound;

#define CS_MAX_CHAIN 8
#define CS_MAX_GROUP 16

typedef struct CsComplex {
    CsCompound parts[CS_MAX_CHAIN];
    /* comb[i] joins parts[i] and parts[i+1]: ' ' descendant, '>' child,
       '+' adjacent sibling, '~' general sibling */
    char comb[CS_MAX_CHAIN - 1];
    int count;
    int spec[3]; /* specificity a,b,c */
} CsComplex;

typedef struct CsGroup {
    CsComplex items[CS_MAX_GROUP];
    int count;
} CsGroup;

bool cs_parse_selector(const char* sel, int len, CsGroup* out); /* false = invalid */

/* ---- rules & sheet ---- */
typedef struct CsRule {
    CsGroup sel;
    CsDecl* decls;
    int decl_count;
    char* media; /* condition text (owned) or NULL */
    int order;
    bool is_pseudo_element; /* ::before/::after — skipped by cascade v1 */
} CsRule;

typedef struct CsSheet {
    CsRule* rules;
    int rule_count, rule_cap;
    CsTokens toks; /* owns string storage referenced by decls/selectors */
    char* src;     /* owned copy of the stylesheet text; selector/decl
                      slices point here, so the caller's buffer may be
                      freed right after parsing */
    /* stats for tests/diagnostics */
    int dropped_rules;
    int dropped_decls;
    int unknown_decls;
    /* @font-face family/url (single record, v1) */
    char* font_family;
    char* font_url;
} CsSheet;

CsSheet* cs_sheet_parse(const char* css, int len);
void cs_sheet_free(CsSheet* sh);

/* ---- media conditions ---- */
typedef struct CsMediaState {
    float width, height; /* viewport px */
    bool print;
} CsMediaState;

/* Evaluate a stored @media condition text against the state.
   Supports: all/screen/print, not, and, or, parens, (min|max)-(width|height)
   and (orientation: portrait|landscape). Unknown features make the clause
   false (documented). */
bool cs_media_matches(const char* cond, const CsMediaState* st);

/* ---- standalone declaration lists (style="" attributes, script writes) ----
   Parses the contents of a declaration block without the surrounding braces.
   Declarations reference token storage owned by the list; free the whole list
   with cs_decls_free(). NULL when the input cannot be tokenized. */
typedef struct CsDeclList {
    CsDecl* decls;
    int count, cap;
    CsTokens toks;
    char* src; /* owned copy the token slices point into */
} CsDeclList;

CsDeclList* cs_decls_parse(const char* text, int len);
void cs_decls_free(CsDeclList* list);

/* ---- value helpers (shared with style.c) ---- */
bool cs_parse_number(const CsTok* t, double* out);
bool cs_is_ident(const CsTok* t, const char* lit); /* case-insensitive ident match */

#endif /* NATIVAX_CSS_H */
