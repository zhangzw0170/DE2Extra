/* pong_game.c — PONG controller for de2shell
 *
 * UP/DOWN or W/S: move paddle
 * ENTER: serve ball
 * ESC: return to shell
 *
 * LOCAL_BUILD: simple software paddle tracking
 * NEORV32: writes paddle position to pong_engine registers
 */

#include "vga_hal.h"
#include <stdint.h>

#define PADDLE_H 40
#define FIELD_H  480

static int paddle_y;    /* top Y of paddle (0-439) */
static int active;
static int frame_count;

/* ── Drawing (local mode: text-based PONG) ────────────────────── */

static void draw_field(void) {
    /* Simplified VGA-less PONG display: HUD + score area */
    vga_goto(0, 0);
    vga_puts("=== PONG ===\n", VGA_CYAN);
    vga_puts("Paddle: ", VGA_WHITE);
    /* Show paddle position as a bar */
    int pos = paddle_y * 20 / FIELD_H;
    for (int i = 0; i < 20; i++) {
        if (i >= pos && i < pos + 2)
            vga_putc('#', VGA_GREEN);
        else
            vga_putc('.', VGA_GRAY);
    }
    vga_puts("\n", VGA_BLACK);
    vga_puts("UP/DOWN: move  ENTER: serve  ESC: quit\n", VGA_GRAY);
}

/* ═══════════════════════════════════════════════════════════════
   Shell Callbacks
   ═══════════════════════════════════════════════════════════════ */

static void init(void) {
    vga_clear();
    paddle_y = FIELD_H / 2 - PADDLE_H / 2;
    frame_count = 0;
    active = 1;
    draw_field();
}

static void update(void) {
    if (!active) return;
    if (++frame_count < 3) return;
    frame_count = 0;

#ifdef LOCAL_BUILD
    /* Software mode: just show paddle position */
    draw_field();
#else
    /* NEORV32: write paddle_y to hardware register 0xF000E000 */
    volatile uint32_t *pong_paddle = (volatile uint32_t*)0xF000E000;
    *pong_paddle = paddle_y;
#endif
}

static void input(char c) {
    if (!active) return;
    switch (c) {
        case 27: active = 0; return;  /* ESC */
        case 'w': case 'W':
            if (paddle_y > 0) paddle_y -= 8;
            if (paddle_y < 0) paddle_y = 0;
            break;
        case 's': case 'S':
            if (paddle_y < FIELD_H - PADDLE_H) paddle_y += 8;
            if (paddle_y > FIELD_H - PADDLE_H) paddle_y = FIELD_H - PADDLE_H;
            break;
        case '\r': case '\n':  /* ENTER — serve */
            /* On NEORV32, write serve=1 to control register */
#ifndef LOCAL_BUILD
            volatile uint32_t *pong_ctrl = (volatile uint32_t*)0xF000E00C;
            *pong_ctrl = 1;
#endif
            break;
    }
    draw_field();
}

static int finish(void) { return !active; }

const program_t prog_pong = {
    "PONG", "PONG — UP/DOWN=move ENTER=serve ESC=quit",
    init, update, input, NULL, finish
};
