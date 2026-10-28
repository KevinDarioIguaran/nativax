/*
    Application host tests: real HTML/CSS/JS load, script-driven DOM updates,
    pointer hit testing, and the three hot-reload paths (css, js, document).

    The example app is copied to a temporary directory first so the reload
    tests can rewrite files without touching the repository.
*/
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "nativax/app.h"
#include "nativax/dom.h"
#include "nativax/layout.h"
#include "nativax/platform.h"

static int g_checks = 0;
static int g_failures = 0;

#define CHECK(cond, ...)                                    \
    do {                                                    \
        g_checks++;                                         \
        if (!(cond)) {                                      \
            g_failures++;                                   \
            printf("FAIL %s:%d: ", __FILE__, __LINE__);     \
            printf(__VA_ARGS__);                            \
            printf("\n");                                   \
        }                                                   \
    } while (0)

static NxBox* find_box(NxBox* box, NxNodeRef node) {
    if (!box) return NULL;
    if (box->node == node) return box;
    for (int i = 0; i < box->child_count; i++) {
        NxBox* r = find_box(box->children[i], node);
        if (r) return r;
    }
    return NULL;
}

static char* text_of(NxApp* app, const char* id) {
    NxDocument* doc = nx_app_doc(app);
    NxNodeRef n = nx_doc_get_element_by_id(doc, id);
    if (!n) return NULL;
    return nx_node_text_content(doc, n);
}

static void write_file(const char* path, const char* data) {
    FILE* f = fopen(path, "wb");
    if (!f) {
        printf("FAIL cannot write %s\n", path);
        exit(1);
    }
    fputs(data, f);
    fclose(f);
}

