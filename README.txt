SBC65 on Cyclone 10 LP (10CL006YE144C8G core board)
====================================================

What it is
----------
Your 65C02 SBC rebuilt in the FPGA with external SRAM:

  $0000-$BFFF  RAM 48K, AS6C1008 SRAM (A16 held low, 64K spare)
  $A000-$BFFF  Forth ROM 8K (on-chip) in place of that RAM while Forth
               runs: FT switches it in, BYE / F10 / power-up switch it out.
               The RAM underneath is kept.
  $C000-$C0FF  I/O page:
    $C000-$C01F  reads $FF (old disk PIA/ACIA, not fitted)
    $C080-$C081  6850 ACIA console (mirrored to $C08F)
    $C090-$C09F  minimal VIA: ORB/IRB ($C090), DDRB ($C092) only.
                 Port B: PB0 SD CLK, PB1 SD DI, PB2 SD CS (outputs),
                 PB6 SD CD, PB7 SD DO (inputs). Other registers read $FF.
    $C0A0        bank latch, bit 0: 1 = Forth ROM at $A000 (read back too)
  $C100-$CFFF  ROM (on-chip) - SD card driver + MO command (rom/SD.S)
  $D000-$DFFF  ROM 4K  (on-chip) - DOSX
  $E000-$FFFF  ROM 8K  (on-chip)
  The cold start finds RAM up to $BFFF, so BASIC shows 34177 BYTES FREE
  and the assembler has about 34K for source (17.8K before).
  NOTE: this differs from the real SBC (ACIA $8000, VIA $9000, 32K RAM).
  Your own programs that use the ACIA or VIA directly need the new
  addresses here. The ROM source builds either way (see Changing things).
  CPU          65C02 at 1 MHz (50 MHz / CPU_DIV)
  Console      8N1, 19200 baud by default, 3.3 V TTL

