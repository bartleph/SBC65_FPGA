import pyte
from py65.devices.mpu65c02 import MPU
from py65.memory import ObservableMemory
class Calc:
    @property
    def files(s): return s.fd[s.mem[0x265C]]
    def __init__(s, lines=24, binf='CALC.BIN', lbl='CALC.lbl'):
        s.lab={}
        for l in open(lbl):
            p=l.split(); s.lab[p[2].lstrip('.')]=int(p[1],16)
        s.mem=ObservableMemory()
        s.inq=[]; s.out=bytearray()
        s.screen=pyte.Screen(80,lines); s.stream=pyte.ByteStream(s.screen)
        s.mem.subscribe_to_read([0xC080],lambda a: 0x02|(1 if s.inq else 0))
        s.mem.subscribe_to_read([0xC081],lambda a: s.inq.pop(0) if s.inq else 0)
        s.mem.subscribe_to_write([0xC081],lambda a,v: s.stream.feed(bytes([v])))
        b=open(binf,'rb').read()
        for i,x in enumerate(b): s.mem[0x4000+i]=x
        # caller: JSR $4000 then loop
        s.mem[0x300:0x306]=[0x20,0x00,0x40,0x4C,0x03,0x03]
        s.cpu=MPU(memory=s.mem); s.cpu.pc=0x300; s.cpu.sp=0xF0
        s.fd={d:{} for d in (1,2,3,4)}; s.mem[0x265C]=1; s.errvec=None; s.exited=False
        s.raw=s.lab['RAWKEY']
    def rts(s):
        c=s.cpu; lo=s.mem[0x100+((c.sp+1)&255)]; hi=s.mem[0x100+((c.sp+2)&255)]; c.sp=(c.sp+2)&255; c.pc=((hi<<8)|lo)+1
    def cmdline(s):
        t=''
        for i in range(60):
            ch=s.mem[0x2E1E+i]
            if ch==13: break
            t+=chr(ch)
        return t
    def doserr(s): s.cpu.pc=s.errvec
    def hook(s):
        c=s.cpu; pc=c.pc
        if pc==0xE7FA: s.errvec=c.a|(c.y<<8); s.rts(); return True
        if pc==0xE801:
            t=s.cmdline().split(); s.log=('DOS',t)
            if t[0]=='MS':
                a=int(t[1],16); e=int(t[2],16); s.files[t[3]]=(a,bytes(s.mem[a:e+1])); s.rts()
            elif t[0]=='ML':
                if t[1] not in s.files: s.doserr(); return True
                a,d=s.files[t[1]]
                # ML loads whole pages
                d=d+bytes((-len(d))%256)
                for i,x in enumerate(d): s.mem[a+i]=x
                s.rts()
            elif t[0]=='SE':
                s.mem[0x265C]=ord(t[1][0])-64; s.rts()
            elif t[0]=='DI':
                s.stream.feed(('\r\nDIRECTORY '+chr(64+s.mem[0x265C])+'\r\n'+''.join(n+'\r\n' for n in s.files)).encode()); s.rts()
            else: s.doserr()
            return True
        if pc==0xF0D2:
            t=s.cmdline().split()
            if t[1] not in s.files: s.doserr(); return True
            s.curfile=t[1]; s.mem[0x10]=0; s.mem[0x11]=0x34; s.mem[0x340E]=0x20; s.rts(); return True
        if pc==0xE435: s.rts(); return True
        if pc==0xFEFE:
            a=s.files[s.curfile][0]; s.mem[0x3300:0x3304]=[ord('M'),ord('C'),a&255,a>>8]; s.rts(); return True
        if pc==0x303: s.exited=True; return True
        return False
    def run(s, maxsteps=30_000_000):
        c=s.cpu; n=0; idle=0
        while n<maxsteps:
            if s.hook():
                if s.exited: return
                continue
            if s.raw<=c.pc<s.raw+16 and not s.inq:
                idle+=1
                if idle>3: return
            c.step(); n+=1
        raise Exception('run limit, pc=%04X'%c.pc)
    def keys(s, t):
        if isinstance(t,str): t=t.encode()
        s.inq+=list(t); s.run()
    def text(s):
        return '\n'.join(s.screen.display)
    def show(s, title=''):
        print('=== '+title); 
        for i,l in enumerate(s.screen.display): print('%2d|%s'%(i+1,l.rstrip()))
UP=b'\x1b[A'; DN=b'\x1b[B'; RT=b'\x1b[C'; LF=b'\x1b[D'; ESC=b'\x1b'
from PIL import Image, ImageDraw, ImageFont
def render(c, fn, scale=1):
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
