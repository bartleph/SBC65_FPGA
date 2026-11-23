-- ============================================================================
-- mem_blocks.vhd - memories written to Quartus's own inference templates
-- so each one maps onto M9K block RAM:
--
--   tdpram    true dual-port RAM, single clock           (screen RAM)
--   romblk_a    8K ROM $A000-$BFFF  \
--   romblk_cd   8K ROM $C000-$DFFF   > from rom_image_pkg
--   romblk_e    8K ROM $E000-$FFFF  /
--   rom_font  2K character generator from font_pkg
-- ============================================================================

-------------------------------------------------------------------- tdpram
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tdpram is
  generic (ABITS : natural := 11);
  port (
    clk    : in  std_logic;
    -- port A (CPU)
    we_a   : in  std_logic;
    addr_a : in  std_logic_vector(ABITS - 1 downto 0);
    din_a  : in  std_logic_vector(7 downto 0);
    dout_a : out std_logic_vector(7 downto 0);
    -- port B (video, read only)
    addr_b : in  std_logic_vector(ABITS - 1 downto 0);
    dout_b : out std_logic_vector(7 downto 0)
  );
end entity;

architecture rtl of tdpram is
  type mem_t is array (0 to 2**ABITS - 1) of std_logic_vector(7 downto 0);
  shared variable mem : mem_t := (others => x"20");   -- screen starts blank
begin
  port_a : process (clk)
  begin
    if rising_edge(clk) then
      if we_a = '1' then
        mem(to_integer(unsigned(addr_a))) := din_a;
      end if;
      dout_a <= mem(to_integer(unsigned(addr_a)));
    end if;
  end process;

  port_b : process (clk)
  begin
    if rising_edge(clk) then
      dout_b <= mem(to_integer(unsigned(addr_b)));
    end if;
  end process;
end architecture;

-------------------------------------------------------------------- romblk_a
-- $A000-$BFFF
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rom_image_pkg.all;

entity romblk_a is
  port (
    clk  : in  std_logic;
    addr : in  std_logic_vector(12 downto 0);
    dout : out std_logic_vector(7 downto 0)
  );
end entity;

architecture rtl of romblk_a is
begin
  process (clk)
  begin
    if rising_edge(clk) then
      dout <= ROM_A(to_integer(unsigned(addr)));
    end if;
  end process;
end architecture;

-------------------------------------------------------------------- romblk_cd
-- $C000-$DFFF in one 8K block ($C000-$C0FF is not decoded: I/O hole).
-- All three ROMs are 8K deep, so when Quartus packs them side by side
-- into one wide ROM (they share the CPU address lines) nothing is wasted.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rom_image_pkg.all;

entity romblk_cd is
  port (
    clk  : in  std_logic;
    addr : in  std_logic_vector(12 downto 0);
    dout : out std_logic_vector(7 downto 0)
  );
end entity;

architecture rtl of romblk_cd is
begin
  process (clk)
  begin
    if rising_edge(clk) then
      dout <= ROM_CD(to_integer(unsigned(addr)));
    end if;
  end process;
end architecture;

-------------------------------------------------------------------- romblk_e
-- $E000-$FFFF
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rom_image_pkg.all;

entity romblk_e is
  port (
    clk  : in  std_logic;
    addr : in  std_logic_vector(12 downto 0);
    dout : out std_logic_vector(7 downto 0)
  );
end entity;

architecture rtl of romblk_e is
begin
  process (clk)
  begin
    if rising_edge(clk) then
      dout <= ROM_E(to_integer(unsigned(addr)));
    end if;
  end process;
end architecture;

-------------------------------------------------------------------- rom_font
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.font_pkg.all;

entity rom_font is
  port (
    clk  : in  std_logic;
    addr : in  std_logic_vector(10 downto 0);   -- char * 8 + row
    dout : out std_logic_vector(7 downto 0)
  );
end entity;

architecture rtl of rom_font is
begin
  process (clk)
  begin
    if rising_edge(clk) then
      dout <= FONT_DATA(to_integer(unsigned(addr)));
    end if;
  end process;
end architecture;
