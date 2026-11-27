import re,subprocess,sys
INV={'beq':'bne','bne':'beq','bcc':'bcs','bcs':'bcc','bmi':'bpl','bpl':'bmi','bvc':'bvs','bvs':'bvc'}
main=sys.argv[1]
for it in range(20):
    r=subprocess.run(['ca65','--cpu','65C02','-g',main,'-o','/tmp/x.o'],capture_output=True,text=True)
    errs=re.findall(r'^(\S+)\((\d+)\): Error: Range error',r.stderr,re.M)
    if not errs:
        print(r.stderr.strip() or 'clean'); break
    byfile={}
    for f,n in errs: byfile.setdefault(f,set()).add(int(n))
    for f,ns in byfile.items():
        L=open(f).read().split('\n')
        for n in sorted(ns,reverse=True):
            line=L[n-1]; m=re.match(r'^(\S*:)?(\s+)(b\w\w)\s+(\S+)(.*)$',line)
            lab=m.group(1) or ''; op=m.group(3); tgt=m.group(4); rest=m.group(5)
            if op=='bra': L[n-1]=f'{lab}{m.group(2)}jmp {tgt}{rest}'
            else:
                L[n-1:n]=[f'{lab}{m.group(2)}{INV[op]} :+{rest}', f'        jmp {tgt}', ':']
        open(f,'w').write('\n'.join(L))
    print('fixed',len(errs))
