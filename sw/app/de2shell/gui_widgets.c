/* gui_widgets.c -- Panel content renderers for tiling WM
 *
 * Each leaf node calls panel_render() with its content area.
 * The renderer dispatches based on tile->id.
 * New splits auto-cycle panel type via tile->id assignment in gui.c.
 */
#include "gui.h"
#include "gfx.h"
#include <string.h>

/* ── Panel types ────────────────────────────────────────────────── */

#define PANEL_SHELL   1
#define PANEL_MONITOR 2
#define PANEL_INFO    3
#define PANEL_MAX     3

static int next_panel_id = PANEL_SHELL;

int gui_widgets_next_id(void) {
    int id = next_panel_id;
    next_panel_id = (next_panel_id >= PANEL_MAX) ? PANEL_SHELL : next_panel_id + 1;
    return id;
}

/* ── Helpers ──────────────────────────────────────────────────────── */

static int text_rows(int ch) { return ch / 16; }
static int text_cols(int cw) { return cw / 8; }

static void label(int x, int y, const char *lbl, const char *val,
                  uint8_t lbl_color, uint8_t val_color) {
    gfx_text(x, y, lbl, lbl_color, 0xFF);
    int lx = x + (int)strlen(lbl) * 8;
    gfx_text(lx, y, val, val_color, 0xFF);
}

static void draw_bar(int x, int y, int w, int pct, uint8_t fg, uint8_t bg) {
    if (w < 4) return;
    gfx_fill_rect(x, y, w, 12, bg);
    int fill = (w * pct) / 100;
    if (fill > 0 && pct > 0)
        gfx_fill_rect(x, y, fill < w ? fill : w, 12, fg);
    gfx_rect(x, y, w, 12, FB_DKGRAY);
}

/* ── Shell panel ─────────────────────────────────────────────────── */

static const char *shell_lines[] = {
    "NEORV32 RISC-V DE2Extra Shell",
    "FreeRTOS V11  SDRAM exec",
    "",
    "Available commands:",
    "  hello     LED chaser",
    "  crypto    AES/SHA/SM4 CLI",
    "  ps2       PS/2 keyboard test",
    "  snake     Snake game",
    "  life      Conway's Game of Life",
    "  info      System dashboard",
    "  expdemo   11 course experiments",
    "  twm       Tiling window manager",
    "  stats     Task list + stack HWM",
    "",
    "Key bindings (inside twm):",
    "  Alt+Enter  Auto-split",
    "  Alt+H/V    Force H/V split",
    "  Alt+Arrow  Move focus",
    "  Alt+Shift+Arrow  Resize",
    "  Alt+F      Fullscreen toggle",
    "  Alt+W      Close pane",
    "  Esc        Exit desktop",
};
#define SHELL_LINE_COUNT (sizeof(shell_lines) / sizeof(shell_lines[0]))

static void render_shell(tile_t *t, int cx, int cy, int cw, int ch) {
    (void)t;
    int rows = text_rows(ch);
    int cols = text_cols(cw);
    int max_lines = rows > 1 ? rows - 1 : 0;

    /* Scrollable log */
    int visible = SHELL_LINE_COUNT;
    if (visible > max_lines && max_lines > 0)
        visible = max_lines;

    int start = 0;
    if (SHELL_LINE_COUNT > visible && visible > 0)
        start = SHELL_LINE_COUNT - visible;

    for (int i = 0; i < visible; i++) {
        const char *line = shell_lines[start + i];
        uint8_t color = FB_LTGRAY;
        if (i == 0) color = FB_GREEN;
        else if (line[0] == ' ') color = FB_LTGRAY;
        gfx_text(cx + 4, cy + 2 + i * 16, line, color, 0xFF);
    }

    /* Prompt at bottom */
    if (rows > 0) {
        int py = cy + 2 + max_lines * 16;
        gfx_text(cx + 4, py, "shell > _", FB_GREEN, 0xFF);
    }

    /* Right-side decoration: mini logo */
    if (cw > 300 && ch > 200) {
        int lx = cx + cw - 120;
        int ly = cy + 4;
        gfx_rect(lx, ly, 112, 48, FB_DKGRAY);
        gfx_fill_rect(lx + 1, ly + 1, 110, 46, FB_BLACK);
        gfx_text(lx + 8, ly + 4, "NEORV32", FB_CYAN, 0xFF);
        gfx_text(lx + 8, ly + 20, "RV32IMC", FB_LTGRAY, 0xFF);
        gfx_text(lx + 8, ly + 36, "50 MHz", FB_YELLOW, 0xFF);

        /* Freq bar */
        if (ch > 260) {
            gfx_text(lx, ly + 56, "CPU Load:", FB_GRAY, 0xFF);
            draw_bar(lx, ly + 72, 112, 23, FB_GREEN, (1 << 5) | (1 << 2));
            gfx_text(lx, ly + 88, "Memory:", FB_GRAY, 0xFF);
            draw_bar(lx, ly + 104, 112, 45, FB_CYAN, (1 << 5) | (1 << 2));
        }
    }
    (void)cols;
}

