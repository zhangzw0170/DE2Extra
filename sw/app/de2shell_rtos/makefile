# DE2Extra — de2shell_rtos (FreeRTOS + de2shell programs, SDRAM execution)
#
# Build: via build.sh app/de2shell_rtos
#   or:  make exe NEORV32_HOME=../../neorv32  (inside Docker)

MARCH = rv32imc_zicsr_zicntr_zifencei
MABI  = ilp32
EFFORT = -Os

# RTOS build flag (moves large static pools to SDRAM)
USER_FLAGS += -DDE2SHELL_RTOS

# SDRAM execution — code at 0x01000000, data stays in DMEM
USER_FLAGS += -Wl,--defsym,__neorv32_rom_base=0x01000000
USER_FLAGS += -Wl,--defsym,__neorv32_rom_size=128M
USER_FLAGS += -Wl,--defsym,__neorv32_ram_size=16k
USER_FLAGS += -T de2shell_rtos.ld

# FreeRTOS kernel sources (from de2os)
FREERTOS_DIR  = ../de2os/freertos
PORT_DIR      = $(FREERTOS_DIR)/portable/GCC/RISC-V
CHIP_EXT_DIR  = $(PORT_DIR)/chip_specific_extensions/RISCV_MTIME_CLINT_no_extensions
MEMMANG_DIR   = $(FREERTOS_DIR)/portable/MemMang

# de2shell source directory
DE2SHELL_DIR = ../de2shell

# This app's own sources
APP_SRC  = $(filter-out ./chroma.c,$(wildcard ./*.c)) $(wildcard ./*.S)

# FreeRTOS kernel
APP_SRC += $(FREERTOS_DIR)/tasks.c
APP_SRC += $(FREERTOS_DIR)/queue.c
APP_SRC += $(FREERTOS_DIR)/list.c
APP_SRC += $(FREERTOS_DIR)/timers.c
APP_SRC += $(FREERTOS_DIR)/event_groups.c
APP_SRC += $(PORT_DIR)/port.c
APP_SRC += $(PORT_DIR)/portASM.S
APP_SRC += $(MEMMANG_DIR)/heap_4.c

# de2shell programs
APP_SRC += $(DE2SHELL_DIR)/hello.c
APP_SRC += $(DE2SHELL_DIR)/crypto.c
APP_SRC += $(DE2SHELL_DIR)/ps2.c
APP_SRC += $(DE2SHELL_DIR)/snake.c
APP_SRC += $(DE2SHELL_DIR)/life.c
APP_SRC += $(DE2SHELL_DIR)/info.c
APP_SRC += $(DE2SHELL_DIR)/monitor.c
APP_SRC += $(DE2SHELL_DIR)/demo.c
APP_SRC += $(DE2SHELL_DIR)/conway_hw.c
APP_SRC += $(DE2SHELL_DIR)/pong_hw.c
APP_SRC += $(DE2SHELL_DIR)/ntt.c
APP_SRC += $(DE2SHELL_DIR)/synth.c

# GUI + pixel mode (for Win 3.0 desktop)
APP_SRC += $(DE2SHELL_DIR)/fb_hal.c
APP_SRC += $(DE2SHELL_DIR)/gfx.c
APP_SRC += $(DE2SHELL_DIR)/gui.c
APP_SRC += $(DE2SHELL_DIR)/gui_widgets.c
APP_SRC += $(DE2SHELL_DIR)/twm.c
APP_SRC += $(DE2SHELL_DIR)/ps2_decoder.c

# de2shell HAL layer
APP_SRC += $(DE2SHELL_DIR)/vga_hal.c
APP_SRC += $(DE2SHELL_DIR)/gpio_hal.c
APP_SRC += $(DE2SHELL_DIR)/board_status.c
APP_SRC += $(DE2SHELL_DIR)/lcd_hal.c

# FreeRTOS+CLI
APP_SRC += ./FreeRTOS_CLI.c

# Crypto CLI sources (linked into de2shell)
APP_SRC += ../crypto_cli/crypto_aes.c
APP_SRC += ../crypto_cli/crypto_sha.c
APP_SRC += ../crypto_cli/crypto_sm.c

# Include paths
APP_INC  = -I . -I $(DE2SHELL_DIR)
APP_INC += -I $(FREERTOS_DIR)/include -I $(PORT_DIR) -I $(CHIP_EXT_DIR)
APP_INC += -I ../crypto_cli
ASM_INC  = -I . -I $(CHIP_EXT_DIR)

NEORV32_HOME ?= ../../neorv32

include $(NEORV32_HOME)/sw/common/common.mk
