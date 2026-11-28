#!/usr/bin/env python3
"""Convert INVADERS.S (ca65) to OSI Assembler format (as DIRSORT.ASM):
line numbers in 10s, labels <= 6 chars, no comments, no quoted text,
no < > operators, .BYTE for data and reserved space, * = origin, .END."""
import re, sys

SRC, OUT = sys.argv[1], sys.argv[2]
ORG = 0x4000

GLOBAL = {
 'START':'START','TITLE':'TITLE','NEWWAVE':'NEWWAV','MAIN':'MAIN','GAMEOVER':'GAMOVR',
 'EXIT':'EXIT','FRAME':'FRAME','DRAIN':'DRAIN','KEYS':'KEYS','PLAYER':'PLAYER',
 'DRAWBASE':'DRWBAS','ERASEBASE':'ERSBAS','SHOT':'SHOT','ENDSHOT':'ENDSHT',
 'HITINV':'HITINV','ROWPTS':'ROWPTS','ISINV':'ISINV','INVCH':'INVCH','ISSHIELD':'ISSHLD',
 'DAMAGE':'DAMAGE','EXPLODE':'EXPLOD','EXPLODEEND':'EXPEND','EXPX':'EXPX',
 'FORMSTEP':'FRMSTP','SETSTEP':'SETSTP','COLRANGE':'COLRNG','CLEARGAPS':'CLRGAP',
 'DRAWFORM':'DRWFRM','ROWTYPE':'ROWTYP','INVL':'TINVL','INVR':'TINVR',
 'DROPBOMB':'DRPBMB','BOMBS':'BOMBS','BOMB1':'BOMB1','BASEHIT':'BASEHT',
 'SAUCER':'SAUCER','UFOCLR':'UFOCLR','UFOHIT':'UFOHIT','UFOPTS':'UFOPTS','UFOHI':'UFOHI',
 'ADDSCORE':'ADDSCR','DRAWHUD':'DRWHUD','DRAWSCORE':'DRWSCR','DRAWLIVES':'DRWLIV',
 'PRBCD':'PRBCD','DRAWSHIELDS':'DRWSHD','SHX':'SHX','DRAWGROUND':'DRWGND','CLS':'CLS',
 'PRINTI':'PRINTI','SETPTR':'SETPTR','RAND':'RAND',
 # variables
 'savesp':'SAVESP','zpsave':'ZPSAVE','hiscore':'HISCOR','score':'SCORE','lives':'LIVES',
 'bonus':'BONUS','wave':'WAVE','frame':'FRAMEC','kleft':'KLEFT','kright':'KRIGHT',
 'kfire':'KFIRE','kesc':'KESC','alive':'ALIVE','nalive':'NALIVE','fx':'FX','fy':'FY',
 'fdir':'FDIR','anim':'ANIM','stepcnt':'STPCNT','stepint':'STPINT','invaded':'INVADD',
 'lc':'LC','rc':'RC','rb':'RB','invl':'INVL','invr':'INVR','px':'PX','pdead':'PDEAD',
 'sact':'SACT','sx':'SX','sy':'SY','bact':'BACT','bx':'BX','by':'BY','bombcnt':'BOMCNT',
 'eact':'EACT','ex':'EX','ey':'EY','etimer':'ETIMER','uact':'UACT','ux':'UX','udir':'UDIR',
 'utimer':'UTIMER',
 # zero page and hardware (kept as equates)
 'ptr':'PTR','tmp':'TMP','tmp2':'TMP2','tmp3':'TMP3','rnd':'RND','sptr':'SPTR',
 'SCR':'SCR','KBD':'KBD','BANK':'BANK','ACIAS':'ACIAS','ACIAD':'ACIAD','OUTCH':'OUTCH',
 'TYPAHD':'TYPAHD',
}
KEEP_EQU = ['PTR','TMP','TMP2','TMP3','RND','SPTR','SCR','KBD','BANK','ACIAS','ACIAD','OUTCH','TYPAHD']

def strip_comment(l):
    out=''; q=False
    for ch in l:
        if ch=='"': q=not q
        if ch==';' and not q: break
        out+=ch
    return out.rstrip()

def num(tok):
    tok=tok.strip()
    if tok.startswith('$'): return int(tok[1:],16)
    if tok.startswith('%'): return int(tok[1:],2)
    return int(tok)

lines=[strip_comment(l) for l in open(SRC)]
consts={}
for l in lines:
    m=re.match(r'^([A-Za-z_]\w*)\s*=\s*(.+)$',l.strip())
    if m: consts[m.group(1)]=m.group(2).strip()
def cval(name):
    v=consts[name]
    v=re.sub(r'\$([0-9A-Fa-f]+)',lambda m:str(int(m.group(1),16)),v)
    v=re.sub(r'%([01]+)',lambda m:str(int(m.group(1),2)),v)
    v=re.sub(r'[A-Za-z_]\w*',lambda m:str(cval(m.group(0))),v)
    return eval(v)
