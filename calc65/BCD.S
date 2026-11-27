;=====================================================================
; BCD.S - DECIMAL FLOATING POINT FOR CALC65
;
; A NUMBER IS 8 BYTES:  +0 SIGN ($00 OR $80)
;                       +1 EXPONENT (SIGNED, -99..99)
;                       +2..+7 MANTISSA, 12 BCD DIGITS, NORMALISED
; VALUE = 0.MMMMMMMMMMMM * 10^EXP.  ZERO = ALL BYTES 0.
;
; FA AND FB ARE THE WORKING REGISTERS.  RESULTS GO TO FA.
; AN ERROR (OVERFLOW, DIVIDE BY 0) JUMPS TO FERR, WHICH UNWINDS THE
; STACK TO ERRSP AND RETURNS C=1 TO WHOEVER SET ERRSP.
;=====================================================================

        .zeropage
FA:     .res 8
FA_S    = FA
FA_E    = FA+1
FA_M    = FA+2
FB:     .res 8
FB_S    = FB
FB_E    = FB+1
FB_M    = FB+2
PR:     .res 8              ; PRODUCT / REMAINDER (PR+0 OVERFLOW, PR+7 GUARD)
QT:     .res 7              ; QUOTIENT
BT1:    .res 1
BT2:    .res 1
BT3:    .res 1
BT4:    .res 1
BT5:    .res 1
ERRSP:  .res 1              ; STACK POINTER TO RETURN TO ON AN ERROR

        .bss
DIG:    .res 13             ; UNPACKED DIGITS FOR PRINTING
DEXP:   .res 1              ; EXPONENT THAT GOES WITH DIG
DZERO:  .res 1              ; 1 = DIG IS ALL ZERO AFTER ROUNDING
OBUF:   .res 48             ; NUMBER AS TEXT
OLEN:   .res 1
T16:    .res 2              ; 16-BIT BINARY FOR FINT16

        .code

; ---- ERROR EXIT ----------------------------------------------------
FERR:   cld
        ldx ERRSP
        txs
        sec
        rts

; ---- FA = 0 ---------------------------------------------------------
FZERO:  ldx #7
@l:     stz FA,x
        dex
        bpl @l
        rts

; ---- FA = 1 ---------------------------------------------------------
FONE:   jsr FZERO
        lda #1
        sta FA_E
        lda #$10
        sta FA_M
        rts

; ---- COPIES ---------------------------------------------------------
FAB:    ldx #7              ; FB = FA
@l:     lda FA,x
        sta FB,x
        dex
        bpl @l
        rts
FBA:    ldx #7              ; FA = FB
@l:     lda FB,x
        sta FA,x
        dex
        bpl @l
        rts
FSWAP:  ldx #7
@l:     lda FA,x
        ldy FB,x
        sta FB,x
        sty FA,x
        dex
        bpl @l
        rts

; FA = (PTR), (PTR) = FA, FB = (PTR)
FLDA:   ldy #7
@l:     lda (PTR),y
        sta FA,y
        dey
        bpl @l
        rts
FSTA:   ldy #7
@l:     lda FA,y
        sta (PTR),y
        dey
        bpl @l
        rts
FLDB:   ldy #7
@l:     lda (PTR),y
        sta FB,y
        dey
        bpl @l
        rts

; ---- NIBBLE SHIFTS --------------------------------------------------
SHRA:   ldx #4
@l:     lsr FA_M
        ror FA_M+1
        ror FA_M+2
        ror FA_M+3
        ror FA_M+4
        ror FA_M+5
        dex
        bne @l
        rts
SHLA:   ldx #4
@l:     asl FA_M+5
        rol FA_M+4
        rol FA_M+3
        rol FA_M+2
        rol FA_M+1
        rol FA_M
        dex
        bne @l
        rts
SHRB:   ldx #4
@l:     lsr FB_M
        ror FB_M+1
        ror FB_M+2
        ror FB_M+3
        ror FB_M+4
        ror FB_M+5
        dex
        bne @l
        rts
