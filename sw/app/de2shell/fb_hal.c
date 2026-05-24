/* fb_hal.c — Pixel Framebuffer HAL implementation (dual-mode)
 *
 * LOCAL_BUILD: SDL2 window + texture rendering
 * NEORV32:     SDRAM linear framebuffer at FRAMEBUFFER_BASE
 */

#include "fb_hal.h"

#ifdef LOCAL_BUILD
  /* ── SDL2 backend ──────────────────────────────────────────── */
  #include <SDL.h>

  static SDL_Window   *window;
  static SDL_Renderer *renderer;
  static SDL_Texture  *texture;
  static uint8_t       fb[FB_H][FB_W];

  /* RGB332 to SDL_Color lookup */
  static SDL_Color palette[256];

  static void build_palette(void) {
      for (int i = 0; i < 256; i++) {
          palette[i].r = (uint8_t)(((i >> 5) & 0x07) * 255 / 7);
          palette[i].g = (uint8_t)(((i >> 2) & 0x07) * 255 / 7);
          palette[i].b = (uint8_t)(( i       & 0x03) * 255 / 3);
          palette[i].a = 255;
      }
  }

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
                                   SDL_PIXELFORMAT_RGB332,
                                   SDL_TEXTUREACCESS_STREAMING,
                                   FB_W, FB_H);
      build_palette();
      fb_clear(FB_BLACK);
  }

  void fb_set_pixel(int x, int y, uint8_t color) {
      if (x >= 0 && x < FB_W && y >= 0 && y < FB_H)
          fb[y][x] = color;
  }

  uint8_t fb_get_pixel(int x, int y) {
      if (x >= 0 && x < FB_W && y >= 0 && y < FB_H)
          return fb[y][x];
      return 0;
  }

  void fb_present(void) {
      uint8_t *pixels;
      int pitch;
      SDL_LockTexture(texture, NULL, (void **)&pixels, &pitch);
      for (int y = 0; y < FB_H; y++) {
          SDL_memcpy(pixels + y * pitch, fb[y], FB_W);
      }
      SDL_UnlockTexture(texture);
      SDL_RenderCopy(renderer, texture, NULL, NULL);
      SDL_RenderPresent(renderer);
  }

  void fb_clear(uint8_t color) {
      SDL_memset(fb, color, sizeof(fb));
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

  /* Framebuffer base in SDRAM — must match VGA pixel mode config */
  #define FRAMEBUFFER_BASE 0x01000000

  static volatile uint8_t * const fb = (volatile uint8_t *)FRAMEBUFFER_BASE;

  void fb_init(void) {
      /* SDRAM should already be initialized by bootloader.
       * Just clear the framebuffer. */
      fb_clear(FB_BLACK);
  }

  void fb_set_pixel(int x, int y, uint8_t color) {
      if (x >= 0 && x < FB_W && y >= 0 && y < FB_H)
          fb[y * FB_W + x] = color;
  }

  uint8_t fb_get_pixel(int x, int y) {
      if (x >= 0 && x < FB_W && y >= 0 && y < FB_H)
          return fb[y * FB_W + x];
      return 0;
  }

  void fb_present(void) {
      /* No-op on FPGA: VGA controller reads SDRAM continuously */
  }

  void fb_clear(uint8_t color) {
      for (int i = 0; i < FB_W * FB_H; i++)
          fb[i] = color;
  }

  void fb_shutdown(void) {
      /* No-op */
  }

#endif
