-- altpll_audio.vhd — Audio PLL for WM8731
--
-- 50 MHz input → 18 MHz output (c0)
-- Matches Terasic DE2-115 Synthesizer reference:
--   18 MHz × 18 / (1 × 50) = 18 MHz
--   VCO = 900 MHz (within Cyclone IV E 600-1300 MHz range)
--
-- WM8731: MCLK = 18 MHz, BOSR=1 (384fs) → 18M/384 = 46.875 kHz
library ieee;
use ieee.std_logic_1164.all;

library altera_mf;
use altera_mf.all;

entity altpll_audio is
    port (
        inclk0_i : in  std_logic;   -- 50 MHz
        clk_18m_o: out std_logic;   -- 18 MHz
        locked_o  : out std_logic
    );
end entity altpll_audio;

architecture rtl of altpll_audio is
    component altpll
    generic (
        bandwidth_type              : string;
        clk0_divide_by              : natural;
        clk0_duty_cycle             : natural;
        clk0_multiply_by            : natural;
        clk0_phase_shift            : string;
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
    clk_18m_o <= clk_s(0);

    u_pll : altpll
    generic map (
        bandwidth_type            => "AUTO",
        clk0_divide_by            => 50,
        clk0_duty_cycle           => 50,
        clk0_multiply_by          => 18,
        clk0_phase_shift          => "0",
        compensate_clock          => "CLK0",
        inclk0_input_frequency    => 20000,
        intended_device_family    => "Cyclone IV E",
        lpm_hint                  => "CBX_MODULE_PREFIX=altpll_audio",
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
        port_clk1                 => "PORT_UNUSED",
        port_clk2                 => "PORT_UNUSED",
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
