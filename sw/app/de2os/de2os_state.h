/* de2os_state.h -- shared state for de2os tasks */

#ifndef DE2OS_STATE_H
#define DE2OS_STATE_H

#include <stdint.h>

#include "FreeRTOS.h"
#include "queue.h"

#define CRYPTO_MSG_RESULT 1u

typedef struct {
    uint8_t msg_type;
    uint8_t reserved0;
    uint8_t reserved1;
    uint8_t reserved2;
    uint32_t cycles;
    uint32_t iteration;
} crypto_msg_t;

extern QueueHandle_t xCryptoQueue;

extern volatile uint32_t g_crypto_iterations;
extern volatile uint32_t g_crypto_last_cycles;
extern volatile uint32_t g_gui_ticks;
extern volatile uint32_t g_idle_count;
extern volatile uint8_t g_crypto_enabled;
extern volatile uint8_t g_crypto_single_shot_request;
extern volatile uint8_t g_crypto_reset_request;
extern volatile char g_last_input;

#endif
