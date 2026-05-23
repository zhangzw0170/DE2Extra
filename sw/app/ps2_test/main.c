#include <neorv32.h>
#include <stdint.h>

#define BAUD_RATE 115200
#define LCD_STATUS_PS2_BASE  0x30000000u
#define LCD_STATUS_PS2_SEEN  0x08000000u
#define LCD_STATUS_PS2_OVF   0x04000000u
#define PS2_STATUS_READY     0x00000001u
#define PS2_STATUS_OVERFLOW  0x00000002u
#define PS2_STATUS_TX_BUSY   0x00010000u
#define PS2_STATUS_TX_DONE   0x00020000u
#define PS2_STATUS_TX_ERROR  0x00040000u
#define PS2_STATUS_TX_RESP   0x00080000u
#define PS2_STATUS_TX_RESP_SHIFT 20
#define PS2_STATUS_BUS_IDLE  0x10000000u
#define PS2_LED_SCROLL       0x01u
#define PS2_LED_NUM          0x02u
#define PS2_LED_CAPS         0x04u
#define PS2_RESP_ACK         0xfau
#define PS2_RESP_RESEND      0xfeu
#define PS2_HOST_TIMEOUT     5000000u

typedef volatile struct {
  uint32_t data;
  uint32_t status;
  uint32_t ctrl;
  uint32_t tx_data;
} ps2_regs_t;

#define PS2 ((ps2_regs_t*)0xF0002000u)

typedef struct {
  const char *zone;
  const char *name;
  const char *tty;
  uint8_t row;
  uint8_t col;
  uint8_t ascii;
  uint8_t has_ascii;
} key_event_t;

static void lcd_show_ps2(uint8_t code, int seen, int overflow) {
  uint32_t status = LCD_STATUS_PS2_BASE | (uint32_t)code;
  if (seen) {
    status |= LCD_STATUS_PS2_SEEN;
  }
  if (overflow) {
    status |= LCD_STATUS_PS2_OVF;
  }
  neorv32_gpio_port_set(status);
}

static void put_hex8(uint8_t val) {
  static const char hex[] = "0123456789ABCDEF";
  neorv32_uart0_putc(hex[(val >> 4) & 0x0f]);
  neorv32_uart0_putc(hex[val & 0x0f]);
}

static void put_dec_u8(uint8_t val) {
  char buf[3];
  int i = 0;

  if (val >= 100u) {
    buf[i++] = (char)('0' + (val / 100u));
    val = (uint8_t)(val % 100u);
    buf[i++] = (char)('0' + (val / 10u));
    buf[i++] = (char)('0' + (val % 10u));
  } else if (val >= 10u) {
    buf[i++] = (char)('0' + (val / 10u));
    buf[i++] = (char)('0' + (val % 10u));
  } else {
    buf[i++] = (char)('0' + val);
  }

  for (int j = 0; j < i; ++j) {
    neorv32_uart0_putc(buf[j]);
  }
}

static void put_tty_repr(uint8_t ascii) {
  if (ascii == 0x20u) {
    neorv32_uart0_puts("SP");
  } else if (ascii == 0x7fu) {
    neorv32_uart0_puts("^?");
  } else if (ascii < 0x20u) {
    neorv32_uart0_putc('^');
    neorv32_uart0_putc((char)(ascii + 64u));
  } else {
    neorv32_uart0_putc((char)ascii);
  }
}

static void print_status(void) {
  uint32_t s = PS2->status;
  neorv32_uart0_puts("status ready=");
  neorv32_uart0_putc((s & PS2_STATUS_READY) ? '1' : '0');
  neorv32_uart0_puts(" overflow=");
  neorv32_uart0_putc((s & PS2_STATUS_OVERFLOW) ? '1' : '0');
  neorv32_uart0_puts(" tx_busy=");
  neorv32_uart0_putc((s & PS2_STATUS_TX_BUSY) ? '1' : '0');
  neorv32_uart0_puts(" tx_done=");
  neorv32_uart0_putc((s & PS2_STATUS_TX_DONE) ? '1' : '0');
  neorv32_uart0_puts(" tx_err=");
  neorv32_uart0_putc((s & PS2_STATUS_TX_ERROR) ? '1' : '0');
  neorv32_uart0_puts(" bus_idle=");
  neorv32_uart0_putc((s & PS2_STATUS_BUS_IDLE) ? '1' : '0');
  neorv32_uart0_puts(" count=0x");
  put_hex8((uint8_t)(s >> 8));
  neorv32_uart0_putc('\n');
}

