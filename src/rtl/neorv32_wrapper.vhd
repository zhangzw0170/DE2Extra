-- neorv32_wrapper.vhd — NEORV32 CPU 配置封装
--
-- 平台无关的 CPU 封装，隔离 NEORV32 的 55 个 generic 配置。
-- 换 CPU: 只需改这个文件的 architecture body。
--
-- std_logic 外部接口 ←→ std_ulogic NEORV32 内部接口 的类型转换在此完成。
library ieee;
use ieee.std_logic_1164.all;

library neorv32;
use neorv32.neorv32_package.all;

entity neorv32_wrapper is
    generic (
        CLOCK_FREQUENCY : natural := 50_000_000;
        IMEM_SIZE       : natural := 32*1024;   -- 指令内存 (bytes, power of 2)
        DMEM_SIZE       : natural := 16*1024;   -- 数据内存 (bytes, power of 2)
        BOOT_MODE       : natural := 2          -- 0=bootloader, 2=IMEM image
    );
    port (
        -- Clock and reset
        clk_i       : in  std_logic;
        rst_n_i     : in  std_logic;
        -- UART0
        uart_txd_o  : out std_logic;
        uart_rxd_i  : in  std_logic;
        -- GPIO
        gpio_o      : out std_logic_vector(31 downto 0);
        gpio_i      : in  std_logic_vector(31 downto 0);
        -- JTAG debug (直接连接 USB-Blaster)
        jtag_tck_i  : in  std_logic;
        jtag_tdi_i  : in  std_logic;
        jtag_tdo_o  : out std_logic;
        jtag_tms_i  : in  std_logic;
        -- XBUS (Wishbone 外部总线, Phase 1 使用)
        xbus_adr_o  : out std_logic_vector(31 downto 0);
        xbus_dat_o  : out std_logic_vector(31 downto 0);
        xbus_dat_i  : in  std_logic_vector(31 downto 0);
        xbus_we_o   : out std_logic;
        xbus_sel_o  : out std_logic_vector(3 downto 0);
        xbus_stb_o  : out std_logic;
        xbus_cyc_o  : out std_logic;
        xbus_ack_i  : in  std_logic;
        xbus_err_i  : in  std_logic
    );
end entity neorv32_wrapper;

architecture rtl of neorv32_wrapper is

    -- NEORV32 内部信号 (std_ulogic 系列)
    signal rstn_ocd       : std_ulogic;
    signal rstn_wdt       : std_ulogic;
    signal xbus_adr_suv   : std_ulogic_vector(31 downto 0);
    signal xbus_dat_suv   : std_ulogic_vector(31 downto 0);
    signal xbus_we_sul    : std_ulogic;
    signal xbus_sel_suv   : std_ulogic_vector(3 downto 0);
    signal xbus_stb_sul   : std_ulogic;
    signal xbus_cyc_sul   : std_ulogic;
    signal gpio_suv       : std_ulogic_vector(31 downto 0);
    signal uart_txd_sul   : std_ulogic;
    signal jtag_tdo_sul   : std_ulogic;

