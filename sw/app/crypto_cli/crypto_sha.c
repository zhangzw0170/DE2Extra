/*
 * crypto_sha.c — SHA-256 and SHA-512 hash functions
 *
 * Pure C reference implementations per NIST FIPS-180-4.
 *
 * SHA-256 test vectors (FIPS-180-4):
 *   ""     (0 bytes)  → e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
 *   "abc"  (616263)   → ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
 *   "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq" (448 bits)
 *                     → 248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1
 *
 * SHA-512 test vectors (FIPS-180-4):
 *   ""     (0 bytes)  → cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e
 *   "abc"  (616263)   → ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f
 */

#include "crypto.h"
#include <string.h>

/* ═══════════════════════════════════════════════════════════════
 * SHA-256
 * ═══════════════════════════════════════════════════════════════ */

static const uint32_t sha256_k[64] = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
    0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
    0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
    0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
};

static inline uint32_t rotr32(uint32_t x, int n) {
    return (x >> n) | (x << (32 - n));
}

static inline uint32_t bswap32(uint32_t x) {
    return ((x & 0xFF000000) >> 24) |
           ((x & 0x00FF0000) >>  8) |
           ((x & 0x0000FF00) <<  8) |
           ((x & 0x000000FF) << 24);
}

void sha256_init(sha256_ctx_t *ctx) {
    ctx->state[0] = 0x6a09e667;
    ctx->state[1] = 0xbb67ae85;
    ctx->state[2] = 0x3c6ef372;
    ctx->state[3] = 0xa54ff53a;
    ctx->state[4] = 0x510e527f;
    ctx->state[5] = 0x9b05688c;
    ctx->state[6] = 0x1f83d9ab;
    ctx->state[7] = 0x5be0cd19;
    ctx->count   = 0;
    ctx->buf_len = 0;
}

static void sha256_transform(uint32_t state[8], const uint8_t block[64]) {
    uint32_t w[64];
    int t;

    /* Prepare message schedule */
    for (t = 0; t < 16; t++) {
        w[t] = ((uint32_t)block[t*4]   << 24) |
               ((uint32_t)block[t*4+1] << 16) |
               ((uint32_t)block[t*4+2] <<  8) |
               ((uint32_t)block[t*4+3]);
    }
    for (t = 16; t < 64; t++) {
        uint32_t s0 = rotr32(w[t-15],  7) ^ rotr32(w[t-15], 18) ^ (w[t-15] >>  3);
        uint32_t s1 = rotr32(w[t-2],  17) ^ rotr32(w[t-2],  19) ^ (w[t-2]  >> 10);
        w[t] = w[t-16] + s0 + w[t-7] + s1;
    }

    /* Working variables */
    uint32_t a = state[0], b = state[1], c = state[2], d = state[3];
    uint32_t e = state[4], f = state[5], g = state[6], h = state[7];

    /* 64 rounds */
    for (t = 0; t < 64; t++) {
        uint32_t S1    = rotr32(e, 6) ^ rotr32(e, 11) ^ rotr32(e, 25);
        uint32_t ch    = (e & f) ^ ((~e) & g);
        uint32_t temp1 = h + S1 + ch + sha256_k[t] + w[t];
        uint32_t S0    = rotr32(a, 2) ^ rotr32(a, 13) ^ rotr32(a, 22);
        uint32_t maj   = (a & b) ^ (a & c) ^ (b & c);
        uint32_t temp2 = S0 + maj;

        h = g;  g = f;  f = e;
        e = d + temp1;
        d = c;  c = b;  b = a;
        a = temp1 + temp2;
    }

    state[0] += a;  state[1] += b;  state[2] += c;  state[3] += d;
    state[4] += e;  state[5] += f;  state[6] += g;  state[7] += h;
}

void sha256_update(sha256_ctx_t *ctx, const uint8_t *data, size_t len) {
    ctx->count += (uint64_t)len * 8;

    while (len > 0) {
        size_t space = SHA256_BLOCK_SIZE - ctx->buf_len;
        size_t copy  = (len < space) ? len : space;
        memcpy(ctx->buf + ctx->buf_len, data, copy);
        ctx->buf_len += (uint32_t)copy;
        data += copy;
        len  -= copy;

        if (ctx->buf_len == SHA256_BLOCK_SIZE) {
            sha256_transform(ctx->state, ctx->buf);
            ctx->buf_len = 0;
        }
    }
}

