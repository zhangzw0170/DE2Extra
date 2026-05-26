/* chroma.c — ChromaShader: 程序化地形沙盒 (C 版本)
 *
 * 世界: 40×25 格, 每格 2 字符宽 = 16×16 像素正方形
 * LOCAL_BUILD: ANSI 24-bit 终端渲染
 * NEORV32:     VGA text terminal via vga_hal.h
 *
 * 编译 (PC):   gcc -DLOCAL_BUILD -Wall -O2 -o chroma chroma.c
 * 编译 (RTOS): 加入 de2shell_rtos makefile
 */

#include <stdint.h>
#include <string.h>

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
#else
  #include "vga_hal.h"
#endif

/* ── 常量 ──────────────────────────────────────────────────────── */

#define WORLD_W  40   /* 格数 (每格 2 字符宽, 屏幕 80 列) */
#define WORLD_H  25
#define WIN_GOLD 10
#define GOLD_HASH 0x5Au  /* magic hash value that spawns gold */

/* ── RGB332 调色板 ─────────────────────────────────────────────── */

#define C_DEEP_BLUE   0x03   /* 深水 */
#define C_LIGHT_BLUE  0x14   /* 浅水 */
#define C_SAND_CLR    0xF5   /* 沙滩 */
#define C_GRASS_CLR   0x39   /* 草地 */
#define C_FOREST_CLR  0x12   /* 森林深绿 */
#define C_MOUNT_CLR   0xA2   /* 山岩 */
#define C_SNOW_CLR    0xFF   /* 雪峰 */
#define C_GOLD_CLR    0xFC   /* 金矿亮黄 */
#define C_WALL_CLR    0x55   /* 围墙灰 */
#define C_PLAYER_CLR  0xFF   /* 玩家标记 */

enum { T_DEEP=0, T_SHALLOW, T_SAND, T_GRASS, T_FOREST, T_MOUNT, T_SNOW };

/* ── 哈希函数 (与 chromashader-spec.md 一致) ──────────────────── */

static uint32_t hash(int wx, int wy, uint32_t seed) {
    uint32_t h = seed ^ ((uint32_t)wx << 7) ^ ((uint32_t)wy << 20);
    h = h ^ (h << 13); h = h ^ (h >> 17); h = h ^ (h << 5);
    h = h ^ ((uint32_t)wy << 3) ^ ((uint32_t)wx << 16);
    h = h ^ (h >> 11); h = h ^ (h << 7);
    return h;
}

/* ── 生物群系 ──────────────────────────────────────────────────── */

typedef struct { uint8_t type, color, left, right; } biome_t;

static const biome_t biome_table[7] = {
    {T_DEEP,    C_DEEP_BLUE,  '~', ' '},
    {T_SHALLOW, C_LIGHT_BLUE, 0xB0, ' '},   /* ░ */
    {T_SAND,    C_SAND_CLR,   0xB0, ' '},   /* ░ */
    {T_GRASS,   C_GRASS_CLR,  0xB1, 0x06},  /* ▒ + ♠ */
    {T_FOREST,  C_FOREST_CLR, 0xB2, 0x1E},  /* ▓ + ▲ */
    {T_MOUNT,   C_MOUNT_CLR,  0x1E, ' '},   /* ▲ */
    {T_SNOW,    C_SNOW_CLR,   0xDB, ' '},   /* █ */
};

/* 草地变体: 用低 2 位 hash 选不同纹理 */
static const uint8_t grass_variants[4][2] = {
    {0xB1, 0x06},  /* ▒♠ */
    {0xB0, 0x05},  /* ░♣ */
    {0xB1, 0x0F},  /* ▒☼ */
    {0xB0, 0x06},  /* ░♠ */
};

