#ifndef NATIVAX_JS_LOOP_H
#define NATIVAX_JS_LOOP_H

/*
    Event loop: timers (setTimeout/setInterval), requestAnimationFrame and
    the microtask drain policy, mirroring the V1 runtime contract:

    - synchronous entry -> drain microtasks (JSC drains at API boundaries)
      -> run due timers -> rAF once per frame;
    - no setImmediate;
    - timer ids are positive int32; rAF ids negative (unambiguous).
    Time is injected (virtual in tests, frame clock in the runtime).
*/

#include "nativax/js_engine.h"

#include <stdbool.h>
#include <stdint.h>

typedef struct NxLoop NxLoop;

NxLoop* nx_loop_new(NxJs* js);
void nx_loop_free(NxLoop* loop);

/* Bind setTimeout/clearTimeout/setInterval/clearInterval/
   requestAnimationFrame/cancelAnimationFrame on the global object. */
void nx_loop_bind(NxLoop* loop);

/* Advance virtual time and run everything due (timers only). */
void nx_loop_run(NxLoop* loop, double now_ms);

/* Fire one animation frame: runs all currently queued rAF callbacks. */
void nx_loop_frame(NxLoop* loop, double now_ms);

int nx_loop_pending_timers(NxLoop* loop);
int nx_loop_pending_frames(NxLoop* loop);

#endif /* NATIVAX_JS_LOOP_H */