void sha256_final(sha256_ctx_t *ctx, uint8_t digest[SHA256_DIGEST_SIZE]) {
    /* Padding: 0x80 + zeros + 64-bit length */
    uint64_t bit_count = ctx->count;
    ctx->buf[ctx->buf_len++] = 0x80;

    if (ctx->buf_len > 56) {
        memset(ctx->buf + ctx->buf_len, 0, SHA256_BLOCK_SIZE - ctx->buf_len);
        sha256_transform(ctx->state, ctx->buf);
        ctx->buf_len = 0;
    }
    memset(ctx->buf + ctx->buf_len, 0, 56 - ctx->buf_len);

    /* Append length in bits as big-endian 64-bit */
    for (int i = 0; i < 8; i++)
        ctx->buf[56 + i] = (bit_count >> (56 - i*8)) & 0xFF;

    sha256_transform(ctx->state, ctx->buf);

    /* Output digest as big-endian */
    for (int i = 0; i < 8; i++) {
        uint32_t w = ctx->state[i];
        digest[i*4]   = (w >> 24) & 0xFF;
        digest[i*4+1] = (w >> 16) & 0xFF;
        digest[i*4+2] = (w >>  8) & 0xFF;
        digest[i*4+3] =  w        & 0xFF;
    }
}

void sha256_hash(const uint8_t *data, size_t len, uint8_t digest[SHA256_DIGEST_SIZE]) {
    sha256_ctx_t ctx;
    sha256_init(&ctx);
    sha256_update(&ctx, data, len);
    sha256_final(&ctx, digest);
}

/* ═══════════════════════════════════════════════════════════════
 * SHA-512
 * ═══════════════════════════════════════════════════════════════ */

static const uint64_t sha512_k[80] = {
    0x428a2f98d728ae22ULL, 0x7137449123ef65cdULL, 0xb5c0fbcfec4d3b2fULL, 0xe9b5dba58189dbbcULL,
    0x3956c25bf348b538ULL, 0x59f111f1b605d019ULL, 0x923f82a4af194f9bULL, 0xab1c5ed5da6d8118ULL,
    0xd807aa98a3030242ULL, 0x12835b0145706fbeULL, 0x243185be4ee4b28cULL, 0x550c7dc3d5ffb4e2ULL,
    0x72be5d74f27b896fULL, 0x80deb1fe3b1696b1ULL, 0x9bdc06a725c71235ULL, 0xc19bf174cf692694ULL,
    0xe49b69c19ef14ad2ULL, 0xefbe4786384f25e3ULL, 0x0fc19dc68b8cd5b5ULL, 0x240ca1cc77ac9c65ULL,
    0x2de92c6f592b0275ULL, 0x4a7484aa6ea6e483ULL, 0x5cb0a9dcbd41fbd4ULL, 0x76f988da831153b5ULL,
    0x983e5152ee66dfabULL, 0xa831c66d2db43210ULL, 0xb00327c898fb213fULL, 0xbf597fc7beef0ee4ULL,
    0xc6e00bf33da88fc2ULL, 0xd5a79147930aa725ULL, 0x06ca6351e003826fULL, 0x142929670a0e6e70ULL,
    0x27b70a8546d22ffcULL, 0x2e1b21385c26c926ULL, 0x4d2c6dfc5ac42aedULL, 0x53380d139d95b3dfULL,
    0x650a73548baf63deULL, 0x766a0abb3c77b2a8ULL, 0x81c2c92e47edaee6ULL, 0x92722c851482353bULL,
    0xa2bfe8a14cf10364ULL, 0xa81a664bbc423001ULL, 0xc24b8b70d0f89791ULL, 0xc76c51a30654be30ULL,
    0xd192e819d6ef5218ULL, 0xd69906245565a910ULL, 0xf40e35855771202aULL, 0x106aa07032bbd1b8ULL,
    0x19a4c116b8d2d0c8ULL, 0x1e376c085141ab53ULL, 0x2748774cdf8eeb99ULL, 0x34b0bcb5e19b48a8ULL,
    0x391c0cb3c5c95a63ULL, 0x4ed8aa4ae3418acbULL, 0x5b9cca4f7763e373ULL, 0x682e6ff3d6b2b8a3ULL,
    0x748f82ee5defb2fcULL, 0x78a5636f43172f60ULL, 0x84c87814a1f0ab72ULL, 0x8cc702081a6439ecULL,
    0x90befffa23631e28ULL, 0xa4506cebde82bde9ULL, 0xbef9a3f7b2c67915ULL, 0xc67178f2e372532bULL,
    0xca273eceea26619cULL, 0xd186b8c721c0c207ULL, 0xeada7dd6cde0eb1eULL, 0xf57d4f7fee6ed178ULL,
    0x06f067aa72176fbaULL, 0x0a637dc5a2c898a6ULL, 0x113f9804bef90daeULL, 0x1b710b35131c471bULL,
    0x28db77f523047d84ULL, 0x32caab7b40c72493ULL, 0x3c9ebe0a15c9bebcULL, 0x431d67c49c100d4cULL,
    0x4cc5d4becb3e42b6ULL, 0x597f299cfc657e2aULL, 0x5fcb6fab3ad6faecULL, 0x6c44198c4a475817ULL
};

