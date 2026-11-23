-- Testbench: runs the whole SBC with the test ROM.
--  * decodes the serial console output and prints it
--  * after the prompt, types 'h' on the PS/2 keyboard and "i<CR>" on serial
--  * checks the composite sync timing
--  * captures one video frame to frame.pgm (800 x 312 samples, 80 ns each)
-- Uses a fast CPU clock and baud rate so the simulation finishes sooner.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity tb_sd_sys is
end entity;

architecture sim of tb_sd_sys is
  constant CLK_HZ  : natural := 50_000_000;
  constant BAUD    : natural := 2_500_000;          -- 20 clocks per bit
  constant BIT_T   : time := 400 ns;
  signal clk      : std_logic := '0';
  signal rst_n    : std_logic := '0';
  signal txd      : std_logic;
  signal rxd      : std_logic := '1';
  signal sync_n   : std_logic;
  signal video    : std_logic;
  signal kclk     : std_logic := '1';
  signal kdat     : std_logic := '1';
  -- SRAM
  signal sram_a   : std_logic_vector(16 downto 0);
  signal sram_d   : std_logic_vector(7 downto 0);
  signal sram_ce_n, sram_ce2, sram_oe_n, sram_we_n : std_logic;
  type sram_t is array (0 to 65535) of std_logic_vector(7 downto 0);
  signal sram     : sram_t := (others => x"00");
  signal sd_cs, sd_clk, sd_mosi, sd_miso : std_logic;
  signal sd_cd    : std_logic := '0';
  signal nrd, nwr : natural := 0;
  signal stars    : natural := 0;
  signal done     : boolean := false;
  signal prompt   : boolean := false;
  signal first_c  : boolean := false;
  signal grab     : boolean := false;
  signal grabbed  : boolean := false;
  shared variable transcript : line;
begin
  clk <= not clk after 10 ns when not done;

  dut : entity work.sbc65_top
    generic map (CLK_HZ => CLK_HZ, CPU_DIV => 10, BAUD => BAUD)
    port map (clk50 => clk, uart_txd => txd, uart_rxd => rxd,
              av_sync_n => sync_n, av_video => video,
              ps2_clk => kclk, ps2_data => kdat,
              sram_a => sram_a, sram_d => sram_d, sram_ce_n => sram_ce_n,
              sram_ce2 => sram_ce2, sram_oe_n => sram_oe_n, sram_we_n => sram_we_n,
              sd_cs => sd_cs, sd_clk => sd_clk, sd_mosi => sd_mosi,
              sd_miso => sd_miso, sd_cd => sd_cd);

  card : entity work.sd_model
    generic map (IMAGE => "card.img", BLOCKS => 14848)
    port map (cs => sd_cs, sclk => sd_clk, mosi => sd_mosi, miso => sd_miso,
              nreads => nrd, nwrites => nwr);

  -- AS6C1008 model (55 ns): only A15..A0 are used by the design
  sram_d <= sram(to_integer(unsigned(sram_a(15 downto 0)))) after 30 ns
              when sram_oe_n = '0' and sram_we_n = '1' and sram_ce_n = '0' and sram_ce2 = '1'
            else (others => 'Z');
  sram_wr : process (sram_we_n)
  begin
    if rising_edge(sram_we_n) and sram_ce_n = '0' then
      assert sram_a(16) = '0' report "A16 not low" severity error;
      sram(to_integer(unsigned(sram_a(15 downto 0)))) <= sram_d;
    end if;
  end process;
  -- check the write pulse is long enough (tWP >= 45 ns)
  sram_tw : process
    variable t0 : time;
  begin
    wait until falling_edge(sram_we_n);
    t0 := now;
    wait until rising_edge(sram_we_n);
    assert now - t0 >= 45 ns report "SRAM /WE pulse too short" severity error;
  end process;

  -- decode serial TX
  rx_mon : process
    variable b : std_logic_vector(7 downto 0);
    variable colons : natural := 0;
  begin
    wait until txd = '0';
    wait for BIT_T * 1.5;
    for i in 0 to 7 loop
      b(i) := txd;
      wait for BIT_T;
    end loop;
    assert txd = '1' report "framing error on TX" severity error;
    if b = x"2A" then stars <= stars + 1; end if;  -- '*' = DOS prompt
    if false then
      colons := colons + 1;
      if colons = 1 then first_c <= true; end if;
      if colons = 5 then prompt <= true; end if;   -- F10 reset re-prints 1 colon
    end if;
    if b = x"0A" then
      writeline(output, transcript);
    elsif b /= x"0D" then
      write(transcript, character'val(to_integer(unsigned(b))));
    end if;
  end process;

  -- composite sync timing check (ordinary lines only)
  sync_mon : process
    variable t_fall, t_rise, t_prev : time := 0 ns;
    variable n : natural := 0;
  begin
    wait until falling_edge(sync_n);
    t_fall := now;
    wait until rising_edge(sync_n);
    t_rise := now;
    if n = 400 then
      report "sync pulse " & time'image(t_rise - t_fall) &
             ", line period " & time'image(t_fall - t_prev);
    end if;
    t_prev := t_fall;
    n := n + 1;
  end process;

  -- frame grabber: starts at the line after the broad (vertical) sync
  grabber : process
    file f : text;
    variable l : line;
    variable lines, t_fall : integer;
    variable broad : natural;
  begin
    wait until grab;
    -- find the end of a vertical sync: a sync pulse longer than 20 us
    loop
      wait until falling_edge(sync_n);
      t_fall := now / 1 ns;
      wait until rising_edge(sync_n);
      exit when (now / 1 ns) - t_fall > 20_000;
    end loop;
    -- skip the rest of the broad pulses
    broad := 0;
    loop
      wait until falling_edge(sync_n);
      t_fall := now / 1 ns;
      wait until rising_edge(sync_n);
      exit when (now / 1 ns) - t_fall < 10_000;
    end loop;
    file_open(f, "frame.pgm", write_mode);
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
    procedure send(c : character) is
      variable b : std_logic_vector(7 downto 0);
    begin
      b := std_logic_vector(to_unsigned(character'pos(c), 8));
      rxd <= '0'; wait for BIT_T;
      for i in 0 to 7 loop rxd <= b(i); wait for BIT_T; end loop;
      rxd <= '1'; wait for 300 us;
    end procedure;
  begin
    wait until stars = 1;                 -- "A*" after the cold start
    report "prompt; SD reads so far " & integer'image(nrd);
    wait for 200 us;
    send('D'); send('I'); send(CR);
    wait until stars = 2 for 400 ms;
    wait for 100 us;
    report "after DI: SD reads " & integer'image(nrd) & ", writes " & integer'image(nwr);
    done <= true;
    wait;
  end process;
end architecture;
