/*
    CSS tokenizer / selector / stylesheet / media tests.

    Ports the structural cases from the V1 CSS test suite
    (tokenizer, parser, invalid-selector recovery, @media/@font-face,
    !important, unbalanced braces) plus selector-parser unit checks and the
    media evaluator. Value conversion and the cascade live in style.c and
    are covered by test_style.c.
*/
#include "nativax/css.h"

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

/* ------------------------------------------------------------------ */
/* tokenizer                                                           */
/* ------------------------------------------------------------------ */

static void test_tokenizer_tokens(void) {
    /* V1 case: a.b #c{w:1.5em 50% -2px url(x.png) "s"q"} then a comment */
    const char* css = "a.b #c{w:1.5em 50% -2px url(x.png) \"s\\\"q\"}/*c*/";
    CsTokens t;
    CHECK(cs_tokenize(css, -1, &t), "tokenize ok");
    /* expected non-ws sequence */
    struct {
        CsTokKind kind;
        const char* text; /* ident/hash/url/string content when applicable */
        double num;
    } exp[] = {
        {CS_IDENT, "a", 0},        {CS_DELIM, ".", 0},        {CS_IDENT, "b", 0},
        {CS_HASH, "c", 0},         {CS_LBRACE, NULL, 0},      {CS_IDENT, "w", 0},
        {CS_COLON, NULL, 0},       {CS_DIMENSION, "em", 1.5}, {CS_PERCENTAGE, NULL, 50},
        {CS_DIMENSION, "px", -2},  {CS_URL, "x.png", 0},      {CS_STRING, "s\"q", 0},
        {CS_RBRACE, NULL, 0},
    };
    int ei = 0;
    for (int i = 0; i < t.count && ei < (int)(sizeof(exp) / sizeof(exp[0])); i++) {
        if (t.toks[i].kind == CS_WS) continue;
        const CsTok* tk = &t.toks[i];
        if (tk->kind == CS_EOF) break;
        CHECK(tk->kind == exp[ei].kind, "tok %d kind %d want %d", ei, tk->kind,
              exp[ei].kind);
        if (tk->kind == exp[ei].kind) {
            if (exp[ei].text) {
                if (tk->kind == CS_DIMENSION) {
                    CHECK(tk->len == (int)strlen(exp[ei].text) &&
                              strncmp(tk->s, exp[ei].text, (size_t)tk->len) == 0,
                          "tok %d unit '%.*s' want '%s'", ei, tk->len, tk->s,
                          exp[ei].text);
                } else if (tk->str) {
                    CHECK(strcmp(tk->str, exp[ei].text) == 0,
                          "tok %d text '%s' want '%s'", ei, tk->str, exp[ei].text);
                } else {
                    /* slices into source are not NUL-terminated */
                    CHECK(tk->len == (int)strlen(exp[ei].text) &&
                              strncmp(tk->s, exp[ei].text, (size_t)tk->len) == 0,
                          "tok %d text '%.*s' want '%s'", ei, tk->len, tk->s,
                          exp[ei].text);
                }
            }
            if (exp[ei].num != 0 || tk->kind == CS_DIMENSION ||
                tk->kind == CS_PERCENTAGE) {
                CHECK(fabs(tk->num - exp[ei].num) < 1e-9, "tok %d num %g want %g", ei,
                      tk->num, exp[ei].num);
            }
        }
        ei++;
    }
    CHECK(ei == (int)(sizeof(exp) / sizeof(exp[0])), "token count %d want %zu", ei,
          sizeof(exp) / sizeof(exp[0]));
    cs_tokens_free(&t);
}

static void test_tokenizer_escapes_numbers(void) {
    /* V1: r'\31 a 1e3 .5' -> ident '1a', 1000, 0.5 */
    CsTokens t;
    CHECK(cs_tokenize("\\31 a 1e3 .5", -1, &t), "tokenize ok");
    int n = 0;
    for (int i = 0; i < t.count; i++) {
        if (t.toks[i].kind == CS_WS) continue;
        if (t.toks[i].kind == CS_EOF) break;
        if (n == 0) {
            CHECK(t.toks[i].kind == CS_IDENT, "esc token ident");
            CHECK(t.toks[i].str && strcmp(t.toks[i].str, "1a") == 0, "esc ident '%s'",
                  t.toks[i].str ? t.toks[i].str : "");
        }
        if (n == 1) {
            CHECK(t.toks[i].kind == CS_NUMBER, "1e3 number");
            CHECK(fabs(t.toks[i].num - 1000.0) < 1e-9, "1e3 = %g", t.toks[i].num);
        }
        if (n == 2) {
            CHECK(t.toks[i].kind == CS_NUMBER, ".5 number");
            CHECK(fabs(t.toks[i].num - 0.5) < 1e-9, ".5 = %g", t.toks[i].num);
        }
        n++;
    }
    CHECK(n == 3, "3 non-ws tokens, got %d", n);
    cs_tokens_free(&t);
}

