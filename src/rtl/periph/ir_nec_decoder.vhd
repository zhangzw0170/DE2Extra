-- ir_nec_decoder.vhd — NEC 红外遥控解码器 (uPD6121G 协议)
-- 来源: Exp10 (已验收)
--
-- NEC 协议: 9ms LOW + 4.5ms HIGH 引导码 → 32-bit 数据
--   [31:24]=高地址 [23:16]=低地址 [15:8]=命令 [7:0]=命令反码
--   校验: 数据码 vs 数据反码 (地址码无校验)
--   重复码: 9ms LOW + 2.25ms HIGH (不包含数据)
--
-- 输出:
--   cmd[7:0]      — 解码后的命令码 (bit-reversed from wire)
--   addr[15:0]    — 地址码 (通常 0x0001)
--   valid         — 单周期脉冲, 命令解码成功
--   repeat        — 单周期脉冲, 检测到重复码
--   cmd_count[7:0] — 成功解码累计次数 (0-99)

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use IEEE.NUMERIC_STD.ALL;

entity ir_nec_decoder is
    port (
        clk_i        : in  std_logic;
        rst_n_i      : in  std_logic;
        irda_rxd_i   : in  std_logic;   -- IR 接收器 (PIN_Y15 on DE2-115)

        -- 解码输出
        cmd_o        : out std_logic_vector(7 downto 0);
        addr_o       : out std_logic_vector(15 downto 0);
        valid_o      : out std_logic;   -- 命令解码完成 (单周期脉冲)
        repeat_o     : out std_logic;   -- 重复码检测 (单周期脉冲)
        cmd_count_o  : out std_logic_vector(7 downto 0)  -- 累计次数 0-99
    );
end ir_nec_decoder;

architecture rtl of ir_nec_decoder is

    -- IR 信号同步 (2级触发器, 抗亚稳态)
    signal ir_sync   : std_logic_vector(2 downto 0) := "111";
    signal ir_fall   : std_logic;   -- IR 下降沿

    -- 下降沿间隔计数器 (50MHz → 20ns/tick, 最大 2^21 ≈ 42ms)
    constant US_MAX  : integer := 2000000;
    signal edge_cnt  : integer range 0 to US_MAX := 0;

    -- NEC 脉宽参数 (50MHz ticks)
    --   引导码: 9ms + 4.5ms = 13.5ms = 675000 ticks
    --   逻辑0:  0.56ms + 0.56ms = 1.12ms = 56000 ticks
    --   逻辑1:  0.56ms + 1.69ms = 2.25ms = 112500 ticks
    --   重复码: 9ms + 2.25ms = 11.25ms = 562500 ticks
    constant NEC_LEADER  : integer := 675000;   -- 13.5ms
    constant NEC_BIT_0   : integer := 56000;     -- 1.12ms
    constant NEC_BIT_1   : integer := 112500;    -- 2.25ms
    constant NEC_REPEAT  : integer := 562500;    -- 11.25ms

    -- 容差比例: 引导码 ±20%, bit0 ±33%, bit1 ±20%
    constant TOL_LEADER  : integer := NEC_LEADER / 5;
    constant TOL_BIT0    : integer := NEC_BIT_0  / 3;
    constant TOL_BIT1    : integer := NEC_BIT_1  / 5;
    constant TOL_REPEAT  : integer := NEC_REPEAT / 5;

    -- 状态机
    type state_t is (S_IDLE, S_DATA);
    signal state     : state_t := S_IDLE;
    signal bit_cnt   : integer range 0 to 31 := 0;
    signal shift_reg : std_logic_vector(31 downto 0) := (others => '0');

    -- 解码结果
    signal ir_cmd    : std_logic_vector(7 downto 0)  := (others => '0');
    signal ir_addr   : std_logic_vector(15 downto 0) := (others => '0');
    signal ir_valid  : std_logic := '0';
    signal ir_repeat : std_logic := '0';

    -- 累计次数
    signal cmd_count : integer range 0 to 99 := 0;

    -- 8位 bit-reverse: NEC 是 LSB-first, shift_reg 中字节需要反转
    function bit_rev8(v : std_logic_vector(7 downto 0)) return std_logic_vector is
        variable r : std_logic_vector(7 downto 0);
    begin
        for i in 0 to 7 loop
            r(i) := v(7 - i);
        end loop;
        return r;
    end function;

