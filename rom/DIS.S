;************************************************************************
;* DIS.S - 65C02 DISASSEMBLER FOR THE OS-65D V3.3 ROM DOS               *
;*                                                                      *
;* DA SSSS          DISASSEMBLE 20 INSTRUCTIONS FROM SSSS, THEN WAIT:   *
;*                  ANY KEY = 20 MORE, ESC OR CTRL-C = BACK TO THE DOS  *
;* DA SSSS EEEE     DISASSEMBLE FROM SSSS THROUGH EEEE                  *
;*                  (ESC OR CTRL-C STOPS, SPACE PAUSES - AS MD)         *
;*                                                                      *
;*   E000  4C A5 F4  JMP  $F4A5                                         *
;*   D123  B1 12     LDA  ($12),Y                                       *
;*   C200  0F 12 FD  BBR0 $12,$C200                                     *
;*                                                                      *
;* KNOWS ALL 212 W65C02S OPCODES, INCLUDING RMB/SMB/BBR/BBS, WAI, STP. *
;* AN UNUSED OPCODE IS SHOWN AS ???, ONE BYTE LONG, SO DATA AND TEXT   *
;* SOON FALL BACK INTO STEP. BRANCH TARGETS ARE WORKED OUT.             *
;*                                                                      *
;* IT RUNS FROM THE SD.S ROM BLOCK ($C100-$CFFF). SDDISP SENDS "DA"     *
;* HERE (DADISP); ANYTHING ELSE GOES ON TO CHKSY AS BEFORE. IT USES     *
;* DOSX'S LINE AND KEY HELPERS (DX_GETW ETC., SET UP IN ROM.S).         *
;*                                                                      *
;* NOTE: DA READS THE MEMORY IT LISTS, SO LISTING THE I/O PAGE CAN      *
;* UPSET THE ACIA OR VIA (A READ OF THE ACIA DATA REGISTER TAKES A KEY).*
;*                                                                      *
;* RAM: P1 ($12/$13) IS THE ADDRESS POINTER (AS MD USES IT). THE OTHER  *
;* VARIABLES SHARE DOSX'S COMMAND SCRATCH BYTES AT $3566-$356F; ONLY    *
;* ONE COMMAND RUNS AT A TIME.                                          *
;*                                                                      *
;* TABLES ARE MADE BY GENTAB.PY FROM ITS OPCODE LIST.                  *
;************************************************************************

PTR     = $12               ; = DOSX P1: ADDRESS OF THE INSTRUCTION
DOPC    = $3566             ; OPCODE
DMODE   = $3567             ; ADDRESSING MODE 0-15
DLEN    = $3568             ; LENGTH 1-3
DTMP    = $3569
DTL     = $356A             ; BRANCH TARGET
DTH     = $356B
DCNT    = $356C             ; LINES LEFT ON THIS PAGE
DFLG    = $356D             ; $FF = RANGE GIVEN (DA SSSS EEEE)
DENDL   = $356E             ; END ADDRESS
DENDH   = $356F

; DADISP: SDDISP JUMPS HERE (INSTEAD OF CHKSY) FOR ANYTHING THAT IS
; NOT MO, WITH X AND Y AS THEY WERE.  "DA" -> DACMD, ELSE CHKSY.
DADISP: phx
        phy
        ldy #0
        lda (INBUF),y
        jsr UCASE
        cmp #'D'
        bne @no
        iny
        lda (INBUF),y
        jsr UCASE
        cmp #'A'
        bne @no
        ply
        plx
        lda #>(DACMD-1)
        pha
        lda #<(DACMD-1)
        pha
        jmp SKIPAR          ; ITS RTS ENTERS DACMD
@no:    ply
        plx
        jmp CHKSY

;================================================================
; DA SSSS [EEEE]
;================================================================
DACMD:  jsr DX_GETW
        sta PTR
        sty PTR+1
        stz DFLG
        jsr DX_ATEND
        beq @page
        jsr DX_GETW
        sta DENDL
        sty DENDH
        dec DFLG            ; $FF: STOP AFTER EEEE
@page:  lda #20
        sta DCNT
