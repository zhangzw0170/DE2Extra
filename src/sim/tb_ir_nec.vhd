-- tb_ir_nec.vhd — NEC 红外解码器 QuestaSim testbench
--
-- 验证:
--   1. 引导码检测 (9ms + 4.5ms)
--   2. 32-bit 帧解码 (地址 0x0001, 命令 0x5A)
--   3. 重复码检测
--   4. 数据校验 (错误命令被丢弃)
--
-- 用法:
--   vcom -93 ir_nec_decoder.vhd tb_ir_nec.vhd
--   vsim tb_ir_nec
--   run 200 ms

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_ir_nec is
end tb_ir_nec;

architecture sim of tb_ir_nec is

    signal clk       : std_logic := '0';
    signal rst_n     : std_logic := '0';
    signal irda_rxd  : std_logic := '1';
    signal cmd       : std_logic_vector(7 downto 0);
    signal addr      : std_logic_vector(15 downto 0);
    signal valid     : std_logic;
    signal repeat    : std_logic;
    signal cmd_count : std_logic_vector(7 downto 0);

    constant CLK_PERIOD : time := 20 ns;  -- 50 MHz

    -- NEC 时序参数 (实际值, 非 tick 数)
    constant NEC_HALF_PERIOD : time := 560 us;  -- 56.25kHz carrier, 但我们模拟基带

    procedure send_bit(signal io : out std_logic; val : std_logic) is
    begin
        -- 逻辑起始: 560us LOW
        io <= '0';
        wait for 560 us;
        if val = '1' then
            io <= '1';
            wait for 1690 us;  -- 逻辑1: +1690us HIGH
        else
            io <= '1';
            wait for 560 us;   -- 逻辑0: +560us HIGH
        end if;
    end procedure;

    procedure send_leader(signal io : out std_logic) is
    begin
        io <= '0';
        wait for 9 ms;
        io <= '1';
        wait for 4500 us;
    end procedure;

    procedure send_repeat(signal io : out std_logic) is
    begin
        io <= '0';
        wait for 9 ms;
        io <= '1';
        wait for 2250 us;
    end procedure;

    procedure send_byte(signal io : out std_logic; byte : std_logic_vector(7 downto 0)) is
    begin
        -- NEC LSB-first
        for i in 0 to 7 loop
            send_bit(io, byte(i));
        end loop;
    end procedure;

    procedure send_frame(
        signal io     : out std_logic;
        addr_low      : std_logic_vector(7 downto 0);
        addr_high     : std_logic_vector(7 downto 0);
        cmd_byte      : std_logic_vector(7 downto 0)
    ) is
    begin
        send_leader(io);
        send_byte(io, addr_low);       -- 低地址
        send_byte(io, addr_high);      -- 高地址
        send_byte(io, cmd_byte);       -- 命令
        send_byte(io, not cmd_byte);   -- 命令反码
    end procedure;

begin

    clk <= not clk after CLK_PERIOD / 2;

    u_dut : entity work.ir_nec_decoder
    port map (
        clk_i        => clk,
        rst_n_i      => rst_n,
        irda_rxd_i   => irda_rxd,
        cmd_o        => cmd,
        addr_o       => addr,
        valid_o      => valid,
        repeat_o     => repeat,
        cmd_count_o  => cmd_count
    );

    process
    begin
        report "=== NEC IR Decoder Testbench ===";

        -- 复位
        rst_n <= '0';
        irda_rxd <= '1';
        wait for 10 us;
        rst_n <= '1';
        wait for 10 us;

        ------------------------------------------------------------
        -- 测试 1: 发送标准 NEC 帧 (地址 0x0001, 命令 0x5A)
        ------------------------------------------------------------
        report "Test 1: Standard NEC frame (addr=0x0001, cmd=0x5A)";
        send_frame(irda_rxd, x"01", x"00", x"5A");
        wait for 50 ms;

        assert valid = '1'
            report "ERROR: valid not asserted after valid frame" severity error;
        assert cmd = x"5A"
            report "ERROR: cmd mismatch" severity error;
        report "  CMD = 0x" & to_hstring(cmd);

        ------------------------------------------------------------
        -- 测试 2: 重复码
        ------------------------------------------------------------
        report "Test 2: Repeat code";
        send_repeat(irda_rxd);
        wait for 50 ms;

        assert repeat = '1'
            report "ERROR: repeat not detected" severity error;

        ------------------------------------------------------------
        -- 测试 3: 错误命令 (反码不匹配)
        ------------------------------------------------------------
        report "Test 3: Corrupt frame (bad complement)";
        send_leader(irda_rxd);
        send_byte(irda_rxd, x"01");     -- 低地址 = 0x01
        send_byte(irda_rxd, x"00");     -- 高地址 = 0x00
        send_byte(irda_rxd, x"42");     -- 命令 = 0x42
        send_byte(irda_rxd, x"00");     -- 错误反码 (应该 ~0x42 = 0xBD)
        wait for 50 ms;

        -- cmd 应该不变 (仍为 0x5A)
        assert cmd = x"5A"
            report "ERROR: cmd should not change on bad frame" severity error;

        ------------------------------------------------------------
        -- 测试 4: 第二次有效帧 (命令 0x0F)
        ------------------------------------------------------------
        report "Test 4: Second valid frame (cmd=0x0F)";
        send_frame(irda_rxd, x"01", x"00", x"0F");
        wait for 50 ms;

        assert cmd = x"0F"
            report "ERROR: second cmd mismatch" severity error;

        report "=== All tests complete ===";
        wait;
    end process;

    -- 监视 valid 脉冲
    process(clk)
    begin
        if rising_edge(clk) and valid = '1' then
            report "  VALID: cmd=0x" & to_hstring(cmd)
                & " addr=0x" & to_hstring(addr)
                & " count=" & integer'image(to_integer(unsigned(cmd_count)));
        end if;
    end process;

end sim;
