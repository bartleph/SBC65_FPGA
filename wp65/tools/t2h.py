def doc(c):
    L=c.lab; m=c.mem
    cur=m[L['CUR']]|m[L['CUR']+1]<<8
    gs=m[L['GS']]|m[L['GS']+1]<<8; ge=m[L['GE']]|m[L['GE']+1]<<8
    return bytes(m[0x8200:gs])+bytes(m[ge:0xC000]), cur