static int ps2_send_host_byte(uint8_t byte, uint8_t *resp_out) {
  uint32_t timeout;

  PS2->status = PS2_STATUS_TX_DONE | PS2_STATUS_TX_ERROR | PS2_STATUS_TX_RESP;

  timeout = PS2_HOST_TIMEOUT;
  while (((PS2->status & PS2_STATUS_TX_BUSY) != 0u) && (timeout != 0u)) {
    --timeout;
  }
  if (timeout == 0u) {
    return -1;
  }

  PS2->tx_data = (uint32_t)byte;

  timeout = PS2_HOST_TIMEOUT;
  while (timeout != 0u) {
    uint32_t status = PS2->status;
    if ((status & PS2_STATUS_TX_DONE) != 0u) {
      if (resp_out != NULL) {
        *resp_out = (uint8_t)((status >> PS2_STATUS_TX_RESP_SHIFT) & 0xffu);
      }

      if (((status & PS2_STATUS_TX_ERROR) != 0u) || ((status & PS2_STATUS_TX_RESP) == 0u)) {
        return -1;
      }
      return 0;
    }
    --timeout;
  }

  return -1;
}

static int ps2_sync_leds(int caps_lock, int num_lock, int scroll_lock) {
  uint8_t resp = 0u;
  uint8_t led_mask = 0u;

  if (scroll_lock != 0) {
    led_mask |= PS2_LED_SCROLL;
  }
  if (num_lock != 0) {
    led_mask |= PS2_LED_NUM;
  }
  if (caps_lock != 0) {
    led_mask |= PS2_LED_CAPS;
  }

  for (int attempt = 0; attempt < 2; ++attempt) {
    if ((ps2_send_host_byte(0xedu, &resp) == 0) && (resp == PS2_RESP_ACK) &&
        (ps2_send_host_byte(led_mask, &resp) == 0) && (resp == PS2_RESP_ACK)) {
      neorv32_uart0_puts("led sync ok mask=0x");
      put_hex8(led_mask);
      neorv32_uart0_putc('\n');
      return 0;
    }

    if (resp != PS2_RESP_RESEND) {
      break;
    }
  }

  neorv32_uart0_puts("led sync failed mask=0x");
  put_hex8(led_mask);
  neorv32_uart0_puts(" resp=0x");
  put_hex8(resp);
  neorv32_uart0_putc('\n');
  print_status();
  return -1;
}

static void set_event(
  key_event_t *ev,
  const char *zone,
  uint8_t row,
  uint8_t col,
  const char *name,
  int has_ascii,
  uint8_t ascii,
  const char *tty
) {
  ev->zone = zone;
  ev->row = row;
  ev->col = col;
  ev->name = name;
  ev->has_ascii = (uint8_t)(has_ascii ? 1 : 0);
  ev->ascii = ascii;
  ev->tty = tty;
}

static uint8_t letter_ascii(char lower, int shift_held, int caps_lock, int ctrl_held) {
  uint8_t ascii = (uint8_t)lower;

  if ((shift_held ^ caps_lock) != 0) {
    ascii = (uint8_t)(lower - ('a' - 'A'));
  }

  if (ctrl_held != 0) {
    ascii = (uint8_t)((lower - 'a') + 1);
  }

  return ascii;
}

