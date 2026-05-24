/* t_input.c -- UART command task */

#include <neorv32.h>
#include <stdint.h>
#include "FreeRTOS.h"
#include "task.h"

#include "de2os_hal.h"
#include "de2os_state.h"

static char normalize_cmd(char c) {
    if ((c >= 'A') && (c <= 'Z')) {
        return (char)(c - 'A' + 'a');
    }
    return c;
}

static void print_help(void) {
    neorv32_uart0_puts("Commands: h=help p=pause/resume b=single-step r=reset s=status\n");
}

static void print_status(void) {
    neorv32_uart0_puts("[status] mode=");
    neorv32_uart0_puts((g_crypto_enabled != 0u) ? "run" : "pause");
    neorv32_uart0_puts(" iter=0x");
    de2os_uart_put_hex(g_crypto_iterations);
    neorv32_uart0_puts(" cycles=0x");
    de2os_uart_put_hex(g_crypto_last_cycles);
    neorv32_uart0_puts(" gui_ticks=");
    de2os_uart_put_dec(g_gui_ticks);
    neorv32_uart0_puts(" idle=");
    de2os_uart_put_dec(g_idle_count);
    neorv32_uart0_puts(" last_key=");
    neorv32_uart0_putc((char)((g_last_input != '\0') ? g_last_input : '-'));
    neorv32_uart0_puts("\n");
}

void t_input_task(void *pv) {
    (void)pv;

    neorv32_uart0_puts("[input] started\n");
    print_help();

    for (;;) {
        if (neorv32_uart0_char_received()) {
            char c = normalize_cmd((char)neorv32_uart0_getc());
            g_last_input = c;

            switch (c) {
                case 'h':
                    print_help();
                    break;
                case 'p':
                    g_crypto_enabled = (uint8_t)((g_crypto_enabled == 0u) ? 1u : 0u);
                    neorv32_uart0_puts("[input] crypto ");
                    neorv32_uart0_puts((g_crypto_enabled != 0u) ? "running\n" : "paused\n");
                    break;
                case 'b':
                    g_crypto_single_shot_request = 1u;
                    neorv32_uart0_puts("[input] single benchmark requested\n");
                    break;
                case 'r':
                    g_crypto_reset_request = 1u;
                    g_crypto_enabled = 1u;
                    neorv32_uart0_puts("[input] counters reset\n");
                    break;
                case 's':
                    print_status();
                    break;
                case '\r':
                case '\n':
                    break;
                default:
                    neorv32_uart0_puts("[input] unknown command '");
                    neorv32_uart0_putc(c);
                    neorv32_uart0_puts("'\n");
                    break;
            }
        }
        vTaskDelay(pdMS_TO_TICKS(20));
    }
}
