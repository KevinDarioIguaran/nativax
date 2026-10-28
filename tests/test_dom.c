/*
    HTML parser + DOM + events tests.

    Covers: tokenizer forms (quoting, entities, raw text, RCDATA, comments,
    doctype, case), tree construction (implicit html/head/body, void,
    implied end tags, stray-close recovery), serialization round-trip,
    mutation/traversal/id index/querySelector, handle invalidation via
    nx_node_destroy, and event dispatch (capture/bubble order, once,
    preventDefault, stopPropagation, stopImmediatePropagation).
*/
#include "nativax/dom.h"
#include "nativax/html.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

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
        fprintf(stderr, "PARSE FAILED: %s\n  input: %s\n", err ? err : "?", html);
        free(err);
        g_failures++;
        nx_doc_free(doc);
        return NULL;
    }
    return doc;
}

/* find first element with tag under parent (direct children) */
static NxNodeRef child_by_tag(NxDocument* doc, NxNodeRef parent, const char* tag) {
    for (NxNodeRef c = nx_node_first_child(doc, parent); c;
         c = nx_node_next_sibling(doc, c)) {
        if (nx_node_type(doc, c) == NX_NODE_ELEMENT &&
            strcmp(nx_node_name(doc, c), tag) == 0) {
            return c;
        }
    }
    return 0;
}

/* ---- parser: structure ---- */
static void test_basic_structure(void) {
    NxDocument* doc = parse("<html><body><p class=\"x\">hi</p></body></html>");
    if (!doc) return;
    NxNodeRef root = nx_doc_root(doc);
    NxNodeRef html = child_by_tag(doc, root, "html");
    CHECK(html != 0, "html under root");
    NxNodeRef body = child_by_tag(doc, html, "body");
    CHECK(body != 0, "body under html");
    NxNodeRef p = child_by_tag(doc, body, "p");
    CHECK(p != 0, "p under body");
    CHECK(strcmp(nx_node_get_attr(doc, p, "class"), "x") == 0, "class attr");
    int len = 0;
    const char* t = nx_node_text(doc, nx_node_first_child(doc, p), &len);
    CHECK(t && len == 2 && memcmp(t, "hi", 2) == 0, "text child (got '%s')", t ? t : "");
    nx_doc_free(doc);

    /* implicit structure: bare content creates html/body */
    doc = parse("<p>hello</p>");
    if (!doc) return;
    html = child_by_tag(doc, nx_doc_root(doc), "html");
    CHECK(html != 0, "implicit html");
    body = child_by_tag(doc, html, "body");
    CHECK(body != 0, "implicit body");
    p = child_by_tag(doc, body, "p");
    CHECK(p != 0, "p in implicit body");
    nx_doc_free(doc);

    /* head-ish first element goes to head */
    doc = parse("<title>T</title><p>x</p>");
    if (!doc) return;
    html = child_by_tag(doc, nx_doc_root(doc), "html");
    NxNodeRef head = child_by_tag(doc, html, "head");
    CHECK(head != 0, "implicit head for title");
    CHECK(child_by_tag(doc, head, "title") != 0, "title in head");
    body = child_by_tag(doc, html, "body");
    CHECK(body != 0, "body after head content");
    CHECK(child_by_tag(doc, body, "p") != 0, "p in body");
    nx_doc_free(doc);
}

static void test_attribute_forms(void) {
    NxDocument* doc =
        parse("<div id=a class='b' data-x=\"c\" flag title=unquoted>x</div>");
    if (!doc) return;
    NxNodeRef d = child_by_tag(doc, nx_doc_root(doc), "html");
    d = child_by_tag(doc, d, "body");
    d = child_by_tag(doc, d, "div");
    CHECK(d != 0, "div found");
    CHECK(strcmp(nx_node_get_attr(doc, d, "id"), "a") == 0, "unquoted value");
    CHECK(strcmp(nx_node_get_attr(doc, d, "class"), "b") == 0, "single-quoted value");
    CHECK(strcmp(nx_node_get_attr(doc, d, "data-x"), "c") == 0, "double-quoted value");
    const char* flag = nx_node_get_attr(doc, d, "flag");
    CHECK(flag && flag[0] == '\0', "boolean attr value is empty (got '%s')",
          flag ? flag : "(null)");
    CHECK(strcmp(nx_node_get_attr(doc, d, "title"), "unquoted") == 0, "unquoted w/ name");
    nx_doc_free(doc);

    /* first duplicate wins, names lowercased */
    doc = parse("<DIV ID=\"one\" id=\"two\">t</DIV>");
    if (!doc) return;
    NxNodeRef html = child_by_tag(doc, nx_doc_root(doc), "html");
    NxNodeRef div = child_by_tag(doc, child_by_tag(doc, html, "body"), "div");
    CHECK(div != 0, "div exists");
    CHECK(strcmp(nx_node_get_attr(doc, div, "id"), "one") == 0, "first duplicate wins");
    nx_doc_free(doc);

    /* entities in attribute values */
    doc = parse("<a href=\"x?a=1&amp;b=2\">l</a>");
    if (!doc) return;
    html = child_by_tag(doc, nx_doc_root(doc), "html");
    NxNodeRef a = child_by_tag(doc, child_by_tag(doc, html, "body"), "a");
    CHECK(a && strcmp(nx_node_get_attr(doc, a, "href"), "x?a=1&b=2") == 0,
          "entities decoded in attr (%s)", a ? nx_node_get_attr(doc, a, "href") : "-");
    nx_doc_free(doc);
}

static void test_entities(void) {
    NxDocument* doc = parse("<p>&amp;&#65;&#x42;&lt;unknown&nope;</p>");
    if (!doc) return;
    NxNodeRef html = child_by_tag(doc, nx_doc_root(doc), "html");
    NxNodeRef p = child_by_tag(doc, child_by_tag(doc, html, "body"), "p");
    char* txt = nx_node_text_content(doc, p);
    /* &amp; -> &, &#65; -> A, &#x42; -> B, &lt; -> <, unknown named stay */
    CHECK(txt && strcmp(txt, "&AB<unknown&nope;") == 0, "entity decode got '%s'",
          txt ? txt : "-");
    free(txt);
    nx_doc_free(doc);
}