/* 森林变体 */
static const uint8_t forest_variants[4][2] = {
    {0xB2, 0x1E},  /* ▓▲ */
    {0xB2, 0x05},  /* ▓♣ */
    {0xB1, 0x1E},  /* ▒▲ */
    {0xB2, 0xB2},  /* ▓▓ */
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

/* ── 格子数据 ──────────────────────────────────────────────────── */

typedef struct {
    uint8_t terrain;
    uint8_t left, right;  /* CP437 字符 */
    uint8_t fg, bg;       /* RGB332 */
    uint8_t has_gold;
    uint8_t modified;
} cell_t;

/* ── 游戏状态 ──────────────────────────────────────────────────── */

static cell_t   world[WORLD_H][WORLD_W];
static uint32_t g_seed;
static int      g_off_x, g_off_y;
static int      g_px, g_py;
static int      g_gold;
static int      g_dirty;
static int      g_px_prev, g_py_prev;  /* previous player position for incremental draw */

/* ── RGB332 → 24-bit ───────────────────────────────────────────── */

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

/* ── 地形生成 ──────────────────────────────────────────────────── */

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

            /* 变体纹理 */
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

/* ── 玩家动作 ──────────────────────────────────────────────────── */

static void collect(void) {
    cell_t *c = &world[g_py][g_px];
    if (c->has_gold) { g_gold++; c->has_gold = 0; c->fg = c->bg; c->modified = 1;
#ifndef LOCAL_BUILD
        /* Incremental redraw */
        uint16_t fg16 = ((uint16_t)c->fg << 8) | c->bg;
        int sx = g_px * 2;
        vga_goto(sx, g_py);   vga_putc((char)c->left, fg16);
        vga_goto(sx+1, g_py); vga_putc((char)c->right, fg16);
#endif
    }
}

static void paint_biome(int t) {
    cell_t *c = &world[g_py][g_px];
    biome_t b = biome_table[t];
    c->terrain  = b.type;
    c->left     = b.left;
    c->right    = b.right;
    c->fg       = b.color;
    c->bg       = b.color;
    c->has_gold = 0;
    c->modified = 1;
#ifndef LOCAL_BUILD
    uint16_t fg16 = ((uint16_t)c->fg << 8) | c->bg;
    int sx = g_px * 2;
    vga_goto(sx, g_py);   vga_putc((char)c->left, fg16);
    vga_goto(sx+1, g_py); vga_putc((char)c->right, fg16);
#endif
}

static void paint_wall(void) {
    cell_t *c = &world[g_py][g_px];
    c->terrain  = T_MOUNT;
    c->left     = 0xDB; c->right = 0xDB;
    c->fg       = C_WALL_CLR; c->bg = C_WALL_CLR;
    c->has_gold = 0; c->modified = 1;
#ifndef LOCAL_BUILD
    uint16_t fg16 = ((uint16_t)c->fg << 8) | c->bg;
    int sx = g_px * 2;
    vga_goto(sx, g_py);   vga_putc((char)c->left, fg16);
    vga_goto(sx+1, g_py); vga_putc((char)c->right, fg16);
#endif
}

static void clear_mods(void) {
    int y, x;
    for (y = 0; y < WORLD_H; y++)
        for (x = 0; x < WORLD_W; x++)
            world[y][x].modified = 0;
    g_dirty = 1;
}

/* ── 移动 ──────────────────────────────────────────────────────── */

static int move_player(int dx, int dy) {
    int nx = g_px + dx, ny = g_py + dy;
    if (nx < 0 || nx >= WORLD_W || ny < 0 || ny >= WORLD_H) return 0;
    g_px = nx; g_py = ny;
    if (dx) { g_off_x += dx; g_dirty = 1; }
    if (dy) { g_off_y += dy; g_dirty = 1; }
    return 1;
}

/* ── 渲染 ──────────────────────────────────────────────────────── */

#ifdef LOCAL_BUILD
/* ANSI 24-bit — 每格 2 字符宽 */

#define BLK_UTF8 "\xE2\x96\x88"
#define BLK_LEN 3

static char g_buf[4096];
static int  g_last_fg = -1, g_last_bg = -1;

static int buf_fg(char *p, int c24) {
    if (c24 == g_last_fg) return 0;
    g_last_fg = c24;
    return sprintf(p, "\033[38;2;%d;%d;%dm",
                   (c24>>16)&0xFF, (c24>>8)&0xFF, c24&0xFF);
}
static int buf_bg(char *p, int c24) {
    if (c24 == g_last_bg) return 0;
    g_last_bg = c24;
    return sprintf(p, "\033[48;2;%d;%d;%dm",
                   (c24>>16)&0xFF, (c24>>8)&0xFF, c24&0xFF);
}

/* CP437 → UTF-8 编码 (仅图形字符 0xB0-0xDF) */
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
                fg24 = rgb24(C_PLAYER_CLR);
                bg24 = rgb24(c->bg);
                ch_left[0] = '['; ch_left[1] = 0;
                ch_right[0] = ']'; ch_right[1] = 0;
            } else if (c->has_gold && c->terrain == T_DEEP) {
                /* 深水中的金矿: 蓝色波浪 + 金色钻石 */
                fg24 = rgb24(c->fg);
                bg24 = rgb24(c->bg);
                ch_left[0] = '~'; ch_left[1] = 0;
                ch_right[0] = 0x04; ch_right[1] = 0;  /* ♦ */
                n = cp437_utf8((uint8_t)ch_right[0], ch_right);
                ch_right[n] = 0;
            } else if (c->has_gold) {
                fg24 = rgb24(C_GOLD_CLR);
                bg24 = rgb24(c->bg);
                n = cp437_utf8(c->left, ch_left);  ch_left[n]  = 0;
                n = cp437_utf8(0x04, ch_right);     ch_right[n] = 0;  /* ♦ */
            } else {
                fg24 = rgb24(c->fg);
                bg24 = rgb24(c->bg);
                n = cp437_utf8(c->left, ch_left);  ch_left[n]  = 0;
                n = cp437_utf8(c->right, ch_right); ch_right[n] = 0;
            }

            pos += buf_fg(g_buf + pos, fg24);
            pos += buf_bg(g_buf + pos, bg24);
            for (char *p = ch_left; *p; p++) g_buf[pos++] = *p;
            for (char *p = ch_right; *p; p++) g_buf[pos++] = *p;
        }
        printf("\033[0m");
        g_last_fg = -1; g_last_bg = -1;
        fwrite(g_buf, 1, (size_t)pos, stdout);
        if (y < WORLD_H - 1) putchar('\n');
    }

    printf("\033[0m\nGold: %d/%d  (%d,%d)  [WASD]move [E]collect [1-3]paint [0]clear [Q]quit",
           g_gold, WIN_GOLD, g_off_x + g_px, g_off_y + g_py);
    if (g_gold >= WIN_GOLD) printf("\n\n  *** YOU WIN! ***");
    fflush(stdout);
}
#else
/* NEORV32 VGA — incremental render */
static void render_full(void) {
    int y, x;
    for (y = 0; y < WORLD_H; y++) {
        for (x = 0; x < WORLD_W; x++) {
            cell_t *c = &world[y][x];
            uint16_t fg16 = ((uint16_t)c->fg << 8) | c->bg;
            int sx = x * 2;
            vga_goto(sx, y);   vga_putc((char)c->left, fg16);
            vga_goto(sx+1, y); vga_putc((char)c->right, fg16);
        }
    }
}

