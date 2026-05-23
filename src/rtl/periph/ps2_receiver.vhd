-- ps2_receiver.vhd — PS/2 字节接收器
-- 来源: Exp8 (已验收)
-- 11位帧 (start+D0..D7+parity+stop)，奇校验，校验失败丢弃
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity ps2_receiver is
    port (
        clk       : in  std_logic;
        enable_i  : in  std_logic;
        clk_fall  : in  std_logic;   -- PS2_CLK 下降沿
        dat_sync  : in  std_logic;   -- 同步后的数据
        scan_code : out std_logic_vector(7 downto 0);
        valid     : out std_logic    -- 单周期脉冲
    );
end ps2_receiver;

architecture rtl of ps2_receiver is
    type state_t is (IDLE, RECEIVING);
    signal state     : state_t := IDLE;
    signal bit_cnt   : integer range 0 to 10 := 0;
    signal shift_reg : std_logic_vector(10 downto 0) := (others => '1');
begin
    process(clk)
        variable parity_v : std_logic;
    begin
        if rising_edge(clk) then
            valid <= '0';

            if enable_i = '0' then
                state     <= IDLE;
                bit_cnt   <= 0;
                shift_reg <= (others => '1');
            else
                if clk_fall = '1' then
                    case state is
                        when IDLE =>
                            if dat_sync = '0' then   -- 起始位
                                state   <= RECEIVING;
                                bit_cnt <= 0;
                            end if;
                        when RECEIVING =>
                            shift_reg <= dat_sync & shift_reg(10 downto 1);
                            if bit_cnt = 9 then       -- 接收完 10 位
                                state <= IDLE;
                            else
                                bit_cnt <= bit_cnt + 1;
                            end if;
                    end case;
                end if;

                -- 帧接收完成: 校验停止位 + 奇偶校验
                if state = IDLE and bit_cnt = 9 then
                    if shift_reg(10) = '1' then        -- 停止位 = 1
                        parity_v := shift_reg(1) xor shift_reg(2) xor shift_reg(3)
                            xor shift_reg(4) xor shift_reg(5) xor shift_reg(6)
                            xor shift_reg(7) xor shift_reg(8) xor shift_reg(9);
                        if parity_v = '1' then          -- 奇校验通过
                            scan_code <= shift_reg(8 downto 1);
                            valid     <= '1';
                        end if;
                    end if;
                    bit_cnt <= 0;
                end if;
            end if;
        end if;
    end process;
end rtl;
