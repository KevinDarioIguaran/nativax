#ifndef NATIVAX_LOG_H
#define NATIVAX_LOG_H

#include <stdarg.h>

typedef enum NxLogLevel {
    NX_LOG_DEBUG = 0,
    NX_LOG_INFO = 1,
    NX_LOG_WARN = 2,
    NX_LOG_ERROR = 3,
} NxLogLevel;

void nx_log_set_level(NxLogLevel min_level);
void nx_log(NxLogLevel level, const char* tag, const char* fmt, ...)
#if defined(__GNUC__)
    __attribute__((format(printf, 3, 4)))
#endif
    ;
void nx_logv(NxLogLevel level, const char* tag, const char* fmt, va_list args);

#define NX_DEBUG(...) nx_log(NX_LOG_DEBUG, "nativax", __VA_ARGS__)
#define NX_INFO(...) nx_log(NX_LOG_INFO, "nativax", __VA_ARGS__)
#define NX_WARN(...) nx_log(NX_LOG_WARN, "nativax", __VA_ARGS__)
#define NX_ERROR(...) nx_log(NX_LOG_ERROR, "nativax", __VA_ARGS__)

#endif /* NATIVAX_LOG_H */
