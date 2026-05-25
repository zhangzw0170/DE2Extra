/* FreeRTOS.h — Minimal FreeRTOS stubs for standalone CLI testing
 *
 * Provides just enough to compile FreeRTOS_CLI.c without the kernel.
 */

#ifndef FREERTOS_H
#define FREERTOS_H

#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include <stdio.h>

typedef long BaseType_t;
typedef unsigned long UBaseType_t;
typedef uint32_t TickType_t;

#define pdTRUE         ( ( BaseType_t ) 1 )
#define pdFALSE        ( ( BaseType_t ) 0 )
#define pdPASS         ( pdTRUE )
#define pdFAIL         ( pdFALSE )

#define configSUPPORT_DYNAMIC_ALLOCATION     1
#define configCOMMAND_INT_MAX_OUTPUT_SIZE    512
#define configAPPLICATION_PROVIDES_cOutputBuffer 1

#define configASSERT( x ) do { if( !(x) ) { fprintf(stderr, "ASSERT: %s:%d\n", __FILE__, __LINE__); abort(); } } while(0)

/* Stubs for FreeRTOS kernel functions used by CLI */
static inline void *pvPortMalloc(size_t sz) { return malloc(sz); }
static inline void vPortFree(void *p) { free(p); }
#define taskENTER_CRITICAL()
#define taskEXIT_CRITICAL()

#endif