static void test_tokenizer_misc(void) {
    CsTokens t;
    /* quoted url() is a function token + string + close paren */
    CHECK(cs_tokenize("url(\"x.png\")", -1, &t), "tokenize ok");
    CHECK(t.count == 4 && t.toks[0].kind == CS_FUNCTION &&
              t.toks[1].kind == CS_STRING && t.toks[2].kind == CS_RPAREN &&
              t.toks[3].kind == CS_EOF,
          "quoted url -> function, string, )");
    CHECK(t.toks[0].str && strcmp(t.toks[0].str, "url") == 0 &&
              t.toks[1].str && strcmp(t.toks[1].str, "x.png") == 0,
          "function name url + string value");
    cs_tokens_free(&t);
    /* url() tolerates inner/outer whitespace */
    CHECK(cs_tokenize("url(  a b.png )", -1, &t), "tokenize ok");
    CHECK(t.toks[0].kind == CS_BAD_URL, "url with inner ws is bad-url");
    cs_tokens_free(&t);
    CHECK(cs_tokenize("url( x.png )", -1, &t), "tokenize ok");
    CHECK(t.toks[0].kind == CS_URL && strcmp(t.toks[0].str, "x.png") == 0,
          "padded url value");
    cs_tokens_free(&t);
    /* comments vanish; CDO/CDC remain tokens (WS filtered) */
    CHECK(cs_tokenize("a/*x*/b<!-- -->c", -1, &t), "tokenize ok");
    {
        CsTokKind seq[8];
        int n = 0;
        for (int i = 0; i < t.count && n < 8; i++) {
            if (t.toks[i].kind == CS_WS) continue;
            seq[n++] = t.toks[i].kind;
        }
        CHECK(n == 6 && seq[0] == CS_IDENT && seq[1] == CS_IDENT &&
                  seq[2] == CS_CDO && seq[3] == CS_CDC && seq[4] == CS_IDENT &&
                  seq[5] == CS_EOF,
              "comment skipped, CDO/CDC tokens");
    }
    cs_tokens_free(&t);
    /* hex color hash + at-keyword */
    CHECK(cs_tokenize("#abc @media", -1, &t), "tokenize ok");
    CHECK(t.toks[0].kind == CS_HASH && t.toks[0].len == 3, "hash token");
    CHECK(t.toks[1].kind == CS_WS && t.toks[2].kind == CS_AT_KEYWORD &&
              t.toks[2].len == 5 && strncmp(t.toks[2].s, "media", 5) == 0,
          "at-keyword token");
    cs_tokens_free(&t);
    /* unterminated string at EOF yields a string token (css-syntax-3);
       only a newline produces bad-string */
    CHECK(cs_tokenize("\"abc", -1, &t), "tokenize ok");
    CHECK(t.toks[0].kind == CS_STRING && t.toks[0].str &&
              strcmp(t.toks[0].str, "abc") == 0,
          "unterminated string at EOF keeps content");
    cs_tokens_free(&t);
    CHECK(cs_tokenize("\"ab\ncd\"", -1, &t), "tokenize ok");
    CHECK(t.toks[0].kind == CS_BAD_STRING, "newline in string is bad-string");
    cs_tokens_free(&t);
}

/* ------------------------------------------------------------------ */
/* selector parser                                                     */
/* ------------------------------------------------------------------ */

