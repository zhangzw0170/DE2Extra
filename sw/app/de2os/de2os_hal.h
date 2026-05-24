/* de2os_hal.h -- UART/LCD helpers shared by de2os tasks */

#ifndef DE2OS_HAL_H
#define DE2OS_HAL_H

#include <stdint.h>

void de2os_uart_put_hex(uint32_t v);
void de2os_uart_put_dec(uint32_t v);

void de2os_lcd_init(void);
void de2os_lcd_write_line(int line, const char *text);
void de2os_lcd_write_lines(const char *line1, const char *line2);

#endif
