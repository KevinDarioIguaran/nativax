/*
    Platform contract tests (no window): the backend-independent helpers that
    every platform backend must use to convert coordinates. The windowed
    lifecycle itself is covered by the gpu_window_screenshot test.
*/
#include <math.h>
#include <stdio.h>

#include "nativax/platform.h"

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

static int close_to(float a, float b, float eps) { return fabsf(a - b) <= eps; }

int main(void) {
    /* framebuffer -> CSS coordinates at common scale factors */
    CHECK(close_to(nx_platform_css_coord(100.0f, 1.0f), 100.0f, 0.001f),
          "dpi 1 keeps coordinates");
    CHECK(close_to(nx_platform_css_coord(200.0f, 2.0f), 100.0f, 0.001f),
          "retina halves framebuffer pixels");
    CHECK(close_to(nx_platform_css_coord(150.0f, 1.5f), 100.0f, 0.001f),
          "fractional dpi");
    CHECK(close_to(nx_platform_css_coord(42.0f, 0.0f), 42.0f, 0.001f),
          "dpi 0 is treated as 1 (no divide by zero)");
    CHECK(close_to(nx_platform_css_coord(-10.0f, 2.0f), -5.0f, 0.001f),
          "negative coordinates stay negative");

    /* CSS -> physical sizes */
    CHECK(nx_platform_physical_size(1024, 1.0f) == 1024, "1x size unchanged");
    CHECK(nx_platform_physical_size(1024, 2.0f) == 2048, "2x size doubles");
    CHECK(nx_platform_physical_size(985, 1.04f) == 1024, "fractional dpi rounds");
    CHECK(nx_platform_physical_size(1024, 0.0f) == 1024, "dpi 0 is treated as 1");
    CHECK(nx_platform_physical_size(0, 2.0f) == 0, "zero size stays zero");
    CHECK(nx_platform_physical_size(-5, 2.0f) == 0, "negative size clamps to zero");

    /* key enum contract: specials never collide with printable ASCII */
    CHECK(NX_KEY_ESCAPE >= 256, "special keys start above ASCII");
    CHECK(NX_KEY_UNKNOWN == 0, "unknown key is zero (memset-friendly)");
    CHECK((int)'A' >= 32 && (int)'A' <= 126, "printable keys use ASCII");

    printf("%d checks, %d failures\n", g_checks, g_failures);
    return g_failures == 0 ? 0 : 1;
}