static void test_selectors(void) {
    CsGroup g;
    CHECK(cs_parse_selector("h1, .t", -1, &g), "group parse");
    CHECK(g.count == 2, "2 selectors in group, got %d", g.count);
    CHECK(g.items[0].parts[0].s.tag_len == 2 && g.items[1].parts[0].s.cls_count == 1,
          "h1 and .t");

    CHECK(cs_parse_selector("div > p + span ~ a", -1, &g), "combinator chain");
    CHECK(g.items[0].count == 4, "4 compounds, got %d", g.items[0].count);
    CHECK(g.items[0].comb[0] == '>' && g.items[0].comb[1] == '+' &&
              g.items[0].comb[2] == '~',
          "comb order > + ~");

    /* specificity: #a .b c -> (1,1,1) */
    CHECK(cs_parse_selector("#a .b c", -1, &g), "spec parse");
    CHECK(g.items[0].spec[0] == 1 && g.items[0].spec[1] == 1 && g.items[0].spec[2] == 1,
          "spec 1,1,1 got %d,%d,%d", g.items[0].spec[0], g.items[0].spec[1],
          g.items[0].spec[2]);
    /* :not() contributes its inner specificity, :hover adds b */
    CHECK(cs_parse_selector("a:not(.x):hover", -1, &g), "not parse");
    CHECK(g.items[0].spec[0] == 0 && g.items[0].spec[1] == 2 && g.items[0].spec[2] == 1,
          "not spec 0,2,1 got %d,%d,%d", g.items[0].spec[0], g.items[0].spec[1],
          g.items[0].spec[2]);
    CHECK(g.items[0].parts[0].has_not && g.items[0].parts[0].not.cls_count == 1,
          "not carries .x");

    /* attribute operators */
    CHECK(cs_parse_selector("[href^=\"https://\"][class~=\"x\"][lang|=en][data]", -1, &g),
          "attr ops parse");
    CsSimple* c = &g.items[0].parts[0].s;
    CHECK(c->attr_count == 4, "4 attr selectors, got %d", c->attr_count);
    CHECK(c->attrs[0].op == CS_ATTR_PREFIX && c->attrs[1].op == CS_ATTR_INCLUDES &&
              c->attrs[2].op == CS_ATTR_DASH && c->attrs[3].op == CS_ATTR_PRESENT,
          "attr ops ^= ~= |= present");
    CHECK(c->attrs[0].val_len == 8 && strncmp(c->attrs[0].val, "https://", 8) == 0,
          "attr value quoted");

    /* nth-child forms */
    CHECK(cs_parse_selector("li:nth-child(2n+1)", -1, &g), "nth parse");
    CHECK(g.items[0].parts[0].pseudo == CS_P_NTH_CHILD &&
              g.items[0].parts[0].nth_a == 2 && g.items[0].parts[0].nth_b == 1,
          "2n+1 -> a=2 b=1");
    CHECK(cs_parse_selector("li:nth-child(odd)", -1, &g) &&
              g.items[0].parts[0].nth_a == 2 && g.items[0].parts[0].nth_b == 1,
          "odd -> 2n+1");
    CHECK(cs_parse_selector("li:nth-child(even)", -1, &g) &&
              g.items[0].parts[0].nth_a == 2 && g.items[0].parts[0].nth_b == 0,
          "even -> 2n");
    CHECK(cs_parse_selector("li:nth-child(3)", -1, &g) &&
              g.items[0].parts[0].nth_a == 0 && g.items[0].parts[0].nth_b == 3,
          "plain 3 -> b=3");

    /* pseudo-element kept, flagged */
    CHECK(cs_parse_selector("p::before", -1, &g), "::before parses");
    CHECK(g.items[0].parts[0].is_pseudo_elem, "::before flagged");

    /* compounds that START with a pseudo (regression: were dropped whole) */
    CHECK(cs_parse_selector(":root", -1, &g), ":root parses");
    CHECK(g.items[0].parts[0].pseudo == CS_P_ROOT, ":root -> CS_P_ROOT");
    CHECK(cs_parse_selector(":hover", -1, &g), ":hover parses");
    CHECK(g.items[0].parts[0].pseudo == CS_P_HOVER, ":hover -> CS_P_HOVER");
    CHECK(cs_parse_selector(":checked", -1, &g), ":checked parses");
    CHECK(g.items[0].parts[0].pseudo == CS_P_CHECKED, ":checked -> CS_P_CHECKED");
    CHECK(cs_parse_selector(":nth-child(2n+1)", -1, &g) &&
              g.items[0].parts[0].nth_a == 2 && g.items[0].parts[0].nth_b == 1,
          "pseudo-only nth-child parses");
    CHECK(cs_parse_selector("::after", -1, &g) &&
              g.items[0].parts[0].is_pseudo_elem &&
              g.items[0].parts[0].pseudo_elem_len == 5 &&
              strncmp(g.items[0].parts[0].pseudo_elem, "after", 5) == 0,
          "pseudo-element-only compound parses");

    /* reference parity: supported pseudo classes (V1 selector implementation) */
    CHECK(cs_parse_selector(":focus-visible", -1, &g) &&
              g.items[0].parts[0].pseudo == CS_P_FOCUS_VISIBLE,
          ":focus-visible parses");
    CHECK(cs_parse_selector("input:user-invalid", -1, &g) &&
              g.items[0].parts[0].pseudo == CS_P_USER_INVALID,
          ":user-invalid parses");
    CHECK(cs_parse_selector(":placeholder-shown", -1, &g) &&
              g.items[0].parts[0].pseudo == CS_P_PLACEHOLDER_SHOWN,
          ":placeholder-shown parses");
    CHECK(cs_parse_selector(":nth-last-of-type(2)", -1, &g) &&
              g.items[0].parts[0].pseudo == CS_P_NTH_LAST_OF_TYPE &&
              g.items[0].parts[0].nth_b == 2,
          ":nth-last-of-type parses with args");
    CHECK(cs_parse_selector(":dir(ltr)", -1, &g) &&
              g.items[0].parts[0].pseudo == CS_P_DIR &&
              g.items[0].parts[0].arg_len == 3 &&
              strncmp(g.items[0].parts[0].arg, "ltr", 3) == 0,
          ":dir(ltr) stores its argument");
    CHECK(cs_parse_selector(":lang(en-US)", -1, &g) &&
              g.items[0].parts[0].pseudo == CS_P_LANG,
          ":lang(en-US) parses");
    CHECK(!cs_parse_selector(":dir", -1, &g),
          ":dir without argument rejected");

    /* reference parity: open pseudo-element set + CSS2 single-colon aliases */
    CHECK(cs_parse_selector("dialog::backdrop", -1, &g) &&
              g.items[0].parts[0].is_pseudo_elem &&
              strncmp(g.items[0].parts[0].pseudo_elem, "backdrop", 8) == 0,
          "::backdrop parses (reference set)");
    CHECK(cs_parse_selector("b:after", -1, &g) &&
              g.items[0].parts[0].is_pseudo_elem &&
              strncmp(g.items[0].parts[0].pseudo_elem, "after", 5) == 0,
          "CSS2 single-colon :after alias");
    CHECK(cs_parse_selector("p::first-letter", -1, &g) &&
              g.items[0].parts[0].is_pseudo_elem,
          "::first-letter parses");

    /* documented v1 gap: :is/:where/:has need inner selector lists */
    CHECK(!cs_parse_selector(":is(div)", -1, &g),
          ":is() still rejected (known gap, not silently ignored)");
    CHECK(cs_parse_selector("div :root", -1, &g), "descendant pseudo-only compound");

    /* a simple that consumed input and failed must still be rejected */
    CHECK(!cs_parse_selector("[href=", -1, &g), "malformed attr rejected");

    /* pseudo-element placement (reference: must be last, class may precede) */
    CHECK(cs_parse_selector(".tip:hover::after", -1, &g) &&
              g.items[0].parts[0].pseudo == CS_P_HOVER &&
              g.items[0].parts[0].is_pseudo_elem,
          "pseudo-class + pseudo-element parses");
    CHECK(cs_parse_selector("span:first-child::after", -1, &g) &&
              g.items[0].parts[0].is_pseudo_elem,
          "first-child::after parses");
    CHECK(!cs_parse_selector("p::before:hover", -1, &g),
          "pseudo-class after pseudo-element rejected");
    CHECK(!cs_parse_selector("p::before > a", -1, &g),
          "pseudo-element must be last (combinator)");
    CHECK(cs_parse_selector("p::before, a:hover", -1, &g),
          "pseudo-element last within its complex selector");

    /* invalid selectors rejected (reference drops these rules) */
    CHECK(!cs_parse_selector("a:bogus", -1, &g), "unknown pseudo-class invalid");
    CHECK(!cs_parse_selector("p::bogus", -1, &g), "unknown pseudo-element invalid");
    CHECK(!cs_parse_selector("..x", -1, &g), "double dot invalid");
    CHECK(!cs_parse_selector("#", -1, &g), "empty id invalid");
    CHECK(!cs_parse_selector("p[", -1, &g), "unclosed attr invalid");
    CHECK(!cs_parse_selector("p q)", -1, &g), "trailing paren invalid");
    CHECK(!cs_parse_selector("", -1, &g), "empty selector invalid");
}

