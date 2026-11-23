-- SPI-mode SD card model for the testbench (SDHC, block addressing).
-- Loads the card image file at start-up; writes go back to the in-memory
-- copy only. Supports CMD0, CMD8, CMD55/ACMD41, CMD58, CMD16, CMD17, CMD24.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sd_model is
  generic (IMAGE : string := "card.img"; BLOCKS : natural := 14848);
  port (
    cs   : in  std_logic;
    sclk : in  std_logic;
    mosi : in  std_logic;
    miso : out std_logic;
    nreads, nwrites : out natural
  );
end entity;

architecture sim of sd_model is
  type mem_t is array (natural range <>) of natural range 0 to 255;
  type q_t is array (0 to 1023) of natural range 0 to 255;
begin
  process
    type cfile is file of character;
    file f : cfile;
    variable mem : mem_t(0 to BLOCKS * 512 - 1);
    variable c : character;
    variable q : q_t;                 -- output queue
    variable qh, qt : natural := 0;
    variable cur : natural := 255;
    variable nout : natural := 8;
    variable inb, nin : natural := 0;
    variable cmd : mem_t(0 to 5);
    variable ncmd : natural := 0;
    variable idle, app : boolean := true;
    variable tries : natural := 0;
    variable wst : natural := 0;      -- 0 none, 1 wait token, 2 data
    variable waddr, wcnt : natural := 0;
    variable rd, wr : natural := 0;
    variable arg, a : natural;
    variable b : natural;

    procedure put(v : natural) is begin q(qt) := v; qt := (qt + 1) mod 1024; end procedure;
  begin
    file_open(f, IMAGE, read_mode);
    for i in mem'range loop
      if endfile(f) then exit; end if;
      read(f, c);
      mem(i) := character'pos(c);
    end loop;
    file_close(f);
    report "sd_model: image loaded";
    miso <= '1';
    loop
      wait until rising_edge(sclk) or rising_edge(cs);
      if cs = '1' then
        ncmd := 0; qh := 0; qt := 0; nout := 8; nin := 0; wst := 0;
        miso <= '1';
      elsif rising_edge(sclk) then
        if nout = 8 then
          if qh /= qt then cur := q(qh); qh := (qh + 1) mod 1024; else cur := 255; end if;
          nout := 0;
        end if;
        if (cur / (2 ** (7 - nout))) mod 2 = 1 then miso <= '1'; else miso <= '0'; end if;
        nout := nout + 1;
        if mosi = '1' then inb := (inb * 2 + 1) mod 256; else inb := (inb * 2) mod 256; end if;
        nin := nin + 1;
        if nin = 8 then
          nin := 0; b := inb;
          if wst = 1 then
            if b = 16#FE# then wst := 2; wcnt := 0; end if;
          elsif wst = 2 then
            if wcnt < 512 then mem(waddr + wcnt) := b; end if;
            wcnt := wcnt + 1;
            if wcnt = 514 then
              wst := 0; wr := wr + 1; nwrites <= wr;
              put(16#05#); put(0); put(0); put(255);
            end if;
          elsif ncmd > 0 or (b / 64) = 1 then
            cmd(ncmd) := b; ncmd := ncmd + 1;
            if ncmd = 6 then
              ncmd := 0;
              -- 24-bit block numbers only; anything past the image reads block 0
              arg := (cmd(2) * 256 + cmd(3)) * 256 + cmd(4);
              if (cmd(0) mod 64 = 17 or cmd(0) mod 64 = 24) and
                 (cmd(1) /= 0 or arg >= BLOCKS) then
                report "sd_model: block out of range" severity warning;
                arg := 0;
              end if;
              put(255);
              case cmd(0) mod 64 is
                when 0  => idle := true; put(1);
                when 8  => put(1); put(0); put(0); put(1); put(16#AA#);
                when 55 => app := true; if idle then put(1); else put(0); end if;
                when 41 =>
                  if app then
                    app := false; tries := tries + 1;
                    if tries >= 3 then idle := false; end if;
                    if idle then put(1); else put(0); end if;
                  else put(4); end if;
                when 58 => put(0); put(16#C0#); put(255); put(16#80#); put(0);
                when 16 => put(0);
                when 17 =>
                  a := arg * 512; rd := rd + 1; nreads <= rd;
                  put(0); put(255); put(16#FE#);
                  for i in 0 to 511 loop put(mem(a + i)); end loop;
                  put(16#12#); put(16#34#);
                when 24 =>
                  waddr := arg * 512; put(0); wst := 1;
                when others => put(4);
              end case;
            end if;
          end if;
        end if;
      end if;
    end loop;
  end process;
end architecture;
