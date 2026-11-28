import pyte
from py65.devices.mpu65c02 import MPU
from py65.memory import ObservableMemory
def bcd(n): return (n//10)*16+n%10
def unbcd(b): return (b>>4)*10+(b&15)
class Disk:
    def __init__(s):
        s.t={}   # (track,sector) -> bytes
        d=bytearray(b'\x00'*512)
        def ent(i,name,a,b):
            e=name.ljust(14).encode()+bytes([bcd(a),bcd(b)]); d[i*16:i*16+16]=e
        ent(0,'BEXEC*',13,13); ent(1,'CALC65',14,19)
        s.t[(12,1)]=bytes(d[:256]); s.t[(12,2)]=bytes(d[256:])
    def dir(s):
        d=s.t[(12,1)]+s.t[(12,2)]; out=[]
        for i in range(32):
            e=d[i*16:i*16+16]
            if e[0] in (0,0x20,0x23): continue
            out.append((i,e[:14].decode().rstrip(),unbcd(e[14]),unbcd(e[15])))
        return out
    def setdir(s,i,name,a,b):
        d=bytearray(s.t[(12,1)]+s.t[(12,2)])
        d[i*16:i*16+16]=name.ljust(14).encode()+bytes([bcd(a),bcd(b)])
        s.t[(12,1)]=bytes(d[:256]); s.t[(12,2)]=bytes(d[256:])
class DB:
    def __init__(s, lines=24, binf='DB.BIN', lbl='DB.lbl', org=0x3B00):
        s.lab={}
        for l in open(lbl):
            p=l.split(); s.lab[p[2].lstrip('.')]=int(p[1],16)
        s.mem=ObservableMemory(); s.inq=[]
        s.screen=pyte.Screen(80,lines); s.stream=pyte.ByteStream(s.screen)
        s.mem.subscribe_to_read([0xC080],lambda a: 0x02|(1 if s.inq else 0))
        s.mem.subscribe_to_read([0xC081],lambda a: s.inq.pop(0) if s.inq else 0)
        s.mem.subscribe_to_write([0xC081],lambda a,v: s.stream.feed(bytes([v])))
        b=open(binf,'rb').read()
        for i,x in enumerate(b): s.mem[org+i]=x
        s.mem[0x400:0x406]=[0x20,org&255,org>>8,0x4C,0x03,0x04]
        s.cpu=MPU(memory=s.mem); s.cpu.pc=0x400; s.cpu.sp=0xF0
        s.disk=Disk(); s.errvec=None; s.exited=False; s.dos=[]
        s.raw=s.lab['RAWKEY']
        s.reads=0; s.writes=0
    def rts(s):
        c=s.cpu; lo=s.mem[0x100+((c.sp+1)&255)]; hi=s.mem[0x100+((c.sp+2)&255)]; c.sp=(c.sp+2)&255; c.pc=((hi<<8)|lo)+1
    def cmdline(s):
        t=''
        for i in range(60):
            ch=s.mem[0x2E1E+i]
            if ch==13: break
            t+=chr(ch)
        return t
    def out(s,txt): s.stream.feed(txt.replace('\n','\r\n').encode())
    def err(s,n):
        s.out(' ERR #%X'%n); s.cpu.pc=s.errvec
    def hook(s):
        c=s.cpu; pc=c.pc
        if pc==0xE7FA: s.errvec=c.a|(c.y<<8); s.rts(); return True
        if pc==0xE801:
            t=s.cmdline(); s.dos.append(t); w=t.split()
            if w[0]=='CA':
                a,ts=w[1].split('='); a=int(a,16); tr,sec=ts.split(','); tr=unbcd(int(tr,16)); sec=int(sec)
                if (tr,sec) not in s.disk.t: return s.err(0xA) or True
                d=s.disk.t[(tr,sec)]
                for i,x in enumerate(d): s.mem[a+i]=x
                s.reads+=1; s.rts(); return True
            if w[0]=='SA':
                ts,ap=w[1].split('='); tr,sec=ts.split(','); tr=unbcd(int(tr,16)); sec=int(sec)
                a,p=ap.split('/'); a=int(a,16); p=int(p)
                if tr==0: return s.err(3) or True
                s.disk.t[(tr,sec)]=bytes(s.mem[a:a+p*256]); s.writes+=1; s.rts(); return True
            if w[0]=='MS':
                a=int(w[1],16); e=int(w[2],16); name=w[3]
                pages=(e>>8)-(a>>8)+1; ntr=(pages+8)//8
                ents=s.disk.dir(); used=set()
                for i,n,x,y in ents:
                    if n!=name: used|=set(range(x,y+1))
                used|=set(range(0,13))
                slot=[i for i,n,x,y in ents if n==name]
                start=None
                for st in range(13,40-ntr+1):
                    if not (set(range(st,st+ntr))&used): start=st; break
                if start is None: return s.err(0xE) or True
                if slot: i=slot[0]
                else:
                    taken={i for i,*_ in ents}; i=min(set(range(32))-taken)
                s.disk.setdir(i,name,start,start+ntr-1)
                # write MC header sector + data, like MS
                s.disk.t[(start,1)]=b'MC'+bytes([a&255,a>>8,e&255,e>>8,0,0,pages+1])+b'\0'*247
                s.disk.t[(start,2)]=bytes(s.mem[a:a+7*256])
                for k in range(1,ntr): s.disk.t[(start+k,1)]=bytes(s.mem[(a+((8*k-1)*256))&0xFFFF:][:2048] if True else b'')
                s.rts(); return True
            if w[0]=='DI':
                s.out('\nDIRECTORY\n')
                for i,n,x,y in sorted(s.disk.dir(),key=lambda e:e[2]): s.out('%-14s %02d-%02d\n'%(n,x,y))
                s.rts(); return True
            return s.err(7) or True
        if pc==0x403: s.exited=True; return True
        return False
    def run(s, maxsteps=60_000_000):
        c=s.cpu; n=0; idle=0
        while n<maxsteps:
            if s.hook():
                if s.exited: return
                continue
            if s.raw<=c.pc<s.raw+16 and not s.inq and s.mem[s.lab['PBK']]==0:
                idle+=1
                if idle>3: return
            c.step(); n+=1
        raise Exception('run limit, pc=%04X'%c.pc)
    def keys(s,t):
        if isinstance(t,str): t=t.encode()
        s.inq+=list(t); s.run()
    def cmd(s,t): s.keys(t+'\r')
    def text(s): return '\n'.join(l.rstrip() for l in s.screen.display)
    def show(s,title=''):
        print('=== '+title)
        for i,l in enumerate(s.screen.display):
            if l.strip(): print('%2d|%s'%(i+1,l.rstrip()))
UP=b'\x1b[A'; DN=b'\x1b[B'; RT=b'\x1b[C'; LF=b'\x1b[D'; ESC=b'\x1b'

from PIL import Image, ImageDraw, ImageFont
def render(c, fn):
    sc=c.screen; W,H=sc.columns, sc.lines
    font=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf',14)
    cw,ch=9,18
    img=Image.new('RGB',(W*cw+16,H*ch+16),(10,20,10)); d=ImageDraw.Draw(img)
    fg=(120,255,120); bg=(10,20,10)
    for y in range(H):
        row=sc.buffer[y]
        for x in range(W):
            chr_=row[x]; rev=chr_.reverse
            if rev: d.rectangle([8+x*cw,8+y*ch,8+(x+1)*cw-1,8+(y+1)*ch-1],fill=fg)
            if chr_.data!=' ': d.text((8+x*cw,8+y*ch),chr_.data,font=font,fill=bg if rev else fg)
    cx,cy=sc.cursor.x,sc.cursor.y
    d.rectangle([8+cx*cw,8+cy*ch+ch-3,8+(cx+1)*cw-1,8+(cy+1)*ch-1],fill=fg)
    img.save(fn)
