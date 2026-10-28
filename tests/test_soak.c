/*
    Soak / stability harness for the native runtime (debug laboratory).

    Exercises the paths that historically leak or corrupt state:

      1. repeated document parse + destroy (no leak, no use-after-free)
      2. repeated application load failures (missing entry, bad script,
         missing stylesheet, malformed HTML) — errors must be reported,
         never crash or corrupt the document
      3. repeated CSS / JS / document hot reloads on the same app
      4. DOM churn through script (create + destroy) — the node slot pool
         must stabilize instead of growing without bound
      5. full teardown of app, JS context, layout and display list

    Every phase records RSS, VmHWM and the glibc heap (mallinfo2) so the
    report distinguishes process RSS from native heap. JavaScript heap size
    is NOT reported: the JavaScriptCoreGTK C API exposes no heap statistic.

    Configuration (environment):
      NATIVAX_SOAK_CYCLES   iterations per churn phase (default 8, ctest)
      NATIVAX_SOAK_JSON     path for a JSON report (optional)

    Run long: NATIVAX_SOAK_CYCLES=300 ./nativax_soak_tests
*/
#include <malloc.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "nativax/app.h"
#include "nativax/css.h"
#include "nativax/dom.h"
#include "nativax/html.h"
#include "nativax/js_dom.h"
#include "nativax/js_engine.h"
#include "nativax/meminfo.h"

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

static int cycles(void) {
    const char* env = getenv("NATIVAX_SOAK_CYCLES");
    int n = env ? atoi(env) : 8;
    return n > 0 ? n : 8;
}

/* native heap in use (bytes); -1 when the platform has no mallinfo2. */
static long long heap_bytes(void) { return nx_native_heap_bytes(); }

static void write_file(const char* path, const char* data) {
    FILE* f = fopen(path, "wb");
    if (!f) {
        printf("FAIL cannot write %s\n", path);
        exit(1);
    }
    fputs(data, f);
    fclose(f);
}

static const char* PAGE =
    "<!DOCTYPE html><html><head><style>"
    "body { margin: 0; font-size: 14px; }"
    ".card { width: 60%; padding: 8px; background: #ffffff; }"
    "</style></head><body><div class=\"card\"><p id=\"p\">soak</p></div></body></html>";

/* ---- 1. document parse/destroy churn ------------------------------------- */
static void phase_documents(int n) {
    long long before = heap_bytes();
    long long before_slots = 0;
    for (int i = 0; i < n; i++) {
        NxDocument* doc = nx_doc_new();
        char* err = NULL;
        bool ok = nx_html_parse(doc, PAGE, (int)strlen(PAGE), &err);
        CHECK(ok, "parse cycle %d: %s", i, err ? err : "ok");
        free(err);
        if (ok) {
            before_slots = nx_node_slot_bound(doc);
            CHECK(before_slots > 3, "document has nodes (%lld)", before_slots);
            /* style resolution over the live document */
            CsSheet* sheet = cs_sheet_parse("p { color: #111111; }", 20);
            const CsSheet* sheets[1] = {sheet};
            NxComputedStyle* styles = nx_style_resolve(doc, sheets, 1, 800.0f, 16.0f);
            CHECK(styles != NULL, "style resolve in cycle %d", i);
            free(styles);
            cs_sheet_free(sheet);
        }
        nx_doc_free(doc);
    }
    long long after = heap_bytes();
    if (before >= 0 && after >= 0) {
        long long growth = after - before;
        /* bounded: a few hundred bytes of allocator noise, not O(n) */
        CHECK(growth < 65536, "document churn heap growth %lld bytes over %d cycles", growth, n);
        printf("soak documents: cycles=%d heap_delta=%lld bytes\n", n, growth);
    }
}

