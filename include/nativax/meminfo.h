#ifndef NATIVAX_MEMINFO_H
#define NATIVAX_MEMINFO_H

/*
    Process memory probes (Phase 9 evidence).

    RSS is resident physical memory; peak RSS is the high-water mark. GPU
    memory is not part of RSS and is reported separately where the backend
    exposes it. Linux reads /proc/self/status; other platforms fall back to
    getrusage().
*/

long nx_mem_rss_kb(void);
long nx_mem_peak_kb(void);

/* glibc heap currently in use (bytes), from mallinfo2(). This is the native
   heap only: it excludes mmap'd regions, shared libraries and the JS engine's
   own allocator. Returns -1 when mallinfo2 is unavailable. */
long long nx_native_heap_bytes(void);

#endif /* NATIVAX_MEMINFO_H */
