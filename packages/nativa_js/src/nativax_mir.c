#include "nativax_mir.h"

#include <stddef.h>

#include "mir.h"
#include "mir-gen.h"

#include "quickjs.h"

static MIR_context_t nx_mir_ctx = NULL;

static void nx_mir_init(void) {
  if (nx_mir_ctx) return;
  nx_mir_ctx = MIR_init();
}

void *nx_mir_compile_return_i32(int32_t value) {
  nx_mir_init();
  if (!nx_mir_ctx) return NULL;

  MIR_module_t mod = MIR_new_module(nx_mir_ctx, "nativax_jit");
  MIR_type_t ret_type = MIR_T_I32;
  MIR_item_t func = MIR_new_func(nx_mir_ctx, "ret_i32", 1, &ret_type, 0);
  MIR_reg_t r = MIR_new_func_reg(nx_mir_ctx, func->u.func, MIR_T_I32, "$r");
  MIR_append_insn(nx_mir_ctx, func,
                  MIR_new_insn(nx_mir_ctx, MIR_MOV,
                               MIR_new_reg_op(nx_mir_ctx, r),
                               MIR_new_int_op(nx_mir_ctx, value)));
  MIR_append_insn(nx_mir_ctx, func,
                  MIR_new_ret_insn(nx_mir_ctx, 1, MIR_new_reg_op(nx_mir_ctx, r)));
  MIR_finish_func(nx_mir_ctx);
  MIR_finish_module(nx_mir_ctx);
  MIR_load_module(nx_mir_ctx, mod);

  MIR_gen_init(nx_mir_ctx);
  MIR_link(nx_mir_ctx, MIR_set_gen_interface, NULL);
  void *addr = MIR_gen(nx_mir_ctx, func);
  MIR_gen_finish(nx_mir_ctx);

  return addr;
}

void nx_mir_finish(void) {
  if (nx_mir_ctx) {
    MIR_finish(nx_mir_ctx);
    nx_mir_ctx = NULL;
  }
}