Built-in terminal
  The composite screen and PS/2 keyboard work as a terminal on the console:
  everything the CPU sends through the ACIA appears on the screen (and on
  the serial port), and key presses arrive through the ACIA receiver
  alongside the serial port. No software changes are needed.
  Screen: 80 x 32 (5x7 characters in 6x8 cells), PAL 50 Hz (or NTSC, F9), blinking block
  cursor, hardware scrolling. Text lines that are exactly 80 wide do not
  leave a blank line (the wrap waits for the next character).
  Understands CR, LF, BS, TAB, FF (clear), and the VT100 sequences
  ESC[nA/B/C/D, ESC[r;cH, ESC[J (0/1/2), ESC[K (0/1/2), ESC[7m / ESC[0m,
  ESC c. Others are ignored.
  Keyboard: UK layout, Caps Lock starts ON (LED follows), arrow keys send
  ESC [ A/B/C/D, Shift+3 sends '#'. F10 resets the computer.
  F9 switches the screen between PAL (50 Hz, 80 x 32) and NTSC (60 Hz,
  80 x 28 - an NTSC picture has no room for 32 rows). It starts as PAL at
  power-up and keeps its setting over an F10 reset.

On-chip memory: 24 ROM + 4 screen + 2 character set = 30 of 30 M9K (full).

SD card "disks"
  The DOS's floppy routines now go to rom/SD.S, which drives the SD card
  through VIA port B. The card holds up to 256 disk images (slots 0-255).
  After power-up drives A-D are slots 0-3; MO mounts any slot on any drive:
      MO          list the mounts      A=000 B=001 C=002 D=003
      MO B 12     drive B = slot 12
  (the mount table is at $35F0-$35F5 in unused DOS RAM; it was at
  $35E0-$35E5, where TY's variables could overwrite it).
  The card has no PC file system - it is written as a raw image. Build
  tools/hfe2sd.c in Dev-C++, then:
    New card (replaces everything on it):
         hfe2sd card.img PBdos.HFE GAMES.HFE      (slots 0, 1, ...)
         hfe2sd card.img 0=PBdos.HFE 12=WORK.HFE  (chosen slots, - = empty)
       and write card.img to the card with Win32 Disk Imager.
    Add or replace a disk, keeping the rest of the card (Command Prompt run
    as administrator; N = the card's disk number in Disk Management):
         hfe2sd -a \\.\PhysicalDriveN 12=WORK.HFE
         hfe2sd -a \\.\PhysicalDriveN 12=-        (empty slot 12)
         hfe2sd -l \\.\PhysicalDriveN             (list the slots)
       -a and -l also work on an image file. They only touch a card that
       hfe2sd labelled ("SBC65 SD CARD" in block 0), so a wrong disk number
       is refused. Cards made before this version have no label: make them
       once more without -a. If Windows offers to format or initialise the
       card, click Cancel (initialising would overwrite the label).
  All DOS commands work as before (DI, BA, AS, LO, PU, SA, CA, IN, EX,
  SE A-D, DOSX's CO/VE/RN ...). IN formats a track on the card.

DA - 65C02 disassembler (rom/DIS.S, in the $C100 ROM after the SD driver)
      DA E000        20 instructions, then any key = 20 more, ESC = stop
      DA E000 E0FF   E000 through E0FF (ESC stops, space pauses, as MD)
  Lines look like   E000  4C A5 F4  JMP  $F4A5
                    C200  0F 12 FD  BBR0 $12,$C200
  All 212 W65C02S opcodes (RMB/SMB/BBR/BBS, WAI, STP included); unused
  opcodes show as ??? and count as one byte. Branch targets are worked
  out. It reads what it lists, so avoid the I/O page. The tables in DIS.S
  are made by tools/gentab.py from tools/optab.py.
  Errors: #1 read failed, #2 write failed, #6 no card, #A no such sector.
  The driver keeps nothing in zero page while sector data is arriving, so
  the cold start's load of track 06 sector 3 into page 0 is exact.
  The same ROM works on the real SBC with the SD module on its VIA
  (PB0 CLK, PB1 DI, PB2 CS, PB7 DO) - rom/EEPROM_8000-FFFF_SD.bin.

Pins (all set in sbc65.qsf)
---------------------------
  91 clk50     (no reset pin - press F10 on the keyboard)
  33 uart_txd  34 uart_rxd
  31 av_sync_n 32 av_video
  84 ps2_data  85 ps2_clk
  SRAM A16..A1  39 43 46 50 52 54 58 60 65 67 69 71 73 75 77 83,  A0 28
  SRAM D7..D0   42 44 49 51 53 55 59 66
  SRAM /CE 68, CE2 70, /OE 72, /WE 74
  SD module CS 132, DI 135, DO 137, CLK 141, CD 143 (module 5V/GND to 5V)

Files
-----
  sbc65.qpf / .qsf / .sdc   Quartus Prime Lite project
  rtl/sbc65_top.vhd         top level: clocks, reset, decode, SRAM, ROM, bus
  rtl/mem_blocks.vhd        ROMs, screen RAM, font ROM (Quartus templates)
  rtl/terminal.vhd          on-screen terminal (VT100 subset, scrolling)
  rtl/acia6850.vhd          6850-compatible ACIA (+ keyboard input path)
  rtl/vdu_composite.vhd     80x32 text display, composite sync + video
  rtl/ps2_kbd.vhd           PS/2 scan codes -> ASCII, 16-byte buffer
  rtl/font_pkg.vhd          6x8 character set (Adafruit-GFX 5x7 font, BSD)
  rtl/rom_image_pkg.vhd     ROM contents (generated from rom/ROM_FPGA48.bin;
                            run bin2vhd on testrom/testrom.bin for the test ROM)
  rom/                      ROM.S + DOSX.S + SD.S (your ROM with the SD driver),
                            rom.cfg, and the built 32K images:
                              ROM_FPGA48.bin              this FPGA (48K layout)
                              EEPROM_8000-FFFF_SD.bin     the real SBC
  rtl/cpu65c02/             cpu65c02_true_cycle by Jens Gutschmidt (OpenCores,
                            GPL v3). Changes: removed the simulation-only
                            "FOR ALL ... USE ENTITY" lines, and fixed a bug in
                            reg_pc.vhd - JMP abs at $xxFE fetched its high
                            address byte from the wrong page (no carry).
  testrom/                  test ROM source (ca65) and the built testrom.bin
  tools/bin2vhd.c           converts a ROM .bin to rom_image_pkg.vhd
  tools/hfe2sd.c            builds an SD card image from Gotek HFE files
  tools/make_font6_pkg.py   rebuilds font_pkg.vhd from Adafruit glcdfont.c
  tools/make_font_pkg.py    the old 8x8 font (for the 64-column version)
  sim/                      GHDL testbench and run script

Steps
-----
1. Open sbc65.qpf in Quartus Prime Lite and compile.
2. Program output_files/sbc65.sof with the USB-Blaster (lost at power off).
   To make it permanent: File > Convert Programming Files > .jic,
   configuration device EPCS16 (the board's Winbond 25Q16), flash loader
   10CL006Y, add sbc65.sof, then program the .jic.
3. The build boots your OS-65D ROM straight to the A* prompt; with an
   SD card made by hfe2sd, DI, BA etc. work. With the test ROM instead
   (bin2vhd testrom/testrom.bin rtl/rom_image_pkg.vhd) the screen (and the serial terminal) show:

     SBC65 FPGA - Cyclone 10 LP
     65C02 opcodes: OK
     SRAM $0200-$7FFF: OK
     Terminal:  inverse  normal                 (middle word inverted)
     Type something:
                     ... and "<- row 20 col 45" further down the screen.

   Anything typed is echoed exactly as typed.

Changing things
---------------
  Baud rate   BAUD generic in sbc65_top.vhd (the 6850's divide-select bits
              are accepted but the rate is fixed by this generic).
  CPU speed   CPU_DIV generic (even, at least 10 -> 5 MHz max with the
              SRAM). If you change it, change "-divide_by 50" in sbc65.sdc.
  Your ROM    Build bin2vhd.c in Dev-C++, then from the project folder:
                bin2vhd ROM.bin rtl\rom_image_pkg.vhd
              A 32K file is taken as $8000-$FFFF (your EEPROM image); the
              $A000-$BFFF, $D000-$DFFF and $E000-$FFFF parts go into the
              FPGA. An 8K file is placed at $E000. Recompile in Quartus.
              To rebuild the ROM for this FPGA (48K RAM, I/O at $C080):
                                  ca65 ROM.S -o rom.o
                                  ld65 -C rom.cfg -o ROM_FPGA48.bin rom.o
                                  bin2vhd ROM_FPGA48.bin ..\rtl\rom_image_pkg.vhd
              For the real SBC (32K RAM, ACIA $8000, VIA $9000):
                                  ca65 -D FPGA48=0 ROM.S -o rom.o
                                  ld65 -C rom.cfg -o EEPROM_8000-FFFF_SD.bin rom.o
              (The test ROM in testrom/ still uses the old $8000 ACIA, so it
              does not run on this layout.)
  Sync wiring If the picture rolls or is inverted, the board's resistor
              network may expect the opposite polarity on pin 31 or 32.
