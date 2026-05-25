/* FreeRTOSConfig.h — NEORV32 on DE2-115 @ 50 MHz
 *
 * Based on de2os FreeRTOSConfig.h with larger heap for de2shell programs.
 * Target: RV32IMC, CLINT MTIMER tick, machine mode only
 * Memory: .text in SDRAM (0x01000000), .data/.bss in DMEM (0x80000000)
 */

#ifndef FREERTOS_CONFIG_H
#define FREERTOS_CONFIG_H

#include "neorv32.h"

/* ── Hardware ──────────────────────────────────────────────────── */

#define configCPU_CLOCK_HZ              50000000UL
#define configMTIME_BASE_ADDRESS        ( NEORV32_CLINT_BASE + 0xBFF8UL )
#define configMTIMECMP_BASE_ADDRESS     ( NEORV32_CLINT_BASE + 0x4000UL )

/* ── Kernel ────────────────────────────────────────────────────── */

#define configUSE_PREEMPTION            1
#define configUSE_PORT_OPTIMISED_TASK_SELECTION 1
#define configUSE_TICKLESS_IDLE         0
#define configTICK_RATE_HZ              ( ( TickType_t ) 100 )
#define configMAX_PRIORITIES            5
#define configMINIMAL_STACK_SIZE        ( ( uint16_t ) 192 )
#define configTOTAL_HEAP_SIZE           ( ( size_t ) 16384 )
#define configMAX_TASK_NAME_LEN         8
#define configUSE_16_BIT_TICKS          0
#define configIDLE_SHOULD_YIELD         1
#define configUSE_TASK_NOTIFICATIONS    1
#define configTASK_NOTIFICATION_ARRAY_ENTRIES 1
#define configQUEUE_REGISTRY_SIZE       8
#define configUSE_QUEUE_SETS            0
#define configUSE_MUTEXES               1
#define configUSE_TIME_SLICING          1
#define configUSE_NEWLIB_REENTRANT      0
#define configENABLE_BACKWARD_COMPATIBILITY 0
#define configNUM_THREAD_LOCAL_STORAGE_POINTERS 0

/* ── Memory allocation ─────────────────────────────────────────── */

#define configSUPPORT_STATIC_ALLOCATION 0
#define configSUPPORT_DYNAMIC_ALLOCATION 1
#define configKERNEL_PROVIDED_STATIC_MEMORY 0
#define configAPPLICATION_ALLOCATED_HEAP 1

/* ── Hooks ─────────────────────────────────────────────────────── */

#define configUSE_IDLE_HOOK             1
#define configUSE_TICK_HOOK             0
#define configUSE_MALLOC_FAILED_HOOK    1
#define configCHECK_FOR_STACK_OVERFLOW  1
#define configUSE_DAEMON_TASK_STARTUP_HOOK 0

/* ── FreeRTOS+CLI ──────────────────────────────────────────────── */

#define configCOMMAND_INT_MAX_OUTPUT_SIZE    256
#define configAPPLICATION_PROVIDES_cOutputBuffer    1

/* ── Run-time stats (mcycle CSR @ 50 MHz) ─────────────────────── */

#define configGENERATE_RUN_TIME_STATS           1
#define configUSE_TRACE_FACILITY                1
#define configUSE_STATS_FORMATTING_FUNCTIONS    1
#define portCONFIGURE_TIMER_FOR_RUN_TIME_STATS() /* mcycle always runs */
#define portGET_RUN_TIME_COUNTER_VALUE()         neorv32_cpu_csr_read(CSR_MCYCLE)

/* ── Software timers ───────────────────────────────────────────── */

#define configUSE_TIMERS                0

/* ── Co-routines (deprecated) ──────────────────────────────────── */

#define configUSE_CO_ROUTINES           0

/* ── API function inclusion ────────────────────────────────────── */

#define INCLUDE_vTaskPrioritySet        1
#define INCLUDE_uxTaskPriorityGet       1
#define INCLUDE_vTaskDelete             1
#define INCLUDE_vTaskCleanUpResources   0
#define INCLUDE_vTaskSuspend            1
#define INCLUDE_vTaskDelayUntil         1
#define INCLUDE_vTaskDelay              1
#define INCLUDE_xTaskGetSchedulerState  1
#define INCLUDE_xTimerPendFunctionCall  0
#define INCLUDE_uxTaskGetStackHighWaterMark 1
#define INCLUDE_xTaskGetCurrentTaskHandle 1
#define INCLUDE_xTaskGetIdleTaskHandle  0
#define INCLUDE_eTaskGetState           0

/* ── RISC-V port specifics ─────────────────────────────────────── */

#define configRISCV_CHIP_EXTENSIONS \
    "freertos/portable/GCC/RISC-V/chip_specific_extensions/RISCV_MTIME_CLINT_no_extensions/freertos_risc_v_chip_specific_extensions.h"

#define configISR_STACK_SIZE_WORDS      256

#define configASSERT( x ) if( ( x ) == 0 ) { taskDISABLE_INTERRUPTS(); for( ;; ); }

#endif /* FREERTOS_CONFIG_H */
