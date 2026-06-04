/* fb_hal.c — Pixel Framebuffer HAL implementation (dual-mode)
 *
 * LOCAL_BUILD: SDL2 window + texture rendering
 * NEORV32:     SDRAM linear framebuffer at FRAMEBUFFER_BASE + GPU 2D accel
 *
 * Pixel format: RGB565 (16-bit per pixel)
 */

#include "fb_hal.h"

#ifdef LOCAL_BUILD
  /* ── SDL2 backend ──────────────────────────────────────────── */
  #include <SDL.h>

  static SDL_Window   *window;
  static SDL_Renderer *renderer;
  static SDL_Texture  *texture;
  static uint16_t      fb[FB_H][FB_W];

  void fb_init(void) {
      if (SDL_Init(SDL_INIT_VIDEO) != 0) {
          SDL_Log("SDL_Init failed: %s", SDL_GetError());
          return;
      }
      window = SDL_CreateWindow("DE2Extra VGA",
                                SDL_WINDOWPOS_CENTERED,
                                SDL_WINDOWPOS_CENTERED,
                                FB_W * 2, FB_H * 2,  /* 2x scale */
                                0);
      if (!window) {
          SDL_Log("SDL_CreateWindow failed: %s", SDL_GetError());
          return;
      }
      renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_SOFTWARE);
      texture = SDL_CreateTexture(renderer,
                                   SDL_PIXELFORMAT_RGB565,
                                   SDL_TEXTUREACCESS_STREAMING,
                                   FB_W, FB_H);
      fb_clear(FB_BLACK);
  }

  void fb_set_pixel(int x, int y, uint16_t color) {
      if (x >= 0 && x < FB_W && y >= 0 && y < FB_H)
          fb[y][x] = color;
  }

  uint16_t fb_get_pixel(int x, int y) {
      if (x >= 0 && x < FB_W && y >= 0 && y < FB_H)
          return fb[y][x];
      return 0;
  }

  int fb_poll_events(void) {
      SDL_Event e;
      while (SDL_PollEvent(&e)) {
          if (e.type == SDL_QUIT) return 0;
      }
      return 1;
  }

  void fb_present(void) {
      uint16_t *pixels;
      int pitch;
      SDL_LockTexture(texture, NULL, (void **)&pixels, &pitch);
      for (int y = 0; y < FB_H; y++) {
          SDL_memcpy(pixels + y * (pitch / 2), fb[y], FB_W * 2);
      }
      SDL_UnlockTexture(texture);
      SDL_RenderCopy(renderer, texture, NULL, NULL);
      SDL_RenderPresent(renderer);
      fb_poll_events();
  }

  void fb_clear(uint16_t color) {
      for (int i = 0; i < FB_H * FB_W; i++)
          ((uint16_t *)fb)[i] = color;
  }

  void fb_set_debug_pattern(int enabled) {
      (void)enabled;
  }

  void fb_shutdown(void) {
      if (texture)  SDL_DestroyTexture(texture);
      if (renderer) SDL_DestroyRenderer(renderer);
      if (window)   SDL_DestroyWindow(window);
      SDL_Quit();
  }

#else
  /* ── NEORV32 SDRAM backend ─────────────────────────────────── */
  #include <neorv32.h>
  #include "gpu.h"

  #define FRAMEBUFFER_BASE 0x01800000u
  #define VGA_BASE         0xF0000000u
  #define VGA_PX_MODE      0x7000u
  #define VGA_PX_FB_BASE   0x7004u
  #define VGA_PX_TESTPAT   0x00000002u

  static volatile uint16_t * const fb = (volatile uint16_t *)FRAMEBUFFER_BASE;
  static volatile uint32_t * const vga_regs = (volatile uint32_t *)VGA_BASE;
  static uint32_t fb_mode_flags = 1u;

  static void fb_hw_mode_set(uint32_t enable) {
      vga_regs[VGA_PX_FB_BASE / 4u] = FRAMEBUFFER_BASE;
      vga_regs[VGA_PX_MODE / 4u] = enable ? fb_mode_flags : 0u;
  }

  void fb_init(void) {
      fb_mode_flags = 1u;  /* pixel mode on, no test pattern */
      fb_hw_mode_set(1u);
  }

  void fb_set_pixel(int x, int y, uint16_t color) {
      if (x >= 0 && x < FB_W && y >= 0 && y < FB_H)
          fb[y * FB_W + x] = color;
  }

  uint16_t fb_get_pixel(int x, int y) {
      if (x >= 0 && x < FB_W && y >= 0 && y < FB_H)
          return fb[y * FB_W + x];
      return 0;
  }

  void fb_present(void) {
      /* No-op on FPGA: VGA controller reads SDRAM continuously */
  }

  void fb_clear(uint16_t color) {
      for (int i = 0; i < FB_H * FB_W; i++)
          ((volatile uint16_t *)fb)[i] = color;
  }

  void fb_set_debug_pattern(int enabled) {
      if (enabled) {
          fb_mode_flags |= VGA_PX_TESTPAT;
      } else {
          fb_mode_flags &= ~VGA_PX_TESTPAT;
      }
      fb_hw_mode_set(1u);
  }

  void fb_shutdown(void) {
      fb_mode_flags = 1u;
      fb_hw_mode_set(0u);
  }

#endif
