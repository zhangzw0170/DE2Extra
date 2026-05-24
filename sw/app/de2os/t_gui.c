/* t_gui.c — GUI task (stub: UART heartbeat) */

#include <neorv32.h>
#include "FreeRTOS.h"
#include "task.h"
#include "queue.h"

extern QueueHandle_t xCryptoQueue;

void t_gui_task(void *pv) {
    (void)pv;
    TickType_t wake = xTaskGetTickCount();

    neorv32_uart0_puts("[gui] started\n");

    for (;;) {
        /* Check crypto queue (non-blocking) */
        /*
        crypto_msg_t msg;
        if (xQueueReceive(xCryptoQueue, &msg, 0) == pdPASS) {
            // TODO: render crypto state to VGA framebuffer
        }
        */

        neorv32_uart0_puts("[gui] tick\n");
        vTaskDelayUntil(&wake, pdMS_TO_TICKS(1000));
    }
}
