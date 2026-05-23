# DE2Extra — Unified Shell Makefile
# Local:  gcc -DLOCAL_BUILD -o de2shell *.c && ./de2shell
# NEORV32: via sw/build.sh app/de2shell

MARCH = rv32imc_zicsr_zicntr_zifencei
MABI  = ilp32
EFFORT = -Os
USER_FLAGS += -Wl,--defsym,__neorv32_rom_size=64k
USER_FLAGS += -Wl,--defsym,__neorv32_ram_size=16k
APP_SRC = $(wildcard ./*.c) $(wildcard ./*.s) $(wildcard ./*.cpp) $(wildcard ./*.S)
APP_SRC += ../crypto_cli/crypto_aes.c ../crypto_cli/crypto_sha.c ../crypto_cli/crypto_sm.c
APP_INC = -I . -I ../crypto_cli
NEORV32_HOME ?= ../../neorv32
APP       ?= .
include $(NEORV32_HOME)/sw/common/common.mk

.PHONY: local clean-local

local:
	gcc -DLOCAL_BUILD -Wall -O2 -I . -I ../crypto_cli -o de2shell main.c vga_hal.c gpio_hal.c hello.c memtest.c crypto.c ps2.c snake.c life.c dashboard.c info.c exp1.c exp4.c exp5.c exp12.c monitor.c ../crypto_cli/crypto_aes.c ../crypto_cli/crypto_sha.c ../crypto_cli/crypto_sm.c

clean-local:
	rm -f de2shell de2shell.exe
