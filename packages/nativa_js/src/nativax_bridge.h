#ifndef NATIVAX_BRIDGE_H
#define NATIVAX_BRIDGE_H

/* Engine-independent native support for nativa_js: memory and the
 * process-wide buffer handoff. Script engines are bound from Dart. */

#include <stddef.h>
#include <stdint.h>

#if defined(_WIN32)
#define NX_EXPORT __declspec(dllexport)
#else
#define NX_EXPORT __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* Parks malloc'd [data] under a process-wide id; ownership moves to the
 * registry until nx_buffer_take. */
NX_EXPORT int64_t nx_buffer_put(void *data, int64_t len);
/* Removes buffer [id]; returns its bytes (caller frees with nx_free) or NULL
 * with *len = -1 when unknown. */
NX_EXPORT void *nx_buffer_take(int64_t id, int64_t *len);
NX_EXPORT void *nx_alloc(int64_t size);

/* Shared memory blocks behind SharedArrayBuffer (see nativax_bridge.c).
 * nx_sab_alloc returns zeroed memory holding one reference; nx_sab_release
 * has the JSTypedArrayBytesDeallocator signature. nx_sab_share takes a new
 * reference under a one-shot id; nx_sab_open hands that reference over. */
NX_EXPORT void *nx_sab_alloc(int64_t len);
NX_EXPORT int32_t nx_sab_is_block(void *data);
NX_EXPORT int64_t nx_sab_length(void *data);
NX_EXPORT void nx_sab_release(void *data, void *context);
NX_EXPORT int64_t nx_sab_share(void *data);
NX_EXPORT void *nx_sab_open(int64_t id);
/* Atomics.wait/notify on an int32 cell of a shared block: wait returns 0
 * "ok", 1 "not-equal" or 2 "timed-out" (timeout_ms < 0: no deadline);
 * notify returns the number woken (count < 0: all). */
NX_EXPORT int32_t nx_sab_wait(void *addr, int32_t expected, double timeout_ms);
NX_EXPORT int32_t nx_sab_notify(void *addr, int32_t count);
NX_EXPORT void nx_free(void *ptr);

#ifdef __cplusplus
}
#endif

#endif /* NATIVAX_BRIDGE_H */
