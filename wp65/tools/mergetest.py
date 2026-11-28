from emu import *; from kw import putfile
def dbimg(fields, recs):
    reclen=1+sum(w for _,_,w in fields)
    h=bytearray(512); h[0:4]=b'DB65'; h[4:6]=len(recs).to_bytes(2,'little'); h[6:8]=reclen.to_bytes(2,'little'); h[8]=len(fields)
    o=1
    for i,(n,t,w) in enumerate(fields):
        e=16+16*i; h[e:e+11]=n.encode().ljust(11,b'\0'); h[e+11]=ord(t); h[e+12]=w; h[e+13]=0; h[e+14:e+16]=o.to_bytes(2,'little'); o+=w
    tracks=[bytearray(h)]; 
    for r in recs:
        b=bytearray()
        b+=b'*' if r[0] else b' '
        for (n,t,w),v in zip(fields,r[1:]):
            b+= (v.rjust(w) if t=='N' else v.ljust(w)).encode()
        if len(tracks[-1])+len(b)>2048: tracks.append(bytearray())
        tracks[-1]+=b
    return b''.join(t.ljust(2048,b'\0') for t in tracks)
F=[('NAME','C',12),('TOWN','C',10),('AGE','N',3),('BORN','D',8)]
R=[(0,'Alice Brown','Ryde','42','19830512'),(1,'Deleted Guy','Cowes','1','20000101'),(0,'Bob Smith','Newport','7','')]
c=DB(binf='WP.BIN',lbl='WP.lbl'); 
c.mem[0x265C]=2; putfile(c,'PEOPLE',dbimg(F,R),20); c.mem[0x265C]=1
c.run()
txt=""".DF B:PEOPLE
.PL 14
Dear &NAME&,
  You live in &town& and are &AGE& (born &BORN&). Fish & chips & &NOPE& stay.
"""
c.keys(txt.replace('\n','\r'))
log=bytearray(); c.mem.subscribe_to_write([0xC081],lambda a,v: log.append(v))
c.keys(b'\x0bpp')
out=log.decode('latin1'); i=out.find('\x1b[2J\x1b[H'); out=out[i+7:]; j=out.find('\x1b[2J'); out=out[:j]
for n,l in enumerate(out.split('\r\n')): print('%2d|%s'%(n+1,l))
c.show('after'); print(c.dos[-6:], c.mem[0x265C])
