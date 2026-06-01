/* gpu.c — GPU 2D accelerator driver */
#include "gpu.h"

#ifdef LOCAL_BUILD
/* GPU not available in local build — stubs (callers use CPU fallback) */
void gpu_fill_rect(uint32_t addr, uint16_t w, uint16_t h,
                   uint16_t stride, uint16_t color) {
    (void)addr; (void)w; (void)h; (void)stride; (void)color;
}
int gpu_busy(void) { return 0; }
void gpu_wait(void) { }
#else
#include <neorv32.h>

void gpu_fill_rect(uint32_t addr, uint16_t w, uint16_t h,
                   uint16_t stride, uint16_t color) {
    volatile uint32_t *gpu = GPU_BASE;
    gpu[GPU_REG_DST_ADDR]  = addr;
    gpu[GPU_REG_WIDTH]     = w;
    gpu[GPU_REG_HEIGHT]    = h;
    gpu[GPU_REG_DST_STRIDE] = stride;
    gpu[GPU_REG_COLOR]     = color;
    gpu[GPU_REG_CONTROL]   = 1;  /* trigger FILL */
}

int gpu_busy(void) {
    return (int)(GPU_BASE[GPU_REG_STATUS] & 1u);
}

void gpu_wait(void) {
    while (gpu_busy()) ;
}
#endif