SHRP:   ldx #4
@l:     lsr PR
        ror PR+1
        ror PR+2
        ror PR+3
        ror PR+4
        ror PR+5
        ror PR+6
        ror PR+7
        dex
        bne @l
        rts
SHLP:   ldx #4
@l:     asl PR+6
        rol PR+5
        rol PR+4
        rol PR+3
        rol PR+2
        rol PR+1
        rol PR
        dex
        bne @l
        rts
SHLQ:   ldx #4
@l:     asl QT+6
        rol QT+5
        rol QT+4
        rol QT+3
        rol QT+2
        rol QT+1
        rol QT
        dex
        bne @l
        rts

; ---- NORMALISE FA AND CHECK THE RANGE -------------------------------
FNORM:  lda FA_M
        ora FA_M+1
        ora FA_M+2
        ora FA_M+3
        ora FA_M+4
        ora FA_M+5
        bne @b
        jmp FZERO
@b:     lda FA_M            ; WHOLE ZERO BYTES FIRST
        bne @n
        ldx #0
@sb:    lda FA_M+1,x
        sta FA_M,x
        inx
        cpx #5
        bne @sb
        stz FA_M+5
        dec FA_E
        dec FA_E
        bra @b
@n:     lda FA_M
        and #$F0
        bne FRANGE
        jsr SHLA
        dec FA_E
        bra @n
; EXPONENT MUST BE -99..99: TOO BIG = ERROR, TOO SMALL = 0
FRANGE: lda FA_E
        bmi @neg
        cmp #100
        bcs FOVER
        rts
@neg:   cmp #$9D            ; -99
        bcs @ok
        jmp FZERO
@ok:    rts
FOVER:  jmp FERR

; ---- FA = FA + FB, FA - FB -----------------------------------------
FSUB:   lda FB_M
        beq FADD
        lda FB_S
        eor #$80
        sta FB_S
FADD:   lda FB_M
        bne @1
        rts                 ; + 0
@1:     lda FA_M
        bne @2
        jmp FBA             ; 0 + B
@2:     lda FA_E            ; MAKE FA THE ONE WITH THE BIGGER EXPONENT
        eor #$80
        sta BT1
        lda FB_E
        eor #$80
        cmp BT1
        bcc @3
        beq @3
        jsr FSWAP
@3:     lda FB_E
        eor #$80
        sta BT1
        lda FA_E
        eor #$80
        sec
        sbc BT1             ; A = DIGITS TO SHIFT FB RIGHT
        cmp #12
        bcc @4
        rts                 ; FB TOO SMALL TO MATTER
@4:     sta BT2
@sh2:   lda BT2             ; WHOLE BYTES
        cmp #2
        bcc @sh1
        ldx #5
@sb:    lda FB_M-1,x
        sta FB_M,x
        dex
        bne @sb
        stz FB_M
        dec BT2
        dec BT2
        bra @sh2
@sh1:   lda BT2
        beq @al
        jsr SHRB
@al:    lda FA_S
        eor FB_S
        bmi @sub
        sed                 ; SAME SIGNS: ADD MAGNITUDES
        clc
        ldx #5
@ad:    lda FA_M,x
        adc FB_M,x
        sta FA_M,x
        dex
        bpl @ad
        cld
        bcc @done
        jsr SHRA
        lda FA_M
        ora #$10
        sta FA_M
        inc FA_E
@done:  jmp FNORM
@sub:   ldx #0              ; DIFFERENT SIGNS: BIGGER - SMALLER
@cm:    lda FA_M,x
        cmp FB_M,x
        bcc @swp
        bne @ds
        inx
        cpx #6
        bne @cm
        jmp FZERO           ; EQUAL MAGNITUDES
@swp:   jsr FSWAP
@ds:    sed
        sec
        ldx #5
@sl:    lda FA_M,x
        sbc FB_M,x
        sta FA_M,x
        dex
        bpl @sl
        cld
        jmp FNORM

; ---- FA = FA * FB ---------------------------------------------------
FMUL:   lda FA_M
        beq @z
        lda FB_M
        bne @1