begin

    -- ============================================================
    -- IR 信号同步 + 下降沿检测
    -- ============================================================
    process(clk_i)
    begin
        if rising_edge(clk_i) then
            ir_sync <= ir_sync(1 downto 0) & irda_rxd_i;
        end if;
    end process;

    ir_fall <= '1' when ir_sync(2) = '1' and ir_sync(1) = '0' else '0';

    -- ============================================================
    -- NEC 解码状态机
    -- ============================================================
    process(clk_i)
        variable cmd_ok   : boolean;
        variable shift_v  : std_logic_vector(31 downto 0);
    begin
        if rising_edge(clk_i) then
            if rst_n_i = '0' then
                state    <= S_IDLE;
                bit_cnt  <= 0;
                ir_cmd   <= (others => '0');
                ir_addr  <= (others => '0');
                ir_valid <= '0';
                ir_repeat <= '0';
                cmd_count <= 0;
                edge_cnt  <= 0;
            else
                ir_valid  <= '0';
                ir_repeat <= '0';

                -- 下降沿间隔计时
                if edge_cnt < US_MAX then
                    edge_cnt <= edge_cnt + 1;
                end if;

                -- 下降沿触发
                if ir_fall = '1' then
                    shift_v := shift_reg;

                    case state is
                        when S_IDLE =>
                            -- 检测引导码: 13.5ms
                            if edge_cnt >= NEC_LEADER - TOL_LEADER and
                               edge_cnt <= NEC_LEADER + TOL_LEADER then
                                state   <= S_DATA;
                                bit_cnt <= 0;
                                shift_v := (others => '0');
                                shift_reg <= shift_v;
                            -- 检测重复码: 11.25ms
                            elsif edge_cnt >= NEC_REPEAT - TOL_REPEAT and
                                  edge_cnt <= NEC_REPEAT + TOL_REPEAT then
                                ir_repeat <= '1';
                            end if;

                        when S_DATA =>
                            -- 逻辑1: 2.25ms
                            if edge_cnt >= NEC_BIT_1 - TOL_BIT1 and
                               edge_cnt <= NEC_BIT_1 + TOL_BIT1 then
                                shift_v := shift_v(30 downto 0) & '1';
                            -- 逻辑0: 1.12ms
                            elsif edge_cnt >= NEC_BIT_0 - TOL_BIT0 and
                                  edge_cnt <= NEC_BIT_0 + TOL_BIT0 then
                                shift_v := shift_v(30 downto 0) & '0';
                            else
                                state <= S_IDLE;  -- 异常脉宽, 放弃
                            end if;

                            if state = S_DATA then
                                shift_reg <= shift_v;
                                if bit_cnt = 31 then
                                    -- 校验: 数据码 == NOT 数据反码
                                    cmd_ok := shift_v(15 downto 8) = not shift_v(7 downto 0);
                                    if cmd_ok then
                                        ir_cmd  <= bit_rev8(shift_v(15 downto 8));
                                        ir_addr <= bit_rev8(shift_v(31 downto 24))
                                                 & bit_rev8(shift_v(23 downto 16));
                                        ir_valid <= '1';
                                        if cmd_count < 99 then
                                            cmd_count <= cmd_count + 1;
                                        end if;
                                    end if;
                                    state <= S_IDLE;
                                else
                                    bit_cnt <= bit_cnt + 1;
                                end if;
                            end if;
                    end case;
                    edge_cnt <= 0;
                end if;

                -- 超时保护: 最后一位通过间隔超时推断为 '1'
                if state = S_DATA and edge_cnt > NEC_BIT_1 + TOL_BIT1 then
                    shift_v := shift_reg;
                    shift_v := shift_v(30 downto 0) & '1';  -- 超时 → 逻辑1
                    cmd_ok := shift_v(15 downto 8) = not shift_v(7 downto 0);
                    if cmd_ok then
                        ir_cmd  <= bit_rev8(shift_v(15 downto 8));
                        ir_addr <= bit_rev8(shift_v(31 downto 24))
                                 & bit_rev8(shift_v(23 downto 16));
                        ir_valid <= '1';
                        if cmd_count < 99 then
                            cmd_count <= cmd_count + 1;
                        end if;
                    end if;
                    state   <= S_IDLE;
                    bit_cnt <= 0;
                end if;
            end if;
        end if;
    end process;

    -- ============================================================
    -- 输出
    -- ============================================================
    cmd_o       <= ir_cmd;
    addr_o      <= ir_addr;
    valid_o     <= ir_valid;
    repeat_o    <= ir_repeat;
    cmd_count_o <= std_logic_vector(to_unsigned(cmd_count, 8));

end rtl;