static int decode_main_key(
  uint8_t sc,
  int shift_held,
  int caps_lock,
  int ctrl_held,
  int num_lock,
  key_event_t *ev
) {
  switch (sc) {
    case 0x0e: set_event(ev, "main",   0,  0, "GRAVE",  1, shift_held ? '~'  : '`', NULL); return 1;
    case 0x16: set_event(ev, "main",   0,  1, "1",      1, shift_held ? '!'  : '1', NULL); return 1;
    case 0x1e: set_event(ev, "main",   0,  2, "2",      1, shift_held ? '@'  : '2', NULL); return 1;
    case 0x26: set_event(ev, "main",   0,  3, "3",      1, shift_held ? '#'  : '3', NULL); return 1;
    case 0x25: set_event(ev, "main",   0,  4, "4",      1, shift_held ? '$'  : '4', NULL); return 1;
    case 0x2e: set_event(ev, "main",   0,  5, "5",      1, shift_held ? '%'  : '5', NULL); return 1;
    case 0x36: set_event(ev, "main",   0,  6, "6",      1, shift_held ? '^'  : '6', NULL); return 1;
    case 0x3d: set_event(ev, "main",   0,  7, "7",      1, shift_held ? '&'  : '7', NULL); return 1;
    case 0x3e: set_event(ev, "main",   0,  8, "8",      1, shift_held ? '*'  : '8', NULL); return 1;
    case 0x46: set_event(ev, "main",   0,  9, "9",      1, shift_held ? '('  : '9', NULL); return 1;
    case 0x45: set_event(ev, "main",   0, 10, "0",      1, shift_held ? ')'  : '0', NULL); return 1;
    case 0x4e: set_event(ev, "main",   0, 11, "MINUS",  1, shift_held ? '_'  : '-', NULL); return 1;
    case 0x55: set_event(ev, "main",   0, 12, "EQUAL",  1, shift_held ? '+'  : '=', NULL); return 1;
    case 0x66: set_event(ev, "main",   0, 13, "BSP",    1, 0x08u, "^H");              return 1;
    case 0x0d: set_event(ev, "main",   1,  0, "TAB",    1, 0x09u, "^I");              return 1;
    case 0x15: set_event(ev, "main",   1,  1, "Q",      1, letter_ascii('q', shift_held, caps_lock, ctrl_held), NULL); return 1;
    case 0x1d: set_event(ev, "main",   1,  2, "W",      1, letter_ascii('w', shift_held, caps_lock, ctrl_held), NULL); return 1;
    case 0x24: set_event(ev, "main",   1,  3, "E",      1, letter_ascii('e', shift_held, caps_lock, ctrl_held), NULL); return 1;
    case 0x2d: set_event(ev, "main",   1,  4, "R",      1, letter_ascii('r', shift_held, caps_lock, ctrl_held), NULL); return 1;
    case 0x2c: set_event(ev, "main",   1,  5, "T",      1, letter_ascii('t', shift_held, caps_lock, ctrl_held), NULL); return 1;
    case 0x35: set_event(ev, "main",   1,  6, "Y",      1, letter_ascii('y', shift_held, caps_lock, ctrl_held), NULL); return 1;
    case 0x3c: set_event(ev, "main",   1,  7, "U",      1, letter_ascii('u', shift_held, caps_lock, ctrl_held), NULL); return 1;
    case 0x43: set_event(ev, "main",   1,  8, "I",      1, letter_ascii('i', shift_held, caps_lock, ctrl_held), NULL); return 1;
    case 0x44: set_event(ev, "main",   1,  9, "O",      1, letter_ascii('o', shift_held, caps_lock, ctrl_held), NULL); return 1;
    case 0x4d: set_event(ev, "main",   1, 10, "P",      1, letter_ascii('p', shift_held, caps_lock, ctrl_held), NULL); return 1;
    case 0x54: set_event(ev, "main",   1, 11, "LBRK",   1, shift_held ? '{'  : '[', NULL); return 1;
    case 0x5b: set_event(ev, "main",   1, 12, "RBRK",   1, shift_held ? '}'  : ']', NULL); return 1;
    case 0x5d: set_event(ev, "main",   1, 13, "BSLASH", 1, shift_held ? '|'  : '\\', NULL); return 1;
    case 0x58: set_event(ev, "mods",   2,  0, "CAPS",   0, 0x00u, NULL);              return 1;
    case 0x1c: set_event(ev, "main",   2,  1, "A",      1, letter_ascii('a', shift_held, caps_lock, ctrl_held), NULL); return 1;
    case 0x1b: set_event(ev, "main",   2,  2, "S",      1, letter_ascii('s', shift_held, caps_lock, ctrl_held), NULL); return 1;
    case 0x23: set_event(ev, "main",   2,  3, "D",      1, letter_ascii('d', shift_held, caps_lock, ctrl_held), NULL); return 1;
    case 0x2b: set_event(ev, "main",   2,  4, "F",      1, letter_ascii('f', shift_held, caps_lock, ctrl_held), NULL); return 1;
    case 0x34: set_event(ev, "main",   2,  5, "G",      1, letter_ascii('g', shift_held, caps_lock, ctrl_held), NULL); return 1;
    case 0x33: set_event(ev, "main",   2,  6, "H",      1, letter_ascii('h', shift_held, caps_lock, ctrl_held), NULL); return 1;
    case 0x3b: set_event(ev, "main",   2,  7, "J",      1, letter_ascii('j', shift_held, caps_lock, ctrl_held), NULL); return 1;
    case 0x42: set_event(ev, "main",   2,  8, "K",      1, letter_ascii('k', shift_held, caps_lock, ctrl_held), NULL); return 1;
    case 0x4b: set_event(ev, "main",   2,  9, "L",      1, letter_ascii('l', shift_held, caps_lock, ctrl_held), NULL); return 1;
    case 0x4c: set_event(ev, "main",   2, 10, "SEMI",   1, shift_held ? ':'  : ';', NULL); return 1;
    case 0x52: set_event(ev, "main",   2, 11, "QUOTE",  1, shift_held ? '"'  : '\'', NULL); return 1;
    case 0x5a: set_event(ev, "main",   2, 12, "ENTER",  1, 0x0du, "^M");              return 1;
    case 0x12: set_event(ev, "mods",   3,  0, "LSHIFT", 0, 0x00u, NULL);              return 1;
    case 0x1a: set_event(ev, "main",   3,  1, "Z",      1, letter_ascii('z', shift_held, caps_lock, ctrl_held), NULL); return 1;
    case 0x22: set_event(ev, "main",   3,  2, "X",      1, letter_ascii('x', shift_held, caps_lock, ctrl_held), NULL); return 1;
    case 0x21: set_event(ev, "main",   3,  3, "C",      1, letter_ascii('c', shift_held, caps_lock, ctrl_held), NULL); return 1;
    case 0x2a: set_event(ev, "main",   3,  4, "V",      1, letter_ascii('v', shift_held, caps_lock, ctrl_held), NULL); return 1;
    case 0x32: set_event(ev, "main",   3,  5, "B",      1, letter_ascii('b', shift_held, caps_lock, ctrl_held), NULL); return 1;
    case 0x31: set_event(ev, "main",   3,  6, "N",      1, letter_ascii('n', shift_held, caps_lock, ctrl_held), NULL); return 1;
    case 0x3a: set_event(ev, "main",   3,  7, "M",      1, letter_ascii('m', shift_held, caps_lock, ctrl_held), NULL); return 1;
    case 0x41: set_event(ev, "main",   3,  8, "COMMA",  1, shift_held ? '<'  : ',', NULL); return 1;
    case 0x49: set_event(ev, "main",   3,  9, "DOT",    1, shift_held ? '>'  : '.', NULL); return 1;
    case 0x4a: set_event(ev, "main",   3, 10, "SLASH",  1, shift_held ? '?'  : '/', NULL); return 1;
    case 0x59: set_event(ev, "mods",   3, 11, "RSHIFT", 0, 0x00u, NULL);              return 1;
    case 0x14: set_event(ev, "mods",   4,  0, "LCTRL",  0, 0x00u, NULL);              return 1;
    case 0x11: set_event(ev, "mods",   4,  2, "LALT",   0, 0x00u, NULL);              return 1;
    case 0x29: set_event(ev, "main",   4,  3, "SPACE",  1, 0x20u, "SP");              return 1;
    case 0x77: set_event(ev, "keypad", 0,  0, "NUM",    0, 0x00u, NULL);              return 1;
    case 0x70: set_event(ev, "keypad", 3,  0, "KP0",    num_lock, '0', NULL);         return 1;
    case 0x69: set_event(ev, "keypad", 2,  0, "KP1",    num_lock, '1', NULL);         return 1;
    case 0x72: set_event(ev, "keypad", 2,  1, "KP2",    num_lock, '2', NULL);         return 1;
    case 0x7a: set_event(ev, "keypad", 2,  2, "KP3",    num_lock, '3', NULL);         return 1;
    case 0x6b: set_event(ev, "keypad", 1,  0, "KP4",    num_lock, '4', NULL);         return 1;
    case 0x73: set_event(ev, "keypad", 1,  1, "KP5",    num_lock, '5', NULL);         return 1;
    case 0x74: set_event(ev, "keypad", 1,  2, "KP6",    num_lock, '6', NULL);         return 1;
    case 0x6c: set_event(ev, "keypad", 0,  0, "KP7",    num_lock, '7', NULL);         return 1;
    case 0x75: set_event(ev, "keypad", 0,  1, "KP8",    num_lock, '8', NULL);         return 1;
    case 0x7d: set_event(ev, "keypad", 0,  2, "KP9",    num_lock, '9', NULL);         return 1;
    case 0x71: set_event(ev, "keypad", 3,  1, "KPDOT",  num_lock, '.', NULL);         return 1;
    case 0x79: set_event(ev, "keypad", 3,  2, "KP+",    1, '+', NULL);                return 1;
    case 0x7b: set_event(ev, "keypad", 0,  3, "KP-",    1, '-', NULL);                return 1;
    case 0x7c: set_event(ev, "keypad", 1,  3, "KP*",    1, '*', NULL);                return 1;
    case 0x7e: set_event(ev, "mods",   0,  2, "SCRLK",  0, 0x00u, NULL);              return 1;
    case 0x76: set_event(ev, "nav",    0,  4, "ESC",    1, 0x1bu, "^[");              return 1;
    default:
      return 0;
  }
}

