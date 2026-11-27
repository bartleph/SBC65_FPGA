;=====================================================================
; EVAL.S - FORMULA EVALUATOR FOR CALC65
;
;  EXPR   = SUM [ ( = < > <= >= <> ) SUM ]      (TRUE = 1, FALSE = 0)
;  SUM    = TERM { (+ -) TERM }
;  TERM   = FACTOR { (* /) FACTOR }
;  FACTOR = - FACTOR | + FACTOR | PRIM [ ^ FACTOR ]
;  PRIM   = NUMBER | CELL | ( EXPR ) | FUNC ( ARGS )
;  CELL   = [$]A-Z[$]1-128
;  FUNCS  SUM AVERAGE (AV) MIN MAX COUNT (ITEMS MAY BE RANGES A1:B9)
;         ABS INT IF(TEST,THEN,ELSE)
;
; EVALUATE: TP -> FORMULA TEXT.  C=0: FA = RESULT.  C=1: ERROR, AND
; PERR=1 IF IT WAS A SYNTAX ERROR (OTHERWISE A MATHS OR CELL ERROR).
;=====================================================================


        .zeropage
TP:     .res 2              ; FORMULA TEXT
TI:     .res 1              ; POSITION IN IT
VSP:    .res 1              ; VALUE STACK OFFSET
AGGB:   .res 1              ; VALUE STACK OFFSET OF THE CURRENT SUM()
PTR:    .res 2
PTR2:   .res 2

        .bss
VSTK:   .res 256            ; VALUE STACK, 32 ENTRIES OF 8 BYTES
PERR:   .res 1
RCOL:   .res 1              ; LAST CELL REFERENCE READ
RROW:   .res 1
RABS:   .res 1              ; BIT0 = $COL, BIT1 = $ROW
R1COL:  .res 1
R1ROW:  .res 1
NAMEB:  .res 9
AGMODE: .res 1
        .code

EVALUATE:
        stz TI
        stz VSP
        stz PERR
        tsx
        stx ERRSP
        jsr EXPR
        jsr PEEK            ; MUST BE AT THE END
        bne SYNERR
        clc
        rts

SYNERR: lda #1
        sta PERR
        jmp FERR

; ---- NEXT CHARACTER (SPACES SKIPPED); Z=1 AT THE END ----------------
PEEK:   ldy TI
@l:     lda (TP),y
        cmp #' '
        bne @r
        iny
        sty TI
        bra @l
@r:     cmp #0
        rts
NEXT:   inc TI
        rts
EXPECT: sta BT1             ; NEXT CHARACTER MUST BE A
        jsr PEEK
        cmp BT1
        bne SYNERR
        inc TI
        rts

; ---- VALUE STACK ----------------------------------------------------
PUSHA:  ldx VSP
        cpx #$F8
        bcs @full
        ldy #0
@l:     lda FA,y
        sta VSTK,x
        inx
        iny
        cpy #8
        bne @l
        stx VSP
        rts
@full:  jmp FERR
POPA:   jsr POPX
@l:     lda VSTK,x
        sta FA,y
        inx
        iny
        cpy #8
        bne @l
        rts
POPB:   jsr POPX
@l:     lda VSTK,x
        sta FB,y
        inx
        iny
        cpy #8
        bne @l
        rts
POPX:   sec
        lda VSP
        sbc #8
        sta VSP
        tax
        ldy #0
        rts

; ---- EXPR: A COMPARISON ---------------------------------------------
EXPR:   jsr SUMX
        jsr PEEK
        ldx #0              ; X = OPERATOR BITS: 1 <, 2 =, 4 >
        cmp #'<'
        bne @1
        ldx #1
        jsr NEXT
        jsr PEEK
        cmp #'='
        bne @2
        ldx #3
        jsr NEXT
        bra @go
@2:     cmp #'>'
        bne @go
        ldx #5
        jsr NEXT
        bra @go
@1:     cmp #'='
        bne @3
        ldx #2
        jsr NEXT
        bra @go
