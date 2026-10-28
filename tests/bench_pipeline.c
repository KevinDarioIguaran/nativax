/*
    nativax_perf — reproducible pipeline diagnostics (debug laboratory).

    Measures, on the real C pipeline (no synthetic stand-in):

      * cold start: main() -> application loaded
      * time to first frame: main() -> first painted display list
      * phase breakdown from NxAppTimings (read/parse/collect/layout/script)
      * isolated phase loops: HTML parse, CSS parse, style+layout, paint,
        JavaScript execution
      * steady-state frame loop statistics (avg/p50/p95/max)
      * repeated document navigation: reload time and RSS growth
      * memory at each stage: RSS, VmHWM, native heap (GPU bytes are reported
        by the runtime in windowed mode; this tool is headless, so GPU=0)

    Output: one JSON object on stdout; with --out DIR it also writes
    perf-<timestamp>.json and appends a line to history.jsonl so runs stack up
    over time.

    This is pipeline cost, NOT display FPS: there is no compositor and no
    vsync here. Presented frame pacing (real FPS under vsync) is measured by
    the windowed runtime with `nativax-runtime --perf` (swap interval 1).
*/
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#include "nativax/app.h"
#include "nativax/css.h"
#include "nativax/dom.h"
#include "nativax/html.h"
#include "nativax/layout.h"
#include "nativax/meminfo.h"
#include "nativax/paint.h"

static double now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec * 1000.0 + (double)ts.tv_nsec / 1e6;
}

