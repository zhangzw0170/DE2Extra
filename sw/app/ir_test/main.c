// ir_test/main.c — Software NEC IR decode via hardware timer captures
//
// Timer (0xF0004000):
//   0x00 COUNTER (R) — free-running 32-bit counter
//   0x04 CAPTURE (R) — counter value at last IR edge
//   0x08 CONTROL (R/W)— [0]=cap_en, [1]=irq_en, [2]=cap_flag
//
// Polls CONTROL[2] (cap_flag), reads CAPTURE on each edge,
// computes delta, runs NEC state machine in C.

#include <neorv32.h>
#include <stdint.h>
#include <stdio.h>

#define TIMER_BASE  ((volatile uint32_t *)0xF0004000)
#define INTC_BASE   ((volatile uint32_t *)0xF0006000)
#define GPIO_BASE   ((volatile uint32_t *)0xFFFC0000)

#define TIMER_COUNTER  0
#define TIMER_CAPTURE  1
#define TIMER_CONTROL  2

#define INTC_PENDING   0
#define INTC_MASK      1

static uint32_t rev8(uint32_t v) {
    uint32_t r = 0;
    for (int i = 0; i < 8; i++)
        r |= ((v >> i) & 1) << (7 - i);
    return r;
}

int main(void) {
    neorv32_uart0_setup(115200, 0);

    printf("IR test: timer-based NEC decode\r\n");

    // Enable timer capture
    TIMER_BASE[TIMER_CONTROL] = 1;  // capture_en=1, irq_en=0

    // Wait for first capture to seed t_prev
    uint32_t ctrl;
    while (1) {
        ctrl = TIMER_BASE[TIMER_CONTROL];
        if (ctrl & 0x04) break;  // cap_flag set
    }
    uint32_t t_prev = TIMER_BASE[TIMER_CAPTURE];
    TIMER_BASE[TIMER_CONTROL] = 1;  // clear cap_flag, keep enabled

    printf("Timer armed. Press IR buttons...\r\n");

    // NEC state machine
    int state   = 0;      // 0=idle, 1=data
    int bit_cnt = 0;
    uint32_t shift_reg = 0;

    for (;;) {
        ctrl = TIMER_BASE[TIMER_CONTROL];
        if (!(ctrl & 0x04)) continue;  // no new capture

        uint32_t t_now = TIMER_BASE[TIMER_CAPTURE];
        TIMER_BASE[TIMER_CONTROL] = 1;  // clear cap_flag

        uint32_t delta = t_now - t_prev;
        t_prev = t_now;

        switch (state) {
        case 0:  // IDLE — look for NEC leader (9ms LOW)
            // NEC leader: ~9ms = 450000 cycles @50MHz
            if (delta >= 400000 && delta <= 550000) {
                state = 1;
                bit_cnt = 0;
                shift_reg = 0;
            }
            break;

        case 1:  // DATA — collect 32 bits
            if (delta >= 45000 && delta <= 80000) {
                // logical 0: ~562.5us
                shift_reg <<= 1;
            } else if (delta >= 90000 && delta <= 135000) {
                // logical 1: ~1.125ms / ~2.25ms
                shift_reg = (shift_reg << 1) | 1;
            } else {
                // timeout or bad pulse — abort
                printf("ERR: bad delta=%lu at bit %d\r\n", (unsigned long)delta, bit_cnt);
                state = 0;
                break;
            }
            bit_cnt++;
            if (bit_cnt == 32) {
                // NEC frame: addr_inv addr cmd cmd_inv
                uint32_t addr     = (shift_reg >> 24) & 0xFF;
                uint32_t addr_inv = (shift_reg >> 16) & 0xFF;
                uint32_t cmd_inv  = (shift_reg >>  8) & 0xFF;
                uint32_t cmd      =  shift_reg        & 0xFF;
                int ok = (cmd == (uint8_t)~cmd_inv);
                printf("NEC: addr=0x%02X cmd=0x%02X %s\r\n",
                       (unsigned)rev8(addr),
                       (unsigned)rev8(cmd),
                       ok ? "OK" : "CHK");
                state = 0;
            }
            break;
        }
    }
}