/* ------------------------------------------------------------------ */
/* stylesheet parser                                                   */
/* ------------------------------------------------------------------ */

static void test_sheet_rules(void) {
    /* V1: 'h1, .t { color: red; margin: 0 auto }' */
    CsSheet* sh = cs_sheet_parse("h1, .t { color: red; margin: 0 auto }", -1);
    CHECK(sh->rule_count == 1, "1 rule, got %d", sh->rule_count);
    CHECK(sh->rules[0].sel.count == 2, "grouped selector count %d",
          sh->rules[0].sel.count);
    CHECK(sh->rules[0].decl_count == 2, "2 decls (no parse-time shorthand expand), got %d",
          sh->rules[0].decl_count);
    CHECK(strncmp(sh->rules[0].decls[0].name, "color", 5) == 0 &&
              sh->rules[0].decls[0].ntoks == 1,
          "color: red");
    CHECK(!sh->rules[0].media, "no media on top rule");
    cs_sheet_free(sh);

    /* !important with and without inner space */
    sh = cs_sheet_parse("p { color: red ! important; width: 1px }", -1);
    CHECK(sh->rule_count == 1 && sh->rules[0].decl_count == 2, "important rule");
    CHECK(sh->rules[0].decls[0].important, "red ! important flagged");
    CHECK(!sh->rules[0].decls[1].important, "width not important");
    cs_sheet_free(sh);
    sh = cs_sheet_parse("p { width: 2px!important }", -1);
    CHECK(sh->rules[0].decls[0].important && sh->rules[0].decls[0].ntoks == 1,
          "no-space !important, value keeps only 2px");
    cs_sheet_free(sh);

    /* invalid selectors drop the whole rule (V1: 1 rule left, 2 dropped) */
    sh = cs_sheet_parse(
        "p::bogus { color: red } a:bogus { color: blue } b { color: green }", -1);
    CHECK(sh->rule_count == 1, "invalid selector rules dropped, %d left",
          sh->rule_count);
    CHECK(sh->dropped_rules == 2, "2 dropped rules, got %d", sh->dropped_rules);
    CHECK(sh->rules[0].decl_count == 1, "green rule kept");
    cs_sheet_free(sh);

    /* structurally invalid declarations dropped, rule kept */
    sh = cs_sheet_parse("p { color red; width: ; padding: 4px }", -1);
    CHECK(sh->rule_count == 1 && sh->rules[0].decl_count == 1,
          "only valid decl kept, got %d", sh->rules[0].decl_count);
    CHECK(sh->dropped_decls == 2, "2 dropped decls, got %d", sh->dropped_decls);
    cs_sheet_free(sh);

    /* unbalanced braces recover (V1: keeps parsing after stray '}') */
    sh = cs_sheet_parse("} p { color: red } q { color: ", -1);
    CHECK(sh->rule_count >= 1, "recovered: p rule parsed");
    CHECK(sh->rules[0].sel.items[0].parts[0].s.tag_len == 1 &&
              strncmp(sh->rules[0].sel.items[0].parts[0].s.tag, "p", 1) == 0,
          "first rule is p");
    CHECK(sh->dropped_decls >= 1, "trailing incomplete decl dropped");
    cs_sheet_free(sh);

    /* pseudo-element rules are kept but flagged (Phase 7 paint hooks) */
    sh = cs_sheet_parse(".a::before { content: '' } .b { color: red }", -1);
    CHECK(sh->rule_count == 2, "pseudo-element rule kept");
    CHECK(sh->rules[0].is_pseudo_element && !sh->rules[1].is_pseudo_element,
          "flag on first rule only");
    cs_sheet_free(sh);
}

