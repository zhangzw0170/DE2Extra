# DE2Extra — de2os (FreeRTOS + SDRAM execution)
#
# Build: via build.sh app/de2os
#   or:  make exe NEORV32_HOME=../../neorv32  (inside Docker)

MARCH = rv32imc_zicsr_zicntr_zifencei
MABI  = ilp32
EFFORT = -Os

# SDRAM execution — code at 0x01000000, data stays in DMEM
USER_FLAGS += -Wl,--defsym,__neorv32_rom_base=0x01000000
USER_FLAGS += -Wl,--defsym,__neorv32_rom_size=8M
USER_FLAGS += -Wl,--defsym,__neorv32_ram_size=16k
USER_FLAGS += -T de2os.ld

# FreeRTOS kernel sources
FREERTOS_DIR  = ./freertos
PORT_DIR      = $(FREERTOS_DIR)/portable/GCC/RISC-V
CHIP_EXT_DIR  = $(PORT_DIR)/chip_specific_extensions/RISCV_MTIME_CLINT_no_extensions
MEMMANG_DIR   = $(FREERTOS_DIR)/portable/MemMang

APP_SRC  = $(wildcard ./*.c) $(wildcard ./*.S)
APP_SRC += $(FREERTOS_DIR)/tasks.c
APP_SRC += $(FREERTOS_DIR)/queue.c
APP_SRC += $(FREERTOS_DIR)/list.c
APP_SRC += $(FREERTOS_DIR)/timers.c
APP_SRC += $(FREERTOS_DIR)/event_groups.c
APP_SRC += $(PORT_DIR)/port.c
APP_SRC += $(PORT_DIR)/portASM.S
APP_SRC += $(MEMMANG_DIR)/heap_4.c

APP_INC  = -I . -I $(FREERTOS_DIR)/include -I $(PORT_DIR) -I $(CHIP_EXT_DIR)
ASM_INC  = -I . -I $(CHIP_EXT_DIR)

NEORV32_HOME ?= ../../neorv32

include $(NEORV32_HOME)/sw/common/common.mk
