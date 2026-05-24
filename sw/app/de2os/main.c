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

#include "de2os_hal.h"
#include "de2os_state.h"
#include "t_gui.h"
#include "t_crypto.h"
#include "t_input.h"

#define BAUD_RATE 115200

QueueHandle_t xCryptoQueue;
volatile uint32_t g_crypto_iterations;
volatile uint32_t g_crypto_last_cycles;
volatile uint32_t g_gui_ticks;
volatile uint32_t g_idle_count;
volatile uint8_t g_crypto_enabled;
volatile uint8_t g_crypto_single_shot_request;
volatile uint8_t g_crypto_reset_request;
volatile char g_last_input;

/* ── Platform hooks (required by FreeRTOS RISC-V port) ──────────── */

void freertos_risc_v_application_interrupt_handler(void) {
}

void freertos_risc_v_application_exception_handler(void) {
    neorv32_uart0_puts("!!! FreeRTOS exception !!!\n");
    neorv32_uart0_puts("mcause=0x");
    de2os_uart_put_hex(neorv32_cpu_csr_read(CSR_MCAUSE));
    neorv32_uart0_puts("\nmepc=0x");
    de2os_uart_put_hex(neorv32_cpu_csr_read(CSR_MEPC));
    neorv32_uart0_puts("\n");
    de2os_lcd_write_lines("EXCEPTION", "mcause see UART");
    for (;;) ;
}

void vApplicationMallocFailedHook(void) {
    neorv32_uart0_puts("FATAL: FreeRTOS malloc failed\n");
    de2os_lcd_write_lines("FATAL", "malloc failed");
    for (;;) ;
}

void vApplicationStackOverflowHook(TaskHandle_t xTask, char *pcTaskName) {
    (void)xTask;
    neorv32_uart0_puts("FATAL: stack overflow in '");
    neorv32_uart0_puts(pcTaskName);
    neorv32_uart0_puts("'\n");
    de2os_lcd_write_lines("FATAL", "stack overflow");
    for (;;) ;
}

void vApplicationIdleHook(void) {
    g_idle_count++;
}

/* ── Main ───────────────────────────────────────────────────────── */

int main(void) {
    neorv32_uart0_setup(BAUD_RATE, 0);
    neorv32_uart0_puts("\n=== de2os: FreeRTOS on NEORV32 ===\n");
    neorv32_uart0_puts("CPU clock: ");
    de2os_uart_put_hex((uint32_t)NEORV32_SYSINFO->CLK);
    neorv32_uart0_puts(" Hz\n");

    neorv32_uart0_puts("LCD init...\n");
    de2os_lcd_init();
    neorv32_uart0_puts("LCD init done\n");
    de2os_lcd_write_lines("DE2Extra Boot", "FreeRTOS 50MHz");

    /* Install FreeRTOS trap handler — replaces NEORV32 RTE */
    extern void freertos_risc_v_trap_handler(void);
    neorv32_cpu_csr_write(CSR_MTVEC, (uint32_t)freertos_risc_v_trap_handler);

    g_crypto_iterations = 0u;
    g_crypto_last_cycles = 0u;
    g_gui_ticks = 0u;
    g_idle_count = 0u;
    g_crypto_enabled = 1u;
    g_crypto_single_shot_request = 0u;
    g_crypto_reset_request = 0u;
    g_last_input = '-';

    xCryptoQueue = xQueueCreate(8, sizeof(crypto_msg_t));
    if (xCryptoQueue == NULL) {
        neorv32_uart0_puts("FATAL: queue create failed\n");
        de2os_lcd_write_lines("FATAL", "queue failed");
        for (;;) ;
    }

    BaseType_t ret;
    ret = xTaskCreate(t_gui_task, "gui", 256, NULL, 3, NULL);
    if (ret != pdPASS) { neorv32_uart0_puts("ERR: gui task\n"); }

    ret = xTaskCreate(t_crypto_task, "crypto", 384, NULL, 2, NULL);
    if (ret != pdPASS) { neorv32_uart0_puts("ERR: crypto task\n"); }

    ret = xTaskCreate(t_input_task, "input", 192, NULL, 1, NULL);
    if (ret != pdPASS) { neorv32_uart0_puts("ERR: input task\n"); }

    de2os_lcd_write_lines("DE2Extra Boot", "Starting tasks");
    neorv32_uart0_puts("Starting scheduler...\n");
    vTaskStartScheduler();

    neorv32_uart0_puts("FATAL: scheduler returned\n");
    de2os_lcd_write_lines("FATAL", "sched returned");
    for (;;) ;
}