static inline uint64_t rotr64(uint64_t x, int n) {
    return (x >> n) | (x << (64 - n));
}

void sha512_init(sha512_ctx_t *ctx) {
    ctx->state[0] = 0x6a09e667f3bcc908ULL;
    ctx->state[1] = 0xbb67ae8584caa73bULL;
    ctx->state[2] = 0x3c6ef372fe94f82bULL;
    ctx->state[3] = 0xa54ff53a5f1d36f1ULL;
    ctx->state[4] = 0x510e527fade682d1ULL;
    ctx->state[5] = 0x9b05688c2b3e6c1fULL;
    ctx->state[6] = 0x1f83d9abfb41bd6bULL;
    ctx->state[7] = 0x5be0cd19137e2179ULL;
    ctx->count_high = 0;
    ctx->count_low  = 0;
    ctx->buf_len    = 0;
}

static void sha512_transform(uint64_t state[8], const uint8_t block[128]) {
    uint64_t w[80];
    int t;

    /* Prepare message schedule */
    for (t = 0; t < 16; t++) {
        w[t] = ((uint64_t)block[t*8]   << 56) |
               ((uint64_t)block[t*8+1] << 48) |
               ((uint64_t)block[t*8+2] << 40) |
               ((uint64_t)block[t*8+3] << 32) |
               ((uint64_t)block[t*8+4] << 24) |
               ((uint64_t)block[t*8+5] << 16) |
               ((uint64_t)block[t*8+6] <<  8) |
               ((uint64_t)block[t*8+7]);
    }
    for (t = 16; t < 80; t++) {
        uint64_t s0 = rotr64(w[t-15],  1) ^ rotr64(w[t-15],  8) ^ (w[t-15] >> 7);
        uint64_t s1 = rotr64(w[t-2],  19) ^ rotr64(w[t-2],  61) ^ (w[t-2]  >> 6);
        w[t] = w[t-16] + s0 + w[t-7] + s1;
    }

    /* Working variables */
    uint64_t a = state[0], b = state[1], c = state[2], d = state[3];
    uint64_t e = state[4], f = state[5], g = state[6], h = state[7];

    /* 80 rounds */
    for (t = 0; t < 80; t++) {
        uint64_t S1    = rotr64(e, 14) ^ rotr64(e, 18) ^ rotr64(e, 41);
        uint64_t ch    = (e & f) ^ ((~e) & g);
        uint64_t temp1 = h + S1 + ch + sha512_k[t] + w[t];
        uint64_t S0    = rotr64(a, 28) ^ rotr64(a, 34) ^ rotr64(a, 39);
        uint64_t maj   = (a & b) ^ (a & c) ^ (b & c);
        uint64_t temp2 = S0 + maj;

        h = g;  g = f;  f = e;
        e = d + temp1;
        d = c;  c = b;  b = a;
        a = temp1 + temp2;
    }

    state[0] += a;  state[1] += b;  state[2] += c;  state[3] += d;
    state[4] += e;  state[5] += f;  state[6] += g;  state[7] += h;
}

