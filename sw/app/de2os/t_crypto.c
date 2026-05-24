/* t_crypto.c — Crypto accelerator task (stub: periodic benchmark) */

#include <neorv32.h>
#include "FreeRTOS.h"
#include "task.h"
#include "queue.h"

extern QueueHandle_t xCryptoQueue;

/* Simple SW NTT for testing (N=4, q=13) — just to have crypto work to do */
static uint16_t modmul(uint16_t a, uint16_t b, uint16_t q) {
    uint32_t p = (uint32_t)a * b;
    return (uint16_t)(p % q);
}

static void put_hex(uint32_t v) {
    static const char hex[] = "0123456789abcdef";
    char buf[9];
    for (int i = 7; i >= 0; i--) {
        buf[7 - i] = hex[(v >> (i * 4)) & 0xf];
    }
    buf[8] = '\0';
    neorv32_uart0_puts(buf);
}

void t_crypto_task(void *pv) {
    (void)pv;
    TickType_t wake = xTaskGetTickCount();
    uint32_t iter = 0;

    neorv32_uart0_puts("[crypto] started\n");

    for (;;) {
        uint32_t t0 = neorv32_cpu_get_cycle();

        volatile uint16_t acc = 1;
        for (int i = 0; i < 1000; i++) {
            acc = modmul(acc, 17, 3329);
        }

        uint32_t t1 = neorv32_cpu_get_cycle();
        (void)acc;

        neorv32_uart0_puts("[crypto] #");
        put_hex(iter++);
        neorv32_uart0_puts(" cycles=");
        put_hex(t1 - t0);
        neorv32_uart0_puts("\n");

        vTaskDelayUntil(&wake, pdMS_TO_TICKS(3000));
    }
}
