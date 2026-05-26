/* de2os_hal.c -- UART/LCD helpers shared by de2os tasks */

#include <neorv32.h>
#include <stdint.h>

#include "de2os_hal.h"

#define LCD_BASE 0xF000B000u
#define LCD_DR   (*(volatile uint32_t *)(LCD_BASE + 0x00u))
#define LCD_CR   (*(volatile uint32_t *)(LCD_BASE + 0x04u))

static void lcd_busy_wait(void) {
    while ((LCD_DR & 1u) != 0u) {
    }
}

static void lcd_cmd(uint8_t cmd) {
    lcd_busy_wait();
    LCD_CR = cmd;
}

static void lcd_data(uint8_t ch) {
    lcd_busy_wait();
    LCD_DR = ch;
}

void de2os_uart_put_hex(uint32_t v) {
    static const char hex[] = "0123456789abcdef";
    char buf[9];
    int i;

    for (i = 7; i >= 0; i--) {
        buf[7 - i] = hex[(v >> (i * 4)) & 0x0fu];
    }
    buf[8] = '\0';
    neorv32_uart0_puts(buf);
}

void de2os_uart_put_dec(uint32_t v) {
    char buf[11];
    int pos = 10;

    buf[pos] = '\0';
    do {
        pos--;
        buf[pos] = (char)('0' + (v % 10u));
        v /= 10u;
    } while (v != 0u);

    neorv32_uart0_puts(&buf[pos]);
}

void de2os_lcd_init(void) {
    volatile int i;

    for (i = 0; i < 2500000; i++) {
    }
    lcd_cmd(0x38u);
    lcd_cmd(0x0cu);
    lcd_cmd(0x06u);
    lcd_cmd(0x01u);
    lcd_cmd(0x80u);
}

void de2os_lcd_write_line(int line, const char *text) {
    int i = 0;

    lcd_cmd((uint8_t)((line == 0) ? 0x80u : 0xc0u));

    while ((text[i] != '\0') && (i < 16)) {
        lcd_data((uint8_t)text[i]);
        i++;
    }
    while (i < 16) {
        lcd_data((uint8_t)' ');
        i++;
    }
}

void de2os_lcd_write_lines(const char *line1, const char *line2) {
    de2os_lcd_write_line(0, line1);
    de2os_lcd_write_line(1, line2);
}