/* ---- 2. application load-failure matrix ---------------------------------- */
static void phase_load_failures(int n) {
    char dir[256];
    snprintf(dir, sizeof(dir), "/tmp/nativax-soak-fail-%d", (int)getpid());
    char cmd[2048];
    snprintf(cmd, sizeof(cmd), "rm -rf %s && mkdir -p %s", dir, dir);
    if (system(cmd) != 0) {
        printf("FAIL cannot create %s\n", dir);
        return;
    }

    for (int i = 0; i < n; i++) {
        /* missing entry document */
        NxAppConfig cfg;
        memset(&cfg, 0, sizeof(cfg));
        cfg.root = dir;
        cfg.entry = "nope.html";
        cfg.font_path = NATIVAX_SOURCE_DIR "/assets/fonts/DejaVuSans.ttf";
        cfg.width = 320;
        cfg.height = 200;
        NxApp* app = nx_app_new(&cfg);
        char* err = NULL;
        CHECK(app != NULL, "app allocation for missing entry");
        CHECK(!nx_app_load(app, &err), "missing entry must fail (cycle %d)", i);
        CHECK(err != NULL, "failure reports an error message (cycle %d)", i);
        free(err);
        nx_app_free(app);

        /* entry that exists but whose script throws, plus a missing stylesheet */
        char html_path[512], js_path[512], css_path[512];
        snprintf(html_path, sizeof(html_path), "%s/index.html", dir);
        snprintf(js_path, sizeof(js_path), "%s/app.js", dir);
        snprintf(css_path, sizeof(css_path), "%s/missing.css", dir);
        char body[1024];
        snprintf(body, sizeof(body),
                 "<html><head><link rel=\"stylesheet\" href=\"missing.css\"></head>"
                 "<body><div id=\"d\">before</div>"
                 "<script src=\"app.js\"></script>"
                 "<script src=\"gone.js\"></script></body></html>");
        write_file(html_path, body);
        write_file(js_path, "throw new Error('intentional script failure');\n"
                            "document.getElementById('d').textContent = 'never';\n");

        cfg.entry = "index.html";
        NxApp* app2 = nx_app_new(&cfg);
        char* err2 = NULL;
        bool loaded = nx_app_load(app2, &err2);
        free(err2);
        CHECK(loaded, "app survives a throwing script and missing assets (cycle %d)", i);
        if (loaded) {
            nx_app_update(app2, 16.0);
            NxDocument* doc = nx_app_doc(app2);
            NxNodeRef d = nx_doc_get_element_by_id(doc, "d");
            char* text = nx_node_text_content(doc, d);
            /* the script threw before its first statement completed */
            CHECK(text && strcmp(text, "before") == 0,
                  "DOM untouched by failing script: %s", text ? text : "(null)");
            free(text);
            nx_app_update(app2, 33.0);
        }
        nx_app_free(app2);

        /* malformed HTML: parser must not crash; outcome may be partial */
        write_file(html_path, "<html><body><div><p>unclosed<span></body>");
        NxAppConfig cfg3 = cfg;
        NxApp* app3 = nx_app_new(&cfg3);
        char* err3 = NULL;
        bool ok3 = nx_app_load(app3, &err3);
        free(err3);
        if (ok3) nx_app_update(app3, 16.0);
        nx_app_free(app3);

        /* completely empty document */
        write_file(html_path, "");
        NxApp* app4 = nx_app_new(&cfg3);
        char* err4 = NULL;
        bool ok4 = nx_app_load(app4, &err4);
        free(err4);
        if (ok4) nx_app_update(app4, 16.0);
        nx_app_free(app4);
    }
    snprintf(cmd, sizeof(cmd), "rm -rf %s", dir);
    if (system(cmd) != 0) printf("note: cannot remove %s\n", dir);
    printf("soak load-failures: cycles=%d ok\n", n);
}

