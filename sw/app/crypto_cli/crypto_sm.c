/*
 * crypto_sm.c — SM4 block cipher and SM3 hash function
 *
 * Pure C reference implementations per:
 *   SM4: GB/T 32907-2016
 *   SM3: GB/T 32905-2016
 *
 * SM4 test vectors:
 *   Key:        0123456789abcdeffedcba9876543210
 *   Plaintext:  0123456789abcdeffedcba9876543210
 *   Ciphertext: 681edf34d206965e86b3e94f536e4246
 *
 * SM3 test vectors:
 *   ""    → 1ab21d8355cfa17f8e61194831e81a8f22bec8c728fefb747ed035eb5082aa2b
 *   "abc" (616263) → 66c7f0f462eeedd9d1f2d46bdc10e4e24167c4875cf2f7a2297da02b8f4ba8e0
 */

#include "crypto.h"
#include <string.h>

/* ═══════════════════════════════════════════════════════════════
 * SM4 Block Cipher (GB/T 32907-2016)
 * ═══════════════════════════════════════════════════════════════ */

static const uint8_t sm4_sbox[256] = {
    0xd6,0x90,0xe9,0xfe,0xcc,0xe1,0x3d,0xb7,0x16,0xb6,0x14,0xc2,0x28,0xfb,0x2c,0x05,
    0x2b,0x67,0x9a,0x76,0x2a,0xbe,0x04,0xc3,0xaa,0x44,0x13,0x26,0x49,0x86,0x06,0x99,
    0x9c,0x42,0x50,0xf4,0x91,0xef,0x98,0x7a,0x33,0x54,0x0b,0x43,0xed,0xcf,0xac,0x62,
    0xe4,0xb3,0x1c,0xa9,0xc9,0x08,0xe8,0x95,0x80,0xdf,0x94,0xfa,0x75,0x8f,0x3f,0xa6,
    0x47,0x07,0xa7,0xfc,0xf3,0x73,0x17,0xba,0x83,0x59,0x3c,0x19,0xe6,0x85,0x4f,0xa8,
    0x68,0x6b,0x81,0xb2,0x71,0x64,0xda,0x8b,0xf8,0xeb,0x0f,0x4b,0x70,0x56,0x9d,0x35,
    0x1e,0x24,0x0e,0x5e,0x63,0x58,0xd1,0xa2,0x25,0x22,0x7c,0x3b,0x01,0x21,0x78,0x87,
    0xd4,0x00,0x46,0x57,0x9f,0xd3,0x27,0x52,0x4c,0x36,0x02,0xe7,0xa0,0xc4,0xc8,0x9e,
    0xea,0xbf,0x8a,0xd2,0x40,0xc7,0x38,0xb5,0xa3,0xf7,0xf2,0xce,0xf9,0x61,0x15,0xa1,
    0xe0,0xae,0x5d,0xa4,0x9b,0x34,0x1a,0x55,0xad,0x93,0x32,0x30,0xf5,0x8c,0xb1,0xe3,
    0x1d,0xf6,0xe2,0x2e,0x82,0x66,0xca,0x60,0xc0,0x29,0x23,0xab,0x0d,0x53,0x4e,0x6f,
    0xd5,0xdb,0x37,0x45,0xde,0xfd,0x8e,0x2f,0x03,0xff,0x6a,0x72,0x6d,0x6c,0x5b,0x51,
    0x8d,0x1b,0xaf,0x92,0xbb,0xdd,0xbc,0x7f,0x11,0xd9,0x5c,0x41,0x1f,0x10,0x5a,0xd8,
    0x0a,0xc1,0x31,0x88,0xa5,0xcd,0x7b,0xbd,0x2d,0x74,0xd0,0x12,0xb8,0xe5,0xb4,0xb0,
    0x89,0x69,0x97,0x4a,0x0c,0x96,0x77,0x7e,0x65,0xb9,0xf1,0x09,0xc5,0x6e,0xc6,0x84,
    0x18,0xf0,0x7d,0xec,0x3a,0xdc,0x4d,0x20,0x79,0xee,0x5f,0x3e,0xd7,0xcb,0x39,0x48
};