@line:  jsr DISONE          ; C=1: WENT PAST $FFFF
        bcs @done
        bit DFLG
        bpl @cnt
        lda DENDL           ; RANGE: DONE WHEN PTR > END
        cmp PTR
        lda DENDH
        sbc PTR+1
        bcc @done
@key:   jsr DX_KEYCHK
        bcc @line
        bra @done
@cnt:   jsr DX_KEYCHK    ; ESC CAN STOP A PAGE PART WAY
        bcs @done
        dec DCNT
        bne @line
        jsr DX_SERIN     ; PAGE FULL: WAIT FOR A KEY
        cmp #$1B
        beq @done
        cmp #$03
        bne @page
@done:  jmp CRLF

;================================================================
; DISONE - LIST THE INSTRUCTION AT PTR ON A NEW LINE, THEN STEP
; PTR PAST IT.  C=1 IF PTR WENT PAST $FFFF.
;================================================================
DISONE: jsr CRLF
        lda PTR+1           ; ADDRESS
        jsr PRHEX
        lda PTR
        jsr PRHEX
        jsr PRSP
        jsr PRSP
        lda (PTR)           ; OPCODE -> MODE (NIBBLE TABLE)
        sta DOPC
        lsr a
        tax
        lda MODET,x
        bcs @odd
        lsr a               ; EVEN OPCODE: HIGH NIBBLE
        lsr a
        lsr a
        lsr a
@odd:   and #$0F
        sta DMODE
        tax
        lda LENT,x
        sta DLEN
        ldy #0              ; THE BYTES, PADDED TO 3
@hex:   lda (PTR),y
        jsr PRHEX
        jsr PRSP
        iny
        cpy DLEN
        bne @hex
@pad:   cpy #3
        beq @mne
        jsr PRSP
        jsr PRSP
        jsr PRSP
        iny
        bra @pad
@mne:   jsr PRSP
        ldx DOPC            ; MNEMONIC: NAMES + 3 * NUMBER
        lda MNET,x
        sta DTMP
        asl a               ; C=0 (NUMBER < 128)
        adc DTMP
        tax
        ldy #3
@nm:    lda NAMES,x
        jsr OUTCH
        inx
        dey
        bne @nm
        lda DOPC            ; $x7 AND $xF (RMB SMB BBR BBS)
        and #$07            ; GET THE BIT NUMBER, BITS 4-6
        cmp #$07
        bne @sp
        lda DOPC
        lsr a
        lsr a
        lsr a
        lsr a
        and #$07
        ora #'0'
        bra @sp2
@sp:    lda #' '
@sp2:   jsr OUTCH
        jsr PRSP
        ldx DMODE           ; OPERAND FROM THE MODE'S TEMPLATE:
        lda TPLOFF,x        ;  b = BYTE 1, w = WORD (BYTES 2,1),
        tax                 ;  r = BRANCH TARGET, 0 = END
@tp:    lda TPL,x
        beq @step
        cmp #'b'
        beq @byte
        cmp #'w'
        beq @word
        cmp #'r'
        beq @rel
        jsr OUTCH
@nx:    inx
        bra @tp
@byte:  ldy #1
        lda (PTR),y
        jsr PRHEX
        bra @nx
@word:  ldy #2
        lda (PTR),y
        jsr PRHEX
        dey
        lda (PTR),y
        jsr PRHEX
        bra @nx
@rel:   clc                 ; TARGET = PTR + LEN + OFFSET (LAST BYTE)
        lda PTR
        adc DLEN
        sta DTL
        lda PTR+1
        adc #0
        sta DTH
        ldy DLEN
        dey
        lda (PTR),y
        bpl @pos
        dec DTH             ; NEGATIVE OFFSET
@pos:   clc
        adc DTL
        sta DTL
        lda DTH
        adc #0
        jsr PRHEX
        lda DTL
        jsr PRHEX
        bra @nx
@step:  clc                 ; PTR += LEN, C=1 IF IT WRAPPED
        lda PTR
        adc DLEN
        sta PTR
        lda PTR+1
        adc #0
        sta PTR+1
        rts

PRSP:   lda #' '
        jmp OUTCH

