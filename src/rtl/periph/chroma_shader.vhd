-- chroma_shader.vhd -- Hardware noise terrain generator for VGA text terminal
-- Uses chroma_dp_ram components for guaranteed M9K BRAM inference.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity chroma_shader is
    port (
        clk_i       : in  std_logic;
        rst_n_i     : in  std_logic;
        wb_adr_i    : in  std_logic_vector(4 downto 0);
        wb_dat_i    : in  std_logic_vector(31 downto 0);
        wb_dat_o    : out std_logic_vector(31 downto 0);
        wb_we_i     : in  std_logic;
        wb_stb_i    : in  std_logic;
        wb_ack_o    : out std_logic;
        clk_25m_i   : in  std_logic;
        rd_addr_i   : in  integer range 0 to 2399;
        rd_char_o   : out std_logic_vector(7 downto 0);
        rd_fg_o     : out std_logic_vector(15 downto 0);
        rd_bg_o     : out std_logic_vector(15 downto 0);
        chroma_en_o : out std_logic
    );
end entity chroma_shader;

architecture rtl of chroma_shader is

    constant TERRAIN_START : integer := 160;
    constant TERRAIN_END   : integer := 2159;

    signal ctrl_reg      : std_logic_vector(31 downto 0);
    signal seed_reg      : unsigned(31 downto 0);
    signal off_x_reg     : signed(15 downto 0);
    signal off_y_reg     : signed(15 downto 0);
    signal player_x      : unsigned(6 downto 0);
    signal player_y      : unsigned(4 downto 0);
    signal enable        : std_logic;
    signal force_refresh : std_logic;
    signal player_addr   : unsigned(10 downto 0);

    type fill_state_t is (S_IDLE, S_HASH, S_WRITE, S_DONE);
    signal fill_state  : fill_state_t;
    signal fill_row    : unsigned(4 downto 0);
    signal fill_col    : unsigned(6 downto 0);
    signal fill_hash   : unsigned(31 downto 0);
    signal fill_busy   : std_logic;
    signal frame_ready : std_logic;
    signal prev_enable : std_logic;

    -- BRAM write interface
    signal wr_en      : std_logic;
    signal wr_addr    : integer range 0 to 2047;
    signal wr_cell_d  : std_logic_vector(23 downto 0);
    signal wr_paint_d : std_logic_vector(17 downto 0);
    signal wr_paint_en : std_logic;

    -- BRAM read interface (25 MHz, VGA side)
    signal rd_local   : integer range 0 to 2047;
    signal rd_cell_q  : std_logic_vector(23 downto 0);
    signal rd_pnt_q   : std_logic_vector(17 downto 0);

    -- WB-side read (50 MHz, same-clock read through write port)
    signal wb_cell_q  : std_logic_vector(23 downto 0);
    signal wb_pnt_q   : std_logic_vector(17 downto 0);

    -- Cross-domain: player_addr and enable synchronized to 25 MHz
    signal player_addr_s1 : unsigned(10 downto 0);
    signal player_addr_s2 : unsigned(10 downto 0);
    signal enable_s1      : std_logic;
    signal enable_s2      : std_logic;

    signal wb_ack : std_logic;

    function rgb332_to_565(c : std_logic_vector(7 downto 0))
        return std_logic_vector is
    begin
        return (c(7 downto 5) & c(6 downto 5))
               & (c(4 downto 2) & c(4 downto 2))
               & (c(1 downto 0) & c(1 downto 0) & c(1));
    end function;

    function terrain_hash(wx, wy : unsigned(15 downto 0);
                          sd : unsigned(31 downto 0))
        return unsigned is
        variable h : unsigned(31 downto 0);
    begin
        h := sd xor resize(wx, 32) sll 7 xor resize(wy, 32) sll 20;
        h := h xor (h(18 downto 0) & "0000000000000");
        h := h xor ("00000000000000000" & h(31 downto 17));
        h := h xor (h(26 downto 0) & "00000");
        h := h xor resize(wy, 32) sll 3 xor resize(wx, 32) sll 16;
        h := h xor ("00000000000" & h(31 downto 11));
        h := h xor (h(24 downto 0) & "0000000");
        return h;
    end function;

    function hash_to_terrain(h : unsigned(7 downto 0))
        return std_logic_vector is
    begin
        if h < 56 then       return x"03";
        elsif h < 76 then    return x"14";
        elsif h < 96 then    return x"F5";
        elsif h < 166 then   return x"39";
        elsif h < 196 then   return x"12";
        elsif h < 226 then   return x"A2";
        else                 return x"FF";
        end if;
    end function;

    function hash_to_type(h : unsigned(7 downto 0))
        return std_logic_vector is
    begin
        if h < 56 then       return "000";
        elsif h < 76 then    return "001";
        elsif h < 96 then    return "010";
        elsif h < 166 then   return "011";
        elsif h < 196 then   return "100";
        elsif h < 226 then   return "101";
        else                 return "110";
        end if;
    end function;

    function terrain_to_char(t : std_logic_vector(2 downto 0))
        return std_logic_vector is
    begin
        case t is
            when "000"  => return x"7E";
            when "001"  => return x"B0";
            when "010"  => return x"B0";
            when "011"  => return x"B1";
            when "100"  => return x"B2";
            when "101"  => return x"1E";
            when "110"  => return x"DB";
            when others => return x"20";
        end case;
    end function;

