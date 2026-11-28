import sys
b=open(sys.argv[1],'rb').read(); org=int(sys.argv[2],16); out=[]
for i in range(0,len(b),16):
    d=b[i:i+16]; a=org+i
    r=bytes([len(d),a>>8,a&255,0])+d
    out.append(':'+r.hex().upper()+'%02X'%((-sum(r))&255))
out.append(':00000001FF')
open(sys.argv[3],'w').write('\r\n'.join(out)+'\r\n')
