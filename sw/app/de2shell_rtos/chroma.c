/* chroma.c — ChromaShader: 程序化地形沙盒
 *
 * LOCAL_BUILD: 纯软件 ANSI 24-bit 终端渲染 (gcc -DLOCAL_BUILD)
 * NEORV32/DE2SHELL_RTOS: 硬件 MMIO 驱动 (RTL chroma_shader.vhd 生成地形)
 */

#include <stdint.h>
#include <string.h>

#ifndef LOCAL_BUILD
#include "ps2_decoder.h"
#endif

#ifdef LOCAL_BUILD
  #include <stdio.h>
  #include <stdlib.h>
  #include <time.h>
  #ifdef _WIN32
    #include <conio.h>
    #include <windows.h>
  #else
    #include <termios.h>
    #include <unistd.h>
    #include <sys/select.h>
  #endif
#endif

/* ── 常量 ──────────────────────────────────────────────────────── */

#define WORLD_W  40
#define WORLD_H  25
#define WIN_GOLD 10
#define GOLD_HASH 0x5Au

/* ── RGB332 调色板 ─────────────────────────────────────────────── */

#define C_DEEP_BLUE   0x03
#define C_LIGHT_BLUE  0x14
#define C_SAND_CLR    0xF5
#define C_GRASS_CLR   0x39
#define C_FOREST_CLR  0x12
#define C_MOUNT_CLR   0xA2
#define C_SNOW_CLR    0xFF
#define C_GOLD_CLR    0xFC
#define C_WALL_CLR    0x55
#define C_PLAYER_CLR  0xFF

enum { T_DEEP=0, T_SHALLOW, T_SAND, T_GRASS, T_FOREST, T_MOUNT, T_SNOW };

/* ══════════════════════════════════════════════════════════════════
 *  LOCAL_BUILD — 纯软件实现 (不变)
 * ══════════════════════════════════════════════════════════════════ */

#ifdef LOCAL_BUILD

static uint32_t hash(int wx, int wy, uint32_t seed) {
    uint32_t h = seed ^ ((uint32_t)wx << 7) ^ ((uint32_t)wy << 20);
    h = h ^ (h << 13); h = h ^ (h >> 17); h = h ^ (h << 5);
    h = h ^ ((uint32_t)wy << 3) ^ ((uint32_t)wx << 16);
    h = h ^ (h >> 11); h = h ^ (h << 7);
    return h;
}

typedef struct { uint8_t type, color, left, right; } biome_t;

static const biome_t biome_table[7] = {
    {T_DEEP,    C_DEEP_BLUE,  '~', ' '},
    {T_SHALLOW, C_LIGHT_BLUE, 0xB0, ' '},
    {T_SAND,    C_SAND_CLR,   0xB0, ' '},
    {T_GRASS,   C_GRASS_CLR,  0xB1, 0x06},
    {T_FOREST,  C_FOREST_CLR, 0xB2, 0x1E},
    {T_MOUNT,   C_MOUNT_CLR,  0x1E, ' '},
    {T_SNOW,    C_SNOW_CLR,   0xDB, ' '},
};

static const uint8_t grass_variants[4][2] = {
    {0xB1, 0x06}, {0xB0, 0x05}, {0xB1, 0x0F}, {0xB0, 0x06},
};
static const uint8_t forest_variants[4][2] = {
    {0xB2, 0x1E}, {0xB2, 0x05}, {0xB1, 0x1E}, {0xB2, 0xB2},
};

static biome_t height_to_biome(uint8_t h) {
    if      (h <= 55)  return biome_table[0];
    else if (h <= 75)  return biome_table[1];
    else if (h <= 95)  return biome_table[2];
    else if (h <= 165) return biome_table[3];
    else if (h <= 195) return biome_table[4];
    else if (h <= 225) return biome_table[5];
    else               return biome_table[6];
}

typedef struct {
    uint8_t terrain;
    uint8_t left, right;
    uint8_t fg, bg;
    uint8_t has_gold;
    uint8_t modified;
} cell_t;

static cell_t   world[WORLD_H][WORLD_W];
static uint32_t g_seed;
static int      g_off_x, g_off_y;
static int      g_px, g_py;
static int      g_gold;
static int      g_dirty;