static void render_player(int draw) {
    /* Erase old player position */
    if (g_px_prev != g_px || g_py_prev != g_py) {
        cell_t *old = &world[g_py_prev][g_px_prev];
        uint16_t fg16 = ((uint16_t)old->fg << 8) | old->bg;
        int sx = g_px_prev * 2;
        vga_goto(sx, g_py_prev);   vga_putc((char)old->left, fg16);
        vga_goto(sx+1, g_py_prev); vga_putc((char)old->right, fg16);
    }
    /* Draw new player position */
    if (draw) {
        cell_t *cur = &world[g_py][g_px];
        int sx = g_px * 2;
        vga_goto(sx, g_py);   vga_putc('[', ((uint16_t)C_PLAYER_CLR << 8) | cur->bg);
        vga_goto(sx+1, g_py); vga_putc(']', ((uint16_t)C_PLAYER_CLR << 8) | cur->bg);
    }
    g_px_prev = g_px;
    g_py_prev = g_py;
}

static void render(void) {
    if (g_dirty) {
        render_full();
        g_dirty = 0;
    }
    render_player(1);
}
#endif

/* ── 输入 ──────────────────────────────────────────────────────── */

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

/* ── 终端设置 ──────────────────────────────────────────────────── */

#ifdef LOCAL_BUILD
static void term_setup(void) {
  #ifndef _WIN32
    struct termios t; tcgetattr(0, &t); t.c_lflag &= (tcflag_t)~(ICANON|ECHO); tcsetattr(0, TCSANOW, &t);
  #endif
    printf("\033[2J\033[H\033[?25l");
}
static void term_restore(void) {
    printf("\033[?25h\033[0m");
  #ifndef _WIN32
    struct termios t; tcgetattr(0, &t); t.c_lflag |= (ICANON|ECHO); tcsetattr(0, TCSANOW, &t);
  #endif
}
#endif

