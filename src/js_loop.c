#include "nativax/js_loop.h"

#include "nativax/log.h"

#include <stdlib.h>
#include <string.h>

#define NX_MAX_TIMERS 1000
#define NX_MIN_INTERVAL_MS 4.0

typedef struct Timer {
    int32_t id;            /* >0 timers, <0 rAF */
    JSObjectRef callback;  /* protected */
    double due_ms;
    double interval_ms;    /* 0 = timeout */
    bool pending;
} Timer;

struct NxLoop {
    NxJs* js;
    Timer* timers;
    int count, cap;
    int32_t next_id;
};

/* ---- internals ---- */
static Timer* timer_slot(NxLoop* loop) {
    /* reuse removed slots first */
    for (int i = 0; i < loop->count; i++) {
        if (!loop->timers[i].pending) return &loop->timers[i];
    }
    if (loop->count == loop->cap) {
        loop->cap = loop->cap ? loop->cap * 2 : 32;
        loop->timers = realloc(loop->timers, (size_t)loop->cap * sizeof(Timer));
    }
    return &loop->timers[loop->count++];
}

static int pending_count(const NxLoop* loop) {
    int n = 0;
    for (int i = 0; i < loop->count; i++) n += loop->timers[i].pending ? 1 : 0;
    return n;
}

static int32_t schedule(NxLoop* loop, JSContextRef ctx, JSObjectRef cb, double delay_ms,
                        double interval_ms) {
    if (pending_count(loop) >= NX_MAX_TIMERS) {
        NX_WARN("timer limit reached (%d), refusing new timer", NX_MAX_TIMERS);
        return 0;
    }
    if (interval_ms > 0 && interval_ms < NX_MIN_INTERVAL_MS) interval_ms = NX_MIN_INTERVAL_MS;
    if (delay_ms < 0) delay_ms = 0;
    Timer* t = timer_slot(loop);
    t->id = loop->next_id++;
    t->callback = cb;
    JSValueProtect(ctx, cb);
    t->due_ms = 0; /* set by caller after reading now — see run() note */
    t->interval_ms = interval_ms;
    t->pending = true;
    return t->id;
}

/* ---- native bindings ---- */
static double g_now; /* current loop time, set by nx_loop_run/frame */

static JSValueRef js_set_timeout(JSContextRef ctx, JSObjectRef fn, JSObjectRef self, size_t argc,
                                 const JSValueRef argv[], void* user) {
    (void)fn;
    (void)self;
    NxLoop* loop = (NxLoop*)user;
    if (argc < 1 || !JSValueIsObject(ctx, argv[0])) return nx_js_number(ctx, 0);
    double delay = argc > 1 ? JSValueToNumber(ctx, argv[1], NULL) : 0;
    int32_t id = schedule(loop, ctx, (JSObjectRef)argv[0], delay, 0);
    /* due time: g_now + delay (schedule stored delay-relative; fix here) */
    for (int i = 0; i < loop->count; i++) {
        if (loop->timers[i].pending && loop->timers[i].id == id) {
            loop->timers[i].due_ms = g_now + delay;
        }
    }
    return nx_js_number(ctx, id);
}

static JSValueRef js_set_interval(JSContextRef ctx, JSObjectRef fn, JSObjectRef self, size_t argc,
                                  const JSValueRef argv[], void* user) {
    (void)fn;
    (void)self;
    NxLoop* loop = (NxLoop*)user;
    if (argc < 1 || !JSValueIsObject(ctx, argv[0])) return nx_js_number(ctx, 0);
    double delay = argc > 1 ? JSValueToNumber(ctx, argv[1], NULL) : 0;
    if (delay < NX_MIN_INTERVAL_MS) delay = NX_MIN_INTERVAL_MS;
    int32_t id = schedule(loop, ctx, (JSObjectRef)argv[0], delay, delay);
    for (int i = 0; i < loop->count; i++) {
        if (loop->timers[i].pending && loop->timers[i].id == id) {
            loop->timers[i].due_ms = g_now + delay;
        }
    }
    return nx_js_number(ctx, id);
}

static JSValueRef js_clear_timer(JSContextRef ctx, JSObjectRef fn, JSObjectRef self, size_t argc,
                                 const JSValueRef argv[], void* user) {
    (void)fn;
    (void)self;
    NxLoop* loop = (NxLoop*)user;
    if (argc < 1) return nx_js_bool(ctx, false);
    int32_t id = (int32_t)JSValueToNumber(ctx, argv[0], NULL);
    for (int i = 0; i < loop->count; i++) {
        if (loop->timers[i].pending && loop->timers[i].id == id) {
            JSValueUnprotect(ctx, loop->timers[i].callback);
            loop->timers[i].pending = false;
            break;
        }
    }
    return nx_js_bool(ctx, true);
}