/* ── Monitor panel ──────────────────────────────────────────────── */

static const char *task_names[] = {
    "uart_input", "shell", "active", "status"
};
static const int task_cpu[] = { 8, 12, 35, 3 };
static const int task_stack[] = { 128, 256, 512, 128 };
static const int task_hwm[] = { 45, 82, 210, 18 };
#define TASK_COUNT 4

static void render_monitor(tile_t *t, int cx, int cy, int cw, int ch) {
    (void)t;
    int rows = text_rows(ch);

    /* Title */
    gfx_text(cx + 4, cy + 4, "System Monitor", FB_CYAN, 0xFF);
    gfx_hline(cx + 4, cy + 22, cw - 8, FB_DKGRAY);

    if (rows < 4) return;

    /* Task list header */
    int y = cy + 28;
    gfx_text(cx + 4, y, "TASK", FB_YELLOW, 0xFF);
    gfx_text(cx + 120, y, "CPU", FB_YELLOW, 0xFF);
    gfx_text(cx + 170, y, "STACK", FB_YELLOW, 0xFF);
    gfx_text(cx + 230, y, "HWM", FB_YELLOW, 0xFF);
    y += 18;

    /* Task rows */
    for (int i = 0; i < TASK_COUNT && y + 16 < cy + ch; i++) {
        uint8_t name_c = (i < 2) ? FB_LTGRAY : FB_GREEN;
        gfx_text(cx + 4, y, task_names[i], name_c, 0xFF);

        /* CPU bar inline */
        draw_bar(cx + 110, y + 2, 48, task_cpu[i],
                 task_cpu[i] < 30 ? FB_GREEN : FB_YELLOW,
                 (1 << 5) | (1 << 2));

        /* Stack bar */
        int pct = (task_stack[i] > 0) ? (task_hwm[i] * 100 / task_stack[i]) : 0;
        draw_bar(cx + 170, y + 2, 48, pct,
                 pct < 70 ? FB_GREEN : (pct < 90 ? FB_YELLOW : FB_RED),
                 (1 << 5) | (1 << 2));

        gfx_text(cx + 230, y, "OK", FB_GREEN, 0xFF);
        y += 20;
    }

    y += 8;
    if (y + 40 < cy + ch) {
        gfx_hline(cx + 4, y, cw - 8, FB_DKGRAY);
        y += 8;
        gfx_text(cx + 4, y, "Overall CPU:", FB_LTGRAY, 0xFF);
        draw_bar(cx + 4, y + 18, cw - 8, 18, FB_GREEN, (1 << 5) | (1 << 2));
        y += 38;
        gfx_text(cx + 4, y, "Heap:", FB_LTGRAY, 0xFF);
        draw_bar(cx + 4, y + 18, cw - 8, 42, FB_CYAN, (1 << 5) | (1 << 2));
        y += 38;
        gfx_text(cx + 4, y, "Uptime: 00:42", FB_YELLOW, 0xFF);
    }

    /* Bottom graph area if tall enough */
    if (ch > 350 && cw > 180) {
        int gy = cy + ch - 80;
        gfx_hline(cx + 4, gy, cw - 8, FB_DKGRAY);
        gfx_text(cx + 4, gy + 4, "CPU History", FB_GRAY, 0xFF);

        /* Fake sparkline */
        static const int spark[] = {
            15, 22, 18, 35, 28, 20, 45, 38, 25, 30,
            22, 18, 40, 32, 20, 25, 35, 28, 15, 20
        };
        int gw = cw - 16;
        int gh = 40;
        int gx = cx + 8;
        int g_y = gy + 22;
        gfx_fill_rect(gx, g_y, gw, gh, (1 << 5));
        for (int i = 0; i < 20; i++) {
            int bx = gx + i * gw / 20;
            int bw = gw / 20 - 1;
            int bh = spark[i] * gh / 50;
            uint8_t c = spark[i] > 35 ? FB_RED : (spark[i] > 20 ? FB_YELLOW : FB_GREEN);
            gfx_fill_rect(bx, g_y + gh - bh, bw > 0 ? bw : 1, bh, c);
        }
    }
}

/* ── Info panel ─────────────────────────────────────────────────── */

