/* ntt.h — NTT driver and CLI
 *
 * Software-only NTT (DIF Cooley-Tukey stages 7→0 + bit-reversal).
 * Hardware accelerator removed from synthesis; SW NTT used as fallback.
 */

#ifndef NTT_H
#define NTT_H

#include <stdint.h>
#include "vga_hal.h"

#define NTT_N       256
#define NTT_Q       3329
#define NTT_G       17
#define NTT_N_INV   3316   /* 256^{-1} mod 3329 */

void ntt_sw(uint16_t *a, int inverse);
void ntt_bit_reverse(uint16_t *a);

extern const program_t prog_ntt;

#endif /* NTT_H */
