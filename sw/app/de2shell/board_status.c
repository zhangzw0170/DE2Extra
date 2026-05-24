#include "board_status.h"
#include "gpio_hal.h"

#ifdef LOCAL_BUILD
  #include <time.h>
  static time_t uptime_start;
#else
  #include <neorv32.h>
#endif

static uint32_t current_word;
static int claimed;

static uint32_t compose_program_word(uint8_t prog_id, uint8_t state, uint8_t flags, uint16_t data) {
    uint32_t word = 0x40000000u;
    word |= ((uint32_t)(prog_id & 0x0fu)) << 24;
    word |= ((uint32_t)(state & 0x0fu)) << 20;
    word |= ((uint32_t)(flags & 0x0fu)) << 16;
    word |= (uint32_t)data;
    return word;
}

void board_status_init(void) {
    claimed = 0;
    current_word = 0;
#ifdef LOCAL_BUILD
    uptime_start = time(NULL);
#endif
}

void board_status_release(void) {
    claimed = 0;
}

int board_status_claimed(void) {
    return claimed;
}

void board_status_set_program(uint8_t prog_id, uint8_t state, uint8_t flags, uint16_t data) {
    claimed = 1;
    current_word = compose_program_word(prog_id, state, flags, data);
    gpio_write_out(current_word);
}

void board_status_set_word(uint32_t word) {
    claimed = 1;
    current_word = word;
    gpio_write_out(word);
}

void board_status_apply_fallback(uint8_t prog_id, uint8_t state) {
    uint32_t word;

    if (claimed) {
        return;
    }

    word = gpio_read_out();
    word &= 0x000fffffu;
    word |= 0x40000000u;
    word |= ((uint32_t)(prog_id & 0x0fu)) << 24;
    word |= ((uint32_t)(state & 0x0fu)) << 20;
    current_word = word;
    gpio_write_out(word);
}

uint32_t board_status_uptime_seconds(void) {
#ifdef LOCAL_BUILD
    time_t now = time(NULL);
    if (now <= uptime_start) {
        return 0;
    }
    return (uint32_t)(now - uptime_start);
#else
    if (neorv32_clint_available() == 0) {
        return 0;
    }
    return (uint32_t)(neorv32_clint_time_get() / (uint64_t)neorv32_sysinfo_get_clk());
#endif
}
