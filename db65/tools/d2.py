from emu import *
import pickle
c=DB(); c.run()
c.cmd('CREATE PEOPLE')
for f in ['NAME,C,20','TOWN,C,15','AGE,N,3','SALARY,N,9,2','BORN,D','MEMBER,L','']: c.cmd(f)
c.cmd('100')
c.cmd('APPEND'); c.show('append form')
recs=[('Alice Smith','Ryde','34','28500','12/03/1991','Y'),('Bob Jones','Cowes','51','31000.5','01/11/1974','N'),
      ('Carol White','Newport','28','24250.75','29/02/1996','Y'),('David Brown','Ryde','45','40100','15/07/1980','Y'),
      ('Eve Black','Sandown','62','19999.99','30/06/1963','N')]
W=[20,15,3,9,10,1]
for r in recs:
    for v,w in zip(r,W):
        c.keys(v.encode()+(b'' if len(v)>=w else b'\r'))
    if len(r[-1])>=1: c.keys(b'\r')
c.show('after typing')
c.keys(b'\x17')
c.show('after ^W')
c.cmd('LIST')
c.show('list')
pickle.dump(c.disk.t,open('disk1.pkl','wb'))
