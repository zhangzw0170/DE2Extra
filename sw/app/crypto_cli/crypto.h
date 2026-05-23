/*
 * crypto.h — Phase 2a Crypto CLI: type definitions and function declarations
 *
 * Dual-mode: LOCAL_BUILD (native GCC test) vs NEORV32 bare-metal target.
 * All crypto algorithms are pure C, portable across both modes.
 */

#ifndef CRYPTO_H
#define CRYPTO_H

#ifdef LOCAL_BUILD
  /* Native GCC: use standard headers */
  #include <stdint.h>
  #include <stddef.h>
#else
  /* NEORV32 bare-metal target */
  #include <neorv32.h>
#endif

/* ── AES-128 ─────────────────────────────────────────────────── */

#define AES_BLOCK_SIZE  16   /* 128 bits */
#define AES128_KEY_SIZE 16
#define AES128_NK        4   /* number of 32-bit words in key */
#define AES128_NR       10   /* number of rounds */

void aes128_key_expand(const uint8_t key[AES128_KEY_SIZE],
                       uint32_t rk[4 * (AES128_NR + 1)]);

void aes128_enc_block(const uint8_t pt[AES_BLOCK_SIZE],
                      const uint32_t rk[4 * (AES128_NR + 1)],
                      uint8_t ct[AES_BLOCK_SIZE]);

void aes128_dec_block(const uint8_t ct[AES_BLOCK_SIZE],
                      const uint32_t rk[4 * (AES128_NR + 1)],
                      uint8_t pt[AES_BLOCK_SIZE]);

/* ── SHA-256 ─────────────────────────────────────────────────── */

#define SHA256_DIGEST_SIZE 32
#define SHA256_BLOCK_SIZE  64

typedef struct {
    uint32_t state[8];
    uint64_t count;       /* total bits processed */
    uint8_t  buf[SHA256_BLOCK_SIZE];
    uint32_t buf_len;     /* bytes in buffer */
} sha256_ctx_t;

void sha256_init(sha256_ctx_t *ctx);
void sha256_update(sha256_ctx_t *ctx, const uint8_t *data, size_t len);
void sha256_final(sha256_ctx_t *ctx, uint8_t digest[SHA256_DIGEST_SIZE]);
void sha256_hash(const uint8_t *data, size_t len, uint8_t digest[SHA256_DIGEST_SIZE]);

/* ── SHA-512 ─────────────────────────────────────────────────── */

#define SHA512_DIGEST_SIZE 64
#define SHA512_BLOCK_SIZE  128

typedef struct {
    uint64_t state[8];
    uint64_t count_high;   /* high 64 bits of bit count */
    uint64_t count_low;    /* low  64 bits of bit count */
    uint8_t  buf[SHA512_BLOCK_SIZE];
    uint32_t buf_len;
} sha512_ctx_t;

void sha512_init(sha512_ctx_t *ctx);
void sha512_update(sha512_ctx_t *ctx, const uint8_t *data, size_t len);
void sha512_final(sha512_ctx_t *ctx, uint8_t digest[SHA512_DIGEST_SIZE]);
void sha512_hash(const uint8_t *data, size_t len, uint8_t digest[SHA512_DIGEST_SIZE]);

/* ── SM4 ──────────────────────────────────────────────────────── */

#define SM4_BLOCK_SIZE  16
#define SM4_KEY_SIZE    16
#define SM4_NR          32   /* 32 rounds */

void sm4_key_schedule(const uint8_t key[SM4_KEY_SIZE], uint32_t rk[SM4_NR]);
void sm4_encrypt(const uint8_t pt[SM4_BLOCK_SIZE], const uint32_t rk[SM4_NR],
                 uint8_t ct[SM4_BLOCK_SIZE]);
void sm4_decrypt(const uint8_t ct[SM4_BLOCK_SIZE], const uint32_t rk[SM4_NR],
                 uint8_t pt[SM4_BLOCK_SIZE]);

/* ── SM3 ──────────────────────────────────────────────────────── */

#define SM3_DIGEST_SIZE 32
#define SM3_BLOCK_SIZE  64

typedef struct {
    uint32_t state[8];
    uint64_t count;       /* total bits processed */
    uint8_t  buf[SM3_BLOCK_SIZE];
    uint32_t buf_len;
} sm3_ctx_t;

void sm3_init(sm3_ctx_t *ctx);
void sm3_update(sm3_ctx_t *ctx, const uint8_t *data, size_t len);
void sm3_final(sm3_ctx_t *ctx, uint8_t digest[SM3_DIGEST_SIZE]);
void sm3_hash(const uint8_t *data, size_t len, uint8_t digest[SM3_DIGEST_SIZE]);

/* ── TRNG ─────────────────────────────────────────────────────── */

#ifdef LOCAL_BUILD
  /* Local: use a simple LCG as placeholder */
  void  trng_init(void);
  void  trng_bytes(uint8_t *buf, int n);
  int   trng_available(void);
#else
  /* NEORV32: map directly to hardware TRNG */
  #define trng_init()            neorv32_trng_enable()
  #define trng_available()       neorv32_trng_available()
  void  trng_bytes(uint8_t *buf, int n);
#endif

/* ── Utility ──────────────────────────────────────────────────── */

#ifdef LOCAL_BUILD
  /* hex string ↔ bytes conversion (local uses stdlib) */
  int   hex_decode(const char *hex, uint8_t *out, int max_len);
  void  hex_print(const uint8_t *data, int len);
  uint32_t bench_cycles(void);
  void  bench_reset(void);
#endif

#endif /* CRYPTO_H */