@z:     jmp FZERO
@1:     lda FA_S
        eor FB_S
        sta FA_S
        clc
        lda FA_E
        adc FB_E
        bvc @2
        lda FA_E            ; OUT OF RANGE: SIGN SAYS WHICH WAY
        bmi @z
        jmp FERR
@2:     sta FA_E
        ldx #6
@cp:    stz PR,x
        dex
        bpl @cp
        lda #12
        sta BT1
@dig:   lda FB_M+5          ; LOWEST DIGIT OF FB
        and #$0F
        beq @sh
        sta BT2
@add:   sed
        clc
        ldx #5
@al:    lda PR+1,x
        adc FA_M,x
        sta PR+1,x
        dex
        bpl @al
        lda PR
        adc #0
        sta PR
        cld
        dec BT2
        bne @add
@sh:    jsr SHRP
        jsr SHRB
        dec BT1
        bne @dig
        lda PR+1            ; PRODUCT UNDER 0.1: BRING IN A GUARD DIGIT
        and #$F0
        bne @cpy
        ldx #4
@gs:    asl PR+7
        rol PR+6
        rol PR+5
        rol PR+4
        rol PR+3
        rol PR+2
        rol PR+1
        dex
        bne @gs
        dec FA_E
@cpy:   ldx #5
@mv:    lda PR+1,x
        sta FA_M,x
        dex
        bpl @mv
        jmp FNORM

; ---- FA = FA / FB ---------------------------------------------------
FDIV:   lda FB_M
        bne @1
        jmp FERR            ; DIVIDE BY ZERO
@1:     lda FA_M
        bne @2
        rts                 ; 0 / B = 0
@2:     lda FA_S
        eor FB_S
        sta FA_S
        sec
        lda FA_E
        sbc FB_E
        bvs @ov
        clc
        adc #1
        bvs @ov
        sta FA_E
        bra @3
@ov:    lda FA_E
        bmi @zz
        jmp FERR
@zz:    jmp FZERO
@3:     stz PR              ; REMAINDER = FA
        ldx #5
@cr:    lda FA_M,x
        sta PR+1,x
        dex
        bpl @cr
        ldx #6
@cq:    stz QT,x
        dex
        bpl @cq
        lda #14
        sta BT1
@dig:   stz BT2             ; THIS DIGIT
@cmp:   lda PR
        bne @ge
        ldx #0
@cb:    lda PR+1,x
        cmp FB_M,x
        bcc @lt
        bne @ge
        inx
        cpx #6
        bne @cb
@ge:    sed
        sec
        ldx #5
@sb:    lda PR+1,x
        sbc FB_M,x
        sta PR+1,x
        dex
        bpl @sb
        lda PR
        sbc #0
        sta PR
        cld
        inc BT2
        bra @cmp
@lt:    jsr SHLQ
        lda QT+6
        ora BT2
        sta QT+6
        jsr SHLP
        dec BT1
        bne @dig
        lda QT              ; FIRST DIGIT 0: USE THE 13TH
        and #$F0
        bne @q
        jsr SHLQ
        dec FA_E
@q:     ldx #5
@mv:    lda QT,x
        sta FA_M,x
        dex
        bpl @mv
        jmp FNORM

; ---- COMPARE FA WITH FB: A = $FF (FA<FB), 0 (EQUAL), 1 (FA>FB) ------
FCMP:   lda FA_M
        bne @1
        lda FB_M
        beq @eq
        lda FB_S            ; 0 VS B
        bmi @gt
        bra @lt
@1:     lda FB_M
        bne @2
        lda FA_S            ; A VS 0
        bmi @lt
        bra @gt
@2:     lda FA_S
        cmp FB_S
        beq @3
        lda FA_S            ; DIFFERENT SIGNS
        bmi @lt
        bra @gt
@3:     lda FB_E            ; SAME SIGN: COMPARE SIZES
        eor #$80
        sta BT1
        lda FA_E
        eor #$80
        cmp BT1
        bne @m
        ldx #0
@c:     lda FA_M,x
        cmp FB_M,x
        bne @m
        inx
        cpx #6
        bne @c
@eq:    lda #0
        rts
