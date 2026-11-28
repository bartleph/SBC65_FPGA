from emu import *; from t2h import doc; import random
random.seed(5)
c=DB(binf='WP.BIN',lbl='WP.lbl'); c.run()
def snap():
    sc=c.screen; return [''.join(ch.data+('#' if ch.reverse else '') for ch in [sc.buffer[y][x] for x in range(80)]) for y in range(1,24)], (sc.cursor.x,sc.cursor.y)
words='the a cat sat on mat and dog jumped over lazy brown quick fox supercalifragilistic'.split()
keys=[lambda: ' '.join(random.choice(words) for _ in range(random.randint(1,12)))+random.choice([' ','\r','']),
      lambda: random.choice([UP,DN,LF,RT,b'\x01',b'\x06',b'\x08',b'\x07',b'\x14',b'\x19',b'\x0e',b'\x11S',b'\x11D',b'\x03',b'\x12']),
      lambda: random.choice([b'\x0bb',b'\x0bk',b'\x0bh',b'\x0bc'])]
bad=0
for it in range(250):
    k=random.choice(keys[0:1]*3+keys[1:2]*4+keys[2:3])()
    c.keys(k)
    if it%10==9:
        a,ca=snap()
        c.keys(b'\x0a'); c.keys(' ')   # help then back: full redraw
        b,cb=snap()
        if a!=b or ca!=cb:
            bad+=1; print('MISMATCH at',it,ca,cb)
            for y in range(23):
                if a[y]!=b[y]: print(y+2,'inc:',a[y].rstrip()); print(y+2,'ful:',b[y].rstrip())
            break
        # check cursor position against model: char under cursor
        d,cur=doc(c)
        sc=c.screen; ch=sc.buffer[sc.cursor.y][sc.cursor.x].data
        want=chr(d[cur]) if cur<len(d) else ' '
        if want=='\r': want=' '
        ln=d[:cur].count(13)+1
        st=sc.display[0]
        if ch!=want or ('Line %d '%ln) not in st: print('CURSOR BAD',it,repr(ch),repr(want),ln,st); bad+=1; break
print('bad',bad, len(doc(c)[0]))
c.show('final')
