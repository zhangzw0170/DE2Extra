/* twm.c -- Tiling window manager desktop (sway-inspired)
 *
 * Alt as Mod key (matches sway default).
 *   Alt+Return   Split focused leaf (auto direction: H if wider, V if taller)
 *   Alt+H        Force horizontal split
 *   Alt+V        Force vertical split
 *   Alt+Arrow    Move focus
 *   Alt+Shift+Arrow  Resize (shift ratio by 5%)
 *   Alt+W        Close focused leaf
 *   Esc          Exit desktop
 *
 * LOCAL_BUILD: SDL2 keyboard input.
 * NEORV32:     PS/2 scancode polling.
 */
#include "vga_hal.h"
#include "fb_hal.h"
#include "gfx.h"
#include "gui.h"
#include "ps2_decoder.h"
#include "board_status.h"
#include <string.h>

#ifdef LOCAL_BUILD
  #include <stdio.h>
  #include <SDL.h>
#else
  #include <neorv32.h>
  #define PS2_MMIO_BASE ((volatile uint32_t *)0xF0008000u)
  #define PS2_REG_DATA  0u
  #define PS2_REG_STAT  1u
  #define PS2_STAT_READY 0x01u
  #define VGA_MMIO_BASE ((volatile uint32_t *)0xF0000000u)
  #define VGA_PX_MODE_REG     (0x7000u / 4u)
  #define VGA_PX_FB_BASE_REG  (0x7004u / 4u)
  #define VGA_PX_STATUS_REG   (0x7008u / 4u)
  #define VGA_PX_DEBUG0_REG   (0x700Cu / 4u)
  #define VGA_PX_DEBUG1_REG   (0x7010u / 4u)
  #define VGA_PX_DEBUG2_REG   (0x7014u / 4u)
  #define VGA_PX_DEBUG3_REG   (0x7018u / 4u)
  #define VGA_PX_SAMPLE0_REG  (0x701Cu / 4u)
  #define VGA_PX_SAMPLE1_REG  (0x7020u / 4u)
  #define VGA_PX_SAMPLE2_REG  (0x7024u / 4u)
  #define VGA_PX_SAMPLE3_REG  (0x7028u / 4u)
#endif

/* PS/2 scancodes (set 2) */

/* Both Left and Right Alt share scancode 0x38.
 * Right Alt arrives with E0 prefix -> ps2_decoder sets is_extended=1. */
#define SC_ALT      0x38
#define SC_ALT_BRK  0xB8

/* State */

static int running;
static int alt_held;
/* Redraw only after layout/input changes; continuous full-screen repaint
 * saturates the FPGA framebuffer path and causes visible corruption. */
static int redraw_pending;
/* UART /-prefix command state */
static int uart_slash;

/* Helpers */

#ifndef LOCAL_BUILD
static void twm_prompt(void) {
    neorv32_uart0_puts("\rtwm > ");
}
#endif

static int is_alt(uint8_t sc) {
    return sc == SC_ALT || sc == SC_ALT_BRK;
}

static void request_redraw(void) {
    redraw_pending = 1;
}

/* Key handling */

static void process_key(uint8_t ascii, uint8_t scancode,
                        int is_press, int is_extended) {
    /* Track Alt modifier */
    if (is_alt(scancode)) {
        alt_held = (is_press && !is_extended);
        return;
    }

    if (!is_press) return;

    /* Plain Esc exits (no Alt held) */
    if (ascii == 0x1b && !alt_held) {
        running = 0;
        return;
    }

    /* Detect Shift for Alt+Shift combos */
    int shift = 0;
#ifdef LOCAL_BUILD
    {
        SDL_Keymod mod = SDL_GetModState();
        shift = (mod & (KMOD_LSHIFT | KMOD_RSHIFT)) ? 1 : 0;
    }
#else
    shift = ps2_dec_shift();
#endif

    /* Tiling commands (Alt held) */
    if (alt_held) {
        switch (ascii) {
        case 'h': case 'H':
            tile_split(TILE_SPLIT_H);
            request_redraw();
            return;
        case 'v': case 'V':
            tile_split(TILE_SPLIT_V);
            request_redraw();
            return;
        case 'f': case 'F':
            tile_toggle_fullscreen();
            request_redraw();
            return;
        case 'q': case 'Q':
            tile_close();
            request_redraw();
            return;
        case 'w': case 'W':
            tile_close();
            request_redraw();
            return;
        case '\r': {
            tile_t *t = tile_focused();
            if (t) tile_split(t->w >= t->h ? TILE_SPLIT_H : TILE_SPLIT_V);
            request_redraw();
            return;
        }
        case '\t':
            tile_focus_cycle(shift);
            request_redraw();
            return;
        }

        /* Arrow keys */
        if (is_extended) {
            if (shift) {
                /* Alt+Shift+Arrow -- resize */
                switch (scancode) {
                case 0x6b: tile_resize(0, -1); request_redraw(); return;
                case 0x74: tile_resize(0, +1); request_redraw(); return;
                case 0x75: tile_resize(1, -1); request_redraw(); return;
                case 0x72: tile_resize(1, +1); request_redraw(); return;
                }
            } else {
                switch (scancode) {
                case 0x6b: tile_focus_dir(0); request_redraw(); return;
                case 0x74: tile_focus_dir(1); request_redraw(); return;
                case 0x75: tile_focus_dir(2); request_redraw(); return;
                case 0x72: tile_focus_dir(3); request_redraw(); return;
                }
            }
        }
    }

    /* Tab without Alt -- cycle focus */
    if (ascii == 0x09 && !alt_held) {
        tile_focus_cycle(shift);
        request_redraw();
        return;
    }
}