; INSTRUCTION LENGTH FOR EACH MODE
LENT:   .byte 1,1,2,2,2,2,3,3,3,3,2,2,2,3,2,3

; OPERAND TEMPLATES FOR EACH MODE
TPLOFF: .byte T_IMP-TPL,T_ACC-TPL,T_IMM-TPL,T_ZP-TPL
        .byte T_ZPX-TPL,T_ZPY-TPL,T_ABS-TPL,T_ABX-TPL
        .byte T_ABY-TPL,T_IND-TPL,T_IZX-TPL,T_IZY-TPL
        .byte T_ZPI-TPL,T_IAX-TPL,T_REL-TPL,T_ZPR-TPL
TPL:
T_IMP:  .byte 0
T_ACC:  .byte "A",0
T_IMM:  .byte "#$b",0
T_ZP:   .byte "$b",0
T_ZPX:  .byte "$b,X",0
T_ZPY:  .byte "$b,Y",0
T_ABS:  .byte "$w",0
T_ABX:  .byte "$w,X",0
T_ABY:  .byte "$w,Y",0
T_IND:  .byte "($w)",0
T_IZX:  .byte "($b,X)",0
T_IZY:  .byte "($b),Y",0
T_ZPI:  .byte "($b)",0
T_IAX:  .byte "($w,X)",0
T_REL:  .byte "$r",0
T_ZPR:  .byte "$b,$r",0

; ---- generated tables (gentab.py) ----
; NAMES: 3 characters per mnemonic
NAMES:
        .byte "ADCANDASLBBRBBSBCCBCSBEQ"   ; 0 1 2 3 4 5 6 7
        .byte "BITBMIBNEBPLBRABRKBVCBVS"   ; 8 9 10 11 12 13 14 15
        .byte "CLCCLDCLICLVCMPCPXCPYDEC"   ; 16 17 18 19 20 21 22 23
        .byte "DEXDEYEORINCINXINYJMPJSR"   ; 24 25 26 27 28 29 30 31
        .byte "LDALDXLDYLSRNOPORAPHAPHP"   ; 32 33 34 35 36 37 38 39
        .byte "PHXPHYPLAPLPPLXPLYRMBROL"   ; 40 41 42 43 44 45 46 47
        .byte "RORRTIRTSSBCSECSEDSEISMB"   ; 48 49 50 51 52 53 54 55
        .byte "STASTPSTXSTYSTZTAXTAYTRB"   ; 56 57 58 59 60 61 62 63
        .byte "TSBTSXTXATXSTYAWAI???"   ; 64 65 66 67 68 69 70