/* ---- 3. hot reload churn + 4. DOM churn + 5. teardown --------------------- */
static void phase_reloads(int n) {
    char dir[256];
    snprintf(dir, sizeof(dir), "/tmp/nativax-soak-reload-%d", (int)getpid());
    char cmd[2048];
    snprintf(cmd, sizeof(cmd), "rm -rf %s && cp -r %s/examples/counter %s", dir,
             NATIVAX_SOURCE_DIR, dir);
    if (system(cmd) != 0) {
        printf("FAIL cannot stage example app\n");
        return;
    }

    long long heap_before = heap_bytes();
    long long rss_before = nx_mem_rss_kb();
    long long peak_before = nx_mem_peak_kb();

    NxAppConfig cfg;
    memset(&cfg, 0, sizeof(cfg));
    cfg.root = dir;
    cfg.entry = "index.html";
    cfg.font_path = NATIVAX_SOURCE_DIR "/assets/fonts/DejaVuSans.ttf";
    cfg.width = 800;
    cfg.height = 600;

    NxApp* app = nx_app_new(&cfg);
    char* err = NULL;
    CHECK(app && nx_app_load(app, &err), "load staged app: %s", err ? err : "ok");
    free(err);
    if (!app) goto cleanup;

    char css_path[512], js_path[512];
    snprintf(css_path, sizeof(css_path), "%s/style.css", dir);
    snprintf(js_path, sizeof(js_path), "%s/app.js", dir);

    int slots_max = 0;
    int baseline_slots = -1;
    for (int i = 0; i < n; i++) {
        char css[1024];
        snprintf(css, sizeof(css),
                 "body { margin: 0; background: #ffffff; }\n"
                 ".card { width: %d%%; padding: 12px; background: #ffffff; }\n",
                 40 + (i % 5));
        write_file(css_path, css);

        char js[512];
        snprintf(js, sizeof(js),
                 "var el = document.getElementById('count');\n"
                 "el.textContent = 'cycle %d';\n"
                 "for (var i = 0; i < 50; i++) {\n"
                 "  var d = document.createElement('div');\n"
                 "  d.id = 'tmp' + i;\n"
                 "  d.textContent = 'x';\n"
                 "  document.body.appendChild(d);\n"
                 "}\n"
                 "for (var i = 0; i < 50; i++) {\n"
                 "  var d = document.getElementById('tmp' + i);\n"
                 "  if (d) d.remove();\n"
                 "}\n",
                 i);
        write_file(js_path, js);

        CHECK(nx_app_reload_css(app), "css reload cycle %d", i);
        nx_app_update(app, (double)(i * 3 + 1) * 16.7);
        int s_css = nx_node_slot_bound(nx_app_doc(app));
        CHECK(nx_app_reload_js(app), "js reload cycle %d", i);
        nx_app_update(app, (double)(i * 3 + 2) * 16.7);
        int s_js = nx_node_slot_bound(nx_app_doc(app));
        CHECK(nx_app_reload_document(app), "document reload cycle %d", i);
        nx_app_update(app, (double)(i * 3 + 3) * 16.7);
        int s_doc = nx_node_slot_bound(nx_app_doc(app));
        if (i < 3 || i == n - 1)
            printf("soak phase-slots cycle %d: css=%d js=%d doc=%d\n", i, s_css, s_js, s_doc);

        char* stats = nx_app_stats_json(app);
        CHECK(stats && strstr(stats, "\"loaded\":true") != NULL, "app loaded after cycle %d", i);
        free(stats);

        int slots = nx_node_slot_bound(nx_app_doc(app));
        if (i == 0) baseline_slots = slots;
        if (slots > slots_max) slots_max = slots;
    }

    /* the slot pool must not grow with reload count. Baseline is the FIRST
       cycle (the old check compared against the final count, which itself
       grows with n and therefore passed trivially while the leak was there). */
    int end_slots = nx_node_slot_bound(nx_app_doc(app));
    CHECK(end_slots > 3, "document still has nodes (%d)", end_slots);
    CHECK(slots_max < 2 * baseline_slots + 256,
          "slot pool bounded across %d reload cycles (baseline %d, max %d, final %d)", n,
          baseline_slots, slots_max, end_slots);

    long long heap_after = heap_bytes();
    long long rss_after = nx_mem_rss_kb();
    long long peak_after = nx_mem_peak_kb();
    printf("soak reloads: cycles=%d rss %lld -> %lld kB, peak %lld -> %lld kB, heap %lld -> %lld bytes, "
           "slots_max=%d\n",
           n, rss_before, rss_after, peak_before, peak_after, heap_before, heap_after, slots_max);
    if (heap_before >= 0 && heap_after >= 0)
        CHECK(heap_after - heap_before < 64LL * 1024 * 1024,
              "heap growth over reload churn %lld bytes", heap_after - heap_before);

cleanup:
    nx_app_free(app);
    snprintf(cmd, sizeof(cmd), "rm -rf %s", dir);
    if (system(cmd) != 0) printf("note: cannot remove %s\n", dir);
}