/* System parameters FK */
static const uint32_t sm4_fk[4] = {
    0xa3b1bac6, 0x56aa3350, 0x677d9197, 0xb27022dc
};

/* Constant parameters CK */
static const uint32_t sm4_ck[32] = {
    0x00070e15, 0x1c232a31, 0x383f464d, 0x545b6269,
    0x70777e85, 0x8c939aa1, 0xa8afb6bd, 0xc4cbd2d9,
    0xe0e7eef5, 0xfc030a11, 0x181f262d, 0x343b4249,
    0x50575e65, 0x6c737a81, 0x888f969d, 0xa4abb2b9,
    0xc0c7ced5, 0xdce3eaf1, 0xf8ff060d, 0x141b2229,
    0x30373e45, 0x4c535a61, 0x686f767d, 0x848b9299,
    0xa0a7aeb5, 0xbcc3cad1, 0xd8dfe6ed, 0xf4fb0209,
    0x10171e25, 0x2c333a41, 0x484f565d, 0x646b7279
};

/* 32-bit left rotate */
static inline uint32_t rotl32(uint32_t x, int n) {
    return (x << n) | (x >> (32 - n));
}

/* Non-linear transformation τ: four S-box lookups */
static uint32_t sm4_tau(uint32_t a) {
    return ((uint32_t)sm4_sbox[(a >> 24) & 0xFF] << 24) |
           ((uint32_t)sm4_sbox[(a >> 16) & 0xFF] << 16) |
           ((uint32_t)sm4_sbox[(a >>  8) & 0xFF] <<  8) |
           ((uint32_t)sm4_sbox[ a        & 0xFF]);
}

/* Linear transformation L */
static uint32_t sm4_l(uint32_t b) {
    return b ^ rotl32(b, 2) ^ rotl32(b, 10) ^ rotl32(b, 18) ^ rotl32(b, 24);
}

/* Linear transformation L' (for key schedule) */
static uint32_t sm4_l_prime(uint32_t b) {
    return b ^ rotl32(b, 13) ^ rotl32(b, 23);
}

/* Round function */
static uint32_t sm4_f(uint32_t x0, uint32_t x1, uint32_t x2, uint32_t x3, uint32_t rk) {
    return x0 ^ sm4_l(sm4_tau(x1 ^ x2 ^ x3 ^ rk));
}

void sm4_key_schedule(const uint8_t key[SM4_KEY_SIZE], uint32_t rk[SM4_NR]) {
    uint32_t mk[4];

    /* Load master key as 4 big-endian 32-bit words */
    for (int i = 0; i < 4; i++) {
        mk[i] = ((uint32_t)key[4*i]   << 24) |
                ((uint32_t)key[4*i+1] << 16) |
                ((uint32_t)key[4*i+2] <<  8) |
                ((uint32_t)key[4*i+3]);
    }

    /* K_i = MK_i ⊕ FK_i */
    uint32_t k[36];
    for (int i = 0; i < 4; i++)
        k[i] = mk[i] ^ sm4_fk[i];

    /* Generate round keys */
    for (int i = 0; i < 32; i++) {
        k[i+4] = k[i] ^ sm4_l_prime(sm4_tau(k[i+1] ^ k[i+2] ^ k[i+3] ^ sm4_ck[i]));
        rk[i]  = k[i+4];
    }
}

