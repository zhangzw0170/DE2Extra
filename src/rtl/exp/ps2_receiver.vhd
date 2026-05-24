-- PS/2接收器：移位寄存器 + 状态机 + 奇偶校验
-- 接收11位PS/2帧，校验停止位和奇偶校验位，输出8位扫描码
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity exp8_ps2_receiver is
    port (
        clk       : in  std_logic;
        clk_fall  : in  std_logic;
        dat_sync  : in  std_logic;
        scan_code : out std_logic_vector(7 downto 0);
        valid     : out std_logic
    );
end exp8_ps2_receiver;

architecture rtl of exp8_ps2_receiver is
    type state_t is (IDLE, RECEIVING);
    signal state     : state_t := IDLE;
    signal bit_cnt   : integer range 0 to 10 := 0;
    signal shift_reg : std_logic_vector(10 downto 0) := (others => '1');
begin
    process(clk)
        variable parity_v : std_logic;
    begin
        if clk'event and clk = '1' then
            valid <= '0';

            -- PS/2时钟下降沿时接收数据
            if clk_fall = '1' then
                case state is
                    when IDLE =>
                        if dat_sync = '0' then  -- 起始位
                            state   <= RECEIVING;
                            bit_cnt <= 0;
                        end if;
                    when RECEIVING =>
                        shift_reg <= dat_sync & shift_reg(10 downto 1);
                        if bit_cnt = 9 then      -- 接收完10位（D0-D7 + 校验 + 停止）
                            state <= IDLE;
                        else
                            bit_cnt <= bit_cnt + 1;
                        end if;
                end case;
            end if;

            -- 帧接收完成：校验停止位和奇偶校验
            if state = IDLE and bit_cnt = 9 then
                if shift_reg(10) = '1' then  -- 停止位 = 1
                    -- 奇校验：D0^D1^...^D7^P = 1
                    parity_v := shift_reg(1) xor shift_reg(2) xor shift_reg(3)
                                xor shift_reg(4) xor shift_reg(5) xor shift_reg(6)
                                xor shift_reg(7) xor shift_reg(8) xor shift_reg(9);
                    if parity_v = '1' then
                        scan_code <= shift_reg(8 downto 1);
                        valid     <= '1';
                    end if;
                end if;
                bit_cnt <= 0;  -- 清除，防止重复触发
            end if;
        end if;
    end process;
end rtl;
