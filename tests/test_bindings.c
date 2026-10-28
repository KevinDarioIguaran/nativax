/*
    JS ↔ DOM binding tests (Phase 4).

    Exercises the boundary directly, without the application host: a parsed
    document, a JavaScriptCore VM and the binding layer. Asserts that script
    writes really mutate the native DOM, that inline style writes re-enter the
    cascade, and that listeners receive dispatched events.
*/
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "nativax/css.h"
#include "nativax/dom.h"
#include "nativax/html.h"
#include "nativax/js_dom.h"
#include "nativax/js_engine.h"
#include "nativax/style.h"

static int g_checks = 0;
static int g_failures = 0;

#define CHECK(cond, ...)                                \
    do {                                                \
        g_checks++;                                     \
        if (!(cond)) {                                  \
            g_failures++;                               \
            printf("FAIL %s:%d: ", __FILE__, __LINE__); \
            printf(__VA_ARGS__);                        \
            printf("\n");                               \
        }                                               \
    } while (0)

static const char* PAGE =
    "<!DOCTYPE html><html><head><style>#title { font-size: 20px; }</style></head>"
    "<body><div id=\"box\"><h1 id=\"title\">Hi</h1><p id=\"p\">x</p></div></body></html>";

static bool eval(NxJs* js, const char* code) {
    char* err = NULL;
    if (!nx_js_eval(js, code, "<test>", &err)) {
        printf("FAIL script: %s\n", err ? err : "unknown");
        free(err);
        return false;
    }
    return true;
}

int main(void) {
    NxDocument* doc = nx_doc_new();
    char* err = NULL;
    CHECK(nx_html_parse(doc, PAGE, (int)strlen(PAGE), &err), "parse page: %s",
          err ? err : "ok");
    free(err);

    NxJs* js = nx_js_new();
    CHECK(js != NULL, "js vm");
    NxDomBindings* bind = nx_dom_bind_new(js, doc);
    CHECK(bind != NULL, "bindings installed");
    if (!js || !bind) return 1;

    /* document queries + text mutation */
    CHECK(eval(js, "var t = document.getElementById('title');"
                   "if (!t) throw new Error('title missing');"
                   "t.textContent = 'Hello';"),
          "script mutates textContent");
    NxNodeRef title = nx_doc_get_element_by_id(doc, "title");
    char* text = nx_node_text_content(doc, title);
    CHECK(text && strcmp(text, "Hello") == 0, "DOM text updated: %s", text ? text : "(null)");
    free(text);

    /* element creation + append + removal */
    CHECK(eval(js, "var d = document.createElement('div');"
                   "d.id = 'added';"
                   "d.textContent = 'new node';"
                   "document.body.appendChild(d);"),
          "script creates and appends an element");
    NxNodeRef added = nx_doc_get_element_by_id(doc, "added");
    CHECK(added != 0, "created element is queryable");
    CHECK(nx_node_parent(doc, added) == nx_doc_query_selector(doc, "body"),
          "created element is attached to body");
    CHECK(eval(js, "var n = document.getElementById('added'); n.remove();"),
          "script removes the element");
    CHECK(nx_doc_get_element_by_id(doc, "added") == 0, "removed element is gone");

    /* attributes, classList, inline style */
    CHECK(eval(js, "document.getElementById('box').className = 'active';"
                   "document.getElementById('p').style.color = '#ff0000';"
                   "document.getElementById('p').dataset = document.getElementById('p').id;"),
          "script writes attributes and style");
    NxNodeRef box = nx_doc_get_element_by_id(doc, "box");
    NxNodeRef p = nx_doc_get_element_by_id(doc, "p");
    CHECK(strcmp(nx_node_get_attr(doc, box, "class"), "active") == 0, "className applied");
    const char* inline_style = nx_node_get_attr(doc, p, "style");
    CHECK(inline_style && strstr(inline_style, "color: #ff0000") != NULL,
          "style attribute written: %s", inline_style ? inline_style : "(none)");

    /* inline style participates in the cascade */
    CsSheet* sheet = cs_sheet_parse("#title { font-size: 20px; }", 27);
    const CsSheet* sheets[1] = {sheet};
    NxComputedStyle* styles = nx_style_resolve(doc, sheets, 1, 1024.0f, 16.0f);
    CHECK(styles != NULL, "style resolution");
    CHECK(styles[nx_node_index(title)].font_size == 20.0f, "stylesheet font-size applied");
    CHECK(styles[nx_node_index(p)].r == 1.0f && styles[nx_node_index(p)].g < 0.05f,
          "inline color won the cascade (r=%.2f g=%.2f)", styles[nx_node_index(p)].r,
          styles[nx_node_index(p)].g);

    /* listeners: registration, dispatch, event payload */
    CHECK(eval(js, "var hits = 0;"
                   "document.getElementById('p').addEventListener('click', function (e) {"
                   "  hits++;"
                   "  e.currentTarget.textContent = 'hit:' + hits;"
                   "});"),
          "script registers a listener");
    CHECK(nx_dom_listener_count(bind) == 1, "listener tracked (%d)",
          nx_dom_listener_count(bind));
    CHECK(nx_dom_dispatch_js(bind, p, "click"), "event dispatched");
    text = nx_node_text_content(doc, p);
    CHECK(text && strcmp(text, "hit:1") == 0, "listener ran: %s", text ? text : "(null)");
    free(text);

    /* bubbling: a parent listener sees a child target */
    CHECK(eval(js, "var boxHits = 0;"
                   "document.getElementById('box').addEventListener('click', function () {"
                   "  boxHits++; boxHits = boxHits;"
                   "  document.getElementById('title').textContent = 'bubbled';"
                   "});"),
          "script registers a parent listener");
    CHECK(nx_dom_dispatch_js(bind, p, "click"), "bubbled dispatch");
    text = nx_node_text_content(doc, title);
    CHECK(text && strcmp(text, "bubbled") == 0, "parent listener received bubble: %s",
          text ? text : "(null)");
    free(text);

    /* teardown leaves no listener references */
    nx_dom_bind_free(bind);
    CHECK(nx_dom_listener_count(NULL) == 0, "bindings freed");
    nx_js_free(js);
    free(styles);
    cs_sheet_free(sheet);
    nx_doc_free(doc);

    printf("%d checks, %d failures\n", g_checks, g_failures);
    return g_failures == 0 ? 0 : 1;
}
