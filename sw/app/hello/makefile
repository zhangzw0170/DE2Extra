# DE2Extra — Hello World Makefile
# 复用 NEORV32 软件框架

# RISC-V ISA: IMC + Zfinx + Zicntr + Zbkb + Zbkc + Zbkx + Zknd + Zkne + Zknh + Zksed + Zksh
MARCH = rv32imc_zicsr_zicntr_zfinx_zbkb_zbkc_zbkx_zknd_zkne_zknh_zksed_zksh
MABI  = ilp32
EFFORT = -Os

# 内存配置 (需与 neorv32_wrapper generic 匹配)
USER_FLAGS += -Wl,--defsym,__neorv32_rom_size=32k
USER_FLAGS += -Wl,--defsym,__neorv32_ram_size=16k

# NEORV32 框架路径
NEORV32_HOME ?= ../../neorv32

# 引入 NEORV32 公共编译规则
include $(NEORV32_HOME)/sw/common/common.mk