@3:     cmp #'>'
        bne @r
        ldx #4
        jsr NEXT
        jsr PEEK
        cmp #'='
        bne @go
        ldx #6
        jsr NEXT
@go:    phx
        jsr PUSHA
        jsr SUMX
        jsr FAB
        jsr POPA
        jsr FCMP            ; $FF / 0 / 1 -> BIT 1 / 2 / 4
        tax
        lda #1
        cpx #$FF
        beq @b
        lda #2
        cpx #0
        beq @b
        lda #4
@b:     sta BT1
        pla
        and BT1
        beq @f
        jmp FONE
@f:     jmp FZERO
@r:     rts

; ---- SUM: + AND - ---------------------------------------------------
SUMX:   jsr TERM
@l:     jsr PEEK
        cmp #'+'
        beq @p
        cmp #'-'
        beq @m
        rts
@p:     jsr NEXT
        jsr PUSHA
        jsr TERM
        jsr FAB
        jsr POPA
        jsr FADD
        bra @l
@m:     jsr NEXT
        jsr PUSHA
        jsr TERM
        jsr FAB
        jsr POPA
        jsr FSUB
        bra @l

; ---- TERM: * AND / --------------------------------------------------
TERM:   jsr FACTOR
@l:     jsr PEEK
        cmp #'*'
        beq @t
        cmp #'/'
        beq @d
        rts
@t:     jsr NEXT
        jsr PUSHA
        jsr FACTOR
        jsr FAB
        jsr POPA
        jsr FMUL
        bra @l
@d:     jsr NEXT
        jsr PUSHA
        jsr FACTOR
        jsr FAB
        jsr POPA
        jsr FDIV
        bra @l

; ---- FACTOR: SIGNS AND ^ (WHOLE-NUMBER POWERS) ----------------------
FACTOR: jsr PEEK
        cmp #'-'
        bne @1
        jsr NEXT
        jsr FACTOR
        jmp FNEG
@1:     cmp #'+'
        bne @2
        jsr NEXT
        jmp FACTOR
@2:     jsr PRIM
        jsr PEEK
        cmp #'^'
        beq @pw
        rts
@pw:    jsr NEXT
        jsr PUSHA           ; BASE
        jsr FACTOR          ; POWER
        jmp POWER

; FA = (STACKED BASE) ^ FA.  THE POWER MUST BE A WHOLE NUMBER -99..99.
POWER:  jsr FAB
        jsr FINT
        jsr FCMP
        cmp #0
        bne @bad            ; NOT WHOLE
        lda FA_M            ; 0..99 -> BINARY
        beq @n0
        lda FA_E
        cmp #3
        bcs @bad
        jsr FTOBYTE
        bra @n
@n0:    lda #0
@n:     sta BT4             ; COUNT
        lda FA_S
        sta BT5             ; NEGATIVE POWER?
        jsr POPA            ; BASE
        jsr PUSHA
        jsr FONE
@l:     lda BT4
        beq @d
        lda VSP             ; FA = FA * BASE
        sec
        sbc #8
        jsr STKB
        lda BT4
        pha
        lda BT5
        pha
        jsr FMUL
        pla
        sta BT5
        pla
        sta BT4
        dec BT4
        bra @l
@d:     jsr POPB            ; DROP THE BASE
        lda BT5
        bpl @r
        jsr FAB             ; 1 / RESULT
        jsr FONE
        jmp FDIV
@r:     rts
@bad:   jmp FERR

; FB = THE VALUE STACK ENTRY AT OFFSET A
STKB:   tax
        ldy #0
@l:     lda VSTK,x
        sta FB,y
        inx
        iny
        cpy #8
        bne @l
        rts
STKA:   tax
        ldy #0
@l:     lda VSTK,x
        sta FA,y
        inx
        iny
        cpy #8
        bne @l
        rts
ASTK:   tax                 ; VALUE STACK ENTRY AT OFFSET A = FA
        ldy #0