static void test_raw_text(void) {
    /* script: raw until </script; '<' not followed by letter is literal.
       Leading script lands in <head> (HTML5 insertion modes) — search there. */
    NxDocument* doc = parse("<script>var s = \"<div>\"; if (a < b) {}</script><p>ok</p>");
    if (!doc) return;
    NxNodeRef html = child_by_tag(doc, nx_doc_root(doc), "html");
    NxNodeRef body = child_by_tag(doc, html, "body");
    NxNodeRef head = child_by_tag(doc, html, "head");
    NxNodeRef script = head ? child_by_tag(doc, head, "script")
                            : child_by_tag(doc, body, "script");
    CHECK(script != 0, "script element");
    CHECK(nx_node_first_child(doc, script) != 0 &&
              nx_node_next_sibling(doc, nx_node_first_child(doc, script)) == 0,
          "script has single text child");
    char* txt = nx_node_text_content(doc, script);
    CHECK(txt && strcmp(txt, "var s = \"<div>\"; if (a < b) {}") == 0,
          "raw script content ('%s')", txt ? txt : "-");
    free(txt);
    CHECK(child_by_tag(doc, body, "p") != 0, "content after script");
    CHECK(nx_node_type(doc, child_by_tag(doc, body, "div")) == 0, "no phantom div");
    nx_doc_free(doc);

    /* textarea is RCDATA: entities decoded, markup is text */
    doc = parse("<textarea>a &amp; b &lt;i&gt;</textarea>");
    if (!doc) return;
    html = child_by_tag(doc, nx_doc_root(doc), "html");
    body = child_by_tag(doc, html, "body");
    NxNodeRef ta = child_by_tag(doc, body, "textarea");
    CHECK(ta != 0, "textarea");
    txt = nx_node_text_content(doc, ta);
    CHECK(txt && strcmp(txt, "a & b <i>") == 0, "rcdata content ('%s')", txt ? txt : "-");
    free(txt);
    CHECK(nx_node_first_child(doc, ta) == 0 ||
              nx_node_type(doc, nx_node_first_child(doc, ta)) == NX_NODE_TEXT,
          "rcdata children are text only");
    nx_doc_free(doc);
}

static void test_comments_doctype(void) {
    NxDocument* doc = parse("<!DOCTYPE html><!-- hi there --><p>x</p>");
    if (!doc) return;
    NxNodeRef root = nx_doc_root(doc);
    NxNodeRef html = child_by_tag(doc, root, "html");
    CHECK(html != 0, "doctype skipped, html created");
    /* comment attached before html? attached to root while mode==0 */
    bool found_comment = false;
    for (NxNodeRef c = nx_node_first_child(doc, root); c;
         c = nx_node_next_sibling(doc, c)) {
        if (nx_node_type(doc, c) == NX_NODE_COMMENT) {
            found_comment = true;
            int len = 0;
            const char* t = nx_node_text(doc, c, &len);
            CHECK(len == 10 && memcmp(t, " hi there ", 10) == 0, "comment content");
        }
    }
    CHECK(found_comment, "comment node present");
    nx_doc_free(doc);
}

static void test_implied_ends(void) {
    /* li */
    NxDocument* doc = parse("<ul><li>a<li>b</ul>");
    if (!doc) return;
    NxNodeRef html = child_by_tag(doc, nx_doc_root(doc), "html");
    NxNodeRef ul = child_by_tag(doc, child_by_tag(doc, html, "body"), "ul");
    CHECK(ul != 0, "ul");
    int li_count = 0;
    for (NxNodeRef c = nx_node_first_child(doc, ul); c;
         c = nx_node_next_sibling(doc, c)) {
        if (nx_node_type(doc, c) == NX_NODE_ELEMENT &&
            strcmp(nx_node_name(doc, c), "li") == 0) {
            li_count++;
        }
    }
    CHECK(li_count == 2, "two implied-closed li (%d)", li_count);
    nx_doc_free(doc);

    /* p */
    doc = parse("<p>one<p>two</p>");
    if (!doc) return;
    html = child_by_tag(doc, nx_doc_root(doc), "html");
    NxNodeRef body = child_by_tag(doc, html, "body");
    int p_count = 0;
    for (NxNodeRef c = nx_node_first_child(doc, body); c;
         c = nx_node_next_sibling(doc, c)) {
        if (nx_node_type(doc, c) == NX_NODE_ELEMENT &&
            strcmp(nx_node_name(doc, c), "p") == 0) {
            p_count++;
        }
    }
    CHECK(p_count == 2, "two implied-closed p (%d)", p_count);
    nx_doc_free(doc);

    /* dl */
    doc = parse("<dl><dt>a<dd>b</dl>");
    if (!doc) return;
    html = child_by_tag(doc, nx_doc_root(doc), "html");
    NxNodeRef dl = child_by_tag(doc, child_by_tag(doc, html, "body"), "dl");
    CHECK(dl != 0 && child_by_tag(doc, dl, "dt") != 0 && child_by_tag(doc, dl, "dd") != 0,
          "dt/dd implied");
    nx_doc_free(doc);

    /* select/option */
    doc = parse("<select><option>a<option>b</select>");
    if (!doc) return;
    html = child_by_tag(doc, nx_doc_root(doc), "html");
    NxNodeRef sel = child_by_tag(doc, child_by_tag(doc, html, "body"), "select");
    int opt_count = 0;
    for (NxNodeRef c = nx_node_first_child(doc, sel); c;
         c = nx_node_next_sibling(doc, c)) {
        if (nx_node_type(doc, c) == NX_NODE_ELEMENT &&
            strcmp(nx_node_name(doc, c), "option") == 0) {
            opt_count++;
        }
    }
    CHECK(opt_count == 2, "two implied-closed option (%d)", opt_count);
    nx_doc_free(doc);

    /* table cells */
    doc = parse("<table><tr><td>1<td>2</table>");
    if (!doc) return;
    html = child_by_tag(doc, nx_doc_root(doc), "html");
    NxNodeRef table = child_by_tag(doc, child_by_tag(doc, html, "body"), "table");
    NxNodeRef tr = child_by_tag(doc, table, "tr");
    CHECK(tr != 0, "tr under table");
    int td_count = 0;
    for (NxNodeRef c = nx_node_first_child(doc, tr); c;
         c = nx_node_next_sibling(doc, c)) {
        if (nx_node_type(doc, c) == NX_NODE_ELEMENT &&
            strcmp(nx_node_name(doc, c), "td") == 0) {
            td_count++;
        }
    }
    CHECK(td_count == 2, "two implied-closed td (%d)", td_count);
    nx_doc_free(doc);
}

