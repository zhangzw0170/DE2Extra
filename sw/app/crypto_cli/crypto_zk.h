/*
 * crypto_zk.h — RISC-V Zk* scalar cryptography instruction wrappers
 *
 * Uses NEORV32 intrinsic helpers (neorv32_intrinsics.h) for .insn emission.
 * For AES-32 and SM4, the bs field (byte-select) is encoded in the top 2
 * bits of funct7, so funct7 = (bs << 5) | funct5.
 *
 * Only available on NEORV32 bare-metal target (not LOCAL_BUILD).
 */

#ifndef CRYPTO_ZK_H
#define CRYPTO_ZK_H

#ifndef LOCAL_BUILD
#include "neorv32_intrinsics.h"

/* ── AES-32 (Zkne / Zknd) ──────────────────────────────────────── */

/* aes32esmi rd, rs1, rs2, bs — encrypt round (SubBytes+ShiftRows+MixColumns+XOR) */
#define zk_aes32esmi(rs1, rs2, bs) \
    RISCV_INSTR_R_TYPE(0x33, 0, ((bs) << 5) | 0x13, rs1, rs2)

/* aes32esi rd, rs1, rs2, bs — encrypt final round (SubBytes+ShiftRows+XOR) */
#define zk_aes32esi(rs1, rs2, bs) \
    RISCV_INSTR_R_TYPE(0x33, 0, ((bs) << 5) | 0x11, rs1, rs2)

/* aes32dsmi rd, rs1, rs2, bs — decrypt round (InvSub+InvShift+InvMixCol+XOR) */
#define zk_aes32dsmi(rs1, rs2, bs) \
    RISCV_INSTR_R_TYPE(0x33, 0, ((bs) << 5) | 0x17, rs1, rs2)

/* aes32dsi rd, rs1, rs2, bs — decrypt final round (InvSub+InvShift+XOR) */
#define zk_aes32dsi(rs1, rs2, bs) \
    RISCV_INSTR_R_TYPE(0x33, 0, ((bs) << 5) | 0x15, rs1, rs2)

/* ── SM4 (Zksed) ───────────────────────────────────────────────── */

/* sm4ed rd, rs1, rs2, bs — SM4 encrypt/decrypt round */
#define zk_sm4ed(rs1, rs2, bs) \
    RISCV_INSTR_R_TYPE(0x33, 0, ((bs) << 5) | 0x18, rs1, rs2)

/* sm4ks rd, rs1, rs2, bs — SM4 key schedule round */
#define zk_sm4ks(rs1, rs2, bs) \
    RISCV_INSTR_R_TYPE(0x33, 0, ((bs) << 5) | 0x1A, rs1, rs2)

/* ── SHA-256 (Zknh, I-type) ────────────────────────────────────── */

/* sha256sig0 rd, rs1 — σ0 for message schedule: rotr7 ^ rotr18 ^ shr3 */
#define zk_sha256sig0(rs1) \
    RISCV_INSTR_I_TYPE(0x13, 1, rs1, 0x102)

/* sha256sig1 rd, rs1 — σ1 for message schedule: rotr17 ^ rotr19 ^ shr10 */
#define zk_sha256sig1(rs1) \
    RISCV_INSTR_I_TYPE(0x13, 1, rs1, 0x103)

/* sha256sum0 rd, rs1 — Σ0 for compression: rotr2 ^ rotr13 ^ rotr22 */
#define zk_sha256sum0(rs1) \
    RISCV_INSTR_I_TYPE(0x13, 1, rs1, 0x100)

/* sha256sum1 rd, rs1 — Σ1 for compression: rotr6 ^ rotr11 ^ rotr25 */
#define zk_sha256sum1(rs1) \
    RISCV_INSTR_I_TYPE(0x13, 1, rs1, 0x101)

/* ── SHA-512 (Zknh, R-type) ────────────────────────────────────── */

/* σ0 high/low pair: rotr64(x,1) ^ rotr64(x,8) ^ (x >> 7) */
#define zk_sha512sig0h(rs1, rs2) \
    RISCV_INSTR_R_TYPE(0x33, 0, 0x2E, rs1, rs2)
#define zk_sha512sig0l(rs1, rs2) \
    RISCV_INSTR_R_TYPE(0x33, 0, 0x2A, rs1, rs2)

/* σ1 high/low pair: rotr64(x,19) ^ rotr64(x,61) ^ (x >> 6) */
#define zk_sha512sig1h(rs1, rs2) \
    RISCV_INSTR_R_TYPE(0x33, 0, 0x2F, rs1, rs2)
#define zk_sha512sig1l(rs1, rs2) \
    RISCV_INSTR_R_TYPE(0x33, 0, 0x2B, rs1, rs2)

/* Σ0 for compression: rotr64(a,28) ^ rotr64(a,34) ^ rotr64(a,39) */
#define zk_sha512sum0r(rs1, rs2) \
    RISCV_INSTR_R_TYPE(0x33, 0, 0x28, rs1, rs2)

/* Σ1 for compression: rotr64(e,14) ^ rotr64(e,18) ^ rotr64(e,41) */
#define zk_sha512sum1r(rs1, rs2) \
    RISCV_INSTR_R_TYPE(0x33, 0, 0x29, rs1, rs2)

/* ── SM3 (Zksh, I-type) ───────────────────────────────────────── */

/* sm3p0 rd, rs1 — P0: x ^ rotl(x,9) ^ rotl(x,17) */
#define zk_sm3p0(rs1) \
    RISCV_INSTR_I_TYPE(0x13, 1, rs1, 0x108)

/* sm3p1 rd, rs1 — P1: x ^ rotl(x,15) ^ rotl(x,23) */
#define zk_sm3p1(rs1) \
    RISCV_INSTR_I_TYPE(0x13, 1, rs1, 0x109)

#endif /* LOCAL_BUILD */
#endif /* CRYPTO_ZK_H */
