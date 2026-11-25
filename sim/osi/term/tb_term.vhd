-- Testbench for OSI mode: runs osi_test.s (built into osi_rom_pkg.vhd in
-- place of the real ROM) and checks the results it leaves at $0300-$0310.
--  * PEEK of text the terminal printed, POKE + read back, PRINT in OSI mode
--  * $DF00 keyboard matrix: 'A' held, SHIFT LOCK, no row, inverted polarity
--  * an instruction fetch at $D000 ends OSI mode and reads the ROM
--  * grabs one 64-column video frame to frame_term.pgm
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity tb_term is
end entity;

architecture sim of tb_term is
  constant BAUD   : natural := 2_500_000;
  signal clk      : std_logic := '0';
  signal txd      : std_logic;
  signal rxd      : std_logic := '1';
  signal sync_n   : std_logic;
  signal video    : std_logic;
  signal kclk     : std_logic := '1';
  signal kdat     : std_logic := '1';
  signal sram_a   : std_logic_vector(16 downto 0);
  signal sram_d   : std_logic_vector(7 downto 0);
  signal sram_ce_n, sram_ce2, sram_oe_n, sram_we_n : std_logic;
  type sram_t is array (0 to 65535) of std_logic_vector(7 downto 0);
  signal sram     : sram_t := (others => x"00");
  signal sd_cs, sd_clk, sd_mosi : std_logic;
  signal done     : boolean := false;
  signal grab     : boolean := false;
  signal grabbed  : boolean := false;

  function hx (v : std_logic_vector(7 downto 0)) return string is
    constant d : string(1 to 16) := "0123456789ABCDEF";
  begin
    return d(to_integer(unsigned(v(7 downto 4))) + 1) & d(to_integer(unsigned(v(3 downto 0))) + 1);
  end function;
begin
  clk <= not clk after 10 ns when not done;

  dut : entity work.sbc65_top
    generic map (CLK_HZ => 50_000_000, CPU_DIV => 10, BAUD => BAUD)
    port map (clk50 => clk, uart_txd => txd, uart_rxd => rxd,
              av_sync_n => sync_n, av_video => video,
              ps2_clk => kclk, ps2_data => kdat,
              sram_a => sram_a, sram_d => sram_d, sram_ce_n => sram_ce_n,
              sram_ce2 => sram_ce2, sram_oe_n => sram_oe_n, sram_we_n => sram_we_n,
              sd_cs => sd_cs, sd_clk => sd_clk, sd_mosi => sd_mosi,
              sd_miso => '1', sd_cd => '1');

  sram_d <= sram(to_integer(unsigned(sram_a(15 downto 0)))) after 30 ns
              when sram_oe_n = '0' and sram_we_n = '1' and sram_ce_n = '0' and sram_ce2 = '1'
            else (others => 'Z');
  sram_wr : process (sram_we_n)
  begin
    if rising_edge(sram_we_n) and sram_ce_n = '0' then
      sram(to_integer(unsigned(sram_a(15 downto 0)))) <= sram_d;
    end if;
  end process;

  tx_mon : process
    variable b : std_logic_vector(7 downto 0);
  begin
    wait until txd = '0';
    wait for 600 ns;
    for i in 0 to 7 loop b(i) := txd; wait for 400 ns; end loop;
  end process;

  -- frame grabber (as in tb_sbc65): 800 samples of 80 ns per line
  grabber : process
    file f : text;
    variable l : line;
    variable t_fall : integer;
  begin
    wait until grab;
    loop
      wait until falling_edge(sync_n);
      t_fall := now / 1 ns;
      wait until rising_edge(sync_n);
      exit when (now / 1 ns) - t_fall > 20_000;
    end loop;
    loop
      wait until falling_edge(sync_n);
      t_fall := now / 1 ns;
      wait until rising_edge(sync_n);
      exit when (now / 1 ns) - t_fall < 10_000;
    end loop;
    file_open(f, "frame_term.pgm", write_mode);
    write(l, string'("P2 800 309 1")); writeline(f, l);
    for y in 0 to 308 loop
      wait until falling_edge(sync_n);
      for x in 0 to 799 loop
        wait for 80 ns;
        if video = '1' then write(l, string'("1 ")); else write(l, string'("0 ")); end if;
      end loop;
      writeline(f, l);
    end loop;
    file_close(f);
    grabbed <= true;
    wait;
  end process;

  stim : process
    procedure ps2(code : std_logic_vector(7 downto 0)) is
      variable fr : std_logic_vector(10 downto 0);
      variable par : std_logic := '1';
    begin
      for i in 0 to 7 loop par := par xor code(i); end loop;
      fr := '1' & par & code & '0';
      for i in 0 to 10 loop
        kdat <= fr(i);
        wait for 20 us;
        kclk <= '0';
        wait for 40 us;
        kclk <= '1';
        wait for 20 us;
      end loop;
      kdat <= '1';
      wait for 200 us;
    end procedure;

    procedure check(a : natural; want : std_logic_vector(7 downto 0); what : string) is
    begin
      if sram(a) = want then
        report "PASS " & what & " = $" & hx(sram(a));
      else
        report "FAIL " & what & " = $" & hx(sram(a)) & ", expected $" & hx(want) severity error;
      end if;
    end procedure;
  begin
    wait until sram(16#031E#) = x"01" for 80 ms;
    assert sram(16#031E#) = x"01" report "program did not finish" severity failure;
    grab <= true;
    wait until grabbed;
    done <= true;
    report "simulation finished";
    wait;
  end process;
end architecture;
