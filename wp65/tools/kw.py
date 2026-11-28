KW="END FOR NEXT DATA INPUT DIM READ LET GOTO RUN IF RESTORE GOSUB RETURN REM STOP ON NULL WAIT LOAD SAVE DEF POKE PRINT CONT LIST CLEAR NEW TAB( TO FN SPC( THEN NOT STEP + - * / ^ AND OR > = < SGN INT ABS USR FRE POS SQR RND LOG EXP COS SIN TAN ATN PEEK LEN STR$ VAL ASC CHR$ LEFT$ RIGHT$ MID$".split()
def kwtab():
    b=bytearray()
    for k in KW: b+=k[:-1].encode()+bytes([ord(k[-1])|0x80])
    return bytes(b)+b'\0'
def tok(text):
    # python model of crunch
    out=bytearray(); i=0; q=False; d=False
    while i<len(text):
        ch=text[i]
        if q: out.append(ord(ch)); q = ch!='"'; i+=1; continue
        if ch=='"': q=True; out.append(34); i+=1; continue
        if d:
            out.append(ord(ch)); d = ch!=':'; i+=1; continue
        if ch=='?': out.append(0x80+KW.index('PRINT')); i+=1; continue
        if ch==' ' or '0'<=ch<'<': out.append(ord(ch)); i+=1; continue
        for n,k in enumerate(KW):
            if text[i:i+len(k)].upper()==k:
                out.append(0x80+n); i+=len(k)
                if k=='DATA': d=True
                if k=='REM': out+=text[i:].encode(); i=len(text)
                break
        else: out.append(ord(ch)); i+=1
    return bytes(out)
def basimg(lines):
    base=0x3A79; body=bytearray(b'\0'); 
    addr=0x3A7F
    for n,t in lines:
        tk=tok(t); nxt=addr+4+len(tk)+1
        body+=bytes([nxt&255,nxt>>8,n&255,n>>8])+tk+b'\0'; addr=nxt
    body+=b'\0\0'
    img=bytearray(5)+body
    end=base+len(img); tr=(len(img)+2047)//2048
    img[0:5]=bytes([0x7F,0x3A,end&255,end>>8,tr])
    return bytes(img)
def asmimg(lines):
    body=bytearray()
    for i,t in enumerate(lines):
        n=(i+1)*10; enc=bytearray(); j=0
        while j<len(t):
            if t[j]==' ':
                k=j
                while k<len(t) and t[k]==' ': k+=1
                run=k-j
                if run>=3:
                    enc.append(32); r=run-1
                    while r: c=min(r,128); enc.append(256-c); r-=c
                else: enc+=b' '*run
                j=k
            else: enc.append(ord(t[j])); j+=1
        body+=bytes([n&255,n>>8])+enc+b'\r'
    img=bytearray(5)+body; base=0x3279
    end=base+len(img); tr=(len(img)+2047)//2048
    img[0:5]=bytes([0x7E,0x32,end&255,end>>8,tr]); return bytes(img)
def putfile(c,name,img,start):
    tr=(len(img)+2047)//2048
    ents=c.disk.dir(); i=min(set(range(32))-{e[0] for e in ents})
    c.disk.setdir(i,name,start,start+tr-1)
    for k in range(tr): c.disk.t[(start+k,1)]=img[k*2048:(k+1)*2048].ljust(2048,b'\0')
def getfile(c,name):
    e=[e for e in c.disk.dir() if e[1]==name][0]
    return b''.join(c.disk.t[(k,1)] for k in range(e[2],e[3]+1))
