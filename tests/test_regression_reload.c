/*
    Regression tests for a real ASan finding (phase 1 diagnostics).

    Bug: paint consumed text pointers borrowed by the layout while script
    mutations had already freed those nodes, so a `textContent` write during
    load/reload followed by a paint was a heap-use-after-free in
    nx_utf8_decode (report: debug/reports/phase1-report.md).

    Root cause: repaint() was reachable with a stale layout — nx_app_load even
    discarded the dirty flag right after running scripts. Fix: a valid layout
    is a precondition of repaint(), and script mutations keep the flag set.

    Under AddressSanitizer these cases abort on the old code and pass on the
    fixed code; without sanitizers they still assert the observable behaviour
    (text updated, display list rebuilt, app still usable after a failed
    reload).
*/
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "nativax/app.h"
#include "nativax/dom.h"
#include "nativax/layout.h"

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

static void write_file(const char* path, const char* data) {
    FILE* f = fopen(path, "wb");
    if (!f) {
        printf("FAIL cannot write %s\n", path);
        exit(1);
    }
    fputs(data, f);
    fclose(f);
}

static char* text_of(NxApp* app, const char* id) {
    NxDocument* doc = nx_app_doc(app);
    NxNodeRef n = nx_doc_get_element_by_id(doc, id);
    if (!n) return NULL;
    return nx_node_text_content(doc, n);
}

int main(void) {
    char dir[256];
    snprintf(dir, sizeof(dir), "/tmp/nativax-regress-%d", (int)getpid());
    char cmd[2048];
    snprintf(cmd, sizeof(cmd), "rm -rf %s && mkdir -p %s", dir, dir);
    if (system(cmd) != 0) {
        printf("FAIL cannot stage %s\n", dir);
        return 1;
    }

    char html_path[512], js_path[512];
    snprintf(html_path, sizeof(html_path), "%s/index.html", dir);
    snprintf(js_path, sizeof(js_path), "%s/app.js", dir);

    /* --- case 1: script writes textContent BEFORE the first paint --------- */
    write_file(html_path,
               "<html><head><style>p { font-size: 14px; }</style></head>"
               "<body><p id=\"a\">original</p>"
               "<script src=\"app.js\"></script></body></html>");
    write_file(js_path,
               "document.getElementById('a').textContent = 'set at load time';\n");

    NxAppConfig cfg;
    memset(&cfg, 0, sizeof(cfg));
    cfg.root = dir;
    cfg.entry = "index.html";
    cfg.font_path = NATIVAX_SOURCE_DIR "/assets/fonts/DejaVuSans.ttf";
    cfg.width = 640;
    cfg.height = 480;

    NxApp* app = nx_app_new(&cfg);
    char* err = NULL;
    CHECK(app && nx_app_load(app, &err), "load: %s", err ? err : "ok");
    free(err);
    if (!app) return 1;
    nx_app_update(app, 16.0); /* paint after load-time mutation */

    char* text = text_of(app, "a");
    CHECK(text && strcmp(text, "set at load time") == 0, "load-time mutation visible: %s",
          text ? text : "(null)");
    free(text);
    CHECK(nx_app_list(app)->vert_count > 0, "display list painted (%u verts)",
          nx_app_list(app)->vert_count);

    /* --- case 2: repeated destroy+recreate then paint ---------------------- */
    write_file(js_path,
               "var a = document.getElementById('a');\n"
               "a.textContent = 'v1';\n"
               "for (var i = 0; i < 20; i++) {\n"
               "  var d = document.createElement('div');\n"
               "  d.id = 't' + i;\n"
               "  d.textContent = 'node ' + i;\n"
               "  document.body.appendChild(d);\n"
               "}\n"
               "for (var i = 0; i < 20; i++) {\n"
               "  var d = document.getElementById('t' + i);\n"
               "  if (d) d.remove();\n"
               "}\n"
               "a.textContent = 'v2';\n");
    CHECK(nx_app_reload_js(app), "js reload with create/destroy churn");
    nx_app_update(app, 33.0);
    text = text_of(app, "a");
    CHECK(text && strcmp(text, "v2") == 0, "text after churn: %s", text ? text : "(null)");
    free(text);

    /* --- case 3: document reload whose script rewrites text ---------------- */
    write_file(html_path,
               "<html><body><h1 id=\"a\">first</h1>"
               "<script>document.getElementById('a').textContent = 'reloaded';</script>"
               "</body></html>");
    CHECK(nx_app_reload_document(app), "document reload with load-time mutation");
    nx_app_update(app, 49.0);
    text = text_of(app, "a");
    CHECK(text && strcmp(text, "reloaded") == 0, "reload mutation visible: %s",
          text ? text : "(null)");
    free(text);

    /* --- case 4: failed reload (entry removed) keeps the app paintable ----- */
    snprintf(cmd, sizeof(cmd), "rm -f %s", html_path);
    if (system(cmd) != 0) printf("note: cannot remove %s\n", html_path);
    CHECK(!nx_app_reload_document(app), "missing entry fails the reload");
    nx_app_update(app, 65.0);
    text = text_of(app, "a");
    CHECK(text && strcmp(text, "reloaded") == 0, "previous DOM kept after failed reload: %s",
          text ? text : "(null)");
    free(text);
    CHECK(nx_app_list(app)->vert_count > 0, "still painting after failed reload");

    /* --- case 5: css reload right after a text mutation ------------------- */
    write_file(html_path,
               "<html><body><p id=\"a\">text</p></body></html>");
    CHECK(nx_app_reload_document(app), "reload back to a small document");
    write_file(js_path, "");
    char* err2 = NULL;
    (void)err2;
    CHECK(nx_app_reload_css(app), "css reload after DOM change");
    nx_app_update(app, 81.0);
    CHECK(nx_app_list(app)->vert_count > 0, "display list after css reload");

    /* --- case 6: 300 document reloads must not leak slot-pool entries ----- */
    /* Regression for a soak finding: nx_html_parse cleared the previous tree
       with nx_node_remove_child (detach only), so every reparse leaked the
       whole old subtree in the slot pool (~244 slots per reload: 400 reloads
       reached 97645 of NX_MAX_NODES=100000, at which point the parser can no
       longer allocate nodes). Destroyed slots must return to the freelist and
       be reused by the next parse. */
    write_file(html_path,
               "<html><body><div id=\"a\">reload slot churn"
               "<span>inner</span><b>bold</b></div></body></html>");
    int baseline_slots = 0;
    int max_slots = 0;
    for (int i = 0; i < 300; i++) {
        if (!nx_app_reload_document(app)) {
            CHECK(false, "slot-churn reload %d", i);
            break;
        }
        int slots = nx_node_slot_bound(nx_app_doc(app));
        if (i == 0) baseline_slots = slots;
        if (slots > max_slots) max_slots = slots;
    }
    CHECK(baseline_slots > 3, "document has nodes (%d)", baseline_slots);
    CHECK(max_slots < 2 * baseline_slots + 128,
          "slot pool bounded over 300 reloads (baseline %d, max %d)", baseline_slots,
          max_slots);
    nx_app_update(app, 97.0);
    text = text_of(app, "a");
    CHECK(text && strstr(text, "reload slot churn") != NULL, "content after churn: %s",
          text ? text : "(null)");
    free(text);

    nx_app_free(app);
    snprintf(cmd, sizeof(cmd), "rm -rf %s", dir);
    if (system(cmd) != 0) printf("note: cannot remove %s\n", dir);

    printf("%d checks, %d failures\n", g_checks, g_failures);
    return g_failures == 0 ? 0 : 1;
}
