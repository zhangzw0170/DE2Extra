/* crypto_viz.c — AES-128 and SHA-256 step-through visualization */
#include "crypto_viz.h"
#include "fb_hal.h"
#include "gfx.h"
#include "crypto.h"
#include "vga_hal.h"
#include <string.h>
#include <stdio.h>

#ifdef LOCAL_BUILD
#include <SDL.h>
#endif

/* ── Color scheme ───────────────────────────────────────────────── */
#define CV_BG   FB_TEAL
#define CV_ACT  FB_GREEN
#define CV_DONE FB_ORANGE
#define CV_WAIT FB_DKGRAY
#define CV_CHG  FB_YELLOW
#define CV_TXT  FB_WHITE
#define CV_DIM  FB_LTGRAY
#define CV_ARR  FB_YELLOW

/* ── Hex decode (self-contained for both LOCAL_BUILD and NEORV32) ─ */
static int cv_hex(const char *s, uint8_t *out, int max) {
    int n = 0;
    while (s[0] && s[1] && n < max) {
        int h = -1, l = -1; char c;
        c = s[0];
        if (c>='0'&&c<='9') h=c-'0'; else if (c>='a'&&c<='f') h=c-'a'+10;
        else if (c>='A'&&c<='F') h=c-'A'+10;
        c = s[1];
        if (c>='0'&&c<='9') l=c-'0'; else if (c>='a'&&c<='f') l=c-'a'+10;
        else if (c>='A'&&c<='F') l=c-'A'+10;
        if (h<0||l<0) break;
        out[n++] = (uint8_t)((h<<4)|l);
        s += 2;
    }
    return n;
}

/* ── Global args (set before init, consumed by cv_init) ─────────── */
static char g_arg_algo[16];
static char g_arg_a1[128];
static char g_arg_a2[128];

void crypto_viz_set_args(const char *algo, const char *a1, const char *a2) {
    int i;
    for (i = 0; algo[i] && i < 15; i++) g_arg_algo[i] = algo[i];
    g_arg_algo[i] = '\0';
    for (i = 0; a1 && a1[i] && i < 127; i++) g_arg_a1[i] = a1[i];
    g_arg_a1[i] = '\0';
    for (i = 0; a2 && a2[i] && i < 127; i++) g_arg_a2[i] = a2[i];
    g_arg_a2[i] = '\0';
}

/* ═══════════════════════════════════════════════════════════════════
 * AES-128
 * ═══════════════════════════════════════════════════════════════════ */

typedef struct {
    uint8_t snap[41][16];
    uint32_t rk[44];
    int step, max_step, auto_play;
    uint8_t key[16], input[16], output[16];
} aes_t;

static void aes_precompute(aes_t *s, const uint8_t key[16], const uint8_t pt[16]) {
    memcpy(s->key, key, 16);
    memcpy(s->input, pt, 16);
    aes128_key_expand(key, s->rk);
    uint8_t st[16]; memcpy(st, pt, 16);
    int si = 0;
    memcpy(s->snap[si++], st, 16);
    aes_add_round_key(st, &s->rk[0]);
    memcpy(s->snap[si++], st, 16);
    for (int r = 1; r <= 9; r++) {
        aes_sub_bytes(st);   memcpy(s->snap[si++], st, 16);
        aes_shift_rows(st);  memcpy(s->snap[si++], st, 16);
        aes_mix_columns(st); memcpy(s->snap[si++], st, 16);
        aes_add_round_key(st, &s->rk[r*4]);
        memcpy(s->snap[si++], st, 16);
    }
    aes_sub_bytes(st);   memcpy(s->snap[si++], st, 16);
    aes_shift_rows(st);  memcpy(s->snap[si++], st, 16);
    aes_add_round_key(st, &s->rk[40]);
    memcpy(s->snap[si++], st, 16);
    memcpy(s->output, st, 16);
    s->max_step = si - 1;
    s->step = 0; s->auto_play = 0;
}

static void aes_map(int step, int *rnd, int *sub) {
    if (step <= 1) { *rnd = 0; *sub = step; return; }
    if (step >= 38) { *rnd = 10; *sub = step - 38; return; }
    *rnd = (step - 2) / 4 + 1;
    *sub = (step - 2) % 4;
}

static const char *op_name[4] = {"SubBytes","ShiftRows","MixColumns","AddRoundKey"};