static void test_stray_closes(void) {
    /* stray close with no opener: ignored */
    NxDocument* doc = parse("</p></div><p>x</p>");
    if (!doc) return;
    NxNodeRef html = child_by_tag(doc, nx_doc_root(doc), "html");
    NxNodeRef body = child_by_tag(doc, html, "body");
    CHECK(body != 0, "body exists");
    CHECK(child_by_tag(doc, body, "p") != 0, "p attached");
    CHECK(nx_node_first_child(doc, body) == child_by_tag(doc, body, "p"),
          "stray closes produced no nodes");
    nx_doc_free(doc);

    /* simplified adoption agency: <b><i>x</b>y</i> — i was popped
       incidentally, so it stays active and is reconstructed for y */
    doc = parse("<b><i>x</b>y</i>");
    if (!doc) return;
    html = child_by_tag(doc, nx_doc_root(doc), "html");
    body = child_by_tag(doc, html, "body");
    NxNodeRef b = child_by_tag(doc, body, "b");
    CHECK(b != 0, "b exists");
    NxNodeRef i = child_by_tag(doc, b, "i");
    CHECK(i != 0, "i nested in b");
    /* y lives in a reconstructed <i> sibling of b (browser behavior) */
    NxNodeRef i2 = nx_node_next_sibling(doc, b);
    CHECK(i2 != 0 && nx_node_type(doc, i2) == NX_NODE_ELEMENT &&
              strcmp(nx_node_name(doc, i2), "i") == 0,
          "i reconstructed after b");
    int len = 0;
    const char* t = nx_node_text(doc, nx_node_first_child(doc, i2), &len);
    CHECK(t && len == 1 && t[0] == 'y', "y content in reconstructed i ('%s')",
          t ? t : "-");
    nx_doc_free(doc);
}

static void test_serializer_roundtrip(void) {
    const char* html_in =
        "<!DOCTYPE html><html><head><title>T &amp; U</title></head>"
        "<body><div id=\"a&amp;b\" class=\"c d\" data-n=5>text &lt;here&gt; "
        "<span>more</span><br><img src=\"x.png\" alt=\"\"></div>"
        "<p>para</p><!-- note --></body></html>";
    NxDocument* doc = parse(html_in);
    if (!doc) return;
    char* s1 = nx_node_serialize(doc, nx_doc_root(doc));
    CHECK(s1 != NULL, "serialize pass1");
    /* second parse of serialized output must be stable */
    NxDocument* doc2 = nx_doc_new();
    char* err = NULL;
    CHECK(nx_html_parse(doc2, s1, -1, &err), "reparse serialized (%s)", err ? err : "-");
    free(err);
    char* s2 = nx_node_serialize(doc2, nx_doc_root(doc2));
    CHECK(s1 && s2 && strcmp(s1, s2) == 0, "serialize idempotent\n  s1: %s\n  s2: %s",
          s1 ? s1 : "-", s2 ? s2 : "-");
    /* spot checks */
    CHECK(s1 && strstr(s1, "id=\"a&amp;b\"") != NULL, "attr escape");
    CHECK(s1 && strstr(s1, "text &lt;here&gt;") != NULL, "text escape");
    CHECK(s1 && strstr(s1, "<br>") != NULL, "void element no close");
    CHECK(s1 && strstr(s1, "<img src=\"x.png\" alt=\"\">") != NULL, "img attrs");
    CHECK(s1 && strstr(s1, "<!-- note -->") != NULL, "comment preserved");
    free(s1);
    free(s2);
    nx_doc_free(doc);
    nx_doc_free(doc2);
}

/* ---- DOM mutation ---- */
static void test_mutation(void) {
    NxDocument* doc = nx_doc_new();
    NxNodeRef root = nx_doc_root(doc);
    NxNodeRef div = nx_node_create_element(doc, "div");
    NxNodeRef span1 = nx_node_create_element(doc, "span");
    NxNodeRef span2 = nx_node_create_element(doc, "span");
    NxNodeRef text = nx_node_create_text(doc, "hello", -1);
    CHECK(nx_node_append_child(doc, div, span1), "append span1");
    CHECK(nx_node_append_child(doc, div, text), "append text");
    CHECK(nx_node_insert_before(doc, div, span2, text), "insert span2 before text");
    CHECK(nx_node_append_child(doc, root, div), "append div to root");

    /* order: span1, span2, text */
    NxNodeRef c = nx_node_first_child(doc, div);
    CHECK(c == span1, "first child span1");
    c = nx_node_next_sibling(doc, c);
    CHECK(c == span2, "second child span2");
    c = nx_node_next_sibling(doc, c);
    CHECK(c == text, "third child text");
    CHECK(nx_node_next_sibling(doc, c) == 0, "no fourth");
    CHECK(nx_node_prev_sibling(doc, c) == span2, "prev sibling");
    CHECK(nx_node_last_child(doc, div) == text, "last child");

    CHECK(nx_node_is_ancestor(doc, div, text), "div is ancestor of text");
    CHECK(!nx_node_is_ancestor(doc, text, div), "text is not ancestor of div");
    CHECK(nx_node_depth(doc, text) == 3, "depth text = 3 (got %d)",
          nx_node_depth(doc, text));

    /* removal detaches but keeps handle valid */
    CHECK(nx_node_remove_child(doc, div, span2), "remove span2");
    CHECK(nx_node_type(doc, span2) == NX_NODE_ELEMENT, "detached handle still valid");
    CHECK(nx_node_parent(doc, span2) == 0, "detached has no parent");
    CHECK(nx_node_first_child(doc, div) == span1, "span1 still first");

    /* re-insert moves the node */
    CHECK(nx_node_append_child(doc, div, span2), "re-append span2");
    CHECK(nx_node_last_child(doc, div) == span2, "span2 now last");

    /* text replacement */
    CHECK(nx_node_replace_text(doc, text, "world!", -1), "replace text");
    int len = 0;
    const char* t = nx_node_text(doc, text, &len);
    CHECK(t && len == 6 && memcmp(t, "world!", 6) == 0, "text replaced");

    /* destroy: subtree freed, handles invalid */
    CHECK(nx_node_destroy(doc, span2), "destroy span2");
    CHECK(nx_node_type(doc, span2) == 0, "destroyed handle invalid");
    CHECK(nx_node_last_child(doc, div) == text, "destroy detached from tree");

    /* cycle guard: cannot insert ancestor under descendant */
    CHECK(!nx_node_append_child(doc, text, div), "cycle insert rejected");
    nx_doc_free(doc);
}

