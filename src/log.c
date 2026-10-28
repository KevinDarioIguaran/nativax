#include "nativax/log.h"

#include <stdio.h>
#include <time.h>

static NxLogLevel g_min_level = NX_LOG_INFO;

static const char* level_name(NxLogLevel level) {
    switch (level) {
        case NX_LOG_DEBUG: return "DEBUG";
        case NX_LOG_INFO: return "INFO";
        case NX_LOG_WARN: return "WARN";
        case NX_LOG_ERROR: return "ERROR";
    }
    return "?";
}

void nx_log_set_level(NxLogLevel min_level) { g_min_level = min_level; }

void nx_logv(NxLogLevel level, const char* tag, const char* fmt, va_list args) {
    if (level < g_min_level) {
        return;
    }
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    struct tm tm;
    localtime_r(&ts.tv_sec, &tm);
    char stamp[32];
    snprintf(stamp, sizeof(stamp), "%02d:%02d:%02d.%03ld", tm.tm_hour, tm.tm_min, tm.tm_sec,
             ts.tv_nsec / 1000000);
    fprintf(stderr, "[%s] %-5s %-8s ", stamp, level_name(level), tag);
    vfprintf(stderr, fmt, args);
    fputc('\n', stderr);
}

void nx_log(NxLogLevel level, const char* tag, const char* fmt, ...) {
    va_list args;
    va_start(args, fmt);
    nx_logv(level, tag, fmt, args);
    va_end(args);
}