static void aes_draw(aes_t *s) {
    char buf[80];
    gfx_clear(CV_BG);

    gfx_text(8, 4, "AES-128 Encryption", CV_TXT, 0xFF);

    int p = 0;
    p += sprintf(buf+p, "Key: ");
    for (int i = 0; i < 16; i++) p += sprintf(buf+p, "%02X", s->key[i]);
    gfx_text(8, 24, buf, CV_DIM, 0xFF);
    p = 0;
    p += sprintf(buf+p, "PT:  ");
    for (int i = 0; i < 16; i++) p += sprintf(buf+p, "%02X", s->input[i]);
    gfx_text(8, 40, buf, CV_DIM, 0xFF);

    int rnd, sub;
    aes_map(s->step, &rnd, &sub);

    if (rnd == 0) {
        sprintf(buf, "Initial Round");
        gfx_text(30, 58, buf, CV_TXT, 0xFF);
        uint8_t col = (s->step == 0) ? CV_WAIT : CV_ACT;
        gfx_rounded_rect(220, 56, 180, 28, 4, col);
        gfx_text(254, 62, "AddRoundKey", CV_TXT, 0xFF);
    } else {
        sprintf(buf, "Round %d / 10%s", rnd, rnd==10?" (final)":"");
        gfx_text(30, 58, buf, CV_TXT, 0xFF);
        int bw = 130, bh = 28, gap = 18;
        for (int i = 0; i < 4; i++) {
            int bx = 30 + i * (bw + gap);
            uint8_t col;
            if (rnd == 10 && i == 2)       col = 0x24;
            else if (i < sub)               col = CV_DONE;
            else if (i == sub)              col = CV_ACT;
            else                            col = CV_WAIT;
            gfx_rounded_rect(bx, 74, bw, bh, 4, col);
            int tx = bx + (bw - (int)strlen(op_name[i])*8) / 2;
            gfx_text(tx, 80, op_name[i], CV_TXT, 0xFF);
            if (i < 3)
                gfx_arrow(bx+bw+2, 88, bx+bw+gap-2, 88, CV_ARR);
        }
    }

    int mx = 20, my = 120, cw = 30, ch = 22;
    gfx_text(mx, my-14, "State:", CV_TXT, 0xFF);
    uint8_t *cur = s->snap[s->step];
    uint8_t *prv = (s->step > 0) ? s->snap[s->step-1] : s->snap[0];
    for (int r = 0; r < 4; r++) {
        for (int c = 0; c < 4; c++) {
            int idx = c*4+r;
            int cx = mx + c*(cw+2), cy = my + r*(ch+2);
            uint8_t bg = (s->step > 0 && cur[idx] != prv[idx]) ? CV_CHG : CV_WAIT;
            gfx_fill_rect(cx, cy, cw, ch, bg);
            gfx_rect(cx, cy, cw, ch, CV_DIM);
            sprintf(buf, "%02X", cur[idx]);
            gfx_text(cx+7, cy+3, buf, CV_TXT, 0xFF);
        }
    }

    int rkx = mx + 4*(cw+2) + 30;
    int show_r = (rnd == 0) ? 0 : rnd;
    gfx_text(rkx, my-14, "Round Key:", CV_TXT, 0xFF);
    uint32_t *rk = &s->rk[show_r * 4];
    for (int r = 0; r < 4; r++) {
        for (int c = 0; c < 4; c++) {
            uint8_t bv = (rk[c] >> (24 - r*8)) & 0xFF;
            int cx = rkx + c*(cw+2), cy = my + r*(ch+2);
            gfx_fill_rect(cx, cy, cw, ch, FB_BLUE);
            gfx_rect(cx, cy, cw, ch, CV_DIM);
            sprintf(buf, "%02X", bv);
            gfx_text(cx+7, cy+3, buf, CV_TXT, 0xFF);
        }
    }

    if (s->step >= s->max_step) {
        p = 0;
        p += sprintf(buf+p, "CT: ");
        for (int i = 0; i < 16; i++) p += sprintf(buf+p, "%02X", s->output[i]);
        gfx_text(mx, my + 4*(ch+2)+8, buf, CV_ACT, 0xFF);
    }

    gfx_text(8, 340, "Progress:", CV_DIM, 0xFF);
    gfx_progress_bar(80, 340, 480, 12, s->step, s->max_step, CV_ACT, CV_WAIT);
    sprintf(buf, "%d/%d", s->step, s->max_step);
    gfx_text(570, 340, buf, CV_DIM, 0xFF);

    gfx_text(8, 400, "Space:Step  A:Auto  P:Pause  Left/Right:Skip  Q:Quit",
             CV_DIM, 0xFF);
    if (s->auto_play) gfx_text(540, 400, "[PLAY]", CV_ACT, 0xFF);

    fb_present();
}