static int rgb24(uint8_t c) {
    int r = ((c >> 5) & 0x7) * 255 / 7;
    int g = ((c >> 2) & 0x7) * 255 / 7;
    int b = ( c       & 0x3) * 255 / 3;
    return (r << 16) | (g << 8) | b;
}
static uint8_t dither_ch(uint8_t v, int d, int max) {
    int x = (int)v + d; if (x < 0) x = 0; if (x > max) x = max; return (uint8_t)x;
}
static uint8_t vary(uint8_t base, uint32_t hb) {
    int ch = hb & 3, delta = (hb & 4) ? 1 : -1;
    int r = (base>>5)&7, g = (base>>2)&7, b = base&3;
    if (ch == 0) r = dither_ch((uint8_t)r, delta, 7);
    if (ch == 1) g = dither_ch((uint8_t)g, delta, 7);
    if (ch == 2) b = dither_ch((uint8_t)b, delta, 3);
    return (uint8_t)((r<<5)|(g<<2)|b);
}

static void generate(void) {
    int y, x;
    for (y = 0; y < WORLD_H; y++) {
        for (x = 0; x < WORLD_W; x++) {
            if (world[y][x].modified) continue;
            uint32_t h  = hash(x + g_off_x, y + g_off_y, g_seed);
            biome_t  b  = height_to_biome((uint8_t)(h & 0xFF));
            uint8_t  cl = vary(b.color, (uint8_t)(h >> 8));
            uint8_t  au = (uint8_t)(h >> 16);
            uint8_t  left  = b.left, right = b.right;
            if (b.type == T_GRASS) {
                int vi = (au >> 4) & 3;
                left = grass_variants[vi][0]; right = grass_variants[vi][1];
            } else if (b.type == T_FOREST) {
                int vi = (au >> 4) & 3;
                left = forest_variants[vi][0]; right = forest_variants[vi][1];
            }
            world[y][x].terrain  = b.type;
            world[y][x].left     = left;
            world[y][x].right    = right;
            world[y][x].fg       = (au == GOLD_HASH) ? C_GOLD_CLR : cl;
            world[y][x].bg       = cl;
            world[y][x].has_gold = (au == GOLD_HASH);
        }
    }
    g_dirty = 0;
}

static void collect(void) {
    cell_t *c = &world[g_py][g_px];
    if (c->has_gold) { g_gold++; c->has_gold = 0; c->fg = c->bg; c->modified = 1; }
}

static void paint_biome(int t) {
    cell_t *c = &world[g_py][g_px];
    biome_t b = biome_table[t];
    c->terrain = b.type; c->left = b.left; c->right = b.right;
    c->fg = b.color; c->bg = b.color;
    c->has_gold = 0; c->modified = 1;
}

static void clear_mods(void) {
    int y, x;
    for (y = 0; y < WORLD_H; y++)
        for (x = 0; x < WORLD_W; x++)
            world[y][x].modified = 0;
    g_dirty = 1;
}

static int move_player(int dx, int dy) {
    int nx = g_px + dx, ny = g_py + dy;
    if (nx < 0 || nx >= WORLD_W || ny < 0 || ny >= WORLD_H) return 0;
    g_px = nx; g_py = ny;
    if (dx) { g_off_x += dx; g_dirty = 1; }
    if (dy) { g_off_y += dy; g_dirty = 1; }
    return 1;
}

static char g_buf[4096];
static int  g_last_fg = -1, g_last_bg = -1;

static int buf_fg(char *p, int c24) {
    if (c24 == g_last_fg) return 0;
    g_last_fg = c24;
    return sprintf(p, "\033[38;2;%d;%d;%dm", (c24>>16)&0xFF, (c24>>8)&0xFF, c24&0xFF);
}
static int buf_bg(char *p, int c24) {
    if (c24 == g_last_bg) return 0;
    g_last_bg = c24;
    return sprintf(p, "\033[48;2;%d;%d;%dm", (c24>>16)&0xFF, (c24>>8)&0xFF, c24&0xFF);
}

static int cp437_utf8(uint8_t c, char *out) {
    if (c < 0x80) { out[0] = (char)c; return 1; }
    out[0] = (char)(0xC0 | (c >> 6));
    out[1] = (char)(0x80 | (c & 0x3F));
    return 2;
}