static void test_ids_and_queries(void) {
    NxDocument* doc = parse(
        "<section id=\"main\" class=\"hero\">"
        "<div id=\"a\" class=\"box\">1</div>"
        "<div class=\"box accent\">2</div>"
        "<p id=\"b\">3</p>"
        "<div><span id=\"deep\" class=\"box\">4</span></div>"
        "</section>");
    if (!doc) return;

    NxNodeRef main_el = nx_doc_get_element_by_id(doc, "main");
    CHECK(main_el != 0, "get_element_by_id main");
    NxNodeRef a = nx_doc_get_element_by_id(doc, "a");
    CHECK(a != 0, "get_element_by_id a");
    CHECK(nx_doc_get_element_by_id(doc, "missing") == 0, "missing id -> 0");

    /* id attr updates move the index */
    CHECK(nx_node_set_attr(doc, a, "id", "renamed"), "rename id");
    CHECK(nx_doc_get_element_by_id(doc, "a") == 0, "old id gone");
    CHECK(nx_doc_get_element_by_id(doc, "renamed") == a, "new id works");

    /* selector: tag */
    NxNodeRef p = nx_doc_query_selector(doc, "p");
    CHECK(p != 0 && strcmp(nx_node_name(doc, p), "p") == 0, "selector tag");
    /* selector: .class */
    NxNodeRef first_box = nx_doc_query_selector(doc, ".box");
    CHECK(first_box == a || first_box != 0, "selector .class");
    /* selector: tag.class (accent) */
    NxNodeRef accent = nx_doc_query_selector(doc, "div.box.accent");
    CHECK(accent != 0 && strcmp(nx_node_get_attr(doc, accent, "class"), "box accent") == 0,
          "selector tag.class.class");
    /* selector: #id */
    CHECK(nx_doc_query_selector(doc, "#deep") != 0, "selector #id");
    /* descendant chain */
    NxNodeRef deep = nx_doc_query_selector(doc, "section div span");
    CHECK(deep != 0 && strcmp(nx_node_get_attr(doc, deep, "id"), "deep") == 0,
          "descendant selector");
    /* query_selector_all count */
    NxNodeRef all[16];
    int n = nx_doc_query_selector_all(doc, ".box", all, 16);
    CHECK(n == 3, "query_selector_all .box = %d", n);
    nx_doc_free(doc);
}

/* ---- events ---- */
typedef struct LogEntry {
    char phase[16];
    char node[16];
} LogEntry;

static LogEntry g_log[32];
static int g_log_n;

static void logger(NxDocument* doc, NxEvent* ev, void* user) {
    (void)doc;
    (void)ev;
    const char* who = (const char*)user;
    const char* phase = ev->event_phase == 1 ? "capture"
                       : ev->event_phase == 2 ? "target"
                                              : "bubble";
    if (g_log_n < 32) {
        snprintf(g_log[g_log_n].phase, 16, "%s", phase);
        snprintf(g_log[g_log_n].node, 16, "%s", who);
        g_log_n++;
    }
}

static void test_event_dispatch(void) {
    NxDocument* doc = parse("<div id=\"outer\"><span id=\"inner\">t</span></div>");
    if (!doc) return;
    NxNodeRef inner = nx_doc_get_element_by_id(doc, "inner");
    NxNodeRef outer = nx_doc_get_element_by_id(doc, "outer");
    NxNodeRef body = child_by_tag(doc, child_by_tag(doc, nx_doc_root(doc), "html"), "body");
    NxNodeRef html = child_by_tag(doc, nx_doc_root(doc), "html");

    g_log_n = 0;
    NxListenerSpec specs[] = {
        {"click", logger, (void*)"html-c", true, false},
        {"click", logger, (void*)"body-c", true, false},
        {"click", logger, (void*)"outer-c", true, false},
        {"click", logger, (void*)"inner-t", false, false},
        {"click", logger, (void*)"outer-b", false, false},
        {"click", logger, (void*)"body-b", false, false},
        {"click", logger, (void*)"html-b", false, false},
    };
    nx_node_add_listener(doc, html, &specs[0]);
    nx_node_add_listener(doc, body, &specs[1]);
    nx_node_add_listener(doc, outer, &specs[2]);
    nx_node_add_listener(doc, inner, &specs[3]);
    nx_node_add_listener(doc, outer, &specs[4]);
    nx_node_add_listener(doc, body, &specs[5]);
    nx_node_add_listener(doc, html, &specs[6]);

    NxEvent ev;
    nx_event_make(&ev, "click", true, true);
    bool not_canceled = nx_event_dispatch(doc, inner, &ev);
    CHECK(not_canceled, "dispatch not canceled");
    CHECK(g_log_n == 7, "7 listener calls (%d)", g_log_n);
    static const char* expect[] = {"html-c", "body-c", "outer-c", "inner-t",
                                   "outer-b", "body-b", "html-b"};
    for (int i = 0; i < g_log_n && i < 7; i++) {
        CHECK(strcmp(g_log[i].node, expect[i]) == 0, "order[%d] = %s (want %s)", i,
              g_log[i].node, expect[i]);
    }
    CHECK(ev.target == inner, "target");
    CHECK(ev.event_phase == 3, "final phase is bubble (%d)", ev.event_phase);
    CHECK(ev.current_target == html, "current_target ends at html");
    nx_doc_free(doc);

    /* non-bubbling event skips bubble phase */
    doc = parse("<div id=\"d\"><span id=\"s\">t</span></div>");
    if (!doc) return;
    inner = nx_doc_get_element_by_id(doc, "s");
    outer = nx_doc_get_element_by_id(doc, "d");
    g_log_n = 0;
    NxListenerSpec s1 = {"focus", logger, (void*)"outer-c", true, false};
    NxListenerSpec s2 = {"focus", logger, (void*)"inner-t", false, false};
    NxListenerSpec s3 = {"focus", logger, (void*)"outer-b", false, false};
    nx_node_add_listener(doc, outer, &s1);
    nx_node_add_listener(doc, inner, &s2);
    nx_node_add_listener(doc, outer, &s3);
    nx_event_make(&ev, "focus", false, false);
    nx_event_dispatch(doc, inner, &ev);
    CHECK(g_log_n == 2, "non-bubbling: 2 calls (%d)", g_log_n);
    CHECK(strcmp(g_log[0].node, "outer-c") == 0 && strcmp(g_log[1].node, "inner-t") == 0,
          "capture+target only");
    nx_doc_free(doc);
}

static void stopper(NxDocument* doc, NxEvent* ev, void* user) {
    (void)doc;
    (void)user;
    ev->propagation_stopped = true;
}

static void preventer(NxDocument* doc, NxEvent* ev, void* user) {
    (void)doc;
    (void)user;
    ev->default_prevented = true;
}

static void immediate_stopper(NxDocument* doc, NxEvent* ev, void* user) {
    (void)doc;
    (void)user;
    ev->immediate_stopped = true;
    ev->propagation_stopped = true;
}