static void test_sheet_at_rules(void) {
    /* V1: @import skipped, @media nested, plain rule after */
    CsSheet* sh = cs_sheet_parse(
        "@import \"x.css\"; @font-face { font-family: x; src: url(f.ttf) }"
        "@media (min-width: 600px) { p { color: red } } div { color: blue }",
        -1);
    CHECK(sh->rule_count == 2, "2 rules (media-nested + div), got %d", sh->rule_count);
    CHECK(sh->rules[0].media != NULL &&
              strcmp(sh->rules[0].media, "(min-width: 600px)") == 0,
          "media condition '%s'", sh->rules[0].media ? sh->rules[0].media : "");
    CHECK(sh->rules[1].media == NULL, "div rule has no media");
    CHECK(sh->font_family && strcmp(sh->font_family, "x") == 0, "font-face family");
    CHECK(sh->font_url && strcmp(sh->font_url, "f.ttf") == 0, "font-face url");
    cs_sheet_free(sh);

    /* @font-face string family with spaces; multi-source picks first url */
    sh = cs_sheet_parse(
        "@font-face{font-family:\"Font Awesome 6 Free\";"
        "src:url(../webfonts/fa-solid-900.woff2) format(\"woff2\"),"
        "url(../webfonts/fa-solid-900.ttf) format(\"truetype\")}", -1);
    CHECK(sh->rule_count == 0, "font-face is not a style rule");
    CHECK(sh->font_family && strcmp(sh->font_family, "Font Awesome 6 Free") == 0,
          "quoted family '%s'", sh->font_family ? sh->font_family : "");
    CHECK(sh->font_url && strcmp(sh->font_url, "../webfonts/fa-solid-900.woff2") == 0,
          "first source url");
    cs_sheet_free(sh);

    /* @keyframes and other unknown at-rules skipped, parsing continues */
    sh = cs_sheet_parse(
        "@keyframes spin { from { opacity: 0 } to { opacity: 1 } }"
        "@supports (display: grid) { .g { display: grid } }"
        "p { color: red }",
        -1);
    CHECK(sh->rule_count == 1, "only p rule kept, got %d", sh->rule_count);
    cs_sheet_free(sh);

    /* nested media: two conditions preserved in order */
    sh = cs_sheet_parse(
        "@media (min-width: 600px) { p { color: red }"
        "@media (orientation: landscape) { p { color: blue } } }", -1);
    CHECK(sh->rule_count == 2, "nested media flattened, got %d", sh->rule_count);
    CHECK(sh->rules[0].media && strstr(sh->rules[0].media, "min-width") != NULL,
          "outer condition");
    CHECK(sh->rules[1].media && strstr(sh->rules[1].media, "orientation") != NULL,
          "inner condition");
    cs_sheet_free(sh);
}

