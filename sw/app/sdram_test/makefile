MARCH = rv32imc_zicsr_zicntr_zifencei_zfinx_zbkb_zbkc_zbkx_zknd_zkne_zknh_zksed_zksh
MABI  = ilp32
EFFORT = -Os
USER_FLAGS += -Wl,--defsym,__neorv32_rom_size=32k
USER_FLAGS += -Wl,--defsym,__neorv32_ram_size=16k
NEORV32_HOME ?= ../../neorv32
include $(NEORV32_HOME)/sw/common/common.mk
