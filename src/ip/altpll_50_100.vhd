-- altpll_50_100.vhd — PLL wrapper for DE2Extra
--
-- 50MHz input →
--   c0: 50MHz   (CPU, 0° phase)
--   c1: 100MHz  (SDRAM controller internal clock, 0° phase)
--   c2: 100MHz  (DRAM_CLK output, phase shifted for board-level setup margin)
--
-- 注意: 只改 c1 的相位没有意义，因为内部控制器和 DRAM_CLK 会一起平移。
-- 必须拆成“内部 100MHz”和“输出到 SDRAM 芯片的 100MHz 相移版”两路时钟。
library ieee;
use ieee.std_logic_1164.all;

library altera_mf;
use altera_mf.all;

entity altpll_50_100 is
    generic (
        -- 100MHz period = 10ns. A full 90° shift (2.496ns) pushed read data too
        -- far relative to the controller clock on DE2-115 hardware. Pull the
        -- external DRAM clock back to ~67.5° so write setup margin remains while
        -- the read-return window moves earlier.
        SDRAM_CLK_SHIFT_PS : string := "1560"
    );
    port (
        inclk0_i         : in  std_logic;    -- 50MHz input
        clk_50m_o        : out std_logic;    -- 50MHz output (CPU)
        clk_100m_o       : out std_logic;    -- 100MHz internal output (SDRAM controller)
        clk_100m_shift_o : out std_logic;    -- 100MHz shifted output (DRAM clock pin)
        locked_o         : out std_logic     -- PLL locked
    );
end entity altpll_50_100;

architecture rtl of altpll_50_100 is
    component altpll
    generic (
        bandwidth_type              : string;
        clk0_divide_by              : natural;
        clk0_duty_cycle             : natural;
        clk0_multiply_by            : natural;
        clk0_phase_shift            : string;
        clk1_divide_by              : natural;
        clk1_duty_cycle             : natural;
        clk1_multiply_by            : natural;
        clk1_phase_shift            : string;
        clk2_divide_by              : natural;
        clk2_duty_cycle             : natural;
        clk2_multiply_by            : natural;
        clk2_phase_shift            : string;
        compensate_clock            : string;
        inclk0_input_frequency      : natural;
        intended_device_family      : string;
        lpm_hint                    : string;
        lpm_type                    : string;
        operation_mode              : string;
        pll_type                    : string;
        port_activeclock            : string;
        port_areset                 : string;
        port_clkbad0                : string;
        port_clkbad1                : string;
        port_clkloss                : string;
        port_clkswitch              : string;
        port_configupdate           : string;
        port_fbin                   : string;
        port_inclk0                 : string;
        port_inclk1                 : string;
        port_locked                 : string;
        port_pfdena                 : string;
        port_phasecounterselect     : string;
        port_phasedone              : string;
        port_phasestep              : string;
        port_phaseupdown            : string;
        port_pllena                 : string;
        port_scanaclr               : string;
        port_scanclk                : string;
        port_scanclkena             : string;
        port_scandata               : string;
        port_scandataout            : string;
        port_scandone               : string;
        port_scanread               : string;
        port_scanwrite              : string;
        port_clk0                   : string;
        port_clk1                   : string;
        port_clk2                   : string;
        port_clk3                   : string;
        port_clk4                   : string;
        port_clk5                   : string;
        port_clkena0                : string;
        port_clkena1                : string;
        port_clkena2                : string;
        port_clkena3                : string;
        port_clkena4                : string;
        port_clkena5                : string;
        port_extclk0                : string;
        port_extclk1                : string;
        port_extclk2                : string;
        port_extclk3                : string;
        self_reset_on_loss_lock     : string;
        width_clock                 : natural
    );
    port (
        areset : in  std_logic;
        inclk  : in  std_logic_vector(1 downto 0);
        clk    : out std_logic_vector(4 downto 0);
        locked : out std_logic
    );
    end component;

    signal inclk_s : std_logic_vector(1 downto 0);
    signal clk_s   : std_logic_vector(4 downto 0);
begin

    inclk_s <= '0' & inclk0_i;

    clk_50m_o        <= clk_s(0);
    clk_100m_o       <= clk_s(1);
    clk_100m_shift_o <= clk_s(2);

    u_pll : altpll
    generic map (
        bandwidth_type            => "AUTO",
        clk0_divide_by            => 1,
        clk0_duty_cycle           => 50,
        clk0_multiply_by          => 1,
        clk0_phase_shift          => "0",
        clk1_divide_by            => 1,
        clk1_duty_cycle           => 50,
        clk1_multiply_by          => 2,
        clk1_phase_shift          => "0",
        clk2_divide_by            => 1,
        clk2_duty_cycle           => 50,
        clk2_multiply_by          => 2,
        clk2_phase_shift          => SDRAM_CLK_SHIFT_PS,
        compensate_clock          => "CLK0",
        inclk0_input_frequency    => 20000,
        intended_device_family    => "Cyclone IV E",
        lpm_hint                  => "CBX_MODULE_PREFIX=altpll_50_100",
        lpm_type                  => "altpll",
        operation_mode            => "NORMAL",
        pll_type                  => "AUTO",
        port_activeclock          => "PORT_UNUSED",
        port_areset               => "PORT_USED",
        port_clkbad0              => "PORT_UNUSED",
        port_clkbad1              => "PORT_UNUSED",
        port_clkloss              => "PORT_UNUSED",
        port_clkswitch            => "PORT_UNUSED",
        port_configupdate         => "PORT_UNUSED",
        port_fbin                 => "PORT_UNUSED",
        port_inclk0               => "PORT_USED",
        port_inclk1               => "PORT_UNUSED",
        port_locked               => "PORT_USED",
        port_pfdena               => "PORT_UNUSED",
        port_phasecounterselect   => "PORT_UNUSED",
        port_phasedone            => "PORT_UNUSED",
        port_phasestep            => "PORT_UNUSED",
        port_phaseupdown          => "PORT_UNUSED",
        port_pllena               => "PORT_UNUSED",
        port_scanaclr             => "PORT_UNUSED",
        port_scanclk              => "PORT_UNUSED",
        port_scanclkena           => "PORT_UNUSED",
        port_scandata             => "PORT_UNUSED",
        port_scandataout          => "PORT_UNUSED",
        port_scandone             => "PORT_UNUSED",
        port_scanread             => "PORT_UNUSED",
        port_scanwrite            => "PORT_UNUSED",
        port_clk0                 => "PORT_USED",
        port_clk1                 => "PORT_USED",
        port_clk2                 => "PORT_USED",
        port_clk3                 => "PORT_UNUSED",
        port_clk4                 => "PORT_UNUSED",
        port_clk5                 => "PORT_UNUSED",
        port_clkena0              => "PORT_UNUSED",
        port_clkena1              => "PORT_UNUSED",
        port_clkena2              => "PORT_UNUSED",
        port_clkena3              => "PORT_UNUSED",
        port_clkena4              => "PORT_UNUSED",
        port_clkena5              => "PORT_UNUSED",
        port_extclk0              => "PORT_UNUSED",
        port_extclk1              => "PORT_UNUSED",
        port_extclk2              => "PORT_UNUSED",
        port_extclk3              => "PORT_UNUSED",
        self_reset_on_loss_lock   => "OFF",
        width_clock               => 5
    )
    port map (
        areset => '0',
        inclk  => inclk_s,
        clk    => clk_s,
        locked => locked_o
    );

end architecture rtl;