static void init(uint32_t seed) {
    g_seed=seed; g_off_x=0; g_off_y=0; g_px=WORLD_W/2; g_py=WORLD_H/2;
    g_px_prev=g_px; g_py_prev=g_py; g_gold=0; g_dirty=1;
    memset(world, 0, sizeof(world));
    generate();
}

/* ── 主循环 (LOCAL_BUILD) ──────────────────────────────────────── */

#ifdef LOCAL_BUILD
int main(void) {
    term_setup();
    init((uint32_t)time(NULL));
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
            case '1': paint_biome(T_GRASS);  break;
            case '2': paint_biome(T_DEEP);   break;
            case '3': paint_wall();          break;
            case '0': clear_mods();          break;
            case 'q': case 'Q': case 3: case 27: goto done;
        }
        if (moved && g_dirty) generate();
        render();
        if (g_gold >= WIN_GOLD) { render(); while (!kbhit()) Sleep(100); getch(); break; }
    }
done:
    term_restore();
    return 0;
}
#endif

/* ── de2shell_rtos 集成 ────────────────────────────────────────── */

#ifdef DE2SHELL_RTOS
#include "vga_hal.h"

static int g_done, g_first;

void chroma_task_init(void) {
    init(0xCAFE1234u); g_done = 0; g_first = 1;
}
void chroma_task_update(void) {
    if (g_first) { vga_clear(); render(); g_first = 0; }
}
void chroma_task_input(char c) {
    if (g_done) return; int moved = 0;
    switch (c) {
        case 'w': case 'W': moved = move_player(0, -1); break;
        case 's': case 'S': moved = move_player(0,  1); break;
        case 'a': case 'A': moved = move_player(-1, 0); break;
        case 'd': case 'D': moved = move_player( 1, 0); break;
        case 'e': case 'E': collect(); break;
        case '1': paint_biome(T_GRASS);  break;
        case '2': paint_biome(T_DEEP);   break;
        case '3': paint_wall();          break;
        case '0': clear_mods();          break;
        case 'q': case 'Q': g_done = 1; return;
    }
    if (moved && g_dirty) generate();
    render();
    if (g_gold >= WIN_GOLD) g_done = 1;
}
int chroma_task_finish(void) { return g_done; }

const program_t prog_chroma = {
    "ChromaShader", "Procedural terrain sandbox",
    chroma_task_init, chroma_task_update, chroma_task_input, NULL, chroma_task_finish
};
#endif