/* ═══════════════════════════════════════════════════════════════════
 * SHA-256
 * ═══════════════════════════════════════════════════════════════════ */

typedef struct {
    uint32_t wh[65][8];
    uint32_t w[64];
    uint32_t init[8];
    int step, auto_play;
    uint8_t digest[32];
} sha_t;

static void sha_precompute(sha_t *s, const uint8_t *msg, int mlen) {
    uint8_t blk[64];
    memset(blk, 0, 64);
    memcpy(blk, msg, mlen < 56 ? mlen : 56);
    blk[mlen] = 0x80;
    uint64_t bits = (uint64_t)mlen * 8;
    for (int i = 0; i < 8; i++) blk[56+i] = (bits >> (56-i*8)) & 0xFF;
    sha256_prepare_w(blk, s->w);

    s->init[0]=0x6a09e667; s->init[1]=0xbb67ae85;
    s->init[2]=0x3c6ef372; s->init[3]=0xa54ff53a;
    s->init[4]=0x510e527f; s->init[5]=0x9b05688c;
    s->init[6]=0x1f83d9ab; s->init[7]=0x5be0cd19;
    memcpy(s->wh[0], s->init, 32);

    uint32_t wk[8]; memcpy(wk, s->init, 32);
    for (int t = 0; t < 64; t++) {
        sha256_round(s->w, wk, t);
        memcpy(s->wh[t+1], wk, 32);
    }
    uint32_t ds[8];
    for (int i = 0; i < 8; i++) ds[i] = s->init[i] + wk[i];
    for (int i = 0; i < 8; i++) {
        s->digest[i*4]   = (ds[i]>>24)&0xFF; s->digest[i*4+1] = (ds[i]>>16)&0xFF;
        s->digest[i*4+2] = (ds[i]>> 8)&0xFF; s->digest[i*4+3] =  ds[i]     &0xFF;
    }
    s->step = 0; s->auto_play = 0;
}

static void sha_draw(sha_t *s) {
    char buf[80];
    gfx_clear(CV_BG);

    gfx_text(8, 4, "SHA-256 Compression Function", CV_TXT, 0xFF);
    sprintf(buf, "Round %d / 64", s->step);
    gfx_text(8, 28, buf, CV_TXT, 0xFF);

    const char *vn[8] = {"a","b","c","d","e","f","g","h"};
    for (int row = 0; row < 2; row++) {
        for (int col = 0; col < 4; col++) {
            int i = row*4+col;
            int bx = 8 + col*155, by = 56 + row*50;
            uint32_t cv = s->wh[s->step][i];
            uint32_t pv = (s->step > 0) ? s->wh[s->step-1][i] : s->init[i];
            uint8_t bg = (cv != pv) ? CV_CHG : CV_WAIT;
            gfx_rounded_rect(bx, by, 148, 40, 4, bg);
            sprintf(buf, "%s=%08X", vn[i], cv);
            gfx_text(bx+6, by+12, buf, CV_TXT, 0xFF);
        }
    }

    int wy = 170;
    gfx_text(8, wy, "Message Schedule:", CV_TXT, 0xFF);
    for (int i = 0; i < 8; i++) {
        int t = s->step - 3 + i;
        int bx = 8 + i*78, by = wy+18;
        if (t < 0 || t >= 64) { gfx_fill_rect(bx,by,74,20,CV_WAIT); continue; }
        uint8_t bg = (i==3) ? CV_ACT : CV_WAIT;
        gfx_fill_rect(bx, by, 74, 20, bg);
        sprintf(buf, "W[%d]", t);
        gfx_text(bx+4, by+2, buf, (i==3)?0:CV_TXT, 0xFF);
    }
    if (s->step < 64) {
        sprintf(buf, "W[%d] = 0x%08X", s->step, s->w[s->step]);
        gfx_text(8, wy+44, buf, CV_TXT, 0xFF);
    }

    if (s->step >= 64) {
        gfx_text(8, 260, "Digest:", CV_ACT, 0xFF);
        int p = 0;
        for (int i = 0; i < 32; i++) p += sprintf(buf+p, "%02x", s->digest[i]);
        gfx_text(8, 278, buf, CV_ACT, 0xFF);
    }

    gfx_text(8, 340, "Progress:", CV_DIM, 0xFF);
    gfx_progress_bar(80, 340, 480, 12, s->step, 64, CV_ACT, CV_WAIT);
    sprintf(buf, "%d/64", s->step);
    gfx_text(570, 340, buf, CV_DIM, 0xFF);

    gfx_text(8, 400, "Space:Step  A:Auto  P:Pause  Left/Right:Skip  Q:Quit",
             CV_DIM, 0xFF);
    if (s->auto_play) gfx_text(540, 400, "[PLAY]", CV_ACT, 0xFF);

    fb_present();
}

