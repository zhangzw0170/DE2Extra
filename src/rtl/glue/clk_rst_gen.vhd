-- clk_rst_gen.vhd — 时钟和复位信号生成
--
-- Phase 0: 50MHz 直通 + 复位同步
-- Phase 2: 添加 PLL 生成 74.25MHz VGA 时钟
--
-- 换板子: 只需改这个文件
library ieee;
use ieee.std_logic_1164.all;

entity clk_rst_gen is
    port (
        clk_50m_i   : in  std_logic;   -- 板载 50MHz 晶振
        rst_key_n_i : in  std_logic;   -- KEY[0] 复位按键 (active-low)
        clk_50m_o   : out std_logic;   -- 50MHz CPU 时钟
        clk_vga_o   : out std_logic;   -- 74.25MHz VGA 时钟 (Phase 2, 当前直通)
        rst_n_o     : out std_logic    -- 同步复位输出 (active-low)
    );
end entity clk_rst_gen;

architecture rtl of clk_rst_gen is

    signal rst_sync   : std_logic_vector(2 downto 0);
    signal rst_n_int  : std_logic;

begin

    -- Phase 0: 时钟直通 (50MHz in = 50MHz out)
    -- Phase 2 将在此处实例化 ALTPLL IP:
    --   c0 = 50MHz (CPU)
    --   c1 = 74.25MHz (VGA)
    --   locked 信号接入复位逻辑
    clk_50m_o <= clk_50m_i;
    clk_vga_o <= clk_50m_i;  -- Phase 2: 替换为 PLL c1 输出

    -- 复位同步: 异步按键输入 → 同步到 clk_50m 时钟域
    -- 三级同步: 第一级消亚稳态, 后两级产生复位脉冲
    p_rst_sync : process (clk_50m_i, rst_key_n_i)
    begin
        if rst_key_n_i = '0' then
            rst_sync <= (others => '0');
        elsif rising_edge(clk_50m_i) then
            rst_sync <= rst_sync(1 downto 0) & '1';
        end if;
    end process p_rst_sync;

    -- 上电复位: 初始为 reset 状态
    -- rst_sync 初始为 "000", 3 个时钟周期后变为 "111"
    -- 复位信号 = NOT (全 1)
    rst_n_int <= rst_sync(2);
    rst_n_o   <= rst_n_int;

end architecture rtl;