static int decode_extended_key(uint8_t sc, key_event_t *ev) {
  switch (sc) {
    case 0x11: set_event(ev, "mods",   4, 4, "RALT",  0, 0x00u, NULL);      return 1;
    case 0x14: set_event(ev, "mods",   4, 7, "RCTRL", 0, 0x00u, NULL);      return 1;
    case 0x1f: set_event(ev, "mods",   4, 1, "LWIN",  0, 0x00u, NULL);      return 1;
    case 0x27: set_event(ev, "mods",   4, 5, "RWIN",  0, 0x00u, NULL);      return 1;
    case 0x2f: set_event(ev, "mods",   4, 6, "MENU",  0, 0x00u, NULL);      return 1;
    case 0x4a: set_event(ev, "keypad", 0, 4, "KP/",   1, '/', NULL);        return 1;
    case 0x5a: set_event(ev, "keypad", 3, 4, "KPENT", 1, 0x0du, "^M");      return 1;
    case 0x69: set_event(ev, "nav",    1, 1, "END",   0, 0x00u, "ESC[F");   return 1;
    case 0x6b: set_event(ev, "nav",    2, 0, "LEFT",  0, 0x00u, "ESC[D");   return 1;
    case 0x6c: set_event(ev, "nav",    0, 1, "HOME",  0, 0x00u, "ESC[H");   return 1;
    case 0x70: set_event(ev, "nav",    0, 0, "INS",   0, 0x00u, "ESC[2~");  return 1;
    case 0x71: set_event(ev, "nav",    1, 0, "DEL",   1, 0x7fu, "ESC[3~");  return 1;
    case 0x72: set_event(ev, "nav",    2, 1, "DOWN",  0, 0x00u, "ESC[B");   return 1;
    case 0x74: set_event(ev, "nav",    2, 2, "RIGHT", 0, 0x00u, "ESC[C");   return 1;
    case 0x75: set_event(ev, "nav",    1, 1, "UP",    0, 0x00u, "ESC[A");   return 1;
    case 0x7a: set_event(ev, "nav",    1, 2, "PGDN",  0, 0x00u, "ESC[6~");  return 1;
    case 0x7d: set_event(ev, "nav",    0, 2, "PGUP",  0, 0x00u, "ESC[5~");  return 1;
    default:
      return 0;
  }
}