begin

    enable <= ctrl_reg(0);
    force_refresh <= ctrl_reg(1);
    player_addr <= (resize(player_y, 11) sll 6)
                   + (resize(player_y, 11) sll 4)
                   + resize(player_x, 11);

    ----------------------------------------------------------------
    -- Cell RAM: [23:16]=fg RGB332, [15:8]=bg RGB332,
    --           [7]=has_gold, [2:0]=terrain_type
    ----------------------------------------------------------------
    u_cell_ram : entity work.chroma_dp_ram
        generic map (WIDTH => 24, DEPTH => 2048)
        port map (
            clk_a   => clk_i,
            wr_en_a => wr_en,
            addr_a  => wr_addr,
            data_a  => wr_cell_d,
            q_a     => wb_cell_q,
            clk_b   => clk_25m_i,
            addr_b  => rd_local,
            q_b     => rd_cell_q
        );

    ----------------------------------------------------------------
    -- Paint RAM: [17]=valid, [16]=has_gold, [15:8]=fg, [7:0]=bg
    ----------------------------------------------------------------
    u_paint_ram : entity work.chroma_dp_ram
        generic map (WIDTH => 18, DEPTH => 2048)
        port map (
            clk_a   => clk_i,
            wr_en_a => wr_paint_en,
            addr_a  => wr_addr,
            data_a  => wr_paint_d,
            q_a     => wb_pnt_q,
            clk_b   => clk_25m_i,
            addr_b  => rd_local,
            q_b     => rd_pnt_q
        );

    ----------------------------------------------------------------
    -- WB + Fill FSM (50 MHz)
    ----------------------------------------------------------------
    process(clk_i)
        variable addr_v  : integer;
        variable idx_int : integer range 0 to 2047;
        variable wx_v    : unsigned(15 downto 0);
        variable wy_v    : unsigned(15 downto 0);
    begin
        if rising_edge(clk_i) then
            if rst_n_i = '0' then
                ctrl_reg <= (others => '0');
                seed_reg <= (others => '0');
                off_x_reg <= (others => '0');
                off_y_reg <= (others => '0');
                player_x <= "1010000";
                player_y <= "01100";
                fill_state <= S_IDLE;
                fill_row <= (others => '0');
                fill_col <= (others => '0');
                fill_busy <= '0';
                frame_ready <= '0';
                prev_enable <= '0';
                wr_en <= '0';
                wr_paint_en <= '0';
                wb_ack <= '0';
            else
                wb_ack <= '0';
                wr_en <= '0';
                wr_paint_en <= '0';
                wr_addr <= to_integer(player_addr);

                -- Fill FSM
                prev_enable <= enable;
                if enable = '1' and prev_enable = '0' then
                    fill_state <= S_HASH;
                    fill_row <= (others => '0');
                    fill_col <= (others => '0');
                    fill_busy <= '1';
                    frame_ready <= '0';
                end if;

                if force_refresh = '1' and fill_state = S_IDLE then
                    ctrl_reg(1) <= '0';
                    fill_state <= S_HASH;
                    fill_row <= (others => '0');
                    fill_col <= (others => '0');
                    fill_busy <= '1';
                    frame_ready <= '0';
                end if;

                case fill_state is
                    when S_IDLE => null;
                    when S_HASH =>
                        wx_v := unsigned(std_logic_vector(
                            off_x_reg + signed(resize(fill_col, 16))));
                        wy_v := unsigned(std_logic_vector(
                            off_y_reg + signed(resize(fill_row, 16))));
                        fill_hash <= terrain_hash(wx_v, wy_v, seed_reg);
                        fill_state <= S_WRITE;
                    when S_WRITE =>
                        idx_int := to_integer(
                            (resize(fill_row, 11) sll 6)
                            + (resize(fill_row, 11) sll 4)
                            + resize(fill_col, 11));
                        wr_addr <= idx_int;
                        if fill_hash(23 downto 16) = x"5A" then
                            wr_cell_d <= hash_to_terrain(fill_hash(7 downto 0))
                                & x"00" & "1" & "0000"
                                & hash_to_type(fill_hash(7 downto 0));
                        else
                            wr_cell_d <= hash_to_terrain(fill_hash(7 downto 0))
                                & x"00" & "0" & "0000"
                                & hash_to_type(fill_hash(7 downto 0));
                        end if;
                        wr_en <= '1';

                        if fill_col = 79 then
                            fill_col <= (others => '0');
                            fill_row <= fill_row + 1;
                        else
                            fill_col <= fill_col + 1;
                        end if;
                        if fill_row = 24 and fill_col = 79 then
                            fill_state <= S_DONE;
                        else
                            fill_state <= S_HASH;
                        end if;
                    when S_DONE =>
                        fill_busy <= '0';
                        frame_ready <= '1';
                        fill_state <= S_IDLE;
                end case;

                -- WB
                if wb_stb_i = '1' then
                    wb_ack <= '1';
                    addr_v := to_integer(unsigned(wb_adr_i));
                    if wb_we_i = '1' then
                        case addr_v is
                            when 16#00# => ctrl_reg <= wb_dat_i;
                            when 16#01# => seed_reg <= unsigned(wb_dat_i);
                            when 16#02# => off_x_reg <= signed(wb_dat_i(15 downto 0));
                            when 16#03# => off_y_reg <= signed(wb_dat_i(15 downto 0));
                            when 16#04# =>
                                if unsigned(wb_dat_i(6 downto 0)) < 80 then
                                    player_x <= unsigned(wb_dat_i(6 downto 0));
                                end if;
                            when 16#05# =>
                                if unsigned(wb_dat_i(4 downto 0)) < 25 then
                                    player_y <= unsigned(wb_dat_i(4 downto 0));
                                end if;
                            when 16#07# =>
                                idx_int := to_integer(player_addr);
                                wr_addr <= idx_int;
                                wr_cell_d <= wb_dat_i(15 downto 8)
                                    & wb_dat_i(23 downto 16)
                                    & wb_dat_i(7) & "0000" & wb_dat_i(2 downto 0);
                                wr_en <= '1';
                                wr_paint_d <= '1' & wb_dat_i(7)
                                    & wb_dat_i(15 downto 8)
                                    & wb_dat_i(23 downto 16);
                                wr_paint_en <= '1';
                            when others => null;
                        end case;
                    else
                        case addr_v is
                            when 16#00# => wb_dat_o <= ctrl_reg;
                            when 16#01# => wb_dat_o <= std_logic_vector(seed_reg);
                            when 16#02# => wb_dat_o <= x"0000" &
                                std_logic_vector(off_x_reg);
                            when 16#03# => wb_dat_o <= x"0000" &
                                std_logic_vector(off_y_reg);
                            when 16#04# => wb_dat_o <= x"000000" & "0" &
                                std_logic_vector(player_x);
                            when 16#05# => wb_dat_o <= x"000000" & "000" &
                                std_logic_vector(player_y);
                            when 16#06# =>
                                if wb_pnt_q(17) = '1' then
                                    wb_dat_o(2 downto 0) <= wb_cell_q(2 downto 0);
                                    wb_dat_o(3) <= wb_pnt_q(16);
                                    wb_dat_o(11 downto 4) <= wb_pnt_q(15 downto 8);
                                    wb_dat_o(19 downto 12) <= wb_pnt_q(7 downto 0);
                                else
                                    wb_dat_o(2 downto 0) <= wb_cell_q(2 downto 0);
                                    wb_dat_o(3) <= wb_cell_q(7);
                                    wb_dat_o(11 downto 4) <= wb_cell_q(23 downto 16);
                                    wb_dat_o(19 downto 12) <= wb_cell_q(15 downto 8);
                                end if;
                                wb_dat_o(31 downto 20) <= x"000";
                            when 16#08# =>
                                wb_dat_o <= (0 => fill_busy, 1 => frame_ready,
                                             others => '0');
                            when others => wb_dat_o <= (others => '0');
                        end case;
                    end if;
                end if;
            end if;
        end if;
    end process;

    wb_ack_o <= wb_ack;

    ----------------------------------------------------------------
    -- VGA output (25 MHz)
    ----------------------------------------------------------------
    process(clk_25m_i)
        variable cell_data : std_logic_vector(23 downto 0);
        variable pnt_data  : std_logic_vector(17 downto 0);
        variable use_paint : boolean;
        variable fg332     : std_logic_vector(7 downto 0);
        variable bg332     : std_logic_vector(7 downto 0);
        variable has_gold  : std_logic;
        variable cell_type : std_logic_vector(2 downto 0);
    begin
        if rising_edge(clk_25m_i) then
            -- Synchronize cross-domain signals from 50 MHz
            player_addr_s1 <= player_addr;
            player_addr_s2 <= player_addr_s1;
            enable_s1 <= enable;
            enable_s2 <= enable_s1;

            chroma_en_o <= '0';
            rd_char_o <= x"20";
            rd_fg_o <= x"FFFF";
            rd_bg_o <= x"0000";

            if enable_s2 = '1' then
                if rd_addr_i >= TERRAIN_START and rd_addr_i <= TERRAIN_END then
                    rd_local <= rd_addr_i - TERRAIN_START;

                    cell_data := rd_cell_q;
                    pnt_data  := rd_pnt_q;

                    use_paint := (pnt_data(17) = '1');
                    if use_paint then
                        fg332    := pnt_data(15 downto 8);
                        bg332    := pnt_data(7 downto 0);
                        has_gold := pnt_data(16);
                    else
                        fg332    := cell_data(23 downto 16);
                        bg332    := cell_data(15 downto 8);
                        has_gold := cell_data(7);
                    end if;
                    cell_type := cell_data(2 downto 0);

                    if rd_local = to_integer(player_addr_s2) then
                        rd_char_o <= x"40";
                        rd_fg_o <= x"FFFF";
                        rd_bg_o <= rgb332_to_565(fg332);
                    elsif has_gold = '1' then
                        rd_char_o <= x"0F";
                        rd_fg_o <= x"FFE0";
                        rd_bg_o <= rgb332_to_565(fg332);
                    else
                        rd_char_o <= terrain_to_char(cell_type);
                        rd_fg_o <= rgb332_to_565(fg332);
                        rd_bg_o <= rgb332_to_565(bg332);
                    end if;
                    chroma_en_o <= '1';
                end if;
            end if;
        end if;
    end process;

end architecture rtl;
