/*
 * NativaJS optional JIT (experimental).
 *
 * This module is the entry point for the tiered JIT planned in
 * docs/nativa-js-jit-plan.md. It is compiled in only when NATIVAX_JIT is
 * defined at build time (see hook/build.dart); otherwise every function here
 * is a safe no-op and the engine behaves exactly as the pure interpreter.
 *
 * The JIT is strictly additive: it never changes QuickJS semantics, and any
 * failure deoptimizes back to the interpreter.
 */
#ifndef NATIVAX_JIT_H
#define NATIVAX_JIT_H

#include <stddef.h>
#include <stdint.h>

#include "nativax_bridge.h"

#ifdef __cplusplus
extern "C" {
#endif

/* 1 if a JIT backend is compiled in and enabled, 0 otherwise. */
NX_EXPORT int nx_jit_available(void);

/* Process-global initialization. Safe to call repeatedly. No-op when
 * unavailable. */
NX_EXPORT void nx_jit_init(void);

/* Bytes of native code currently retained by the JIT. 0 when unavailable. */
NX_EXPORT size_t nx_jit_code_bytes(void);

/* Attempt to compile a QuickJS bytecode object. Returns a native entry point
 * or NULL when the JIT is unavailable / compilation is not supported yet.
 * The returned pointer (if any) is owned by the JIT and freed via
 * nx_jit_free_code when the bytecode is destroyed. */
NX_EXPORT void *nx_jit_try_compile(void *rt, void *bytecode);

/* Compile a function whose bytecode is a single OP_return_undef into native
 * code. Returns NULL when the platform/backend is unavailable. */
NX_EXPORT void *nx_jit_compile_return_undef(void);

/* Compile a function returning local 0 / arg 0. */
NX_EXPORT void *nx_jit_compile_return_loc0(void);
NX_EXPORT void *nx_jit_compile_return_arg0(void);

/* Context for entry functions that need counts (set before calling JIT). */
NX_EXPORT void nx_jit_set_arg_count(int n);
NX_EXPORT void nx_jit_set_var_count(int n);
NX_EXPORT int nx_jit_get_arg_count(void);
NX_EXPORT int nx_jit_get_var_count(void);

/* Compile a function returning the given 32-bit integer (push_i32; return). */
NX_EXPORT void *nx_jit_compile_return_i32(int32_t value);

/* Release a code pointer returned by nx_jit_try_compile. No-op for NULL. */
NX_EXPORT void nx_jit_free_code(void *code);

#ifdef __cplusplus
}
#endif

#endif /* NATIVAX_JIT_H */