/* Program interface */

static void tiling_init(void) {
    board_status_set_program(8u, BOARD_STATE_RUN, 0u, 0u);
    fb_init();
    fb_set_debug_pattern(0);
    ps2_dec_init();
    tile_init();
    tile_set_panel_render(panel_render);
    tile_layout();
    tile_render_all();
    running = 1;
    alt_held = 0;
    redraw_pending = 0;
    uart_slash = 0;
#ifndef LOCAL_BUILD
    neorv32_uart0_puts("\nTWM: /h /v /w /f /j /l /i /k  Tab=cycle  F10=quit\n");
    twm_prompt();
#endif
}

static void tiling_update(void) {
#ifdef LOCAL_BUILD
    SDL_Event e;
    while (SDL_PollEvent(&e)) {
        if (e.type == SDL_QUIT) { running = 0; return; }
        if (e.type == SDL_KEYDOWN || e.type == SDL_KEYUP) {
            int is_press = (e.type == SDL_KEYDOWN);
            uint8_t ascii = 0, scancode = 0;
            int is_extended = 0;

            SDL_Keycode sym = e.key.keysym.sym;
            SDL_Keymod mod = SDL_GetModState();

            /* Alt key */
            if (sym == SDLK_LALT || sym == SDLK_RALT) {
                scancode = SC_ALT;
                if (!is_press) scancode = SC_ALT_BRK;
            }
            /* Nav keys */
            else if (sym == SDLK_ESCAPE)     { ascii = 0x1b; }
            else if (sym == SDLK_RETURN)     { ascii = '\r'; }
            else if (sym == SDLK_TAB)        { ascii = 0x09; }
            else if (sym == SDLK_UP)         { scancode = 0x75; is_extended = 1; }
            else if (sym == SDLK_DOWN)       { scancode = 0x72; is_extended = 1; }
            else if (sym == SDLK_LEFT)       { scancode = 0x6b; is_extended = 1; }
            else if (sym == SDLK_RIGHT)      { scancode = 0x74; is_extended = 1; }
            /* Printable */
            else if (sym >= ' ' && sym < 127) {
                ascii = (uint8_t)sym;
                if (mod & (KMOD_LSHIFT | KMOD_RSHIFT))
                    if (ascii >= 'a' && ascii <= 'z') ascii -= 32;
            }

            process_key(ascii, scancode, is_press, is_extended);
        }
    }
#else
    {
        ps2_key_t key;
        int budget = 8;
        while ((budget-- > 0) &&
               ((PS2_MMIO_BASE[PS2_REG_STAT] & PS2_STAT_READY) != 0u)) {
            uint8_t raw = (uint8_t)PS2_MMIO_BASE[PS2_REG_DATA];
            if (ps2_dec_feed(raw, &key))
                process_key(key.ascii, key.scancode, key.is_press, key.is_extended);
        }
    }
#endif

    if (redraw_pending) {
        tile_layout();
        tile_render_all();
        redraw_pending = 0;
    }
}

static void tiling_input(char c) {
    uint8_t k = (uint8_t)c;

    /* F10 / ESC → quit */
    if (k == PS2_VK_F10 || k == 0x1b) { running = 0; return; }

    /* /-prefix: /h /v /w /f /j /l /i /k /J /L /I /K */
    if (uart_slash) {
        uart_slash = 0;
        switch (k) {
        case 'h': tile_split(TILE_SPLIT_H);  break;
        case 'v': tile_split(TILE_SPLIT_V);  break;
        case 'w': tile_close();               break;
        case 'f': tile_toggle_fullscreen();   break;
        case 'j': tile_focus_dir(0);          break; /* focus left  */
        case 'l': tile_focus_dir(1);          break; /* focus right */
        case 'i': tile_focus_dir(2);          break; /* focus up    */
        case 'k': tile_focus_dir(3);          break; /* focus down  */
        case 'J': tile_resize(0, -1);         break; /* shrink ←    */
        case 'L': tile_resize(0, +1);         break; /* grow →      */
        case 'I': tile_resize(1, -1);         break; /* shrink ↑    */
        case 'K': tile_resize(1, +1);         break; /* grow ↓      */
        default: break;
        }
        request_redraw();
#ifndef LOCAL_BUILD
        twm_prompt();
#endif
        return;
    }

    if (k == '/') { uart_slash = 1; return; }

    /* Tab = cycle focus */
    if (k == 0x09) {
        tile_focus_cycle(0);
        request_redraw();
#ifndef LOCAL_BUILD
        twm_prompt();
#endif
        return;
    }

    /* Pass through to PS/2 handler for other keys */
    process_key(k, 0, 1, 0);
}

static int tiling_finish(void) {
    if (!running) { fb_shutdown(); return 1; }
    return 0;
}

/* Program descriptor */

const program_t prog_twm = {
    .name     = "twm",
    .help     = "Tiling WM (Alt+H/V split, Alt+Arrow focus, Alt+W close)",
    .init     = tiling_init,
    .update   = tiling_update,
    .input    = tiling_input,
    .ir_input = NULL,
    .finish   = tiling_finish
};
