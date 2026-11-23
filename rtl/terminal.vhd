-- ============================================================================
-- terminal.vhd - hardware "glass terminal" for the 80 x 32 composite screen
--
-- Every byte the CPU sends through the console ACIA is also fed here, so the
-- screen shows exactly what the serial terminal shows. No software changes
-- and no address space are needed.
--
-- Supported (a practical VT100 / ANSI subset):
--   printable $20-$7E, $80-$FF   written at the cursor (with wrap at col 80)
--   CR $0D  LF $0A (scrolls)  BS $08  TAB $09  FF $0C (clear + home)
--   ESC [ n A / B / C / D        cursor up / down / right / left
--   ESC [ r ; c H  (or f)        cursor to row r, column c (1-based)
--   ESC [ 0J / 1J / 2J           clear to end / to start / whole screen
--   ESC [ 0K / 1K / 2K           clear to end / to start / whole line
--   ESC [ 7m / 0m / 27m          inverse video on / off / off
--   ESC c                        reset: clear screen, home, normal video
-- Anything else is ignored. Scrolling is done in hardware (top_row), so it
-- costs only the clearing of the new bottom line (128 clocks).
-- Screen RAM is 4K: cell = row*128 + col (columns 80-127 are not shown).
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity terminal is
  port (
    clk      : in  std_logic;                       -- 50 MHz
    rst      : in  std_logic;
    in_valid : in  std_logic;                       -- one-clock pulse
    in_data  : in  std_logic_vector(7 downto 0);
    -- screen RAM write port
    ram_we   : out std_logic;
    ram_addr : out std_logic_vector(11 downto 0);
    ram_din  : out std_logic_vector(7 downto 0);
    -- to the VDU
    top_row  : out unsigned(4 downto 0);
    cur_row  : out unsigned(4 downto 0);
    cur_col  : out unsigned(6 downto 0);
    ntsc     : in  std_logic                        -- '1': 28 rows, '0': 32
  );
end entity;

architecture rtl of terminal is
  type state_t is (S_IDLE, S_ESC, S_CSI, S_CLEAR);
  signal state    : state_t := S_CLEAR;               -- clears screen at start

  signal top      : unsigned(4 downto 0) := (others => '0');
  signal row      : unsigned(4 downto 0) := (others => '0');
  signal col      : unsigned(6 downto 0) := (others => '0');
  signal wrap_pend: std_logic := '0';
  signal inverse  : std_logic := '0';
  signal ntsc_d   : std_logic := '0';                  -- mode the rows are set for
  signal last_row : natural range 0 to 31;             -- bottom row: 27 or 31

  signal pend     : std_logic := '0';                  -- byte being handled
  signal pbyte    : std_logic_vector(7 downto 0) := (others => '0');

  -- 4-byte input FIFO, so bytes arriving while the screen is being
  -- cleared (4096 clocks = 82 us for a full clear) are not lost
  type fifo_t is array (0 to 3) of std_logic_vector(7 downto 0);
  signal fifo     : fifo_t;
  attribute ramstyle : string;
  attribute ramstyle of fifo : signal is "logic";   -- all 30 M9K are in use
  signal f_wr, f_rd : unsigned(1 downto 0) := (others => '0');

  signal p1, p2   : unsigned(6 downto 0) := (others => '0');
  signal pidx     : std_logic := '0';

  signal clr_ptr  : unsigned(12 downto 0) := (others => '0');   -- logical cell
  signal clr_end  : unsigned(12 downto 0) := to_unsigned(4096, 13);

  signal we_r     : std_logic := '0';
  signal addr_r   : std_logic_vector(11 downto 0) := (others => '0');
  signal din_r    : std_logic_vector(7 downto 0) := x"20";

  -- logical cell (row*128+col) -> physical screen RAM address
  function phys (cell : unsigned(11 downto 0); t : unsigned(4 downto 0))
    return std_logic_vector is
  begin
    return std_logic_vector(cell + (t & "0000000"));
  end function;

  function sat_add (a : unsigned; n : unsigned(6 downto 0); lim : natural)
    return unsigned is
    variable s : unsigned(7 downto 0);
  begin
    s := resize(a, 8) + n;
    if s > lim then return to_unsigned(lim, a'length); end if;
    return resize(s, a'length);
  end function;

  function sat_sub (a : unsigned; n : unsigned(6 downto 0)) return unsigned is
  begin
    if n >= resize(a, 7) then return to_unsigned(0, a'length); end if;
    return a - resize(n, a'length);
  end function;

  function times10_plus (p : unsigned(6 downto 0); d : unsigned(3 downto 0))
    return unsigned is
    variable s : unsigned(10 downto 0);
  begin
    s := (resize(p, 11) sll 3) + (resize(p, 11) sll 1) + resize(d, 11);
    if s > 127 then return to_unsigned(127, 7); end if;
    return s(6 downto 0);
  end function;
begin

  last_row <= 27 when ntsc_d = '1' else 31;

  ram_we   <= we_r;
  ram_addr <= addr_r;
  ram_din  <= din_r;
  top_row  <= top;
  cur_row  <= row;
  cur_col  <= col;

  process (clk)
    variable b      : std_logic_vector(7 downto 0);
    variable n      : unsigned(6 downto 0);
    variable cell   : unsigned(12 downto 0);
    variable go     : boolean;
    variable nl     : boolean;          -- do a line feed
    variable put    : boolean;          -- write b at the cursor
  begin
    if rising_edge(clk) then
      we_r <= '0';

      if in_valid = '1' and f_wr + 1 /= f_rd then   -- (dropped if full)
        fifo(to_integer(f_wr)) <= in_data;
        f_wr <= f_wr + 1;
      end if;

      cell := resize(row & col, 13);

      if ntsc /= ntsc_d and state /= S_CLEAR and pend = '0' then
        ------------------------------------------------ PAL <-> NTSC (F9)
        ntsc_d <= ntsc;
        if ntsc = '1' then
          -- 28 rows: if the cursor is below them, scroll so it is on the
          -- new bottom row (the text above it stays in view)
          if row > 27 then
            top <= top + (row - 27);
            row <= to_unsigned(27, 5);
          end if;
        else
          -- 32 rows: blank the four rows that come into view
          clr_ptr <= to_unsigned(28 * 128, 13);
          clr_end <= to_unsigned(32 * 128, 13);
          state   <= S_CLEAR;
        end if;

      elsif state = S_CLEAR then
        ------------------------------------------------ clearing a range
        if clr_ptr = clr_end then
          state <= S_IDLE;
        else
          we_r    <= '1';
          addr_r  <= phys(clr_ptr(11 downto 0), top);
          din_r   <= x"20";
          clr_ptr <= clr_ptr + 1;
        end if;

      elsif pend = '0' then
        if f_rd /= f_wr then                         -- next byte from the FIFO
          pbyte <= fifo(to_integer(f_rd));
          f_rd  <= f_rd + 1;
          pend  <= '1';
        end if;

      else
        pend <= '0';
        b   := pbyte;
        nl  := false;
        put := false;
        if p1 = 0 then n := to_unsigned(1, 7); else n := p1; end if;

        case state is
          ---------------------------------------------- normal characters
          when S_IDLE =>
            case b is
              when x"0D" => col <= (others => '0'); wrap_pend <= '0';
              when x"0A" => nl := true; wrap_pend <= '0';
              when x"08" =>
                wrap_pend <= '0';
                if col /= 0 then col <= col - 1; end if;
              when x"09" =>                            -- tab stops every 8
                if col < 72 then
                  col <= (col(6 downto 3) + 1) & "000";
                else
                  col <= to_unsigned(79, 7);
                end if;
              when x"0C" =>
                row <= (others => '0'); col <= (others => '0'); wrap_pend <= '0';
                clr_ptr <= (others => '0'); clr_end <= to_unsigned(4096, 13);
                state <= S_CLEAR;
              when x"1B" => state <= S_ESC;
              when others =>
                if b >= x"20" and b /= x"7F" then
                  put := true;
                end if;
            end case;

          ---------------------------------------------- after ESC
          when S_ESC =>
            if b = x"5B" then                          -- '['
              p1 <= (others => '0'); p2 <= (others => '0'); pidx <= '0';
              state <= S_CSI;
            elsif b = x"63" then                       -- 'c' reset
              row <= (others => '0'); col <= (others => '0');
              wrap_pend <= '0'; inverse <= '0';
              clr_ptr <= (others => '0'); clr_end <= to_unsigned(4096, 13);
              state <= S_CLEAR;
            else
              state <= S_IDLE;
            end if;

          ---------------------------------------------- ESC [ params final
          when S_CSI =>
            if b >= x"30" and b <= x"39" then          -- digit
              if pidx = '0' then
                p1 <= times10_plus(p1, unsigned(b(3 downto 0)));
              else
                p2 <= times10_plus(p2, unsigned(b(3 downto 0)));
              end if;
            elsif b = x"3B" then                       -- ';'
              pidx <= '1';
            elsif b >= x"40" and b <= x"7E" then       -- final byte
              state <= S_IDLE;
              wrap_pend <= '0';
              case b is
                when x"41" => row <= sat_sub(row, n);              -- A
                when x"42" => row <= sat_add(row, n, last_row);    -- B
                when x"43" => col <= sat_add(col, n, 79);          -- C
                when x"44" => col <= sat_sub(col, n);              -- D
                when x"48" | x"66" =>                              -- H f
                  if p1 = 0 then row <= (others => '0');
                  else row <= sat_add(to_unsigned(0, 5), p1 - 1, last_row); end if;
                  if p2 = 0 then col <= (others => '0');
                  else col <= sat_add(to_unsigned(0, 7), p2 - 1, 79); end if;
                when x"4A" =>                                      -- J
                  if p1 = 0 then
                    clr_ptr <= cell; clr_end <= to_unsigned(4096, 13);
                    state <= S_CLEAR;
                  elsif p1 = 1 then
                    clr_ptr <= (others => '0'); clr_end <= cell + 1;
                    state <= S_CLEAR;
                  elsif p1 = 2 then
                    clr_ptr <= (others => '0'); clr_end <= to_unsigned(4096, 13);
                    state <= S_CLEAR;
                  end if;
                when x"4B" =>                                      -- K
                  if p1 = 0 then
                    clr_ptr <= cell; clr_end <= resize(row & "0000000", 13) + 128;
                    state <= S_CLEAR;
                  elsif p1 = 1 then
                    clr_ptr <= resize(row & "0000000", 13); clr_end <= cell + 1;
                    state <= S_CLEAR;
                  elsif p1 = 2 then
                    clr_ptr <= resize(row & "0000000", 13);
                    clr_end <= resize(row & "0000000", 13) + 128;
                    state <= S_CLEAR;
                  end if;
                when x"6D" =>                                      -- m
                  if p1 = 7 or p2 = 7 then
                    inverse <= '1';
                  elsif p1 = 0 or p1 = 27 then
                    inverse <= '0';
                  end if;
                when others => null;
              end case;
            elsif b < x"20" then                       -- control char: abort
              state <= S_IDLE;
            end if;

          when others => null;
        end case;

        ------------------------------------------------ write a character
        if put then
          go := true;
          if wrap_pend = '1' then                      -- deferred wrap
            col <= (others => '0');
            wrap_pend <= '0';
            go := false;
            nl := true;
            pend  <= '1';                              -- write it next time
            pbyte <= b;
          end if;
          if go then
            we_r   <= '1';
            addr_r <= phys(row & col, top);
            din_r  <= (b(7) or inverse) & b(6 downto 0);
            if col = 79 then
              wrap_pend <= '1';
            else
              col <= col + 1;
            end if;
          end if;
        end if;

        ------------------------------------------------ line feed / scroll
        if nl then
          if row < last_row then
            row <= row + 1;
          else
            top     <= top + 1;                         -- scroll up one line
            clr_ptr <= to_unsigned(last_row * 128, 13); -- clear the new line
            clr_end <= to_unsigned(last_row * 128 + 128, 13);
            state   <= S_CLEAR;
          end if;
        end if;
      end if;

      if rst = '1' then
        state <= S_CLEAR;
        clr_ptr <= (others => '0'); clr_end <= to_unsigned(4096, 13);
        top <= (others => '0'); row <= (others => '0'); col <= (others => '0');
        wrap_pend <= '0'; inverse <= '0'; pend <= '0';
        f_rd <= f_wr;
      end if;
    end if;
  end process;

end architecture;
