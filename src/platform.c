/*
    Backend-independent platform helpers.

    Kept free of OS/graphics headers so the coordinate contract can be unit
    tested on CI without a display: every backend must normalize pointer
    positions with nx_platform_css_coord() and size its framebuffer with
    nx_platform_physical_size().
*/
#include "nativax/platform.h"

#include <math.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

float nx_platform_css_coord(float pixels, float dpi) {
    if (dpi <= 0.0f) dpi = 1.0f;
    return pixels / dpi;
}

int nx_platform_physical_size(int css_px, float dpi) {
    if (dpi <= 0.0f) dpi = 1.0f;
    if (css_px <= 0) return 0;
    return (int)((float)css_px * dpi + 0.5f);
}

#include <execinfo.h>
#include <unistd.h>

static void nx_crash_handler(int sig) {
    void* frames[64];
    int n = backtrace(frames, 64);
    fprintf(stderr, "\nnativax: fatal signal %d (%s)\n", sig, strsignal(sig));
    backtrace_symbols_fd(frames, n, STDERR_FILENO);
    signal(sig, SIG_DFL);
    raise(sig);
}

void nx_crash_init(void) {
    signal(SIGSEGV, nx_crash_handler);
    signal(SIGABRT, nx_crash_handler);
    signal(SIGFPE, nx_crash_handler);
    signal(SIGILL, nx_crash_handler);
}