void sha512_update(sha512_ctx_t *ctx, const uint8_t *data, size_t len) {
    /* Update bit count: add len*8 to 128-bit counter */
    uint64_t bits = (uint64_t)len * 8;
    ctx->count_low += bits;
    if (ctx->count_low < bits) ctx->count_high++;

    while (len > 0) {
        size_t space = SHA512_BLOCK_SIZE - ctx->buf_len;
        size_t copy  = (len < space) ? len : space;
        memcpy(ctx->buf + ctx->buf_len, data, copy);
        ctx->buf_len += (uint32_t)copy;
        data += copy;
        len  -= copy;

        if (ctx->buf_len == SHA512_BLOCK_SIZE) {
            sha512_transform(ctx->state, ctx->buf);
            ctx->buf_len = 0;
        }
    }
}

void sha512_final(sha512_ctx_t *ctx, uint8_t digest[SHA512_DIGEST_SIZE]) {
    ctx->buf[ctx->buf_len++] = 0x80;

    if (ctx->buf_len > 112) {
        memset(ctx->buf + ctx->buf_len, 0, SHA512_BLOCK_SIZE - ctx->buf_len);
        sha512_transform(ctx->state, ctx->buf);
        ctx->buf_len = 0;
    }
    memset(ctx->buf + ctx->buf_len, 0, 112 - ctx->buf_len);

    /* Append length as 128-bit big-endian */
    for (int i = 0; i < 8; i++) {
        ctx->buf[112 + i] = (ctx->count_high >> (56 - i*8)) & 0xFF;
        ctx->buf[120 + i] = (ctx->count_low  >> (56 - i*8)) & 0xFF;
    }

    sha512_transform(ctx->state, ctx->buf);

    /* Output digest as big-endian */
    for (int i = 0; i < 8; i++) {
        uint64_t w = ctx->state[i];
        digest[i*8]   = (w >> 56) & 0xFF;
        digest[i*8+1] = (w >> 48) & 0xFF;
        digest[i*8+2] = (w >> 40) & 0xFF;
        digest[i*8+3] = (w >> 32) & 0xFF;
        digest[i*8+4] = (w >> 24) & 0xFF;
        digest[i*8+5] = (w >> 16) & 0xFF;
        digest[i*8+6] = (w >>  8) & 0xFF;
        digest[i*8+7] =  w        & 0xFF;
    }
}

void sha512_hash(const uint8_t *data, size_t len, uint8_t digest[SHA512_DIGEST_SIZE]) {
    sha512_ctx_t ctx;
    sha512_init(&ctx);
    sha512_update(&ctx, data, len);
    sha512_final(&ctx, digest);
}

/* ═══════════════════════════════════════════════════════════════
 * SHA-256 Zk* Hardware Acceleration
 * ═══════════════════════════════════════════════════════════════ */

#ifndef LOCAL_BUILD
#include "crypto_zk.h"

static void sha256_transform_zkn(uint32_t state[8], const uint8_t block[64]) {
    uint32_t w[64];
    int t;

    for (t = 0; t < 16; t++) {
        w[t] = bswap32(((uint32_t)block[t*4]) |
                       ((uint32_t)block[t*4+1] << 8) |
                       ((uint32_t)block[t*4+2] << 16) |
                       ((uint32_t)block[t*4+3] << 24));
    }
    for (t = 16; t < 64; t++) {
        uint32_t s0 = zk_sha256sig0(w[t-15]);
        uint32_t s1 = zk_sha256sig1(w[t-2]);
        w[t] = w[t-16] + s0 + w[t-7] + s1;
    }

    uint32_t a = state[0], b = state[1], c = state[2], d = state[3];
    uint32_t e = state[4], f = state[5], g = state[6], h = state[7];

    for (t = 0; t < 64; t++) {
        uint32_t S1    = zk_sha256sum1(e);
        uint32_t ch    = (e & f) ^ ((~e) & g);
        uint32_t temp1 = h + S1 + ch + sha256_k[t] + w[t];
        uint32_t S0    = zk_sha256sum0(a);
        uint32_t maj   = (a & b) ^ (a & c) ^ (b & c);
        uint32_t temp2 = S0 + maj;

        h = g;  g = f;  f = e;
        e = d + temp1;
        d = c;  c = b;  b = a;
        a = temp1 + temp2;
    }

    state[0] += a;  state[1] += b;  state[2] += c;  state[3] += d;
    state[4] += e;  state[5] += f;  state[6] += g;  state[7] += h;
}

