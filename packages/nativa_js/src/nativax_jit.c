#include "nativax_jit.h"

#include <stdio.h>
#include <stddef.h>
#include <string.h>

#if defined(__linux__)
#include <sys/mman.h>
#endif

#include "quickjs.h"

static size_t nx_jit_bytes = 0;
static int nx_jit_arg_count = 0;
static int nx_jit_var_count = 0;

int nx_jit_available(void) { return 1; }

void nx_jit_init(void) { (void)0; }

size_t nx_jit_code_bytes(void) { return nx_jit_bytes; }

JSValue nx_jit_ret_undef(void) { return JS_UNDEFINED; }
JSValue nx_jit_ret_i32(int32_t v) { return JS_MKVAL(JS_TAG_INT, v); }

JSValue nx_jit_entry_ret_undef(JSContext *ctx, void *b, void *sf,
                              JSValue *arg_buf, JSValue *var_buf,
                              JSValue *stack_buf, JSValue **sp_ptr) {
  (void)ctx; (void)b; (void)sf; (void)arg_buf; (void)var_buf;
  (void)stack_buf; (void)sp_ptr;
  return JS_UNDEFINED;
}

JSValue nx_jit_entry_ret_loc0(JSContext *ctx, void *b, void *sf,
                              JSValue *arg_buf, JSValue *var_buf,
                              JSValue *stack_buf, JSValue **sp_ptr) {
  (void)b; (void)sf; (void)arg_buf; (void)stack_buf; (void)sp_ptr;
  if (nx_jit_get_var_count() < 1 || !var_buf) return JS_UNDEFINED;
  return JS_DupValue(ctx, var_buf[0]);
}

JSValue nx_jit_entry_ret_arg0(JSContext *ctx, void *b, void *sf,
                             JSValue *arg_buf, JSValue *var_buf,
                             JSValue *stack_buf, JSValue **sp_ptr) {
  (void)b; (void)sf; (void)var_buf; (void)stack_buf; (void)sp_ptr;
  if (nx_jit_get_arg_count() < 1 || !arg_buf) return JS_UNDEFINED;
  return JS_DupValue(ctx, arg_buf[0]);
}

/* Temporarily disabled to isolate segfault. */
void *nx_jit_try_compile(void *rt, void *bytecode) { (void)rt; (void)bytecode; return NULL; }
void *nx_jit_compile_return_undef(void) { return (void *)nx_jit_entry_ret_undef; }
void *nx_jit_compile_return_i32(int32_t value) {
#if defined(__linux__) && defined(__x86_64__)
  unsigned char code[17];
  code[0] = 0xBF;
  *(int32_t *)(code + 1) = value;
  code[5] = 0x48;
  code[6] = 0xB8;
  void *helper = (void *)nx_jit_ret_i32;
  for (int i = 0; i < 8; i++) code[7 + i] = ((unsigned char *)&helper)[i];
  code[15] = 0xFF;
  code[16] = 0xE0;

  size_t page = 4096;
  void *mem = mmap(NULL, page, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
  if (mem == MAP_FAILED) return NULL;
  memcpy(mem, code, sizeof(code));
  if (mprotect(mem, page, PROT_READ | PROT_EXEC) != 0) {
    munmap(mem, page);
    return NULL;
  }
  nx_jit_bytes += page;
  return mem;
#else
  (void)value;
  return NULL;
#endif
}
void *nx_jit_compile_return_loc0(void) { return (void *)nx_jit_entry_ret_loc0; }
void *nx_jit_compile_return_arg0(void) { return (void *)nx_jit_entry_ret_arg0; }

void nx_jit_set_arg_count(int n) { nx_jit_arg_count = n; }
void nx_jit_set_var_count(int n) { nx_jit_var_count = n; }
int nx_jit_get_arg_count(void) { return nx_jit_arg_count; }
int nx_jit_get_var_count(void) { return nx_jit_var_count; }

void nx_jit_free_code(void *code) { (void)code; }