; MNET: mnemonic number for each opcode $00-$FF
MNET:
        .byte 13,37,70,70,64,37, 2,46,39,37, 2,70,64,37, 2, 3  ; $00 BRK ORA ??? ??? TSB ORA ASL RMB PHP ORA ASL ??? TSB ORA ASL BBR
        .byte 11,37,37,70,63,37, 2,46,16,37,27,70,63,37, 2, 3  ; $10 BPL ORA ORA ??? TRB ORA ASL RMB CLC ORA INC ??? TRB ORA ASL BBR
        .byte 31, 1,70,70, 8, 1,47,46,43, 1,47,70, 8, 1,47, 3  ; $20 JSR AND ??? ??? BIT AND ROL RMB PLP AND ROL ??? BIT AND ROL BBR
        .byte  9, 1, 1,70, 8, 1,47,46,52, 1,23,70, 8, 1,47, 3  ; $30 BMI AND AND ??? BIT AND ROL RMB SEC AND DEC ??? BIT AND ROL BBR
        .byte 49,26,70,70,70,26,35,46,38,26,35,70,30,26,35, 3  ; $40 RTI EOR ??? ??? ??? EOR LSR RMB PHA EOR LSR ??? JMP EOR LSR BBR
        .byte 14,26,26,70,70,26,35,46,18,26,41,70,70,26,35, 3  ; $50 BVC EOR EOR ??? ??? EOR LSR RMB CLI EOR PHY ??? ??? EOR LSR BBR
        .byte 50, 0,70,70,60, 0,48,46,42, 0,48,70,30, 0,48, 3  ; $60 RTS ADC ??? ??? STZ ADC ROR RMB PLA ADC ROR ??? JMP ADC ROR BBR
        .byte 15, 0, 0,70,60, 0,48,46,54, 0,45,70,30, 0,48, 3  ; $70 BVS ADC ADC ??? STZ ADC ROR RMB SEI ADC PLY ??? JMP ADC ROR BBR
        .byte 12,56,70,70,59,56,58,55,25, 8,66,70,59,56,58, 4  ; $80 BRA STA ??? ??? STY STA STX SMB DEY BIT TXA ??? STY STA STX BBS
        .byte  5,56,56,70,59,56,58,55,68,56,67,70,60,56,60, 4  ; $90 BCC STA STA ??? STY STA STX SMB TYA STA TXS ??? STZ STA STZ BBS
        .byte 34,32,33,70,34,32,33,55,62,32,61,70,34,32,33, 4  ; $A0 LDY LDA LDX ??? LDY LDA LDX SMB TAY LDA TAX ??? LDY LDA LDX BBS
        .byte  6,32,32,70,34,32,33,55,19,32,65,70,34,32,33, 4  ; $B0 BCS LDA LDA ??? LDY LDA LDX SMB CLV LDA TSX ??? LDY LDA LDX BBS
        .byte 22,20,70,70,22,20,23,55,29,20,24,69,22,20,23, 4  ; $C0 CPY CMP ??? ??? CPY CMP DEC SMB INY CMP DEX WAI CPY CMP DEC BBS
        .byte 10,20,20,70,70,20,23,55,17,20,40,57,70,20,23, 4  ; $D0 BNE CMP CMP ??? ??? CMP DEC SMB CLD CMP PHX STP ??? CMP DEC BBS
        .byte 21,51,70,70,21,51,27,55,28,51,36,70,21,51,27, 4  ; $E0 CPX SBC ??? ??? CPX SBC INC SMB INX SBC NOP ??? CPX SBC INC BBS
        .byte  7,51,51,70,70,51,27,55,53,51,44,70,70,51,27, 4  ; $F0 BEQ SBC SBC ??? ??? SBC INC SMB SED SBC PLX ??? ??? SBC INC BBS

; MODET: addressing mode, two opcodes per byte (even opcode in the
; high nibble). 0 IMP 1 ACC 2 IMM 3 ZP 4 ZP,X 5 ZP,Y 6 ABS 7 ABS,X
; 8 ABS,Y 9 (ABS) 10 (ZP,X) 11 (ZP),Y 12 (ZP) 13 (ABS,X) 14 REL 15 ZP,REL
MODET:
        .byte $0A,$00,$33,$33,$02,$10,$66,$6F  ; $00-$0F
        .byte $EB,$C0,$34,$43,$08,$10,$67,$7F  ; $10-$1F
        .byte $6A,$00,$33,$33,$02,$10,$66,$6F  ; $20-$2F
        .byte $EB,$C0,$44,$43,$08,$10,$77,$7F  ; $30-$3F
        .byte $0A,$00,$03,$33,$02,$10,$66,$6F  ; $40-$4F
        .byte $EB,$C0,$04,$43,$08,$00,$07,$7F  ; $50-$5F
        .byte $0A,$00,$33,$33,$02,$10,$96,$6F  ; $60-$6F
        .byte $EB,$C0,$44,$43,$08,$00,$D7,$7F  ; $70-$7F
        .byte $EA,$00,$33,$33,$02,$00,$66,$6F  ; $80-$8F
        .byte $EB,$C0,$44,$53,$08,$00,$67,$7F  ; $90-$9F
        .byte $2A,$20,$33,$33,$02,$00,$66,$6F  ; $A0-$AF
        .byte $EB,$C0,$44,$53,$08,$00,$77,$8F  ; $B0-$BF
        .byte $2A,$00,$33,$33,$02,$00,$66,$6F  ; $C0-$CF
        .byte $EB,$C0,$04,$43,$08,$00,$07,$7F  ; $D0-$DF
        .byte $2A,$00,$33,$33,$02,$00,$66,$6F  ; $E0-$EF
        .byte $EB,$C0,$04,$43,$08,$00,$07,$7F  ; $F0-$FF