void sm4_encrypt(const uint8_t pt[SM4_BLOCK_SIZE], const uint32_t rk[SM4_NR],
                 uint8_t ct[SM4_BLOCK_SIZE]) {
    uint32_t x[36];

    /* Load plaintext as 4 big-endian 32-bit words */
    for (int i = 0; i < 4; i++) {
        x[i] = ((uint32_t)pt[4*i]   << 24) |
               ((uint32_t)pt[4*i+1] << 16) |
               ((uint32_t)pt[4*i+2] <<  8) |
               ((uint32_t)pt[4*i+3]);
    }

    /* 32 rounds */
    for (int i = 0; i < 32; i++)
        x[i+4] = sm4_f(x[i], x[i+1], x[i+2], x[i+3], rk[i]);

    /* Output in reverse order as big-endian */
    for (int i = 0; i < 4; i++) {
        uint32_t w = x[35 - i];
        ct[4*i]   = (w >> 24) & 0xFF;
        ct[4*i+1] = (w >> 16) & 0xFF;
        ct[4*i+2] = (w >>  8) & 0xFF;
        ct[4*i+3] =  w        & 0xFF;
    }
}

void sm4_decrypt(const uint8_t ct[SM4_BLOCK_SIZE], const uint32_t rk[SM4_NR],
                 uint8_t pt[SM4_BLOCK_SIZE]) {
    uint32_t x[36];

    /* Load ciphertext as 4 big-endian 32-bit words */
    for (int i = 0; i < 4; i++) {
        x[i] = ((uint32_t)ct[4*i]   << 24) |
               ((uint32_t)ct[4*i+1] << 16) |
               ((uint32_t)ct[4*i+2] <<  8) |
               ((uint32_t)ct[4*i+3]);
    }

    /* 32 rounds with reversed key order */
    for (int i = 0; i < 32; i++)
        x[i+4] = sm4_f(x[i], x[i+1], x[i+2], x[i+3], rk[31 - i]);

    /* Output in reverse order as big-endian */
    for (int i = 0; i < 4; i++) {
        uint32_t w = x[35 - i];
        pt[4*i]   = (w >> 24) & 0xFF;
        pt[4*i+1] = (w >> 16) & 0xFF;
        pt[4*i+2] = (w >>  8) & 0xFF;
        pt[4*i+3] =  w        & 0xFF;
    }
}

/* ═══════════════════════════════════════════════════════════════
 * SM3 Hash Function (GB/T 32905-2016)
 * ═══════════════════════════════════════════════════════════════ */

/* Initial value IV */
static const uint32_t sm3_iv[8] = {
    0x7380166f, 0x4914b2b9, 0x172442d7, 0xda8a0600,
    0xa96f30bc, 0x163138aa, 0xe38dee4d, 0xb0fb0e4e
};

/* Constants T_j */
static inline uint32_t sm3_tj(int j) {
    return (j < 16) ? 0x79cc4519 : 0x7a879d8a;
}

/* P0 permutation */
static inline uint32_t sm3_p0(uint32_t x) {
    return x ^ rotl32(x, 9) ^ rotl32(x, 17);
}

/* P1 permutation */
static inline uint32_t sm3_p1(uint32_t x) {
    return x ^ rotl32(x, 15) ^ rotl32(x, 23);
}

/* Boolean functions */
static inline uint32_t sm3_ff0(uint32_t x, uint32_t y, uint32_t z) {
    return x ^ y ^ z;
}

static inline uint32_t sm3_ff1(uint32_t x, uint32_t y, uint32_t z) {
    return (x & y) | (x & z) | (y & z);
}

static inline uint32_t sm3_gg0(uint32_t x, uint32_t y, uint32_t z) {
    return x ^ y ^ z;
}

static inline uint32_t sm3_gg1(uint32_t x, uint32_t y, uint32_t z) {
    return (x & y) | ((~x) & z);
}

void sm3_init(sm3_ctx_t *ctx) {
    for (int i = 0; i < 8; i++)
        ctx->state[i] = sm3_iv[i];
    ctx->count   = 0;
    ctx->buf_len = 0;
}