/* ------------------------------------------------------------------ */
/* media conditions                                                    */
/* ------------------------------------------------------------------ */

static void test_media(void) {
    CsMediaState st = {1024, 768, false};
    CsMediaState stp = {1024, 768, true};
    CsMediaState narrow = {500, 800, false};
    CHECK(cs_media_matches("(min-width: 600px)", &st), "min-width 600 @1024");
    CHECK(!cs_media_matches("(min-width: 600px)", &narrow), "min-width 600 @500");
    CHECK(cs_media_matches("(max-width: 1100px)", &st), "max-width 1100 @1024");
    CHECK(!cs_media_matches("(max-width: 400px)", &narrow), "max-width 400 @500 fails");
    CHECK(cs_media_matches("(min-width: 600px) and (max-width: 1100px)", &st),
          "conjunction");
    CHECK(!cs_media_matches("(min-width: 600px) and (max-width: 900px)", &st),
          "conjunction false");
    CHECK(cs_media_matches("(max-width: 900px) or (min-width: 600px)", &narrow),
          "disjunction true");
    CHECK(!cs_media_matches("(max-width: 900px) or (min-width: 2000px)", &st),
          "disjunction false");
    CHECK(cs_media_matches("not (max-width: 900px)", &st), "not clause");
    CHECK(!cs_media_matches("not (min-width: 600px)", &st), "not clause false");
    CHECK(cs_media_matches("all", &st), "all");
    CHECK(cs_media_matches("screen", &st) && !cs_media_matches("screen", &stp),
          "screen vs print");
    CHECK(cs_media_matches("print", &stp), "print");
    /* landscape width 1024 > height 768 */
    CHECK(cs_media_matches("(orientation: landscape)", &st),
          "landscape @1024x768");
    CHECK(cs_media_matches("(orientation: portrait)", &narrow),
          "portrait @500x800");
    CHECK(!cs_media_matches("(min-resolution: 2dppx)", &st), "unknown feature false");
    CHECK(!cs_media_matches("(min-width: 600px) garbage", &st), "trailing garbage false");
    CHECK(cs_media_matches("", &st) && cs_media_matches(NULL, &st), "empty matches");
    /* em lengths in media queries resolve at 16px */
    CHECK(cs_media_matches("(min-width: 40em)", &st), "40em=640px @1024");
    CHECK(!cs_media_matches("(min-width: 80em)", &st), "80em=1280px @1024 fails");
}

int main(void) {
    test_tokenizer_tokens();
    test_tokenizer_escapes_numbers();
    test_tokenizer_misc();
    test_selectors();
    test_sheet_rules();
    test_sheet_at_rules();
    test_media();
    printf("css tests: %d checks, %d failures\n", g_checks, g_failures);
    return g_failures == 0 ? 0 : 1;
}
