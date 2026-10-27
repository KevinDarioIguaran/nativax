#include "nativax_bridge.h"

#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#include <windows.h>
#else
#include <pthread.h>
#endif

/* Engine-independent native support for nativa_js. Script engines
 * (JavaScriptCore) are bound from Dart at run time; nothing here depends on
 * one. */

void *nx_alloc(int64_t size) { return malloc(size > 0 ? (size_t)size : 1); }

void nx_free(void *ptr) { free(ptr); }

/* --- Native buffer handoff -------------------------------------------------
 * Byte buffers move between Dart and script code (and later between
 * runtimes on different threads) without JSON or base64: the producer parks
 * malloc'd memory under an id and the consumer adopts it. The registry is
 * process-wide and guarded by a mutex. */

typedef struct NxParked {
  int64_t id;
  uint8_t *data;
  size_t len;
  struct NxParked *next;
} NxParked;

#if defined(_WIN32)
static SRWLOCK nx_park_lock = SRWLOCK_INIT;
#define NX_LOCK() AcquireSRWLockExclusive(&nx_park_lock)
#define NX_UNLOCK() ReleaseSRWLockExclusive(&nx_park_lock)
#else
static pthread_mutex_t nx_park_lock = PTHREAD_MUTEX_INITIALIZER;
#define NX_LOCK() pthread_mutex_lock(&nx_park_lock)
#define NX_UNLOCK() pthread_mutex_unlock(&nx_park_lock)
#endif

static NxParked *nx_parked = NULL;
static int64_t nx_next_park_id = 1;

int64_t nx_buffer_put(void *data, int64_t len) {
  NxParked *p = (NxParked *)malloc(sizeof(NxParked));
  if (p == NULL) return 0;
  p->data = (uint8_t *)data;
  p->len = len > 0 ? (size_t)len : 0;
  NX_LOCK();
  p->id = nx_next_park_id++;
  p->next = nx_parked;
  nx_parked = p;
  NX_UNLOCK();
  return p->id;
}

void *nx_buffer_take(int64_t id, int64_t *len) {
  NxParked *found = NULL;
  NX_LOCK();
  for (NxParked **pp = &nx_parked; *pp != NULL; pp = &(*pp)->next) {
    if ((*pp)->id == id) {
      found = *pp;
      *pp = found->next;
      break;
    }
  }
  NX_UNLOCK();
  if (found == NULL) {
    *len = -1;
    return NULL;
  }
  void *data = found->data;
  *len = (int64_t)found->len;
  free(found);
  return data;
}

/* --- Shared memory blocks ---------------------------------------------------
 * Backing store of SharedArrayBuffer objects shared between script runtimes
 * on different threads. Each block carries an atomic reference count; every
 * runtime that exposes it holds one reference and releases it from its
 * ArrayBuffer deallocator, which may run on any thread. Live blocks are
 * tracked so pointers coming from script code can be validated. */

typedef struct {
  volatile int64_t refs;
  size_t len;
} NxSabHeader;

#define NX_SAB_HEADER ((sizeof(NxSabHeader) + 15) & ~(size_t)15)

#if defined(_WIN32)
#define NX_ATOMIC_INC(p) InterlockedIncrement64((volatile LONG64 *)(p))
#define NX_ATOMIC_DEC(p) InterlockedDecrement64((volatile LONG64 *)(p))
#else
#define NX_ATOMIC_INC(p) __atomic_add_fetch((p), 1, __ATOMIC_SEQ_CST)
#define NX_ATOMIC_DEC(p) __atomic_sub_fetch((p), 1, __ATOMIC_SEQ_CST)
#endif

static NxSabHeader *nx_sab_header(void *data) {
  return (NxSabHeader *)((uint8_t *)data - NX_SAB_HEADER);
}

typedef struct NxSabNode {
  void *data;
  struct NxSabNode *next;
} NxSabNode;

static NxSabNode *nx_sab_live = NULL;

