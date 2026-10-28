/*
    JavaScriptCore integration tests: eval, JSON boundary, native functions,
    exceptions, execution budget, timers/intervals/rAF with virtual time.
*/
#include "nativax/js_engine.h"
#include "nativax/js_loop.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static int g_failures;
static int g_checks;

#define CHECK(cond, ...)                                            \
    do {                                                            \
        g_checks++;                                                 \
        if (!(cond)) {                                              \
            g_failures++;                                           \
            fprintf(stderr, "FAIL %s:%d: ", __FILE__, __LINE__);    \
            fprintf(stderr, __VA_ARGS__);                           \
            fputc('\n', stderr);                                    \
        }                                                           \
    } while (0)

static double wall_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec * 1000.0 + (double)ts.tv_nsec / 1e6;
}

static void test_eval(void) {
    NxJs* js = nx_js_new();
    CHECK(js != NULL, "context created");
    if (!js) return;
    char* err = NULL;

    char* r = nx_js_eval_json(js, "1+1", &err);
    CHECK(r && strcmp(r, "2") == 0, "1+1 -> %s (err=%s)", r ? r : "NULL", err ? err : "-");
    free(r);

    r = nx_js_eval_json(js, "'na' + 'tiva'", &err);
    CHECK(r && strcmp(r, "\"nativa\"") == 0, "string concat -> %s", r ? r : "NULL");
    free(r);

    r = nx_js_eval_json(js, "({a: [1, 2], b: 'x'})", &err);
    CHECK(r && strstr(r, "\"a\"") && strstr(r, "\"b\""), "object json -> %s", r ? r : "NULL");
    free(r);

    r = nx_js_eval_json(js, "undefined", &err);
    CHECK(r && strcmp(r, "null") == 0, "undefined -> null (%s)", r ? r : "NULL");
    free(r);

    r = nx_js_eval_json(js, "Math.max(3, 9, 1)", &err);
    CHECK(r && strcmp(r, "9") == 0, "Math.max -> %s", r ? r : "NULL");
    free(r);

    /* exceptions surface as errors with the message */
    bool ok = nx_js_eval(js, "throw new Error('boom')", "<t>", &err);
    CHECK(!ok && err && strstr(err, "boom") != NULL, "exception captured: %s", err ? err : "NULL");
    free(err);
    err = NULL;

    ok = nx_js_eval(js, "syntax ( error", "<t>", &err);
    CHECK(!ok && err != NULL, "syntax error captured: %s", err ? err : "NULL");
    free(err);
    err = NULL;

    /* state persists across evals */
    ok = nx_js_eval(js, "var counter = 41;", NULL, &err);
    CHECK(ok, "eval ok: %s", err ? err : "-");
    r = nx_js_eval_json(js, "++counter", &err);
    CHECK(r && strcmp(r, "42") == 0, "state persists -> %s", r ? r : "NULL");
    free(r);
    free(err);
    nx_js_free(js);
}

/* native add() exposed to JS */
static JSValueRef native_add(JSContextRef ctx, JSObjectRef fn, JSObjectRef self, size_t argc,
                             const JSValueRef argv[], void* user) {
    (void)fn;
    (void)self;
    (void)user;
    double a = argc > 0 ? JSValueToNumber(ctx, argv[0], NULL) : 0;
    double b = argc > 1 ? JSValueToNumber(ctx, argv[1], NULL) : 0;
    return nx_js_number(ctx, a + b);
}

static JSValueRef native_echo_json(JSContextRef ctx, JSObjectRef fn, JSObjectRef self, size_t argc,
                                   const JSValueRef argv[], void* user) {
    (void)fn;
    (void)self;
    (void)user;
    if (argc < 1) return nx_js_string(ctx, "null");
    char* json = nx_js_value_to_json(ctx, argv[0]);
    JSValueRef v = nx_js_json(ctx, json); /* round-trip: boundary is pure JSON */
    free(json);
    return v;
}

