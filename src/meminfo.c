#include "nativax/meminfo.h"

#include <stdio.h>
#include <string.h>
#include <sys/resource.h>

static long read_status_kb(const char* key) {
    FILE* f = fopen("/proc/self/status", "r");
    if (!f) return -1;
    char line[256];
    long value = -1;
    size_t key_len = strlen(key);
    while (fgets(line, sizeof(line), f)) {
        if (strncmp(line, key, key_len) != 0) continue;
        long kb = 0;
        if (sscanf(line + key_len, " %ld", &kb) == 1) {
            value = kb;
            break;
        }
    }
    fclose(f);
    return value;
}

long nx_mem_rss_kb(void) {
    long v = read_status_kb("VmRSS:");
    if (v > 0) return v;
    struct rusage ru;
    if (getrusage(RUSAGE_SELF, &ru) == 0) return (long)ru.ru_maxrss;
    return -1;
}

long nx_mem_peak_kb(void) {
    long v = read_status_kb("VmHWM:");
    if (v > 0) return v;
    struct rusage ru;
    if (getrusage(RUSAGE_SELF, &ru) == 0) return (long)ru.ru_maxrss;
    return -1;
}
