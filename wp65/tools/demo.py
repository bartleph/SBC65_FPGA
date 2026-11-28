from emu import *; from kw import *
c=DB(binf='WP.BIN',lbl='WP.lbl')
for i,b in enumerate(kwtab()): c.mem[0x284+i]=b
c.run()
txt=""".HE The SBC65 Newsletter
.FO - page # -
.JU
.CE
WP65 - a word processor for the SBC65

WP65 is a full-screen word processor for the 65C02 SBC, in the spirit of OSI's WP-2. You type, and the words wrap at the edge of the screen; the dot commands on lines of their own set the margins, the page length and the headers when the text is printed.

It edits three kinds of file: its own documents, assembler source for the OSI assembler, and BASIC programs, which it turns into text when it loads them and back into tokens when it saves them.

Blocks can be copied, moved and deleted, and find and replace works on the whole text or from the cursor.
"""
c.keys(txt.replace('\n','\r'))
c.keys(b'\x0bs\x15NEWS\r'+b'\x11R'+DN*6+b'\x0bb'+DN*5+b'\x0bk'+DN*2+RT*6)
render(c,'wp65_edit.png'); c.show()
c.keys(b'\x0bpv'); render(c,'wp65_view.png'); c.show()
c.keys(b'\x1b')
blines=[(10,'REM GUESS THE NUMBER'),(20,'N=INT(RND(1)*100)+1:T=0'),(30,'PRINT "GUESS (1-100)";:INPUT G'),(40,'T=T+1:IF G=N THEN 80'),(50,'IF G<N THEN PRINT "HIGHER"'),(60,'IF G>N THEN PRINT "LOWER"'),(70,'GOTO 30'),(80,'PRINT "YES! IN";T;"GOES"'),(90,'END')]
putfile(c,'GUESS',basimg(blines),22)
c.keys(b'\x0bly\x15GUESS\r'); render(c,'wp65_basic.png'); c.show()