static void sm3_compress(uint32_t state[8], const uint8_t block[64]) {
    uint32_t w[68], w1[64];

    /* Message expansion: W[0..15] */
    for (int t = 0; t < 16; t++) {
        w[t] = ((uint32_t)block[t*4]   << 24) |
               ((uint32_t)block[t*4+1] << 16) |
               ((uint32_t)block[t*4+2] <<  8) |
               ((uint32_t)block[t*4+3]);
    }

    /* W[16..67] */
    for (int t = 16; t < 68; t++) {
        w[t] = sm3_p1(w[t-16] ^ w[t-9] ^ rotl32(w[t-3], 15))
             ^ rotl32(w[t-13], 7) ^ w[t-6];
    }

    /* W'[0..63] */
    for (int t = 0; t < 64; t++)
        w1[t] = w[t] ^ w[t+4];

    /* Working variables */
    uint32_t a = state[0], b = state[1], c = state[2], d = state[3];
    uint32_t e = state[4], f = state[5], g = state[6], h = state[7];

    /* 64 rounds */
    for (int j = 0; j < 64; j++) {
        uint32_t ss1 = rotl32(rotl32(a, 12) + e + rotl32(sm3_tj(j), j % 32), 7);
        uint32_t ss2 = ss1 ^ rotl32(a, 12);
        uint32_t tt1, tt2;

        if (j < 16) {
            tt1 = sm3_ff0(a, b, c) + d + ss2 + w1[j];
            tt2 = sm3_gg0(e, f, g) + h + ss1 + w[j];
        } else {
            tt1 = sm3_ff1(a, b, c) + d + ss2 + w1[j];
            tt2 = sm3_gg1(e, f, g) + h + ss1 + w[j];
        }

        d = c;
        c = rotl32(b, 9);
        b = a;
        a = tt1;
        h = g;
        g = rotl32(f, 19);
        f = e;
        e = sm3_p0(tt2);
    }

    state[0] ^= a;  state[1] ^= b;  state[2] ^= c;  state[3] ^= d;
    state[4] ^= e;  state[5] ^= f;  state[6] ^= g;  state[7] ^= h;
}

void sm3_update(sm3_ctx_t *ctx, const uint8_t *data, size_t len) {
    ctx->count += (uint64_t)len * 8;

    while (len > 0) {
        size_t space = SM3_BLOCK_SIZE - ctx->buf_len;
        size_t copy  = (len < space) ? len : space;
        memcpy(ctx->buf + ctx->buf_len, data, copy);
        ctx->buf_len += (uint32_t)copy;
        data += copy;
        len  -= copy;

        if (ctx->buf_len == SM3_BLOCK_SIZE) {
            sm3_compress(ctx->state, ctx->buf);
            ctx->buf_len = 0;
        }
    }
}

void sm3_final(sm3_ctx_t *ctx, uint8_t digest[SM3_DIGEST_SIZE]) {
    uint64_t bit_count = ctx->count;
    ctx->buf[ctx->buf_len++] = 0x80;

    if (ctx->buf_len > 56) {
        memset(ctx->buf + ctx->buf_len, 0, SM3_BLOCK_SIZE - ctx->buf_len);
        sm3_compress(ctx->state, ctx->buf);
        ctx->buf_len = 0;
    }
    memset(ctx->buf + ctx->buf_len, 0, 56 - ctx->buf_len);

    /* Append bit length as big-endian 64-bit */
    for (int i = 0; i < 8; i++)
        ctx->buf[56 + i] = (bit_count >> (56 - i*8)) & 0xFF;

    sm3_compress(ctx->state, ctx->buf);

    /* Output as big-endian */
    for (int i = 0; i < 8; i++) {
        uint32_t w = ctx->state[i];
        digest[i*4]   = (w >> 24) & 0xFF;
        digest[i*4+1] = (w >> 16) & 0xFF;
        digest[i*4+2] = (w >>  8) & 0xFF;
        digest[i*4+3] =  w        & 0xFF;
    }
}

void sm3_hash(const uint8_t *data, size_t len, uint8_t digest[SM3_DIGEST_SIZE]) {
    sm3_ctx_t ctx;
    sm3_init(&ctx);
    sm3_update(&ctx, data, len);
    sm3_final(&ctx, digest);
}

