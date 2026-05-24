#include "lcd_hal.h"
#include <stdint.h>

#ifndef LOCAL_BUILD
  #include <neorv32.h>

  typedef volatile struct {
      uint32_t dr;
      uint32_t cr;
  } lcd_regs_t;

  #define LCD ((lcd_regs_t*)0xF0008000u)
#endif

static char lcd_shadow[2][17] = {
    "                ",
    "                "
};

static void lcd_copy_16(char *dst, const char *src) {
    int i = 0;

    while ((i < 16) && src[i]) {
        dst[i] = src[i];
        i++;
    }
    while (i < 16) {
        dst[i++] = ' ';
    }
    dst[16] = '\0';
}

static void lcd_shadow_store(int line, const char *text) {
    if ((line < 0) || (line > 1)) {
        return;
    }

    lcd_copy_16(lcd_shadow[line], text);
}

#ifndef LOCAL_BUILD
static void lcd_delay_ms(uint32_t time_ms) {
    neorv32_aux_delay_ms(neorv32_sysinfo_get_clk(), time_ms);
}

static void lcd_wait_ready(void) {
    uint32_t timeout = 500000u;

    while (timeout != 0u) {
        if ((LCD->dr & 1u) == 0u) {
            return;
        }
        timeout--;
    }
}

static void lcd_write_cmd(uint8_t cmd) {
    lcd_wait_ready();
    LCD->cr = (uint32_t)cmd;
}

static void lcd_write_data(uint8_t data) {
    lcd_wait_ready();
    LCD->dr = (uint32_t)data;
}
#endif

void lcd_init(void) {
    lcd_shadow_store(0, "");
    lcd_shadow_store(1, "");
#ifndef LOCAL_BUILD
    lcd_delay_ms(50u);
    lcd_write_cmd(0x38u);
    lcd_delay_ms(10u);
    lcd_write_cmd(0x38u);
    lcd_delay_ms(1u);
    lcd_write_cmd(0x38u);
    lcd_write_cmd(0x0Cu);
    lcd_write_cmd(0x06u);
    lcd_write_cmd(0x01u);
    lcd_write_cmd(0x80u);
#endif
}

void lcd_clear(void) {
    lcd_shadow_store(0, "");
    lcd_shadow_store(1, "");
#ifndef LOCAL_BUILD
    lcd_write_cmd(0x01u);
#endif
}

void lcd_write_line(int line, const char *text) {
    char padded[17];

    lcd_copy_16(padded, text);
    lcd_shadow_store(line, text);

#ifndef LOCAL_BUILD
    lcd_write_cmd((line == 0) ? 0x80u : 0xC0u);
    for (int i = 0; i < 16; i++) {
        lcd_write_data((uint8_t)padded[i]);
    }
#else
    (void)line;
    (void)padded;
#endif
}

void lcd_write_lines(const char *line1, const char *line2) {
    lcd_write_line(0, line1);
    lcd_write_line(1, line2);
}

void lcd_get_line(int line, char *text_out) {
    const char *src;

    if (line == 0) {
        src = lcd_shadow[0];
    } else if (line == 1) {
        src = lcd_shadow[1];
    } else {
        src = "                ";
    }

    for (int i = 0; i <= 16; i++) {
        text_out[i] = src[i];
    }
}

void lcd_get_lines(char *line1_out, char *line2_out) {
    lcd_get_line(0, line1_out);
    lcd_get_line(1, line2_out);
}
