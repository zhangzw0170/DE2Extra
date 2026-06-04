/* rtos_memory.c -- FreeRTOS application-managed heap in SDRAM */

#include <stdint.h>

#include "FreeRTOS.h"

uint8_t ucHeap[ configTOTAL_HEAP_SIZE ]
    __attribute__((section(".freertos_heap"), aligned(16)));
