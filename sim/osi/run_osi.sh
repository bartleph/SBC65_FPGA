#!/bin/sh
# Simulate OSI mode with GHDL. Run from this folder.
# Needs GHDL, cc65 (ca65/ld65) and a C compiler.
set -e
ca65 --cpu 65C02 osi_test.s -o osi_test.o
ld65 -C osi_test.cfg osi_test.o -o osi_test.bin
cc -O2 -o bin2vhd ../../tools/bin2vhd.c
./bin2vhd osi_test.bin osi_rom_pkg.vhd
mkdir -p work && cd work
for f in reg_pc reg_sp regbank_axy fsm_intnmi fsm_execution_unit core r65c02_tc; do
  ghdl -a -fsynopsys --std=93c --work=r65c02_tc ../../../rtl/cpu65c02/$f.vhd
done
ghdl -a -fsynopsys --std=93c ../osi_rom_pkg.vhd ../../../rtl/font_pkg.vhd ../../../rtl/mem_blocks.vhd \
     ../../../rtl/acia6850.vhd ../../../rtl/vdu_composite.vhd ../../../rtl/ps2_kbd.vhd \
     ../../../rtl/osi_kbd.vhd ../../../rtl/terminal.vhd ../../../rtl/sbc65_top.vhd ../tb_osi.vhd
ghdl -e -fsynopsys --std=93c tb_osi
ghdl -r -fsynopsys --std=93c tb_osi --ieee-asserts=disable
