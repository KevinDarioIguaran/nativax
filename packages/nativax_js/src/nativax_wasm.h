/*
 * NativaX WebAssembly: a WebAssembly 1.0/2.0 runtime backed by wasm3.
 *
 * The public `WebAssembly.*` API lives in the JavaScript host prelude; this
 * header only exposes the process-level hooks the QuickJS bridge needs. Like
 * the WebGL bridge, the object installed on the global object is private and
 * removed by the prelude before any document script runs.
 */
#ifndef NATIVAX_WASM_H
#define NATIVAX_WASM_H

#include "nativax_bridge.h"

#ifdef __cplusplus
extern "C" {
#endif

struct NxRuntime;

/* Creates the wasm3 environment and installs `__nx_wasm_native` on the
 * context's global object. */
void nx_wasm_install(NxRuntime *rt);

/* Releases every module/instance owned by this runtime. Called before the
 * QuickJS context is destroyed, while JSValue handles are still valid. */
void nx_wasm_free(NxRuntime *rt);

#ifdef __cplusplus
}
#endif

#endif /* NATIVAX_WASM_H */
