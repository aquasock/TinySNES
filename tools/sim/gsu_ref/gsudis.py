import sys
rom=open(sys.argv[1],'rb').read()
def off(b,a): return (b&0x3f)*0x8000+(a&0x7fff)
bank=int(sys.argv[2],16); s=int(sys.argv[3],16); e=int(sys.argv[4],16)
br=['STOP','NOP','CACHE','LSR','ROL','BRA','BGE','BLT','BNE','BEQ','BPL','BMI','BCC','BCS','BVC','BVS']
a=s; alt=0
while a<e:
    o=rom[off(bank,a)]; n=o&15; h=o>>4; ln=1; t=''
    if h==0:
        t=br[n]
        if n>=5: d=rom[off(bank,a+1)]; d=d-256 if d>127 else d; t+=' %04x'%((a+2+d)&0xffff); ln=2
    elif h==1: t='TO R%d'%n
    elif h==2: t='WITH R%d'%n
    elif h==3: t={12:'LOOP',13:'ALT1',14:'ALT2',15:'ALT3'}.get(n,('STB' if alt&1 else 'STW')+' (R%d)'%n)
    elif h==4: t={12:'RPIX' if alt&1 else 'PLOT',13:'SWAP',14:'CMODE' if alt&1 else 'COLOR',15:'NOT'}.get(n,('LDB' if alt&1 else 'LDW')+' (R%d)'%n)
    elif h in(5,6,7,8,0xc):
        nm={5:['ADD','ADC','ADD#','ADC#'],6:['SUB','SBC','SUB#','CMP'],7:['AND','BIC','AND#','BIC#'],8:['MULT','UMULT','MULT#','UMULT#'],0xc:['OR','XOR','OR#','XOR#']}[h][alt]
        if h==7 and n==0: nm='MERGE'
        if h==0xc and n==0: nm='HIB'
        t=nm+('' if nm in('MERGE','HIB') else (' %d'%n if '#' in nm else ' R%d'%n))
    elif h==9:
        t={0:'SBK',5:'SEX',6:'DIV2' if alt&1 else 'ASR',7:'ROR',0xe:'LOB',0xf:'LMULT' if alt&1 else 'FMULT'}.get(n)
        if t is None: t='LINK #%d'%n if n<5 else (('LJMP' if alt&1 else 'JMP')+' R%d'%(n))
    elif h==0xa:
        b=rom[off(bank,a+1)]; ln=2
        t=['IBT R%d,#%02x'%(n,b),'LMS R%d,(%03x)'%(n,b*2),'SMS (%03x),R%d'%(b*2,n),'?'][alt]
    elif h==0xb: t='FROM R%d'%n
    elif h==0xd: t='INC R%d'%n if n<15 else ['GETC','?','RAMB','ROMB'][alt]
    elif h==0xe: t='DEC R%d'%n if n<15 else ['GETB','GETBH','GETBL','GETBS'][alt]
    elif h==0xf:
        w=rom[off(bank,a+1)]|rom[off(bank,a+2)]<<8; ln=3
        t=['IWT R%d,#%04x'%(n,w),'LM R%d,(%04x)'%(n,w),'SM (%04x),R%d'%(w,n),'?'][alt]
    print('%02x:%04x  %-10s %s'%(bank,a,' '.join('%02x'%rom[off(bank,a+i)] for i in range(ln)),t))
    alt = {0x3d:1,0x3e:2,0x3f:3}.get(o,0) if h==3 and n>=13 else 0
    if h in(1,2,0xb): alt=alt  # prefixes keep alt? (TO/WITH/FROM don't reset)
    a+=ln
