/* rtos_memory.c -- FreeRTOS application-managed heap in SDRAM */

#include <stdint.h>

#include "FreeRTOS.h"

uint8_t ucHeap[ configTOTAL_HEAP_SIZE ]
    __attribute__((section(".sdram_bss"), aligned(16)));