@m:     bcc @small          ; C=0: |A| < |B|
        lda FA_S
        bmi @lt
        bra @gt
@small: lda FA_S
        bmi @gt
@lt:    lda #$FF
        rts
@gt:    lda #1
        rts

; ---- FA = INT(FA)  (TOWARDS ZERO) -----------------------------------
FINT:   lda FA_M
        beq @r
        lda FA_E
        bmi @z
        beq @z
        cmp #12
        bcs @r
        tax                 ; X = FIRST DIGIT TO CLEAR (1-11)
        lsr a
        tay                 ; Y = ITS BYTE
        bcc @even
        lda FA_M,y          ; ODD DIGIT = LOW NIBBLE
        and #$F0
        sta FA_M,y
        iny
@even:  cpy #6
        bcs @n
        lda #0
        sta FA_M,y
        iny
        bra @even
@n:     jmp FNORM
@z:     jmp FZERO
@r:     rts

FABS:   stz FA_S
        rts
FNEG:   lda FA_M
        beq @r
        lda FA_S
        eor #$80
        sta FA_S
@r:     rts

; ---- 16-BIT BINARY T16 -> FA ----------------------------------------
FINT16: jsr FZERO
        lda #16
        sta BT1
        sed
@l:     asl T16
        rol T16+1
        lda FA_M+2
        adc FA_M+2
        sta FA_M+2
        lda FA_M+1
        adc FA_M+1
        sta FA_M+1
        lda FA_M
        adc FA_M
        sta FA_M
        dec BT1
        bne @l
        cld
        lda #6
        sta FA_E
        jmp FNORM

;=====================================================================
; TEXT -> NUMBER.  READS DIGITS AT (TP),Y.  C=0: FA = THE NUMBER,
; Y PAST IT.  C=1: NO NUMBER THERE (Y UNCHANGED).
; ACCEPTS 123  1.5  .25  1E6  2.5E-3
;=====================================================================
FPARSE: sty BT5             ; START, IN CASE IT FAILS
        jsr FZERO
        stz BT1             ; DIGITS KEPT
        stz BT2             ; DECIMAL EXPONENT
        stz BT3             ; 1 = AFTER THE POINT
        stz BT4             ; 1 = SAW A DIGIT
@nx:    lda (TP),y
        cmp #'.'
        beq @dot
        cmp #'0'
        bcc @end
        cmp #'9'+1
        bcs @end
        and #$0F
        pha
        lda #1
        sta BT4
        pla
        bne @nz
        ldx BT1             ; A ZERO
        bne @nz
        lda BT3             ; LEADING ZERO: ONLY COUNTS AFTER THE POINT
        beq @nxt
        dec BT2
        bra @nxt
@nz:    ldx BT1
        cpx #12
        bcs @skip
        pha
        txa
        lsr a
        tax                 ; BYTE
        pla
        bcs @odd
        asl a
        asl a
        asl a
        asl a
        sta FA_M,x
        bra @kept
@odd:   ora FA_M,x
        sta FA_M,x
@kept:  inc BT1
@skip:  lda BT3
        bne @nxt
        inc BT2
@nxt:   iny
        bra @nx
@dot:   lda BT3
        bne @end
        inc BT3
        iny
        bra @nx
@end:   lda BT4
        bne @ex
        ldy BT5
        sec
        rts
@ex:    lda (TP),y          ; EXPONENT PART?
        cmp #'E'
        bne @fin
        sty BT5             ; WHERE THE E IS
        iny
        stz BT3             ; EXPONENT SIGN
        lda (TP),y
        cmp #'+'
        beq @es
        cmp #'-'
        bne @ed
        inc BT3
@es:    iny
@ed:    lda (TP),y
        cmp #'0'
        bcc @noe
        cmp #'9'+1
        bcs @noe
        stz BT4             ; EXPONENT VALUE
@el:    lda (TP),y
        cmp #'0'
        bcc @ee
        cmp #'9'+1
        bcs @ee
        and #$0F
        sta BT1
        lda BT4             ; BT4 = BT4*10 + DIGIT
        cmp #13
        bcs @big
        asl a
        asl a
        adc BT4
        asl a
        adc BT1
        sta BT4
        iny
        bra @el