static void print_event(
  uint8_t sc,
  int extended,
  int is_release,
  const key_event_t *ev,
  int shift_held,
  int ctrl_held,
  int alt_held,
  int win_held,
  int caps_lock,
  int num_lock,
  int scroll_lock
) {
  neorv32_uart0_puts("scan ");
  if (extended) {
    neorv32_uart0_puts("E0 ");
  }
  put_hex8(sc);
  neorv32_uart0_puts(is_release ? " release" : " press");

  if (ev != NULL) {
    neorv32_uart0_puts(" zone=");
    neorv32_uart0_puts(ev->zone);
    neorv32_uart0_puts(" rc=(");
    put_dec_u8(ev->row);
    neorv32_uart0_putc(',');
    put_dec_u8(ev->col);
    neorv32_uart0_putc(')');
    neorv32_uart0_puts(" key=");
    neorv32_uart0_puts(ev->name);

    if (ev->has_ascii != 0u) {
      neorv32_uart0_puts(" ascii=0x");
      put_hex8(ev->ascii);
      neorv32_uart0_putc(' ');
      put_tty_repr(ev->ascii);
    } else {
      neorv32_uart0_puts(" ascii=--");
    }

    if (ev->tty != NULL) {
      neorv32_uart0_puts(" tty=");
      neorv32_uart0_puts(ev->tty);
    }
  } else {
    neorv32_uart0_puts(" unmapped");
  }

  neorv32_uart0_puts(" mods[S");
  neorv32_uart0_putc(shift_held ? '1' : '0');
  neorv32_uart0_puts(" C");
  neorv32_uart0_putc(ctrl_held ? '1' : '0');
  neorv32_uart0_puts(" A");
  neorv32_uart0_putc(alt_held ? '1' : '0');
  neorv32_uart0_puts(" W");
  neorv32_uart0_putc(win_held ? '1' : '0');
  neorv32_uart0_puts("] locks[C");
  neorv32_uart0_putc(caps_lock ? '1' : '0');
  neorv32_uart0_puts(" N");
  neorv32_uart0_putc(num_lock ? '1' : '0');
  neorv32_uart0_puts(" S");
  neorv32_uart0_putc(scroll_lock ? '1' : '0');
  neorv32_uart0_puts("]\n");
}

