-- ============================================================================
-- ps2_kbd.vhd - PS/2 keyboard (scan code set 2, UK layout) to ASCII
--
--   Letters, digits, punctuation, Enter (CR), Backspace ($08), Tab, Esc,
--   Delete ($7F), keypad keys, Ctrl+letter ($01-$1A), Caps Lock.
--   Arrow keys send ANSI sequences: ESC [ A/B/C/D  (up/down/right/left),
--   the same as your terminal.
--   Caps Lock starts ON (OS-65D wants upper-case commands).
--   UK Shift+3 (pound sign) has no ASCII code and sends '#'.
--   F10 resets the computer (reset_key pulse).
--   F9 switches the screen between PAL and NTSC (mode_key pulse).
--   Every key press / release is also given out raw (sc_*) for the OSI
--   keyboard matrix at $DF00.
--
--   Output is an 8-byte FIFO: "valid" is high while a byte is waiting on
--   "data"; pulse "ack" for one clock to take it.
--
--   Host-to-keyboard: when the keyboard sends AA (self-test passed) the
--   FPGA answers like a PC does: ED <leds> (set LEDs) then F4 (enable).
--   Caps Lock presses also send ED <leds> so the Caps LED follows.
--   The PS/2 lines are open-drain: the FPGA only ever pulls them low.
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ps2_kbd is
  port (
    clk      : in  std_logic;               -- 50 MHz
    rst      : in  std_logic;
    ps2_clk  : inout std_logic;
    ps2_data : inout std_logic;
    valid    : out std_logic;
    data     : out std_logic_vector(7 downto 0);
    ack      : in  std_logic;
    reset_key : out std_logic;                      -- one-clock pulse on F10
    mode_key  : out std_logic;                      -- one-clock pulse on F9
    -- raw key events for the OSI keyboard matrix (osi_kbd.vhd)
    sc_valid  : out std_logic;                      -- one-clock pulse per key event
    sc_code   : out std_logic_vector(7 downto 0);   -- set-2 code (E0/F0 removed)
    sc_ext    : out std_logic;                      -- it had an E0 prefix
    sc_brk    : out std_logic;                      -- '1' = key released
    caps_on   : out std_logic;                      -- Caps Lock state
    -- diagnostics
    dbg_edges : out std_logic_vector(7 downto 0);   -- filtered clock edges seen
    dbg_last  : out std_logic_vector(7 downto 0);   -- last byte received (any frame)
    dbg_good  : out std_logic_vector(7 downto 0)    -- frames with good start/parity/stop
  );
end entity;

architecture rtl of ps2_kbd is

  -- unshifted / shifted ASCII for a set-2 make code (0 = no character)
  function to_ascii (sc : std_logic_vector(7 downto 0); sh : boolean)
    return std_logic_vector is
    variable u, s : character;
  begin
    u := NUL; s := NUL;
    case sc is
      when x"1C" => u := 'a'; s := 'A';   when x"32" => u := 'b'; s := 'B';
      when x"21" => u := 'c'; s := 'C';   when x"23" => u := 'd'; s := 'D';
      when x"24" => u := 'e'; s := 'E';   when x"2B" => u := 'f'; s := 'F';
      when x"34" => u := 'g'; s := 'G';   when x"33" => u := 'h'; s := 'H';
      when x"43" => u := 'i'; s := 'I';   when x"3B" => u := 'j'; s := 'J';
      when x"42" => u := 'k'; s := 'K';   when x"4B" => u := 'l'; s := 'L';
      when x"3A" => u := 'm'; s := 'M';   when x"31" => u := 'n'; s := 'N';
      when x"44" => u := 'o'; s := 'O';   when x"4D" => u := 'p'; s := 'P';
      when x"15" => u := 'q'; s := 'Q';   when x"2D" => u := 'r'; s := 'R';
      when x"1B" => u := 's'; s := 'S';   when x"2C" => u := 't'; s := 'T';
      when x"3C" => u := 'u'; s := 'U';   when x"2A" => u := 'v'; s := 'V';
      when x"1D" => u := 'w'; s := 'W';   when x"22" => u := 'x'; s := 'X';
      when x"35" => u := 'y'; s := 'Y';   when x"1A" => u := 'z'; s := 'Z';
      when x"16" => u := '1'; s := '!';   when x"1E" => u := '2'; s := '"';
      when x"26" => u := '3'; s := '#';   when x"25" => u := '4'; s := '$';
      when x"2E" => u := '5'; s := '%';   when x"36" => u := '6'; s := '^';
      when x"3D" => u := '7'; s := '&';   when x"3E" => u := '8'; s := '*';
      when x"46" => u := '9'; s := '(';   when x"45" => u := '0'; s := ')';
      when x"4E" => u := '-'; s := '_';   when x"55" => u := '='; s := '+';
      when x"54" => u := '['; s := '{';   when x"5B" => u := ']'; s := '}';
      when x"4C" => u := ';'; s := ':';   when x"52" => u := '''; s := '@';
      when x"0E" => u := '`'; s := '~';   when x"5D" => u := '#'; s := '~';
      when x"61" => u := '\'; s := '|';
      when x"41" => u := ','; s := '<';   when x"49" => u := '.'; s := '>';
      when x"4A" => u := '/'; s := '?';
      when x"29" => u := ' '; s := ' ';
      when x"5A" => u := CR;  s := CR;    when x"66" => u := BS;  s := BS;
      when x"0D" => u := HT;  s := HT;    when x"76" => u := ESC; s := ESC;
      -- keypad (non-extended codes)
      when x"70" => u := '0'; s := '0';   when x"69" => u := '1'; s := '1';
      when x"72" => u := '2'; s := '2';   when x"7A" => u := '3'; s := '3';
      when x"6B" => u := '4'; s := '4';   when x"73" => u := '5'; s := '5';
      when x"74" => u := '6'; s := '6';   when x"6C" => u := '7'; s := '7';
      when x"75" => u := '8'; s := '8';   when x"7D" => u := '9'; s := '9';
      when x"71" => u := '.'; s := '.';   when x"7C" => u := '*'; s := '*';
      when x"7B" => u := '-'; s := '-';   when x"79" => u := '+'; s := '+';
      when others => null;
    end case;
    if sh then
      return std_logic_vector(to_unsigned(character'pos(s), 8));
    else
      return std_logic_vector(to_unsigned(character'pos(u), 8));
    end if;
  end function;

  -- PS/2 receiver
  signal c_s, d_s       : std_logic_vector(2 downto 0) := (others => '1');
  -- glitch filter on the PS/2 clock: 8 samples taken 0.32 us apart must all
  -- agree before the filtered clock changes (rejects slow/noisy edges)
  signal flt_div        : unsigned(3 downto 0) := (others => '0');
  signal flt_hist       : std_logic_vector(7 downto 0) := (others => '1');
  signal kc_f, kc_prev  : std_logic := '1';
  signal n_edges, n_good, last_byte : unsigned(7 downto 0) := (others => '0');
  signal bitcnt         : natural range 0 to 10 := 0;
  signal shift          : std_logic_vector(10 downto 0) := (others => '0');
  signal idle_cnt       : natural range 0 to 100_000 := 0;   -- 2 ms timeout
  signal code           : std_logic_vector(7 downto 0) := (others => '0');
  signal code_rdy       : std_logic := '0';

  -- decoder state
  signal brk, ext       : std_logic := '0';
  signal lshift, rshift : std_logic := '0';
  signal ctrl           : std_logic := '0';
  signal caps           : std_logic := '1';

  -- host-to-keyboard transmitter
  type tx_state_t is (T_IDLE, T_INHIBIT, T_START, T_BITS, T_ACK, T_WAITRESP);
  signal tx_state       : tx_state_t := T_IDLE;
  signal clk_oe, dat_oe : std_logic := '0';      -- '1' = pull the line low
  signal tx_timer       : natural range 0 to 1_250_000 := 0;
  signal tx_frame       : std_logic_vector(9 downto 0) := (others => '1');
  signal tx_bit         : natural range 0 to 10 := 0;
  type q_t is array (0 to 2) of std_logic_vector(7 downto 0);
  signal q              : q_t := (others => x"00");
  signal q_n            : natural range 0 to 3 := 0;
  -- 1 s after reset, enable the keyboard if it has not sent AA by then
  -- (it may have finished its self-test before the FPGA was configured)
  signal boot_cnt       : natural range 0 to 50_000_000 := 0;
  signal seen_aa        : std_logic := '0';

  -- FIFO
  -- (8 bytes: plenty for typing, and half the logic of 16 - the FPGA is full)
  type fifo_t is array (0 to 7) of std_logic_vector(7 downto 0);
  signal fifo           : fifo_t;
  signal wp, rp         : unsigned(2 downto 0) := (others => '0');
  signal cnt            : natural range 0 to 8 := 0;
begin

  dbg_edges <= std_logic_vector(n_edges);
  dbg_last  <= std_logic_vector(last_byte);
  dbg_good  <= std_logic_vector(n_good);

  ps2_clk  <= '0' when clk_oe = '1' else 'Z';
  ps2_data <= '0' when dat_oe = '1' else 'Z';

  sc_valid <= '1' when code_rdy = '1' and code /= x"F0" and code /= x"E0" else '0';
  sc_code  <= code;
  sc_ext   <= ext;
  sc_brk   <= brk;
  caps_on  <= caps;

  valid <= '1' when cnt /= 0 else '0';
  data  <= fifo(to_integer(rp));

  process (clk)
    variable ch      : std_logic_vector(7 downto 0);
    variable is_let  : boolean;
    variable sh      : boolean;
    variable n_push  : natural range 0 to 3;
    variable p0, p1, p2 : std_logic_vector(7 downto 0);
    variable new_cnt : natural range 0 to 8;
    variable w       : unsigned(2 downto 0);
    variable leds    : std_logic_vector(7 downto 0);
    variable fall    : boolean;
    variable par     : std_logic;
  begin
    if rising_edge(clk) then
      c_s <= c_s(1 downto 0) & to_x01(ps2_clk);    -- to_x01: pull-up "H" reads as 1
      d_s <= d_s(1 downto 0) & to_x01(ps2_data);
      code_rdy <= '0';
      reset_key <= '0';
      mode_key  <= '0';

      flt_div <= flt_div + 1;
      if flt_div = 0 then
        flt_hist <= flt_hist(6 downto 0) & c_s(2);
        if flt_hist = x"FF" then kc_f <= '1'; end if;
        if flt_hist = x"00" then kc_f <= '0'; end if;
      end if;
      kc_prev <= kc_f;

      fall := kc_prev = '1' and kc_f = '0';          -- filtered falling edge

      ------------------------------------------------ receive 11-bit frames
      -- (ignored while the FPGA is itself sending to the keyboard)
      if tx_state /= T_IDLE and tx_state /= T_WAITRESP then
        bitcnt   <= 0;
        idle_cnt <= 0;
      elsif fall then
        idle_cnt <= 0;
        n_edges <= n_edges + 1;
        shift <= d_s(1) & shift(10 downto 1);
        if bitcnt = 10 then
          bitcnt <= 0;
          last_byte <= unsigned(shift(9 downto 2));
          -- shift(1) after this edge = start bit, data in 2..9, parity, stop
          if shift(1) = '0' and d_s(1) = '1' and
             (shift(2) xor shift(3) xor shift(4) xor shift(5) xor shift(6) xor
              shift(7) xor shift(8) xor shift(9) xor shift(10)) = '1' then
            code     <= shift(9 downto 2);
            code_rdy <= '1';
            n_good   <= n_good + 1;
          end if;
        else
          bitcnt <= bitcnt + 1;
        end if;
      elsif bitcnt /= 0 then
        if idle_cnt = 100_000 then                   -- lost sync: start again
          bitcnt <= 0;
        else
          idle_cnt <= idle_cnt + 1;
        end if;
      end if;

      ------------------------------------------------ decode
      n_push := 0; p0 := x"00"; p1 := x"00"; p2 := x"00";
      if code_rdy = '1' then
        if code = x"F0" then
          brk <= '1';
        elsif code = x"E0" then
          ext <= '1';
        else
          brk <= '0';
          ext <= '0';
          case code is
            when x"12" => if ext = '0' then lshift <= not brk; end if;
            when x"59" => rshift <= not brk;
            when x"14" => ctrl   <= not brk;
            when x"58" =>
              if brk = '0' then
                caps <= not caps;
                if q_n = 0 then                      -- update Caps LED
                  leds := "00000" & (not caps) & "00";
                  q(0) <= x"ED"; q(1) <= leds; q_n <= 2;
                end if;
              end if;
            when x"09" =>                            -- F10: reset the computer
              if brk = '0' and ext = '0' then reset_key <= '1'; end if;
            when x"01" =>                            -- F9: PAL / NTSC
              if brk = '0' and ext = '0' then mode_key <= '1'; end if;
            when x"AA" =>                            -- keyboard reset done
              seen_aa <= '1';
              leds := "00000" & caps & "00";
              q(0) <= x"ED"; q(1) <= leds; q(2) <= x"F4"; q_n <= 3;
            when others =>
              if brk = '0' then
                if ext = '1' then
                  case code is
                    when x"75" => n_push := 3; p0 := x"1B"; p1 := x"5B"; p2 := x"41";
                    when x"72" => n_push := 3; p0 := x"1B"; p1 := x"5B"; p2 := x"42";
                    when x"74" => n_push := 3; p0 := x"1B"; p1 := x"5B"; p2 := x"43";
                    when x"6B" => n_push := 3; p0 := x"1B"; p1 := x"5B"; p2 := x"44";
                    when x"71" => n_push := 1; p0 := x"7F";
                    when x"5A" => n_push := 1; p0 := x"0D";
                    when x"4A" => n_push := 1; p0 := x"2F";
                    when others => null;
                  end case;
                else
                  ch := to_ascii(code, false);
                  is_let := ch >= x"61" and ch <= x"7A";
                  sh := (lshift = '1' or rshift = '1');
                  if is_let and caps = '1' then sh := not sh; end if;
                  ch := to_ascii(code, sh);
                  if ctrl = '1' and is_let then
                    ch := "000" & ch(4 downto 0);
                  end if;
                  if ch /= x"00" then
                    n_push := 1; p0 := ch;
                  end if;
                end if;
              end if;
          end case;
        end if;
      end if;

      ------------------------------------------------ host -> keyboard
      if boot_cnt /= 50_000_000 then
        boot_cnt <= boot_cnt + 1;
      elsif seen_aa = '0' then
        seen_aa <= '1';
        if q_n = 0 then
          q(0) <= x"ED"; q(1) <= "00000" & caps & "00"; q(2) <= x"F4"; q_n <= 3;
        end if;
      end if;
      if tx_timer /= 0 then tx_timer <= tx_timer - 1; end if;
      case tx_state is
        when T_IDLE =>
          clk_oe <= '0'; dat_oe <= '0';
          if q_n /= 0 and bitcnt = 0 and code_rdy = '0' then
            par := '1';
            for i in 0 to 7 loop par := par xor q(0)(i); end loop;
            tx_frame <= '1' & par & q(0);      -- stop, parity, data
            clk_oe   <= '1';                   -- inhibit: clock low 120 us
            tx_timer <= 6_000;
            tx_state <= T_INHIBIT;
          end if;
        when T_INHIBIT =>
          if tx_timer = 0 then
            dat_oe   <= '1';                   -- start bit
            tx_timer <= 250;                   -- 5 us
            tx_state <= T_START;
          end if;
        when T_START =>
          if tx_timer = 0 then
            clk_oe   <= '0';                   -- release clock: keyboard clocks us
            tx_bit   <= 0;
            tx_timer <= 1_000_000;             -- 20 ms to finish
            tx_state <= T_BITS;
          end if;
        when T_BITS =>
          if fall then
            if tx_bit < 10 then
              dat_oe <= not tx_frame(tx_bit);  -- data, parity, then release (stop)
              tx_bit <= tx_bit + 1;
            else
              tx_state <= T_ACK;               -- 11th clock: keyboard's ack bit
            end if;
          elsif tx_timer = 0 then              -- keyboard never clocked: give up
            dat_oe <= '0';
            q_n    <= 0;
            tx_state <= T_IDLE;
          end if;
        when T_ACK =>
          dat_oe <= '0';
          if kc_f = '1' then
            tx_timer <= 1_250_000;             -- 25 ms for the reply (FA)
            tx_state <= T_WAITRESP;
          end if;
        when T_WAITRESP =>
          if code_rdy = '1' or tx_timer = 0 then
            q(0) <= q(1); q(1) <= q(2);
            if q_n /= 0 then q_n <= q_n - 1; end if;
            tx_state <= T_IDLE;
          end if;
      end case;

      ------------------------------------------------ FIFO
      new_cnt := cnt;
      if ack = '1' and cnt /= 0 then
        rp <= rp + 1;
        new_cnt := new_cnt - 1;
      end if;
      if n_push /= 0 and cnt <= 8 - n_push then
        w := wp;
        fifo(to_integer(w)) <= p0;
        if n_push = 3 then
          fifo(to_integer(w + 1)) <= p1;
          fifo(to_integer(w + 2)) <= p2;
        end if;
        wp <= w + n_push;
        new_cnt := new_cnt + n_push;
      end if;
      cnt <= new_cnt;

      if rst = '1' then
        wp <= (others => '0'); rp <= (others => '0'); cnt <= 0;
        brk <= '0'; ext <= '0'; lshift <= '0'; rshift <= '0'; ctrl <= '0';
        caps <= '1';
        tx_state <= T_IDLE; clk_oe <= '0'; dat_oe <= '0';
        q_n <= 0; boot_cnt <= 0; seen_aa <= '0';
      end if;
    end if;
  end process;

end architecture;
