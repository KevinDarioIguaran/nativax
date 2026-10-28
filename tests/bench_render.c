/*
    nativax_bench: renderer benchmark (display-list build + CPU raster).

    Measures the phases the GPU runtime also exercises per frame:
      build  — display-list construction (rects, strokes, text, clips, images)
      clear  — raster target clear
      raster — display list -> RGBA8 pixels (CPU reference rasterizer)
      frame  — clear + raster + build of the NEXT frame (steady-state sim)

    Output: one JSON object on stdout (machine-readable, archived by
    debug/benchmarks/workloads/render_benchmark.py). A pixel checksum guards
    against silent visual changes between runs/commits.

    Usage: nativax_bench [--w W] [--h H] [--iters N] [--cards N] [--text N]
*/
#include "nativax/display_list.h"
#include "nativax/image.h"
#include "nativax/raster.h"
#include "nativax/text.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "stb_image_write.h"

static double now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec * 1000.0 + (double)ts.tv_nsec / 1e6;
}

typedef struct SceneCfg {
    int w, h;
    int cards;
    int text_runs;
    int iters;
} SceneCfg;

/* deterministic pseudo-random (fixed seed: comparable runs) */
static uint32_t rng_state = 0x2F6E2B1u;
static uint32_t rng_next(void) {
    rng_state = rng_state * 1664525u + 1013904223u;
    return rng_state;
}
static float rng_float(float lo, float hi) { return lo + (hi - lo) * (rng_next() % 1000) / 1000.0f; }

static const char* FONT = NATIVAX_SOURCE_DIR "/assets/fonts/DejaVuSans.ttf";

static void build_scene(NxDisplayList* dl, const SceneCfg* cfg, int32_t font, int32_t img,
                        int frame) {
    nx_dl_reset(dl);
    float W = (float)cfg->w, H = (float)cfg->h;
    nx_dl_fill_rect(dl, 0, 0, W, H, (NxColor){0.06f, 0.07f, 0.11f, 1}, NULL);
    float r12[4] = {12, 12, 12, 12};
    float r8[4] = {8, 8, 8, 8};
    float title[] = {'N', 'a', 't', 'i', 'v', 'a', 'X'};
    (void)title;
    int per_row = 4;
    for (int i = 0; i < cfg->cards; i++) {
        int col = i % per_row, row = i / per_row;
        float x = 24.0f + col * ((W - 48.0f) / per_row);
        float y = 24.0f + row * 150.0f;
        if (y + 130 > H) y = 24.0f + (i % 8) * 90.0f; /* wrap deterministically */
        float cw = (W - 48.0f) / per_row - 16.0f;
        nx_dl_fill_rect(dl, x, y, cw, 126, (NxColor){0.10f, 0.12f, 0.20f, 1}, r12);
        nx_dl_stroke_rect(dl, x, y, cw, 126, (NxColor){0.25f, 0.30f, 0.50f, 1}, r12, 1);
        nx_dl_fill_rect(dl, x + 16, y + 16, 96, 28, (NxColor){0.23f, 0.36f, 1.0f, 1}, r8);
        char label[48];
        int len = snprintf(label, sizeof(label), "Card %d frame %d", i, frame);
        nx_dl_text(dl, x + 24, y + 36, font, 15, (NxColor){1, 1, 1, 1}, label, len);
        const char* body = "The quick brown fox jumps over the lazy dog";
        nx_dl_text(dl, x + 16, y + 66, font, 13, (NxColor){0.80f, 0.84f, 0.92f, 1}, body, 43);
        nx_dl_text(dl, x + 16, y + 84, font, 13, (NxColor){0.55f, 0.60f, 0.72f, 1},
                   "portable C11 + Sokol display list", 32);
        float frac = rng_float(0.15f, 1.0f);
        nx_dl_fill_rect(dl, x + 16, y + 98, cw - 32, 6, (NxColor){0.16f, 0.19f, 0.30f, 1}, NULL);
        nx_dl_fill_rect(dl, x + 16, y + 98, (cw - 32) * frac, 6, (NxColor){0.23f, 0.36f, 1.0f, 0.85f},
                        NULL);
        if (img > 0 && (i & 1)) {
            nx_dl_image(dl, x + cw - 56, y + 12, 40, 40, img, (NxColor){1, 1, 1, 1});
        }
    }
    /* clipped text band (scissor groups) */
    int bands = cfg->text_runs / 12 + 1;
    for (int b = 0; b < bands; b++) {
        float y = H - 120.0f + b * 22.0f;
        if (y < 0) continue;
        nx_dl_push_clip(dl, 24, y - 14, W - 48, 20);
        for (int t = 0; t < 12; t++) {
            char s[64];
            int len = snprintf(s, sizeof(s), "run %d.%d deterministic glyph raster", b, t);
            nx_dl_text(dl, 24 + t * ((W - 60) / 12), y, font, 12,
                       (NxColor){0.55f, 0.90f, 0.70f, 1}, s, len);
        }
        nx_dl_pop_clip(dl);
    }
}

