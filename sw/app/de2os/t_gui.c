/* t_gui.c -- GUI/status task */

#include <neorv32.h>
#include "FreeRTOS.h"
#include "task.h"
#include "queue.h"

#include "de2os_hal.h"
#include "de2os_state.h"

static void line_put_text(char *line, unsigned int pos, const char *text) {
    while ((*text != '\0') && (pos < 16u)) {
        line[pos++] = *text++;
    }
}

static void line_put_hex8(char *line, unsigned int pos, uint32_t value) {
    static const char hex[] = "0123456789abcdef";
    int i;

    for (i = 0; i < 8; i++) {
        if ((pos + (unsigned int)i) < 16u) {
            line[pos + (unsigned int)i] = hex[(value >> ((7 - i) * 4)) & 0x0fu];
        }
    }
}

static void compose_status_lines(char *line1, char *line2) {
    unsigned int i;

    for (i = 0; i < 16u; i++) {
        line1[i] = ' ';
        line2[i] = ' ';
    }
    line1[16] = '\0';
    line2[16] = '\0';

    line_put_text(line1, 0u, (g_crypto_enabled != 0u) ? "RUN " : "PAUSE ");
    line_put_text(line1, 4u, "I=");
    line_put_hex8(line1, 6u, g_crypto_iterations);

    line_put_text(line2, 0u, "C=");
    line_put_hex8(line2, 2u, g_crypto_last_cycles);
    line_put_text(line2, 11u, "K=");
    line2[13] = (g_last_input != '\0') ? g_last_input : '-';
}

void t_gui_task(void *pv) {
    crypto_msg_t msg;
    (void)pv;
    TickType_t wake = xTaskGetTickCount();
    char line1[17];
    char line2[17];

    neorv32_uart0_puts("[gui] started\n");
    de2os_lcd_write_lines("GUI online", "h:help p:pause");

    for (;;) {
        while (xQueueReceive(xCryptoQueue, &msg, 0) == pdPASS) {
            if (msg.msg_type == CRYPTO_MSG_RESULT) {
                g_crypto_last_cycles = msg.cycles;
                g_crypto_iterations = msg.iteration;
            }
        }

        compose_status_lines(line1, line2);
        de2os_lcd_write_lines(line1, line2);
        g_gui_ticks++;

        vTaskDelayUntil(&wake, pdMS_TO_TICKS(200));
    }
}