@l:     lda FA,y
        sta VSTK,x
        inx
        iny
        cpy #8
        bne @l
        rts

; WHOLE FA 0..99 -> A
FTOBYTE: lda FA_E
        cmp #1
        bne @2
        lda FA_M            ; ONE DIGIT
        lsr a
        lsr a
        lsr a
        lsr a
        rts
@2:     lda FA_M            ; TWO DIGITS: TENS*10 + UNITS
        lsr a
        lsr a
        lsr a
        lsr a
        sta BT1
        asl a
        asl a
        adc BT1
        asl a
        sta BT1
        lda FA_M
        and #$0F
        adc BT1
        rts

; ---- PRIMARY --------------------------------------------------------
PRIM:   jsr PEEK
        cmp #'('
        bne @1
        jsr NEXT
        jsr EXPR
        lda #')'
        jmp EXPECT
@1:     cmp #'.'
        beq @num
        cmp #'0'
        bcc @2
        cmp #'9'+1
        bcs @2
@num:   ldy TI
        jsr FPARSE
        bcs @syn
        sty TI
        rts
@2:     jsr CELLREF
        bcs @fn
        jmp CELLVAL
@fn:    jmp FUNC
@syn:   jmp SYNERR

; ---- READ A CELL REFERENCE: C=0 -> RCOL, RROW (0-BASED), RABS -------
CELLREF:
        jsr PEEK
        ldy TI
        sty BT5             ; WHERE WE STARTED
        stz RABS
        cmp #'$'
        bne @c
        lda #1
        sta RABS
        iny
        lda (TP),y
@c:     jsr UPPER
        cmp #'A'
        bcc @no
        cmp #'Z'+1
        bcs @no
        sbc #'A'-1          ; (C=0 HERE)
        sta RCOL
        iny
        lda (TP),y
        cmp #'$'
        bne @d
        lda RABS
        ora #2
        sta RABS
        iny
        lda (TP),y
@d:     cmp #'0'
        bcc @no
        cmp #'9'+1
        bcs @no
        stz RROW            ; DIGITS -> ROW NUMBER (1-128)
        stz BT4             ; HIGH BYTE (TO CATCH 999)
@dl:    lda (TP),y
        cmp #'0'
        bcc @de
        cmp #'9'+1
        bcs @de
        and #$0F
        sta BT1
        lda RROW            ; RROW = RROW*10 + DIGIT
        cmp #26
        bcs @no
        asl a
        asl a
        adc RROW
        asl a
        adc BT1
        sta RROW
        iny
        bra @dl
@de:    jsr UPPER           ; NOT A CELL IF A LETTER FOLLOWS
        cmp #'A'
        bcc @ok
        cmp #'Z'+1
        bcc @no
@ok:    lda RROW
        beq @no
        cmp #NROW+1
        bcs @no
        dec RROW
        sty TI
        clc
        rts
@no:    ldy BT5
        sty TI
        sec
        rts

UPPER:  cmp #'a'
        bcc @r
        cmp #'z'+1
        bcs @r
        and #$DF
@r:     rts

; ---- FA = VALUE OF THE CELL RCOL,RROW (TEXT/EMPTY = 0) ---------------
CELLVAL:
        ldx RCOL
        lda RROW
        jsr GETCELL
        bcs @z
        ldy #R_TYPE
        lda (RP),y
        bmi @err
        beq @z
        clc
        lda RP
        adc #R_VAL
        sta PTR
        lda RP+1
        adc #0
        sta PTR+1
        jmp FLDA
@z:     jmp FZERO
@err:   jmp FERR

; ---- FUNCTIONS ------------------------------------------------------
FUNC:   ldy TI              ; NAME -> NAMEB
        ldx #0
@n:     lda (TP),y
        jsr UPPER
        cmp #'A'
        bcc @e
        cmp #'Z'+1
        bcs @e
        cpx #8
        bcs @syn
        sta NAMEB,x
        inx
        iny
        bra @n
