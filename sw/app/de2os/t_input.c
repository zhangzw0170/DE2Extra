/* t_input.c — Input handler task (stub: UART echo) */

#include <neorv32.h>
#include "FreeRTOS.h"
#include "task.h"

void t_input_task(void *pv) {
    (void)pv;

    neorv32_uart0_puts("[input] started\n");

    for (;;) {
        if (neorv32_uart0_char_received()) {
            char c = (char)neorv32_uart0_getc();
            neorv32_uart0_putc('[');
            neorv32_uart0_putc(c);
            neorv32_uart0_puts("]\n");
        }
        vTaskDelay(pdMS_TO_TICKS(50));
    }
}