int main(void) {
    char tmp[256];
    snprintf(tmp, sizeof(tmp), "/tmp/nativax-app-test-%d", (int)getpid());
    char cmd[1600];
    snprintf(cmd, sizeof(cmd), "rm -rf %s && cp -r %s/examples/counter %s", tmp,
             NATIVAX_SOURCE_DIR, tmp);
    if (system(cmd) != 0) {
        printf("FAIL could not stage example app\n");
        return 1;
    }

    NxAppConfig cfg;
    memset(&cfg, 0, sizeof(cfg));
    cfg.root = tmp;
    cfg.entry = "index.html";
    cfg.font_path = NATIVAX_SOURCE_DIR "/assets/fonts/DejaVuSans.ttf";
    cfg.width = 1024;
    cfg.height = 768;

    NxApp* app = nx_app_new(&cfg);
    CHECK(app != NULL, "app allocation");
    char* err = NULL;
    bool loaded = nx_app_load(app, &err);
    CHECK(loaded, "load example app: %s", err ? err : "ok");
    free(err);
    if (!loaded) return 1;

    nx_app_update(app, 16.0);

    /* --- pipeline is real: DOM + layout + painted display list ---------- */
    char* stats = nx_app_stats_json(app);
    CHECK(stats != NULL && strstr(stats, "\"loaded\":true") != NULL, "stats report loaded app");
    CHECK(stats != NULL && strstr(stats, "\"scripts\":1") != NULL, "one external script ran");
    CHECK(stats != NULL && strstr(stats, "\"listeners\":2") != NULL,
          "two script listeners registered: %s", stats ? stats : "(null)");
    CHECK(stats != NULL && strstr(stats, "\"sheets\":1") != NULL, "stylesheet linked");
    free(stats);

    NxNodeRef count = nx_doc_get_element_by_id(nx_app_doc(app), "count");
    CHECK(count != 0, "#count element exists");
    NxBox* count_box = find_box(nx_app_layout(app)->root, count);
    CHECK(count_box != NULL, "#count has a layout box");
    CHECK(count_box && count_box->w > 100.0f && count_box->h > 10.0f,
          "#count box has real geometry (%.1fx%.1f)", count_box ? count_box->w : 0.0f,
          count_box ? count_box->h : 0.0f);

    const NxDisplayList* dl = nx_app_list(app);
    CHECK(dl->vert_count > 0 && dl->group_count > 0, "display list has geometry");
    unsigned before_verts = dl->vert_count;

    /* --- native platform input reaches script listeners ---------------- */
    char* input_err = NULL;
    CHECK(nx_js_eval(nx_app_js(app),
                     "window.__keys = 0; window.__moves = 0;\n"
                     "document.body.addEventListener('keydown', function(){ window.__keys++; });\n"
                     "document.body.addEventListener('pointermove', function(){ window.__moves++; });",
                     "platform-input-test.js", &input_err),
          "install input listeners: %s", input_err ? input_err : "ok");
    free(input_err);
    CHECK(nx_app_key(app, NX_KEY_ENTER, true), "keydown is dispatched on <body>");
    CHECK(nx_app_pointer_move(app, 10.0f, 10.0f), "pointermove hits a node");
    char* counter = nx_js_eval_json(nx_app_js(app), "window.__keys * 10 + window.__moves", NULL);
    CHECK(counter && strcmp(counter, "11") == 0, "listeners observed native input: %s",
          counter ? counter : "(null)");
    free(counter);

    char* text = text_of(app, "count");
    CHECK(text && strcmp(text, "Clicked 0 times") == 0, "initial text: %s", text ? text : "(null)");
    free(text);

    /* --- JavaScript mutates the DOM in response to a click -------------- */
    float cx = count_box->x + count_box->w / 2.0f;
    float cy = count_box->y + count_box->h / 2.0f;
    CHECK(nx_app_pointer(app, cx, cy, true), "click hits a node");
    nx_app_update(app, 32.0);

    text = text_of(app, "count");
    CHECK(text && strcmp(text, "Clicked 1 times") == 0, "script updated text: %s",
          text ? text : "(null)");
    free(text);
    text = text_of(app, "title");
    CHECK(text && strcmp(text, "DOM updated by script") == 0, "script updated title: %s",
          text ? text : "(null)");
    free(text);

    const char* style_attr = nx_node_get_attr(nx_app_doc(app), count, "style");
    CHECK(style_attr && strstr(style_attr, "background-color") != NULL,
          "inline style written by script: %s", style_attr ? style_attr : "(none)");
    nx_app_update(app, 48.0);
    CHECK(nx_app_list(app)->vert_count != before_verts,
          "repaint reflects the script mutation (%u -> %u)", before_verts,
          nx_app_list(app)->vert_count);

    /* --- CSS hot reload: stylesheet edit, DOM/JS state kept ------------- */
    NxBox* card_box = find_box(nx_app_layout(app)->root,
                               nx_doc_get_element_by_id(nx_app_doc(app), "card"));
    CHECK(card_box != NULL, "#card box exists");
    float width_before = card_box ? card_box->w : 0.0f;
    char css_path[512];
    snprintf(css_path, sizeof(css_path), "%s/style.css", tmp);
    write_file(css_path,
               "body { margin: 0; background: #ffffff; color: #000000; }\n"
               "header { background: #0f3460; color: #ffffff; padding: 24px; }\n"
               "h1 { font-size: 32px; margin: 0; }\n"
               "main { padding: 24px; }\n"
               ".card { background: #ffffff; padding: 20px; width: 40%; }\n"
               "h2 { font-size: 22px; margin-top: 0; }\n"
               "p { font-size: 16px; }\n"
               ".btn { background: #0f3460; color: #ffffff; font-size: 16px; padding: 10px;\n"
               "       width: 240px; }\n"
               ".note { background: #fff3cd; color: #664d03; padding: 12px; width: 60%; }\n");
    CHECK(nx_app_reload_css(app), "css reload");
    nx_app_update(app, 64.0);
    NxBox* card_after = find_box(nx_app_layout(app)->root,
                                 nx_doc_get_element_by_id(nx_app_doc(app), "card"));
    CHECK(card_after && card_after->w < width_before,
          "css reload changed layout width (%.1f -> %.1f)", width_before,
          card_after ? card_after->w : 0.0f);
    text = text_of(app, "count");
    CHECK(text && strcmp(text, "Clicked 1 times") == 0, "css reload preserved DOM state: %s",
          text ? text : "(null)");
    free(text);

    /* --- JS hot reload: fresh context, scripts re-run on the live DOM --- */
    char js_path[512];
    snprintf(js_path, sizeof(js_path), "%s/app.js", tmp);
    write_file(js_path,
               "document.getElementById('title').textContent = 'js reloaded';\n"
               "document.getElementById('count').addEventListener('click', function () {\n"
               "  document.getElementById('count').textContent = 'script v2';\n"
               "});\n");
    CHECK(nx_app_reload_js(app), "js reload");
    nx_app_update(app, 80.0);
    text = text_of(app, "title");
    CHECK(text && strcmp(text, "js reloaded") == 0, "js reload re-ran scripts: %s",
          text ? text : "(null)");
    free(text);
    CHECK(nx_dom_listener_count(NULL) == 0, "listener count null-safe");

    NxBox* count_after = find_box(nx_app_layout(app)->root,
                                  nx_doc_get_element_by_id(nx_app_doc(app), "count"));
    CHECK(count_after != NULL, "layout rebuilt after js reload");
    CHECK(nx_app_pointer(app, count_after->x + 5, count_after->y + 5, true),
          "click after js reload");
    nx_app_update(app, 96.0);
    text = text_of(app, "count");
    CHECK(text && strcmp(text, "script v2") == 0, "v2 listener ran: %s", text ? text : "(null)");
    free(text);

    /* --- full document reload ------------------------------------------ */
    write_file(js_path, "document.getElementById('title').textContent = 'v3';\n");
    CHECK(nx_app_reload_document(app), "document reload");
    nx_app_update(app, 112.0);
    text = text_of(app, "title");
    CHECK(text && strcmp(text, "v3") == 0, "document reload re-parsed and re-ran: %s",
          text ? text : "(null)");
    free(text);

    /* ---- Phase 3: transform + overflow hit testing ----------------- */
    char tmp2[256];
    snprintf(tmp2, sizeof(tmp2), "/tmp/nativax-app-test2-%d", (int)getpid());
    char cmd2[1600];
    snprintf(cmd2, sizeof(cmd2), "rm -rf %s && mkdir -p %s", tmp2, tmp2);
    if (system(cmd2) != 0) { printf("FAIL stage2\n"); return 1; }
    char p2[512];
    snprintf(p2, sizeof(p2), "%s/index.html", tmp2);
    write_file(p2, "<!doctype html><html><head><meta charset=\"utf-8\"><link rel=\"stylesheet\" href=\"style.css\"></head><body><div id=\"moved\" class=\"moved\">moved</div><div id=\"clip\" class=\"clip\"><div id=\"wideh\" class=\"wide\">wide</div></div><div id=\"visible\" class=\"visible\"><div id=\"widev\" class=\"wide\">wide</div></div><script src=\"app.js\"></script></body></html>");
    snprintf(p2, sizeof(p2), "%s/style.css", tmp2);
    write_file(p2, "body { margin: 0; background: #ffffff; }\n.moved { width: 80px; height: 40px; background: #ff0000; transform: translate(200px, 60px); }\n.clip { width: 100px; height: 60px; overflow: hidden; background: #00ff00; margin-top: 20px; }\n.visible { width: 100px; height: 60px; background: #0000ff; margin-top: 20px; }\n.wide { width: 300px; height: 20px; background: #000000; }\n");
    snprintf(p2, sizeof(p2), "%s/app.js", tmp2);
    write_file(p2, "window.__moved=0; window.__hidden=0; window.__visible=0;\ndocument.getElementById('moved').addEventListener('click',function(){window.__moved++;});\ndocument.getElementById('wideh').addEventListener('click',function(){window.__hidden++;});\ndocument.getElementById('widev').addEventListener('click',function(){window.__visible++;});\n");

    NxAppConfig cfg2; memset(&cfg2,0,sizeof(cfg2));
    cfg2.root = tmp2; cfg2.entry = "index.html";
    cfg2.font_path = NATIVAX_SOURCE_DIR "/assets/fonts/DejaVuSans.ttf";
    cfg2.width = 1024; cfg2.height = 768;
    NxApp* app2 = nx_app_new(&cfg2);
    CHECK(app2 != NULL, "app2 alloc");
    char* err2 = NULL;
    bool loaded2 = nx_app_load(app2, &err2);
    CHECK(loaded2, "app2 load: %s", err2 ? err2 : "ok");
    free(err2);
    if (loaded2) nx_app_update(app2, 16.0);

    /* transformed hit */
    CHECK(nx_app_pointer(app2, 240.0f, 80.0f, true), "moved click returns hit");
    nx_app_update(app2, 32.0);
    char* v = nx_js_eval_json(nx_app_js(app2), "window.__moved", NULL);
    CHECK(v && strcmp(v, "1") == 0, "transformed element hit (got %s)", v ? v : "(null)");
    free(v);
    CHECK(nx_app_pointer(app2, 40.0f, 20.0f, true), "miss click returns (some) hit");
    nx_app_update(app2, 48.0);
    char* v2 = nx_js_eval_json(nx_app_js(app2), "window.__moved", NULL);
    CHECK(v2 && strcmp(v2, "1") == 0, "untransformed location did not hit moved (got %s)", v2 ? v2 : "(null)");
    free(v2);

    /* overflow hidden blocks hits outside the clip box */
    CHECK(nx_app_pointer(app2, 50.0f, 50.0f, true), "hidden inside clip");
    nx_app_update(app2, 64.0);
    char* h = nx_js_eval_json(nx_app_js(app2), "window.__hidden", NULL);
    CHECK(h && strcmp(h, "1") == 0, "overflow-hidden child hit inside (got %s)", h ? h : "(null)");
    free(h);
    CHECK(nx_app_pointer(app2, 200.0f, 50.0f, true), "hidden outside returns some node");
    nx_app_update(app2, 80.0);
    h = nx_js_eval_json(nx_app_js(app2), "window.__hidden", NULL);
    CHECK(h && strcmp(h, "1") == 0, "overflow-hidden child not hit outside (got %s)", h ? h : "(null)");
    free(h);

    /* visible (no overflow) allows hits outside parent box */
    CHECK(nx_app_pointer(app2, 200.0f, 110.0f, true), "visible outside returns hit");
    nx_app_update(app2, 96.0);
    char* vis = nx_js_eval_json(nx_app_js(app2), "window.__visible", NULL);
    CHECK(vis && strcmp(vis, "1") == 0, "non-hidden child hit outside parent (got %s)", vis ? vis : "(null)");
    free(vis);

    nx_app_free(app2);
    snprintf(cmd2, sizeof(cmd2), "rm -rf %s", tmp2);
    if (system(cmd2) != 0) printf("note: could not remove %s\n", tmp2);

    nx_app_free(app);
    snprintf(cmd, sizeof(cmd), "rm -rf %s", tmp);
    if (system(cmd) != 0) printf("note: could not remove %s\n", tmp);

    printf("%d checks, %d failures\n", g_checks, g_failures);
    return g_failures == 0 ? 0 : 1;
}