/* ═══════════════════════════════════════════════════════════════════
 * Program interface (program_t callbacks)
 * ═══════════════════════════════════════════════════════════════════ */

enum { CV_NONE = 0, CV_AES = 1, CV_SHA = 2 };

static int cv_mode;
static int cv_done;
static int cv_key_q;
static uint32_t cv_auto_tick;

/* AES / SHA state live in a union to save space */
typedef union {
    aes_t aes;
    sha_t sha;
} cv_state_t;

static cv_state_t cv_state;

static void cv_init(void) {
    cv_done = 0;
    cv_key_q = 0;
    cv_auto_tick = 0;
    fb_init();

    if (strcmp(g_arg_algo, "aes") == 0) {
        uint8_t key[16], pt[16];
        if (cv_hex(g_arg_a1, key, 16)!=16 || cv_hex(g_arg_a2, pt, 16)!=16) {
            cv_done = 1; return;
        }
        cv_mode = CV_AES;
        aes_precompute(&cv_state.aes, key, pt);
    } else if (strcmp(g_arg_algo, "sha256") == 0) {
        uint8_t msg[64];
        int ml = cv_hex(g_arg_a1, msg, 64);
        if (ml <= 0) { cv_done = 1; return; }
        cv_mode = CV_SHA;
        sha_precompute(&cv_state.sha, msg, ml);
    } else {
        cv_done = 1;
    }
}

static void cv_update(void) {
    if (cv_done) return;

    /* Drain queued key */
    int c = cv_key_q;
    cv_key_q = 0;

    if (cv_mode == CV_AES) {
        aes_t *s = &cv_state.aes;
        if (c=='Q') { cv_done = 1; return; }
        if (c==' ') { if(s->step<s->max_step) s->step++; }
        else if (c=='A') s->auto_play=1;
        else if (c=='P') s->auto_play=0;
        else if (c=='R') { if(s->step<s->max_step) s->step++; }
        else if (c=='L') { if(s->step>0) s->step--; }
        if (s->auto_play && s->step<s->max_step && ++cv_auto_tick>=30)
            { s->step++; cv_auto_tick=0; }
        aes_draw(s);
    } else if (cv_mode == CV_SHA) {
        sha_t *s = &cv_state.sha;
        if (c=='Q') { cv_done = 1; return; }
        if (c==' ') { if(s->step<64) s->step++; }
        else if (c=='A') s->auto_play=1;
        else if (c=='P') s->auto_play=0;
        else if (c=='R') { if(s->step<64) s->step++; }
        else if (c=='L') { if(s->step>0) s->step--; }
        if (s->auto_play && s->step<64 && ++cv_auto_tick>=30)
            { s->step++; cv_auto_tick=0; }
        sha_draw(s);
    }
}

static void cv_input(char c) {
    cv_key_q = (int)c;
}

static int cv_finish(void) {
    return cv_done;
}

const program_t prog_cryptoviz = {
    "CryptoViz",
    "AES/SHA step-through visualization",
    cv_init,
    cv_update,
    cv_input,
    NULL,
    cv_finish
};

/* ═══════════════════════════════════════════════════════════════════
 * Standalone entry (for direct use by RTOS CLI or testing)
 * ═══════════════════════════════════════════════════════════════════ */

#ifdef LOCAL_BUILD
static int cv_get_key_sdl(void) {
    SDL_Event e;
    while (SDL_PollEvent(&e)) {
        if (e.type == SDL_QUIT) return 'Q';
        if (e.type == SDL_KEYDOWN) {
            switch (e.key.keysym.sym) {
            case SDLK_SPACE:  return ' ';
            case SDLK_a:      return 'A';
            case SDLK_p:      return 'P';
            case SDLK_q:      return 'Q';
            case SDLK_ESCAPE: return 'Q';
            case SDLK_LEFT:   return 'L';
            case SDLK_RIGHT:  return 'R';
            }
        }
    }
    return 0;
}
#endif

int crypto_viz_run(const char *algo, const char *a1, const char *a2) {
    crypto_viz_set_args(algo, a1, a2);
    cv_init();
    if (cv_done) return 1;

#ifdef LOCAL_BUILD
    for (;;) {
        cv_update();
        if (cv_done) break;
        int c = cv_get_key_sdl();
        if (c) cv_key_q = c;
        SDL_Delay(16);
    }
#else
    /* NEORV32: relies on program_t callbacks from main loop */
#endif
    fb_shutdown();
    return 0;
}