static void render(void) {
    int y, x, pos;
    for (y = 0; y < WORLD_H; y++) {
        g_last_fg = -1; g_last_bg = -1;
        pos = sprintf(g_buf, "\033[%d;1H", y + 1);
        for (x = 0; x < WORLD_W; x++) {
            cell_t *c = &world[y][x];
            int is_player = (x == g_px && y == g_py);
            int fg24, bg24, n;
            char ch_left[4], ch_right[4];
            if (is_player) {
                fg24 = rgb24(C_PLAYER_CLR); bg24 = rgb24(c->bg);
                ch_left[0] = '['; ch_left[1] = 0;
                ch_right[0] = ']'; ch_right[1] = 0;
            } else if (c->has_gold) {
                fg24 = rgb24(C_GOLD_CLR); bg24 = rgb24(c->bg);
                n = cp437_utf8(c->left, ch_left); ch_left[n] = 0;
                n = cp437_utf8(0x04, ch_right); ch_right[n] = 0;
            } else {
                fg24 = rgb24(c->fg); bg24 = rgb24(c->bg);
                n = cp437_utf8(c->left, ch_left); ch_left[n] = 0;
                n = cp437_utf8(c->right, ch_right); ch_right[n] = 0;
            }
            pos += buf_fg(g_buf + pos, fg24);
            pos += buf_bg(g_buf + pos, bg24);
            for (char *p = ch_left; *p; p++) g_buf[pos++] = *p;
            for (char *p = ch_right; *p; p++) g_buf[pos++] = *p;
        }
        printf("\033[0m"); g_last_fg = -1; g_last_bg = -1;
        fwrite(g_buf, 1, (size_t)pos, stdout);
        if (y < WORLD_H - 1) putchar('\n');
    }
    printf("\033[0m\nGold: %d/%d  (%d,%d)  [WASD]move [E]collect [1-3]paint [0]clear [Q]quit",
           g_gold, WIN_GOLD, g_off_x + g_px, g_off_y + g_py);
    fflush(stdout);
}

#ifndef _WIN32
static int kbhit(void) {
    struct timeval tv = {0,0}; fd_set fds; FD_ZERO(&fds); FD_SET(0, &fds);
    return select(1, &fds, NULL, NULL, &tv) > 0;
}
static int getch(void) {
    char c; return (read(0, &c, 1) == 1) ? (int)(uint8_t)c : -1;
}
#else
#define kbhit _kbhit
#define getch _getch
#endif

int main(void) {
    struct termios t;
    tcgetattr(0, &t); t.c_lflag &= (tcflag_t)~(ICANON|ECHO); tcsetattr(0, TCSANOW, &t);
    printf("\033[2J\033[H\033[?25l");
    g_seed = (uint32_t)time(NULL); g_off_x = 0; g_off_y = 0;
    g_px = WORLD_W/2; g_py = WORLD_H/2; g_gold = 0; g_dirty = 1;
    memset(world, 0, sizeof(world));
    generate();
    render();
    while (g_gold < WIN_GOLD) {
        if (!kbhit()) { Sleep(16); continue; }
        int c = getch(), moved = 0;
        switch (c) {
            case 'w': case 'W': moved = move_player(0, -1); break;
            case 's': case 'S': moved = move_player(0,  1); break;
            case 'a': case 'A': moved = move_player(-1, 0); break;
            case 'd': case 'D': moved = move_player( 1, 0); break;
            case 'e': case 'E': collect(); break;
            case '1': paint_biome(T_GRASS); break;
            case '2': paint_biome(T_DEEP);  break;
            case '3': { cell_t *c2 = &world[g_py][g_px]; c2->terrain=T_MOUNT; c2->left=0xDB; c2->right=0xDB; c2->fg=C_WALL_CLR; c2->bg=C_WALL_CLR; c2->has_gold=0; c2->modified=1; break; }
            case '0': clear_mods(); break;
            case 'q': case 'Q': case 3: case 27: goto done;
        }
        if (moved && g_dirty) generate();
        render();
    }
done:
    printf("\033[?25h\033[0m");
    tcgetattr(0, &t); t.c_lflag |= (ICANON|ECHO); tcsetattr(0, TCSANOW, &t);
    return 0;
}

#else /* ─── NEORV32 / DE2SHELL_RTOS: 硬件 MMIO 驱动 ─── */

