/*
    NativaX runtime — sokol_app entry point.

    Owns the native window, input events, the frame clock and the development
    client. The HTML/CSS/JS pipeline lives in app.c; this file maps window
    events onto it and presents the painted display list through Sokol GFX.

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
#include "nativax/raster.h"
#include "nativax/text.h"
#include "sokol_app.h"
#include "sokol_gfx.h"
#include "sokol_glue.h"
#include "sokol_log.h"

#include <GL/gl.h>
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
    float dpi;
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
    int fb_w = (int)(g_state.width * g_state.dpi + 0.5f);
    int fb_h = (int)(g_state.height * g_state.dpi + 0.5f);
    uint8_t* px = malloc((size_t)fb_w * (size_t)fb_h * 4);
    uint8_t* flipped = malloc((size_t)fb_w * (size_t)fb_h * 4);
    if (!px || !flipped) {
        free(px);
        free(flipped);
        return;
    }
    glReadPixels(0, 0, fb_w, fb_h, GL_RGBA, GL_UNSIGNED_BYTE, px); /* y-up */
    for (int y = 0; y < fb_h; y++)
        memcpy(flipped + (size_t)y * fb_w * 4, px + (size_t)(fb_h - 1 - y) * fb_w * 4,
               (size_t)fb_w * 4);
    if (stbi_write_png(g_state.screenshot, fb_w, fb_h, 4, flipped, fb_w * 4))
        NX_INFO("screenshot written: %s (%dx%d)", g_state.screenshot, fb_w, fb_h);
    else
        NX_ERROR("screenshot write failed: %s", g_state.screenshot);
    free(px);
    free(flipped);
}

/* ---- sokol callbacks ----------------------------------------------------- */

static void init_cb(void) {
    sg_setup(&(sg_desc){
        .environment = sglue_environment(),
        .logger.func = slog_func,
    });
    nx_gfx_init();

    g_state.dpi = g_state.deterministic ? 1.0f : sapp_dpi_scale();

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
        sapp_quit();
        return;
    }
    free(err);
    nx_app_set_dpi(g_state.app, g_state.dpi);
    nx_app_update(g_state.app, now_ms() - g_state.start_ms);

    if (g_state.dev_url) g_state.hr = nx_hot_reload_connect(g_state.dev_url, on_reload, g_state.app);
    NX_INFO("runtime ready: %s/%s (%dx%d css px, dpi %.2f)", g_state.root, g_state.entry,
            g_state.width, g_state.height, g_state.dpi);
}

static void frame_cb(void) {
    if (!g_state.app) return;
    if (g_state.hr) nx_hot_reload_poll(g_state.hr);
    nx_app_update(g_state.app, now_ms() - g_state.start_ms);

    int fb_w = (int)(g_state.width * g_state.dpi + 0.5f);
    int fb_h = (int)(g_state.height * g_state.dpi + 0.5f);
    nx_gfx_sync_textures();
    const float clear[4] = {1.0f, 1.0f, 1.0f, 1.0f};
    nx_gfx_render(nx_app_list(g_state.app), fb_w, fb_h, clear);
    sg_commit();

    g_state.frame_count++;
    if (g_state.screenshot && g_state.frame_count == 3) take_screenshot();
    if (g_state.max_frames > 0 && g_state.frame_count >= g_state.max_frames) {
        NX_INFO("frame budget reached (%d), quitting", g_state.max_frames);
        sapp_quit();
    }
}

static void cleanup_cb(void) {
    if (g_state.hr) nx_hot_reload_free(g_state.hr);
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
    nx_font_reset();
    nx_tex_reset_all();
    sg_shutdown();
    NX_INFO("runtime shut down cleanly after %d frames", g_state.frame_count);
}

static void event_cb(const sapp_event* ev) {
    switch (ev->type) {
        case SAPP_EVENTTYPE_RESIZED: {
            int css_w = (int)ev->window_width;
            int css_h = (int)ev->window_height;
            g_state.width = css_w;
            g_state.height = css_h;
            if (g_state.app) nx_app_set_viewport(g_state.app, css_w, css_h);
            if (g_state.app) nx_app_set_dpi(g_state.app, g_state.dpi);
            NX_DEBUG("resize: %dx%d css px (fb %dx%d)", css_w, css_h, ev->framebuffer_width,
                     ev->framebuffer_height);
            break;
        }
        case SAPP_EVENTTYPE_KEY_DOWN:
            if (ev->key_code == SAPP_KEYCODE_ESCAPE) sapp_quit();
            break;
        case SAPP_EVENTTYPE_MOUSE_DOWN:
            if (g_state.app) nx_app_pointer(g_state.app, ev->mouse_x, ev->mouse_y, true);
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
    if (!g_state.stats) printf("nativax-runtime headless OK\n");
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
            "  --verbose            debug logging\n",
            argv0);
}

int main(int argc, char** argv) {
    bool headless = false;
    g_state.root = ".";
    g_state.entry = "index.html";
    g_state.width = 1024;
    g_state.height = 768;
    g_state.start_ms = now_ms();

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

    sapp_run(&(sapp_desc){
        .init_cb = init_cb,
        .frame_cb = frame_cb,
        .cleanup_cb = cleanup_cb,
        .event_cb = event_cb,
        .width = g_state.width,
        .height = g_state.height,
        .depth_format = SAPP_PIXELFORMAT_NONE,
        .window_title = "NativaX",
        .swap_interval = g_state.deterministic ? 0 : 1,
        .logger.func = slog_func,
    });
    return 0;
}
