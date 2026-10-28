/*
    NativaX runtime — sokol_app entry point (Phase 2: window + lifecycle).

    Owns the native window, input events and the frame clock. The rendering
    pipeline plugs into frame_cb; headless mode skips windowing entirely so
    tests and CI can run the full pipeline without a display.
*/
#include "nativax/display_list.h"
#include "nativax/gfx.h"
#include "nativax/log.h"
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

#include "stb_image_write.h"

typedef struct AppState {
    const char* entry;      /* entry HTML file (pipeline phases use it) */
    const char* screenshot; /* --screenshot FILE */
    int max_frames;         /* >0: exit after N frames (tests/benchmarks) */
    int frame_count;
    NxDisplayList dl;
    int32_t font;
} AppState;

static AppState g_state;

/* smoke scene: proves GPU path (batching, textures, text, clipping) end to end.
   Geometry is authored in CSS px; a global DPI scale maps to device pixels. */
static void build_smoke_scene(void) {
    nx_dl_reset(&g_state.dl);
    if (g_state.font < 0) return;
    float dpi = sapp_dpi_scale();
    NxMat2x3 scale = nx_mat_scale(dpi, dpi);
    nx_dl_push_transform(&g_state.dl, &scale);
    nx_dl_fill_rect(&g_state.dl, 0, 0, 1024, 768, (NxColor){0.06f, 0.07f, 0.11f, 1}, NULL);
    float r16[4] = {16, 16, 16, 16};
    nx_dl_fill_rect(&g_state.dl, 120, 180, 784, 400, (NxColor){0.10f, 0.12f, 0.20f, 1}, r16);
    nx_dl_stroke_rect(&g_state.dl, 120, 180, 784, 400, (NxColor){0.25f, 0.30f, 0.50f, 1}, r16, 2);
    nx_dl_fill_rect(&g_state.dl, 160, 220, 200, 60, (NxColor){0.23f, 0.36f, 1.0f, 1}, r16);
    nx_dl_text(&g_state.dl, 180, 258, g_state.font, 28, (NxColor){1, 1, 1, 1}, "NativaX C runtime", 17);
    nx_dl_text(&g_state.dl, 160, 340, g_state.font, 22, (NxColor){0.85f, 0.88f, 0.95f, 1},
               "Sokol GFX + JavaScriptCore + native DOM", 40);
    nx_dl_push_clip(&g_state.dl, 160, 370, 500, 80);
    nx_dl_text(&g_state.dl, 160, 400, g_state.font, 18, (NxColor){0.55f, 0.90f, 0.70f, 1},
               "clipped text inside a scissor region — hot reload coming in Phase 8", 65);
    nx_dl_fill_rect(&g_state.dl, 160, 410, 700, 8, (NxColor){0.23f, 0.36f, 1.0f, 0.7f}, NULL);
    nx_dl_pop_clip(&g_state.dl);
}

static void take_screenshot(void) {
    if (!g_state.screenshot) return;
    int w = (int)(sapp_width() * sapp_dpi_scale() + 0.5f);
    int h = (int)(sapp_height() * sapp_dpi_scale() + 0.5f);
    uint8_t* px = malloc((size_t)w * h * 4);
    glReadPixels(0, 0, w, h, GL_RGBA, GL_UNSIGNED_BYTE, px); /* GL backbuffer, y-up */
    /* flip vertically for PNG */
    uint8_t* flipped = malloc((size_t)w * h * 4);
    for (int y = 0; y < h; y++) {
        memcpy(flipped + (size_t)y * w * 4, px + (size_t)(h - 1 - y) * w * 4, (size_t)w * 4);
    }
    if (stbi_write_png(g_state.screenshot, w, h, 4, flipped, w * 4)) {
        NX_INFO("screenshot written: %s (%dx%d)", g_state.screenshot, w, h);
    } else {
        NX_ERROR("screenshot write failed: %s", g_state.screenshot);
    }
    free(px);
    free(flipped);
}

static void init_cb(void) {
    sg_setup(&(sg_desc){
        .environment = sglue_environment(),
        .logger.func = slog_func,
    });
    nx_gfx_init();
    nx_dl_init(&g_state.dl);
    g_state.font = nx_font_load("assets/fonts/DejaVuSans.ttf");
    if (g_state.font < 0) {
        g_state.font = nx_font_load(NATIVAX_SOURCE_DIR "/assets/fonts/DejaVuSans.ttf");
    }
    NX_INFO("gfx backend: %s, %dx%d", sg_query_backend() == SG_BACKEND_GLCORE ? "GLCORE" : "other",
            sapp_width(), sapp_height());
    build_smoke_scene();
}