@e:     cpx #0
        beq @syn
        stz NAMEB,x
        sty TI
        lda #'('
        jsr EXPECT
        ldx #0              ; LOOK IT UP
@f:     lda FNTAB,x
        beq @syn
        ldy #0
@c:     lda FNTAB,x
        cmp NAMEB,y
        bne @skip
        cmp #0
        beq @hit
        inx
        iny
        bra @c
@skip:  lda FNTAB,x         ; TO THE END OF THIS NAME
        beq @s2
        inx
        bra @skip
@s2:    inx                 ; PAST 0 AND THE 2-BYTE ADDRESS
        inx
        inx
        bra @f
@hit:   lda FNTAB+2,x       ; ADDRESS - 1, LIKE THE DOS TABLE
        pha
        lda FNTAB+1,x
        pha
        rts
@syn:   jmp SYNERR

FNTAB:  .byte "SUM",0
        .word F_SUM-1
        .byte "AVERAGE",0
        .word F_AVG-1
        .byte "AV",0
        .word F_AVG-1
        .byte "AVG",0
        .word F_AVG-1
        .byte "MIN",0
        .word F_MIN-1
        .byte "MAX",0
        .word F_MAX-1
        .byte "COUNT",0
        .word F_CNT-1
        .byte "ABS",0
        .word F_ABS-1
        .byte "INT",0
        .word F_INT-1
        .byte "IF",0
        .word F_IF-1
        .byte 0

F_ABS:  jsr EXPR
        lda #')'
        jsr EXPECT
        jmp FABS
F_INT:  jsr EXPR
        lda #')'
        jsr EXPECT
        jmp FINT

F_IF:   jsr EXPR            ; TEST
        jsr PUSHA
        lda #','
        jsr EXPECT
        jsr EXPR            ; THEN
        jsr PUSHA
        lda #','
        jsr EXPECT
        jsr EXPR            ; ELSE (IN FA)
        lda #')'
        jsr EXPECT
        lda VSP             ; TEST IS 16 BELOW THE TOP
        sec
        sbc #16
        tax
        lda VSTK+2,x        ; ITS FIRST MANTISSA BYTE: 0 = FALSE
        beq @f
        jsr POPA            ; TRUE: THE THEN VALUE
        bra @d
@f:     jsr POPB            ; FALSE: DROP THEN, KEEP FA
@d:     jmp POPB            ; DROP THE TEST

; SUM AVERAGE MIN MAX COUNT SHARE ONE ROUTINE.  FOUR VALUE STACK
; ENTRIES AT AGGB: +0 SUM, +8 MIN, +16 MAX, +24 COUNT (2 BYTES BINARY)
F_SUM:  lda #0
        bra AGG
F_AVG:  lda #1
        bra AGG
F_MIN:  lda #2
        bra AGG
F_MAX:  lda #3
        bra AGG
F_CNT:  lda #4
AGG:    pha                 ; MODE
        lda AGGB
        pha                 ; THE OUTER ONE'S BASE
        lda VSP
        sta AGGB
        jsr FZERO
        jsr PUSHA
        jsr PUSHA
        jsr PUSHA
        jsr PUSHA           ; (COUNT = 0 TOO)
@item:  jsr PEEK
        ldy TI
        sty BT3             ; REMEMBER, IN CASE IT IS NOT A RANGE
        jsr CELLREF
        bcs @exp
        jsr PEEK
        cmp #':'
        beq @rng
@exp:   ldy BT3             ; AN EXPRESSION
        sty TI
        jsr EXPR
        jsr AGADD
        bra @sep
@rng:   jsr NEXT
        lda RCOL
        sta R1COL
        lda RROW
        sta R1ROW
        jsr CELLREF
        bcc @r2
        jmp SYNERR
@r2:    jsr RANGEADD
@sep:   jsr PEEK
        cmp #','
        bne @end
        jsr NEXT
        bra @item