@big:   jmp FERR
@noe:   ldy BT5             ; NOT AN EXPONENT AFTER ALL
        bra @fin
@ee:    lda BT3
        beq @ep
        sec
        lda BT2
        sbc BT4
        sta BT2
        bra @fin
@ep:    clc
        lda BT2
        adc BT4
        sta BT2
@fin:   lda FA_M
        beq @zero
        lda BT2
        sta FA_E
        phy
        jsr FRANGE
        ply
        clc
        rts
@zero:  jsr FZERO
        clc
        rts

;=====================================================================
; NUMBER -> TEXT IN OBUF/OLEN
;=====================================================================
; UNPACK FA INTO DIG[0..11], DEXP
UNPACK: ldx #0
        ldy #0
@l:     lda FA_M,x
        lsr a
        lsr a
        lsr a
        lsr a
        sta DIG,y
        iny
        lda FA_M,x
        and #$0F
        sta DIG,y
        iny
        inx
        cpx #6
        bne @l
        lda FA_E
        sta DEXP
        stz DZERO
        lda FA_M
        bne @r
        inc DZERO
@r:     rts

; ROUND DIG TO KEEP A DIGITS (A SIGNED)
ROUNDK: tax
        bmi @zero
        beq @first
        cpx #12
        bcs @r
        lda DIG,x
        cmp #5
        bcc @clr
        phx
@up:    dex
        bmi @carry
        inc DIG,x
        lda DIG,x
        cmp #10
        bcc @upd
        stz DIG,x
        bra @up
@carry: lda #1              ; 9.99 -> 10.0
        sta DIG
        inc DEXP
@upd:   plx
@clr:   stz DIG,x
        inx
        cpx #12
        bcc @clr
@r:     rts
@first: lda DIG             ; KEEP NO DIGITS: 0 OR ONE UNIT UP
        cmp #5
        bcc @zero
        ldx #11
@f:     stz DIG,x
        dex
        bpl @f
        lda #1
        sta DIG
        inc DEXP
        rts
@zero:  ldx #11
@z:     stz DIG,x
        dex
        bpl @z
        lda #1
        sta DZERO
        rts

; APPEND A TO OBUF
OPUTC:  ldx OLEN
        cpx #47
        bcs @r
        sta OBUF,x
        inc OLEN
@r:     rts
OPUTD:  ora #'0'
        bra OPUTC

; FIXED FORMAT WITH A DECIMALS (0-15).  OLEN = 255 IF TOO BIG.
FIXSTR: sta BT4             ; DECIMALS
        jsr UNPACK
        stz OLEN
        lda DEXP
        bmi @k
        cmp #31
        bcc @k
        lda #255            ; WAY TOO BIG FOR ANY COLUMN
        sta OLEN
        rts
@k:     clc
        lda DEXP
        adc BT4
        bvs @k0
        jsr ROUNDK
        bra @k1
@k0:    lda #$FF            ; (CANNOT HAPPEN WITH SANE DECIMALS)
        jsr ROUNDK
@k1:    lda FA_S
        bpl @int
        lda DZERO
        bne @int
        lda #'-'
        jsr OPUTC
@int:   lda DEXP
        beq @i0
        bpl @id
@i0:    lda #'0'
        jsr OPUTC
        bra @dec
@id:    stz BT3             ; INTEGER DIGITS 0..DEXP-1
@il:    ldx BT3
        lda #0
        cpx #12
        bcs @iz
        lda DIG,x
@iz:    jsr OPUTD
        inc BT3
        lda BT3
        cmp DEXP
        bne @il
@dec:   lda BT4
        beq @r
        lda #'.'
        jsr OPUTC
        stz BT3             ; J = 0..DECIMALS-1, POSITION = DEXP+J
@dl:    clc
        lda DEXP
        adc BT3
        bmi @d0
        cmp #12
        bcs @d0
        tax
        lda DIG,x
        bra @dp
@d0:    lda #0
@dp:    jsr OPUTD
        inc BT3
        lda BT3
        cmp BT4
        bne @dl
