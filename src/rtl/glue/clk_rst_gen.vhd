-- clk_rst_gen.vhd — 时钟和复位信号生成
--
-- Phase 1: PLL 生成 50MHz (CPU) + 100MHz (SDRAM)
-- Phase 2: 添加 74.25MHz VGA 时钟
--
-- 换板子: 只需改这个文件
library ieee;
use ieee.std_logic_1164.all;

entity clk_rst_gen is
    port (
        clk_50m_i    : in  std_logic;   -- 板载 50MHz 晶振
        rst_key_n_i  : in  std_logic;   -- KEY[0] 复位按键 (active-low)
        clk_50m_o    : out std_logic;   -- 50MHz CPU 时钟
        clk_sdram_o  : out std_logic;   -- 100MHz SDRAM 时钟
        clk_sdram_shift_o : out std_logic; -- 100MHz SDRAM 引脚时钟 (相移版)
        clk_vga_o    : out std_logic;   -- 74.25MHz VGA 时钟 (Phase 2, 当前直通)
        rst_n_o      : out std_logic;   -- 同步复位输出 (active-low)
        pll_locked_o : out std_logic    -- PLL 锁定状态
    );
end entity clk_rst_gen;

architecture rtl of clk_rst_gen is

    signal rst_sync   : std_logic_vector(2 downto 0);
    signal rst_n_int  : std_logic;
    signal pll_locked : std_logic;

begin

    -- ================================================================
    -- PLL: 50MHz → 50MHz (CPU) + 100MHz internal + 100MHz shifted DRAM clock
    -- ================================================================
    u_pll : entity work.altpll_50_100
    port map (
        inclk0_i         => clk_50m_i,
        clk_50m_o        => clk_50m_o,
        clk_100m_o       => clk_sdram_o,
        clk_100m_shift_o => clk_sdram_shift_o,
        locked_o         => pll_locked
    );

    pll_locked_o <= pll_locked;

    -- VGA 时钟: Phase 2 替换为 PLL c2 输出
    clk_vga_o <= clk_50m_i;

    -- ================================================================
    -- 复位同步: 按键 + PLL locked 联合复位
    -- ================================================================
    -- 异步按键输入 → 同步到 clk_50m 时钟域
    -- 按键按下 或 PLL 未锁定 → 复位
    p_rst_sync : process (clk_50m_i, rst_key_n_i)
    begin
        if rst_key_n_i = '0' then
            rst_sync <= (others => '0');
        elsif rising_edge(clk_50m_i) then
            rst_sync <= rst_sync(1 downto 0) & '1';
        end if;
    end process p_rst_sync;

    rst_n_int <= rst_sync(2);
    rst_n_o   <= rst_n_int and pll_locked;

end architecture rtl;