typedef struct NxSabShare {
  int64_t id;
  void *data;
  struct NxSabShare *next;
} NxSabShare;

static NxSabShare *nx_sab_shares = NULL;
static int64_t nx_next_sab_id = 1;

void *nx_sab_alloc(int64_t len) {
  size_t n = len > 0 ? (size_t)len : 0;
  uint8_t *raw = (uint8_t *)calloc(1, NX_SAB_HEADER + (n > 0 ? n : 1));
  NxSabNode *node = (NxSabNode *)malloc(sizeof(NxSabNode));
  if (raw == NULL || node == NULL) {
    free(raw);
    free(node);
    return NULL;
  }
  NxSabHeader *h = (NxSabHeader *)raw;
  h->refs = 1;
  h->len = n;
  node->data = raw + NX_SAB_HEADER;
  NX_LOCK();
  node->next = nx_sab_live;
  nx_sab_live = node;
  NX_UNLOCK();
  return node->data;
}

int32_t nx_sab_is_block(void *data) {
  int32_t found = 0;
  NX_LOCK();
  for (NxSabNode *n = nx_sab_live; n != NULL; n = n->next) {
    if (n->data == data) {
      found = 1;
      break;
    }
  }
  NX_UNLOCK();
  return found;
}

int64_t nx_sab_length(void *data) { return (int64_t)nx_sab_header(data)->len; }

void nx_sab_release(void *data, void *context) {
  (void)context;
  if (data == NULL || NX_ATOMIC_DEC(&nx_sab_header(data)->refs) != 0) return;
  NX_LOCK();
  for (NxSabNode **pp = &nx_sab_live; *pp != NULL; pp = &(*pp)->next) {
    if ((*pp)->data == data) {
      NxSabNode *dead = *pp;
      *pp = dead->next;
      free(dead);
      break;
    }
  }
  NX_UNLOCK();
  free(nx_sab_header(data));
}

int64_t nx_sab_share(void *data) {
  if (!nx_sab_is_block(data)) return 0;
  NxSabShare *s = (NxSabShare *)malloc(sizeof(NxSabShare));
  if (s == NULL) return 0;
  NX_ATOMIC_INC(&nx_sab_header(data)->refs);
  s->data = data;
  NX_LOCK();
  s->id = nx_next_sab_id++;
  s->next = nx_sab_shares;
  nx_sab_shares = s;
  NX_UNLOCK();
  return s->id;
}

void *nx_sab_open(int64_t id) {
  NxSabShare *found = NULL;
  NX_LOCK();
  for (NxSabShare **pp = &nx_sab_shares; *pp != NULL; pp = &(*pp)->next) {
    if ((*pp)->id == id) {
      found = *pp;
      *pp = found->next;
      break;
    }
  }
  NX_UNLOCK();
  if (found == NULL) return NULL;
  void *data = found->data;
  free(found);
  return data;
}

/* --- Atomics.wait / Atomics.notify on shared blocks -------------------------
 * A futex over 32-bit cells: waiters register under nx_wait_lock after
 * checking the value, and notify wakes them in arrival order. Checking and
 * registering under the same lock that notify takes means a notify that
 * follows a store cannot be lost. */

#if defined(_WIN32)
static SRWLOCK nx_wait_lock = SRWLOCK_INIT;
#define NX_WAIT_LOCK() AcquireSRWLockExclusive(&nx_wait_lock)
#define NX_WAIT_UNLOCK() ReleaseSRWLockExclusive(&nx_wait_lock)
typedef CONDITION_VARIABLE NxCond;
#else
#include <errno.h>
#include <time.h>
static pthread_mutex_t nx_wait_lock = PTHREAD_MUTEX_INITIALIZER;
#define NX_WAIT_LOCK() pthread_mutex_lock(&nx_wait_lock)
#define NX_WAIT_UNLOCK() pthread_mutex_unlock(&nx_wait_lock)
typedef pthread_cond_t NxCond;
#endif

