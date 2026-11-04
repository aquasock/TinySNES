import re
L=open('GSU.vhd').read().split('\n')
procs=[(835,842,858),(890,914,969),(1127,1185,1272)]
def targets(lines):
    s=set()
    for l in lines:
        l=l.split('--')[0]
        for m in re.finditer(r'([A-Za-z_]\w*)(\([^)]*\))?(\.\w+)?\s*(<=|:=)',l): s.add(m.group(1))
    return s
def idents(lines):
    s=set()
    for l in lines: s|=set(re.findall(r'[A-Za-z_]\w*',l.split('--')[0]))
    return s
out=[];shadow_decl=[];pos=0
for (p,f,r) in procs:
    e=next(i for i in range(r,len(L)+1) if re.match(r'\s*end process',L[i-1]))
    b=next(i for i in range(p,f) if re.match(r'\s*begin\s*$',L[i-1]))
    head=L[p-1:b]
    rst0=L[b]; assert "RST_N" in rst0
    vdecl={re.search(r'variable\s+(\w+)',l).group(1):l for l in head if 'variable' in l}
    rst=L[b+1:f-1]; fb=L[f:r-1]; rb=L[r:e-2]  # bodies (exclude elsif lines and final end if)
    assert re.match(r'\s*end if;',L[e-2]),L[e-2]
    fa,ra=targets(fb),targets(rb)
    # split reset statements (single-line assumption checked)
    rf,rr=[],[]
    for l in rst:
        t=targets([l])
        if not t: rf.append(l); rr.append(l); continue
        assert len(t)==1,l
        (rf if t<=fa else rr).append(l) if (t<=fa or t<=ra) else (_ for _ in ()).throw(Exception(l))
    shadows={}
    for v in vdecl:
        own='f' if v in fa else 'r' if v in ra else None
        other=rb if own=='f' else fb
        if own and v in idents(other): shadows[v]=own
    print(p,'cross-edge vars:',shadows)
    def sub(lines,owner):
        res=[]
        for l in lines:
            for v,o in shadows.items():
                if o!=owner: l=re.sub(r'\b%s\b'%v,v+'_XS',l)
            res.append(l)
        return res
    for v,o in shadows.items():
        typ=vdecl[v].split(':',1)[1].strip().rstrip(';')
        shadow_decl.append('\tsignal %s_XS : %s;'%(v,typ))
    out+=L[pos:p-1]
    for edge,body,rs,own in (('falling',fb,rf,'f'),('rising',rb,rr,'r')):
        mine=fa if own=='f' else ra
        out+=[l for l in head if 'variable' not in l or re.search(r'variable\s+(\w+)',l).group(1) in mine]
        sh=['\t\t\t%s_XS <= %s;'%(v,v) for v,o in shadows.items() if o==own]
        out+=['\t\tif RST_N = \'0\' then']+rs+sh+['\t\telsif %s_edge(CLK) then'%edge]+sub(body,own)+sh+['\t\tend if;']
        out+=['\tend process;','']
    pos=e
out+=L[pos:]
txt='\n'.join(out)
i=txt.index('\nbegin',txt.index('architecture'))
txt=txt[:i]+'\n'+'\n'.join(shadow_decl)+txt[i:]
open('GSU_split.vhd','w').write(txt)