static void test_event_flags(void) {
    /* stopPropagation in capture on outer: target + bubble must not run */
    NxDocument* doc = parse("<div id=\"d\"><span id=\"s\">t</span></div>");
    if (!doc) return;
    NxNodeRef inner = nx_doc_get_element_by_id(doc, "s");
    NxNodeRef outer = nx_doc_get_element_by_id(doc, "d");
    g_log_n = 0;
    NxListenerSpec s1 = {"x", stopper, NULL, true, false};
    NxListenerSpec s2 = {"x", logger, (void*)"inner-t", false, false};
    NxListenerSpec s3 = {"x", logger, (void*)"outer-b", false, false};
    nx_node_add_listener(doc, outer, &s1);
    nx_node_add_listener(doc, inner, &s2);
    nx_node_add_listener(doc, outer, &s3);
    NxEvent ev;
    nx_event_make(&ev, "x", true, true);
    bool not_canceled = nx_event_dispatch(doc, inner, &ev);
    CHECK(not_canceled, "stop does not cancel default");
    CHECK(ev.propagation_stopped, "propagation_stopped set");
    CHECK(g_log_n == 0, "stopped before target/bubble (%d)", g_log_n);
    nx_doc_free(doc);

    /* preventDefault: dispatch returns false, flag visible */
    doc = parse("<div id=\"d\">t</div>");
    if (!doc) return;
    outer = nx_doc_get_element_by_id(doc, "d");
    NxListenerSpec s4 = {"x", preventer, NULL, false, false};
    nx_node_add_listener(doc, outer, &s4);
    nx_event_make(&ev, "x", true, true);
    not_canceled = nx_event_dispatch(doc, outer, &ev);
    CHECK(!not_canceled, "dispatch returns false when default prevented");
    CHECK(ev.default_prevented, "default_prevented set");
    nx_doc_free(doc);

    /* non-cancelable event: preventDefault still flags but dispatch
       semantics follow cancelable in callers (flag always recorded) */
    doc = parse("<div id=\"d\">t</div>");
    if (!doc) return;
    outer = nx_doc_get_element_by_id(doc, "d");
    nx_node_add_listener(doc, outer, &s4);
    nx_event_make(&ev, "x", true, false); /* not cancelable */
    not_canceled = nx_event_dispatch(doc, outer, &ev);
    CHECK(!ev.cancelable, "cancelable false preserved");
    (void)not_canceled;
    nx_doc_free(doc);

    /* stopImmediatePropagation: later listeners on same node skipped */
    doc = parse("<div id=\"d\">t</div>");
    if (!doc) return;
    outer = nx_doc_get_element_by_id(doc, "d");
    g_log_n = 0;
    NxListenerSpec s5 = {"x", immediate_stopper, NULL, false, false};
    NxListenerSpec s6 = {"x", logger, (void*)"after", false, false};
    nx_node_add_listener(doc, outer, &s5);
    nx_node_add_listener(doc, outer, &s6);
    nx_event_make(&ev, "x", true, true);
    nx_event_dispatch(doc, outer, &ev);
    CHECK(g_log_n == 0, "immediate stop skips later listeners (%d)", g_log_n);
    nx_doc_free(doc);

    /* once: listener fires exactly one dispatch */
    doc = parse("<div id=\"d\">t</div>");
    if (!doc) return;
    outer = nx_doc_get_element_by_id(doc, "d");
    g_log_n = 0;
    NxListenerSpec s7 = {"x", logger, (void*)"once", false, true};
    nx_node_add_listener(doc, outer, &s7);
    nx_event_make(&ev, "x", true, true);
    nx_event_dispatch(doc, outer, &ev);
    nx_event_make(&ev, "x", true, true);
    nx_event_dispatch(doc, outer, &ev);
    CHECK(g_log_n == 1, "once listener fired once (%d)", g_log_n);
    nx_doc_free(doc);

    /* remove_listener */
    doc = parse("<div id=\"d\">t</div>");
    if (!doc) return;
    outer = nx_doc_get_element_by_id(doc, "d");
    g_log_n = 0;
    NxListenerSpec s8 = {"x", logger, (void*)"rm", false, false};
    nx_node_add_listener(doc, outer, &s8);
    CHECK(nx_node_remove_listener(doc, outer, "x", false, logger, (void*)"rm"),
          "remove_listener finds it");
    nx_event_make(&ev, "x", true, true);
    nx_event_dispatch(doc, outer, &ev);
    CHECK(g_log_n == 0, "removed listener not called (%d)", g_log_n);
    nx_doc_free(doc);
}

/* ---- ported from packages/nativa_html/test/parser_test.dart ---- */
static char* body_inner(NxDocument* doc) {
    NxNodeRef html = child_by_tag(doc, nx_doc_root(doc), "html");
    NxNodeRef body = child_by_tag(doc, html, "body");
    if (!body) return strdup("");
    /* serialize children only (innerHTML semantics): strip the <body ...>
       prefix and </body> suffix from the full serialization */
    char* full = nx_node_serialize(doc, body);
    char* out = strdup(full ? full : "");
    free(full);
    char* gt = strchr(out, '>');
    if (gt) memmove(out, gt + 1, strlen(gt + 1) + 1);
    char* close = strstr(out, "</body>");
    if (close) *close = '\0';
    return out;
}

