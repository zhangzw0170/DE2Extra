-- 实验11：DDS频率合成器
-- 20位相位累加器（2位区间 + 10位地址 + 8位fword）
-- lpm_rom + mif（1024×10bit，只存0~π/2，ROM压缩）
-- 50MHz输入，分频50倍→1MHz供DDS使用
-- f₀ = 1MHz/4 × fword / 2^18
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;

entity DDS is
    port (
        fword : in  std_logic_vector(7 downto 0);   -- 频率控制字
        clk   : in  std_logic;                      -- 系统时钟 50MHz
        rst   : in  std_logic;                      -- 复位信号（低电平有效）
        mode  : in  std_logic;                      -- 模式切换：0=慢速LED观察，1=快速SignalTap抓波形
        dout  : out std_logic_vector(9 downto 0)     -- 10位幅度值输出
    );
end DDS;

architecture behavioral of DDS is
    component DDS_ROM
        port (
            address : in  std_logic_vector(9 downto 0);
            clock   : in  std_logic;
            q       : out std_logic_vector(9 downto 0)
        );
    end component;

    -- 时钟分频：50MHz / 500 = 100kHz
    signal div_cnt : integer range 0 to 249 := 0;
    signal clk_1m  : std_logic := '0';

    -- 20位相位累加器: [19:18]区间, [17:8]ROM地址, [7:0]fword增量
    signal phase_acc : std_logic_vector(19 downto 0) := (others => '0');

    -- ROM接口
    signal rom_addr : std_logic_vector(9 downto 0);
    signal rom_q    : std_logic_vector(9 downto 0);

    -- 区间译码
    signal quadrant   : std_logic_vector(1 downto 0);
    signal addr_raw   : std_logic_vector(9 downto 0);
    signal addr_flip  : std_logic_vector(9 downto 0);
    signal dout_int   : std_logic_vector(9 downto 0);

    -- DDS实际工作信号
    signal dds_clk    : std_logic;
    signal fword_eff  : std_logic_vector(19 downto 0);
begin
    -- 模式选择：慢速（LED观察）或快速（SignalTap）
    -- mode=0: 100kHz时钟, fword不变 → f₀ ≈ 0.1Hz@fword=1
    -- mode=1: 50MHz直连, fword左移8位 → f₀ = fword × 12kHz, fword=5时约5周期/4096样本
    dds_clk   <= clk_1m when mode = '0' else clk;
    fword_eff <= x"000" & fword when mode = '0' else x"0" & fword & x"00";

    -- 50MHz → 100kHz 分频器
    process(clk)
    begin
        if clk'event and clk = '1' then
            if rst = '0' then
                div_cnt <= 0;
                clk_1m  <= '0';
            elsif div_cnt = 249 then
                div_cnt <= 0;
                clk_1m  <= not clk_1m;
            else
                div_cnt <= div_cnt + 1;
            end if;
        end if;
    end process;

    -- 相位累加器
    process(dds_clk, rst)
    begin
        if rst = '0' then
            phase_acc <= (others => '0');
        elsif dds_clk'event and dds_clk = '1' then
            phase_acc <= phase_acc + fword_eff;
        end if;
    end process;

    -- 区间: phase_acc[19:18]
    quadrant <= phase_acc(19 downto 18);

    -- ROM地址: phase_acc[17:8]
    addr_raw <= phase_acc(17 downto 8);

    -- ROM压缩：区间π/2~π需要地址取反 (3FF - x)
    addr_flip <= not addr_raw;

    -- 根据区间选择ROM地址
    rom_addr <= addr_flip when quadrant = "01" or quadrant = "11" else addr_raw;

    -- lpm_rom实例化（Quartus MegaFunction，需在Qsys/IP Catalog中生成）
    u_rom : DDS_ROM
        port map(
            address => rom_addr,
            clock   => dds_clk,
            q       => rom_q
        );

    -- 原始正弦输出（含正负半周，补码表示，供SignalTap抓取）

    -- 条形图显示：rom_q(0~1023) → 10-LED温度计码
    -- 每个LED约覆盖1024/10≈102个幅度值
    -- rom_q始终为正半周值，bar自然呈现全波整流正弦包络
    process(rom_q)
    begin
        dout_int <= (others => '0');
        if rom_q > "0001100110" then dout_int(0) <= '1'; end if;  -- > 102
        if rom_q > "0011001101" then dout_int(1) <= '1'; end if;  -- > 205
        if rom_q > "0100110011" then dout_int(2) <= '1'; end if;  -- > 307
        if rom_q > "0110011010" then dout_int(3) <= '1'; end if;  -- > 410
        if rom_q > "1000000000" then dout_int(4) <= '1'; end if;  -- > 512
        if rom_q > "1001100110" then dout_int(5) <= '1'; end if;  -- > 614
        if rom_q > "1011001101" then dout_int(6) <= '1'; end if;  -- > 717
        if rom_q > "1100110011" then dout_int(7) <= '1'; end if;  -- > 819
        if rom_q > "1110011010" then dout_int(8) <= '1'; end if;  -- > 922
        if rom_q > "1111111110" then dout_int(9) <= '1'; end if;  -- > 1022
    end process;

    -- mode=0: LED条形图显示; mode=1: 直接输出rom_q供SignalTap抓取
    dout <= dout_int when mode = '0' else rom_q;
end behavioral;
