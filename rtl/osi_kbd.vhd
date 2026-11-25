-- ============================================================================
-- osi_kbd.vhd - OSI polled keyboard at $DF00, driven by the PS/2 keyboard
--
-- The OSI keyboard is an 8 x 8 switch matrix. A program writes a row
-- select byte to $DF00 and reads back which keys in those rows are down.
-- Key positions are those of the OSI 542 / 600 keyboard (as in MAME's
-- osi driver):
--
--   row  bit7    bit6   bit5   bit4   bit3   bit2   bit1    bit0
--    0   REPEAT  CTRL   ESC    -      -      LSHIFT RSHIFT  SHIFT LOCK
--    1   Q       A      Z      SPACE  /      ;      P       -
--    2   X       C      V      B      N      M      ,       -
--    3   S       D      F      G      H      J      K       -
--    4   W       E      R      T      Y      U      I       -
--    5   .       L      O      LF     RETURN -      -       -
--    6   8       9      0      :      -      RUBOUT -       -
--    7   1       2      3      4      5      6      7       -
--
-- PS/2 keys used: the letters, digits and punctuation in the same places,
-- Space, Enter (RETURN), Backspace (RUB OUT), Esc and Tab (ESC), either
-- Ctrl (CTRL), Left / Right Shift, [ (LINE FEED), # or \ (REPEAT),
-- PS/2 '-' (OSI ':'), PS/2 '=' (OSI '-'). SHIFT LOCK follows Caps Lock
-- (on at power-up, as OSI software wants capitals).
--
-- Polarity (inv):
--   inv = '0'  Challenger 1P / Superboard / MAME: a 0 bit in the row byte
--              selects that row, and a key that is down reads as 0.
--   inv = '1'  the same with both inverted (1 selects, down reads as 1).
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity osi_kbd is
  port (
    clk      : in  std_logic;
    rst      : in  std_logic;
    -- raw key events from ps2_kbd
    sc_valid : in  std_logic;
    sc_code  : in  std_logic_vector(7 downto 0);
    sc_ext   : in  std_logic;
    sc_brk   : in  std_logic;
    caps_on  : in  std_logic;
    -- CPU side
    wr_stb   : in  std_logic;                       -- write to $DF00
    din      : in  std_logic_vector(7 downto 0);
    inv      : in  std_logic;
    dout     : out std_logic_vector(7 downto 0);
    -- diagnostics ($DF01)
    last_code : out std_logic_vector(7 downto 0)    -- last key code pressed
  );
end entity;

architecture rtl of osi_kbd is
  -- key(r*8 + c) = '1' while the key at row r, bit c is down
  signal key   : std_logic_vector(63 downto 0) := (others => '0');
  signal latch : std_logic_vector(7 downto 0) := (others => '1');
  signal lastc : std_logic_vector(7 downto 0) := (others => '0');

  -- matrix position (row*8 + bit) for a set-2 code; 0 = not an OSI key
  -- (position 0 is SHIFT LOCK, which comes from caps_on instead)
  function pos (c : std_logic_vector(7 downto 0); e : std_logic)
    return natural is
  begin
    if e = '1' then
      case c is
        when x"14" => return 0*8 + 6;           -- right Ctrl
        when x"5A" => return 5*8 + 3;           -- keypad Enter
        when x"4A" => return 1*8 + 3;           -- keypad /
        when others => return 0;
      end case;
    end if;
    case c is
      -- row 0
      when x"59" => return 0*8 + 1;  when x"12" => return 0*8 + 2;
      when x"76" => return 0*8 + 5;  when x"0D" => return 0*8 + 5;
      when x"14" => return 0*8 + 6;  when x"5D" => return 0*8 + 7;
      when x"61" => return 0*8 + 7;
      -- row 1
      when x"4D" => return 1*8 + 1;  when x"4C" => return 1*8 + 2;
      when x"4A" => return 1*8 + 3;  when x"29" => return 1*8 + 4;
      when x"1A" => return 1*8 + 5;  when x"1C" => return 1*8 + 6;
      when x"15" => return 1*8 + 7;
      -- row 2
      when x"41" => return 2*8 + 1;  when x"3A" => return 2*8 + 2;
      when x"31" => return 2*8 + 3;  when x"32" => return 2*8 + 4;
      when x"2A" => return 2*8 + 5;  when x"21" => return 2*8 + 6;
      when x"22" => return 2*8 + 7;
      -- row 3
      when x"42" => return 3*8 + 1;  when x"3B" => return 3*8 + 2;
      when x"33" => return 3*8 + 3;  when x"34" => return 3*8 + 4;
      when x"2B" => return 3*8 + 5;  when x"23" => return 3*8 + 6;
      when x"1B" => return 3*8 + 7;
      -- row 4
      when x"43" => return 4*8 + 1;  when x"3C" => return 4*8 + 2;
      when x"35" => return 4*8 + 3;  when x"2C" => return 4*8 + 4;
      when x"2D" => return 4*8 + 5;  when x"24" => return 4*8 + 6;
      when x"1D" => return 4*8 + 7;
      -- row 5
      when x"5A" => return 5*8 + 3;  when x"54" => return 5*8 + 4;
      when x"44" => return 5*8 + 5;  when x"4B" => return 5*8 + 6;
      when x"49" => return 5*8 + 7;
      -- row 6
      when x"66" => return 6*8 + 2;  when x"55" => return 6*8 + 3;
      when x"4E" => return 6*8 + 4;  when x"45" => return 6*8 + 5;
      when x"46" => return 6*8 + 6;  when x"3E" => return 6*8 + 7;
      -- row 7
      when x"3D" => return 7*8 + 1;  when x"36" => return 7*8 + 2;
      when x"2E" => return 7*8 + 3;  when x"25" => return 7*8 + 4;
      when x"26" => return 7*8 + 5;  when x"1E" => return 7*8 + 6;
      when x"16" => return 7*8 + 7;
      when others => return 0;
    end case;
  end function;

begin

  process (clk)
    variable p : natural range 0 to 63;
  begin
    if rising_edge(clk) then
      if sc_valid = '1' then
        p := pos(sc_code, sc_ext);
        if p /= 0 then
          key(p) <= not sc_brk;
        end if;
        if sc_brk = '0' then
          lastc <= sc_code;
        end if;
      end if;
      if wr_stb = '1' then
        latch <= din;
      end if;
      if rst = '1' then
        key   <= (others => '0');
        latch <= (others => '1');
      end if;
    end if;
  end process;

  last_code <= lastc;

  -- columns of the selected rows (key down = '1' here), then the polarity
  process (key, latch, inv, caps_on)
    variable k   : std_logic_vector(63 downto 0);
    variable col : std_logic_vector(7 downto 0);
    variable sel : std_logic;
  begin
    k := key;
    k(0) := caps_on;                            -- SHIFT LOCK
    col := (others => '0');
    for r in 0 to 7 loop
      sel := latch(r) xnor inv;                 -- inv=0: a 0 selects the row
      if sel = '1' then
        col := col or k(r*8 + 7 downto r*8);
      end if;
    end loop;
    if inv = '1' then
      dout <= col;
    else
      dout <= not col;
    end if;
  end process;

end architecture;
