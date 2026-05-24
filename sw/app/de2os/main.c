/* main.c — de2os: FreeRTOS on NEORV32, SDRAM execution
 *
 * Boot mode 0 (bootloader) uploads to 0x01000000.
 * CLINT MTIMER provides the FreeRTOS tick.
 * Three tasks: t_gui (pri 3), t_crypto (pri 2), t_input (pri 1).
 */

#include <neorv32.h>
#include "FreeRTOS.h"
#include "task.h"
#include "queue.h"

#include "t_gui.h"
#include "t_crypto.h"
#include "t_input.h"

#define BAUD_RATE 115200

/* ── Shared queue: crypto -> gui ────────────────────────────────── */

QueueHandle_t xCryptoQueue;

#define CRYPTO_MSG_STATE  1
#define CRYPTO_MSG_DONE   2

typedef struct {
    uint8_t msg_type;
    uint8_t stage;
    uint8_t round;
    uint32_t cycles;
} crypto_msg_t;

/* ── Helper: print 32-bit hex via printf ─────────────────────────── */

static void put_hex(uint32_t v) {
    static const char hex[] = "0123456789abcdef";
    char buf[9];
    for (int i = 7; i >= 0; i--) {
        buf[7 - i] = hex[(v >> (i * 4)) & 0xf];
    }
    buf[8] = '\0';
    neorv32_uart0_puts(buf);
}

/* ── Platform hooks (required by FreeRTOS RISC-V port) ──────────── */

void freertos_risc_v_application_interrupt_handler(void) {
}

void freertos_risc_v_application_exception_handler(void) {
    neorv32_uart0_puts("!!! FreeRTOS exception !!!\n");
    neorv32_uart0_puts("mcause=0x");
    put_hex(neorv32_cpu_csr_read(CSR_MCAUSE));
    neorv32_uart0_puts("\nmepc=0x");
    put_hex(neorv32_cpu_csr_read(CSR_MEPC));
    neorv32_uart0_puts("\n");
    for (;;) ;
}

void vApplicationMallocFailedHook(void) {
    neorv32_uart0_puts("FATAL: FreeRTOS malloc failed\n");
    for (;;) ;
}

void vApplicationStackOverflowHook(TaskHandle_t xTask, char *pcTaskName) {
    (void)xTask;
    neorv32_uart0_puts("FATAL: stack overflow in '");
    neorv32_uart0_puts(pcTaskName);
    neorv32_uart0_puts("'\n");
    for (;;) ;
}

static uint32_t idle_count;

void vApplicationIdleHook(void) {
    idle_count++;
}

/* ── Main ───────────────────────────────────────────────────────── */

int main(void) {
    neorv32_uart0_setup(BAUD_RATE, 0);

    neorv32_uart0_puts("\n=== de2os: FreeRTOS on NEORV32 ===\n");
    neorv32_uart0_puts("CPU clock: ");
    put_hex((uint32_t)NEORV32_SYSINFO->CLK);
    neorv32_uart0_puts(" Hz\n");

    /* Install FreeRTOS trap handler — replaces NEORV32 RTE */
    extern void freertos_risc_v_trap_handler(void);
    neorv32_cpu_csr_write(CSR_MTVEC, (uint32_t)freertos_risc_v_trap_handler);

    xCryptoQueue = xQueueCreate(8, sizeof(crypto_msg_t));
    if (xCryptoQueue == NULL) {
        neorv32_uart0_puts("FATAL: queue create failed\n");
        for (;;) ;
    }

    BaseType_t ret;
    ret = xTaskCreate(t_gui_task, "gui", 256, NULL, 3, NULL);
    if (ret != pdPASS) { neorv32_uart0_puts("ERR: gui task\n"); }

    ret = xTaskCreate(t_crypto_task, "crypto", 384, NULL, 2, NULL);
    if (ret != pdPASS) { neorv32_uart0_puts("ERR: crypto task\n"); }

    ret = xTaskCreate(t_input_task, "input", 192, NULL, 1, NULL);
    if (ret != pdPASS) { neorv32_uart0_puts("ERR: input task\n"); }

    neorv32_uart0_puts("Starting scheduler...\n");
    vTaskStartScheduler();

    neorv32_uart0_puts("FATAL: scheduler returned\n");
    for (;;) ;
}