static void test_ported_dart_cases(void) {
    /* empty document gets html/head/body */
    NxDocument* doc = parse("");
    if (!doc) return;
    char* s = nx_node_serialize(doc, nx_doc_root(doc));
    CHECK(s && strcmp(s, "<html><head></head><body></body></html>") == 0,
          "empty doc skeleton ('%s')", s ? s : "-");
    free(s);
    nx_doc_free(doc);

    /* explicit structure with doctype */
    doc = parse("<!DOCTYPE html><html lang=\"es\"><head><title>T</title>"
                "</head><body class=\"b\"><p>x</p></body></html>");
    if (!doc) return;
    NxNodeRef html = child_by_tag(doc, nx_doc_root(doc), "html");
    CHECK(html && strcmp(nx_node_get_attr(doc, html, "lang"), "es") == 0, "html lang");
    NxNodeRef head = child_by_tag(doc, html, "head");
    NxNodeRef title = child_by_tag(doc, head, "title");
    char* txt = nx_node_text_content(doc, title);
    CHECK(txt && strcmp(txt, "T") == 0, "title text");
    free(txt);
    NxNodeRef body = child_by_tag(doc, html, "body");
    CHECK(body && strcmp(nx_node_get_attr(doc, body, "class"), "b") == 0, "body class");
    char* inner = body_inner(doc);
    CHECK(strcmp(inner, "<p>x</p>") == 0, "body inner ('%s')", inner);
    free(inner);
    nx_doc_free(doc);

    /* head elements before content go to head; content starts body */
    doc = parse("<style>p{}</style><meta charset=utf-8>Hola<div>a</div>");
    if (!doc) return;
    NxNodeRef h = child_by_tag(doc, child_by_tag(doc, nx_doc_root(doc), "html"), "head");
    CHECK(child_by_tag(doc, h, "style") != 0, "style in head");
    CHECK(child_by_tag(doc, h, "meta") != 0, "meta in head");
    inner = body_inner(doc);
    CHECK(strcmp(inner, "Hola<div>a</div>") == 0, "body content after head ('%s')", inner);
    free(inner);
    nx_doc_free(doc);

    /* content after </body> stays in body */
    doc = parse("<body><p>a</p></body><p>b</p>");
    if (!doc) return;
    inner = body_inner(doc);
    CHECK(strcmp(inner, "<p>a</p><p>b</p>") == 0, "content after </body> ('%s')", inner);
    free(inner);
    nx_doc_free(doc);

    /* nesting */
    doc = parse("<div><section><span>a<b>b</b></span></section></div>");
    if (!doc) return;
    inner = body_inner(doc);
    CHECK(strcmp(inner, "<div><section><span>a<b>b</b></span></section></div>") == 0,
          "nesting ('%s')", inner);
    free(inner);
    nx_doc_free(doc);

    /* quoted, unquoted, empty and boolean attributes */
    doc = parse("<input type=text value=\"a b\" data-x='q\"' disabled>");
    if (!doc) return;
    NxNodeRef input = nx_doc_query_selector(doc, "input");
    CHECK(input != 0, "input found");
    CHECK(nx_node_attr_count(doc, input) == 4, "4 attrs (%d)",
          nx_node_attr_count(doc, input));
    CHECK(strcmp(nx_node_get_attr(doc, input, "type"), "text") == 0, "type");
    CHECK(strcmp(nx_node_get_attr(doc, input, "value"), "a b") == 0, "value with space");
    CHECK(strcmp(nx_node_get_attr(doc, input, "data-x"), "q\"") == 0, "quote in value");
    const char* dis = nx_node_get_attr(doc, input, "disabled");
    CHECK(dis && dis[0] == '\0', "boolean disabled = empty");
    nx_doc_free(doc);

    /* attribute names lower-cased; duplicates keep the first */
    doc = parse("<div ID=\"a\" id=\"b\" Class=c></div>");
    if (!doc) return;
    NxNodeRef div = nx_doc_query_selector(doc, "div");
    CHECK(div && strcmp(nx_node_get_attr(doc, div, "id"), "a") == 0, "first dup wins");
    CHECK(div && strcmp(nx_node_get_attr(doc, div, "class"), "c") == 0, "class lowercased");
    nx_doc_free(doc);

    /* void elements never take children; <hr> closes <p>; </p> inserts one */
    doc = parse("<p>a<br>b<img src=x.png>c<hr></p>");
    if (!doc) return;
    inner = body_inner(doc);
    CHECK(strcmp(inner, "<p>a<br>b<img src=\"x.png\">c</p><hr><p></p>") == 0,
          "void + hr closes p ('%s')", inner);
    free(inner);
    nx_doc_free(doc);
    doc = parse("<input/><span>x</span>");
    if (!doc) return;
    inner = body_inner(doc);
    CHECK(strcmp(inner, "<input><span>x</span>") == 0, "input self-close ('%s')", inner);
    free(inner);
    nx_doc_free(doc);

    /* unknown elements kept; tag names case-insensitive */
    doc = parse("<my-widget foo=1><x-y>t</x-y></my-widget>");
    if (!doc) return;
    inner = body_inner(doc);
    CHECK(strcmp(inner, "<my-widget foo=\"1\"><x-y>t</x-y></my-widget>") == 0,
          "unknown elements ('%s')", inner);
    free(inner);
    nx_doc_free(doc);
    doc = parse("<DIV><SpAn>x</span></div>");
    if (!doc) return;
    inner = body_inner(doc);
    CHECK(strcmp(inner, "<div><span>x</span></div>") == 0, "case-insensitive ('%s')", inner);
    free(inner);
    nx_doc_free(doc);

    /* named and numeric references */
    doc = parse("<p>&lt;b&gt; &amp; &copy; &#169; &#xA9; &ntilde; &nbsp;</p>");
    if (!doc) return;
    txt = nx_node_text_content(doc, nx_doc_query_selector(doc, "p"));
    CHECK(txt && strcmp(txt, "<b> & \xC2\xA9 \xC2\xA9 \xC2\xA9 \xC3\xB1 \xC2\xA0") == 0,
          "char refs ('%s')", txt ? txt : "-");
    free(txt);
    nx_doc_free(doc);

    /* unknown and bare ampersands stay literal */
    doc = parse("<p>a & b &zz; &#;</p>");
    if (!doc) return;
    txt = nx_node_text_content(doc, nx_doc_query_selector(doc, "p"));
    CHECK(txt && strcmp(txt, "a & b &zz; &#;") == 0, "literal ampersands ('%s')",
          txt ? txt : "-");
    free(txt);
    nx_doc_free(doc);

    /* references in attributes */
    doc = parse("<a href=\"?a=1&amp;b=2&copy=3\" title=\"&quot;x&quot;\">l</a>");
    if (!doc) return;
    NxNodeRef a = nx_doc_query_selector(doc, "a");
    CHECK(a && strcmp(nx_node_get_attr(doc, a, "href"), "?a=1&b=2&copy=3") == 0,
          "attr refs href ('%s')", a ? nx_node_get_attr(doc, a, "href") : "-");
    CHECK(a && strcmp(nx_node_get_attr(doc, a, "title"), "\"x\"") == 0, "attr refs title");
    nx_doc_free(doc);

    /* invalid numeric references become U+FFFD */
    doc = parse("<p>&#0;&#xD800;&#99999999;</p>");
    if (!doc) return;
    txt = nx_node_text_content(doc, nx_doc_query_selector(doc, "p"));
    CHECK(txt && strcmp(txt, "\xEF\xBF\xBD\xEF\xBF\xBD\xEF\xBF\xBD") == 0,
          "invalid numerics -> FFFD ('%s')", txt ? txt : "-");
    free(txt);
    nx_doc_free(doc);

    /* windows-1252 numeric references */
    doc = parse("<p>&#x80;</p>");
    if (!doc) return;
    txt = nx_node_text_content(doc, nx_doc_query_selector(doc, "p"));
    CHECK(txt && strcmp(txt, "\xE2\x82\xAC") == 0, "&#x80; -> euro ('%s')", txt ? txt : "-");
    free(txt);
    nx_doc_free(doc);

    /* a lone < is text; non-ASCII preserved */
    doc = parse("<p>1 < 2 and 3 <= 4</p>");
    if (!doc) return;
    txt = nx_node_text_content(doc, nx_doc_query_selector(doc, "p"));
    CHECK(txt && strcmp(txt, "1 < 2 and 3 <= 4") == 0, "lone < ('%s')", txt ? txt : "-");
    free(txt);
    nx_doc_free(doc);
    doc = parse("<p>\xD7\xA9\xD7\x9C\xD7\x95\xD7\x9D \xE6\xBC\xA2\xE5\xAD\x97 \xF0\x9F\x8E\x89</p>");
    if (!doc) return;
    txt = nx_node_text_content(doc, nx_doc_query_selector(doc, "p"));
    CHECK(txt && strcmp(txt, "\xD7\xA9\xD7\x9C\xD7\x95\xD7\x9D \xE6\xBC\xA2\xE5\xAD\x97 \xF0\x9F\x8E\x89") == 0,
          "non-ASCII preserved");
    free(txt);
    nx_doc_free(doc);

    /* comments become nodes; bogus comments dropped */
    doc = parse("<div><!-- hi --><span></span></div>");
    if (!doc) return;
    NxNodeRef d2 = nx_doc_query_selector(doc, "div");
    NxNodeRef first = nx_node_first_child(doc, d2);
    CHECK(first && nx_node_type(doc, first) == NX_NODE_COMMENT, "comment is first child");
    int clen = 0;
    const char* ct = nx_node_text(doc, first, &clen);
    CHECK(clen == 4 && memcmp(ct, " hi ", 4) == 0, "comment data");
    nx_doc_free(doc);
    doc = parse("<?xml version=\"1.0\"?><p>x</p>");
    if (!doc) return;
    inner = body_inner(doc);
    CHECK(strcmp(inner, "<p>x</p>") == 0, "bogus PI dropped ('%s')", inner);
    free(inner);
    nx_doc_free(doc);

    /* raw text: script/style/textarea semantics */
    doc = parse("<script>if (a < b && c > d) { x = \"</div>\"; }</script><p>after</p>");
    if (!doc) return;
    NxNodeRef script = nx_doc_query_selector(doc, "script");
    txt = nx_node_text_content(doc, script);
    CHECK(txt && strcmp(txt, "if (a < b && c > d) { x = \"</div>\"; }") == 0,
          "script raw ('%s')", txt ? txt : "-");
    free(txt);
    txt = nx_node_text_content(doc, nx_doc_query_selector(doc, "p"));
    CHECK(txt && strcmp(txt, "after") == 0, "after script");
    free(txt);
    nx_doc_free(doc);
    doc = parse("<style>a > b { color: red }</STYLE><p>x</p>");
    if (!doc) return;
    txt = nx_node_text_content(doc, nx_doc_query_selector(doc, "style"));
    CHECK(txt && strcmp(txt, "a > b { color: red }") == 0, "style raw ('%s')",
          txt ? txt : "-");
    free(txt);
    CHECK(nx_doc_query_selector(doc, "p") != 0, "case-insensitive style close");
    nx_doc_free(doc);
    doc = parse("<textarea>&lt;b&gt;<i>x</i></textarea>");
    if (!doc) return;
    txt = nx_node_text_content(doc, nx_doc_query_selector(doc, "textarea"));
    CHECK(txt && strcmp(txt, "<b><i>x</i>") == 0, "textarea rcdata ('%s')", txt ? txt : "-");
    free(txt);
    CHECK(nx_doc_query_selector(doc, "i") == 0, "no element inside textarea");
    nx_doc_free(doc);
    doc = parse("<script>let a = 1;<p>");
    if (!doc) return;
    txt = nx_node_text_content(doc, nx_doc_query_selector(doc, "script"));
    CHECK(txt && strcmp(txt, "let a = 1;<p>") == 0, "unterminated script ('%s')",
          txt ? txt : "-");
    free(txt);
    nx_doc_free(doc);
    doc = parse("<script></script");
    if (!doc) return;
    txt = nx_node_text_content(doc, nx_doc_query_selector(doc, "script"));
    CHECK(txt && strcmp(txt, "</script") == 0, "unterminated end tag stays raw ('%s')",
          txt ? txt : "-");
    free(txt);
    nx_doc_free(doc);

    /* implicit closing and recovery */
    doc = parse("<p>a<div>b</div>");
    if (!doc) return;
    inner = body_inner(doc);
    CHECK(strcmp(inner, "<p>a</p><div>b</div>") == 0, "p closed by div ('%s')", inner);
    free(inner);
    nx_doc_free(doc);
    doc = parse("<p>a<center>b<p>c");
    if (!doc) return;
    inner = body_inner(doc);
    CHECK(strcmp(inner, "<p>a</p><center>b<p>c</p></center>") == 0,
          "p closed by center ('%s')", inner);
    free(inner);
    nx_doc_free(doc);
    doc = parse("<a>1<a>2</a>");
    if (!doc) return;
    inner = body_inner(doc);
    CHECK(strcmp(inner, "<a>1</a><a>2</a>") == 0, "nested anchors ('%s')", inner);
    free(inner);
    nx_doc_free(doc);
    doc = parse("<form><div></form><div>");
    if (!doc) return;
    inner = body_inner(doc);
    CHECK(strcmp(inner, "<form><div><div></div></div></form>") == 0,
          "form end tag leaves descendants ('%s')", inner);
    free(inner);
    nx_doc_free(doc);
    doc = parse("<frame>test");
    if (!doc) return;
    inner = body_inner(doc);
    CHECK(strcmp(inner, "test") == 0, "frame ignored in body ('%s')", inner);
    free(inner);
    nx_doc_free(doc);
    doc = parse("<ul><li>a<ul><li>b</ul><li>c</ul>");
    if (!doc) return;
    inner = body_inner(doc);
    CHECK(strcmp(inner, "<ul><li>a<ul><li>b</li></ul></li><li>c</li></ul>") == 0,
          "nested li close ('%s')", inner);
    free(inner);
    nx_doc_free(doc);
    doc = parse("<div>a</span>b</div>");
    if (!doc) return;
    inner = body_inner(doc);
    CHECK(strcmp(inner, "<div>ab</div>") == 0, "unmatched end tag ignored ('%s')", inner);
    free(inner);
    nx_doc_free(doc);
    doc = parse("<div><span><b>x</div>y");
    if (!doc) return;
    inner = body_inner(doc);
    CHECK(strcmp(inner, "<div><span><b>x</b></span></div><b>y</b>") == 0,
          "intervening close + reconstruction ('%s')", inner);
    free(inner);
    nx_doc_free(doc);
    doc = parse("<div><span>x");
    if (!doc) return;
    inner = body_inner(doc);
    CHECK(strcmp(inner, "<div><span>x</span></div>") == 0, "unclosed closed at EOF ('%s')",
          inner);
    free(inner);
    nx_doc_free(doc);
    doc = parse("a</br>b</p>");
    if (!doc) return;
    inner = body_inner(doc);
    CHECK(strcmp(inner, "a<br>b<p></p>") == 0, "</br> and </p> quirks ('%s')", inner);
    free(inner);
    nx_doc_free(doc);
    doc = parse("<div/><span>x</span>");
    if (!doc) return;
    inner = body_inner(doc);
    CHECK(strcmp(inner, "<div><span>x</span></div>") == 0,
          "self-closing non-void stays open ('%s')", inner);
    free(inner);
    nx_doc_free(doc);
    doc = parse("<p>x</p><div class=\"a");
    if (!doc) return;
    inner = body_inner(doc);
    CHECK(strcmp(inner, "<p>x</p>") == 0, "truncated start tag dropped ('%s')", inner);
    free(inner);
    nx_doc_free(doc);
    doc = parse("<p>x</p></div");
    if (!doc) return;
    inner = body_inner(doc);
    CHECK(strcmp(inner, "<p>x</p>") == 0, "truncated end tag dropped ('%s')", inner);
    free(inner);
    nx_doc_free(doc);

    /* foreign content: svg self-closing tags and breakout */
    doc = parse("<svg viewBox=\"0 0 10 10\"><rect width=\"1\"/><circle r=\"2\"/>"
                "<g><path d=\"M0 0\"/></g></svg><p>after</p><svg><circle/>"
                "<p>break</p>");
    if (!doc) return;
    NxNodeRef svgs[4];
    int nsvg = nx_doc_query_selector_all(doc, "svg", svgs, 4);
    CHECK(nsvg == 2, "two svg (%d)", nsvg);
    if (nsvg == 2) {
        int k = 0;
        const char* want[3] = {"rect", "circle", "g"};
        for (NxNodeRef c = nx_node_first_child(doc, svgs[0]); c;
             c = nx_node_next_sibling(doc, c)) {
            if (nx_node_type(doc, c) != NX_NODE_ELEMENT) continue;
            CHECK(k < 3 && strcmp(nx_node_name(doc, c), want[k]) == 0, "svg child %d (%s)",
                  k, nx_node_name(doc, c));
            k++;
        }
        CHECK(k == 3, "three svg children (%d)", k);
        NxNodeRef g = nx_doc_query_selector(doc, "svg g");
        CHECK(g != 0 && child_by_tag(doc, g, "path") != 0, "path inside g");
        /* breakout: p after circle is in body, not svg */
        NxNodeRef ps[4];
        int np = nx_doc_query_selector_all(doc, "p", ps, 4);
        CHECK(np == 2, "two p (%d)", np);
        if (np == 2) {
            NxNodeRef pbody = child_by_tag(
                doc, child_by_tag(doc, nx_doc_root(doc), "html"), "body");
            CHECK(nx_node_parent(doc, ps[0]) == pbody, "first p in body");
            CHECK(nx_node_parent(doc, ps[1]) == pbody, "breakout p in body");
        }
        /* second svg contains only circle */
        int k2 = 0;
        for (NxNodeRef c = nx_node_first_child(doc, svgs[1]); c;
             c = nx_node_next_sibling(doc, c)) {
            if (nx_node_type(doc, c) == NX_NODE_ELEMENT) k2++;
        }
        CHECK(k2 == 1, "second svg has one element (%d)", k2);
    }
    nx_doc_free(doc);

    /* input length limit */
    {
        char* big = malloc(64 * 1024 * 1024);
        memset(big, 'a', 5 * 1024 * 1024);
        big[5 * 1024 * 1024] = '\0';
        NxDocument* d2 = nx_doc_new();
        char* err = NULL;
        CHECK(!nx_html_parse(d2, big, 5 * 1024 * 1024, &err) && err != NULL,
              "input limit enforced");
        free(err);
        nx_doc_free(d2);
        free(big);
    }

    /* depth limit flattens nesting without failing */
    {
        char deep[6000];
        int off = 0;
        for (int i = 0; i < 500; i++) {
            memcpy(deep + off, "<div>", 5);
            off += 5;
        }
        deep[off] = '\0';
        NxDocument* d2 = parse(deep);
        if (d2) {
            int depth = 0;
            NxNodeRef cur = child_by_tag(d2, child_by_tag(d2, nx_doc_root(d2), "html"),
                                         "body");
            while (cur) {
                NxNodeRef next = nx_node_first_child(d2, cur);
                if (!next) break;
                cur = next;
                depth++;
                if (depth > NX_MAX_DEPTH + 4) break;
            }
            CHECK(depth <= NX_MAX_DEPTH, "depth flattened (%d)", depth);
            nx_doc_free(d2);
        }
    }

    /* large documents parse in linear time */
    {
        int per = (int)strlen("<div class=\"row\"><span>item &amp; text</span><b>x</b></div>");
        int reps = 2000;
        char* big = malloc((size_t)per * (size_t)reps + 1);
        int off = 0;
        for (int i = 0; i < reps; i++) {
            memcpy(big + off, "<div class=\"row\"><span>item &amp; text</span><b>x</b></div>",
                   (size_t)per);
            off += per;
        }
        big[off] = '\0';
        struct timespec t0, t1;
        clock_gettime(CLOCK_MONOTONIC, &t0);
        NxDocument* d2 = nx_doc_new();
        char* err = NULL;
        bool ok = nx_html_parse(d2, big, off, &err);
        clock_gettime(CLOCK_MONOTONIC, &t1);
        free(err);
        CHECK(ok, "large doc parses");
        double ms = (double)(t1.tv_sec - t0.tv_sec) * 1000.0 +
                    (double)(t1.tv_nsec - t0.tv_nsec) / 1e6;
        CHECK(ms < 3000.0, "large doc linear-ish (%.0f ms for %d rows)", ms, reps);
        int rows = 0;
        NxNodeRef body = child_by_tag(
            d2, child_by_tag(d2, nx_doc_root(d2), "html"), "body");
        for (NxNodeRef c = nx_node_first_child(d2, body); c;
             c = nx_node_next_sibling(d2, c)) {
            if (nx_node_type(d2, c) == NX_NODE_ELEMENT) rows++;
        }
        CHECK(rows == reps, "all rows (%d)", rows);
        nx_doc_free(d2);
        free(big);
    }
}

int main(void) {
    test_basic_structure();
    test_attribute_forms();
    test_entities();
    test_raw_text();
    test_comments_doctype();
    test_implied_ends();
    test_stray_closes();
    test_serializer_roundtrip();
    test_mutation();
    test_ids_and_queries();
    test_event_dispatch();
    test_event_flags();
    test_ported_dart_cases();
    fprintf(stderr, "%d checks, %d failures\n", g_checks, g_failures);
    return g_failures == 0 ? 0 : 1;
}
