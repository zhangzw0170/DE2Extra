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

/* Helpers */

#ifndef LOCAL_BUILD
static void uart_hex32(uint32_t value) {
    static const char hex[] = "0123456789ABCDEF";
    int shift;
    for (shift = 28; shift >= 0; shift -= 4) {
        neorv32_uart0_putc(hex[(value >> shift) & 0x0f]);
    }
}

static void twm_dump_px_regs(void) {
    neorv32_uart0_puts("TWM: px regs ");
    uart_hex32(VGA_MMIO_BASE[VGA_PX_MODE_REG]);
    neorv32_uart0_putc(' ');
    uart_hex32(VGA_MMIO_BASE[VGA_PX_FB_BASE_REG]);
    neorv32_uart0_putc(' ');
    uart_hex32(VGA_MMIO_BASE[VGA_PX_STATUS_REG]);
    neorv32_uart0_putc('\n');

    neorv32_uart0_puts("TWM: px dbg  ");
    uart_hex32(VGA_MMIO_BASE[VGA_PX_DEBUG0_REG]);
    neorv32_uart0_putc(' ');
    uart_hex32(VGA_MMIO_BASE[VGA_PX_DEBUG1_REG]);
    neorv32_uart0_putc(' ');
    uart_hex32(VGA_MMIO_BASE[VGA_PX_DEBUG2_REG]);
    neorv32_uart0_putc(' ');
    uart_hex32(VGA_MMIO_BASE[VGA_PX_DEBUG3_REG]);
    neorv32_uart0_putc('\n');

    neorv32_uart0_puts("TWM: px samp ");
    uart_hex32(VGA_MMIO_BASE[VGA_PX_SAMPLE0_REG]);
    neorv32_uart0_putc(' ');
    uart_hex32(VGA_MMIO_BASE[VGA_PX_SAMPLE1_REG]);
    neorv32_uart0_putc(' ');
    uart_hex32(VGA_MMIO_BASE[VGA_PX_SAMPLE2_REG]);
    neorv32_uart0_putc(' ');
    uart_hex32(VGA_MMIO_BASE[VGA_PX_SAMPLE3_REG]);
    neorv32_uart0_putc('\n');
}
#endif

static int is_alt(uint8_t sc) {
    return sc == SC_ALT || sc == SC_ALT_BRK;
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
            return;
        case 'v': case 'V':
            tile_split(TILE_SPLIT_V);
            return;
        case 'f': case 'F':
            tile_toggle_fullscreen();
            return;
        case 'q': case 'Q':
            tile_close();
            return;
        case 'w': case 'W':
            tile_close();
            return;
        case '\r': {
            tile_t *t = tile_focused();
            if (t) tile_split(t->w >= t->h ? TILE_SPLIT_H : TILE_SPLIT_V);
            return;
        }
        case '\t':
            tile_focus_cycle(shift);
            return;
        }

        /* Arrow keys */
        if (is_extended) {
            if (shift) {
                /* Alt+Shift+Arrow -- resize */
                switch (scancode) {
                case 0x6b: tile_resize(0, -1); return;
                case 0x74: tile_resize(0, +1); return;
                case 0x75: tile_resize(1, -1); return;
                case 0x72: tile_resize(1, +1); return;
                }
            } else {
                switch (scancode) {
                case 0x6b: tile_focus_dir(0); return;
                case 0x74: tile_focus_dir(1); return;
                case 0x75: tile_focus_dir(2); return;
                case 0x72: tile_focus_dir(3); return;
                }
            }
        }
    }

    /* Tab without Alt -- cycle focus */
    if (ascii == 0x09 && !alt_held) {
        tile_focus_cycle(shift);
        return;
    }
}

/* Program interface */

static void tiling_init(void) {
    fb_init();
    fb_set_debug_pattern(0);
#ifndef LOCAL_BUILD
    neorv32_uart0_puts("TWM: framebuffer init\n");
    twm_dump_px_regs();
#endif
    ps2_dec_init();
    tile_init();
    tile_set_panel_render(panel_render);
    tile_layout();
    tile_render_all();
    running = 1;
    alt_held = 0;
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

    tile_layout();
    tile_render_all();
}

static void tiling_input(char c) {
    process_key((uint8_t)c, 0, 1, 0);
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