void sha256_hash_zkn(const uint8_t *data, size_t len,
                     uint8_t digest[SHA256_DIGEST_SIZE]) {
    sha256_ctx_t ctx;
    sha256_init(&ctx);

    ctx.count += (uint64_t)len * 8;

    while (len > 0) {
        size_t space = SHA256_BLOCK_SIZE - ctx.buf_len;
        size_t copy  = (len < space) ? len : space;
        memcpy(ctx.buf + ctx.buf_len, data, copy);
        ctx.buf_len += (uint32_t)copy;
        data += copy;
        len  -= copy;

        if (ctx.buf_len == SHA256_BLOCK_SIZE) {
            sha256_transform_zkn(ctx.state, ctx.buf);
            ctx.buf_len = 0;
        }
    }

    /* Padding */
    uint64_t bit_count = ctx.count;
    ctx.buf[ctx.buf_len++] = 0x80;
    if (ctx.buf_len > 56) {
        memset(ctx.buf + ctx.buf_len, 0, SHA256_BLOCK_SIZE - ctx.buf_len);
        sha256_transform_zkn(ctx.state, ctx.buf);
        ctx.buf_len = 0;
    }
    memset(ctx.buf + ctx.buf_len, 0, 56 - ctx.buf_len);
    for (int i = 0; i < 8; i++)
        ctx.buf[56 + i] = (bit_count >> (56 - i*8)) & 0xFF;

    sha256_transform_zkn(ctx.state, ctx.buf);

    for (int i = 0; i < 8; i++) {
        uint32_t w = ctx.state[i];
        digest[i*4]   = (w >> 24) & 0xFF;
        digest[i*4+1] = (w >> 16) & 0xFF;
        digest[i*4+2] = (w >>  8) & 0xFF;
        digest[i*4+3] =  w        & 0xFF;
    }
}

/* ═══════════════════════════════════════════════════════════════
 * SHA-512 Zk* Hardware Acceleration (RV32 — 64-bit via high/low pairs)
 * ═══════════════════════════════════════════════════════════════ */

/*
 * On RV32, 64-bit values are split into (high, low) 32-bit halves.
 * The Zknh SHA-512 instructions operate on these pairs:
 *
 *   sig0(x) = rotr64(x,1) ^ rotr64(x,8) ^ (x >> 7)
 *     → sig0h(x_hi, x_lo) = rotr32(x_hi, 1) ^ x_lo >> 8
 *     → sig0l(x_hi, x_lo) = rotr32(x_lo, 8) ^ x_hi << 24 ^ x_lo >> 7 ^ x_hi >> 8
 *     But the instruction returns the full 32-bit partial, so:
 *       sig0h = sha512sig0h(x_hi, x_lo)  — upper bits of the result
 *       sig0l = sha512sig0l(x_hi, x_lo)  — lower bits of the result
 *
 * Similarly for sig1, sum0r, sum1r.
 */