#include "vga_hal.h"
#include <stdio.h>

/* ── ChromaShader MMIO registers ───────────────────────────────── */
#define CHROMA_BASE  ((volatile uint32_t *)0xF0014000u)
#define CHROMA_CTRL      0  /* [0]=enable, [1]=force_refresh */
#define CHROMA_SEED      1  /* [31:0] hash seed */
#define CHROMA_OFF_X     2  /* [15:0] signed scroll X */
#define CHROMA_OFF_Y     3  /* [15:0] signed scroll Y */
#define CHROMA_PLAYER_X  4  /* [6:0] col 0-79 */
#define CHROMA_PLAYER_Y  5  /* [4:0] row 0-24 */
#define CHROMA_CELL      6  /* R: [2:0]=type, [3]=gold, [11:4]=fg, [19:12]=bg */
#define CHROMA_PAINT     7  /* W: [2:0]=type, [7]=gold, [15:8]=fg, [23:16]=bg */
#define CHROMA_STATUS    8  /* R: [0]=busy, [1]=frame_ready */

/* Terrain region: rows 2-26 (80 cols), HUD rows 0-1 header, 27-29 footer */
#define TERRAIN_COLS 80
#define TERRAIN_ROWS 25
#define HUD_HEADER_ROWS 2
#define HUD_FOOTER_ROWS 3  /* rows 27-29 */

static int g_done;
static int g_gold;
static int g_px, g_py;    /* player position within terrain (0-79, 0-24) */
static int g_off_x, g_off_y;

/* ── HUD helpers ──────────────────────────────────────────────── */

static void hud_write(int row, int col, const char *s, uint16_t fg) {
    vga_goto(col, row);
    while (*s) { vga_putc(*s++, fg); }
}

static void hud_header(void) {
    /* Row 0: title */
    hud_write(0, 0, "ChromaShader HW -- Procedural Terrain", 0xFFFF);
    /* Row 1: controls help */
    hud_write(1, 0, "[WASD]move [E]collect [1-3]paint [Q]quit", 0x07FF);
}

static void hud_footer(void) {
    char buf[80];
    int n;
    /* Row 27: score + position */
    n = sprintf(buf, "Gold: %d/%d  Pos: (%d,%d)  World: (%d,%d)",
                g_gold, WIN_GOLD, g_px, g_py, g_off_x + g_px, g_off_y + g_py);
    /* Pad to clear line */
    for (int i = n; i < TERRAIN_COLS; i++) buf[i] = ' ';
    buf[TERRAIN_COLS] = 0;
    hud_write(27, 0, buf, 0xFFFF);

    /* Row 28: border line */
    for (int i = 0; i < TERRAIN_COLS; i++) buf[i] = 0xCD;  /* ═ */
    buf[TERRAIN_COLS] = 0;
    hud_write(28, 0, buf, 0x07FF);

    /* Row 29 is system status bar — don't touch */
}

/* ── Borders ──────────────────────────────────────────────────── */

static void draw_borders(void) {
    /* Top border (row 1 already has help text, draw ═ on row 1 after help? No:
       Plan says "only draw top and bottom borders". Row 1 is HUD. Let's draw
       a separator between header and terrain. */
    char buf[80];
    for (int i = 0; i < TERRAIN_COLS; i++) buf[i] = 0xCD;  /* ═ */
    buf[TERRAIN_COLS] = 0;
    /* Top border: row 1 separator (after help text). Actually row 1 has help text,
       so the border is the bottom of the header region. We'll draw on row 1 at
       end after help text. Better: draw top border on row 1 cols 0-79. But we
       already wrote help there. Let's skip top border since header text serves
       as visual separator. Bottom border is row 27 (which is in footer). */
}

/* ── MMIO helpers ─────────────────────────────────────────────── */

static inline void chroma_write(int reg, uint32_t val) {
    CHROMA_BASE[reg] = val;
}
static inline uint32_t chroma_read(int reg) {
    return CHROMA_BASE[reg];
}

static void refresh_terrain(void) {
    chroma_write(CHROMA_OFF_X, (uint32_t)(int16_t)g_off_x);
    chroma_write(CHROMA_OFF_Y, (uint32_t)(int16_t)g_off_y);
    chroma_write(CHROMA_CTRL, 0x03);  /* enable + force_refresh */
}