static JSValueRef js_raf(JSContextRef ctx, JSObjectRef fn, JSObjectRef self, size_t argc,
                         const JSValueRef argv[], void* user) {
    (void)fn;
    (void)self;
    NxLoop* loop = (NxLoop*)user;
    if (argc < 1 || !JSValueIsObject(ctx, argv[0])) return nx_js_number(ctx, 0);
    Timer* t = timer_slot(loop);
    t->id = -(loop->next_id++); /* negative ids for rAF */
    t->callback = (JSObjectRef)argv[0];
    JSValueProtect(ctx, t->callback);
    t->due_ms = 0;
    t->interval_ms = 0;
    t->pending = true;
    return nx_js_number(ctx, t->id);
}

/* ---- lifecycle ---- */
NxLoop* nx_loop_new(NxJs* js) {
    NxLoop* loop = calloc(1, sizeof(NxLoop));
    loop->js = js;
    loop->next_id = 1;
    return loop;
}

void nx_loop_free(NxLoop* loop) {
    if (!loop) return;
    JSContextRef ctx = nx_js_ctx(loop->js);
    for (int i = 0; i < loop->count; i++) {
        if (loop->timers[i].pending) JSValueUnprotect(ctx, loop->timers[i].callback);
    }
    free(loop->timers);
    free(loop);
}

void nx_loop_bind(NxLoop* loop) {
    NxJs* js = loop->js;
    nx_js_set_function(js, "setTimeout", js_set_timeout, loop);
    nx_js_set_function(js, "setInterval", js_set_interval, loop);
    nx_js_set_function(js, "clearTimeout", js_clear_timer, loop);
    nx_js_set_function(js, "clearInterval", js_clear_timer, loop);
    nx_js_set_function(js, "requestAnimationFrame", js_raf, loop);
    nx_js_set_function(js, "cancelAnimationFrame", js_clear_timer, loop);
}

/* ---- pumping ---- */
static void run_due(NxLoop* loop, double now_ms) {
    JSContextRef ctx = nx_js_ctx(loop->js);
    /* execute in (due, id) order; timers scheduled by callbacks may also become
       due within the same pump if their delay is 0 */
    for (;;) {
        int best = -1;
        for (int i = 0; i < loop->count; i++) {
            Timer* t = &loop->timers[i];
            if (!t->pending || t->id < 0 || t->due_ms > now_ms) continue;
            if (best < 0 || t->due_ms < loop->timers[best].due_ms ||
                (t->due_ms == loop->timers[best].due_ms && t->id < loop->timers[best].id)) {
                best = i;
            }
        }
        if (best < 0) break;
        Timer* t = &loop->timers[best];
        if (t->interval_ms > 0) {
            t->due_ms += t->interval_ms;
            if (t->due_ms <= now_ms) t->due_ms = now_ms + t->interval_ms; /* catch-up guard */
        } else {
            t->pending = false;
        }
        JSValueRef exc = NULL;
        JSObjectRef global = (JSObjectRef)JSContextGetGlobalObject(ctx);
        JSValueRef res = JSObjectCallAsFunction(ctx, t->callback, global, 0, NULL, &exc);
        if (!t->interval_ms) {
            JSValueUnprotect(ctx, t->callback);
        }
        if (!res && exc) {
            char* msg = nx_js_value_to_json(ctx, exc);
            NX_ERROR("uncaught exception in timer: %s", msg);
            free(msg);
        }
    }
}

void nx_loop_run(NxLoop* loop, double now_ms) {
    g_now = now_ms;
    run_due(loop, now_ms);
}

void nx_loop_frame(NxLoop* loop, double now_ms) {
    g_now = now_ms;
    JSContextRef ctx = nx_js_ctx(loop->js);
    /* collect rAF callbacks, then run them (callbacks may queue the next frame) */
    int n = 0;
    JSObjectRef* cbs = malloc(sizeof(JSObjectRef) * (size_t)(pending_count(loop) + 1));
    for (int i = 0; i < loop->count; i++) {
        Timer* t = &loop->timers[i];
        if (t->pending && t->id < 0) {
            cbs[n++] = t->callback;
            JSValueUnprotect(ctx, t->callback);
            t->pending = false;
        }
    }
    JSObjectRef global = (JSObjectRef)JSContextGetGlobalObject(ctx);
    for (int i = 0; i < n; i++) {
        JSValueRef exc = NULL;
        JSValueRef res = JSObjectCallAsFunction(ctx, cbs[i], global, 0, NULL, &exc);
        if (!res && exc) {
            char* msg = nx_js_value_to_json(ctx, exc);
            NX_ERROR("uncaught exception in rAF: %s", msg);
            free(msg);
        }
    }
    free(cbs);
    run_due(loop, now_ms); /* rAF callbacks may schedule immediate timers */
}

int nx_loop_pending_timers(NxLoop* loop) {
    int n = 0;
    for (int i = 0; i < loop->count; i++) {
        if (loop->timers[i].pending && loop->timers[i].id > 0) n++;
    }
    return n;
}

int nx_loop_pending_frames(NxLoop* loop) {
    int n = 0;
    for (int i = 0; i < loop->count; i++) {
        if (loop->timers[i].pending && loop->timers[i].id < 0) n++;
    }
    return n;
}
