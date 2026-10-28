/*
    NativaX runtime — native entry point.

    Owns the frame clock and the development client. The HTML/CSS/JS pipeline
    lives in app.c; window creation, input and platform services come from
    nativax/platform.h (backend: platform_sokol.c). The painted display list is
    presented through Sokol GFX.

    Modes:
      windowed   native window + GPU presentation (default)
      --headless run the full pipeline with the CPU rasterizer (CI, no display)
      --dev URL  connect to the development server for hot reload
*/
#include "nativax/app.h"
#include "nativax/display_list.h"
#include "nativax/gfx.h"
#include "nativax/hotreload.h"
#include "nativax/log.h"
#include "nativax/meminfo.h"
#include "nativax/platform.h"
#include "nativax/raster.h"
#include "nativax/text.h"
#include "sokol_gfx.h"
#include "sokol_glue.h"
#include "sokol_log.h"

#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "stb_image_write.h"

typedef struct AppState {
    const char* root;
    const char* entry;
    const char* screenshot;
    const char* dev_url;
    int max_frames;
    int frame_count;
    int width, height; /* CSS px */
    bool deterministic;
    bool stats;
    bool mem;
    bool perf;
    /* presented-frame pacing (--perf): delta between consecutive frame_cb
       invocations under vsync (swap_interval 1) — this is real presentation
       cadence, not renderer throughput. */
    double* frame_delta_ms;
    int frame_delta_count, frame_delta_cap;
    double last_frame_ts;
    bool perf_have_prev;
    bool gfx_up;
    float dpi;
    long rss_start_kb;
    long rss_loaded_kb;
    NxApp* app;
    NxHotReload* hr;
    double start_ms;
} AppState;

static AppState g_state;

static double now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec * 1000.0 + (double)ts.tv_nsec / 1e6;
}

/* ---- hot reload ---------------------------------------------------------- */

static void on_reload(const char* json, void* user) {
    NxApp* app = (NxApp*)user;
    if (strstr(json, "\"kind\":\"css\"")) {
        NX_INFO("hot reload: css -> styles + layout rebuilt (DOM/JS state kept)");
        nx_app_reload_css(app);
    } else if (strstr(json, "\"kind\":\"js\"")) {
        NX_INFO("hot reload: js -> fresh context, scripts re-run (DOM kept)");
        nx_app_reload_js(app);
    } else {
        NX_INFO("hot reload: %s -> full document reload", json);
        nx_app_reload_document(app);
    }
}

/* ---- screenshots --------------------------------------------------------- */

static void take_screenshot(void) {
    if (!g_state.screenshot) return;
    int fb_w = nx_platform_framebuffer_width();
    int fb_h = nx_platform_framebuffer_height();
    uint8_t* px = malloc((size_t)fb_w * (size_t)fb_h * 4);
    if (!px) return;
    if (nx_platform_read_pixels(px, fb_w, fb_h)) {
        if (stbi_write_png(g_state.screenshot, fb_w, fb_h, 4, px, fb_w * 4))
            NX_INFO("screenshot written: %s (%dx%d)", g_state.screenshot, fb_w, fb_h);
        else
            NX_ERROR("screenshot write failed: %s", g_state.screenshot);
    } else {
        NX_ERROR("framebuffer readback failed");
    }
    free(px);
}

/* ---- platform callbacks -------------------------------------------------- */

static void init_cb(void* user) {
    (void)user;
    sg_setup(&(sg_desc){
        .environment = sglue_environment(),
        .logger.func = slog_func,
    });
    nx_gfx_init();
    g_state.gfx_up = true;

    g_state.dpi = g_state.deterministic ? 1.0f : nx_platform_dpi();
    g_state.width = nx_platform_width();
    g_state.height = nx_platform_height();

    NxAppConfig cfg;
    memset(&cfg, 0, sizeof(cfg));
    cfg.root = g_state.root;
    cfg.entry = g_state.entry;
    cfg.font_path = NATIVAX_SOURCE_DIR "/assets/fonts/DejaVuSans.ttf";
    cfg.width = g_state.width;
    cfg.height = g_state.height;
    g_state.app = nx_app_new(&cfg);
    char* err = NULL;
    if (!g_state.app || !nx_app_load(g_state.app, &err)) {
        NX_ERROR("failed to load application: %s", err ? err : "unknown");
        free(err);
        nx_platform_quit();
        return;
    }
    free(err);
    g_state.rss_loaded_kb = nx_mem_rss_kb();
    nx_app_set_dpi(g_state.app, g_state.dpi);
    nx_app_update(g_state.app, now_ms() - g_state.start_ms);

    if (g_state.dev_url) g_state.hr = nx_hot_reload_connect(g_state.dev_url, on_reload, g_state.app);
    NX_INFO("runtime ready: %s/%s (%dx%d css px, dpi %.2f)", g_state.root, g_state.entry,
            g_state.width, g_state.height, g_state.dpi);
}

