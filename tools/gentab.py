from optab import op, M
names = sorted({m for m,_ in op.values() if m!='???'}) + ['???']
out=[]
out.append("; ---- generated tables (gentab.py) ----")
out.append("; NAMES: 3 characters per mnemonic")
out.append("NAMES:")
for i in range(0,len(names),8):
    out.append('        .byte "'+''.join(names[i:i+8])+'"   ; '+' '.join(f'{j}' for j in range(i,min(i+8,len(names)))))
out.append("\n; MNET: mnemonic number for each opcode $00-$FF")
out.append("MNET:")
for r in range(16):
    row=[op[r*16+c][0] for c in range(16)]
    out.append('        .byte '+','.join(f'{names.index(m):2d}' for m in row)+f'  ; ${r:X}0 '+' '.join(row))
out.append("\n; MODET: addressing mode, two opcodes per byte (even opcode in the")
out.append("; high nibble). 0 IMP 1 ACC 2 IMM 3 ZP 4 ZP,X 5 ZP,Y 6 ABS 7 ABS,X")
out.append("; 8 ABS,Y 9 (ABS) 10 (ZP,X) 11 (ZP),Y 12 (ZP) 13 (ABS,X) 14 REL 15 ZP,REL")
out.append("MODET:")
for r in range(16):
    bs=[M.index(op[r*16+c][1])*16+M.index(op[r*16+c+1][1]) for c in range(0,16,2)]
    out.append('        .byte '+','.join(f'${b:02X}' for b in bs)+f'  ; ${r:X}0-${r:X}F')
open('/home/claude/tools/tables.inc','w').write('\n'.join(out)+'\n')
print(len(names))
