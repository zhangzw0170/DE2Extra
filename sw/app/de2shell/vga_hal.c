/* vga_hal.c — VGA HAL implementation (dual-mode)
 *
 * LOCAL_BUILD: ANSI terminal via stdout
 * NEORV32:     VGA text buffer via XBUS mapped at 0xF0000000
 */

#include "vga_hal.h"

#ifdef LOCAL_BUILD
  #include <stdio.h>

  #define VGA_BASE 0  /* unused in local mode */

  static int cur_col = 0;
  static int cur_row = 0;

  void vga_init(void) {
      printf("\033[2J\033[H\033[?25l");  /* clear, home, hide cursor */
      cur_col = 0;
      cur_row = 0;
  }

  void vga_putc(char c, uint8_t color) {
      (void)color;  /* ANSI doesn't support per-char RGB332 without OSC codes */
      putchar(c);
      cur_col++;
      if (cur_col >= VGA_COLS) {
          cur_col = 0;
          cur_row++;
      }
  }

  void vga_puts(const char *s, uint8_t color) {
      while (*s) vga_putc(*s++, color);
  }

  void vga_goto(int col, int row) {
      printf("\033[%d;%dH", row + 1, col + 1);
      cur_col = col;
      cur_row = row;
  }

  void vga_clear(void) {
      printf("\033[2J\033[H");
      cur_col = 0;
      cur_row = 0;
  }

  void vga_cursor_show(int show) {
      printf(show ? "\033[?25h" : "\033[?25l");
  }

  int vga_col(void) { return cur_col; }
  int vga_row(void) { return cur_row; }

#else  /* NEORV32 */

  #include <neorv32.h>

  /* VGA text buffer base address (from de2extra_pkg.vhd ADDR_VGA_BASE) */
  #define VGA_BASE  0xF0000000

  /* VGA control registers (offsets from VGA_BASE) */
  #define VGA_CTRL_CURSOR_X  0x1000
  #define VGA_CTRL_CURSOR_Y  0x1004
  #define VGA_CTRL_CONTROL   0x1008
  #define VGA_CTRL_STATUS    0x100C
  #define VGA_CTRL_BGCOLOR   0x1010
  #define VGA_CTRL_CLEAR     0x1014

  #define VGA_CTRL_ENABLE     0x01
  #define VGA_CTRL_BLINK      0x02
  #define VGA_CTRL_PAGE       0x04

  volatile uint16_t * const vga_buf = (volatile uint16_t *)VGA_BASE;

  static int cur_col = 0;
  static int cur_row = 0;
  static uint8_t cur_color = VGA_WHITE;

  void vga_init(void) {
      vga_buf[VGA_CTRL_CLEAR / 2] = 0x0001;        /* clear screen */
      vga_buf[VGA_CTRL_CONTROL / 2] = VGA_CTRL_ENABLE | VGA_CTRL_BLINK;
      vga_buf[VGA_CTRL_BGCOLOR / 2] = VGA_BLACK;
      vga_buf[VGA_CTRL_CURSOR_X / 2] = 0;
      vga_buf[VGA_CTRL_CURSOR_Y / 2] = 0;
      cur_col = 0;
      cur_row = 0;
  }

  void vga_putc(char c, uint8_t color) {
      uint16_t entry = ((uint16_t)color << 8) | ((uint8_t)c);
      int addr = cur_row * VGA_COLS + cur_col;
      vga_buf[addr] = entry;

      cur_col++;
      if (cur_col >= VGA_COLS) {
          cur_col = 0;
          cur_row++;
      }
      /* Update hardware cursor */
      vga_buf[VGA_CTRL_CURSOR_X / 2] = cur_col;
      vga_buf[VGA_CTRL_CURSOR_Y / 2] = cur_row;
  }

  void vga_puts(const char *s, uint8_t color) {
      while (*s) vga_putc(*s++, color);
  }

  void vga_goto(int col, int row) {
      cur_col = col;
      cur_row = row;
      vga_buf[VGA_CTRL_CURSOR_X / 2] = col;
      vga_buf[VGA_CTRL_CURSOR_Y / 2] = row;
  }

  void vga_clear(void) {
      vga_buf[VGA_CTRL_CLEAR / 2] = 0x0001;
      cur_col = 0;
      cur_row = 0;
      vga_buf[VGA_CTRL_CURSOR_X / 2] = 0;
      vga_buf[VGA_CTRL_CURSOR_Y / 2] = 0;
  }

  void vga_cursor_show(int show) {
      uint16_t ctrl = vga_buf[VGA_CTRL_CONTROL / 2];
      if (show)
          ctrl |= VGA_CTRL_BLINK | VGA_CTRL_ENABLE;
      else
          ctrl &= ~VGA_CTRL_BLINK;
      vga_buf[VGA_CTRL_CONTROL / 2] = ctrl;
  }

  int vga_col(void) { return cur_col; }
  int vga_row(void) { return cur_row; }

#endif
