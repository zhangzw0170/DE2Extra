/* pong_hw.c — Hardware PONG game using FPGA pong_engine
 *
 * FPGA pong_engine at 0xF0011000 handles all rendering and physics.
 * CPU controls paddles via PS/2/UART and reads scores.
 *
 * Registers:
 *   0x00 [W] paddle_l: bits[9:0] = top Y (0..439)
 *   0x04 [W] paddle_r: bits[9:0] = top Y
 *   0x08 [W] control: bit0=serve/reset, bit1=pause, bit2=enable
 *   0x0C [R] scores: [15:8]=left, [7:0]=right
 */
#include "board_status.h"
#include "vga_hal.h"
#include "ps2_decoder.h"
#include <stdint.h>

#define PONG_BASE  ((volatile uint32_t *)0xF0011000u)

#define PONG_PADDLE_L  (*(PONG_BASE + 0))  /* W */
#define PONG_PADDLE_R  (*(PONG_BASE + 1))  /* W */
#define PONG_CONTROL   (*(PONG_BASE + 2))  /* W */
#define PONG_SCORES    (*(PONG_BASE + 3))  /* R */

#define PONG_CTL_SERVE  0x01u
#define PONG_CTL_PAUSE  0x02u
#define PONG_CTL_ENABLE 0x04u
#define PONG_PROG_ID    7u
#define HW_TIMEOUT      1000000  /* ~20ms @50MHz */

static int initialized;
static int paddle_l_y;
static int paddle_r_y;
static int paused;

/* PS/2 scancode helpers */
#define PS2_MMIO_BASE ((volatile uint32_t *)0xF0008000u)
#define PS2_REG_DATA  0u
#define PS2_REG_STAT  1u
#define PS2_STAT_READY 0x01u

static int ps2_available(void) {
    return (int)(PS2_MMIO_BASE[PS2_REG_STAT] & PS2_STAT_READY);
}

static uint8_t ps2_read(void) {
    return (uint8_t)(PS2_MMIO_BASE[PS2_REG_DATA] & 0xFFu);
}

static void hw_set_paddles(void) {
    if (paddle_l_y < 0) paddle_l_y = 0;
    if (paddle_l_y > 439) paddle_l_y = 439;
    if (paddle_r_y < 0) paddle_r_y = 0;
    if (paddle_r_y > 439) paddle_r_y = 439;
    PONG_PADDLE_L = (uint32_t)paddle_l_y;
    PONG_PADDLE_R = (uint32_t)paddle_r_y;
}

static uint8_t hw_left_score(void) {
    return (uint8_t)(PONG_SCORES >> 8);
}

static uint8_t hw_right_score(void) {
    return (uint8_t)(PONG_SCORES & 0xFF);
}

/* ── Callbacks ───────────────────────────────────────────────────── */

static void init(void) {
    paddle_l_y = 220;
    paddle_r_y = 220;
    paused = 1;

    /* Enable PONG (takes over VGA output) */
    PONG_CONTROL = PONG_CTL_ENABLE | PONG_CTL_PAUSE;

    /* Serve the ball */
    PONG_CONTROL = PONG_CTL_ENABLE | PONG_CTL_SERVE;

    initialized = 1;
}

static void update(void) {
    if (!initialized) return;

    /* Check PS/2 for paddle input */
    while (ps2_available()) {
        uint8_t sc = ps2_read();
        ps2_key_t key;
        if (ps2_dec_feed(sc, &key)) {
            if (key.is_press) {
                /* Left paddle: W/S */
                if (key.ascii == 'w' || key.ascii == 'W') {
                    paddle_l_y -= 12;
                    hw_set_paddles();
                }
                if (key.ascii == 's' || key.ascii == 'S') {
                    paddle_l_y += 12;
                    hw_set_paddles();
                }
                /* Right paddle: Up/Down arrows (E0-prefixed, scancode 0x75/0x72) */
                if (key.scancode == 0x75) {  /* UP */
                    paddle_r_y -= 12;
                    hw_set_paddles();
                }
                if (key.scancode == 0x72) {  /* DOWN */
                    paddle_r_y += 12;
                    hw_set_paddles();
                }
                /* Pause toggle */
                if (key.ascii == 'p' || key.ascii == 'P') {
                    paused = !paused;
                    uint32_t ctl = PONG_CTL_ENABLE;
                    if (paused) ctl |= PONG_CTL_PAUSE;
                    PONG_CONTROL = ctl;
                }
                /* Quit */
                if (key.ascii == 'q' || key.ascii == 'Q') {
                    PONG_CONTROL = 0;  /* disable PONG, return to text terminal */
                    initialized = 0;
                    return;
                }
                /* Serve */
                if (key.ascii == ' ') {
                    PONG_CONTROL = PONG_CTL_ENABLE | PONG_CTL_SERVE;
                }
            }
        }
    }

    /* Update board status */
    board_status_set_program(PONG_PROG_ID, paused ? BOARD_STATE_EDIT : BOARD_STATE_RUN,
                             0u, (uint16_t)((hw_left_score() << 8) | hw_right_score()));
}

static void input(char c) {
    if (!initialized) return;

    /* UART fallback paddle control */
    switch (c) {
        case 'q': case 'Q':
            PONG_CONTROL = 0;
            initialized = 0;
            return;
        case 'w': case 'W':
            paddle_l_y -= 12; hw_set_paddles(); break;
        case 's': case 'S':
            paddle_l_y += 12; hw_set_paddles(); break;
        case 'i': case 'I':
            paddle_r_y -= 12; hw_set_paddles(); break;
        case 'k': case 'K':
            paddle_r_y += 12; hw_set_paddles(); break;
        case 'p': case 'P':
            paused = !paused;
            {
                uint32_t ctl = PONG_CTL_ENABLE;
                if (paused) ctl |= PONG_CTL_PAUSE;
                PONG_CONTROL = ctl;
            }
            break;
        case ' ':
            PONG_CONTROL = PONG_CTL_ENABLE | PONG_CTL_SERVE;
            break;
        default: return;
    }
}

static int finish(void) { return !initialized; }

const program_t prog_pong_hw = {
    "PongHW", "Hardware PONG — W/S left, I/K right, P pause, SPACE serve, Q quit",
    init, update, input, NULL, finish
};