@end:   lda #')'
        jsr EXPECT
        pla                 ; THE OUTER BASE
        tay
        pla                 ; MODE
        tax
        phy
        lda AGGB
        cpx #0
        beq @sum
        cpx #1
        beq @avg
        cpx #4
        beq @cnt
        clc                 ; MIN (+8) OR MAX (+16)
        adc #8
        cpx #2
        beq @mm
        clc
        adc #8
@mm:    jsr STKA
        bra @out
@sum:   jsr STKA
        bra @out
@avg:   jsr AGCNT
        lda T16
        ora T16+1
        beq @zero
        jsr FINT16
        jsr FAB
        lda AGGB
        jsr STKA
        jsr FDIV
        bra @out
@cnt:   jsr AGCNT
        jsr FINT16
@out:   lda AGGB            ; DROP THE FOUR ENTRIES
        sta VSP
        pla
        sta AGGB
        rts
@zero:  jmp FERR            ; AVERAGE OF NOTHING

AGCNT:  clc                 ; T16 = THE COUNT
        lda AGGB
        adc #24
        tax
        lda VSTK,x
        sta T16
        lda VSTK+1,x
        sta T16+1
        rts

; ADD FA TO THE CURRENT SUM()
AGADD:  clc
        lda AGGB
        adc #24
        tax
        inc VSTK,x          ; COUNT
        bne @c1
        inc VSTK+1,x
@c1:    lda VSTK+1,x
        bne @nf
        lda VSTK,x
        cmp #1
        bne @nf
        clc                 ; THE FIRST ONE: MIN = MAX = IT
        lda AGGB
        adc #8
        jsr ASTK
        clc
        lda AGGB
        adc #16
        jsr ASTK
        bra @sum
@nf:    clc                 ; NEW MIN?
        lda AGGB
        adc #8
        jsr STKB
        jsr FCMP
        cmp #$FF
        bne @mx
        clc
        lda AGGB
        adc #8
        jsr ASTK
@mx:    clc                 ; NEW MAX?
        lda AGGB
        adc #16
        jsr STKB
        jsr FCMP
        cmp #1
        bne @sum
        clc
        lda AGGB
        adc #16
        jsr ASTK
@sum:   lda AGGB            ; SUM += FA
        jsr STKB
        jsr FADD
        lda AGGB
        jmp ASTK

; ADD EVERY NUMBER IN THE RANGE R1COL,R1ROW : RCOL,RROW
RANGEADD:
        lda RCOL            ; PUT THE CORNERS IN ORDER
        cmp R1COL
        bcs @1
        ldx R1COL
        sta R1COL
        stx RCOL
@1:     lda RROW
        cmp R1ROW
        bcs @2
        ldx R1ROW
        sta R1ROW
        stx RROW
@2:     lda R1ROW
        pha                 ; ROW LOOP (NESTED SUMS USE THESE TOO)
@row:   lda R1COL
        pha
@col:   pla
        pha
        tax
        tsx                 ; ROW IS ONE DEEPER ON THE STACK
        lda $0102,x
        pha
        lda $0101,x
        tax
        pla
        jsr GETCELL
        bcs @next
        ldy #R_TYPE
        lda (RP),y
        bmi @err
        beq @next           ; TEXT
        clc
        lda RP
        adc #R_VAL
        sta PTR
        lda RP+1
        adc #0
        sta PTR+1
        jsr FLDA
        lda RCOL            ; KEEP THE CORNERS SAFE
        pha
        lda RROW
        pha
        lda R1COL
        pha
        jsr AGADD
        pla
        sta R1COL
        pla
        sta RROW
        pla
        sta RCOL
@next:  pla                 ; NEXT COLUMN
        inc a
        pha
        cmp RCOL
        beq @col
        bcc @col
        pla
        pla                 ; NEXT ROW
        inc a
        pha
        cmp RROW
        beq @row
        bcc @row
        pla
        rts
@err:   jmp FERR
