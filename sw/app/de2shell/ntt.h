/* ntt.h — NTT accelerator driver and CLI
 *
 * LOCAL_BUILD: pure-software reference (DIF stages 7→0 + bit-reversal)
 * NEORV32:     MMIO driver for ntt_sdf.vhd @ 0xF000C000
 */

#ifndef NTT_H
#define NTT_H

#include <stdint.h>
#include "vga_hal.h"

#define NTT_N       256
#define NTT_Q       3329
#define NTT_G       17
#define NTT_N_INV   3316   /* 256^{-1} mod 3329 */

/* Register map (byte offsets, matches ntt_sdf.vhd) */
#define NTT_REG_DATA    0x000  /* R/W [0..255] x 12-bit */
#define NTT_REG_CTRL    0x400  /* W   bit0=start, bit1=dir (0=FWD,1=INV) */
#define NTT_REG_STATUS  0x404  /* R   bit0=busy, bit1=done */
#define NTT_REG_CYCLES  0x408  /* R   cycle count [31:0] */

#ifdef LOCAL_BUILD
/* Software NTT engine (matches VHDL algorithm exactly) */
void ntt_sw(uint16_t *a, int inverse);
void ntt_bit_reverse(uint16_t *a);
#else
/* Hardware NTT via MMIO */
#define NTT_BASE ((volatile uint32_t *)0xF000C000u)

static inline void ntt_hw_write(int idx, uint16_t val) {
    NTT_BASE[idx] = (uint32_t)val;
}
static inline uint16_t ntt_hw_read(int idx) {
    return (uint16_t)(NTT_BASE[idx] & 0xFFF);
}
static inline void ntt_hw_start(int inverse) {
    NTT_BASE[0x400 / 4] = 1u | ((uint32_t)(inverse & 1) << 1);
}
static inline uint32_t ntt_hw_status(void) {
    return NTT_BASE[0x404 / 4];
}
static inline uint32_t ntt_hw_cycles(void) {
    return NTT_BASE[0x408 / 4];
}
/* Blocking NTT: loads data, starts engine, polls until done, reads back */
void ntt_hw_exec(uint16_t *a, int inverse);
#endif

extern const program_t prog_ntt;

#endif /* NTT_H */