static void sha512_transform_zkn(uint64_t state[8], const uint8_t block[128]) {
    uint64_t w[80];
    int t;

    for (t = 0; t < 16; t++) {
        w[t] = ((uint64_t)block[t*8]   << 56) |
               ((uint64_t)block[t*8+1] << 48) |
               ((uint64_t)block[t*8+2] << 40) |
               ((uint64_t)block[t*8+3] << 32) |
               ((uint64_t)block[t*8+4] << 24) |
               ((uint64_t)block[t*8+5] << 16) |
               ((uint64_t)block[t*8+6] <<  8) |
               ((uint64_t)block[t*8+7]);
    }
    for (t = 16; t < 80; t++) {
        uint32_t w15h = (uint32_t)(w[t-15] >> 32), w15l = (uint32_t)w[t-15];
        uint32_t w2h  = (uint32_t)(w[t-2]  >> 32), w2l  = (uint32_t)w[t-2];
        uint64_t s0 = ((uint64_t)zk_sha512sig0h(w15h, w15l) << 32) |
                      zk_sha512sig0l(w15h, w15l);
        uint64_t s1 = ((uint64_t)zk_sha512sig1h(w2h, w2l) << 32) |
                      zk_sha512sig1l(w2h, w2l);
        w[t] = w[t-16] + s0 + w[t-7] + s1;
    }

    uint64_t a = state[0], b = state[1], c = state[2], d = state[3];
    uint64_t e = state[4], f = state[5], g = state[6], h = state[7];

    for (t = 0; t < 80; t++) {
        uint32_t eh = (uint32_t)(e >> 32), el = (uint32_t)e;
        uint32_t ah = (uint32_t)(a >> 32), al = (uint32_t)a;

        uint64_t S1 = ((uint64_t)zk_sha512sum1r(eh, el) << 32) |
                      zk_sha512sum1r(el, eh);
        uint64_t ch = (e & f) ^ ((~e) & g);
        uint64_t temp1 = h + S1 + ch + sha512_k[t] + w[t];
        uint64_t S0 = ((uint64_t)zk_sha512sum0r(ah, al) << 32) |
                      zk_sha512sum0r(al, ah);
        uint64_t maj = (a & b) ^ (a & c) ^ (b & c);
        uint64_t temp2 = S0 + maj;

        h = g;  g = f;  f = e;
        e = d + temp1;
        d = c;  c = b;  b = a;
        a = temp1 + temp2;
    }

    state[0] += a;  state[1] += b;  state[2] += c;  state[3] += d;
    state[4] += e;  state[5] += f;  state[6] += g;  state[7] += h;
}

void sha512_hash_zkn(const uint8_t *data, size_t len,
                     uint8_t digest[SHA512_DIGEST_SIZE]) {
    sha512_ctx_t ctx;
    sha512_init(&ctx);

    uint64_t bits = (uint64_t)len * 8;
    ctx.count_low += bits;
    if (ctx.count_low < bits) ctx.count_high++;

    while (len > 0) {
        size_t space = SHA512_BLOCK_SIZE - ctx.buf_len;
        size_t copy  = (len < space) ? len : space;
        memcpy(ctx.buf + ctx.buf_len, data, copy);
        ctx.buf_len += (uint32_t)copy;
        data += copy;
        len  -= copy;

        if (ctx.buf_len == SHA512_BLOCK_SIZE) {
            sha512_transform_zkn(ctx.state, ctx.buf);
            ctx.buf_len = 0;
        }
    }

    ctx.buf[ctx.buf_len++] = 0x80;
    if (ctx.buf_len > 112) {
        memset(ctx.buf + ctx.buf_len, 0, SHA512_BLOCK_SIZE - ctx.buf_len);
        sha512_transform_zkn(ctx.state, ctx.buf);
        ctx.buf_len = 0;
    }
    memset(ctx.buf + ctx.buf_len, 0, 112 - ctx.buf_len);
    for (int i = 0; i < 8; i++) {
        ctx.buf[112 + i] = (ctx.count_high >> (56 - i*8)) & 0xFF;
        ctx.buf[120 + i] = (ctx.count_low  >> (56 - i*8)) & 0xFF;
    }

    sha512_transform_zkn(ctx.state, ctx.buf);

    for (int i = 0; i < 8; i++) {
        uint64_t w = ctx.state[i];
        digest[i*8]   = (w >> 56) & 0xFF;
        digest[i*8+1] = (w >> 48) & 0xFF;
        digest[i*8+2] = (w >> 40) & 0xFF;
        digest[i*8+3] = (w >> 32) & 0xFF;
        digest[i*8+4] = (w >> 24) & 0xFF;
        digest[i*8+5] = (w >> 16) & 0xFF;
        digest[i*8+6] = (w >>  8) & 0xFF;
        digest[i*8+7] =  w        & 0xFF;
    }
}

#endif /* LOCAL_BUILD */
