/* t_crypto.c -- crypto worker task */

#include <neorv32.h>
#include <stdint.h>
#include "FreeRTOS.h"
#include "task.h"
#include "queue.h"

#include "de2os_hal.h"
#include "de2os_state.h"

static uint16_t modmul(uint16_t a, uint16_t b, uint16_t q) {
    uint32_t p = (uint32_t)a * b;
    return (uint16_t)(p % q);
}

static uint32_t run_soft_benchmark(void) {
    uint32_t t0 = neorv32_cpu_get_cycle();
    volatile uint16_t acc = 1u;
    int i;

    for (i = 0; i < 1000; i++) {
        acc = modmul(acc, 17u, 3329u);
    }

    (void)acc;
    return neorv32_cpu_get_cycle() - t0;
}

void t_crypto_task(void *pv) {
    (void)pv;
    uint32_t iter = 0u;

    neorv32_uart0_puts("[crypto] started\n");

    for (;;) {
        crypto_msg_t msg;
        uint32_t cycles;

        if (g_crypto_reset_request != 0u) {
            iter = 0u;
            g_crypto_iterations = 0u;
            g_crypto_last_cycles = 0u;
            g_crypto_reset_request = 0u;
        }

        if ((g_crypto_enabled == 0u) && (g_crypto_single_shot_request == 0u)) {
            vTaskDelay(pdMS_TO_TICKS(100));
            continue;
        }

        cycles = run_soft_benchmark();
        iter++;
        g_crypto_iterations = iter;
        g_crypto_last_cycles = cycles;
        g_crypto_single_shot_request = 0u;

        msg.msg_type = CRYPTO_MSG_RESULT;
        msg.reserved0 = 0u;
        msg.reserved1 = 0u;
        msg.reserved2 = 0u;
        msg.cycles = cycles;
        msg.iteration = iter;
        (void)xQueueSend(xCryptoQueue, &msg, 0);

        neorv32_uart0_puts("[crypto] #");
        de2os_uart_put_hex(iter);
        neorv32_uart0_puts(" cycles=");
        de2os_uart_put_hex(cycles);
        neorv32_uart0_puts("\n");

        vTaskDelay(pdMS_TO_TICKS((g_crypto_enabled != 0u) ? 1000 : 100));
    }
}