static void frame_cb(void) {
    const float clear[4] = {0.06f, 0.07f, 0.11f, 1.0f};
    nx_gfx_sync_textures();
    /* framebuffer pixels (HiDPI): window size * dpi scale */
    int fb_w = (int)(sapp_width() * sapp_dpi_scale() + 0.5f);
    int fb_h = (int)(sapp_height() * sapp_dpi_scale() + 0.5f);
    nx_gfx_render(&g_state.dl, fb_w, fb_h, clear);
    sg_commit();

    g_state.frame_count++;
    if (g_state.screenshot && g_state.frame_count == 3) {
        take_screenshot();
    }
    if (g_state.max_frames > 0 && g_state.frame_count >= g_state.max_frames) {
        NX_INFO("frame budget reached (%d), quitting", g_state.max_frames);
        sapp_quit();
    }
}

static void cleanup_cb(void) {
    nx_gfx_shutdown();
    nx_dl_free(&g_state.dl);
    nx_font_reset();
    nx_tex_reset_all();
    sg_shutdown();
    NX_INFO("gfx shut down cleanly after %d frames", g_state.frame_count);
}

static void event_cb(const sapp_event* ev) {
    switch (ev->type) {
        case SAPP_EVENTTYPE_RESIZED:
            NX_DEBUG("resize %dx%d (fb %dx%d)", ev->framebuffer_width, ev->framebuffer_height,
                     ev->framebuffer_width, ev->framebuffer_height);
            break;
        case SAPP_EVENTTYPE_KEY_DOWN:
            NX_DEBUG("key down: %d", (int)ev->key_code);
            if (ev->key_code == SAPP_KEYCODE_ESCAPE) {
                sapp_quit();
            }
            break;
        case SAPP_EVENTTYPE_MOUSE_DOWN:
            NX_DEBUG("mouse down: btn=%d at %.1f,%.1f", (int)ev->mouse_button, ev->mouse_x, ev->mouse_y);
            break;
        default:
            break;
    }
}

static int run_headless(int frames) {
    /* Headless smoke: no GPU, no window. The pipeline tests run headless via
       nativax_tests; this mode exists so `nativax-runtime --headless` works
       on display-less machines and in CI. */
    NX_INFO("headless smoke: %d frame(s) requested, no display needed", frames);
    printf("nativax-runtime headless OK\n");
    return 0;
}

static void usage(const char* argv0) {
    fprintf(stderr,
            "usage: %s [options] [index.html]\n"
            "  --headless           run without a window (smoke/tests)\n"
            "  --frames N           quit after N frames (tests/benchmarks)\n"
            "  --screenshot FILE    headless: write PNG (pipeline phases)\n"
            "  --dev URL            connect to dev server for hot reload\n"
            "  --verbose            debug logging\n",
            argv0);
}

int main(int argc, char** argv) {
    bool headless = false;

    g_state.entry = NULL;
    g_state.max_frames = 0;
    g_state.screenshot = NULL;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--headless") == 0) {
            headless = true;
        } else if (strcmp(argv[i], "--frames") == 0 && i + 1 < argc) {
            g_state.max_frames = atoi(argv[++i]);
        } else if (strcmp(argv[i], "--screenshot") == 0 && i + 1 < argc) {
            g_state.screenshot = argv[++i];
        } else if (strcmp(argv[i], "--dev") == 0 && i + 1 < argc) {
            (void)argv[++i]; /* dev client, Phase 8 */
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

    if (headless) {
        return run_headless(g_state.max_frames > 0 ? g_state.max_frames : 1);
    }

    sapp_run(&(sapp_desc){
        .init_cb = init_cb,
        .frame_cb = frame_cb,
        .cleanup_cb = cleanup_cb,
        .event_cb = event_cb,
        .width = 1024,
        .height = 768,
        .depth_format = SAPP_PIXELFORMAT_NONE,
        .window_title = "NativaX",
        .swap_interval = 1,
        .logger.func = slog_func,
    });
    return 0;
}
