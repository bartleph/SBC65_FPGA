-- ============================================================================
-- vdu_composite.vhd - 80 x 32 (PAL) / 80 x 28 (NTSC) text, composite output
--
--   Screen memory : 4K, row-major, 128 bytes per row (byte at row*128+col,
--                   columns 80-127 unused), read through the second port.
--   Characters    : 6x8 cells (5x7 font), codes $00-$7F normal, $80-$FF
--                   inverse video (made here, not stored in the font).
--                   Font bit 7 = leftmost pixel.
--   OSI mode      : osi='1': 64 columns of 8x8 cells and all 256 font
--                   codes as stored (the OSI graphics live in font codes
--                   $00-$1F and $80-$FF), no inverse, no cursor.
--   Timing        : ntsc='0': PAL 50 Hz, 312 lines of 64 us, 32 text rows.
--                   ntsc='1': NTSC 60 Hz, 262 lines of 63.56 us, 28 text
--                   rows (an NTSC picture has no room for 32).
--                   Both non-interlaced ("240p" style), which every TV and
--                   capture stick accepts. Monochrome, so no colour burst.
--                   Pixel clock 12.5 MHz -> 480 pixels = 38.4 us of the
--                   line, centred, so all 80 columns clear the TV's overscan.
--   Scrolling     : top_row says which RAM row is shown at the top, so the
--                   terminal can scroll by changing one register.
--   Cursor        : the character at (cur_row, cur_col) - counted from the
--                   top of the screen - is shown inverted, blinking ~1.5 Hz.
--   Outputs       : sync_n ('0' = sync tip) and video ('1' = white), meant
--                   for the board's resistor network into the RCA socket.
--                   During sync both are '0'.
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;


entity vdu_composite is
  port (
    clk      : in  std_logic;                       -- 50 MHz
    scr_addr : out std_logic_vector(11 downto 0);
    scr_q    : in  std_logic_vector(7 downto 0);    -- valid 1 clock after addr
    top_row  : in  unsigned(4 downto 0);
    cur_row  : in  unsigned(4 downto 0);
    cur_col  : in  unsigned(6 downto 0);
    cur_on   : in  std_logic;
    ntsc     : in  std_logic;
    osi      : in  std_logic;
    sync_n   : out std_logic;
    video    : out std_logic
  );
end entity;

architecture rtl of vdu_composite is
  constant H_SYNC  : natural := 235;    -- 4.7 us
  constant H_MAX   : natural := 3200;
  constant H_START : natural := 860;    -- first text pixel (~17.2 us)
  constant H_START_OSI : natural := 796; -- 64 x 8 px is 128 clocks wider
  constant V_MAX   : natural := 312;
  constant V_BROAD : natural := 3;      -- lines 0-2: broad (vertical) sync
  -- terminal: 80 columns of 24 clocks (6 px x 4); OSI: 64 of 32 (8 px x 4)
  signal COLS      : natural range 0 to 80;
  signal SLOT_LAST : natural range 0 to 31;    -- clocks per character - 1
  signal H_FETCH   : natural range 0 to 1023;  -- h where slot 0 starts - 1
  -- PAL: 3200 clocks (64 us), 312 lines, text lines 40-295 (32 rows)
  -- NTSC: 3178 clocks (63.56 us), 262 lines, text lines 32-255 (28 rows)
  -- (the first text line must be a multiple of 8)
  signal H_TOTAL : natural range 0 to H_MAX;
  signal H_HALF  : natural range 0 to H_MAX;
  signal V_TOTAL : natural range 0 to V_MAX;
  signal V_START : natural range 0 to V_MAX;
  signal TEXT_H  : natural range 0 to V_MAX;
  -- the same, pre-combined, so no adders are needed in the comparisons
  signal H_LAST, H_B1, H_B2 : natural range 0 to H_MAX;
  signal V_LAST, V_STOP     : natural range 0 to V_MAX;

  signal h      : natural range 0 to H_MAX - 1 := 0;
  signal v      : natural range 0 to V_MAX - 1 := 0;

  signal font_addr : std_logic_vector(10 downto 0);
  signal font_q    : std_logic_vector(7 downto 0);   -- 1 clock after font_addr
  signal next_bits : std_logic_vector(7 downto 0) := (others => '0');
  signal shreg     : std_logic_vector(7 downto 0) := (others => '0');
  signal sync_r    : std_logic := '1';
  signal vid_r     : std_logic := '0';
  signal frame     : unsigned(4 downto 0) := (others => '0');
  signal is_cur    : boolean := false;
  signal col_c     : natural range 0 to 127 := 127;
  signal sub_c     : natural range 0 to 31 := 0;
