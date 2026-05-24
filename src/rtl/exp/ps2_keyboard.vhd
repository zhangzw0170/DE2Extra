-- 实验8：PS/2键盘扫描码显示器（流式设计）
-- PS/2时钟同步器 → 移位寄存器/状态机/奇偶校验 → 字节缓冲 → 7段译码
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity exp8_ps2_keyboard is
    port (
        CLOCK_50 : in  std_logic;
        PS2_CLK  : in  std_logic;
        PS2_DAT  : in  std_logic;
        HEX0     : out std_logic_vector(6 downto 0);
        HEX1     : out std_logic_vector(6 downto 0);
        HEX2     : out std_logic_vector(6 downto 0);
        HEX3     : out std_logic_vector(6 downto 0);
        HEX4     : out std_logic_vector(6 downto 0);
        HEX5     : out std_logic_vector(6 downto 0);
        HEX6     : out std_logic_vector(6 downto 0);
        HEX7     : out std_logic_vector(6 downto 0)
    );
end exp8_ps2_keyboard;

architecture structural of exp8_ps2_keyboard is
    component exp8_ps2_sync is
        port (
            clk      : in  std_logic;
            ps2_clk  : in  std_logic;
            ps2_dat  : in  std_logic;
            clk_fall : out std_logic;
            dat_sync : out std_logic
        );
    end component;

    component exp8_ps2_receiver is
        port (
            clk       : in  std_logic;
            clk_fall  : in  std_logic;
            dat_sync  : in  std_logic;
            scan_code : out std_logic_vector(7 downto 0);
            valid     : out std_logic
        );
    end component;

    component scan_code_buffer is
        port (
            clk        : in  std_logic;
            scan_code  : in  std_logic_vector(7 downto 0);
            valid      : in  std_logic;
            buf        : out std_logic_vector(31 downto 0);
            num_bytes  : out integer range 0 to 4;
            display_on : out std_logic
        );
    end component;

    component seg7_decoder is
        port (
            hex_val : in  std_logic_vector(3 downto 0);
            blank   : in  std_logic;
            seg_out : out std_logic_vector(6 downto 0)
        );
    end component;

    signal clk_fall    : std_logic;
    signal dat_sync    : std_logic;
    signal scan_code   : std_logic_vector(7 downto 0);
    signal rx_valid    : std_logic;
    signal disp_buf    : std_logic_vector(31 downto 0);
    signal disp_count  : integer range 0 to 4;
    signal disp_active : std_logic;
    signal blank_76    : std_logic;
    signal blank_54    : std_logic;
    signal blank_32    : std_logic;
begin
    u_sync : exp8_ps2_sync
        port map (clk => CLOCK_50, ps2_clk => PS2_CLK, ps2_dat => PS2_DAT,
                   clk_fall => clk_fall, dat_sync => dat_sync);

    u_rx : exp8_ps2_receiver
        port map (clk => CLOCK_50, clk_fall => clk_fall, dat_sync => dat_sync,
                   scan_code => scan_code, valid => rx_valid);

    u_buf : scan_code_buffer
        port map (clk => CLOCK_50, scan_code => scan_code, valid => rx_valid,
                   buf => disp_buf, num_bytes => disp_count,
                   display_on => disp_active);

    blank_76 <= '0' when disp_active = '1' and disp_count >= 4 else '1';
    blank_54 <= '0' when disp_active = '1' and disp_count >= 3 else '1';
    blank_32 <= '0' when disp_active = '1' and disp_count >= 2 else '1';

    u_hex7 : seg7_decoder port map (hex_val => disp_buf(31 downto 28), blank => blank_76, seg_out => HEX7);
    u_hex6 : seg7_decoder port map (hex_val => disp_buf(27 downto 24), blank => blank_76, seg_out => HEX6);
    u_hex5 : seg7_decoder port map (hex_val => disp_buf(23 downto 20), blank => blank_54, seg_out => HEX5);
    u_hex4 : seg7_decoder port map (hex_val => disp_buf(19 downto 16), blank => blank_54, seg_out => HEX4);
    u_hex3 : seg7_decoder port map (hex_val => disp_buf(15 downto 12), blank => blank_32, seg_out => HEX3);
    u_hex2 : seg7_decoder port map (hex_val => disp_buf(11 downto 8),  blank => blank_32, seg_out => HEX2);
    u_hex1 : seg7_decoder port map (hex_val => disp_buf(7 downto 4),   blank => not disp_active, seg_out => HEX1);
    u_hex0 : seg7_decoder port map (hex_val => disp_buf(3 downto 0),   blank => not disp_active, seg_out => HEX0);
end structural;
