-- ============================================================================
-- sbc65_top.vhd  -  65C02 SBC on Cyclone 10 LP 10CL006 core board
--
--   $0000-$BFFF  RAM 48K   external AS6C1008 SRAM (A16 held low; the
--                upper 64K of the chip is unused)
--   $A000-$BFFF  Forth ROM 8K (on-chip) instead of the RAM while the bank
--                latch bit 0 is 1 (set by FT, cleared by BYE / reset).
--                Writes there then go nowhere; the RAM below is kept.
--   $C000-$C0FF  I/O page ($C000-$C01F: old disk PIA/ACIA, not fitted, $FF)
--     $C080-$C081  ACIA 6850 console (mirrored to $C08F)
--     $C090-$C09F  minimal 6522 VIA: ORB/IRB ($C090) and DDRB ($C092) only.
--                  Port B drives the SD card module:
--                  PB0 CLK, PB1 DI (MOSI), PB2 CS (out)  PB6 CD, PB7 DO (in).
--                  Other registers read $FF and ignore writes.
--     $C0A0        bank latch (reads back; bits 7-3 read 1; mirrored to $C0AF)
--                  bit 0 = 1 maps the Forth ROM at $A000
--                  bit 1 = 1 OSI mode (see below)
--                  bit 2 = OSI keyboard polarity: 0 = C1P style (a 0 selects
--                          a row, a key down reads 0), 1 = both inverted
--   $C100-$CFFF  ROM 3.75K (on-chip) - the SD card driver
--   $D000-$DFFF  ROM 4K   > on-chip, contents from rom_image_pkg.vhd
--   $E000-$FFFF  ROM 8K  /
--
--   OSI mode (bank latch bit 1) - for OSI BASIC programs that PEEK and POKE
--   the screen and keyboard like a C2/C4:
--   $D000-$D7FF  screen: 32 rows of 64 bytes, read / write, shown 64 x 32 on
--                the composite output with the OSI character set. It is the
--                terminal's own screen, so text the CPU prints through the
--                ACIA appears there too (the terminal wraps at 64 columns).
--   $DF00        OSI keyboard matrix from the PS/2 keyboard (osi_kbd.vhd)
--                (the whole of $D800-$DFFF answers: even addresses the
--                matrix, odd ones the last PS/2 key code - diagnostics)
--   While a DOSX command runs (from fetching code at $D000-$DFFF until code
--   is next run from RAM) $D000-$DFFF is the ROM, so DOS commands keep
--   working without leaving OSI mode. BASIC and programs in RAM see the
--   screen and keyboard.
--   Diagnostics: $DF01 reads the last PS/2 key code pressed.
--
--   Screen + PS/2 keyboard form a built-in terminal: everything the CPU sends
--   through the ACIA is shown on the composite output (terminal.vhd), and key
--   presses arrive through the ACIA receiver alongside the serial port.
--
-- M9K use: 24 ROM (3 x 8K) + 4 screen + 2 character set = 30 of 30
-- (OSI mode adds no memory blocks: it uses the terminal's screen RAM).
--
-- Clocking: everything runs from the 50 MHz board clock. The CPU clock is
-- 50 MHz / CPU_DIV (default 50 -> 1 MHz, same as the real SBC). Memory and
-- I/O are accessed once per CPU cycle at mid-cycle (the "phi2 falling
-- edge" point), and the read data is ready long before the CPU samples it
-- on its next rising edge. SRAM writes get a /WE pulse in the second half of
-- the cycle.
--
-- CPU core: cpu65c02_true_cycle by Jens Gutschmidt (OpenCores, GPL v3),
-- compiled into VHDL library "r65c02_tc".
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;


library r65c02_tc;

entity sbc65_top is
  generic (
    CLK_HZ  : natural := 50_000_000;
    CPU_DIV : natural := 50;        -- even, >= 10: 50 -> 1 MHz, 24 -> ~2 MHz, 10 -> 5 MHz
    BAUD    : natural := 19200
  );
  port (
    clk50    : in  std_logic;
    uart_txd : out std_logic;       -- to terminal / ESP32 RX
    uart_rxd : in  std_logic;       -- from terminal / ESP32 TX
    av_sync_n: out std_logic;       -- composite sync  (PIN_31)
    av_video : out std_logic;       -- composite video (PIN_32)
    ps2_clk  : inout std_logic;     -- keyboard clock  (PIN_85), open-drain
    ps2_data : inout std_logic;     -- keyboard data   (PIN_84), open-drain
    -- AS6C1008 SRAM
    sram_a    : out   std_logic_vector(16 downto 0);
    sram_d    : inout std_logic_vector(7 downto 0);
    sram_ce_n : out   std_logic;
    sram_ce2  : out   std_logic;
    sram_oe_n : out   std_logic;
    sram_we_n : out   std_logic;
    -- SD card module on VIA port B
    sd_cs     : out   std_logic;     -- PB2
    sd_clk    : out   std_logic;     -- PB0
    sd_mosi   : out   std_logic;     -- PB1  (module pin DI)
    sd_miso   : in    std_logic;     -- PB7  (module pin DO)
    sd_cd     : in    std_logic      -- PB6  (card detect)
  );
end entity;

architecture rtl of sbc65_top is


  -- clock / strobes
  signal div_cnt   : natural range 0 to CPU_DIV - 1 := 0;
  signal cpu_clk   : std_logic := '0';
  signal bus_stb   : std_logic := '0';     -- mid-cycle strobe
  signal bus_stb_d : std_logic := '0';     -- one clock later (data mux)
  signal bus_stb_d2: std_logic := '0';     -- two clocks later (screen reads)

  -- reset
  signal por_cnt   : unsigned(19 downto 0) := (others => '0');  -- ~21 ms
  signal rst       : std_logic := '1';
  signal rst_n     : std_logic := '0';
  signal por_done  : std_logic := '0';     -- power-on reset finished
  signal kb_reset  : std_logic;            -- F10 pressed
  signal kb_mode   : std_logic;            -- F9 pressed
  signal ntsc      : std_logic := '0';     -- screen standard (power-up: PAL)
  signal rst_por   : std_logic := '1';     -- power-on only (keyboard logic)

  -- CPU bus
  signal cpu_a     : std_logic_vector(15 downto 0);
  signal cpu_do    : std_logic_vector(7 downto 0);
  signal cpu_di    : std_logic_vector(7 downto 0) := x"FF";
  signal cpu_wr    : std_logic;
  signal cpu_sync  : std_logic;   -- opcode fetch (for simulation traces)
  signal cpu_rd_n  : std_logic;            -- '1' = read (6502 R/W style)
  signal cpu_irq_n : std_logic;
  signal a_l       : std_logic_vector(15 downto 0) := (others => '0');

  -- selects
  type sel_t is (S_SRAM, S_ACIA, S_BANK, S_VIA, S_ROMA, S_ROMC, S_ROMD, S_ROME,
                 S_VID, S_KBD, S_NONE);
  signal fbank : std_logic := '0';          -- 1: Forth ROM at $A000-$BFFF
  signal osi   : std_logic := '0';          -- 1: OSI mode
  signal kbinv : std_logic := '0';          -- OSI keyboard polarity
  signal in_dx : std_logic := '0';          -- a DOSX command is running
  signal osi_d : std_logic;                 -- this access goes to the OSI devices
  signal sel, sel_l : sel_t;

  -- memories
  signal roma_q, romcd_q, rome_q : std_logic_vector(7 downto 0);

  -- SRAM interface
  signal sr_a      : std_logic_vector(16 downto 0) := (others => '0');
  signal sr_q      : std_logic_vector(7 downto 0) := x"FF";
  signal sr_dout   : std_logic_vector(7 downto 0) := x"00";
  signal sr_drive  : std_logic := '0';
  signal sr_oe_n   : std_logic := '0';
  signal sr_we_n   : std_logic := '1';
  signal sr_wcyc   : std_logic := '0';

  -- minimal VIA (port B only)
  signal via_orb   : std_logic_vector(7 downto 0) := (others => '0');
  signal via_ddrb  : std_logic_vector(7 downto 0) := (others => '0');
  signal via_pins  : std_logic_vector(7 downto 0);
  signal via_irb   : std_logic_vector(7 downto 0);
  signal miso_s, cd_s : std_logic_vector(1 downto 0) := "11";

  -- terminal / screen
  signal tap_valid : std_logic;
  signal tap_data  : std_logic_vector(7 downto 0);
  signal t_we      : std_logic;
  signal t_addr    : std_logic_vector(11 downto 0);
  signal t_din     : std_logic_vector(7 downto 0);
  signal t_top, t_row : unsigned(4 downto 0);
  signal t_col     : unsigned(6 downto 0);

  -- VDU / keyboard
  signal vdu_addr  : std_logic_vector(11 downto 0);
  -- CPU access to the screen RAM (OSI mode): it takes port A for the clock
  -- after the strobe, while the terminal is held for that clock
  signal t_hold    : std_logic;
  signal v_acc     : std_logic := '0';
  signal v_we      : std_logic := '0';
  signal v_addr    : std_logic_vector(11 downto 0) := (others => '0');
  signal v_din     : std_logic_vector(7 downto 0) := (others => '0');
  signal scr_we    : std_logic;
  signal scr_addr  : std_logic_vector(11 downto 0);
  signal scr_din   : std_logic_vector(7 downto 0);
  signal scr_qa    : std_logic_vector(7 downto 0);
  -- OSI keyboard
  signal sc_valid, sc_ext, sc_brk, caps_on : std_logic;
  signal sc_code   : std_logic_vector(7 downto 0);
  signal okb_wr    : std_logic;
  signal okb_q     : std_logic_vector(7 downto 0);
  signal okb_code  : std_logic_vector(7 downto 0);   -- diagnostics
  signal cur_on    : std_logic;                -- no cursor in OSI mode
  signal vdu_q     : std_logic_vector(7 downto 0);
  signal kb_valid  : std_logic;
  signal kb_data   : std_logic_vector(7 downto 0);
  signal kb_ack    : std_logic;

  -- ACIA
  signal acia_stb  : std_logic;
  signal acia_q    : std_logic_vector(7 downto 0);

begin

  assert CPU_DIV >= 10 and CPU_DIV mod 2 = 0
    report "CPU_DIV must be even and at least 10 (5 MHz max with external SRAM)"
    severity failure;

  ---------------------------------------------------------------- reset
  process (clk50)
  begin
    if rising_edge(clk50) then
      -- ~21 ms reset at power-on, and again whenever F10 is pressed
      if kb_reset = '1' then
        por_cnt <= (others => '0');
        rst     <= '1';
      elsif por_cnt /= (por_cnt'range => '1') then
        por_cnt <= por_cnt + 1;
        rst     <= '1';
      else
        rst      <= '0';
        por_done <= '1';
      end if;
      rst_por <= not por_done;
    end if;
  end process;

  ---------------------------------------------------------------- CPU clock
  -- cpu_clk rises when div_cnt wraps to 0, falls at CPU_DIV/2.
  -- bus_stb fires in the same 50 MHz cycle as the falling edge.
  process (clk50)
  begin
    if rising_edge(clk50) then
      bus_stb   <= '0';
      bus_stb_d <= bus_stb;
      bus_stb_d2 <= bus_stb_d;
      if div_cnt = CPU_DIV - 1 then
        div_cnt <= 0;
        cpu_clk <= '1';
        rst_n   <= not rst;          -- reset changes only on a CPU clock edge
      else
        div_cnt <= div_cnt + 1;
      end if;
      if div_cnt = CPU_DIV/2 - 1 then
        cpu_clk <= '0';
        bus_stb <= '1';
      end if;
    end if;
  end process;

  ---------------------------------------------------------------- CPU
  u_cpu : entity r65c02_tc.r65c02_tc
    port map (
      clk_clk_i   => cpu_clk,
      d_i         => cpu_di,
      irq_n_i     => cpu_irq_n,
      nmi_n_i     => '1',
      rdy_i       => '1',
      rst_rst_n_i => rst_n,
      so_n_i      => '1',
      a_o         => cpu_a,
      d_o         => cpu_do,
      rd_o        => open,
      sync_o      => cpu_sync,
      wr_n_o      => open,
      wr_o        => cpu_wr
    );

  cpu_rd_n <= not cpu_wr;

  ---------------------------------------------------------------- decode
  -- OSI mode: $D000-$DFFF is the screen / keyboard for code run from RAM.
  -- Instruction fetches there, and everything while a DOSX command is
  -- running (in_dx), still see the DOSX ROM.
  osi_d <= '1' when osi = '1' and cpu_sync = '0' and in_dx = '0' else '0';
  sel <= S_VID  when osi_d = '1' and cpu_a(15 downto 11) = "11010" else
         S_KBD  when osi_d = '1' and cpu_a(15 downto 11) = "11011" else
         S_SRAM when cpu_a(15) = '0' or cpu_a(15 downto 13) = "100" else
         S_SRAM when cpu_a(15 downto 13) = "101" and fbank = '0' else
         S_ROMA when cpu_a(15 downto 13) = "101"  else
         S_ACIA when cpu_a(15 downto 4) = x"C08" else
         S_VIA  when cpu_a(15 downto 4) = x"C09" else
         S_BANK when cpu_a(15 downto 4) = x"C0A" else
         S_ROMC when cpu_a(15 downto 12) = "1100" and cpu_a(11 downto 8) /= "0000" else
         S_ROMD when cpu_a(15 downto 12) = "1101" else
         S_ROME when cpu_a(15 downto 13) = "111"  else
         S_NONE;

  acia_stb <= bus_stb when sel = S_ACIA else '0';

  ---------------------------------------------------------------- ROM
  -- clocked every 50 MHz cycle with the CPU address; the output is picked
  -- up by the read mux one clock after the strobe.
  u_roma : entity work.romblk_a
    port map (clk => clk50, addr => cpu_a(12 downto 0), dout => roma_q);
  u_romcd : entity work.romblk_cd
    port map (clk => clk50, addr => cpu_a(12 downto 0), dout => romcd_q);
  u_rome : entity work.romblk_e
    port map (clk => clk50, addr => cpu_a(12 downto 0), dout => rome_q);

  process (clk50)
  begin
    if rising_edge(clk50) then
      if bus_stb = '1' then
        a_l   <= cpu_a;
        sel_l <= sel;
      end if;
    end if;
  end process;

  ---------------------------------------------------------------- SRAM
  -- /CE always active. The address follows the CPU (registered, so the pins
  -- change cleanly). Reads: /OE low, data sampled at the mid-cycle strobe.
  -- Writes: from the strobe, /OE goes high, the FPGA drives the data and
  -- /WE goes low until one clock before the end of the cycle (>= 60 ns at
  -- 5 MHz, ~460 ns at 1 MHz); the data is held one clock after /WE rises.
  sram_ce_n <= '0';
  sram_ce2  <= '1';
  sram_a    <= sr_a;
  sram_oe_n <= sr_oe_n;
  sram_we_n <= sr_we_n;
  sram_d    <= sr_dout when sr_drive = '1' else (others => 'Z');

  process (clk50)
  begin
    if rising_edge(clk50) then
      sr_a <= '0' & cpu_a(15 downto 0);
      if bus_stb = '1' then
        sr_q <= to_x01(sram_d);
        if sel = S_SRAM and cpu_wr = '1' then
          sr_wcyc  <= '1';
          sr_oe_n  <= '1';
          sr_drive <= '1';
          sr_dout  <= cpu_do;
          sr_we_n  <= '0';
        end if;
      end if;
      if div_cnt = CPU_DIV - 2 then
        sr_we_n <= '1';
      end if;
      if div_cnt = CPU_DIV - 1 then
        sr_wcyc  <= '0';
        sr_drive <= '0';
        sr_oe_n  <= '0';
      end if;
    end if;
  end process;

  ---------------------------------------------------------------- VIA
  -- Port B pins: a bit set as output (DDRB=1) drives ORB; as input the
  -- output pins idle high (so CS is deselected after reset).
  via_pins(0) <= via_orb(0) when via_ddrb(0) = '1' else '1';
  via_pins(1) <= via_orb(1) when via_ddrb(1) = '1' else '1';
  via_pins(2) <= via_orb(2) when via_ddrb(2) = '1' else '1';
  via_pins(5 downto 3) <= (others => '1');
  via_pins(6) <= cd_s(1);
  via_pins(7) <= miso_s(1);
  sd_clk  <= via_pins(0);
  sd_mosi <= via_pins(1);
  sd_cs   <= via_pins(2);

  -- IRB: output bits read back ORB, input bits read the pins (6522 rule)
  gen_irb : for i in 0 to 7 generate
    via_irb(i) <= via_orb(i) when via_ddrb(i) = '1' else via_pins(i);
  end generate;

  process (clk50)
  begin
    if rising_edge(clk50) then
      miso_s <= miso_s(0) & sd_miso;
      cd_s   <= cd_s(0) & sd_cd;
      if bus_stb = '1' and sel = S_BANK and cpu_wr = '1' then
        fbank <= cpu_do(0);
        osi   <= cpu_do(1);
        kbinv <= cpu_do(2);
      end if;
      -- DOS command in progress? Code run from $D000-$DFFF (DOSX) sets this,
      -- code run from RAM ($0000-$BFFF: BASIC, user programs) clears it.
      -- While it is set, $D000-$DFFF is the DOSX ROM even for the $E000 ROM
      -- routines that DOSX calls (e.g. PRINT reading DOSX's message text).
      if bus_stb = '1' and cpu_sync = '1' then
        if cpu_a(15 downto 12) = x"D" then
          in_dx <= '1';
        elsif cpu_a(15 downto 14) /= "11" then
          in_dx <= '0';
        end if;
      end if;
      if bus_stb = '1' and sel = S_VIA and cpu_wr = '1' then
        case cpu_a(3 downto 0) is
          when x"0"   => via_orb  <= cpu_do;
          when x"2"   => via_ddrb <= cpu_do;
          when others => null;
        end case;
      end if;
      if rst = '1' then
        fbank    <= '0';
        osi      <= '0';
        kbinv    <= '0';
        via_orb  <= (others => '0');
        via_ddrb <= (others => '0');
      end if;
    end if;
  end process;

  ---------------------------------------------------------------- ACIA
  u_acia : entity work.acia6850
    generic map (CLK_HZ => CLK_HZ, BAUD => BAUD)
    port map (
      clk    => clk50,
      rst    => rst,
      cs_stb => acia_stb,
      rs     => cpu_a(0),
      rw     => cpu_rd_n,
      din    => cpu_do,
      dout   => acia_q,
      irq_n  => cpu_irq_n,
      txd    => uart_txd,
      rxd    => uart_rxd,
      ext_valid => kb_valid,
      ext_data  => kb_data,
      ext_ack   => kb_ack,
      tap_valid => tap_valid,
      tap_data  => tap_data
    );

  -- F9 toggles PAL / NTSC (kept over an F10 reset, PAL at power-up)
  process (clk50)
  begin
    if rising_edge(clk50) then
      if kb_mode = '1' then
        ntsc <= not ntsc;
      end if;
    end if;
  end process;

  ---------------------------------------------------------------- terminal
  u_term : entity work.terminal
    port map (
      clk      => clk50,
      rst      => rst,
      in_valid => tap_valid,
      in_data  => tap_data,
      ram_we   => t_we,
      ram_addr => t_addr,
      ram_din  => t_din,
      top_row  => t_top,
      cur_row  => t_row,
      cur_col  => t_col,
      ntsc     => ntsc,
      osi      => osi,
      hold     => t_hold
    );

  ---------------------------------------------------------------- screen RAM
  -- OSI address $D000 + row*64 + col is screen row "row" as you see it; the
  -- terminal scrolls by moving top_row, so the RAM row is row + top_row.
  t_hold <= '1' when bus_stb = '1' and sel = S_VID else '0';

  process (clk50)
  begin
    if rising_edge(clk50) then
      v_acc <= t_hold;
      if t_hold = '1' then
        v_we   <= cpu_wr;
        v_addr <= std_logic_vector(unsigned(cpu_a(10 downto 6)) + t_top) &
                  '0' & cpu_a(5 downto 0);
        v_din  <= cpu_do;
      end if;
    end if;
  end process;

  scr_we   <= v_we   when v_acc = '1' else t_we;
  scr_addr <= v_addr when v_acc = '1' else t_addr;
  scr_din  <= v_din  when v_acc = '1' else t_din;

  u_scr : entity work.tdpram
    generic map (ABITS => 12)
    port map (clk => clk50,
              we_a => scr_we, addr_a => scr_addr, din_a => scr_din, dout_a => scr_qa,
              addr_b => vdu_addr, dout_b => vdu_q);

  ---------------------------------------------------------------- VDU
  cur_on <= not osi;

  u_vdu : entity work.vdu_composite
    port map (
      clk      => clk50,
      scr_addr => vdu_addr,
      scr_q    => vdu_q,
      top_row  => t_top,
      cur_row  => t_row,
      cur_col  => t_col,
      cur_on   => cur_on,
      ntsc     => ntsc,
      osi      => osi,
      sync_n   => av_sync_n,
      video    => av_video
    );

  ---------------------------------------------------------------- keyboard
  u_kbd : entity work.ps2_kbd
    port map (
      clk      => clk50,
      rst      => rst_por,
      ps2_clk  => ps2_clk,
      ps2_data => ps2_data,
      valid    => kb_valid,
      data     => kb_data,
      ack      => kb_ack,
      reset_key => kb_reset,
      mode_key  => kb_mode,
      sc_valid  => sc_valid,
      sc_code   => sc_code,
      sc_ext    => sc_ext,
      sc_brk    => sc_brk,
      caps_on   => caps_on,
      dbg_edges => open,                  -- diagnostics not used (saves logic)
      dbg_last  => open,
      dbg_good  => open
    );

  ---------------------------------------------------------------- OSI keyboard
  okb_wr <= '1' when bus_stb = '1' and sel = S_KBD and cpu_wr = '1' else '0';

  u_okb : entity work.osi_kbd
    port map (
      clk      => clk50,
      rst      => rst,
      sc_valid => sc_valid,
      sc_code  => sc_code,
      sc_ext   => sc_ext,
      sc_brk   => sc_brk,
      caps_on  => caps_on,
      wr_stb   => okb_wr,
      din      => cpu_do,
      inv      => kbinv,
      dout     => okb_q,
      last_code => okb_code
    );

  ---------------------------------------------------------------- read mux
  -- Captured one 50 MHz clock after the strobe, i.e. ~half a CPU cycle
  -- before the CPU samples it. The ACIA status is captured here too, before
  -- the read side-effect (clearing RDRF) is visible.
  process (clk50)
  begin
    if rising_edge(clk50) then
      if bus_stb = '1' and sel = S_ACIA then
        cpu_di <= acia_q;
      elsif bus_stb_d = '1' then
        case sel_l is
          when S_SRAM => cpu_di <= sr_q;
          when S_BANK => cpu_di <= "11111" & kbinv & osi & fbank;
          when S_KBD  =>
            if cpu_a(0) = '1' then
              cpu_di <= okb_code;            -- $DF01: diagnostics
            else
              cpu_di <= okb_q;
            end if;
          when S_VID  => null;               -- picked up one clock later
          when S_VIA  =>
            case a_l(3 downto 0) is
              when x"0"   => cpu_di <= via_irb;
              when x"2"   => cpu_di <= via_ddrb;
              when others => cpu_di <= x"FF";
            end case;
          when S_ROMA => cpu_di <= roma_q;
          when S_ROMC => cpu_di <= romcd_q;
          when S_ROMD => cpu_di <= romcd_q;
          when S_ROME => cpu_di <= rome_q;
          when S_ACIA => null;               -- already captured
          when others => cpu_di <= x"FF";
        end case;
      end if;
      -- screen RAM (OSI mode): port A was used the clock after the strobe,
      -- so its data is ready one clock later than the rest
      if bus_stb_d2 = '1' and sel_l = S_VID then
        cpu_di <= scr_qa;
      end if;
    end if;
  end process;

end architecture;