static int32_t make_test_image(void) {
    static uint8_t px[64 * 64 * 4];
    for (int i = 0; i < 64 * 64; i++) {
        px[i * 4] = (uint8_t)((i / 64) * 4);
        px[i * 4 + 1] = (uint8_t)(128 - (i / 64));
        px[i * 4 + 2] = (uint8_t)(i % 64 * 4);
        px[i * 4 + 3] = 255;
    }
    const char* tmp = "/tmp/nativax_bench_img.png";
    if (!stbi_write_png(tmp, 64, 64, 4, px, 64 * 4)) return -1;
    return nx_image_load_file(tmp);
}

int main(int argc, char** argv) {
    SceneCfg cfg = {.w = 1280, .h = 720, .cards = 16, .text_runs = 96, .iters = 30};
    for (int i = 1; i < argc - 1; i++) {
        if (strcmp(argv[i], "--w") == 0) cfg.w = atoi(argv[++i]);
        else if (strcmp(argv[i], "--h") == 0) cfg.h = atoi(argv[++i]);
        else if (strcmp(argv[i], "--iters") == 0) cfg.iters = atoi(argv[++i]);
        else if (strcmp(argv[i], "--cards") == 0) cfg.cards = atoi(argv[++i]);
        else if (strcmp(argv[i], "--text") == 0) cfg.text_runs = atoi(argv[++i]);
    }

    int32_t font = nx_font_load(FONT);
    if (font < 0) {
        fprintf(stderr, "bench: font not found: %s\n", FONT);
        return 2;
    }
    int32_t img = make_test_image();

    NxDisplayList dl;
    nx_dl_init(&dl);
    NxRaster r;
    nx_raster_init(&r, cfg.w, cfg.h);

    /* warmup: glyph cache, atlas pages, page tables */
    build_scene(&dl, &cfg, font, img, 0);
    nx_raster_clear(&r, (NxColor){0, 0, 0, 1});
    nx_raster_run(&r, &dl);

    double build_ms = 0, clear_ms = 0, raster_ms = 0;
    uint64_t verts = 0, indices = 0;
    uint32_t checksum = 0;
    for (int it = 0; it < cfg.iters; it++) {
        double t0 = now_ms();
        build_scene(&dl, &cfg, font, img, it + 1);
        double t1 = now_ms();
        nx_raster_clear(&r, (NxColor){0.06f, 0.07f, 0.11f, 1});
        double t2 = now_ms();
        nx_raster_run(&r, &dl);
        double t3 = now_ms();
        build_ms += t1 - t0;
        clear_ms += t2 - t1;
        raster_ms += t3 - t2;
        verts += dl.vert_count;
        indices += dl.index_count;
    }
    /* checksum over final frame (guards visual equivalence across commits) */
    for (size_t i = 0; i < (size_t)cfg.w * cfg.h * 4; i += 4) {
        checksum = checksum * 31u + r.pixels[i] + r.pixels[i + 1] * 3u + r.pixels[i + 2] * 7u;
    }
    double n = (double)cfg.iters;
    double frame_ms = (clear_ms + raster_ms) / n;
    double mpix = (double)cfg.w * cfg.h / 1e6;
    printf("{\"bench\":\"render\",\"w\":%d,\"h\":%d,\"iters\":%d,\"cards\":%d,"
           "\"build_ms\":%.3f,\"clear_ms\":%.3f,\"raster_ms\":%.3f,\"frame_ms\":%.3f,"
           "\"raster_mpix_s\":%.1f,\"avg_verts\":%.0f,\"avg_indices\":%.0f,"
           "\"checksum\":\"%08x\"}\n",
           cfg.w, cfg.h, cfg.iters, cfg.cards, build_ms / n, clear_ms / n, raster_ms / n,
           frame_ms, mpix * 1000.0 / (frame_ms > 0 ? frame_ms : 1), verts / n, indices / n,
           checksum);

    nx_raster_free(&r);
    nx_dl_free(&dl);
    nx_image_reset();
    nx_font_reset();
    nx_tex_reset_all();
    remove("/tmp/nativax_bench_img.png");
    return 0;
}
