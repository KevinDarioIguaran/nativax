#ifndef NATIVAX_JS_ENGINE_H
#define NATIVAX_JS_ENGINE_H

/*
    JavaScript engine layer — JavaScriptCore only (AGENTS.md non-negotiable).

    Links the system JavaScriptCoreGTK via its C API (pkg-config
    javascriptcoregtk-4.1 on Linux). This is a native C implementation of the
    contract the V1 runtime exposed through an FFI bridge; no FFI, Dart or
    Flutter code participates. This module is the only place allowed to hold
    JSValueRef; everything above it (DOM bindings, host APIs) exchanges only
    ids, scalars and JSON strings — never engine values across the boundary.
*/

#include <JavaScriptCore/JavaScript.h>

#include <stdbool.h>

typedef struct NxJs NxJs;

typedef JSValueRef (*NxJsNativeFn)(JSContextRef ctx, JSObjectRef fn, JSObjectRef self,
                                   size_t argc, const JSValueRef argv[], void* user);

NxJs* nx_js_new(void);
void nx_js_free(NxJs* js);
JSContextRef nx_js_ctx(NxJs* js);

/* Evaluate statements. Returns false on exception; *error (caller frees)
   holds the message. */
bool nx_js_eval(NxJs* js, const char* code, const char* url, char** error);

/* Evaluate an expression and return its JSON encoding (JSON.stringify),
   e.g. `1+1` -> "2", objects -> "{\"a\":1}", undefined -> "null".
   Caller frees the result. NULL + *error on exception. */
char* nx_js_eval_json(NxJs* js, const char* expr, char** error);

/* JSON-encode any JSValueRef (strings quoted, objects via JSON.stringify). */
char* nx_js_value_to_json(JSContextRef ctx, JSValueRef v);

/* Call a global function with a JSON array argument, returning the result
   as JSON (caller frees). Matches the ids/scalars/JSON contract. */
char* nx_js_call_json(NxJs* js, const char* fn_name, const char* json_args, char** error);

/* Register a native function on the global object. */
bool nx_js_set_function(NxJs* js, const char* name, NxJsNativeFn fn, void* user);

/* Execution time budget for scripts (0 = unlimited). SOFT budget: scripts that
   exceed it complete anyway but emit a warning with the measured time.
   Hard termination needs an engine API (JS interrupt handler /
   context-group time limit) that WebKitGTK's JSC C API does not export; on
   Apple platforms the same call sites can be backed by the interrupt handler. */
void nx_js_set_time_budget_ms(NxJs* js, int budget_ms);

/* Convenience constructors for native callbacks. */
JSValueRef nx_js_number(JSContextRef ctx, double v);
JSValueRef nx_js_bool(JSContextRef ctx, bool v);
JSValueRef nx_js_string(JSContextRef ctx, const char* s);
JSValueRef nx_js_json(JSContextRef ctx, const char* json); /* parse JSON literal */

#endif /* NATIVAX_JS_ENGINE_H */
