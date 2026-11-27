from emu import *
import pickle,time
c=DB(lines=24); c.run()
c.cmd('CREATE T'); [c.cmd(f) for f in ['NAME,C,10','AGE,N,3','']]; c.cmd('300')
for i in range(300): c.cmd('APPEND BLANK')
c.cmd('REPLACE ALL NAME WITH "N"+STR(RECNO(),4), AGE WITH RECNO()*37-INT(RECNO()*37/100)*100')
c.cmd('DELETE FOR AGE < 10')
r0,w0=c.reads,c.writes
c.cmd('PACK'); print('pack io',c.reads-r0,c.writes-w0, c.text().split('\n')[-2])
r0,w0=c.reads,c.writes; cy=c.cpu.processorCycles
c.cmd('SORT ON AGE TO TS'); print('sort io',c.reads-r0,c.writes-w0,'cycles',c.cpu.processorCycles-cy)
cy=c.cpu.processorCycles
c.cmd('SORT ON NAME TO TN DESCENDING'); print('sort2 cycles',c.cpu.processorCycles-cy)
pickle.dump(c.disk.t,open('disk3.pkl','wb'))
# verify by decoding disk in python
def readfile(name):
    for i,n,a,b in c.disk.dir():
        if n==name: break
    data=b''.join(c.disk.t[(t,1)] for t in range(a,b+1))
    nrec=data[4]|data[5]<<8; rl=data[6]|data[7]<<8
    r0=1536//rl; rpt=2048//rl; recs=[]
    for k in range(nrec):
        if k<r0: off=512+k*rl
        else:
            m=k-r0; off=2048*(1+m//rpt)+(m%rpt)*rl
        recs.append(data[off:off+rl].decode('latin1'))
    return recs
T=readfile('T'); S=readfile('TS'); N=readfile('TN')
print(len(T),len(S),len(N))
ages=[int(r[11:14]) for r in S]; print('TS sorted:',ages==sorted(ages), ages[:10])
names=[r[1:11] for r in N]; print('TN sorted desc:',names==sorted(names,reverse=True), names[:3])
print('same records:', sorted(T)==sorted(S)==sorted(N))
print('T has no deleted:', all(r[0]==' ' for r in T), 'no age<10:', all(int(r[11:14])>=10 for r in T))