int main(void) {
  uint8_t break_prefix = 0;
  uint8_t ext_prefix = 0;
  uint8_t last_ascii = 0;
  int shift_l = 0;
  int shift_r = 0;
  int ctrl_l = 0;
  int ctrl_r = 0;
  int alt_l = 0;
  int alt_r = 0;
  int win_l = 0;
  int win_r = 0;
  int caps_lock = 0;
  int num_lock = 0;
  int scroll_lock = 0;

  neorv32_rte_setup();
  neorv32_uart0_setup(BAUD_RATE, 0);
  neorv32_gpio_dir_set(0xFFFFFFFFu);
  lcd_show_ps2(0x00u, 0, 0);

  neorv32_uart0_puts("\nDE2Extra PS/2 decode test\n");
  neorv32_uart0_puts("Logs include raw scan code, key name, row/col coordinate and ASCII/TTY.\n");
  neorv32_uart0_puts("Lock state is tracked in software and mirrored back to keyboard LEDs.\n");
  print_status();

  while (1) {
    uint32_t status = PS2->status;

    if ((status & PS2_STATUS_OVERFLOW) != 0u) {
      neorv32_uart0_puts("WARN overflow; clearing flag\n");
      PS2->status = PS2_STATUS_OVERFLOW;
      lcd_show_ps2(last_ascii, 1, 1);
      continue;
    }

    if ((status & PS2_STATUS_READY) == 0u) {
      continue;
    }

    {
      uint8_t code = (uint8_t)PS2->data;
      int shift_held;
      int ctrl_held;
      int alt_held;
      int win_held;
      key_event_t ev;
      key_event_t *ev_ptr = NULL;
      int is_release;
      int is_extended;

      if (code == 0xE0u) {
        ext_prefix = 1;
        continue;
      }

      if (code == 0xF0u) {
        break_prefix = 1;
        continue;
      }

      is_release = break_prefix ? 1 : 0;
      is_extended = ext_prefix ? 1 : 0;

      if (is_extended) {
        if (code == 0x14u) {
          ctrl_r = is_release ? 0 : 1;
          set_event(&ev, "mods", 4, 7, "RCTRL", 0, 0x00u, NULL);
          ev_ptr = &ev;
        } else if (code == 0x11u) {
          alt_r = is_release ? 0 : 1;
          set_event(&ev, "mods", 4, 4, "RALT", 0, 0x00u, NULL);
          ev_ptr = &ev;
        } else if (code == 0x1fu) {
          win_l = is_release ? 0 : 1;
          set_event(&ev, "mods", 4, 1, "LWIN", 0, 0x00u, NULL);
          ev_ptr = &ev;
        } else if (code == 0x27u) {
          win_r = is_release ? 0 : 1;
          set_event(&ev, "mods", 4, 5, "RWIN", 0, 0x00u, NULL);
          ev_ptr = &ev;
        } else if (code == 0x2fu) {
          set_event(&ev, "mods", 4, 6, "MENU", 0, 0x00u, NULL);
          ev_ptr = &ev;
        } else if (decode_extended_key(code, &ev) != 0) {
          ev_ptr = &ev;
        }
      } else {
        if (code == 0x12u) {
          shift_l = is_release ? 0 : 1;
          set_event(&ev, "mods", 3, 0, "LSHIFT", 0, 0x00u, NULL);
          ev_ptr = &ev;
        } else if (code == 0x59u) {
          shift_r = is_release ? 0 : 1;
          set_event(&ev, "mods", 3, 11, "RSHIFT", 0, 0x00u, NULL);
          ev_ptr = &ev;
        } else if (code == 0x14u) {
          ctrl_l = is_release ? 0 : 1;
          set_event(&ev, "mods", 4, 0, "LCTRL", 0, 0x00u, NULL);
          ev_ptr = &ev;
        } else if (code == 0x11u) {
          alt_l = is_release ? 0 : 1;
          set_event(&ev, "mods", 4, 2, "LALT", 0, 0x00u, NULL);
          ev_ptr = &ev;
        } else if (code == 0x58u) {
          if (!is_release) {
            caps_lock ^= 1;
            (void)ps2_sync_leds(caps_lock, num_lock, scroll_lock);
          }
          set_event(&ev, "mods", 2, 0, "CAPS", 0, 0x00u, NULL);
          ev_ptr = &ev;
        } else if (code == 0x77u) {
          if (!is_release) {
            num_lock ^= 1;
            (void)ps2_sync_leds(caps_lock, num_lock, scroll_lock);
          }
          set_event(&ev, "keypad", 0, 0, "NUM", 0, 0x00u, NULL);
          ev_ptr = &ev;
        } else if (code == 0x7eu) {
          if (!is_release) {
            scroll_lock ^= 1;
            (void)ps2_sync_leds(caps_lock, num_lock, scroll_lock);
          }
          set_event(&ev, "mods", 0, 2, "SCRLK", 0, 0x00u, NULL);
          ev_ptr = &ev;
        } else {
          shift_held = shift_l || shift_r;
          ctrl_held = ctrl_l || ctrl_r;
          if (decode_main_key(code, shift_held, caps_lock, ctrl_held, num_lock, &ev) != 0) {
            ev_ptr = &ev;
          }
        }
      }

      shift_held = shift_l || shift_r;
      ctrl_held = ctrl_l || ctrl_r;
      alt_held = alt_l || alt_r;
      win_held = win_l || win_r;

      if ((ev_ptr != NULL) && (ev_ptr->has_ascii != 0u) && !is_release) {
        last_ascii = ev_ptr->ascii;
        lcd_show_ps2(last_ascii, 1, 0);
      }

      print_event(
        code,
        is_extended,
        is_release,
        ev_ptr,
        shift_held,
        ctrl_held,
        alt_held,
        win_held,
        caps_lock,
        num_lock,
        scroll_lock
      );

      break_prefix = 0;
      ext_prefix = 0;
    }
  }

  return 0;
}
