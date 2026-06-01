#ifndef BOARD_STATUS_H
#define BOARD_STATUS_H

#include <stdint.h>

enum {
    BOARD_STATE_READY = 0x0,
    BOARD_STATE_LIVE  = 0x1,
    BOARD_STATE_RUN   = 0x2,
    BOARD_STATE_EDIT  = 0x3,
    BOARD_STATE_HOLD  = 0x4,
    BOARD_STATE_PASS  = 0x5,
    BOARD_STATE_FAIL  = 0x6,
    BOARD_STATE_BUSY  = 0x7
};

void board_status_init(void);
void board_status_release(void);
int board_status_claimed(void);
void board_status_set_program(uint8_t prog_id, uint8_t state, uint8_t flags, uint16_t data);
void board_status_set_word(uint32_t word);
void board_status_apply_fallback(uint8_t prog_id, uint8_t state);
uint32_t board_status_uptime_seconds(void);

#endif
