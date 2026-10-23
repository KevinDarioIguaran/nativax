#ifndef NATIVAX_MIR_H
#define NATIVAX_MIR_H

#include <stddef.h>
#include <stdint.h>

void *nx_mir_compile_return_i32(int32_t value);
void nx_mir_finish(void);

#endif /* NATIVAX_MIR_H */
