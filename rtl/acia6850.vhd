-- ============================================================================
-- acia6850.vhd  -  Minimal MC6850-compatible ACIA for the SBC65 FPGA build
--
-- Register map (A0 = rs):
--   rs=0 read  : status   b0 RDRF  b1 TDRE  b2 /DCD(0)  b3 /CTS(0)
--                         b4 FE    b5 OVRN  b6 PE(0)    b7 IRQ
--   rs=0 write : control  b1..0 = "11" master reset
--                         b6..5 = TX control (only TIE "01" used)
--                         b7    = RX interrupt enable
--                         word select bits are accepted but the UART is
--                         always 8N1 at the BAUD generic.
--   rs=1 read  : RX data  (clears RDRF / OVRN)
--   rs=1 write : TX data  (clears TDRE)
--
-- Everything runs in the 50 MHz domain. "cs_stb" is a one-clock strobe
-- that the top level raises once per CPU bus cycle, at mid-cycle, when
-- the ACIA is addressed. Reads of the data register are therefore
-- counted exactly once per CPU read, just like the real chip.
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity acia6850 is
  generic (
    CLK_HZ : natural := 50_000_000;
    BAUD   : natural := 19200
  );
  port (
    clk    : in  std_logic;
    rst    : in  std_logic;                     -- active high
    cs_stb : in  std_logic;                     -- one-clock bus strobe
    rs     : in  std_logic;                     -- register select (A0)
    rw     : in  std_logic;                     -- '1' = read, '0' = write
    din    : in  std_logic_vector(7 downto 0);
    dout   : out std_logic_vector(7 downto 0);
    irq_n  : out std_logic;
    txd    : out std_logic;
    rxd    : in  std_logic;
    -- second receive source (PS/2 keyboard FIFO): bytes appear exactly
    -- as if they had arrived on rxd
    ext_valid : in  std_logic := '0';
    ext_data  : in  std_logic_vector(7 downto 0) := (others => '0');
    ext_ack   : out std_logic;
    -- copy of every transmitted byte (for the on-screen terminal)
    tap_valid : out std_logic;
    tap_data  : out std_logic_vector(7 downto 0)
  );
end entity;

architecture rtl of acia6850 is
  constant BIT_TICKS : natural := CLK_HZ / BAUD;

  -- control / status
  signal mreset   : std_logic := '1';           -- held in master reset until written
  signal rie      : std_logic := '0';
  signal tie      : std_logic := '0';

  -- transmitter
  signal tdr      : std_logic_vector(7 downto 0) := (others => '0');
  signal tdre     : std_logic := '1';
  signal tx_busy  : std_logic := '0';
  signal tx_shift : std_logic_vector(9 downto 0) := (others => '1');
  signal tx_cnt   : natural range 0 to BIT_TICKS := 0;
  signal tx_bits  : natural range 0 to 10 := 0;

  -- receiver
  signal rx_s1, rx_s2 : std_logic := '1';
  signal rdr      : std_logic_vector(7 downto 0) := (others => '0');
  signal rdrf     : std_logic := '0';
  signal ovrn     : std_logic := '0';
  signal fe       : std_logic := '0';
  signal rx_busy  : std_logic := '0';
  signal rx_cnt   : natural range 0 to BIT_TICKS := 0;
  signal rx_bits  : natural range 0 to 9 := 0;
  signal rx_shift : std_logic_vector(7 downto 0) := (others => '0');

  signal irq      : std_logic;
begin

  irq   <= (rie and (rdrf or ovrn)) or (tie and tdre);
  irq_n <= not irq;

  dout <= (irq & '0' & ovrn & fe & "00" & tdre & rdrf) when rs = '0' else rdr;

  process (clk)
  begin
    if rising_edge(clk) then
      rx_s1 <= rxd;
      rx_s2 <= rx_s1;
      ext_ack <= '0';
      tap_valid <= '0';

      ------------------------------------------------------------ CPU access
      if cs_stb = '1' then
        if rw = '0' then
          if rs = '0' then                       -- control register
            if din(1 downto 0) = "11" then
              mreset <= '1';
            else
              mreset <= '0';
            end if;
            rie <= din(7);
            if din(6 downto 5) = "01" then tie <= '1'; else tie <= '0'; end if;
          else                                   -- TX data
            tdr  <= din;
            tdre <= '0';
          end if;
        else
          if rs = '1' then                       -- reading RX data
            rdrf <= '0';
            ovrn <= '0';
          end if;
        end if;
      end if;

      ------------------------------------------------------------ transmitter
      if tx_busy = '0' then
        txd <= '1';
        if tdre = '0' and mreset = '0' then
          tx_shift <= '1' & tdr & '0';           -- stop, data (LSB first), start
          tdre     <= '1';
          tap_valid <= '1';
          tap_data  <= tdr;
          tx_busy  <= '1';
          tx_cnt   <= 0;
          tx_bits  <= 0;
        end if;
      else
        txd <= tx_shift(0);
        if tx_cnt = BIT_TICKS - 1 then
          tx_cnt   <= 0;
          tx_shift <= '1' & tx_shift(9 downto 1);
          if tx_bits = 9 then
            tx_busy <= '0';
          else
            tx_bits <= tx_bits + 1;
          end if;
        else
          tx_cnt <= tx_cnt + 1;
        end if;
      end if;

      ------------------------------------------------------------ receiver
      if rx_busy = '0' then
        if rx_s2 = '0' then                      -- start bit edge
          rx_busy <= '1';
          rx_cnt  <= 0;
          rx_bits <= 0;
        end if;
      else
        if (rx_bits = 0 and rx_cnt = BIT_TICKS/2 - 1) or
           (rx_bits /= 0 and rx_cnt = BIT_TICKS - 1) then
          rx_cnt <= 0;
          if rx_bits = 0 then
            if rx_s2 = '1' then                  -- false start
              rx_busy <= '0';
            else
              rx_bits <= 1;
            end if;
          elsif rx_bits <= 8 then
            rx_shift <= rx_s2 & rx_shift(7 downto 1);
            rx_bits  <= rx_bits + 1;
          else                                   -- stop bit
            rx_busy <= '0';
            if mreset = '0' then
              if rdrf = '1' then
                ovrn <= '1';
              else
                rdr  <= rx_shift;
                rdrf <= '1';
                fe   <= not rx_s2;
              end if;
            end if;
          end if;
        else
          rx_cnt <= rx_cnt + 1;
        end if;
      end if;

      ------------------------------------------------------------ keyboard
      -- load a keyboard byte when the data register is empty and neither
      -- the CPU nor the serial receiver is touching it this clock
      if ext_valid = '1' and rdrf = '0' and mreset = '0' and cs_stb = '0'
         and not (rx_busy = '1' and rx_bits = 9) then
        rdr     <= ext_data;
        rdrf    <= '1';
        fe      <= '0';
        ext_ack <= '1';
      end if;

      ------------------------------------------------------------ reset
      if rst = '1' or mreset = '1' then
        tdre <= '1';
        rdrf <= '0';
        ovrn <= '0';
        fe   <= '0';
        if rst = '1' then
          mreset <= '1';
          rie <= '0';
          tie <= '0';
        end if;
      end if;
    end if;
  end process;

end architecture;