static void test_native_functions(void) {
    NxJs* js = nx_js_new();
    char* err = NULL;
    CHECK(nx_js_set_function(js, "add", native_add, NULL), "bind add");
    CHECK(nx_js_set_function(js, "echoJson", native_echo_json, NULL), "bind echoJson");

    char* r = nx_js_eval_json(js, "add(2, 40)", &err);
    CHECK(r && strcmp(r, "42") == 0, "native add -> %s", r ? r : "NULL");
    free(r);

    r = nx_js_eval_json(js, "echoJson({x: [1, 'two']})", &err);
    CHECK(r && strstr(r, "\"x\"") && strstr(r, "\"two\""), "json round trip -> %s", r ? r : "NULL");
    free(r);
    free(err);
    nx_js_free(js);
}

static void test_call_json(void) {
    NxJs* js = nx_js_new();
    char* err = NULL;
    CHECK(nx_js_eval(js, "function mul(a, b) { return a * b; }", NULL, &err), "define mul");
    char* r = nx_js_call_json(js, "mul", "[6, 7]", &err);
    CHECK(r && strcmp(r, "42") == 0, "call_json mul -> %s (err=%s)", r ? r : "NULL", err ? err : "-");
    free(r);
    r = nx_js_call_json(js, "missingFn", "[]", &err);
    CHECK(!r && err != NULL, "missing function is an error");
    free(err);
    err = NULL;
    nx_js_free(js);
}

static void test_time_budget(void) {
    NxJs* js = nx_js_new();
    nx_js_set_time_budget_ms(js, 10);
    char* err = NULL;
    /* soft budget: bounded busy work completes, warning logged (hard abort is
       unavailable in WebKitGTK's JSC C API — see risk register) */
    double t0 = wall_ms();
    bool ok = nx_js_eval(js, "var s = 0; for (var i = 0; i < 3e7; i++) s += i;", "<budget>", &err);
    double elapsed = wall_ms() - t0;
    CHECK(ok, "bounded busy loop completes: %s", err ? err : "-");
    CHECK(elapsed > 10.0, "loop actually did work (%.0f ms)", elapsed);
    free(err);
    err = NULL;
    /* context stays usable */
    char* r = nx_js_eval_json(js, "6 * 7", &err);
    CHECK(r && strcmp(r, "42") == 0, "context usable after slow script -> %s", r ? r : "NULL");
    free(r);
    free(err);
    nx_js_free(js);
}

static void test_timers(void) {
    NxJs* js = nx_js_new();
    NxLoop* loop = nx_loop_new(js);
    nx_loop_bind(loop);
    char* err = NULL;
    CHECK(nx_js_eval(js,
                     "var log = [];"
                     "setTimeout(function(){ log.push('a'); }, 10);"
                     "setTimeout(function(){ log.push('c'); }, 30);"
                     "setTimeout(function(){ log.push('b'); }, 20);",
                     NULL, &err),
          "schedule timers: %s", err ? err : "-");
    CHECK(nx_loop_pending_timers(loop) == 3, "3 timers pending");

    nx_loop_run(loop, 5); /* nothing due yet */
    char* r = nx_js_eval_json(js, "log.length", &err);
    CHECK(r && strcmp(r, "0") == 0, "nothing due at 5ms -> %s", r ? r : "NULL");
    free(r);

    nx_loop_run(loop, 25); /* a (10) and b (20) due, in order */
    r = nx_js_eval_json(js, "log.join(',')", &err);
    CHECK(r && strcmp(r, "\"a,b\"") == 0, "due order at 25ms -> %s", r ? r : "NULL");
    free(r);
    CHECK(nx_loop_pending_timers(loop) == 1, "1 timer left");

    nx_loop_run(loop, 35);
    r = nx_js_eval_json(js, "log.join(',')", &err);
    CHECK(r && strcmp(r, "\"a,b,c\"") == 0, "final order -> %s", r ? r : "NULL");
    free(r);
    CHECK(nx_loop_pending_timers(loop) == 0, "no timers left");

    /* setInterval repeats; clearInterval stops it */
    CHECK(nx_js_eval(js,
                     "var ticks = 0;"
                     "var iv = setInterval(function(){ ticks++; }, 10);",
                     NULL, &err),
          "schedule interval");
    nx_loop_run(loop, 45);
    nx_loop_run(loop, 65);
    r = nx_js_eval_json(js, "ticks", &err);
    CHECK(r && strcmp(r, "2") == 0, "interval fired twice -> %s", r ? r : "NULL");
    free(r);
    CHECK(nx_js_eval(js, "clearInterval(iv)", NULL, &err), "clearInterval");
    nx_loop_run(loop, 100);
    r = nx_js_eval_json(js, "ticks", &err);
    CHECK(r && strcmp(r, "2") == 0, "interval cleared -> %s", r ? r : "NULL");
    free(r);

    /* clearTimeout */
    CHECK(nx_js_eval(js, "var tid = setTimeout(function(){ log.push('X'); }, 5); clearTimeout(tid);",
                     NULL, &err),
          "clearTimeout");
    nx_loop_run(loop, 200);
    r = nx_js_eval_json(js, "log.indexOf('X')", &err);
    CHECK(r && strcmp(r, "-1") == 0, "timeout cleared -> %s", r ? r : "NULL");
    free(r);

    /* timer limit */
    CHECK(nx_js_eval(js, "for (var i = 0; i < 2000; i++) setTimeout(function(){}, 1000);", NULL,
                     &err),
          "schedule flood");
    CHECK(nx_loop_pending_timers(loop) <= 1000 + 1, "timer cap enforced (%d)",
          nx_loop_pending_timers(loop));

    free(err);
    nx_loop_free(loop);
    nx_js_free(js);
}

