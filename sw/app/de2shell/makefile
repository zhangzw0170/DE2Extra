# DE2Extra — Unified Shell Makefile
# Local:  make local (needs SDL2 via scoop)
# NEORV32: via sw/build.sh app/de2shell

MARCH = rv32imc_zicsr_zicntr_zifencei
MABI  = ilp32
EFFORT = -Os
USER_FLAGS += -Wl,--defsym,__neorv32_rom_size=64k
USER_FLAGS += -Wl,--defsym,__neorv32_ram_size=16k
USER_FLAGS += -flto -fno-fat-lto-objects
USER_FLAGS += -fno-unwind-tables -fno-asynchronous-unwind-tables
USER_FLAGS += -msave-restore -Wl,--relax
APP_SRC = $(filter-out ./fb_test.c ./ntt.c ./screenshot_win30.c,$(wildcard ./*.c)) $(wildcard ./*.s) $(wildcard ./*.cpp) $(wildcard ./*.S)
APP_SRC += ../crypto_cli/crypto_aes.c ../crypto_cli/crypto_sha.c ../crypto_cli/crypto_sm.c
APP_INC = -I . -I ../crypto_cli
NEORV32_HOME ?= ../../neorv32
APP       ?= .
ifneq ($(filter local clean-local,$(MAKECMDGOALS)),)
else
include $(NEORV32_HOME)/sw/common/common.mk
endif

# SDL2 paths (scoop install sdl2)
SDL2_ROOT := $(shell scoop prefix sdl2 2>/dev/null)
SDL2_INC  ?= $(SDL2_ROOT)/include/SDL2
SDL2_LIB  ?= $(SDL2_ROOT)/lib

.PHONY: local clean-local

local:
	gcc -DLOCAL_BUILD -Wall -O2 -I . -I ../crypto_cli -I "$(SDL2_INC)" -o de2shell main.c board_status.c lcd_hal.c vga_hal.c gpio_hal.c fb_hal.c gfx.c gui.c gui_widgets.c win30_desk.c ps2_decoder.c hello.c memtest.c crypto.c ps2.c snake.c life.c dashboard.c info.c monitor.c demo.c ../crypto_cli/crypto_aes.c ../crypto_cli/crypto_sha.c ../crypto_cli/crypto_sm.c -L "$(SDL2_LIB)" -lmingw32 -lSDL2main -lSDL2

clean-local:
	rm -f de2shell de2shell.exe