static void frame_cb(void* user) {
    (void)user;
    if (!g_state.app) return;
    if (g_state.hr) nx_hot_reload_poll(g_state.hr);

    if (g_state.perf) {
        double ts = now_ms();
        if (g_state.perf_have_prev) {
            if (g_state.frame_delta_count == g_state.frame_delta_cap) {
                int cap = g_state.frame_delta_cap ? g_state.frame_delta_cap * 2 : 4096;
                double* p = (double*)realloc(g_state.frame_delta_ms, sizeof(double) * (size_t)cap);
                if (p) {
                    g_state.frame_delta_ms = p;
                    g_state.frame_delta_cap = cap;
                }
            }
            if (g_state.frame_delta_count < g_state.frame_delta_cap) {
                g_state.frame_delta_ms[g_state.frame_delta_count++] = ts - g_state.last_frame_ts;
            }
        }
        g_state.last_frame_ts = ts;
        g_state.perf_have_prev = true;
    }

    nx_app_update(g_state.app, now_ms() - g_state.start_ms);

    int fb_w = nx_platform_framebuffer_width();
    int fb_h = nx_platform_framebuffer_height();
    nx_gfx_sync_textures();
    const float clear[4] = {1.0f, 1.0f, 1.0f, 1.0f};
    nx_gfx_render(nx_app_list(g_state.app), fb_w, fb_h, clear);
    sg_commit();

    g_state.frame_count++;
    if (g_state.screenshot && g_state.frame_count == 3) take_screenshot();
    if (g_state.max_frames > 0 && g_state.frame_count >= g_state.max_frames) {
        NX_INFO("frame budget reached (%d), quitting", g_state.max_frames);
        nx_platform_quit();
    }
}

static void print_mem_report(void) {
    /* RSS and native heap are process memory; gpu_* are renderer-side
       allocations reported by sokol gfx and are NOT part of RSS. The
       JavaScript heap cannot be read: JavaScriptCoreGTK's C API exposes no
       heap statistic (documented limitation). */
    const NxGfxStats* gfx = nx_gfx_stats();
    printf("{\"rss_start_kb\":%ld,\"rss_after_load_kb\":%ld,\"rss_kb\":%ld,"
           "\"peak_rss_kb\":%ld,\"native_heap_bytes\":%lld,"
           "\"gpu_texture_bytes\":%lld,\"gpu_buffer_bytes\":%lld,"
           "\"js_heap_bytes\":null,\"js_heap_note\":\"unavailable: JSC C API\","
           "\"frames\":%d}\n",
           g_state.rss_start_kb, g_state.rss_loaded_kb, nx_mem_rss_kb(), nx_mem_peak_kb(),
           nx_native_heap_bytes(), g_state.gfx_up ? gfx->texture_bytes : 0,
           g_state.gfx_up ? gfx->buffer_bytes : 0, g_state.frame_count);
}

/* Presented-frame pacing report: distribution of real frame-to-frame deltas
   observed while vsync was active. This is NOT renderer throughput: with
   swap_interval 1 the cadence is bounded by the display refresh, so a slow
   frame shows up as a long delta (jank) instead of a higher FPS. Driver-side
   present latency (submit -> scanout) cannot be read from this API level and
   is a documented limitation. */
static int cmp_dbl(const void* a, const void* b) {
    double x = *(const double*)a, y = *(const double*)b;
    return x < y ? -1 : (x > y ? 1 : 0);
}

static void print_perf_report(void) {
    int n = g_state.frame_delta_count;
    if (n <= 0) {
        printf("{\"perf\":true,\"frames\":0,\"note\":\"no inter-frame deltas"
               " (need --frames N >= 2)\"}\n");
        return;
    }
    double sum = 0, worst = 0;
    int missed = 0;
    for (int i = 0; i < n; i++) {
        double d = g_state.frame_delta_ms[i];
        sum += d;
        if (d > worst) worst = d;
        if (d > 16.67 * 1.5) missed++; /* > 1.5x budget = dropped refresh */
    }
    double* sorted = (double*)malloc(sizeof(double) * (size_t)n);
    if (!sorted) return;
    memcpy(sorted, g_state.frame_delta_ms, sizeof(double) * (size_t)n);
    qsort(sorted, (size_t)n, sizeof(double), cmp_dbl);
    double p50 = sorted[(int)(0.50 * (n - 1))];
    double p95 = sorted[(int)(0.95 * (n - 1))];
    double avg = sum / n;
    printf("{\"perf\":true,\"vsync\":true,\"deltas\":%d,\"avg_ms\":%.3f,"
           "\"p50_ms\":%.3f,\"p95_ms\":%.3f,\"max_ms\":%.3f,"
           "\"presented_fps\":%.2f,\"missed_frame_percent\":%.2f,"
           "\"budget_ms\":16.67}\n",
           n, avg, p50, p95, worst, avg > 0 ? 1000.0 / avg : 0.0,
           100.0 * (double)missed / (double)n);
    free(sorted);
}

