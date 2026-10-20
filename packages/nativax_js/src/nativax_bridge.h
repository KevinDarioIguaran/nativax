/*
 * NativaX <-> QuickJS bridge.
 *
 * A deliberately small C surface consumed from Dart through FFI. Every value
 * crossing the boundary is either a scalar or a UTF-8 buffer (JSON), so the
 * Dart side never touches QuickJS' JSValue struct, whose ABI differs between
 * 32-bit (NaN-boxed uint64_t) and 64-bit (16-byte struct) targets.
 *
 * Buffers returned through `out` parameters are allocated with nx_alloc and
 * must be released with nx_free.
 */
#ifndef NATIVAX_BRIDGE_H
#define NATIVAX_BRIDGE_H

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

typedef struct NxRuntime NxRuntime;

/*
 * Called synchronously when script code invokes `__nx_host(string)`.
 * The callee must store a buffer allocated with nx_alloc in *response (JSON
 * text, or an empty buffer meaning `undefined`). Ownership passes to C.
 */
typedef void (*NxHostCallback)(int64_t runtime_id, const char *request,
                               int64_t request_len, char **response,
                               int64_t *response_len);

/* Status codes. */
#define NX_OK 0
#define NX_EXCEPTION 1
#define NX_INTERNAL_ERROR 2

NX_EXPORT NxRuntime *nx_runtime_new(int64_t runtime_id, int64_t memory_limit,
                                    int64_t stack_size, NxHostCallback host);
NX_EXPORT void nx_runtime_free(NxRuntime *rt);

/* Sets an execution budget in milliseconds starting now; 0 disables it. */
NX_EXPORT void nx_set_budget_ms(NxRuntime *rt, int64_t budget_ms);

/*
 * Evaluates a classic (non-module) script. On NX_OK *out holds the completion
 * value as JSON (empty for undefined / non-serializable values). On
 * NX_EXCEPTION *out holds {"name","message","stack","uncatchable"}.
 */
NX_EXPORT int32_t nx_eval(NxRuntime *rt, const char *source, int64_t len,
                          const char *filename, char **out, int64_t *out_len);

/* Calls globalThis[function_name](JSON.parse(json_arg)). Same out contract. */
NX_EXPORT int32_t nx_call(NxRuntime *rt, const char *function_name,
                          const char *json_arg, int64_t len, char **out,
                          int64_t *out_len);

/*
 * Runs at most max_jobs pending jobs (promise reactions). Returns the number
 * executed, or -1 when a job threw (error JSON in *out).
 */
NX_EXPORT int32_t nx_run_jobs(NxRuntime *rt, int32_t max_jobs, char **out,
                              int64_t *out_len);
NX_EXPORT int32_t nx_has_pending_jobs(NxRuntime *rt);

NX_EXPORT void nx_run_gc(NxRuntime *rt);
NX_EXPORT int64_t nx_memory_used(NxRuntime *rt);

NX_EXPORT void *nx_alloc(int64_t size);
NX_EXPORT void nx_free(void *ptr);

#ifdef __cplusplus
}
#endif

#endif /* NATIVAX_BRIDGE_H */