/* ═══════════════════════════════════════════════════════════════
 * SM4 Zks* Hardware Acceleration
 * ═══════════════════════════════════════════════════════════════ */

#ifndef LOCAL_BUILD
#include "crypto_zk.h"

/*
 * sm4ed rd, rs1, rs2, bs — one byte of τ + partial L:
 *   rd = rs1 ^ (L_partial ^ rol32(sbox(byte_bs(rs2)), bs*8))
 * sm4ks rd, rs1, rs2, bs — one byte of τ + partial L':
 *   rd = rs1 ^ (L'_partial ^ rol32(sbox(byte_bs(rs2)), bs*8))
 *
 * Pattern: accumulate 4 bs values (0..3) per round word.
 * L = x ^ rotl(x,2) ^ rotl(x,10) ^ rotl(x,18) ^ rotl(x,24)
 *   emerges from the 4 partial L results XORed together.
 */

static uint32_t sm4_ed_zk(uint32_t src, uint32_t x, uint32_t rk_val) {
    uint32_t b = 0;
    b ^= zk_sm4ed(0, x, 0);
    b ^= zk_sm4ed(0, x, 1);
    b ^= zk_sm4ed(0, x, 2);
    b ^= zk_sm4ed(0, x, 3);
    return src ^ b ^ rk_val;
}

static uint32_t sm4_ks_zk(uint32_t x, uint32_t ck_val) {
    uint32_t b = 0;
    b ^= zk_sm4ks(0, x, 0);
    b ^= zk_sm4ks(0, x, 1);
    b ^= zk_sm4ks(0, x, 2);
    b ^= zk_sm4ks(0, x, 3);
    return b ^ ck_val;
}

void sm4_key_schedule_zks(const uint8_t key[SM4_KEY_SIZE], uint32_t rk[SM4_NR]) {
    uint32_t k[36];

    for (int i = 0; i < 4; i++) {
        k[i] = ((uint32_t)key[4*i]   << 24) |
               ((uint32_t)key[4*i+1] << 16) |
               ((uint32_t)key[4*i+2] <<  8) |
               ((uint32_t)key[4*i+3]) ^ sm4_fk[i];
    }

    for (int i = 0; i < 32; i++)
        k[i+4] = k[i] ^ sm4_ks_zk(k[i+1] ^ k[i+2] ^ k[i+3], sm4_ck[i]);

    for (int i = 0; i < 32; i++)
        rk[i] = k[i+4];
}

void sm4_encrypt_zks(const uint8_t pt[SM4_BLOCK_SIZE], const uint32_t rk[SM4_NR],
                     uint8_t ct[SM4_BLOCK_SIZE]) {
    uint32_t x[36];

    for (int i = 0; i < 4; i++) {
        x[i] = ((uint32_t)pt[4*i]   << 24) |
               ((uint32_t)pt[4*i+1] << 16) |
               ((uint32_t)pt[4*i+2] <<  8) |
               ((uint32_t)pt[4*i+3]);
    }

    for (int i = 0; i < 32; i++)
        x[i+4] = sm4_ed_zk(x[i], x[i+1] ^ x[i+2] ^ x[i+3], rk[i]);

    for (int i = 0; i < 4; i++) {
        uint32_t w = x[35 - i];
        ct[4*i]   = (w >> 24) & 0xFF;
        ct[4*i+1] = (w >> 16) & 0xFF;
        ct[4*i+2] = (w >>  8) & 0xFF;
        ct[4*i+3] =  w        & 0xFF;
    }
}

/* ═══════════════════════════════════════════════════════════════
 * SM3 Zksh Hardware Acceleration
 * ═══════════════════════════════════════════════════════════════ */

/*
 * sm3p0 rd, rs1 — P0(x) = x ^ rotl(x,9) ^ rotl(x,17)
 * sm3p1 rd, rs1 — P1(x) = x ^ rotl(x,15) ^ rotl(x,23)
 *
 * P1 replaces sm3_p1() in message expansion (W[16..67]).
 * P0 replaces sm3_p0() in compression (e = P0(tt2)).
 */

