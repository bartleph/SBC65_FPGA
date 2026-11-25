#!/bin/sh
# Terminal-mode regression: draws the same picture with two copies of the
# VHDL so the frames can be compared, e.g.
#   git archive <old commit> rtl | tar -x -C /tmp/old
#   ./run_term.sh /tmp/old/rtl old.pgm
#   ./run_term.sh $PWD/../../../rtl new.pgm $PWD/../../../rtl/osi_kbd.vhd
#   cmp old.pgm new.pgm
# (term_rom_pkg.vhd is built from term_test.s with ca65/ld65 and bin2vhd)
set -e
R=$1; OUT=$2; shift 2
rm -rf work_t && mkdir work_t && cd work_t
for f in reg_pc reg_sp regbank_axy fsm_intnmi fsm_execution_unit core r65c02_tc; do
  ghdl -a -fsynopsys --std=93c --work=r65c02_tc $R/cpu65c02/$f.vhd
done
ghdl -a -fsynopsys --std=93c ../term_rom_pkg.vhd $R/font_pkg.vhd $R/mem_blocks.vhd $R/acia6850.vhd \
     $R/vdu_composite.vhd $R/ps2_kbd.vhd "$@" $R/terminal.vhd $R/sbc65_top.vhd ../tb_term.vhd
ghdl -e -fsynopsys --std=93c tb_term
ghdl -r -fsynopsys --std=93c tb_term --ieee-asserts=disable 2>&1 | grep -v "^\s*$" | tail -3
cp frame_term.pgm ../$OUT
