/*
    Debug dump tests: DOM tree formatting, stats, canonical selector
    formatting and CSS rule dumps. The dumps are the native equivalent of
    the V1 debug artifacts — tests pin their format so refactors that
    break reviewability fail CI.
*/
#include "nativax/debug_dump.h"
#include "nativax/html.h"

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

static NxDocument* parse(const char* html) {
    NxDocument* doc = nx_doc_new();
    char* err = NULL;
    if (!nx_html_parse(doc, html, -1, &err)) {
        fprintf(stderr, "PARSE FAILED: %s\n", err ? err : "?");
        free(err);
        g_failures++;
        nx_doc_free(doc);
        return NULL;
    }
    return doc;
}

/* dump a doc into a malloc'd buffer (caller frees) */
static char* dump_dom(NxDocument* doc, size_t* len_out) {
    char* buf = NULL;
    size_t len = 0;
    FILE* f = open_memstream(&buf, &len);
    if (!f) return NULL;
    nxd_dump_dom(f, doc, nx_doc_root(doc), 0);
    fclose(f);
    *len_out = len;
    return buf;
}

static void test_dom_dump(void) {
    NxDocument* doc =
        parse("<div id=x class=\"a b\" data-k=\"v\"><p>hi</p><!--c--></div>");
    if (!doc) return;
    size_t len = 0;
    char* out = dump_dom(doc, &len);
    CHECK(out != NULL, "dump produced output");
    if (out) {
        CHECK(strstr(out, "<html>") != NULL, "root element printed");
        CHECK(strstr(out, "<div id=\"x\" class=\"a b\" data-k=\"v\">") != NULL,
              "attributes quoted:\\n%s", out);
        CHECK(strstr(out, "<p>") != NULL, "child element");
        CHECK(strstr(out, "text \"hi\"") != NULL, "text node escaped");
        CHECK(strstr(out, "<!-- c -->") != NULL, "comment printed");
        free(out);
    }
    NxdDomStats st;
    memset(&st, 0, sizeof(st));
    nxd_dom_stats(doc, nx_doc_root(doc), 0, &st);
    CHECK(st.elements == 5, "5 elements (html/head/body/div/p), got %d",
          st.elements);
    CHECK(st.text == 1, "1 text node, got %d", st.text);
    CHECK(st.comments == 1, "1 comment, got %d", st.comments);
    CHECK(st.max_depth >= 3, "depth >= 3, got %d", st.max_depth);

    /* JSON tree (native counterpart of elements.json) */
    {
        char* buf = NULL;
        size_t blen = 0;
        FILE* f = open_memstream(&buf, &blen);
        if (f) {
            nxd_dump_dom_json(f, doc, nx_doc_root(doc));
            fclose(f);
        }
        if (buf) {
            CHECK(strstr(buf, "{\"children\":[{\"tag\":\"html\"") != NULL,
                  "json root starts with html:\\n%.200s", buf);
            CHECK(strstr(buf, "\"tag\":\"div\",\"id\":\"x\",\"class\":[\"a\",\"b\"]") != NULL,
                  "json id+classes:\\n%.400s", buf);
            CHECK(strstr(buf, "{\"text\":\"hi\"}") != NULL, "json text node");
            CHECK(strstr(buf, "{\"comment\":\"c\"}") != NULL, "json comment node");
            CHECK(strstr(buf, "\"attrs\":{\"data-k\":\"v\"}") != NULL,
                  "json non-special attrs");
            free(buf);
        }
    }

    /* long text is truncated, control chars escaped */
    char big[400];
    memset(big, 'z', sizeof(big) - 1);
    big[sizeof(big) - 1] = '\0';
    char html[512];
    snprintf(html, sizeof(html), "<p>%s</p>", big);
    NxDocument* doc2 = parse(html);
    if (doc2) {
        char* out2 = dump_dom(doc2, &len);
        if (out2) {
            CHECK(strstr(out2, "...\"") != NULL, "long text truncated");
            CHECK(strstr(out2, big) == NULL, "full text not present");
            free(out2);
        }
        nx_doc_free(doc2);
    }
    nx_doc_free(doc);
}