static char* read_file(const char* path, int* out_len) {
    FILE* f = fopen(path, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (size < 0 || size > 8 * 1024 * 1024) {
        fclose(f);
        return NULL;
    }
    char* buf = (char*)malloc((size_t)size + 1);
    if (!buf) {
        fclose(f);
        return NULL;
    }
    size_t rd = fread(buf, 1, (size_t)size, f);
    fclose(f);
    buf[rd] = '\0';
    if (out_len) *out_len = (int)rd;
    return buf;
}

static int cmp_double(const void* a, const void* b) {
    double x = *(const double*)a, y = *(const double*)b;
    return x < y ? -1 : (x > y ? 1 : 0);
}

static double pct(double* v, int n, double p) {
    if (n <= 0) return 0;
    qsort(v, (size_t)n, sizeof(double), cmp_double);
    int idx = (int)(p * (double)(n - 1) + 0.5);
    if (idx < 0) idx = 0;
    if (idx >= n) idx = n - 1;
    return v[idx];
}

int main(int argc, char** argv) {
    const char* root = NULL;
    const char* entry = "index.html";
    const char* out_dir = NULL;
    int frames = 120;
    int iters = 20;
    int nav = 20;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--root") == 0 && i + 1 < argc) root = argv[++i];
        else if (strcmp(argv[i], "--entry") == 0 && i + 1 < argc) entry = argv[++i];
        else if (strcmp(argv[i], "--out") == 0 && i + 1 < argc) out_dir = argv[++i];
        else if (strcmp(argv[i], "--frames") == 0 && i + 1 < argc) frames = atoi(argv[++i]);
        else if (strcmp(argv[i], "--iters") == 0 && i + 1 < argc) iters = atoi(argv[++i]);
        else if (strcmp(argv[i], "--nav") == 0 && i + 1 < argc) nav = atoi(argv[++i]);
        else {
            fprintf(stderr,
                    "usage: %s --root DIR [--entry FILE] [--frames N] [--iters N]\n"
                    "          [--nav N] [--out DIR]\n",
                    argv[0]);
            return 1;
        }
    }
    if (!root) {
        fprintf(stderr, "nativax_perf: --root is required\n");
        return 1;
    }
    if (iters < 1) iters = 1;
    if (frames < 1) frames = 1;
    if (nav < 1) nav = 1;

    double t_main = now_ms();
    long rss_start = nx_mem_rss_kb();

    /* ---- cold start: load the real application --------------------------- */
    NxAppConfig cfg;
    memset(&cfg, 0, sizeof(cfg));
    cfg.root = root;
    cfg.entry = entry;
    cfg.font_path = NATIVAX_SOURCE_DIR "/assets/fonts/DejaVuSans.ttf";
    cfg.width = 1024;
    cfg.height = 768;

    NxApp* app = nx_app_new(&cfg);
    char* err = NULL;
    if (!app || !nx_app_load(app, &err)) {
        fprintf(stderr, "nativax_perf: load failed: %s\n", err ? err : "unknown");
        free(err);
        nx_app_free(app);
        return 1;
    }
    free(err);
    double cold_start_ms = now_ms() - t_main;

    /* ---- time to first frame -------------------------------------------- */
    double t_first = now_ms();
    nx_app_update(app, 16.0);
    double first_frame_ms = now_ms() - t_main;
    (void)t_first;
    long rss_loaded = nx_mem_rss_kb();

    const NxAppTimings* lt = nx_app_timings(app);

    /* ---- isolated phase loops -------------------------------------------- */
    char html_path[2048];
    snprintf(html_path, sizeof(html_path), "%s/%s", root, entry);
    int html_len = 0;
    char* html = read_file(html_path, &html_len);

    double parse_total = 0, css_total = 0, layout_total = 0, paint_total = 0;
    int iters_used = iters;
    if (html) {
        for (int i = 0; i < iters; i++) {
            NxDocument* doc = nx_doc_new();
            double t0 = now_ms();
            if (!nx_html_parse(doc, html, html_len, NULL)) {
                nx_doc_free(doc);
                break;
            }
            parse_total += now_ms() - t0;

            /* CSS parse: the sheets the application itself declares */
            int sheet_count = 0;
            CsSheet* sheets[8];
            const CsSheet* csheets[8];
            NxNodeRef stack[512];
            int sp = 0;
            for (NxNodeRef c = nx_node_first_child(doc, nx_doc_root(doc)); c && sp < 512;
                 c = nx_node_next_sibling(doc, c))
                stack[sp++] = c;
            while (sp > 0 && sheet_count < 8) {
                NxNodeRef n = stack[--sp];
                if (nx_node_type(doc, n) != NX_NODE_ELEMENT) continue;
                const char* tag = nx_node_name(doc, n);
                if (strcmp(tag, "style") == 0) {
                    char* css = nx_node_text_content(doc, n);
                    if (css && *css) {
                        double t1 = now_ms();
                        CsSheet* sh = cs_sheet_parse(css, (int)strlen(css));
                        css_total += now_ms() - t1;
                        if (sh) {
                            sheets[sheet_count] = sh;
                            csheets[sheet_count] = sh;
                            sheet_count++;
                        }
                    }
                    free(css);
                } else if (strcmp(tag, "link") == 0) {
                    const char* rel = nx_node_get_attr(doc, n, "rel");
                    const char* href = nx_node_get_attr(doc, n, "href");
                    bool is_css = rel && href && *href &&
                                  strcasecmp(rel, "stylesheet") == 0;
                    if (is_css && sheet_count < 8) {
                        char css_path[2048];
                        snprintf(css_path, sizeof(css_path), "%s/%s", root, href);
                        int clen = 0;
                        char* cbuf = read_file(css_path, &clen);
                        if (cbuf) {
                            double t1 = now_ms();
                            CsSheet* sh = cs_sheet_parse(cbuf, clen);
                            css_total += now_ms() - t1;
                            if (sh) {
                                sheets[sheet_count] = sh;
                                csheets[sheet_count] = sh;
                                sheet_count++;
                            }
                            free(cbuf);
                        }
                    }
                }
                for (NxNodeRef c = nx_node_first_child(doc, n); c && sp < 512;
                     c = nx_node_next_sibling(doc, c))
                    stack[sp++] = c;
            }

            double t2 = now_ms();
            NxLayout* lay = nx_layout_build(doc, (const CsSheet* const*)csheets, sheet_count,
                                            1024, 768, 0);
            layout_total += now_ms() - t2;

            if (lay) {
                NxDisplayList dl;
                nx_dl_init(&dl);
                double t3 = now_ms();
                nx_paint(&dl, lay, 0);
                paint_total += now_ms() - t3;
                nx_dl_free(&dl);
                nx_layout_free(lay);
            }
            for (int k = 0; k < sheet_count; k++) cs_sheet_free(sheets[k]);
            nx_doc_free(doc);
        }
    } else {
        iters_used = 0;
    }

    /* ---- JavaScript execution ------------------------------------------- */
    double js_total = 0;
    int js_iters = iters;
    {
        NxJs* js = nx_js_new();
        if (js) {
            const char* workload =
                "(()=>{let s=0;for(let i=0;i<50000;i++){s=(s+i*7)%1000003;}return s;})()";
            /* warm up once (JSC compiles lazily) */
            char* werr = NULL;
            nx_js_eval(js, workload, "<warmup>", &werr);
            free(werr);
            for (int i = 0; i < js_iters; i++) {
                char* e = NULL;
                double t0 = now_ms();
                bool ok = nx_js_eval(js, workload, "<bench>", &e);
                js_total += now_ms() - t0;
                free(e);
                if (!ok) break;
            }
            nx_js_free(js);
        } else {
            js_iters = 0;
        }
    }

    /* ---- steady-state frame loop ----------------------------------------- */
    double* frame = (double*)malloc(sizeof(double) * (size_t)frames);
    double loop_start = now_ms();
    for (int i = 0; i < frames; i++) {
        nx_app_update(app, now_ms());
        frame[i] = nx_app_timings(app)->frame_ms;
    }
    double loop_ms = now_ms() - loop_start;

    /* ---- repeated navigation (reload churn) ------------------------------ */
    double nav_total = 0;
    for (int i = 0; i < nav; i++) {
        double t0 = now_ms();
        if (!nx_app_reload_document(app)) {
            /* reload failures are reported by the soak harness, not here */
            nav_total += now_ms() - t0;
            continue;
        }
        nx_app_update(app, now_ms());
        nav_total += now_ms() - t0;
    }

    const NxAppTimings* t = nx_app_timings(app);
    char* stats = nx_app_stats_json(app);

    /* summarize before freeing the samples */
    double frame_avg = frames ? loop_ms / frames : 0;
    double frame_p50 = pct(frame, frames, 0.50);
    double frame_p95 = pct(frame, frames, 0.95);
    double frame_max = pct(frame, frames, 1.0);

    printf("{\n"
           "  \"tool\": \"nativax_perf\",\n"
           "  \"root\": \"%s\",\n"
           "  \"entry\": \"%s\",\n"
           "  \"viewport\": [1024, 768],\n"
           "  \"cold_start_ms\": %.3f,\n"
           "  \"first_frame_ms\": %.3f,\n"
           "  \"load_phases_ms\": {\"read\": %.3f, \"parse\": %.3f, \"collect\": %.3f,"
           " \"style_layout\": %.3f, \"script\": %.3f, \"total\": %.3f},\n"
           "  \"isolated_ms_per_iter\": {\"html_parse\": %.4f, \"css_parse\": %.4f,"
           " \"style_layout\": %.4f, \"paint\": %.4f, \"js_exec\": %.4f},\n"
           "  \"isolated_iters\": {\"pipeline\": %d, \"js\": %d},\n"
           "  \"frames\": {\"n\": %d, \"wall_ms\": %.3f, \"avg_ms\": %.4f,"
           " \"p50_ms\": %.4f, \"p95_ms\": %.4f, \"max_ms\": %.4f},\n"
           "  \"last_phases_ms\": {\"restyle\": %.4f, \"relayout\": %.4f, \"paint\": %.4f},\n"
           "  \"navigation\": {\"reloads\": %d, \"avg_ms\": %.3f},\n"
           "  \"memory\": {\"rss_start_kb\": %ld, \"rss_loaded_kb\": %ld, \"rss_end_kb\": %ld,"
           " \"peak_rss_kb\": %ld, \"native_heap_bytes\": %lld,"
           " \"gpu_texture_bytes\": 0, \"gpu_buffer_bytes\": 0,"
           " \"js_heap_bytes\": null, \"js_heap_note\": \"unavailable: JSC C API\"},\n"
           "  \"app\": %s,\n"
           "  \"notes\": \"headless pipeline cost; no vsync/compositor, not display FPS; GPU"
           " bytes are 0 because no GPU context exists in this mode\"\n"
           "}\n",
           root, entry, cold_start_ms, first_frame_ms, lt->load_read_ms, lt->load_parse_ms,
           lt->load_collect_ms, lt->load_layout_ms, lt->load_script_ms, lt->load_total_ms,
           iters_used ? parse_total / iters_used : 0, iters_used ? css_total / iters_used : 0,
           iters_used ? layout_total / iters_used : 0, iters_used ? paint_total / iters_used : 0,
           js_iters ? js_total / js_iters : 0, iters_used, js_iters, frames, loop_ms, frame_avg,
           frame_p50, frame_p95, frame_max, t->restyle_ms, t->relayout_ms, t->paint_ms, nav,
           nav ? nav_total / nav : 0, rss_start, rss_loaded, nx_mem_rss_kb(), nx_mem_peak_kb(),
           nx_native_heap_bytes(), stats ? stats : "{}");
    free(stats);
    free(frame);
    free(html);

    /* ---- archive with history ------------------------------------------- */
    if (out_dir) {
        mkdir(out_dir, 0755);
        time_t now = time(NULL);
        struct tm tm_buf;
        localtime_r(&now, &tm_buf);
        char stamp[64];
        strftime(stamp, sizeof(stamp), "%Y%m%d-%H%M%S", &tm_buf);
        char path[2048];
        snprintf(path, sizeof(path), "%s/perf-%s.json", out_dir, stamp);
        FILE* f = fopen(path, "wb");
        if (f) {
            fprintf(f, "{\"id\":\"perf-%s\",\"root\":\"%s\",\"cold_start_ms\":%.3f,"
                       "\"first_frame_ms\":%.3f,\"frame_avg_ms\":%.4f,\"frame_p95_ms\":%.4f,"
                       "\"rss_peak_kb\":%ld,\"native_heap_bytes\":%lld}\n",
                    stamp, root, cold_start_ms, first_frame_ms, frame_avg, frame_p95,
                    nx_mem_peak_kb(), nx_native_heap_bytes());
            fclose(f);
            printf("perf report: %s\n", path);
            char hist[2148];
            snprintf(hist, sizeof(hist), "%s/history.jsonl", out_dir);
            FILE* h = fopen(hist, "ab");
            if (h) {
                fprintf(h, "{\"id\":\"perf-%s\",\"cold_start_ms\":%.3f,\"frame_avg_ms\":%.4f,"
                           "\"rss_peak_kb\":%ld}\n",
                        stamp, cold_start_ms, frame_avg, nx_mem_peak_kb());
                fclose(h);
            }
        } else {
            fprintf(stderr, "nativax_perf: cannot write %s\n", path);
        }
    }

    nx_app_free(app);
    return 0;
}