static void sm3_compress_zkn(uint32_t state[8], const uint8_t block[64]) {
    uint32_t w[68], w1[64];

    for (int t = 0; t < 16; t++) {
        w[t] = ((uint32_t)block[t*4]   << 24) |
               ((uint32_t)block[t*4+1] << 16) |
               ((uint32_t)block[t*4+2] <<  8) |
               ((uint32_t)block[t*4+3]);
    }

    for (int t = 16; t < 68; t++) {
        w[t] = zk_sm3p1(w[t-16] ^ w[t-9] ^ rotl32(w[t-3], 15))
             ^ rotl32(w[t-13], 7) ^ w[t-6];
    }

    for (int t = 0; t < 64; t++)
        w1[t] = w[t] ^ w[t+4];

    uint32_t a = state[0], b = state[1], c = state[2], d = state[3];
    uint32_t e = state[4], f = state[5], g = state[6], h = state[7];

    for (int j = 0; j < 64; j++) {
        uint32_t ss1 = rotl32(rotl32(a, 12) + e + rotl32(sm3_tj(j), j % 32), 7);
        uint32_t ss2 = ss1 ^ rotl32(a, 12);
        uint32_t tt1, tt2;

        if (j < 16) {
            tt1 = sm3_ff0(a, b, c) + d + ss2 + w1[j];
            tt2 = sm3_gg0(e, f, g) + h + ss1 + w[j];
        } else {
            tt1 = sm3_ff1(a, b, c) + d + ss2 + w1[j];
            tt2 = sm3_gg1(e, f, g) + h + ss1 + w[j];
        }

        d = c;
        c = rotl32(b, 9);
        b = a;
        a = tt1;
        h = g;
        g = rotl32(f, 19);
        f = e;
        e = zk_sm3p0(tt2);   /* was: sm3_p0(tt2) */
    }

    state[0] ^= a;  state[1] ^= b;  state[2] ^= c;  state[3] ^= d;
    state[4] ^= e;  state[5] ^= f;  state[6] ^= g;  state[7] ^= h;
}

void sm3_hash_zks(const uint8_t *data, size_t len,
                  uint8_t digest[SM3_DIGEST_SIZE]) {
    sm3_ctx_t ctx;
    sm3_init(&ctx);

    ctx.count += (uint64_t)len * 8;

    while (len > 0) {
        size_t space = SM3_BLOCK_SIZE - ctx.buf_len;
        size_t copy  = (len < space) ? len : space;
        memcpy(ctx.buf + ctx.buf_len, data, copy);
        ctx.buf_len += (uint32_t)copy;
        data += copy;
        len  -= copy;

        if (ctx.buf_len == SM3_BLOCK_SIZE) {
            sm3_compress_zkn(ctx.state, ctx.buf);
            ctx.buf_len = 0;
        }
    }

    uint64_t bit_count = ctx.count;
    ctx.buf[ctx.buf_len++] = 0x80;
    if (ctx.buf_len > 56) {
        memset(ctx.buf + ctx.buf_len, 0, SM3_BLOCK_SIZE - ctx.buf_len);
        sm3_compress_zkn(ctx.state, ctx.buf);
        ctx.buf_len = 0;
    }
    memset(ctx.buf + ctx.buf_len, 0, 56 - ctx.buf_len);
    for (int i = 0; i < 8; i++)
        ctx.buf[56 + i] = (bit_count >> (56 - i*8)) & 0xFF;

    sm3_compress_zkn(ctx.state, ctx.buf);

    for (int i = 0; i < 8; i++) {
        uint32_t w = ctx.state[i];
        digest[i*4]   = (w >> 24) & 0xFF;
        digest[i*4+1] = (w >> 16) & 0xFF;
        digest[i*4+2] = (w >>  8) & 0xFF;
        digest[i*4+3] =  w        & 0xFF;
    }
}

#endif /* LOCAL_BUILD */