static void test_raf(void) {
    NxJs* js = nx_js_new();
    NxLoop* loop = nx_loop_new(js);
    nx_loop_bind(loop);
    char* err = NULL;
    CHECK(nx_js_eval(js,
                     "var frames = 0;"
                     "var tickId; function tick(){ frames++; tickId = requestAnimationFrame(tick); }"
                     "requestAnimationFrame(tick);"
                     "requestAnimationFrame(function(){ frames += 10; });",
                     NULL, &err),
          "queue rAF: %s", err ? err : "-");
    CHECK(nx_loop_pending_frames(loop) == 2, "2 callbacks queued");

    nx_loop_frame(loop, 16.7);
    char* r = nx_js_eval_json(js, "frames", &err);
    CHECK(r && strcmp(r, "11") == 0, "frame ran both callbacks -> %s", r ? r : "NULL");
    free(r);
    CHECK(nx_loop_pending_frames(loop) == 1, "re-queued callback pending");

    nx_loop_frame(loop, 33.3);
    r = nx_js_eval_json(js, "frames", &err);
    CHECK(r && strcmp(r, "12") == 0, "second frame -> %s", r ? r : "NULL");
    free(r);

    /* cancelAnimationFrame (clear both the re-queued tick and a fresh one) */
    CHECK(nx_js_eval(js,
                     "var rid = requestAnimationFrame(function(){});"
                     "cancelAnimationFrame(rid); cancelAnimationFrame(tickId);",
                     NULL, &err),
          "cancel rAF");
    CHECK(nx_loop_pending_frames(loop) == 0, "canceled rAF removed");
    free(err);
    nx_loop_free(loop);
    nx_js_free(js);
}

static void test_microtasks(void) {
    NxJs* js = nx_js_new();
    char* err = NULL;
    /* promise callbacks must run before the next macrotask (empirical JSC
       behavior on API boundaries; if this fails the loop needs an explicit
       drain) */
    bool ok = nx_js_eval(js,
                         "var done = false;"
                         "Promise.resolve().then(function(){ done = 'micro'; });",
                         NULL, &err);
    CHECK(ok, "promise scheduled: %s", err ? err : "-");
    char* r = nx_js_eval_json(js, "done", &err);
    CHECK(r && strcmp(r, "\"micro\"") == 0, "microtask drained before next eval -> %s",
          r ? r : "NULL");
    free(r);
    free(err);
    nx_js_free(js);
}

int main(void) {
    test_eval();
    test_native_functions();
    test_call_json();
    test_time_budget();
    test_timers();
    test_raf();
    test_microtasks();
    fprintf(stderr, "%d checks, %d failures\n", g_checks, g_failures);
    return g_failures == 0 ? 0 : 1;
}