begin

    -- 类型转换: std_ulogic → std_logic (输出方向)
    xbus_adr_o  <= std_logic_vector(xbus_adr_suv);
    xbus_dat_o  <= std_logic_vector(xbus_dat_suv);
    xbus_we_o   <= xbus_we_sul;
    xbus_sel_o  <= std_logic_vector(xbus_sel_suv);
    xbus_stb_o  <= xbus_stb_sul;
    xbus_cyc_o  <= xbus_cyc_sul;
    gpio_o      <= std_logic_vector(gpio_suv);
    uart_txd_o  <= uart_txd_sul;
    jtag_tdo_o  <= jtag_tdo_sul;

    -- ================================================================
    -- NEORV32 实例化 — 所有 ISA 和外设配置集中在此
    -- ================================================================
    u_neorv32 : entity neorv32.neorv32_top
    generic map (
        -- General --
        CLOCK_FREQUENCY      => CLOCK_FREQUENCY,
        TRACE_PORT_EN        => false,
        DUAL_CORE_EN         => false,

        -- Boot --
        BOOT_MODE_SELECT     => BOOT_MODE,
        BOOT_ADDR_CUSTOM     => x"00000000",

        -- On-Chip Debugger --
        OCD_EN               => true,
        OCD_NUM_HW_TRIGGERS  => 2,
        OCD_AUTHENTICATION   => false,
        OCD_JEDEC_ID         => "00000000000",

        -- RISC-V ISA Extensions --
        RISCV_ISA_C          => true,    -- 压缩指令
        RISCV_ISA_E          => false,
        RISCV_ISA_M          => true,    -- 乘除法
        RISCV_ISA_U          => false,
        RISCV_ISA_Zaamo      => false,
        RISCV_ISA_Zalrsc     => false,
        RISCV_ISA_Zba        => false,
        RISCV_ISA_Zbb        => false,
        RISCV_ISA_Zbc        => false,
        RISCV_ISA_Zbkb       => true,    -- Crypto bit-manipulation
        RISCV_ISA_Zbkc       => true,    -- Crypto carry-less multiply
        RISCV_ISA_Zbkx       => true,    -- Crypto crossbar permutation
        RISCV_ISA_Zbs        => false,
        RISCV_ISA_Zcb        => false,
        RISCV_ISA_Zfinx      => true,    -- 浮点 (x-register ABI)
        RISCV_ISA_Zibi       => false,
        RISCV_ISA_Zicntr     => true,    -- 基础计数器
        RISCV_ISA_Zicond     => false,
        RISCV_ISA_Zihpm      => false,
        RISCV_ISA_Zimop      => false,
        RISCV_ISA_Zknd       => true,    -- AES 解密
        RISCV_ISA_Zkne       => true,    -- AES 加密
        RISCV_ISA_Zknh       => true,    -- SHA-256/512
        RISCV_ISA_Zksed      => true,    -- SM4 (国密)
        RISCV_ISA_Zksh       => true,    -- SM3 (国密)
        RISCV_ISA_Zmmul      => false,
        RISCV_ISA_Smcntrpmf  => false,
        RISCV_ISA_Xcfu       => false,   -- 自定义指令 (Phase 4+)

        -- CPU Tuning --
        CPU_CONSTT_BR_EN     => false,
        CPU_FAST_MUL_EN      => true,    -- 使用 DSP 做乘法
        CPU_FAST_SHIFT_EN    => true,    -- 桶形移位器
        CPU_RF_ARCH_SEL      => 0,       -- 默认寄存器文件

        -- PMP --
        PMP_NUM_REGIONS      => 0,
        PMP_MIN_GRANULARITY  => 4,
        PMP_TOR_MODE_EN      => false,
        PMP_NAP_MODE_EN      => false,

        -- HPM --
        HPM_NUM_CNTS         => 0,
        HPM_CNT_WIDTH        => 64,

        -- IMEM --
        IMEM_EN              => true,
        IMEM_BASE            => x"00000000",
        IMEM_SIZE            => IMEM_SIZE,
        IMEM_OUTREG_EN       => false,

        -- DMEM --
        DMEM_EN              => true,
        DMEM_BASE            => x"80000000",
        DMEM_SIZE            => DMEM_SIZE,
        DMEM_OUTREG_EN       => false,

        -- Cache --
        ICACHE_EN            => false,   -- Phase 0 不需要
        DCACHE_EN            => false,

        -- XBUS --
        XBUS_EN              => true,    -- Phase 1 接 SDRAM + 外设
        XBUS_TIMEOUT         => 2048,
        XBUS_REGSTAGE_EN     => true,    -- 改善时序

        -- GPIO --
        IO_GPIO_NUM          => 32,
        IO_GPIO_DIR_EN       => true,

        -- CLINT --
        IO_CLINT_EN          => false,   -- FreeRTOS 用自定义 timer

        -- UART --
        IO_UART0_EN          => true,
        IO_UART0_RX_FIFO     => 32,
        IO_UART0_TX_FIFO     => 32,
        IO_UART1_EN          => false,

        -- SPI --
        IO_SPI_EN            => false,
        IO_SDI_EN            => false,

        -- TWI (I2C) --
        IO_TWI_EN            => false,
        IO_TWD_EN            => false,

        -- PWM --
        IO_PWM_NUM           => 0,

        -- WDT --
        IO_WDT_EN            => false,

        -- TRNG --
        IO_TRNG_EN           => true,
        IO_TRNG_FIFO         => 4,
        IO_TRNG_NUM_RO       => 3,
        IO_TRNG_NUM_INV      => 5,
        IO_TRNG_NUM_RBIT     => 64,

        -- CFS --
        IO_CFS_EN            => false,

        -- NEOLED --
        IO_NEOLED_EN         => false,

        -- GPTMR --
        IO_GPTMR_NUM         => 0,

        -- ONEWIRE --
        IO_ONEWIRE_EN        => false,

        -- DMA --
        IO_DMA_EN            => false,

        -- SLINK --
        IO_SLINK_EN          => false,

        -- TRACER --
        IO_TRACER_EN         => false
    )
    port map (
        -- Global control
        clk_i          => std_ulogic(clk_i),
        rstn_i         => std_ulogic(rst_n_i),
        rstn_ocd_o     => rstn_ocd,
        rstn_wdt_o     => rstn_wdt,

        -- JTAG debug
        jtag_tck_i     => std_ulogic(jtag_tck_i),
        jtag_tdi_i     => std_ulogic(jtag_tdi_i),
        jtag_tdo_o     => jtag_tdo_sul,
        jtag_tms_i     => std_ulogic(jtag_tms_i),

        -- XBUS
        xbus_adr_o     => xbus_adr_suv,
        xbus_dat_o     => xbus_dat_suv,
        xbus_dat_i     => std_ulogic_vector(xbus_dat_i),
        xbus_we_o      => xbus_we_sul,
        xbus_sel_o     => xbus_sel_suv,
        xbus_stb_o     => xbus_stb_sul,
        xbus_cyc_o     => xbus_cyc_sul,
        xbus_ack_i     => std_ulogic(xbus_ack_i),
        xbus_err_i     => std_ulogic(xbus_err_i),

        -- GPIO
        gpio_o         => gpio_suv,
        gpio_i         => std_ulogic_vector(gpio_i),

        -- UART0
        uart0_txd_o    => uart_txd_sul,
        uart0_rxd_i    => std_ulogic(uart_rxd_i)
    );

end architecture rtl;