typedef struct NxWaiter {
  void *addr;
  int notified;
  NxCond cond;
  struct NxWaiter *next;
} NxWaiter;

static NxWaiter *nx_waiters_head = NULL;
static NxWaiter *nx_waiters_tail = NULL;

static void nx_waiter_unlink(NxWaiter *w) {
  NxWaiter *prev = NULL;
  for (NxWaiter *cur = nx_waiters_head; cur != NULL; prev = cur, cur = cur->next) {
    if (cur != w) continue;
    if (prev) prev->next = cur->next; else nx_waiters_head = cur->next;
    if (nx_waiters_tail == cur) nx_waiters_tail = prev;
    return;
  }
}

/* 0 = "ok", 1 = "not-equal", 2 = "timed-out". [timeout_ms] < 0 waits
 * without a deadline. */
int32_t nx_sab_wait(void *addr, int32_t expected, double timeout_ms) {
  NxWaiter w;
  w.addr = addr;
  w.notified = 0;
  w.next = NULL;
  NX_WAIT_LOCK();
#if defined(_WIN32)
  int32_t current = InterlockedCompareExchange((volatile LONG *)addr, 0, 0);
#else
  int32_t current = __atomic_load_n((int32_t *)addr, __ATOMIC_SEQ_CST);
#endif
  if (current != expected) {
    NX_WAIT_UNLOCK();
    return 1;
  }
#if defined(_WIN32)
  InitializeConditionVariable(&w.cond);
#else
  pthread_cond_init(&w.cond, NULL);
#endif
  if (nx_waiters_tail) nx_waiters_tail->next = &w; else nx_waiters_head = &w;
  nx_waiters_tail = &w;
  int timed_out = 0;
#if defined(_WIN32)
  ULONGLONG start = GetTickCount64();
  while (!w.notified) {
    DWORD wait_ms = INFINITE;
    if (timeout_ms >= 0) {
      double left = timeout_ms - (double)(GetTickCount64() - start);
      if (left <= 0) { timed_out = 1; break; }
      wait_ms = (DWORD)left;
    }
    SleepConditionVariableSRW(&w.cond, &nx_wait_lock, wait_ms, 0);
  }
#else
  struct timespec deadline;
  if (timeout_ms >= 0) {
    clock_gettime(CLOCK_REALTIME, &deadline);
    double secs = timeout_ms / 1000.0;
    deadline.tv_sec += (time_t)secs;
    deadline.tv_nsec += (long)((secs - (double)(time_t)secs) * 1e9);
    if (deadline.tv_nsec >= 1000000000L) {
      deadline.tv_sec += 1;
      deadline.tv_nsec -= 1000000000L;
    }
  }
  while (!w.notified) {
    int rc = timeout_ms >= 0
                 ? pthread_cond_timedwait(&w.cond, &nx_wait_lock, &deadline)
                 : pthread_cond_wait(&w.cond, &nx_wait_lock);
    if (rc == ETIMEDOUT && !w.notified) { timed_out = 1; break; }
  }
#endif
  nx_waiter_unlink(&w);
  NX_WAIT_UNLOCK();
#if !defined(_WIN32)
  pthread_cond_destroy(&w.cond);
#endif
  return timed_out ? 2 : 0;
}

/* Wakes up to [count] waiters on [addr] (count < 0: all); returns how many. */
int32_t nx_sab_notify(void *addr, int32_t count) {
  int32_t woken = 0;
  NX_WAIT_LOCK();
  for (NxWaiter *w = nx_waiters_head; w != NULL; w = w->next) {
    if (count >= 0 && woken >= count) break;
    if (w->addr != addr || w->notified) continue;
    w->notified = 1;
    woken++;
#if defined(_WIN32)
    WakeConditionVariable(&w->cond);
#else
    pthread_cond_signal(&w->cond);
#endif
  }
  NX_WAIT_UNLOCK();
  return woken;
}
