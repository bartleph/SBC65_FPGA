from emu import *; from kw import *; from t2h import doc
c=DB(binf='WP.BIN',lbl='WP.lbl')
for i,b in enumerate(kwtab()): c.mem[0x284+i]=b
blines=[(10,'REM A TEST PROGRAM'),(20,'PRINT "HELLO, WORLD":X=1'),(30,'FOR I=1 TO 10:?I;:NEXT I'),(40,'DATA 1,PRINT,3:GOTO 10'),(50,'IF A>=B THEN PRINT LEFT$(A$,2)'),(100,'END')]
putfile(c,'PROG',basimg(blines),22)
al=['; INVADERS','START    LDA #$00     ; CLEAR','         STA $C000','LOOP     JMP LOOP'+' '*150+'X','']
putfile(c,'SRC',asmimg(al),24)
c.run()
c.keys(b'\x0bl'+b'PROG\r'); c.show('basic')
c.keys(b'\x11C'+b'60 GOSUB 1000\r')  # add line at end -> out of order (60 after 100)
c.keys(b'\x0bs\x15PROG2\r'); c.show('order err')
c.keys(b'\x19'+b'\x11R'+DN*4+b'\x11D\r55 ? "NEW";'+b'\x0bs\x15PROG2\r'); c.show('saved2')
img=getfile(c,'PROG2')
want=basimg(blines[:5]+[(55,'? "NEW";')]+blines[5:])
L=len(want); print('basic match',img[:L]==want); 
if img[:L]!=want: print(img[:L].hex()); print(want.hex())
c.keys(b'\x0bl'+b'SRC\r'); c.show('asm')
d=doc(c)[0]; print(d)
c.keys(b'\x0bs\x15SRC2\r')
img=getfile(c,'SRC2'); w=asmimg(al); print('asm match', img[:len(w)]==w)
if img[:len(w)]!=w: print(img[:len(w)].hex()); print(w.hex())
