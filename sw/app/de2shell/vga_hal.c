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
  static uint32_t clear_epoch = 0;

  static void advance_cursor(void) {
      cur_col++;
      if (cur_col >= VGA_COLS) {
          cur_col = 0;
          cur_row = (cur_row + 1) % VGA_ROWS;
      }
  }

  void vga_init(void) {
      printf("\033[2J\033[H\033[?25h");  /* clear, home, show cursor */
      cur_col = 0;
      cur_row = 0;
  }

  void vga_putc(char c, uint16_t color) {
      (void)color;  /* ANSI doesn't support per-char RGB565 without OSC codes */
      if (c == '\n') {
          putchar('\n');
          cur_col = 0;
          cur_row = (cur_row + 1) % VGA_ROWS;
          return;
      }
      if (c == '\r') {
          putchar('\r');
          cur_col = 0;
          return;
      }
      if (c == '\b') {
          if (cur_col > 0) {
              fputs("\b \b", stdout);
              cur_col--;
          }
          return;
      }

      putchar((unsigned char)c);
      advance_cursor();
  }

  void vga_puts(const char *s, uint16_t color) {
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
      clear_epoch++;
  }

  void vga_cursor_show(int show) {
      printf(show ? "\033[?25h" : "\033[?25l");
  }

  int vga_col(void) { return cur_col; }
  int vga_row(void) { return cur_row; }
  uint32_t vga_clear_epoch(void) { return clear_epoch; }

  void vga_puthex32(uint32_t val) {
      printf("%08X", (unsigned)val);
  }

#else  /* NEORV32 */

  #include <neorv32.h>

#ifdef DE2EXTRA_VGA_STUB
  #define VGA_MMIO_ENABLED 0
#else
  #define VGA_MMIO_ENABLED 1
