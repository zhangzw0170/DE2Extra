# DE2Extra — Conway's Game of Life Makefile
# Local:  gcc -DLOCAL_BUILD -o life main.c && ./life
# NEORV32: via sw/build.sh app/game_life

MARCH = rv32imc_zicsr_zicntr_zifencei
MABI  = ilp32
EFFORT = -Os
USER_FLAGS += -Wl,--defsym,__neorv32_rom_size=32k
USER_FLAGS += -Wl,--defsym,__neorv32_ram_size=16k
NEORV32_HOME ?= ../../neorv32
APP       ?= .
include $(NEORV32_HOME)/sw/common/common.mk

.PHONY: local local-test clean-local

local:
	gcc -DLOCAL_BUILD -Wall -O2 -o life main.c

clean-local:
	rm -f life life.exe
