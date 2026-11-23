#!/bin/sh
# Simulate the whole SBC with GHDL (about 3 minutes). Run from this folder.
set -e
mkdir -p work && cd work
for f in reg_pc reg_sp regbank_axy fsm_intnmi fsm_execution_unit core r65c02_tc; do
  ghdl -a -fsynopsys --std=93c --work=r65c02_tc ../../rtl/cpu65c02/$f.vhd
done
ghdl -a -fsynopsys --std=93c ../../rtl/rom_image_pkg.vhd ../../rtl/font_pkg.vhd ../../rtl/mem_blocks.vhd ../../rtl/acia6850.vhd \
     ../../rtl/vdu_composite.vhd ../../rtl/ps2_kbd.vhd ../../rtl/terminal.vhd ../../rtl/sbc65_top.vhd ../tb_sbc65.vhd
ghdl -e -fsynopsys --std=93c tb_sbc65
ghdl -r -fsynopsys --std=93c tb_sbc65 --ieee-asserts=disable