#endif

  /* VGA text buffer base address (from de2extra_pkg.vhd ADDR_VGA_BASE) */
  #define VGA_BASE  0xF0000000

  /* VGA control registers (byte offsets from VGA_BASE) */
  #define VGA_CTRL_CURSOR_X  0x1000
  #define VGA_CTRL_CURSOR_Y  0x1004
  #define VGA_CTRL_CONTROL   0x1008
  #define VGA_CTRL_STATUS    0x100C
  #define VGA_CTRL_BGCOLOR   0x1010
  #define VGA_CTRL_CLEAR     0x1014

  #define VGA_CTRL_ENABLE     0x01
  #define VGA_CTRL_BLINK      0x02
  #define VGA_CTRL_PAGE       0x04

  /* 32-bit buffer: [31:24]=ASCII, [23:16]=bg RGB565, [15:0]=fg RGB565 */
  volatile uint32_t * const vga_buf = (volatile uint32_t *)VGA_BASE;

  static int cur_col = 0;
  static int cur_row = 0;
  static uint32_t clear_epoch = 0;

  static void hw_cursor_sync(void) {
#if VGA_MMIO_ENABLED
      vga_buf[VGA_CTRL_CURSOR_X / 4] = (uint32_t)cur_col;
      vga_buf[VGA_CTRL_CURSOR_Y / 4] = (uint32_t)cur_row;
#endif
  }

  static void hw_write_cell(int col, int row, char c, uint16_t color) {
#if VGA_MMIO_ENABLED
      int addr = row * VGA_COLS + col;
      vga_buf[addr] = ((uint32_t)(uint8_t)c << 24) | ((uint32_t)color);
#else
      (void)col;
      (void)row;
      (void)c;
      (void)color;
#endif
  }

  static void serial_putc(char c) {
      neorv32_uart0_putc(c);
  }

  static void serial_putu(unsigned value) {
      char buf[10];
      int pos = 0;

      if (value == 0) {
          serial_putc('0');
          return;
      }

      while ((value != 0) && (pos < (int)sizeof(buf))) {
          buf[pos++] = (char)('0' + (value % 10u));
          value /= 10u;
      }

      while (pos > 0) {
          serial_putc(buf[--pos]);
      }
  }

  static void serial_goto(int col, int row) {
      neorv32_uart0_puts("\033[");
      serial_putu((unsigned)(row + 1));
      serial_putc(';');
      serial_putu((unsigned)(col + 1));
      serial_putc('H');
  }

  static void advance_cursor(void) {
      cur_col++;
      if (cur_col >= VGA_COLS) {
          cur_col = 0;
          cur_row = (cur_row + 1) % VGA_ROWS;
      }
  }

  void vga_init(void) {
#if VGA_MMIO_ENABLED
      vga_buf[VGA_CTRL_CLEAR / 4] = 0x00000001;       /* clear screen */
      vga_buf[VGA_CTRL_CONTROL / 4] = VGA_CTRL_ENABLE; /* visible, non-blinking cursor */
      vga_buf[VGA_CTRL_BGCOLOR / 4] = VGA_BLACK;
#endif
      cur_col = 0;
      cur_row = 0;
      hw_cursor_sync();
      neorv32_uart0_puts("\033[2J\033[H\033[?25h");
  }

  void vga_putc(char c, uint16_t color) {
      if (c == '\n') {
          neorv32_uart0_puts("\r\n");
          cur_col = 0;
          cur_row = (cur_row + 1) % VGA_ROWS;
          hw_cursor_sync();
          return;
      }
      if (c == '\r') {
          serial_putc('\r');
          cur_col = 0;
          hw_cursor_sync();
          return;
      }
      if (c == '\b') {
          if (cur_col > 0) {
              cur_col--;
              hw_write_cell(cur_col, cur_row, ' ', VGA_BLACK);
              neorv32_uart0_puts("\b \b");
              hw_cursor_sync();
          }
          return;
      }

      hw_write_cell(cur_col, cur_row, c, color);
      serial_putc(c);
      advance_cursor();
      hw_cursor_sync();
  }

  void vga_puts(const char *s, uint16_t color) {
      while (*s) vga_putc(*s++, color);
  }

  void vga_goto(int col, int row) {
      if (col < 0) col = 0;
      if (row < 0) row = 0;
      if (col >= VGA_COLS) col = VGA_COLS - 1;
      if (row >= VGA_ROWS) row = VGA_ROWS - 1;
      cur_col = col;
      cur_row = row;
      hw_cursor_sync();
      serial_goto(col, row);
  }

  void vga_clear(void) {
#if VGA_MMIO_ENABLED
      vga_buf[VGA_CTRL_CLEAR / 4] = 0x00000001;
#endif
      cur_col = 0;
      cur_row = 0;
      clear_epoch++;
      hw_cursor_sync();
      neorv32_uart0_puts("\033[2J\033[H");
  }

  void vga_cursor_show(int show) {
#if VGA_MMIO_ENABLED
      uint32_t ctrl = vga_buf[VGA_CTRL_CONTROL / 4];
      if (show) {
          ctrl |= VGA_CTRL_ENABLE;
          ctrl &= ~(uint32_t)VGA_CTRL_BLINK;
      } else {
          ctrl &= ~(uint32_t)VGA_CTRL_ENABLE;
      }
      vga_buf[VGA_CTRL_CONTROL / 4] = ctrl;
#endif
      neorv32_uart0_puts(show ? "\033[?25h" : "\033[?25l");
  }

  int vga_col(void) { return cur_col; }
  int vga_row(void) { return cur_row; }
  uint32_t vga_clear_epoch(void) { return clear_epoch; }

  void vga_puthex32(uint32_t val) {
      static const char h[] = "0123456789ABCDEF";
      vga_putc(h[(val>>28)&0xF], VGA_WHITE);
      vga_putc(h[(val>>24)&0xF], VGA_WHITE);
      vga_putc(h[(val>>20)&0xF], VGA_WHITE);
      vga_putc(h[(val>>16)&0xF], VGA_WHITE);
      vga_putc(h[(val>>12)&0xF], VGA_WHITE);
      vga_putc(h[(val>>8)&0xF], VGA_WHITE);
      vga_putc(h[(val>>4)&0xF], VGA_WHITE);
      vga_putc(h[(val)&0xF], VGA_WHITE);
  }

#endif