static void render_info(tile_t *t, int cx, int cy, int cw, int ch) {
    (void)t;
    gfx_text(cx + 4, cy + 4, "System Information", FB_YELLOW, 0xFF);
    gfx_hline(cx + 4, cy + 22, cw - 8, FB_DKGRAY);

    if (text_rows(ch) < 3) return;

    int y = cy + 30;
    int lh = 18;

    /* SoC section */
    gfx_text(cx + 4, y, "[SoC]", FB_CYAN, 0xFF);
    y += lh;
    label(cx + 8, y, "Core:    ", "NEORV32 V1.13.1", FB_GRAY, FB_LTGRAY);
    y += lh;
    label(cx + 8, y, "ISA:     ", "RV32IMC Zicsr Zicntr", FB_GRAY, FB_LTGRAY);
    y += lh;
    label(cx + 8, y, "Freq:    ", "50 MHz", FB_GRAY, FB_LTGRAY);
    y += lh;
    label(cx + 8, y, "XLEN:    ", "32-bit", FB_GRAY, FB_LTGRAY);
    y += lh + 6;

    /* Memory section */
    gfx_text(cx + 4, y, "[Memory]", FB_CYAN, 0xFF);
    y += lh;
    label(cx + 8, y, "IMEM:    ", "64 KB (bootloader)", FB_GRAY, FB_LTGRAY);
    y += lh;
    label(cx + 8, y, "DMEM:    ", "16 KB", FB_GRAY, FB_LTGRAY);
    y += lh;
    label(cx + 8, y, "SDRAM:   ", "128 MB", FB_GRAY, FB_LTGRAY);
    y += lh + 6;

    /* Peripherals */
    gfx_text(cx + 4, y, "[Peripherals]", FB_CYAN, 0xFF);
    y += lh;
    label(cx + 8, y, "VGA:     ", "640x480 60Hz RGB332", FB_GRAY, FB_LTGRAY);
    y += lh;
    label(cx + 8, y, "PS/2:    ", "Keyboard (scancode set 2)", FB_GRAY, FB_LTGRAY);
    y += lh;
    label(cx + 8, y, "LCD:     ", "HD44780 16x2", FB_GRAY, FB_LTGRAY);
    y += lh;
    label(cx + 8, y, "UART:    ", "115200 8N1", FB_GRAY, FB_LTGRAY);
    y += lh + 6;

    /* Board */
    if (y + lh < cy + ch) {
        gfx_text(cx + 4, y, "[Board]", FB_CYAN, 0xFF);
        y += lh;
        label(cx + 8, y, "Board:   ", "Terasic DE2-115", FB_GRAY, FB_LTGRAY);
        y += lh;
        label(cx + 8, y, "FPGA:    ", "Cyclone IV E EP4CE115", FB_GRAY, FB_LTGRAY);
        y += lh;
        label(cx + 8, y, "LEs:     ", "8,125 / 114,480 (7%)", FB_GRAY, FB_LTGRAY);
    }

    /* Right column if wide enough */
    if (cw > 360 && ch > 200) {
        int rx = cx + cw / 2 + 8;
        int ry = cy + 30;

        /* Color palette showcase */
        gfx_text(rx, ry, "[Palette]", FB_CYAN, 0xFF);
        ry += lh;
        uint8_t colors[] = {
            FB_BLACK, FB_RED, FB_GREEN, FB_BLUE,
            FB_YELLOW, FB_CYAN, FB_MAGENTA, FB_WHITE,
            FB_GRAY, FB_DKGRAY, FB_LTGRAY, FB_ORANGE,
            FB_BROWN, FB_TEAL
        };
        const char *cnames[] = {
            "BLACK", "RED", "GREEN", "BLUE",
            "YELLOW", "CYAN", "MAGENTA", "WHITE",
            "GRAY", "DKGRAY", "LTGRAY", "ORANGE",
            "BROWN", "TEAL"
        };
        for (int i = 0; i < 14 && ry + 16 < cy + ch; i++) {
            gfx_fill_rect(rx, ry + 2, 14, 14, colors[i]);
            if (colors[i] == FB_BLACK)
                gfx_rect(rx, ry + 2, 14, 14, FB_DKGRAY);
            gfx_text(rx + 20, ry + 2, cnames[i], FB_LTGRAY, 0xFF);
            ry += 18;
        }

        /* CP437 box drawing demo */
        if (ch > 360) {
            ry += 8;
            gfx_text(rx, ry, "[Box Drawing]", FB_CYAN, 0xFF);
            ry += lh;
            /* Draw a box using CP437 chars directly */
            const char *box_top    = "+--+\n";
            const char *box_mid    = "|  |\n";
            const char *box_bottom = "+--+";
            gfx_text(rx + 4, ry, box_top, FB_LTGRAY, 0xFF);
            gfx_text(rx + 4, ry + 16, box_mid, FB_LTGRAY, 0xFF);
            gfx_text(rx + 4, ry + 32, box_mid, FB_LTGRAY, 0xFF);
            gfx_text(rx + 4, ry + 48, box_bottom, FB_LTGRAY, 0xFF);
        }
    }
}

/* ── Dispatcher ─────────────────────────────────────────────────── */

void panel_render(tile_t *t, int cx, int cy, int cw, int ch) {
    if (!t) return;
    switch (t->id) {
        case PANEL_MONITOR: render_monitor(t, cx, cy, cw, ch); break;
        case PANEL_INFO:    render_info(t, cx, cy, cw, ch);    break;
        default:            render_shell(t, cx, cy, cw, ch);   break;
    }
}
