/* gpu.h — GPU 2D accelerator driver (Wishbone MMIO @ 0xF0015000)
 *
 * Operations: FILL (solid-color rectangle via SDRAM burst write)
 * Pixel format: RGB565 (16-bit)
 */
#ifndef GPU_H
#define GPU_H

#include <stdint.h>

#define GPU_BASE  ((volatile uint32_t *)0xF0015000u)

#define GPU_REG_CONTROL    0  /* [1:0] opcode: 0=nop, 1=FILL */
#define GPU_REG_STATUS     1  /* [0] busy */
#define GPU_REG_DST_ADDR   2  /* [31:0] destination byte address */
#define GPU_REG_WIDTH      3  /* [15:0] pixels per row */
#define GPU_REG_HEIGHT     4  /* [15:0] number of rows */
#define GPU_REG_DST_STRIDE 5  /* [15:0] destination row stride (bytes) */
#define GPU_REG_COLOR      6  /* [15:0] RGB565 fill color */

/* Start a FILL operation. Returns immediately; use gpu_wait() to block. */
void gpu_fill_rect(uint32_t addr, uint16_t w, uint16_t h,
                   uint16_t stride, uint16_t color);

/* Block until GPU finishes the current operation. */
void gpu_wait(void);

/* Returns 1 if GPU is busy. */
int gpu_busy(void);

#endif /* GPU_H */