static void update_player_hw(void) {
    chroma_write(CHROMA_PLAYER_X, (uint32_t)g_px);
    chroma_write(CHROMA_PLAYER_Y, (uint32_t)g_py);
}

/* ── program_t callbacks ──────────────────────────────────────── */

static void chroma_task_init(void) {
    g_done = 0;
    g_gold = 0;
    g_px = 40;
    g_py = 12;
    g_off_x = 0;
    g_off_y = 0;

    vga_clear();

    /* Draw HUD */
    hud_header();

    /* Configure HW ChromaShader */
    chroma_write(CHROMA_SEED, 0xCAFE1234u);
    chroma_write(CHROMA_OFF_X, 0);
    chroma_write(CHROMA_OFF_Y, 0);
    update_player_hw();
    /* Enable + force_refresh to generate initial terrain */
    chroma_write(CHROMA_CTRL, 0x03);

    /* Draw borders and footer */
    hud_footer();

    /* Wait for terrain ready (optional, FSM completes in ~40us) */
    /* Don't busy-wait, just let it render on next vblank */
}

static void chroma_task_update(void) {
    /* Nothing to poll — HW renders terrain automatically */
}

static void chroma_task_input(char c) {
    if (g_done) return;

    int dx = 0, dy = 0;
    switch ((uint8_t)c) {
        case 'w': case 'W': dy = -1; break;
        case 's': case 'S': dy =  1; break;
        case 'a': case 'A': dx = -1; break;
        case 'd': case 'D': dx =  1; break;
#ifndef LOCAL_BUILD
        case PS2_VK_UP:    dy = -1; break;
        case PS2_VK_DOWN:  dy =  1; break;
        case PS2_VK_LEFT:  dx = -1; break;
        case PS2_VK_RIGHT: dx =  1; break;
#endif
        case 'e': case 'E': {
            /* Read CELL at player position */
            uint32_t cell = chroma_read(CHROMA_CELL);
            if (cell & 0x08) {  /* has_gold */
                g_gold++;
                /* Clear gold via PAINT: keep terrain, clear gold flag */
                chroma_write(CHROMA_PAINT,
                    (cell & 0x07) |           /* terrain type */
                    (((cell >> 4) & 0xFF) << 8));  /* fg as both fg and bg */
            }
            break;
        }
        case '1': {
            /* Paint grass at player pos */
            uint32_t cell = chroma_read(CHROMA_CELL);
            chroma_write(CHROMA_PAINT,
                T_GRASS | ((uint32_t)C_GRASS_CLR << 8) | ((uint32_t)C_GRASS_CLR << 16));
            break;
        }
        case '2': {
            /* Paint deep water at player pos */
            chroma_write(CHROMA_PAINT,
                T_DEEP | ((uint32_t)C_DEEP_BLUE << 8) | ((uint32_t)C_DEEP_BLUE << 16));
            break;
        }
        case '3': {
            /* Paint wall at player pos */
            chroma_write(CHROMA_PAINT,
                T_MOUNT | ((uint32_t)C_WALL_CLR << 8) | ((uint32_t)C_WALL_CLR << 16));
            break;
        }
        case PS2_VK_F10:
            g_done = 1;
            /* Disable ChromaShader */
            chroma_write(CHROMA_CTRL, 0x00);
            return;
        default: return;
    }

    /* Move player */
    if (dx || dy) {
        int nx = g_px + dx, ny = g_py + dy;
        if (nx >= 0 && nx < TERRAIN_COLS && ny >= 0 && ny < TERRAIN_ROWS) {
            g_px = nx;
            g_py = ny;
            g_off_x += dx;
            g_off_y += dy;
            update_player_hw();
            refresh_terrain();
        }
    }

    hud_footer();

    if (g_gold >= WIN_GOLD) {
        g_done = 1;
        hud_write(27, 0, "*** YOU WIN! Press any key to exit ***", 0xFFE0);
    }
}

static int chroma_task_finish(void) {
    return g_done;
}

const program_t prog_chroma = {
    "ChromaShader", "HW terrain sandbox (WASD/E/1-3/Q)",
    chroma_task_init, chroma_task_update, chroma_task_input, NULL, chroma_task_finish
};

#endif /* LOCAL_BUILD / NEORV32 */
