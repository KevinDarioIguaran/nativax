/* Private layout shared by the bridge and the WebAssembly/WebGL subsystems.
 * Not part of the package's Dart FFI surface. */
#ifndef NATIVAX_RUNTIME_INTERNAL_H
#define NATIVAX_RUNTIME_INTERNAL_H

#include "nativax_bridge.h"
#include "quickjs.h"

typedef struct NxWasm NxWasm;

struct NxRuntime {
  JSRuntime *rt;
  JSContext *ctx;
  int64_t id;
  NxHostCallback host;
  int64_t deadline_ms; /* 0 = no deadline */
  /* wasm3 environment + module/instance registry for this JS runtime. */
  NxWasm *wasm;
  /* Callbacks the host invokes by name (nx_call). Kept here instead of on
   * the global object so scripts cannot discover or forge them. */
  JSValue callbacks;
};

#endif /* NATIVAX_RUNTIME_INTERNAL_H */