static void cleanup_cb(void* user) {
    (void)user;
    if (g_state.hr) nx_hot_reload_free(g_state.hr);
    if (g_state.mem) print_mem_report();
    if (g_state.perf) print_perf_report();
    if (g_state.stats && g_state.app) {
        char* json = nx_app_stats_json(g_state.app);
        if (json) {
            printf("%s\n", json);
            free(json);
        }
    }
    nx_gfx_shutdown();
    nx_app_free(g_state.app);
    g_state.app = NULL;
    free(g_state.frame_delta_ms);
    g_state.frame_delta_ms = NULL;
    nx_font_reset();
    nx_tex_reset_all();
    sg_shutdown();
    NX_INFO("runtime shut down cleanly after %d frames", g_state.frame_count);
}

static void event_cb(const NxPlatformEvent* ev, void* user) {
    (void)user;
    switch (ev->type) {
        case NX_PLATFORM_EVENT_RESIZE:
            g_state.width = ev->window_width;
            g_state.height = ev->window_height;
            if (!g_state.deterministic) g_state.dpi = ev->dpi;
            if (g_state.app) nx_app_set_viewport(g_state.app, g_state.width, g_state.height);
            if (g_state.app) nx_app_set_dpi(g_state.app, g_state.dpi);
            NX_DEBUG("resize: %dx%d css px (fb %dx%d, dpi %.2f)", ev->window_width,
                     ev->window_height, ev->framebuffer_width, ev->framebuffer_height, ev->dpi);
            break;
        case NX_PLATFORM_EVENT_KEY_DOWN:
            if (ev->key == NX_KEY_ESCAPE) nx_platform_quit();
            if (g_state.app) nx_app_key(g_state.app, ev->key, true);
            break;
        case NX_PLATFORM_EVENT_KEY_UP:
            if (g_state.app) nx_app_key(g_state.app, ev->key, false);
            break;
        case NX_PLATFORM_EVENT_POINTER_DOWN:
        case NX_PLATFORM_EVENT_TOUCH_BEGIN:
            if (g_state.app) nx_app_pointer(g_state.app, ev->x, ev->y, true);
            break;
        case NX_PLATFORM_EVENT_POINTER_MOVE:
        case NX_PLATFORM_EVENT_TOUCH_MOVE:
            if (g_state.app) nx_app_pointer_move(g_state.app, ev->x, ev->y);
            break;
        case NX_PLATFORM_EVENT_POINTER_UP:
        case NX_PLATFORM_EVENT_TOUCH_END:
            if (g_state.app) nx_app_pointer(g_state.app, ev->x, ev->y, false);
            break;
        case NX_PLATFORM_EVENT_QUIT_REQUESTED:
            nx_platform_quit();
            break;
        default:
            break;
    }
}

/* ---- headless ------------------------------------------------------------ */

static int run_headless(void) {
    NxAppConfig cfg;
    memset(&cfg, 0, sizeof(cfg));
    cfg.root = g_state.root;
    cfg.entry = g_state.entry;
    cfg.font_path = NATIVAX_SOURCE_DIR "/assets/fonts/DejaVuSans.ttf";
    cfg.width = g_state.width;
    cfg.height = g_state.height;

    NxApp* app = nx_app_new(&cfg);
    char* err = NULL;
    if (!app || !nx_app_load(app, &err)) {
        fprintf(stderr, "nativax-runtime: load failed: %s\n", err ? err : "unknown");
        free(err);
        nx_app_free(app);
        return 1;
    }
    free(err);
    g_state.start_ms = now_ms();
    g_state.rss_loaded_kb = nx_mem_rss_kb();
    nx_app_update(app, 0.0);

    int frames = g_state.max_frames > 0 ? g_state.max_frames : 1;
    for (int i = 0; i < frames; i++) nx_app_update(app, (double)(i + 1) * 16.7);

    if (g_state.screenshot) {
        NxRaster raster;
        nx_raster_init(&raster, g_state.width, g_state.height);
        nx_raster_clear(&raster, (NxColor){1, 1, 1, 1});
        nx_raster_run(&raster, nx_app_list(app));
        if (!nx_raster_write_png(&raster, g_state.screenshot)) {
            fprintf(stderr, "nativax-runtime: cannot write %s\n", g_state.screenshot);
            nx_raster_free(&raster);
            nx_app_free(app);
            return 1;
        }
        printf("screenshot: %s (%dx%d)\n", g_state.screenshot, g_state.width, g_state.height);
        nx_raster_free(&raster);
    }
    if (g_state.stats) {
        char* json = nx_app_stats_json(app);
        if (json) {
            printf("%s\n", json);
            free(json);
        }
    }
    g_state.frame_count = frames;
    if (g_state.mem) print_mem_report();
    if (!g_state.stats && !g_state.mem) printf("nativax-runtime headless OK\n");
    nx_app_free(app);
    return 0;
}