static void test_selector_format(void) {
    char buf[512];
    CsGroup g;

    CHECK(cs_parse_selector("h1, .t", -1, &g), "parse group");
    nxd_format_selector(&g, buf, sizeof(buf));
    CHECK(strcmp(buf, "h1 (0,0,1), .t (0,1,0)") == 0, "group format: '%s'", buf);

    CHECK(cs_parse_selector("div > p.x[data-v=\"1\"]", -1, &g), "parse chain");
    nxd_format_selector(&g, buf, sizeof(buf));
    CHECK(strcmp(buf, "div > p.x[data-v=1] (0,2,2)") == 0, "chain format: '%s'", buf);

    /* plain-integer nth formats without the "+b" suffix (was 1+1) */
    CHECK(cs_parse_selector("li:nth-child(1)", -1, &g), "nth plain parse");
    nxd_format_selector(&g, buf, sizeof(buf));
    CHECK(strcmp(buf, "li:nth-child(1) (0,1,1)") == 0, "nth plain format: '%s'", buf);

    CHECK(cs_parse_selector("li:nth-child(2n+1)", -1, &g), "parse nth");
    nxd_format_selector(&g, buf, sizeof(buf));
    CHECK(strcmp(buf, "li:nth-child(2n+1) (0,1,1)") == 0, "nth format: '%s'", buf);

    CHECK(cs_parse_selector("a:not(.x)", -1, &g), "parse not");
    nxd_format_selector(&g, buf, sizeof(buf));
    CHECK(strcmp(buf, "a:not(.x) (0,1,1)") == 0, "not format: '%s'", buf);

    CHECK(cs_parse_selector("p::after", -1, &g), "parse pseudo-element");
    nxd_format_selector(&g, buf, sizeof(buf));
    CHECK(strcmp(buf, "p::after (0,0,1)") == 0, "after format: '%s'", buf);

    CHECK(cs_parse_selector("img + a ~ span", -1, &g), "parse siblings");
    nxd_format_selector(&g, buf, sizeof(buf));
    CHECK(strcmp(buf, "img + a ~ span (0,0,3)") == 0, "sibling format: '%s'", buf);
}

static void test_css_dump(void) {
    const char* css =
        "h1, .t { color: red; width: 2px !important }"
        "@media (min-width: 600px) { p { min-width: 600px } }"
        "p::after { content: '' }";
    CsSheet* sh = cs_sheet_parse(css, -1);
    CHECK(sh->rule_count == 3, "3 rules, got %d", sh->rule_count);
    char* buf = NULL;
    size_t blen = 0;
    FILE* f = open_memstream(&buf, &blen);
    CHECK(f != NULL, "memstream");
    if (f) {
        nxd_dump_css(f, sh);
        fclose(f);
    }
    if (buf) {
        CHECK(strstr(buf, "[0] h1 (0,0,1), .t (0,1,0) {") != NULL,
              "group rule header:\\n%s", buf);
        CHECK(strstr(buf, "color: red") != NULL, "plain decl");
        CHECK(strstr(buf, "width: 2px !important") != NULL, "important decl");
        CHECK(strstr(buf, "[1] @media (min-width: 600px) {") != NULL,
              "media rule header");
        CHECK(strstr(buf, "min-width: 600px") != NULL, "dimension decl value");
        CHECK(strstr(buf, "::after") != NULL, "pseudo-element selector");
        CHECK(strstr(buf, "(pseudo-element rule)") != NULL, "pseudo flag line");
        CHECK(strstr(buf, "rules=3") != NULL, "stats header");
        free(buf);
    }
    cs_sheet_free(sh);
}

int main(void) {
    test_dom_dump();
    test_selector_format();
    test_css_dump();
    printf("debug tests: %d checks, %d failures\n", g_checks, g_failures);
    return g_failures == 0 ? 0 : 1;
}
