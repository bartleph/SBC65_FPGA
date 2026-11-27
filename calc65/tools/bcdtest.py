import random, re, sys
from decimal import Decimal, getcontext
from py65.devices.mpu65c02 import MPU
from py65.memory import ObservableMemory
getcontext().prec=40
lab={}
for l in open('TBCD.lbl'):
    p=l.split(); lab[p[2].lstrip('.')]=int(p[1],16)
bin_=open('TBCD.BIN','rb').read()
mem=ObservableMemory()
for i,b in enumerate(bin_): mem[0x4000+i]=b
FA=lab['FA']; FB=lab['FB']
def enc(d):
    d=Decimal(d)
    if d==0: return [0]*8
    s=0x80 if d<0 else 0; d=abs(d)
    t=d.as_tuple(); digs=list(t.digits); e=len(digs)+t.exponent
    while digs and digs[0]==0: digs.pop(0); e-=1
    digs=(digs+[0]*12)[:12]
    m=[digs[i]*16+digs[i+1] for i in range(0,12,2)]
    return [s,e&255]+m
def dec(b):
    if b[2]==0: return Decimal(0)
    e=b[1]-256 if b[1]>127 else b[1]
    digs=''.join('%02X'%x for x in b[2:8])
    v=Decimal('0.'+digs).scaleb(e)
    return -v if b[0]&0x80 else v
def call(name):
    mem[lab['TVEC']]=lab[name]&255; mem[lab['TVEC']+1]=lab[name]>>8
    mem[0x300]=0x20; mem[0x301]=lab['TWRAP']&255; mem[0x302]=lab['TWRAP']>>8; mem[0x303]=0x4C;mem[0x304]=3;mem[0x305]=3
    c=MPU(memory=mem); c.pc=0x300; c.sp=0xFF
    n=0
    while c.pc!=0x303:
        c.step(); n+=1
        if n>2000000: raise Exception('hang '+name)
    return mem[lab['TRES']], c.processorCycles
def setv(addr,v):
    for i,x in enumerate(enc(v)): mem[addr+i]=x
def getv(addr): return dec([mem[addr+i] for i in range(8)])
def rnd():
    m=random.randint(1,10**12-1); e=random.randint(-20,20)
    return Decimal(m).scaleb(e-12)*random.choice([1,-1])
ops={'FADD':lambda a,b:a+b,'FSUB':lambda a,b:a-b,'FMUL':lambda a,b:a*b,'FDIV':lambda a,b:a/b}
random.seed(1); bad=0; maxc={}
for op,f in ops.items():
    for i in range(400):
        a,b=rnd(),rnd()
        if i%10==0: b=a      # equal
        if i%17==0: a=Decimal(0)
        setv(FA,a); setv(FB,b); err,cyc=call(op); r=getv(FA)
        maxc[op]=max(maxc.get(op,0),cyc)
        exp=f(a,b)
        if err: print('ERR',op,a,b); bad+=1; continue
        tol=abs(exp)*Decimal('1e-11') if exp else Decimal(0)
        if abs(r-exp)>tol: print('BAD',op,a,b,'got',r,'want',exp); bad+=1
print('arith bad',bad,'cycles',maxc)
# compare
for i in range(300):
    a,b=rnd(),rnd()
    if i%5==0: b=a
    if i%7==0: a=Decimal(0)
    setv(FA,a);setv(FB,b);call('FCMP')
# FCMP returns A; read via wrapper? use FSUB sign instead
# int
for v in ['3.7','-3.7','0.5','123456.789','1E11','12345678901.5','0']:
    setv(FA,Decimal(v)); call('FINT'); print('INT',v,getv(FA))
# div by zero
setv(FA,Decimal(1)); setv(FB,Decimal(0)); print('1/0 err=',call('FDIV')[0])
setv(FA,Decimal('1E90')); setv(FB,Decimal('1E20')); print('1E90*1E20 err=',call('FMUL')[0])
setv(FA,Decimal('1E-90')); setv(FB,Decimal('1E-20')); call('FMUL'); print('tiny ->',getv(FA))
print('0.1+0.2 ->', end=' '); setv(FA,Decimal('0.1')); setv(FB,Decimal('0.2')); call('FADD'); print(getv(FA))
# --- FCMP
bad=0
for i in range(400):
    a,b=rnd(),rnd()
    if i%5==0: b=a
    if i%7==0: a=Decimal(0)
    if i%11==0: b=Decimal(0)
    if i%13==0: b=-a
    setv(FA,a);setv(FB,b);call('FCMP'); r=mem[lab['TAV']]; r=-1 if r==255 else r
    w=(a>b)-(a<b)
    if r!=w: bad+=1; print('CMP',a,b,r,w)
print('cmp bad',bad)
# --- FPARSE
TXT=0x0400; mem[lab['TP']]=0; mem[lab['TP']+1]=4
def parse(t):
    for i,ch in enumerate(t.encode()+b'\0'): mem[TXT+i]=ch
    err,_=call('TPAR'); return err, mem[lab['TAV']], getv(FA)
for t in ['123','1.5','.25','0.05','100','1E6','2.5E-3','007.50','12345678901234567','1E','3E+2','.','abc','0','0.000','5*2']:
    print('PARSE %-18r'%t, parse(t))
def gen(v,w,f='TGEN'):
    setv(FA,Decimal(v)); mem[lab['TW']]=w; err,_=call(f)
    n=mem[lab['OLEN']]; return 'ERR' if err else ('<TOO WIDE>' if n==255 else bytes(mem[lab['OBUF']+i] for i in range(n)).decode())
for v in ['0','1','-1','0.3','123.456','-123.456','1234567890','12345678901','0.000123','-0.000123','1E-20','1E20','3.14159265359','99999.99999','-0.5','2E15','0.1','1E-6','123456789.123']:
    print('%-16s'%v, [gen(v,w) for w in (9,5,14)], 'FIX2', gen(v,2,'TFIX'), 'FIX0', gen(v,0,'TFIX'))