begin

  COLS      <= 64 when osi = '1' else 80;
  SLOT_LAST <= 31 when osi = '1' else 23;
  H_FETCH   <= H_START_OSI - 32 - 1 when osi = '1' else H_START - 24 - 1;

  H_TOTAL <= 3178 when ntsc = '1' else 3200;
  H_HALF  <= 1589 when ntsc = '1' else 1600;
  V_TOTAL <= 262  when ntsc = '1' else 312;
  V_START <= 32   when ntsc = '1' else 40;
  TEXT_H  <= 224  when ntsc = '1' else 256;
  H_LAST  <= 3177 when ntsc = '1' else 3199;          -- H_TOTAL - 1
  H_B1    <= 1589 - H_SYNC when ntsc = '1' else 1600 - H_SYNC;
  H_B2    <= 3178 - H_SYNC when ntsc = '1' else 3200 - H_SYNC;
  V_LAST  <= 261  when ntsc = '1' else 311;           -- V_TOTAL - 1
  V_STOP  <= 256  when ntsc = '1' else 296;           -- V_START + TEXT_H

  sync_n <= sync_r;
  video  <= vid_r;

  -- character generator: address = character code * 8 + scan line.
  -- V_START is a multiple of 8, so the scan line is the low 3 bits of v.
  -- (terminal mode: codes $80-$FF use the $00-$7F glyphs, inverted below)
  font_addr <= (scr_q(7) and osi) & scr_q(6 downto 0) &
               std_logic_vector(to_unsigned(v mod 8, 3));

  u_font : entity work.rom_font
    port map (clk => clk, addr => font_addr, dout => font_q);

  process (clk)
    variable col   : natural range 0 to 127;
    variable sub   : natural range 0 to 31;
    variable bits  : std_logic_vector(7 downto 0);
    variable ty    : natural range 0 to 511;
    variable in_ty : boolean;
  begin
    if rising_edge(clk) then
      -------------------------------------------------- counters
      if h >= H_LAST then
        h <= 0;
        if v >= V_LAST then
          v <= 0;
          frame <= frame + 1;
        else
          v <= v + 1;
        end if;
      else
        h <= h + 1;
      end if;

      -------------------------------------------------- sync
      if v < V_BROAD then
        -- broad pulses: low except the last 4.7 us of each half line
        if (h < H_B1) or (h >= H_HALF and h < H_B2) then
          sync_r <= '0';
        else
          sync_r <= '1';
        end if;
      else
        if h < H_SYNC then sync_r <= '0'; else sync_r <= '1'; end if;
      end if;

      -------------------------------------------------- text
      in_ty := (v >= V_START) and (v < V_STOP);
      if in_ty then ty := v - V_START; else ty := 0; end if;

      -- character slot (col) and clock within it (sub). Counters rather
      -- than h / 24 and h mod 24, which would cost a divider. Slot 0 starts
      -- at h = H_START - SLOT and fetches column 0; outside the text col=127.
      col := col_c;
      sub := sub_c;
      if h = H_FETCH then
        col_c <= 0;
        sub_c <= 0;
      elsif col_c /= 127 then
        if sub_c = SLOT_LAST then
          sub_c <= 0;
          if col_c = COLS then col_c <= 127; else col_c <= col_c + 1; end if;
        else
          sub_c <= sub_c + 1;
        end if;
      end if;

      -- fetch pipeline for the character shown in the NEXT slot
      if col < COLS and in_ty then
        if sub = 0 then
          scr_addr <= std_logic_vector(
                        (to_unsigned(ty / 8, 5) + top_row) & to_unsigned(col, 7));
          is_cur <= to_unsigned(ty / 8, 5) = cur_row and
                    to_unsigned(col, 7) = cur_col and
                    cur_on = '1' and frame(4) = '1';
        elsif sub = 3 then
          bits := font_q;
          if scr_q(7) = '1' and osi = '0' then
            bits := bits xor "11111100";              -- inverse (6 pixels)
          end if;
          if is_cur then
            bits := not bits;
          end if;
          next_bits <= bits;
        end if;
      end if;

      -- pixel shifter: 4 clocks per pixel, load at the start of each slot
      if col >= 1 and col <= COLS and in_ty and sub mod 4 = 3 then
        shreg <= shreg(6 downto 0) & '0';
      end if;
      if sub = SLOT_LAST then
        if col < COLS and in_ty then
          shreg <= next_bits;
        else
          shreg <= (others => '0');
        end if;
      end if;

      if col >= 1 and col <= COLS and in_ty then
        vid_r <= shreg(7);
      else
        vid_r <= '0';
      end if;
      if sync_r = '0' then
        vid_r <= '0';
      end if;
    end if;
  end process;

end architecture;