@r:     rts

; SCIENTIFIC WITH A DIGITS (1-10): D.DDDE+NN
SCISTR: sta BT4
        jsr UNPACK
        stz OLEN
        lda BT4
        jsr ROUNDK
        lda FA_S
        bpl @1
        lda #'-'
        jsr OPUTC
@1:     lda DIG
        jsr OPUTD
        lda BT4
        cmp #2
        bcc @e
        lda #'.'
        jsr OPUTC
        lda #1
        sta BT3
@dl:    ldx BT3
        lda DIG,x
        jsr OPUTD
        inc BT3
        lda BT3
        cmp BT4
        bne @dl
@e:     jsr TRIMZ           ; 1.500E+03 -> 1.5E+03
        lda #'E'
        jsr OPUTC
        ldx DEXP
        dex                 ; D.DDD * 10^(DEXP-1)
        txa
        bmi @neg
        pha
        lda #'+'
        bra @s
@neg:   eor #$FF
        inc a
        pha
        lda #'-'
@s:     jsr OPUTC
        pla
        ldx #0              ; TENS
@t:     cmp #10
        bcc @u
        sbc #10
        inx
        bra @t
@u:     pha
        txa
        jsr OPUTD
        pla
        jmp OPUTD

; REMOVE TRAILING ZEROS AFTER A DECIMAL POINT
TRIMZ:  ldx #0
@f:     cpx OLEN
        beq @r              ; NO POINT
        lda OBUF,x
        cmp #'.'
        beq @t
        inx
        bra @f
@t:     ldx OLEN
        dex
        lda OBUF,x
        cmp #'0'
        bne @p
        dec OLEN
        bra @t
@p:     cmp #'.'
        bne @r
        dec OLEN
@r:     rts

; GENERAL FORMAT TO FIT A COLUMNS.  OLEN > WIDTH IF IT CANNOT.
GENSTR: sta BT5             ; WIDTH
        lda FA_M
        bne @nz
        stz OLEN
        lda #'0'
        jmp OPUTC
@nz:    lda BT5             ; AVAILABLE = WIDTH - SIGN
        ldx FA_S
        bpl @a
        dec a
        bpl @a
        lda #0
@a:     sta GAVAIL
        lda FA_E
        bmi @small
        beq @small
        cmp #13             ; 1..12 INTEGER DIGITS
        bcs @sci
        cmp GAVAIL
        beq @f1
        bcs @sci
@f1:    sec                 ; D = AVAIL - E - 1, AT MOST 10 - E
        lda GAVAIL
        sbc FA_E
        sbc #1
        bpl @f2
        lda #0
@f2:    sta BT1
        sec
        lda #10
        sbc FA_E
        bpl @f4
        lda #0
@f4:    cmp BT1
        bcs @f3
        sta BT1
@f3:    lda BT1
        jsr FIXSTR
        jsr TRIMZ
        lda OLEN
        cmp BT5
        beq @r
        bcc @r
        bra @sci
@small: sec                 ; 0.000DDD: D = AVAIL - 2, AT MOST 10 - E
        lda GAVAIL
        sbc #2
        bmi @sci
        sta BT1
        sec
        lda #10
        sbc FA_E
        cmp BT1
        bcs @s2
        sta BT1
@s2:    lda #1              ; NEED D >= 1 - E TO SHOW THE FIRST DIGIT
        sec
        sbc FA_E
        cmp BT1
        beq @s3
        bcs @sci
@s3:    lda BT1
        jsr FIXSTR
        jsr TRIMZ
        lda DZERO
        bne @sci
        lda OLEN
        cmp BT5
        beq @r
        bcc @r
@sci:   lda GAVAIL          ; M = AVAIL - 5 DIGITS (1..10)
        cmp #5
        bcc @wide
        sec
        sbc #5
        cmp #2
        bcs @m1
        lda #1
@m1:    cmp #11
        bcc @m2
        lda #10
@m2:    jmp SCISTR
@wide:  lda #255
        sta OLEN
@r:     rts

        .bss
GAVAIL: .res 1
        .code
