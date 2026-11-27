;=====================================================================
; DBEXPR.S - EXPRESSIONS FOR DB65  (dBASE II STYLE)
;
; A VALUE IS VT (TYPE) PLUS FA:
;   'N' NUMBER: FA IS THE 8-BYTE BCD NUMBER
;   'C' TEXT, 'D' DATE (YYYYMMDD): FA+0/1 = ADDRESS, FA+2 = LENGTH
;   'L' LOGICAL: FA+0 = 0 OR 1
;
;   OR   = AND { .OR. AND }          AND = NOT { .AND. NOT }
;   NOT  = .NOT. NOT | REL           REL = ADD [ = <> # < > <= >= $ ADD ]
;   ADD  = MUL { + - MUL }           MUL = UN { * / UN }
;   UN   = - UN | + UN | PRIM
;   PRIM = NUMBER | "TEXT" | 'TEXT' | .T. | .F. | ( OR ) | FIELD
;        | FUNCTION(ARGS)
;=====================================================================

        .zeropage
TP:     .res 2              ; TEXT BEING READ
TI:     .res 1              ; POSITION IN IT
VT:     .res 1              ; TYPE OF THE VALUE IN FA
VSP:    .res 1
PTR:    .res 2              ; (FOR BCD.S FLDA/FSTA)
SP1:    .res 2              ; STRING POINTERS
SP2:    .res 2

        .bss
VSTK:   .res 252            ; VALUE STACK, 28 ENTRIES OF 9 BYTES
NAMEB:  .res 12
SPOS:   .res 2              ; NEXT FREE BYTE IN SBUF
NBUF:   .res 40             ; NUMBER TEXT FOR PARSING
SL1:    .res 1
NSIGN:  .res 1
STRDEC: .res 1
SL2:    .res 1
FNIDX:  .res 1
DSPBUF: .res 256            ; A VALUE AS TEXT
DSPLEN: .res 1
        .code

; ---- ERRORS ---------------------------------------------------------
ESYNTAX: lda #<M_SYN
        ldy #>M_SYN
        jmp ERRMSG
ETYPE:  lda #<M_TYPE
        ldy #>M_TYPE
        jmp ERRMSG
M_SYN:  .byte "SYNTAX ERROR",0
M_TYPE: .byte "WRONG TYPE OF VALUE",0
M_NOVAR: .byte "NO FIELD CALLED ",0

; ---- READING THE TEXT -----------------------------------------------
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
EXPECT: sta BT1
        jsr PEEK
        cmp BT1
        bne ESYNTAX
        inc TI
        rts

; READ A NAME (LETTER, THEN LETTERS/DIGITS/_) INTO NAMEB, UPPER CASE.
; C=1 IF THERE IS NO NAME HERE (TI UNCHANGED)
GETNAME: jsr PEEK
        jsr UPPER
        cmp #'A'
        bcc @no
        cmp #'Z'+1
        bcs @no
        ldx #0
        ldy TI
@l:     lda (TP),y
        jsr UPPER
        jsr ISNAMEC
        bcs @e
        cpx #10
        bcs @sk
        sta NAMEB,x
        inx
@sk:    iny
        bra @l
@e:     stz NAMEB,x
        sty TI
        clc
        rts
@no:    sec
        rts
; C=0 IF A IS A-Z, 0-9 OR _
ISNAMEC: cmp #'_'
        beq @y
        cmp #'0'
        bcc @n
        cmp #'9'+1
        bcc @y
        cmp #'A'
        bcc @n
        cmp #'Z'+1
        bcc @y
@n:     sec
        rts
@y:     clc
        rts

; IS THE WORD AT TI THE KEYWORD AT (MP)?  (WHOLE WORD, ANY CASE)
; C=0 YES (TI MOVED PAST IT), C=1 NO
KEYWORD: jsr PEEK
        ldy TI
        sty BT5
        ldx #0
@l:     phy
        txa
        tay
        lda (MP),y
        sta BT1
        ply
        lda BT1
        beq @end
        lda (TP),y
        jsr UPPER
        cmp BT1
        bne @no
        iny
        inx
        bra @l
@end:   lda (TP),y          ; MUST NOT GO ON AS A NAME
        jsr UPPER
        jsr ISNAMEC
        bcc @no
        sty TI
        clc
        rts
@no:    ldy BT5
        sty TI
        sec
        rts

; A DOTTED WORD (.AND. .OR. .NOT. .T. .F.) AT TI?  A = WHICH:
; 1 AND, 2 OR, 3 NOT, 4 TRUE, 5 FALSE.  C=1 NONE (TI UNCHANGED)
DOTWORD: jsr PEEK
        cmp #'.'
        bne @no
        ldy TI
        iny
        ldx #0
@l:     lda (TP),y
        jsr UPPER
        cmp #'.'
        beq @e
        cpx #4
        bcs @no
        sta NAMEB,x
        inx
        iny
        bra @l
@e:     iny
        stz NAMEB,x
        sty BT5
        ldx #0              ; LOOK IT UP
        ldy #1
@t:     lda DOTTAB,x
        beq @no
        phx
        phy
        ldy #0
@c:     lda DOTTAB,x
        cmp NAMEB,y
        bne @nx
        cmp #0
        beq @hit
        inx
        iny
        bra @c
@nx:    ply
        plx
@sk:    lda DOTTAB,x
        inx
        cmp #0
        bne @sk
        iny
        bra @t
@hit:   ply
        plx
        lda BT5
        sta TI
        tya
        clc
        rts
@no:    sec
        rts
DOTTAB: .byte "AND",0,"OR",0,"NOT",0,"T",0,"F",0,"Y",0,"N",0,0

; ---- VALUE STACK ----------------------------------------------------
PUSHV:  ldx VSP
        cpx #252-9
        bcs @full
        lda VT
        sta VSTK,x
        inx
        ldy #0
@l:     lda FA,y
        sta VSTK,x
        inx
        iny
        cpy #8
        bne @l
        stx VSP
        rts
@full:  lda #<M_CPLX
        ldy #>M_CPLX
        jmp ERRMSG
M_CPLX: .byte "EXPRESSION TOO COMPLICATED",0
; POP INTO FB (TYPE IN BT4)
POPB:   sec
        lda VSP
        sbc #9
        sta VSP
        tax
        lda VSTK,x
        sta BT4
        inx
        ldy #0
@l:     lda VSTK,x
        sta FB,y
        inx
        iny
        cpy #8
        bne @l
        rts
; LEFT VALUE (STACK) -> FA, RIGHT (FA NOW) -> FB.
; LEFT TYPE -> VT, RIGHT TYPE -> BT3
POPLR:  jsr FAB
        lda VT
        sta BT3
        sec
        lda VSP
        sbc #9
        sta VSP
        tax
        lda VSTK,x
        sta VT
        inx
        ldy #0
@l:     lda VSTK,x
        sta FA,y
        inx
        iny
        cpy #8
        bne @l
        rts

; ---- STRINGS --------------------------------------------------------
; RESERVE A BYTES IN SBUF -> SP2
SALLOC: sta BT1
        lda SPOS
        sta SP2
        lda SPOS+1
        sta SP2+1
        clc
        lda SPOS
        adc BT1
        sta SPOS
        lda SPOS+1
        adc #0
        sta SPOS+1
        cmp #>SBUFEND
        bcs @full
        rts
@full:  lda #<M_STR
        ldy #>M_STR
        jmp ERRMSG
M_STR:  .byte "TEXT TOO LONG",0
SRESET: lda #<SBUF
        sta SPOS
        lda #>SBUF
        sta SPOS+1
        rts
; FA = TEXT VALUE AT SP2, LENGTH A, TYPE C
SETSTR: sta FA+2
        lda SP2
        sta FA
        lda SP2+1
        sta FA+1
        lda #'C'
        sta VT
        rts

;=====================================================================
; EVALUATE THE EXPRESSION AT TP/TI -> VT, FA
;=====================================================================
EVAL:   stz VSP
        jsr SRESET
EVALX:  jsr ANDX            ; (EVALX: INSIDE, KEEPS THE STACK)
@l:     ldy TI
        phy
        jsr DOTWORD
        ply
        bcs @r
        cmp #2
        beq @or
        sty TI              ; NOT .OR.: PUT IT BACK
        rts
@or:    jsr NEEDL
        jsr PUSHV
        jsr ANDX
        jsr NEEDL
        jsr POPLR
        lda FA
        ora FB
        sta FA
        bra @l
@r:     rts

; (A DOTWORD THAT IS NOT OURS HAS MOVED TI: THE CALLERS BELOW
; SAVE TI BEFORE LOOKING)
ANDX:   jsr NOTX
@l:     ldy TI
        phy
        jsr DOTWORD
        ply
        bcs @r
        cmp #1
        beq @and
        sty TI              ; NOT .AND.: PUT IT BACK
        rts
@and:   jsr NEEDL
        jsr PUSHV
        jsr NOTX
        jsr NEEDL
        jsr POPLR
        lda FA
        and FB
        sta FA
        bra @l
@r:     rts

NOTX:   ldy TI
        phy
        jsr DOTWORD
        ply
        bcs @rel
        cmp #3
        beq @not
        sty TI
@rel:   jmp RELX
@not:   jsr NOTX
        jsr NEEDL
        lda FA
        eor #1
        sta FA
        rts

NEEDL:  lda VT
        cmp #'L'
        bne @t
        rts
@t:     jmp ETYPE
NEEDN:  lda VT
        cmp #'N'
        bne @t
        rts
@t:     jmp ETYPE
NEEDC:  lda VT
        cmp #'C'
        bne @t
        rts
@t:     jmp ETYPE

; ---- COMPARISONS ----------------------------------------------------
RELX:   jsr ADDX
        jsr PEEK
        ldx #0              ; BITS: 1 <, 2 =, 4 >, 8 = $
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
@3:     cmp #'#'
        bne @4
        ldx #5
        jsr NEXT
        bra @go
@4:     cmp #'$'
        bne @5
        ldx #8
        jsr NEXT
        bra @go
@5:     cmp #'>'
        bne @r
        ldx #4
        jsr NEXT
        jsr PEEK
        cmp #'='
        bne @go
        ldx #6
        jsr NEXT
@go:    phx
        jsr PUSHV
        jsr ADDX
        jsr POPLR
        pla
        sta BT2             ; OPERATOR
        lda VT
        cmp BT3
        bne @te             ; BOTH SIDES THE SAME TYPE
        lda BT2
        cmp #8
        beq @cont
        lda VT
        cmp #'N'
        beq @num
        cmp #'L'
        beq @log
        jsr SCMP            ; TEXT / DATES
        bra @res
@num:   jsr FCMP
        bra @res
@log:   lda FA
        cmp FB
        beq @eq
        lda #1
        bra @res
@eq:    lda #0
@res:   tax                 ; $FF / 0 / 1 -> BIT 1 / 2 / 4
        lda #1
        cpx #$FF
        beq @b
        lda #2
        cpx #0
        beq @b
        lda #4
@b:     and BT2
        beq @f
        lda #1
@f:     sta FA
        lda #'L'
        sta VT
@r:     rts
@te:    jmp ETYPE
@cont:  lda VT              ; A $ B: IS A INSIDE B?
        cmp #'C'
        bne @te
        jsr CONTAINS
        bra @f

; COMPARE TEXT FA WITH TEXT FB, dBASE STYLE: OVER THE LENGTH OF THE
; RIGHT ONE (SO NAME = "SM" MATCHES "SMITH").  A = $FF / 0 / 1
SCMP:   jsr STRPTRS
        ldy #0
@l:     cpy SL2
        beq @eq
        lda #' '
        cpy SL1
        bcs @p
        lda (SP1),y
@p:     cmp (SP2),y
        bne @ne
        iny
        bra @l
@eq:    lda #0
        rts
@ne:    bcc @lt
        lda #1
        rts
@lt:    lda #$FF
        rts
STRPTRS: lda FA             ; SP1/SL1 = LEFT (FA), SP2/SL2 = RIGHT (FB)
        sta SP1
        lda FA+1
        sta SP1+1
        lda FA+2
        sta SL1
        lda FB
        sta SP2
        lda FB+1
        sta SP2+1
        lda FB+2
        sta SL2
        rts

; A = 1 IF TEXT FA (TRAILING SPACES IGNORED) IS FOUND IN TEXT FB
CONTAINS:
        jsr STRPTRS
@t:     ldy SL1             ; TRIM THE LEFT ONE
        beq @yes
        dey
        lda (SP1),y
        cmp #' '
        bne @go
        dec SL1
        bra @t
@go:    lda SL2             ; TRY EACH START POSITION IN THE RIGHT
        sec
        sbc SL1
        bcc @no
        sta BT1             ; LAST START
        stz BT2
@s:     ldy #0
@c:     cpy SL1
        beq @yes
        phy
        tya
        clc
        adc BT2
        tay
        lda (SP2),y
        ply
        cmp (SP1),y
        bne @nx
        iny
        bra @c
@nx:    lda BT2
        cmp BT1
        beq @no
        inc BT2
        bra @s
@yes:   lda #1
        rts
@no:    lda #0
        rts

; ---- + AND - (TEXT + TEXT JOINS THEM) --------------------------------
ADDX:   jsr MULX
@l:     jsr PEEK
        cmp #'+'
        beq @p
        cmp #'-'
        beq @m
        rts
@p:     jsr NEXT
        jsr PUSHV
        jsr MULX
        jsr POPLR
        lda VT
        cmp BT3
        bne @te
        cmp #'C'
        beq @cat
        cmp #'N'
        bne @te
        jsr FADD
        bra @l
@m:     jsr NEXT
        jsr PUSHV
        jsr MULX
        jsr POPLR
        lda VT
        cmp #'N'
        bne @te
        cmp BT3
        bne @te
        jsr FSUB
        bra @l
@te:    jmp ETYPE
@cat:   clc                 ; JOIN TWO TEXTS
        lda FA+2
        adc FB+2
        bcs @long
        pha
        jsr STRPTRS
        pla
        pha
        jsr SALLOC
        ldy #0
@c1:    cpy SL1
        beq @c2
        lda (SP1),y
        sta (SP2),y
        iny
        bra @c1
@c2:    lda SP2             ; SECOND PART AFTER THE FIRST
        clc
        adc SL1
        sta GP2
        lda SP2+1
        adc #0
        sta GP2+1
        lda FB
        sta SP1
        lda FB+1
        sta SP1+1
        ldy #0
@c3:    cpy SL2
        beq @c4
        lda (SP1),y
        sta (GP2),y
        iny
        bra @c3
@c4:    pla
        jsr SETSTR
        jmp @l
@long:  lda #<M_STR
        ldy #>M_STR
        jmp ERRMSG

; ---- * AND / --------------------------------------------------------
MULX:   jsr UNX
@l:     jsr PEEK
        cmp #'*'
        beq @t
        cmp #'/'
        beq @d
        rts
@t:     jsr NEXT
        jsr @two
        jsr FMUL
        bra @l
@d:     jsr NEXT
        jsr @two
        jsr FDIV
        bra @l
@two:   jsr NEEDN
        jsr PUSHV
        jsr UNX
        jsr NEEDN
        jmp POPLR

UNX:    jsr PEEK
        cmp #'-'
        bne @1
        jsr NEXT
        jsr UNX
        jsr NEEDN
        jmp FNEG
@1:     cmp #'+'
        bne @2
        jsr NEXT
        jmp UNX
@2:     jmp PRIM

; ---- PRIMARY --------------------------------------------------------
PRIM:   jsr PEEK
        bne @0
        jmp ESYNTAX
@0:     cmp #'('
        bne @1
        jsr NEXT
        jsr EVALX
        lda #')'
        jmp EXPECT
@1:     cmp #'"'
        beq @str
        cmp #$27            ; '
        beq @str
        cmp #'.'
        bne @2
        ldy TI              ; .T. .F. OR A NUMBER LIKE .5
        iny
        lda (TP),y
        cmp #'0'
        bcc @dw
        cmp #'9'+1
        bcc @num
@dw:    jsr DOTWORD
        bcs @syn
        cmp #4
        bcc @syn
        ldx #1              ; .T. / .Y.
        cmp #4
        beq @lg
        cmp #6
        beq @lg
        ldx #0
@lg:    stx FA
        lda #'L'
        sta VT
        rts
@2:     cmp #'0'
        bcc @nm
        cmp #'9'+1
        bcs @nm
@num:   ldy TI
        jsr FPARSE
        bcs @syn
        sty TI
        lda #'N'
        sta VT
        rts
@nm:    jsr GETNAME
        bcs @syn
        jsr PEEK
        cmp #'('
        bne @fld
        jsr NEXT
        jmp FUNC
@fld:   jsr FINDFLD
        bcs @novar
        jmp FLDVAL
@syn:   jmp ESYNTAX
@novar: jmp NOVAR
@str:   sta BT1             ; QUOTED TEXT: POINT AT IT IN PLACE
        ldy TI
        iny
        sty BT2
@q:     lda (TP),y
        beq @syn
        cmp BT1
        beq @qe
        iny
        bra @q
@qe:    iny
        sty TI
        tya
        sec
        sbc BT2
        dec a               ; LENGTH
        sta FA+2
        clc
        lda TP
        adc BT2
        sta FA
        lda TP+1
        adc #0
        sta FA+1
        lda #'C'
        sta VT
        rts

NOVAR:  lda #<M_NOVAR
        sta EMSG
        lda #>M_NOVAR
        sta EMSG+1
        lda #<NAMEB         ; MESSAGE + THE NAME
        sta EMSG2
        lda #>NAMEB
        sta EMSG2+1
        jmp ERRJMP2

; ---- THE VALUE OF FIELD FP IN RECBUF -----------------------------------
FLDVAL: jsr FLDADDR         ; GP = FIELD, A = WIDTH
        sta BT1
        ldy #F_TYPE
        lda (FP),y
        cmp #'N'
        beq @n
        cmp #'L'
        beq @l
        sta VT              ; C OR D: POINT AT IT
        lda GP
        sta FA
        lda GP+1
        sta FA+1
        lda BT1
        sta FA+2
        rts
@l:     lda (GP)
        jsr UPPER
        ldx #1
        cmp #'T'
        beq @lv
        cmp #'Y'
        beq @lv
        ldx #0
@lv:    stx FA
        lda #'L'
        sta VT
        rts
@n:     lda BT1
        jsr NUMTEXT         ; (GP), A CHARACTERS -> FA
        lda #'N'
        sta VT
        rts

; TEXT AT (GP), A CHARACTERS -> NUMBER IN FA (SPACES AROUND IT AND A
; SIGN ALLOWED; BLANK = 0).  C=1 IF IT IS NOT A NUMBER.
NUMTEXT:
        sta BT1
        ldy #0
        ldx #0
@c:     cpy BT1
        beq @e
        cpx #38
        bcs @e
        lda (GP),y
        cmp #' '
        beq @s
        sta NBUF,x
        inx
@s:     iny
        bra @c
@e:     stz NBUF,x
        lda TP              ; READ IT WITH FPARSE
        pha
        lda TP+1
        pha
        lda #<NBUF
        sta TP
        lda #>NBUF
        sta TP+1
        stz NSIGN           ; SIGN
        ldy #0
        lda NBUF
        beq @zero
        cmp #'-'
        bne @p
        inc NSIGN
        iny
@p:     phy
        jsr FPARSE
        pla
        bcs @bad
        lda (TP),y          ; NOTHING MAY FOLLOW
        bne @bad
        lda NSIGN
        beq @ok
        jsr FNEG
@ok:    pla
        sta TP+1
        pla
        sta TP
        clc
        rts
@zero:  jsr FZERO
        bra @ok
@bad:   jsr FZERO
        pla
        sta TP+1
        pla
        sta TP
        sec
        rts

;=====================================================================
; FUNCTIONS.  NAMEB HOLDS THE NAME; THE ( HAS BEEN READ.
;=====================================================================
FUNC:   ldx #0
@f:     lda FNTAB,x
        bne @1
        jmp ESYNTAX
@1:     ldy #0
@c:     lda FNTAB,x
        cmp NAMEB,y
        bne @skip
        cmp #0
        beq @hit
        inx
        iny
        bra @c
@skip:  lda FNTAB,x
        beq @s2
        inx
        bra @skip
@s2:    inx
        inx
        inx
        bra @f
@hit:   lda FNTAB+2,x
        pha
        lda FNTAB+1,x
        pha
        rts

FNTAB:  .byte "UPPER",0
        .word FN_UPPER-1
        .byte "LOWER",0
        .word FN_LOWER-1
        .byte "TRIM",0
        .word FN_TRIM-1
        .byte "LEN",0
        .word FN_LEN-1
        .byte "SUBSTR",0
        .word FN_SUBSTR-1
        .byte "VAL",0
        .word FN_VAL-1
        .byte "STR",0
        .word FN_STR-1
        .byte "INT",0
        .word FN_INT-1
        .byte "ABS",0
        .word FN_ABS-1
        .byte "ROUND",0
        .word FN_ROUND-1
        .byte "RECNO",0
        .word FN_RECNO-1
        .byte "DELETED",0
        .word FN_DEL-1
        .byte "CTOD",0
        .word FN_CTOD-1
        .byte "DTOC",0
        .word FN_DTOC-1
        .byte "IIF",0
        .word FN_IIF-1
        .byte "SPACE",0
        .word FN_SPACE-1
        .byte 0

; ONE ARGUMENT OF ANY TYPE, THEN )
ARG1:   jsr EVALX
CLOSEP: lda #')'
        jmp EXPECT
COMMA:  lda #','
        jmp EXPECT

; COPY TEXT FA INTO NEW STRING SPACE (SP2), THEN FA POINTS THERE
SCOPY:  lda FA
        sta SP1
        lda FA+1
        sta SP1+1
        lda FA+2
        pha
        jsr SALLOC
        pla
        sta SL1
        ldy #0
@l:     cpy SL1
        beq @e
        lda (SP1),y
        sta (SP2),y
        iny
        bra @l
@e:     lda SL1
        jmp SETSTR

FN_UPPER: jsr ARG1
        jsr NEEDC
        jsr SCOPY
        ldy #0
@l:     cpy FA+2
        beq @r
        lda (SP2),y
        jsr UPPER
        sta (SP2),y
        iny
        bra @l
@r:     rts
FN_LOWER: jsr ARG1
        jsr NEEDC
        jsr SCOPY
        ldy #0
@l:     cpy FA+2
        beq @r
        lda (SP2),y
        cmp #'A'
        bcc @n
        cmp #'Z'+1
        bcs @n
        ora #$20
        sta (SP2),y
@n:     iny
        bra @l
@r:     rts
FN_TRIM: jsr ARG1           ; DROP TRAILING SPACES
        jsr NEEDC
TRIMFA: lda FA
        sta SP1
        lda FA+1
        sta SP1+1
@l:     ldy FA+2
        beq @r
        dey
        lda (SP1),y
        cmp #' '
        bne @r
        dec FA+2
        bra @l
@r:     rts
FN_LEN: jsr ARG1
        jsr NEEDC
        lda FA+2
NUMA:   sta T16             ; FA = A AS A NUMBER
        stz T16+1
        jsr FINT16
        lda #'N'
        sta VT
        rts
FN_SUBSTR:                  ; SUBSTR(TEXT, START [, LENGTH])
        jsr EVALX
        jsr NEEDC
        jsr PUSHV
        jsr COMMA
        jsr EVALX
        jsr NEEDN
        jsr TOBYTE
        sta BT3             ; START (1-BASED)
        lda #255
        sta BT4             ; LENGTH (ALL)
        jsr PEEK
        cmp #','
        bne @e
        jsr NEXT
        lda BT3
        pha
        jsr EVALX
        jsr NEEDN
        jsr TOBYTE
        sta BT4
        pla
        sta BT3
@e:     jsr CLOSEP
        lda BT3
        pha
        lda BT4
        pha
        jsr POPB            ; THE TEXT
        pla
        sta BT4
        pla
        sta BT3
        ldx BT3             ; START 0 -> 1
        bne @s
        inx
@s:     dex                 ; 0-BASED
        cpx FB+2
        bcc @in
        ldx FB+2            ; PAST THE END: EMPTY
@in:    stx BT3
        clc
        txa
        adc FB
        sta FA
        lda FB+1
        adc #0
        sta FA+1
        sec
        lda FB+2
        sbc BT3             ; WHAT IS LEFT
        cmp BT4
        bcc @l
        lda BT4
@l:     sta FA+2
        lda #'C'
        sta VT
        rts
FN_VAL: jsr ARG1
        jsr NEEDC
        lda FA
        sta GP
        lda FA+1
        sta GP+1
        lda FA+2
        jsr NUMTEXT
        lda #'N'
        sta VT
        rts
FN_STR:                     ; STR(N [, WIDTH [, DECIMALS]])
        jsr EVALX
        jsr NEEDN
        jsr PUSHV
        lda #10
        sta BT3             ; WIDTH
        stz STRDEC          ; DECIMALS
        jsr PEEK
        cmp #','
        bne @e
        jsr NEXT
        jsr EVALX
        jsr NEEDN
        jsr TOBYTE
        pha
        jsr PEEK
        cmp #','
        bne @w
        jsr NEXT
        jsr EVALX
        jsr NEEDN
        jsr TOBYTE
        sta STRDEC
@w:     pla
        sta BT3
@e:     jsr CLOSEP
        lda BT3
        pha
        jsr POPB
        jsr FBA
        lda STRDEC
        jsr FIXSTR
        pla
        sta BT3
        jmp OTOSTR          ; OBUF RIGHT-ALIGNED IN BT3 -> TEXT VALUE
FN_INT: jsr ARG1
        jsr NEEDN
        jmp FINT
FN_ABS: jsr ARG1
        jsr NEEDN
        jmp FABS
FN_ROUND:                   ; ROUND(N, DECIMALS)
        jsr EVALX
        jsr NEEDN
        jsr PUSHV
        jsr COMMA
        jsr EVALX
        jsr NEEDN
        jsr TOBYTE
        pha
        jsr CLOSEP
        jsr POPB
        jsr FBA
        pla
        jsr FIXSTR          ; ROUND BY PRINTING AND READING BACK
        lda #<OBUF
        sta GP
        lda #>OBUF
        sta GP+1
        lda OLEN
        jsr NUMTEXT
        lda #'N'
        sta VT
        rts
FN_RECNO: jsr CLOSEP
        lda RECNO
        sta T16
        lda RECNO+1
        sta T16+1
        jsr FINT16
        lda #'N'
        sta VT
        rts
FN_DEL: jsr CLOSEP
        ldx #0
        lda RECBUF
        cmp #'*'
        bne @n
        inx
@n:     stx FA
        lda #'L'
        sta VT
        rts
FN_IIF: jsr EVALX           ; IIF(TEST, A, B)
        jsr NEEDL
        jsr PUSHV
        jsr COMMA
        jsr EVALX
        jsr PUSHV
        jsr COMMA
        jsr EVALX
        jsr CLOSEP
        sec                 ; TEST IS 18 BELOW THE TOP
        lda VSP
        sbc #18
        tax
        lda VSTK+1,x
        bne @t
        jsr POPB            ; FALSE: KEEP B (IN FA)
        jmp POPB
@t:     jsr POPB            ; TRUE: A
        jsr FBA
        lda BT4
        sta VT
        jmp POPB
FN_SPACE: jsr ARG1
        jsr NEEDN
        jsr TOBYTE
        pha
        jsr SALLOC
        pla
        pha
        tay
        lda #' '
@l:     dey
        cpy #$FF
        beq @e
        sta (SP2),y
        bra @l
@e:     pla
        jmp SETSTR

; CTOD("DD/MM/YYYY") -> DATE YYYYMMDD (BLANK IF IT IS NOT A DATE)
FN_CTOD: jsr ARG1
        jsr NEEDC
        lda FA
        sta GP
        lda FA+1
        sta GP+1
        lda FA+2
        jsr TEXTDATE
        lda #8
        jsr SALLOC
        ldy #7
@c:     lda DATEB,y
        sta (SP2),y
        dey
        bpl @c
        lda #8
        jsr SETSTR
        lda #'D'
        sta VT
        rts
; DTOC(DATE) -> "DD/MM/YYYY"
FN_DTOC: jsr ARG1
        lda VT
        cmp #'D'
        beq @ok
        jmp ETYPE
@ok:    lda FA
        sta GP
        lda FA+1
        sta GP+1
        jsr DATETEXT        ; -> DSPBUF (10)
        lda #10
        jsr SALLOC
        ldy #9
@c:     lda DSPBUF,y
        sta (SP2),y
        dey
        bpl @c
        lda #10
        jmp SETSTR

; WHOLE NUMBER FA (0-255) -> A
TOBYTE: lda FA_M
        beq @z
        lda FA_S
        bmi @z
        lda FA_E
        bmi @z
        beq @z
        cmp #4
        bcs @big
        jsr FINT
        lda #0              ; DIGIT BY DIGIT
        sta BT1
        ldx #0
@l:     cpx FA_E
        beq @r
        lda BT1             ; *10
        cmp #26
        bcs @big
        asl a
        asl a
        adc BT1
        asl a
        sta BT1
        txa
        lsr a
        tay
        lda FA_M,y
        bcs @lo
        lsr a
        lsr a
        lsr a
        lsr a
@lo:    and #$0F
        clc
        adc BT1
        bcs @big
        sta BT1
        inx
        bra @l
@r:     lda BT1
        rts
@z:     lda #0
        rts
@big:   lda #255
        rts

; OBUF/OLEN RIGHT-ALIGNED IN BT3 CHARACTERS -> NEW TEXT VALUE
; (TOO LONG = ALL *)
OTOSTR: lda BT3
        jsr SALLOC
        ldy #0
        lda #' '
@f:     cpy BT3
        beq @1
        sta (SP2),y
        iny
        bra @f
@1:     lda OLEN
        cmp BT3
        beq @ok
        bcc @ok
        ldy #0
        lda #'*'
@s:     cpy BT3
        beq @d
        sta (SP2),y
        iny
        bra @s
@ok:    sec
        lda BT3
        sbc OLEN
        tay
        ldx #0
@c:     cpx OLEN
        beq @d
        lda OBUF,x
        sta (SP2),y
        inx
        iny
        bra @c
@d:     lda BT3
        jmp SETSTR

;=====================================================================
; DATES.  STORED AS YYYYMMDD, SHOWN AND TYPED AS DD/MM/YYYY
;=====================================================================
; TEXT AT (GP), A CHARACTERS -> DATEB.  C=0 GOOD DATE.
; C=1 NOT A DATE (DATEB = 8 SPACES).  A BLANK TEXT GIVES A BLANK DATE
; WITH C=0.
TEXTDATE:
        sta BT1
        ldx #7
        lda #' '
@b:     sta DATEB,x
        dex
        bpl @b
        ldy #0              ; ALL BLANK?
@sp:    cpy BT1
        beq @blank
        lda (GP),y
        cmp #' '
        bne @go
        iny
        bra @sp
@blank: clc
        rts
@go:    lda BT1
        cmp #10
        bcc @bad
        ldy #2
        lda (GP),y
        cmp #'/'
        bne @bad
        ldy #5
        lda (GP),y
        cmp #'/'
        bne @bad
        ldx #0              ; DD/MM/YYYY -> YYYYMMDD
@m:     ldy DMAP,x
        lda (GP),y
        cmp #'0'
        bcc @bad
        cmp #'9'+1
        bcs @bad
        sta DATEB,x
        inx
        cpx #8
        bne @m
        jsr DMONTH          ; CHECK THE MONTH AND DAY
        bcs @bad
        rts
@bad:   ldx #7
        lda #' '
@b2:    sta DATEB,x
        dex
        bpl @b2
        sec
        rts
DMAP:   .byte 6,7,8,9,3,4,0,1

; DATEB: MONTH 1-12, DAY 1..DAYS IN THE MONTH.  C=1 IF NOT
DMONTH: lda DATEB+4         ; MONTH
        and #$0F
        tax
        lda DATEB+5
        and #$0F
        cpx #1
        bcc @m1
        clc
        adc #10
        cpx #2
        bcs @no
@m1:    beq @no             ; MONTH 0
        cmp #13
        bcs @no
        tax                 ; X = MONTH
        lda DATEB+6         ; DAY
        and #$0F
        tay
        lda #0
@d:     cpy #0
        beq @d2
        clc
        adc #10
        dey
        bra @d
@d2:    sta BT1
        lda DATEB+7
        and #$0F
        clc
        adc BT1
        beq @no
        sta BT1
        lda MDAYS-1,x
        cpx #2              ; FEBRUARY IN A LEAP YEAR
        bne @c
        jsr LEAP
        bcc @c
        lda #29
@c:     cmp BT1
        bcc @no
        clc
        rts
@no:    sec
        rts
MDAYS:  .byte 31,28,31,30,31,30,31,31,30,31,30,31
; C=1 IF THE YEAR IN DATEB IS A LEAP YEAR (DIVISIBLE BY 4, AND NOT BY
; 100 UNLESS BY 400)
LEAP:   lda DATEB+2         ; LAST TWO DIGITS
        and #$0F
        asl a
        sta BT2
        asl a
        asl a
        adc BT2             ; TENS*10
        sta BT2
        lda DATEB+3
        and #$0F
        clc
        adc BT2
        sta BT2             ; YY
        bne @yy
        lda DATEB           ; YY = 00: LOOK AT THE CENTURY
        and #$0F
        asl a
        sta BT2
        asl a
        asl a
        adc BT2
        sta BT2
        lda DATEB+1
        and #$0F
        adc BT2
@yy:    and #3
        bne @n
        sec
        rts
@n:     clc
        rts

; DATE (YYYYMMDD) AT (GP) -> DSPBUF "DD/MM/YYYY" (BLANK STAYS BLANK)
DATETEXT:
        ldx #0
@l:     ldy DMAP2,x
        bmi @sl
        lda (GP),y
        bra @p
@sl:    lda #'/'
        ldy #0
        pha
        lda (GP),y
        cmp #' '
        bne @sl2
        pla
        lda #' '
        bra @p
@sl2:   pla
@p:     sta DSPBUF,x
        inx
        cpx #10
        bne @l
        lda #10
        sta DSPLEN
        rts
DMAP2:  .byte 6,7,$FF,4,5,$FF,0,1,2,3

        .bss
DATEB:  .res 8
        .code

;=====================================================================
; A VALUE AS TEXT, INTO DSPBUF/DSPLEN
;=====================================================================
VALTEXT: lda VT
        cmp #'N'
        beq @n
        cmp #'L'
        beq @l
        cmp #'D'
        beq @d
        ldy #0              ; TEXT
@c:     cpy FA+2
        beq @ce
        lda FA
        sta GP
        lda FA+1
        sta GP+1
        lda (GP),y
        sta DSPBUF,y
        iny
        bra @c
@ce:    sty DSPLEN
        rts
@d:     lda FA
        sta GP
        lda FA+1
        sta GP+1
        jmp DATETEXT
@l:     ldx #0
        lda FA
        beq @lf
        ldx #4
@lf:    ldy #0
@lc:    lda LTXT,x
        sta DSPBUF,y
        inx
        iny
        cpy #3
        bne @lc
        sty DSPLEN
        rts
@n:     lda #16
        jsr GENSTR
        ldx #0
@nc:    cpx OLEN
        beq @ne
        lda OBUF,x
        sta DSPBUF,x
        inx
        bra @nc
@ne:    stx DSPLEN
        rts
LTXT:   .byte ".F. .T. "

; PRINT DSPBUF
PRDSP:  ldx #0
@l:     cpx DSPLEN
        beq @r
        lda DSPBUF,x
        jsr OUTC
        inx
        bra @l
@r:     rts

;=====================================================================
; STORE THE VALUE VT/FA INTO FIELD FP OF RECBUF (TYPES MUST MATCH)
;=====================================================================
STOREFLD:
        jsr FLDADDR         ; GP, A = WIDTH
        sta SL1
        ldy #F_TYPE
        lda (FP),y
        cmp VT
        beq @ok
        jmp ETYPE
@ok:    cmp #'N'
        beq @n
        cmp #'L'
        beq @l
        lda FA              ; C / D: COPY, PAD WITH SPACES
        sta SP1
        lda FA+1
        sta SP1+1
        ldy #0
@c:     cpy SL1
        beq @r
        lda #' '
        cpy FA+2
        bcs @p
        lda (SP1),y
@p:     sta (GP),y
        iny
        bra @c
@r:     rts
@l:     lda #'F'
        ldx FA
        beq @lf
        lda #'T'
@lf:    sta (GP)
        rts
@n:     ldy #F_DEC          ; NUMBER: AS TEXT, RIGHT-ALIGNED
        lda (FP),y
        jsr FIXSTR
        lda GP
        sta GP2
        lda GP+1
        sta GP2+1
        ldy #0              ; SPACES
        lda #' '
@f:     cpy SL1
        beq @1
        sta (GP2),y
        iny
        bra @f
@1:     lda OLEN
        cmp SL1
        beq @in
        bcc @in
        ldy #0              ; TOO WIDE: STARS
        lda #'*'
@s:     cpy SL1
        beq @r2
        sta (GP2),y
        iny
        bra @s
@in:    sec
        lda SL1
        sbc OLEN
        tay
        ldx #0
@cp:    cpx OLEN
        beq @r2
        lda OBUF,x
        sta (GP2),y
        inx
        iny
        bra @cp
@r2:    rts
