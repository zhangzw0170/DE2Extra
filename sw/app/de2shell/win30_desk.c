/* win30_desk.c — Windows 3.0-style desktop for DE2Extra
 *
 * Desktop composition: teal background, icon grid, taskbar, demo windows.
 * Keyboard-driven: Tab cycles focus, Enter activates, Escape closes.
 * F10 opens "Start Menu" (just highlights taskbar for now).
 *
 * LOCAL_BUILD: SDL2 keyboard input.
 * NEORV32: PS/2 scancode polling at 0xF0002000.
 */
#include "vga_hal.h"
#include "fb_hal.h"
#include "gfx.h"
#include "gui.h"
#include "ps2_decoder.h"
#include <string.h>

#ifdef LOCAL_BUILD
  #include <stdio.h>
  #include <conio.h>
#else
  #include <neorv32.h>
#endif

/* ── Desktop state ──────────────────────────────────────────────── */

static widget_t *desk_taskbar;
static widget_t *desk_win_calc;
static widget_t *desk_win_about;
static widget_t *desk_icons[9];
static widget_t *desk_btn_ok;
static widget_t *desk_lbl_about;
static int desk_running;

/* ── Icon definitions ───────────────────────────────────────────── */

static const char *icon_names[] = {
    "Snake", "Life", "Crypto", "Info",
    "Dash",  "PS/2", "Demo",   "MemTest",
    "Settings"
};

#define ICON_GRID_X    16
#define ICON_GRID_Y    16
#define ICON_COLS       3
#define ICON_SPACING_X  80
#define ICON_SPACING_Y  72

/* ── Program interface callbacks ────────────────────────────────── */

static void win30_init(void) {
    fb_init();
    ps2_dec_init();
    gui_init();
    desk_running = 1;

    /* Desktop background: Win 3.1 deep teal */
    gfx_clear(FB_TEAL);

    /* Taskbar */
    desk_taskbar = gui_create(WIDGET_TASKBAR, 0, FB_H - 24, FB_W, 24, NULL, NULL);

    /* Icon grid: 3 columns × 3 rows */
    for (int i = 0; i < 9; i++) {
        int col = i % ICON_COLS;
        int row = i / ICON_COLS;
        int ix = ICON_GRID_X + col * ICON_SPACING_X;
        int iy = ICON_GRID_Y + row * ICON_SPACING_Y;
        desk_icons[i] = gui_create(WIDGET_ICON, ix, iy, 32, 32, icon_names[i], NULL);
    }

    /* Demo window 1: "Calculator" */
    desk_win_calc = gui_create(WIDGET_WINDOW, 200, 40, 240, 200, "Calculator", NULL);
    /* Calculator buttons inside the window */
    gui_create(WIDGET_LABEL, 210, 68, 0, 0, "DE2Extra Calc", desk_win_calc);
    gui_create(WIDGET_BUTTON, 210, 88, 96, 24, "7", desk_win_calc);
    gui_create(WIDGET_BUTTON, 312, 88, 96, 24, "8", desk_win_calc);
    gui_create(WIDGET_BUTTON, 210, 118, 96, 24, "4", desk_win_calc);
    gui_create(WIDGET_BUTTON, 312, 118, 96, 24, "5", desk_win_calc);
    gui_create(WIDGET_BUTTON, 210, 148, 96, 24, "1", desk_win_calc);
    gui_create(WIDGET_BUTTON, 312, 148, 96, 24, "2", desk_win_calc);

    /* Demo window 2: "About" */
    desk_win_about = gui_create(WIDGET_WINDOW, 280, 180, 280, 160, "About DE2Extra", NULL);
    desk_lbl_about = gui_create(WIDGET_LABEL, 292, 208, 0, 0,
        "DE2Extra Shell v0.2\nNEORV32 RISC-V SoC\nDE2-115 Cyclone IV E", desk_win_about);
    (void)desk_lbl_about;
    desk_btn_ok = gui_create(WIDGET_BUTTON, 380, 290, 80, 24, "OK", desk_win_about);
    (void)desk_btn_ok;

    /* Initial focus */
    gui_focus_next();

    /* Render */
    gui_render_all();
    fb_present();
}

static void process_key(const gui_event_t *ev) {
    if (!ev->is_press) return;

    /* Global hotkeys */
    if (ev->ascii == 0x09) {
        /* Tab — cycle focus */
        if (ps2_dec_shift()) gui_focus_prev();
        else                 gui_focus_next();
        return;
    }
    if (ev->ascii == 0x1b) {
        /* Escape — exit desktop */
        desk_running = 0;
        return;
    }

    /* Dispatch to focused widget */
    if (!gui_dispatch_key(ev)) {
        /* If not consumed, try global shortcuts */
    }
}

static void win30_update(void) {
    /* Poll for keyboard input */
#ifdef LOCAL_BUILD
    while (_kbhit()) {
        int raw = _getch();
        /* LOCAL_BUILD: raw is already ASCII, synthesize a key event */
        gui_event_t ev;
        ev.ascii = (uint8_t)raw;
        ev.scancode = 0;
        ev.is_press = 1;
        ev.is_extended = 0;

        /* Handle special keys from _getch */
        if (raw == 0 || raw == 0xe0) {
            /* Extended key — read the actual code */
            raw = _getch();
            ev.ascii = 0;
            ev.is_extended = 1;
            if (raw == 'H') ev.scancode = 0x75;      /* Up */
            else if (raw == 'P') ev.scancode = 0x72;  /* Down */
            else if (raw == 'K') ev.scancode = 0x6b;  /* Left */
            else if (raw == 'M') ev.scancode = 0x74;  /* Right */
            else if (raw == 'I') ev.scancode = 0x69;  /* End-ish (PageUp) */
            else if (raw == 'G') ev.scancode = 0x6c;  /* Home-ish */
            else if (raw == 'S') ev.scancode = 0x71;  /* Delete */
            else { ev.scancode = (uint8_t)raw; }
        }

        process_key(&ev);
    }
#else
    /* NEORV32: poll PS/2 hardware */
    volatile uint32_t *ps2_base = (volatile uint32_t *)0xF0002000u;
    uint32_t status = ps2_base[1];
    while (status & 0x01u) {
        uint8_t scancode = (uint8_t)ps2_base[0];
        ps2_key_t key;
        if (ps2_dec_feed(scancode, &key)) {
            gui_event_t ev;
            ev.ascii = key.ascii;
            ev.scancode = key.scancode;
            ev.is_press = key.is_press;
            ev.is_extended = key.is_extended;
            process_key(&ev);
        }
        status = ps2_base[1];
    }
#endif

    /* Re-render */
    gfx_clear(FB_TEAL);
    gui_render_all();
    fb_present();
}

static void win30_input(char c) {
    (void)c; /* all input handled in update() via PS/2 poll */
}

static int win30_finish(void) {
    if (!desk_running) {
        fb_shutdown();
        return 1;
    }
    return 0;
}

/* ── Public program descriptor ──────────────────────────────────── */

const program_t prog_win30 = {
    .name     = "Win30",
    .help     = "Windows 3.0 desktop GUI",
    .init     = win30_init,
    .update   = win30_update,
    .input    = win30_input,
    .ir_input = NULL,
    .finish   = win30_finish
};