static void usage(const char* argv0) {
    fprintf(stderr,
            "usage: %s [options] [entry.html]\n"
            "  --root DIR           project directory (default .)\n"
            "  --entry FILE         entry document relative to root (default index.html)\n"
            "  --headless           run the pipeline without a window (CI)\n"
            "  --frames N           quit after N frames (tests/benchmarks)\n"
            "  --size W H           window size in CSS px (default 1024 768)\n"
            "  --deterministic      pin DPI to 1.0 for reproducible screenshots\n"
            "  --screenshot FILE    write a PNG screenshot at frame 3\n"
            "  --dev URL            connect to the dev server (ws://127.0.0.1:PORT/__nativax_ws)\n"
            "  --stats              print pipeline stats JSON on exit\n"
            "  --mem                print RSS/peak memory JSON on exit\n"
            "  --perf               print presented-frame pacing JSON on exit"
            " (vsync deltas, real FPS)\n"
            "  --verbose            debug logging\n",
            argv0);
}

int main(int argc, char** argv) {
    nx_crash_init();
    bool headless = false;
    g_state.root = ".";
    g_state.entry = "index.html";
    g_state.width = 1024;
    g_state.height = 768;
    g_state.start_ms = now_ms();
    g_state.rss_start_kb = nx_mem_rss_kb();

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--headless") == 0) {
            headless = true;
        } else if (strcmp(argv[i], "--root") == 0 && i + 1 < argc) {
            g_state.root = argv[++i];
        } else if (strcmp(argv[i], "--entry") == 0 && i + 1 < argc) {
            g_state.entry = argv[++i];
        } else if (strcmp(argv[i], "--frames") == 0 && i + 1 < argc) {
            g_state.max_frames = atoi(argv[++i]);
        } else if (strcmp(argv[i], "--size") == 0 && i + 2 < argc) {
            g_state.width = atoi(argv[++i]);
            g_state.height = atoi(argv[++i]);
        } else if (strcmp(argv[i], "--deterministic") == 0) {
            g_state.deterministic = true;
        } else if (strcmp(argv[i], "--screenshot") == 0 && i + 1 < argc) {
            g_state.screenshot = argv[++i];
        } else if (strcmp(argv[i], "--dev") == 0 && i + 1 < argc) {
            g_state.dev_url = argv[++i];
        } else if (strcmp(argv[i], "--stats") == 0) {
            g_state.stats = true;
        } else if (strcmp(argv[i], "--mem") == 0) {
            g_state.mem = true;
        } else if (strcmp(argv[i], "--perf") == 0) {
            g_state.perf = true;
        } else if (strcmp(argv[i], "--verbose") == 0) {
            nx_log_set_level(NX_LOG_DEBUG);
        } else if (strcmp(argv[i], "--help") == 0) {
            usage(argv[0]);
            return 0;
        } else if (argv[i][0] == '-') {
            usage(argv[0]);
            return 2;
        } else {
            g_state.entry = argv[i];
        }
    }

    if (headless) return run_headless();

    NxPlatformDesc desc;
    memset(&desc, 0, sizeof(desc));
    desc.title = "NativaX";
    desc.width = g_state.width;
    desc.height = g_state.height;
    desc.vsync = !g_state.deterministic;
    desc.callbacks.init = init_cb;
    desc.callbacks.frame = frame_cb;
    desc.callbacks.cleanup = cleanup_cb;
    desc.callbacks.event = event_cb;
    desc.user = &g_state;
    if (!nx_platform_run(&desc)) {
        fprintf(stderr, "nativax-runtime: could not start the native window\n");
        return 1;
    }
    return 0;
}
