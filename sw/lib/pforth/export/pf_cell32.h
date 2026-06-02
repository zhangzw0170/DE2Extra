/* pf_cell32.h -- Force 32-bit cells for dictionary export targeting RV32.
 *
 * Include before pforth.h via: gcc -include export/pf_cell32.h
 * After pforth.h includes <stdint.h>, we undef the 64-bit types
 * and redefine them as 32-bit. pforth.h then does typedef intptr_t cell_t
 * which picks up our 32-bit override.
 */
#ifndef PF_CELL32_H
#define PF_CELL32_H

#include <stdint.h>

#undef intptr_t
#undef uintptr_t
#define intptr_t int32_t
#define uintptr_t uint32_t

#endif /* PF_CELL32_H */