/* Repeated full construction/teardown: catches leaks in the JS context, the
   bindings, the layout and the display list. */
static void phase_teardown(int n) {
    char dir[256];
    snprintf(dir, sizeof(dir), "/tmp/nativax-soak-teardown-%d", (int)getpid());
    char cmd[2048];
    snprintf(cmd, sizeof(cmd), "rm -rf %s && cp -r %s/examples/counter %s", dir,
             NATIVAX_SOURCE_DIR, dir);
    if (system(cmd) != 0) {
        printf("FAIL cannot stage example app\n");
        return;
    }
    long long heap_before = heap_bytes();
    for (int i = 0; i < n; i++) {
        NxAppConfig cfg;
        memset(&cfg, 0, sizeof(cfg));
        cfg.root = dir;
        cfg.entry = "index.html";
        cfg.font_path = NATIVAX_SOURCE_DIR "/assets/fonts/DejaVuSans.ttf";
        cfg.width = 640;
        cfg.height = 480;
        NxApp* app = nx_app_new(&cfg);
        char* err = NULL;
        CHECK(app && nx_app_load(app, &err), "teardown cycle %d load", i);
        free(err);
        if (app) {
            nx_app_update(app, 16.0);
            nx_app_pointer(app, 50.0f, 50.0f, true);
            nx_app_update(app, 33.0);
            nx_app_free(app);
        }
    }
    long long heap_after = heap_bytes();
    if (heap_before >= 0 && heap_after >= 0) {
        CHECK(heap_after - heap_before < 32LL * 1024 * 1024,
              "teardown heap growth %lld bytes over %d cycles", heap_after - heap_before, n);
        printf("soak teardown: cycles=%d heap_delta=%lld bytes rss=%ld kB peak=%ld kB\n", n,
               heap_after - heap_before, nx_mem_rss_kb(), nx_mem_peak_kb());
    }
    snprintf(cmd, sizeof(cmd), "rm -rf %s", dir);
    if (system(cmd) != 0) printf("note: cannot remove %s\n", dir);
}

int main(void) {
    int n = cycles();
    long long heap0 = heap_bytes();
    long rss0 = nx_mem_rss_kb();

    printf("soak start: cycles=%d rss=%ld kB peak=%ld kB heap=%lld bytes\n", n, rss0,
           nx_mem_peak_kb(), heap0);

    phase_documents(n * 50 > 400 ? 400 : n * 50);
    phase_load_failures(n > 6 ? 6 : n);
    phase_reloads(n);
    phase_teardown(n > 12 ? 12 : n);

    long rss1 = nx_mem_rss_kb();
    long peak = nx_mem_peak_kb();
    long long heap1 = heap_bytes();
    printf("soak end: rss=%ld kB peak=%ld kB heap=%lld bytes\n", rss1, peak, heap1);

    const char* json_path = getenv("NATIVAX_SOAK_JSON");
    if (json_path) {
        FILE* f = fopen(json_path, "wb");
        if (f) {
            fprintf(f,
                    "{\"tool\":\"soak\",\"cycles\":%d,\"checks\":%d,\"failures\":%d,"
                    "\"rss_start_kb\":%ld,\"rss_end_kb\":%ld,\"peak_rss_kb\":%ld,"
                    "\"heap_start_bytes\":%lld,\"heap_end_bytes\":%lld,"
                    "\"js_heap\":\"unavailable: JavaScriptCoreGTK C API exposes no heap "
                    "statistic\"}\n",
                    n, g_checks, g_failures, rss0, rss1, peak, heap0, heap1);
            fclose(f);
            printf("soak report: %s\n", json_path);
        }
    }

    printf("%d checks, %d failures\n", g_checks, g_failures);
    return g_failures == 0 ? 0 : 1;
}
