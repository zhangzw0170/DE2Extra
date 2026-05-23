# DE2Extra — Phase 2a Crypto CLI Makefile
#
# Local build: make -f makefile local     → ./crypto_cli (native GCC, stdin/stdout)
# NEORV32:     ./sw/build.sh app/crypto_cli → IMEM image via Docker
#
# Source files:
#   main.c          CLI entry + command parser
#   crypto_aes.c    AES-128 ECB (NIST FIPS-197)
#   crypto_sha.c    SHA-256 / SHA-512 (NIST FIPS-180-4)
#   crypto_sm.c     SM4 / SM3 (GB/T 32907, GB/T 32905)

# ── NEORV32 target (default) ────────────────────────────────────
MARCH = rv32imc_zicsr_zicntr_zifencei_zfinx_zbkb_zbkc_zbkx_zknd_zkne_zknh_zksed_zksh
MABI  = ilp32
EFFORT = -Os
USER_FLAGS += -Wl,--defsym,__neorv32_rom_size=32k
USER_FLAGS += -Wl,--defsym,__neorv32_ram_size=16k
NEORV32_HOME ?= ../../neorv32
APP       ?= .
include $(NEORV32_HOME)/sw/common/common.mk

# ── Local native build ──────────────────────────────────────────
.PHONY: local local-test clean-local

local:
	gcc -DLOCAL_BUILD -Wall -O2 -o crypto_cli \
		main.c crypto_aes.c crypto_sha.c crypto_sm.c

local-test: local
	@echo "=== Running quick self-test ==="
	@echo "aes enc 2b7e151628aed2a6abf7158809cf4f3c 6bc1bee22e409f96e93d7e117393172a" | ./crypto_cli
	@echo "sha256 616263" | ./crypto_cli
	@echo "sha512 616263" | ./crypto_cli
	@echo "sm4 enc 0123456789abcdeffedcba9876543210 0123456789abcdeffedcba9876543210" | ./crypto_cli
	@echo "sm3 616263" | ./crypto_cli
	@echo "trng 32" | ./crypto_cli
	@echo "bench" | ./crypto_cli
	@echo "help" | ./crypto_cli
	@echo "info" | ./crypto_cli
	@echo "=== Done ==="

clean-local:
	rm -f crypto_cli crypto_cli.exe