numconst={k:cval(k) for k in consts if GLOBAL.get(k) not in KEEP_EQU}

# local labels -> unique names
local={}; parent=None; cnt=0
for l in lines:
    m=re.match(r'^(@?[A-Za-z_]\w*):',l)
    if not m: continue
    lab=m.group(1)
    if lab.startswith('@'):
        cnt+=1
        local[(parent,lab)]=GLOBAL[parent][:3]+'%03d'%cnt
    else:
        parent=lab

def operand(op,par):
    op=op.strip()
    if not op: return ''
    imm=op.startswith('#'); body=op[1:] if imm else op
    lohi=''
    if body[:1] in '<>': lohi=body[0]; body=body[1:]
    def sym(m):
        s=m.group(0)
        if s.lower() in ('a','x','y') : return s.upper()
        if s.startswith('@'): return local[(par,s)]
        if s in numconst: return str(numconst[s])
        return GLOBAL[s]
    hexish='$' in body
    body=re.sub(r'(?<![$\w])@?[A-Za-z_]\w*',sym,body)
    # a pure number expression (maybe with ,X / ,Y): evaluate it
    m=re.match(r'^([0-9$A-Fa-f+\-\s]+?)(,[XY])?$',body)
    if (m and re.match(r'^[\d$]',body)) or lohi:
        if lohi:
            v=numconst.get(op.lstrip('#<>'), None)
            if v is None: v={'SCR':0xD000}[op.lstrip('#<>')]
            v=(v>>8) if lohi=='>' else (v&255)
            body='$%02X'%v; hexish=True
        else:
            e=m.group(1).replace(' ','')
            v=eval(re.sub(r'\$([0-9A-Fa-f]+)',lambda mm:str(int(mm.group(1),16)),e))
            body=(('$%02X'%v if v<256 else '$%04X'%v) if (hexish or not imm) else str(v))+(m.group(2) or '')
    return ('#' if imm else '')+body.upper()

out=[]   # (label, text)
out.append(('', '* = $%04X'%ORG))
for k in KEEP_EQU:
    src=[s for s,t in GLOBAL.items() if t==k][0]
    v=cval(src)
    out.append((k, '= $%02X'%v if v<256 else '= $%04X'%v))
parent=None
for l in lines:
    s=l.strip()
    if not s or re.match(r'^[A-Za-z_]\w*\s*=',s) or s.startswith('.setcpu') or s.startswith('.segment'):
        continue
    lab=''
    m=re.match(r'^(@?[A-Za-z_]\w*):\s*(.*)$',l)
    if m:
        name,rest=m.group(1),m.group(2)
        if name.startswith('@'): lab=local[(parent,name)]
        else: parent=name; lab=GLOBAL[name]
        s=rest.strip()
    if not s:
        out.append((lab,None)); continue
    if s.startswith('.byte'):
        args=[]
        for a in re.findall(r'"[^"]*"|[^,]+',s[5:]):
            a=a.strip()
            if a.startswith('"'): args+=['$%02X'%ord(c) for c in a[1:-1]]
            else: args.append(operand(a,parent))
        for i in range(0,len(args),8):
            out.append((lab if i==0 else '', '.BYTE '+','.join(args[i:i+8])))
        continue
    if s.startswith('.res'):
        n=numconst.get(s[4:].strip()) or num(s[4:])
        z=['0']*n
        for i in range(0,n,8):
            out.append((lab if i==0 else '', '.BYTE '+','.join(z[i:i+8])))
        continue
    parts=s.split(None,1)
    mn=parts[0].upper(); op=parts[1] if len(parts)>1 else ''
    if mn=='INC' and op.strip().lower()=='a':
        out.append((lab,'CLC')); out.append(('','ADC #1')); continue
    out.append((lab,(mn+' '+operand(op,parent)).strip()))

# merge label-only lines onto the next instruction
merged=[]; pend=None
for lab,t in out:
    if t is None:
        if pend: merged.append((pend,'NOP_PLACEHOLDER'))
        pend=lab; continue
    if pend:
        if lab: merged.append((pend,'NOP_PLACEHOLDER'))
        else: lab=pend
        pend=None
    merged.append((lab,t))
assert not any(t=='NOP_PLACEHOLDER' for _,t in merged), 'two labels in a row'
merged.append(('', '.END'))
with open(OUT,'w', newline='\r\n') as f:
    n=10
    for lab,t in merged:
        assert len(lab)<=6, lab
        f.write('%5d %-7s %s\n'%(n,lab,t) if not t.startswith('=') else '%5d %-5s %s\n'%(n,lab,t))
        n+=10
print(len(merged),'lines')
